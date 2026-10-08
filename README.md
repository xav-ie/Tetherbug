<img align="right" src="design/icon.svg" width="120" alt="tether-link icon: an inchworm made of two interlocked chain links">

# tether-link

Apple's Instant Hotspot, for an Android phone and a Mac. The phone runs a
Bluetooth LE service; the Mac asks it to turn its hotspot on when there's no
Wi-Fi, and the hotspot advertises itself the way an iPhone's does, so macOS
treats it as a Personal Hotspot.

## Pieces

| Path | What | Status |
| --- | --- | --- |
| `cli/softap-ie` | `softap-ie show\|apple\|clear` over `adb` | done |
| `android/` | foreground service: BLE GATT server, hotspot control via Shizuku | done |
| `macos/` | `tether-link` CoreBluetooth helper + sketchybar item | planned |
| `design/` | icon: `icon-source.svg` (editable), `icon.py` (generates the app's vector drawables and `icon.svg`) | done |

## How macOS recognises a Personal Hotspot

macOS decides a network is a personal hotspot from an Apple vendor element in
the Wi-Fi beacon (OUI `00:17:F2`, type 6, `DD0A0017F206010103010000`).
`-[CWNetwork isPersonalHotspot]` checks for it, and it drives the link icon in
the Wi-Fi menu, the metered ("expensive") interface and the hotspot auto-join
rules. The saved known-network `PersonalHotspot` flag does not. The separate
"Personal Hotspot" section with battery bars is Continuity over BLE tied to an
Apple Account, and is out of reach.

Android 13+ can add vendor elements to its hotspot through the system-only
`SoftApConfiguration.Builder#setVendorElements`, which the shell uid (adb or
Shizuku) may call. The setting persists in the hotspot config.

## softap-ie

```sh
nix run .#softap-ie -- show    # current hotspot config (passphrase redacted)
nix run .#softap-ie -- apple   # advertise as an Apple Personal Hotspot
nix run .#softap-ie -- clear   # remove the vendor elements again
```

Restart the hotspot to apply. Needs an `adb` connection to the phone. The dex
is built with JDK 17 and D8 from Google's R8 jar, no Android SDK required.

## References

- [Configure an access point as a personal hotspot](https://www.yichya.dev/configure-access-point-as-personal-hotspot/):
  adding the Apple vendor element to an OpenWrt hostapd config makes macOS
  treat the AP as a Personal Hotspot; the element used here comes from it.
- [MikroTik forum: Apple personal hotspot vendor element](https://forum.mikrotik.com/viewtopic.php?t=199314):
  the same trick on RouterOS.
- [Android metered hotspots](https://www.lorier.net/docs/android-metered.html):
  Android marks its hotspot metered via DHCP option 43 `ANDROID_METERED`,
  which macOS ignores.
- [`SoftApConfiguration.java`](https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/SoftApConfiguration.java):
  `Builder#setVendorElements` (Android 13+, `@SystemApi`).
- [Apple Platform Security: Instant Hotspot](https://support.apple.com/guide/security/instant-hotspot-security-seca4b33e8c9/web):
  why the Continuity "Personal Hotspot" section can't be reproduced.

## BLE protocol (draft)

One primary service; characteristics require an encrypted, bonded link, so only
a paired Mac can read status or send commands. The advertisement carries only
the service UUID.

| UUID | Name | Properties | Payload |
| --- | --- | --- | --- |
| `1581bac4-33fe-43a8-b97f-5dd7a01f48c9` | service | | |
| `90766fca-8a24-43ae-8501-3dcef06a8479` | status | read, notify | `version u8`, `hotspot u8` (0 off, 1 starting, 2 on, 3 failed), `battery u8` (%), `signal u8` (0–4), `ssid` (UTF-8, rest) |
| `e036426f-6317-487d-8777-e6f6d91f8a4d` | command | write | `0x01` enable, `0x02` disable |
