package ie.xav.tetherlink

import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.foundation.clickable
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.runtime.remember
import androidx.compose.runtime.derivedStateOf
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.fadeOut
import androidx.compose.animation.fadeIn
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.Image
import androidx.compose.ui.res.painterResource
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
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
        AppIcon.applyFirstLaunchDefault(this)
        // The platform theme's action bar would sit above the Compose top app bar.
        actionBar?.hide()
        Shizuku.addRequestPermissionResultListener(shizukuChanged)
        Shizuku.addBinderReceivedListenerSticky(shizukuBinder)
        setContent { Theme(remember(tick) { AppTheme.get(this) }) { SetupScreen(tick) { tick++ } } }
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

private object Links {
    const val REPO = "https://github.com/xav-ie/tether-link"
    const val MAC_SETUP = "$REPO/blob/main/docs/macos.md"
    const val RELEASES = "$REPO/releases"
}

internal val PERMISSIONS =
    arrayOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.POST_NOTIFICATIONS)

/** App colours: the wallpaper's (Material You) or xav.ie's purple palette. */
enum class ThemeStyle { SYSTEM, PURPLE }

object AppTheme {
    private const val KEY = "theme_style"

    fun get(context: Context) =
        context.getSharedPreferences("tether-link", Context.MODE_PRIVATE).getString(KEY, null)
            ?.let { runCatching { ThemeStyle.valueOf(it) }.getOrNull() } ?: ThemeStyle.SYSTEM

    fun set(context: Context, style: ThemeStyle) =
        context.getSharedPreferences("tether-link", Context.MODE_PRIVATE).edit().putString(KEY, style.name).apply()
}

// xav.ie's palette (src/styles/global.css): dark #12081a/#fff17b, light #bebdb6/#281336.
private val PurpleDark =
    darkColorScheme(
        primary = Color(0xFFFFF17B), onPrimary = Color(0xFF281336),
        primaryContainer = Color(0xFF3A1E4E), onPrimaryContainer = Color(0xFFFFF17B),
        background = Color(0xFF12081A), onBackground = Color(0xFFFFF7C2),
        surface = Color(0xFF12081A), onSurface = Color(0xFFFFF7C2), onSurfaceVariant = Color(0xFFC9B8D6),
        surfaceContainer = Color(0xFF281336), surfaceContainerHighest = Color(0xFF3A1E4E),
        secondaryContainer = Color(0xFF3A1E4E), onSecondaryContainer = Color(0xFFFFF17B),
    )
private val PurpleLight =
    lightColorScheme(
        primary = Color(0xFF281336), onPrimary = Color(0xFFFFF17B),
        primaryContainer = Color(0xFFD9CFE3), onPrimaryContainer = Color(0xFF281336),
        background = Color(0xFFBEBDB6), onBackground = Color(0xFF281336),
        surface = Color(0xFFBEBDB6), onSurface = Color(0xFF281336), onSurfaceVariant = Color(0xFF4D3A5C),
        surfaceContainer = Color(0xFFD3D2CC), surfaceContainerHighest = Color(0xFFE2E1DC),
        secondaryContainer = Color(0xFFD9CFE3), onSecondaryContainer = Color(0xFF281336),
    )

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun Theme(style: ThemeStyle, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val dark = isSystemInDarkTheme()
    MaterialExpressiveTheme(
        colorScheme =
            when (style) {
                ThemeStyle.SYSTEM -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
                ThemeStyle.PURPLE -> if (dark) PurpleDark else PurpleLight
            },
        motionScheme = MotionScheme.expressive(),
        content = content,
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun SetupScreen(tick: Int, refresh: () -> Unit) {
    val context = LocalContext.current
    val uri = LocalUriHandler.current
    val state by TetherState.snapshot.collectAsState()
    val requestPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { refresh() }

    // Recomputed on every tick so the checklist follows changes made in other apps.
    val permissionsGranted = tick >= 0 && PERMISSIONS.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    val shizukuRunning = Shizuku.pingBinder()
    val shizukuReady = Privileged.isReady()
    val iconStyle = remember(tick) { AppIcon.current(context) }
    val list = rememberLazyListState()
    val headerGone by remember { derivedStateOf { list.firstVisibleItemIndex > 0 } }
    val appleIe = shizukuReady && runCatching { Privileged.hasAppleIe() }.getOrDefault(false)
    val pairedMacs = if (permissionsGranted) pairedComputers(context) else emptyList()

    Scaffold(
    ) { padding ->
        Box {
        LazyColumn(
            state = list,
            contentPadding =
                PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                // Title and subtitle, with the mascot (the inchworm on macOS's Personal Hotspot link
                // glyph) beside them at the same height.
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.padding(top = 24.dp, bottom = 8.dp, start = 4.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("TetherLink", style = MaterialTheme.typography.displaySmall)
                        Text("Instant Hotspot for your Mac", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Buddy(Modifier.height(80.dp))
                }
            }
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
                            "Stop" to { AutoStart.set(context, false); context.stopService(Intent(context, TetherService::class.java)); Unit }
                        } else {
                            ("Start" to { AutoStart.set(context, true); context.startForegroundService(Intent(context, TetherService::class.java)); Unit })
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
                            else -> "Paired with ${pairedMacs.joinToString()}. Your Mac connects when its TetherLink app runs."
                        },
                    details =
                        "1. On your Mac, open System Settings → Bluetooth and leave it open, so the Mac stays discoverable.\n" +
                            "2. On this phone, open Bluetooth settings → Pair new device, and pick your Mac.\n" +
                            "3. Check that both screens show the same code, and confirm on both within 30 seconds. " +
                            "If it times out, Android forgets the Mac, so just pair again.\n" +
                            "4. Install TetherLink on your Mac. Pairing also gives it the keys for the encrypted " +
                            "Bluetooth LE link, so there's no second prompt.",
                    detailsLink = "Mac setup guide" to { uri.openUri(Links.MAC_SETUP) },
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
            item { SectionTitle("Appearance") }
            item {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("App theme", style = MaterialTheme.typography.titleMedium)
                        Choice(
                            listOf(ThemeStyle.SYSTEM to "System colors", ThemeStyle.PURPLE to "Default"),
                            selected = AppTheme.get(context),
                        ) {
                            AppTheme.set(context, it)
                            refresh()
                        }
                        Text("App icon", style = MaterialTheme.typography.titleMedium)
                        Choice(listOf(AppIcon.Style.SYSTEM to "System colors", AppIcon.Style.PURPLE to "Default"), selected = iconStyle) {
                            AppIcon.set(context, it)
                            refresh()
                        }
                        Text(
                            "System colors follow your wallpaper. Some launchers drop the home-screen icon when it changes; " +
                                "add it back from the app drawer.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            item { SectionTitle("Resources") }
            item {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    Column {
                        ResourceRow("Set up the Mac app", "Install TetherLink on your Mac and pair it") { uri.openUri(Links.MAC_SETUP) }
                        ResourceRow("Get TetherLink for Mac", "Downloads on the releases page") { uri.openUri(Links.RELEASES) }
                        ResourceRow("Source code on GitHub", "xav-ie/tether-link") { uri.openUri(Links.REPO) }
                    }
                }
            }
            item {
                Text(
                    "Version ${context.packageManager.getPackageInfo(context.packageName, 0).versionName}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(8.dp),
                    textAlign = TextAlign.Center,
                )
            }
        }
        // Sticky compact bar once the big header has scrolled away.
        AnimatedVisibility(
            visible = headerGone,
            enter = fadeIn() + slideInVertically { -it },
            exit = fadeOut() + slideOutVertically { -it },
        ) {
            Surface(color = MaterialTheme.colorScheme.surfaceContainer, shadowElevation = 3.dp) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().statusBarsPadding().height(64.dp).padding(horizontal = 20.dp),
                ) {
                    Text("TetherLink", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    Buddy(Modifier.height(36.dp))
                }
            }
        }
        }
    }
}

/** The app's mascot: the inchworm on macOS's Personal Hotspot link glyph, in the accent colour. */
@Composable
private fun Buddy(modifier: Modifier) {
    Image(
        painterResource(R.drawable.ic_stat_tether),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MaterialTheme.colorScheme.primary),
        // The drawable is square; crop to the creature's own aspect so it fills the height.
        contentScale = ContentScale.Crop,
        modifier = modifier.aspectRatio(1.6f),
    )
}

@Composable
private fun ResourceRow(title: String, subtitle: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle) },
        trailingContent = { Text("↗", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        modifier = Modifier.clickable(onClick = onClick),
    )
}

@Composable
private fun <T> Choice(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (value, label) ->
            SegmentedButton(
                selected = value == selected,
                onClick = { onSelect(value) },
                shape = SegmentedButtonDefaults.itemShape(i, options.size),
            ) { Text(label) }
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
    detailsLink: Pair<String, () -> Unit>? = null,
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
            Column(Modifier.padding(start = 68.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(details.orEmpty(), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                detailsLink?.let { (label, onClick) -> FilledTonalButton(onClick = onClick) { Text(label) } }
            }
        }
    }
}
