# Development

## Repository layout

| Path | What |
| --- | --- |
| `android/` | Android app: setup screen and the foreground service (BLE GATT server, hotspot control via Shizuku) |
| `macos/` | Mac app: one binary that is the window, the background agent (`agent`) and the CLI |
| `cli/softap-ie/` | `softap-ie show\|apple\|clear`: set the Personal Hotspot marker over `adb`, without the app |
| `design/` | the icon: `icon-source.svg` (editable) and `icon.py`, which generates every shipped icon asset |
| `docs/` | [Mac](macos.md) and [SketchyBar](sketchybar.md) guides, this page, the [BLE protocol](protocol.md) |

## Building

Everything builds from the repository root, in the flake's dev shell (JDK 21 and the Android SDK).

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
