package ie.xav.tetherlink

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import rikka.shizuku.Shizuku

/** Setup screen: permissions, service start/stop, and the Apple Personal Hotspot toggle. */
class MainActivity : Activity() {
    private val permissions =
        arrayOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.POST_NOTIFICATIONS)

    private lateinit var status: TextView
    private lateinit var apple: Switch

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        status = TextView(this).apply { textSize = 16f }
        apple =
            Switch(this).apply {
                text = "Advertise as an Apple Personal Hotspot"
                setOnClickListener {
                    if (!Privileged.isReady() || !Privileged.setAppleIe(isChecked)) isChecked = !isChecked
                    refresh()
                }
            }
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(48, 160, 48, 48)
                addView(status)
                addView(button("Set up permissions") { setUp() })
                addView(button("Start service") { startForegroundService(Intent(context, TetherService::class.java)); refresh() })
                addView(button("Stop service") { stopService(Intent(context, TetherService::class.java)); refresh() })
                addView(apple)
            },
        )
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun button(label: String, onClick: () -> Unit) = Button(this).apply { text = label; setOnClickListener { onClick() } }

    private fun setUp() {
        requestPermissions(permissions, 0)
        if (Shizuku.pingBinder() && Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) Shizuku.requestPermission(0)
    }

    private fun refresh() {
        val granted = permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        val shizuku =
            when {
                !Shizuku.pingBinder() -> "not running"
                Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED -> "no permission"
                else -> "ready"
            }
        status.text = "Permissions: ${if (granted) "granted" else "missing"}\nShizuku: $shizuku"
        apple.isEnabled = Privileged.isReady()
        if (apple.isEnabled) apple.isChecked = runCatching { Privileged.hasAppleIe() }.getOrDefault(false)
    }
}
