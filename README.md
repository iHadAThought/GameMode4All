# GameMode4All

A macOS menu bar app that adds a **System Settings–style pane** to choose which applications should turn on **Game Mode** when they launch. When any selected app starts, Game Mode is enabled automatically; when the last selected app quits, it can switch back to the system default.

## Requirements

- **macOS 14 (Sonoma) or later**
- **Apple Silicon Mac** (Game Mode is not available on Intel Macs)
- **Xcode** installed (for the `gamepolicyctl` tool; the app does not ship it)

## What Game Mode does to your Mac

When Game Mode is on, macOS optimizes the system for your game or app:

- **CPU & GPU priority** — Your game or app gets the highest priority access to the CPU and GPU. Background tasks and services are suppressed (via `gamepolicyd` and RunningBoard) so the game or app receives more resources. This typically results in smoother, more consistent frame rates and improved responsiveness.
- **Higher GPU usage** — Your game or app can use a larger share of GPU capacity; measurements show GPU usage often increases from ~50% in windowed mode to over 80% when Game Mode is enabled.
- **Reduced input latency** — Bluetooth sampling is doubled for wireless game controllers and accessories, cutting input lag.
- **Reduced audio latency** — The same Bluetooth change lowers audio latency for wireless headsets like AirPods.

Game Mode is intended for gaming or focused app sessions. When it’s on, background work (updates, indexing, etc.) is deprioritized, so you may notice other apps running slightly slower if you switch away.

## How to build

1. Open `GameMode4All.xcodeproj` in Xcode.
2. Select the **GameMode4All** scheme and your Mac as the run destination.
3. Press **⌘B** to build, or **⌘R** to run.

## How to use

1. **Launch the app** — it runs from the menu bar (game controller icon). It does not appear in the Dock (`LSUIElement`).
2. **Open settings** — click the menu bar icon, then **“Open Game Mode Settings…”** (or use **⌘,** when the app is focused). This opens the main settings window.
3. **Choose apps** — the pane lists installed applications from `/Applications`, `/System/Applications`, and your user `~/Applications`. Check the apps that should enable Game Mode when they start.
4. **Behavior** — leave **“Turn Game Mode back to automatic when no selected app is running”** on so that when you quit the last selected app, Game Mode returns to the system default.
5. **Keyboard (Modifier Keys)** — optionally swap Command (⌘) and Option (⌥) for any connected keyboard (like System Settings → Keyboard → Modifier Keys). Uses `hidutil`; changes are temporary and reset after restart.

Game Mode is turned **on** when you launch any selected app, and (if the option above is on) is set back to **automatic** when none of those apps are running.

## How it works

- The app uses **`xcrun gamepolicyctl game-mode set on|auto`**, which is provided by Xcode. If Xcode is not installed (or not at `/Applications/Xcode.app`), the status will show that Game Mode control is unavailable.
- It observes **app launch/quit** via `NSWorkspace.didLaunchApplicationNotification` and `didTerminateApplicationNotification`, and keeps a list of selected apps by **bundle ID** in UserDefaults.
- **Keyboard (Modifier Keys)** is integrated from KeySwap: IOKit enumerates HID keyboards, and **`hidutil`** applies `UserKeyMapping` to swap ⌘ and ⌥. App Sandbox must be disabled (already is) for `hidutil` to run.
- The settings UI is a standard SwiftUI **Form** with search, similar to a System Settings pane. The app does not install a real third-party pane inside System Settings (Apple does not support that on modern macOS); instead it provides its own settings window.

## Project structure

- **GameMode4AllApp.swift** — App entry, `Settings` scene (main pane), and menu bar extra.
- **SettingsPaneView.swift** — System Settings–style form: status, behavior toggle, and searchable app list with checkboxes.
- **InstalledAppsProvider.swift** — Enumerates `.app` bundles under `/Applications`, `/System/Applications`, and the user Applications directory.
- **InstalledAppStore.swift** — Persists selected bundle IDs in UserDefaults and exposes them to the UI.
- **GameModeController.swift** — Runs `gamepolicyctl`, observes app launch/terminate, and turns Game Mode on/auto as needed.
- **KeyboardInfo.swift** / **KeyboardManager.swift** — KeySwap integration: enumerate keyboards (IOKit), swap Command ⇄ Option via `hidutil`.
- **MenuBarMenuView.swift** — Menu bar dropdown: status, “Open Game Mode Settings…”, Quit.

## License

Use and modify as you like.
