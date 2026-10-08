<img align="right" src="design/icon.svg" width="120" alt="TetherLink icon: an inchworm made of two interlocked chain links">

# TetherLink

Apple's Instant Hotspot, for an Android phone and a Mac. When your Mac loses
Wi-Fi, it asks the phone over Bluetooth to turn its hotspot on, and the
hotspot advertises itself the way an iPhone's does, so macOS treats it as a
Personal Hotspot: link icon in the Wi-Fi menu, a metered connection, and the
usual hotspot auto-join rules.

## How it works

1. The **Android app** runs a small foreground service that advertises a
   Bluetooth LE service. Only a Mac paired with the phone can read its status
   or send it commands (the link is encrypted and bonded).
2. The **Mac app**'s background agent stays connected to the phone. When Wi-Fi
   stays disconnected for 5 seconds it asks for the hotspot; once the Mac is
   back on a regular network it turns the hotspot off again.
3. The phone turns its hotspot on through [Shizuku](https://shizuku.rikka.app)
   (no root) and can add Apple's Personal Hotspot marker to its Wi-Fi beacon,
   which is what makes macOS recognise it.

The Mac app has a window for status, the hotspot switch, its password and
settings, plus a `tether-link` command for scripts and
[SketchyBar](docs/sketchybar.md).

## Getting started

- **Phone:** install the Android app (Android 13+), then follow its setup
  checklist: Bluetooth and notification permissions, Shizuku, start the
  service. Turn on **Look like an iPhone hotspot** for the Personal Hotspot
  marker.
- **Mac:** see [TetherLink for Mac](docs/macos.md) for installing, pairing and
  settings (macOS 14+).
- **SketchyBar:** see [TetherLink in SketchyBar](docs/sketchybar.md).

Releases aren't published yet; until then, build from source (below).

## Repository layout

| Path | What |
| --- | --- |
| `android/` | Android app: setup screen and the foreground service (BLE GATT server, hotspot control via Shizuku) |
| `macos/` | Mac app: one binary that is the window, the background agent (`agent`) and the CLI |
| `cli/softap-ie/` | `softap-ie show\|apple\|clear`: set the Personal Hotspot marker over `adb`, without the app |
| `design/` | the icon: `icon-source.svg` (editable) and `icon.py`, which generates every shipped icon asset |
| `docs/` | Mac and SketchyBar guides |

## Development

Everything builds from the flake's dev shell (JDK 21 and the Android SDK).

```sh
nix develop
(cd android && ./gradlew assembleDebug)     # android/build/outputs/apk/debug/
macos/build.sh ~/Applications               # TetherLink.app (needs Xcode command line tools)
nix run .#softap-ie -- show                 # softap-ie over adb
```

`macos/build.sh` also renders the Mac app icon from the buddy outline, so no
raster assets live in the repo. After changing the icon, regenerate the
Android drawables, `design/icon.svg` and the Mac's shape data:

```sh
nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (p: [ p.shapely p.svg-path ])' -c python3 design/icon.py
```

CI builds the app and `softap-ie` on every push. Pushing a `v*` tag builds a
minified, signed APK and attaches it to a GitHub release; Mac release builds
are still to come.

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
Shizuku) may call. The setting persists in the hotspot config, and takes
effect the next time the hotspot starts.

## BLE protocol

One primary service. Every characteristic requires an encrypted, bonded link,
so only a paired Mac can use it; the advertisement carries nothing but the
service UUID.

| UUID | Name | Properties | Payload |
| --- | --- | --- | --- |
| `1581bac4-33fe-43a8-b97f-5dd7a01f48c9` | service | | |
| `90766fca-8a24-43ae-8501-3dcef06a8479` | status | read, notify | `version u8` (2), `hotspot u8` (0 off, 1 starting, 2 on, 3 failed), `battery u8` (%), `signal u8` (cell, 0–4), `flags u8` (bit 0: hotspot controllable, i.e. Shizuku ready), `ssid` (UTF-8, rest). Version 1 had no `flags`. |
| `e036426f-6317-487d-8777-e6f6d91f8a4d` | command | write | `0x01` enable, `0x02` disable |
| `355534b0-7222-480b-aa18-02a6c30feea2` | credentials | read | hotspot passphrase (UTF-8) |

The phone notifies status whenever the hotspot state changes; a command that
asks for the state the hotspot is already in is a no-op. The Mac agent reads
the passphrase on connect and whenever the hotspot comes on, and hands it out
only on an explicit request, never in its status stream.

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
