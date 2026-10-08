package ie.xav.tetherlink

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/** Picks the launcher icon colourway by enabling one of the two activity aliases. */
object AppIcon {
    enum class Style(val alias: String) { PURPLE(".IconPurple"), SYSTEM(".IconSystem") }

    private const val PREFS = "tether-link"
    private const val KEY = "icon_style"

    fun current(context: Context): Style =
        Style.entries.firstOrNull { context.packageManager.getComponentEnabledSetting(component(context, it)).let { s ->
            s == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (s == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && it == Style.PURPLE)
        } } ?: Style.PURPLE

    fun set(context: Context, style: Style) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, style.name).apply()
        for (other in Style.entries) {
            context.packageManager.setComponentEnabledSetting(
                component(context, other),
                if (other == style) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    /** The manifest ships the purple icon; the first launch switches to the wallpaper colours. */
    fun applyFirstLaunchDefault(context: Context) {
        if (!context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).contains(KEY)) set(context, Style.SYSTEM)
    }

    private fun component(context: Context, style: Style) = ComponentName(context.packageName, context.packageName + style.alias)
}
