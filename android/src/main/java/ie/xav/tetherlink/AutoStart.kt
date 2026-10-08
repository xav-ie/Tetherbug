package ie.xav.tetherlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/** Remembers whether the user wants the service running, and restarts it after a reboot or an app update. */
object AutoStart {
    private const val PREFS = "tether-link"
    private const val KEY = "service_wanted"

    fun set(context: Context, wanted: Boolean) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY, wanted).apply()

    // Defaults to wanted: running is the app's point, and Stop records the opt-out.
    fun wanted(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, true)

    class Receiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            // The connectedDevice service type needs the Bluetooth permissions; skip until setup grants them.
            val granted = PERMISSIONS.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
            if (wanted(context) && granted) context.startForegroundService(Intent(context, TetherService::class.java))
        }
    }
}
