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

   <img src="docs/images/step-pair.svg" alt="The phone advertises over Bluetooth; only the paired Mac gets an encrypted, bonded link, other devices are refused.">
2. The **Mac app**'s background agent stays connected to the phone. When Wi-Fi
   stays disconnected for 5 seconds it asks for the hotspot; once the Mac is
   back on a regular network it turns the hotspot off again.

   <img src="docs/images/step-wifi-drops.svg" alt="The Mac loses Wi-Fi, waits 5 seconds for a known network, then sends enable to the phone; back on regular Wi-Fi it sends disable.">
3. The phone turns its hotspot on through [Shizuku](https://shizuku.rikka.app)
   (no root) and can add Apple's Personal Hotspot marker to its Wi-Fi beacon,
   which is what makes macOS recognise it.

   <img src="docs/images/step-hotspot-on.svg" alt="The phone turns its hotspot on via Shizuku with the Apple marker in its beacon, and the Mac joins it as a Personal Hotspot.">

### When Wi-Fi drops

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'fontFamily': 'Helvetica, Arial, sans-serif', 'primaryColor': '#281336', 'primaryTextColor': '#fff17b', 'primaryBorderColor': '#fff17b', 'lineColor': '#fff17b', 'textColor': '#fff17b', 'clusterBkg': '#12081a', 'clusterBorder': '#51d136', 'titleColor': '#51d136', 'edgeLabelBackground': '#12081a', 'actorBkg': '#281336', 'actorBorder': '#fff17b', 'actorTextColor': '#fff17b', 'actorLineColor': '#fff17b', 'signalColor': '#fff17b', 'signalTextColor': '#fff17b', 'noteBkgColor': '#281336', 'noteTextColor': '#51d136', 'noteBorderColor': '#51d136'}}}%%
sequenceDiagram
    box rgb(18, 8, 26)
    participant Mac as Mac agent
    participant Phone as Android app
    participant Shizuku
    end
    Note over Mac,Phone: Wi-Fi disconnected
    Mac->>Mac: wait 5 s for a known network
    Mac->>Phone: enable (encrypted BLE write)
    Phone->>Shizuku: start tethering
    Shizuku-->>Phone: hotspot on
    Phone-->>Mac: status: on, ssid "My Hotspot"
    Note over Mac,Phone: macOS joins it as a Personal Hotspot
    Note over Mac,Phone: later: back on regular Wi-Fi
    Mac->>Phone: disable
    Phone->>Shizuku: stop tethering
```

### The pieces

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'fontFamily': 'Helvetica, Arial, sans-serif', 'primaryColor': '#281336', 'primaryTextColor': '#fff17b', 'primaryBorderColor': '#fff17b', 'lineColor': '#fff17b', 'textColor': '#fff17b', 'clusterBkg': '#12081a', 'clusterBorder': '#51d136', 'titleColor': '#51d136', 'edgeLabelBackground': '#12081a', 'actorBkg': '#281336', 'actorBorder': '#fff17b', 'actorTextColor': '#fff17b', 'actorLineColor': '#fff17b', 'signalColor': '#fff17b', 'signalTextColor': '#fff17b', 'noteBkgColor': '#281336', 'noteTextColor': '#51d136', 'noteBorderColor': '#51d136'}}}%%
flowchart LR
    subgraph frame [" "]
        direction LR
        subgraph mac [Mac]
            window[TetherLink window]
            cli[tether-link CLI / SketchyBar]
            agent[Background agent]
            sock([agent.sock])
            window --> sock
            cli --> sock
            sock --> agent
        end
        subgraph phone [Android phone]
            service[TetherLink service]
            shizuku[Shizuku]
            tethering[Tethering + Wi-Fi services]
            service --> shizuku --> tethering
        end
        agent <-- "BLE: status, commands, password" --> service
    end
    style frame fill:#12081a,stroke:#12081a
```

The phone and Mac talk over a small, documented [BLE protocol](docs/protocol.md).
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

Releases aren't published yet; until then, build from source ([Development](docs/development.md)).

## Documentation

- [TetherLink for Mac](docs/macos.md): installing, pairing, settings and the `tether-link` command
- [TetherLink in SketchyBar](docs/sketchybar.md)
- [Development](docs/development.md): repository layout and building each piece
- [BLE protocol](docs/protocol.md): how the phone and Mac talk

## How macOS recognises a Personal Hotspot

<p align="center"><img src="docs/images/beacon.svg" alt="The phone's Wi-Fi beacon carries an Apple vendor element (DD 0A 00:17:F2 06 …), so macOS lists the network as a Personal Hotspot with the link icon, treats it as metered and applies hotspot auto-join rules."></p>

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
