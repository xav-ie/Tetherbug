package ie.xav.tetherlink

import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.animation.AnimatedVisibility
import android.provider.Settings
import android.content.Context
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothClass
import android.annotation.SuppressLint
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.LargeFlexibleTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import rikka.shizuku.Shizuku

/** Setup screen: a checklist to get the service running, the Personal Hotspot toggle, and live status. */
class MainActivity : ComponentActivity() {
    // Bumped whenever something outside Compose (permissions, Shizuku) may have changed.
    private var tick by mutableIntStateOf(0)
    private val shizukuChanged = Shizuku.OnRequestPermissionResultListener { _, _ -> tick++ }
    private val shizukuBinder = Shizuku.OnBinderReceivedListener { tick++ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // The platform theme's action bar would sit above the Compose top app bar.
        actionBar?.hide()
        Shizuku.addRequestPermissionResultListener(shizukuChanged)
        Shizuku.addBinderReceivedListenerSticky(shizukuBinder)
        setContent { Theme { SetupScreen(tick) { tick++ } } }
    }

    override fun onResume() {
        super.onResume()
        tick++
    }

    override fun onDestroy() {
        Shizuku.removeRequestPermissionResultListener(shizukuChanged)
        Shizuku.removeBinderReceivedListener(shizukuBinder)
        super.onDestroy()
    }
}

private val PERMISSIONS =
    arrayOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.POST_NOTIFICATIONS)

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun Theme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    MaterialExpressiveTheme(
        colorScheme = if (isSystemInDarkTheme()) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context),
        motionScheme = MotionScheme.expressive(),
        content = content,
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun SetupScreen(tick: Int, refresh: () -> Unit) {
    val context = LocalContext.current
    val state by TetherState.snapshot.collectAsState()
    val requestPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { refresh() }

    // Recomputed on every tick so the checklist follows changes made in other apps.
    val permissionsGranted = tick >= 0 && PERMISSIONS.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    val shizukuRunning = Shizuku.pingBinder()
    val shizukuReady = Privileged.isReady()
    val appleIe = shizukuReady && runCatching { Privileged.hasAppleIe() }.getOrDefault(false)
    val pairedMacs = if (permissionsGranted) pairedComputers(context) else emptyList()

    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeFlexibleTopAppBar(
                title = { Text("tether-link") },
                subtitle = { Text("Instant Hotspot for your Mac") },
                scrollBehavior = scroll,
            )
        },
    ) { padding ->
        LazyColumn(
            contentPadding =
                PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    "When your Mac has no Wi-Fi, it asks this phone over Bluetooth to turn on its hotspot, then joins it. " +
                        "Only a Mac paired with this phone can send that request.",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
            }
            item { SectionTitle("Setup") }
            item {
                Step(
                    number = 1,
                    done = permissionsGranted,
                    title = "Bluetooth & notifications",
                    body = "Lets the app advertise itself to your Mac, accept its connection, and show the always-on service notification.",
                    action = ("Allow" to { requestPermissions.launch(PERMISSIONS) }).takeUnless { permissionsGranted },
                )
            }
            item {
                Step(
                    number = 2,
                    done = shizukuReady,
                    title = "Shizuku",
                    body =
                        if (shizukuRunning) {
                            "Turning the hotspot on needs system rights. Shizuku grants them without root."
                        } else {
                            "Shizuku isn't running. Start it in the Shizuku app (it stops after every reboot), then come back."
                        },
                    action = ("Allow" to { Shizuku.requestPermission(0) }).takeIf { shizukuRunning && !shizukuReady },
                )
            }
            item {
                Step(
                    number = 3,
                    done = state.running,
                    title = "Background service",
                    body =
                        when {
                            !state.running -> "Keeps the Bluetooth link open so your Mac can reach the phone at any time."
                            state.advertising -> "Running and visible to your Mac."
                            else -> "Running, waiting for Bluetooth advertising to start…"
                        },
                    action =
                        if (state.running) {
                            "Stop" to { context.stopService(Intent(context, TetherService::class.java)); Unit }
                        } else {
                            ("Start" to { context.startForegroundService(Intent(context, TetherService::class.java)); Unit })
                                .takeIf { permissionsGranted }
                        },
                )
            }
            item {
                Step(
                    number = 4,
                    done = pairedMacs.isNotEmpty(),
                    title = "Pair your Mac",
                    body =
                        when {
                            pairedMacs.isEmpty() -> "Pair this phone with your Mac once. Tap for step-by-step instructions."
                            state.connectedMacs > 0 -> "Paired with ${pairedMacs.joinToString()} and connected now."
                            else -> "Paired with ${pairedMacs.joinToString()}. Your Mac connects when its tether-link helper runs."
                        },
                    details =
                        "1. On your Mac, open System Settings → Bluetooth and leave it open, so the Mac stays discoverable.\n" +
                            "2. On this phone, open Bluetooth settings → Pair new device, and pick your Mac.\n" +
                            "3. Check that both screens show the same code, and confirm on both within 30 seconds. " +
                            "If it times out, Android forgets the Mac, so just pair again.\n" +
                            "4. Install the tether-link helper on your Mac (from the dots/tether-link flake). " +
                            "Pairing also gives it the keys for the encrypted Bluetooth LE link, so there's no second prompt.",
                    action =
                        ("Bluetooth settings" to { context.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) })
                            .takeIf { pairedMacs.isEmpty() },
                )
            }
            item { SectionTitle("Hotspot") }
            item {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    ListItem(
                        headlineContent = { Text("Look like an iPhone hotspot") },
                        supportingContent = {
                            Text(
                                "Adds Apple's Personal Hotspot marker to the Wi-Fi signal, so macOS shows the link icon, " +
                                    "treats the connection as metered, and leaves it when a regular network is around. " +
                                    "Takes effect the next time the hotspot starts.",
                            )
                        },
                        trailingContent = {
                            Switch(
                                checked = appleIe,
                                enabled = shizukuReady,
                                onCheckedChange = {
                                    runCatching { Privileged.setAppleIe(it) }
                                    refresh()
                                },
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
                    )
                }
            }
            item {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    ListItem(
                        headlineContent = { Text("Hotspot is ${hotspotLabel(state.hotspot)}") },
                        supportingContent = {
                            Text(
                                when (state.connectedMacs) {
                                    0 -> "No Mac connected"
                                    1 -> "1 Mac connected"
                                    else -> "${state.connectedMacs} Macs connected"
                                },
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
                    )
                }
            }
        }
    }
}

private fun hotspotLabel(state: Byte) =
    when (state.toInt()) {
        1 -> "starting"
        2 -> "on"
        3 -> "failed"
        else -> "off"
    }

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 4.dp, top = 8.dp),
    )
}

/** Names of bonded devices whose Bluetooth class is a computer (the Macs this phone is paired with). */
@SuppressLint("MissingPermission") // Only called once BLUETOOTH_CONNECT is granted.
private fun pairedComputers(context: Context): List<String> =
    context.getSystemService(BluetoothManager::class.java).adapter?.bondedDevices.orEmpty()
        .filter { it.bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.COMPUTER }
        .map { it.name ?: it.address }

@Composable
private fun Step(
    number: Int,
    done: Boolean,
    title: String,
    body: String,
    action: Pair<String, () -> Unit>?,
    details: String? = null,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Card(
        onClick = { expanded = !expanded },
        enabled = details != null,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceContainer,
            disabledContentColor = MaterialTheme.colorScheme.onSurface,
        ),
    ) {
        ListItem(
            leadingContent = {
                Surface(
                    shape = CircleShape,
                    color = if (done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest,
                    contentColor = if (done) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(36.dp),
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Text(if (done) "✓" else number.toString(), style = MaterialTheme.typography.titleMedium)
                    }
                }
            },
            headlineContent = { Text(title) },
            supportingContent = { Text(body) },
            trailingContent = action?.let { (label, onClick) -> { FilledTonalButton(onClick = onClick) { Text(label) } } },
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        )
        AnimatedVisibility(visible = expanded && details != null) {
            Text(
                details.orEmpty(),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 68.dp, end = 16.dp, bottom = 16.dp),
            )
        }
    }
}
