# AltTab

A small Windows-style window switcher for macOS. No updates, no upgrades, no tracking.

- **Option-Tab** opens the list of windows, most recent first. Tab or arrows move, Shift-Tab goes back.
- **Release Option** to switch. **Esc** cancels.
- **Type while holding Option** to search window titles and app names.
- Includes minimized windows and hidden apps on the current Space.

Needs Accessibility permission (System Settings → Privacy & Security → Accessibility).

## Build

```sh
./build.sh
```

Builds `AltTab.app`, signs it and installs it to `~/Applications`. Set `SIGN_ID` to use another signing identity.

## Credits

The window focusing approach (private SkyLight calls) is borrowed from
[AltTab by lwouis](https://github.com/lwouis/alt-tab-macos), which ported it from yabai and Hammerspoon.
Licensed GPL-3.0 to match.
