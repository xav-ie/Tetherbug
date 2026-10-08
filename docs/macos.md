# TetherLink for Mac

TetherLink keeps a Bluetooth link to your Android phone and asks it to turn its hotspot on when your
Mac loses Wi-Fi. It has a window for status and settings, a background agent that does the work, and
a `tether-link` command-line tool.

## 1. Set up the phone

Install the TetherLink Android app from the
[releases page](https://github.com/xav-ie/TetherLink/releases), then follow its setup checklist:
Bluetooth and notification permissions, [Shizuku](https://shizuku.rikka.app) (hotspot control needs
system rights), and start the service.

## 2. Pair the phone with your Mac

1. On your Mac, open **System Settings → Bluetooth** and leave it open so the Mac stays discoverable.
2. On the phone, open **Bluetooth settings → Pair new device** and pick your Mac.
3. Check that both screens show the same code and confirm on both within 30 seconds. If it times out,
   Android forgets the Mac; just pair again.

Pairing also gives TetherLink the keys for its encrypted Bluetooth LE link, so there's no second
prompt. Only a paired Mac can read the phone's status or turn its hotspot on.

## 3. Run TetherLink

Open TetherLink and turn on **Run in the background**. macOS may ask you to allow it under
**System Settings → General → Login Items**, and asks once for Bluetooth access. The window then shows
your phone, its hotspot state and battery.

### Settings

| Setting | Default | What it does |
| --- | --- | --- |
| Ask for the hotspot when Wi-Fi drops | on | When Wi-Fi stays disconnected for 5 seconds, ask the phone to turn its hotspot on. |
| Turn it off when back on regular Wi-Fi | on | Once the Mac is on a non-metered network again, turn the phone's hotspot off to save its battery. |
| Run in the background | off | Starts the agent at login and keeps it running when the window is closed. |

### Command line

```sh
tether-link status          # phone, hotspot state, battery, signal (--json for scripts)
tether-link enable          # ask the phone to turn its hotspot on
tether-link disable         # ...or off
tether-link watch           # one JSON line every time the state changes
```

Using SketchyBar? See [TetherLink in SketchyBar](sketchybar.md).

## Build from source

Needs the Xcode command line tools.

```sh
git clone https://github.com/xav-ie/TetherLink
TetherLink/macos/build.sh ~/Applications
open ~/Applications/TetherLink.app
```
