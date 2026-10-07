import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/**
 * Makes an Android hotspot advertise itself like an iPhone Personal Hotspot.
 *
 * <p>macOS decides a Wi-Fi network is a personal hotspot (link icon in the Wi-Fi menu, metered
 * interface, hotspot auto-join rules) from an Apple vendor element in the beacon: OUI 00:17:F2,
 * type 6. Android 13+ can add vendor elements to its hotspot via the system-only
 * SoftApConfiguration.Builder#setVendorElements, which the shell uid may call. Run through
 * `app_process` as shell (adb or Shizuku); the setting persists in the hotspot config.
 *
 * <p>Usage: show | apple | clear
 */
public class SoftApIe {
    private static final byte[] APPLE_PERSONAL_HOTSPOT = {
        0x00, 0x17, (byte) 0xF2, 0x06, 0x01, 0x01, 0x03, 0x01, 0x00, 0x00
    };
    private static final int EID_VSA = 221;

    public static void main(String[] args) throws Exception {
        String mode = args.length == 0 ? "show" : args[0];
        if (!List.of("show", "apple", "clear").contains(mode)) {
            System.err.println("usage: softap-ie [show|apple|clear]");
            System.exit(1);
        }

        Object binder =
                Class.forName("android.os.ServiceManager")
                        .getMethod("getService", String.class)
                        .invoke(null, "wifi");
        Class<?> wifiManager = Class.forName("android.net.wifi.IWifiManager");
        Object wifi =
                Class.forName("android.net.wifi.IWifiManager$Stub")
                        .getMethod("asInterface", Class.forName("android.os.IBinder"))
                        .invoke(null, binder);
        Method get = wifiManager.getMethod("getSoftApConfiguration");
        Object config = get.invoke(wifi);
        if (mode.equals("show")) {
            System.out.println(config);
            return;
        }

        Class<?> configClass = Class.forName("android.net.wifi.SoftApConfiguration");
        Class<?> builderClass = Class.forName("android.net.wifi.SoftApConfiguration$Builder");
        Object builder = builderClass.getConstructor(configClass).newInstance(config);
        List<Object> elements = new ArrayList<>();
        if (mode.equals("apple")) {
            elements.add(
                    Class.forName("android.net.wifi.ScanResult$InformationElement")
                            .getConstructor(int.class, int.class, byte[].class)
                            .newInstance(EID_VSA, 0, APPLE_PERSONAL_HOTSPOT));
        }
        builderClass.getMethod("setVendorElements", List.class).invoke(builder, elements);
        Object updated = builderClass.getMethod("build").invoke(builder);
        boolean ok =
                (boolean)
                        wifiManager
                                .getMethod("setSoftApConfiguration", configClass, String.class)
                                .invoke(wifi, updated, "com.android.shell");
        System.out.println(mode + ": " + (ok ? "ok (restart the hotspot to apply)" : "rejected"));
        if (!ok) System.exit(1);
    }
}
