# ExposeLabels

Adds app icons, app names and window titles to Mission Control thumbnails.
About 250 lines of Swift in `Sources/main.swift`. No dependencies, no network, no screenshots:
it reads the Dock's accessibility tree (thumbnail positions + titles) and the system window list.

## Setup

1. **Build** — `./make-dmg.sh` (needs only the Xcode Command Line Tools). Output: `build/ExposeLabels.dmg` (and `build/ExposeLabels.app`).
2. **Install** — open the DMG, drag ExposeLabels onto Applications, open it. A setup window explains the app, shows which permissions are granted, and has Grant buttons and an *Open at login* switch. Reopen it any time from the menu-bar icon → *Setup & Permissions…*.
3. **Permissions** (if you'd rather do it by hand) — System Settings → Privacy & Security:
   - **Accessibility** → turn on ExposeLabels (required).
   - **Screen Recording** → turn on ExposeLabels (only for window titles; without it you still get icons + app names). Takes effect after a relaunch; the setup window offers a Relaunch button.
4. **Start at login** — the *Open at login* switch in the setup window. By hand: System Settings → General → Login Items & Extensions → **+**.

## Sharing the DMG with other people

The app is signed only on this Mac (ad-hoc), not with an Apple Developer ID. On someone else's Mac, a downloaded copy is blocked the first time:
they right-click the app → **Open** → **Open** (or System Settings → Privacy & Security → *Open Anyway*). Removing that step needs a paid Apple Developer account and notarization.

## After a rebuild

The app is ad-hoc signed, so every rebuild looks like a new app to macOS:
remove the old ExposeLabels entry under Accessibility (and Screen Recording) with **−**, add the new one, and relaunch.
The login item keeps working because it points at the path in `/Applications`.

## Files

- `Sources/main.swift` — the app
- `make-dmg.sh` — builds the app and packages the drag-to-Applications DMG
- `tools/make-icon.swift` — draws the app icon
- `Sources/Setup.swift` — the setup / permissions window
- `build.sh` — builds a universal (Apple silicon + Intel) `.app`, macOS 14+
- `probe.swift` — diagnostic: dumps what the Dock exposes during Mission Control; run it if a macOS update breaks the labels
