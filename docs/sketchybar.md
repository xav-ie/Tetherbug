# TetherLink in SketchyBar

Show your phone's hotspot state and battery in [SketchyBar](https://github.com/FelixKratz/SketchyBar).
It reads `tether-link status --json` from the TetherLink app's background agent, so turn on **Run in the
background** in TetherLink first. The CLI lives inside the app at
`/Applications/TetherLink.app/Contents/MacOS/TetherLink` (Homebrew and Nix installs also put it on
your `PATH` as `tether-link`).

## The item

Add to your `sketchybarrc`:

```sh
sketchybar --add item tether right \
  --set tether update_freq=10 \
               script="$CONFIG_DIR/plugins/tether.sh" \
               click_script="tether-link enable"
```

## The plugin

Save as `plugins/tether.sh` and make it executable (`chmod +x`). It needs [`jq`](https://jqlang.org).

```sh
#!/usr/bin/env bash
# Hidden while the phone isn't connected; otherwise hotspot state and phone battery.
state=$(tether-link status --json 2>/dev/null) || { sketchybar --set "$NAME" drawing=off; exit 0; }
if [ "$(jq -r .connected <<<"$state")" != true ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi
hotspot=$(jq -r .status.hotspot <<<"$state")
battery=$(jq -r .status.battery <<<"$state")
sketchybar --set "$NAME" drawing=on label="$hotspot · $battery%"
```

Clicking the item asks the phone to turn its hotspot on. Use `tether-link disable` to turn it off.
