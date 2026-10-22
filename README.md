# Snug

Your menu bar's backroom.

Snug hides the menu bar icons you don't need to see. Click the beard (or press ⌃⌥⌘B) for a dropdown with three rows: Showing, Hidden and Always hidden. Click an icon to use it; drag it to another row to move it.

Everything stays on your Mac. The build fails if the app references any networking API (`check-no-network.sh`).

## Permissions

- **Accessibility**: to see which app owns each menu bar icon, and to click or ⌘-drag icons for you.
- **Screen Recording** (optional): to show the real icons in the dropdown. Snug captures only the icons' own small windows, keeps the pictures in memory and never saves them. Without it, the dropdown shows each app's Dock icon.

Snug explains each one before macOS asks.

## Build

Requires macOS 14 or later (Liquid Glass on macOS 26) and an Apple Development signing identity.

```
./build.sh
```

This builds `build/Snug.app` and installs it to `~/Applications/Snug.app`.

Snug is not affiliated with Bartender or Ice.
