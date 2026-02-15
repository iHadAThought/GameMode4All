# GameMode4All

A macOS menu bar app that adds a **System Settings–style pane** to choose which games or apps should turn on **Game Mode** when fullscreen and frontmost.
## Requirements

- **macOS 14 (Sonoma) or later**
- **Apple Silicon Mac** (Game Mode is not available on Intel Macs)
- **Xcode** installed (for the `gamepolicyctl` tool; the app does not ship it)
- **Accessibility** permission (for fullscreen detection and the Game Mode shortcut)

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

1. **Launch the app** — it runs from the menu bar (game controller icon). It does not appear in the Dock.
2. **Open settings** — click the menu bar icon, then **“Open GameMode4All…”** (or use **⌘,** when the app is focused).
3. **Mac Apps** — choose games or apps from the main list. Each list has its own search bar and can be collapsed.
4. **CrossOver** — add the CrossOver applications folder to list CrossOver/Wine games; these appear in a separate section.
5. **Keyboard (Modifier Keys)** — swap Command (⌘) and Option (⌥) for a selected keyboard. Choose one: **Save swap at login** (Launch Agent re-applies after restart) or **Swap keys in Game Mode** (swap only when Game Mode is on).
6. **Settings** — **Game Mode shortcut** (default ⌘⇧G): press the combo to sync Game Mode based on the frontmost fullscreen app. Enable the shortcut and optionally **Record…** a custom combo. **Start GameMode4All at login**, **Reopen setup**, debug logging, and **Uninstall…**.

Game Mode is turned **on** when a selected app is fullscreen and frontmost, and **off** when it is not (or when you press the shortcut to re-evaluate).

## How it works

- **`xcrun gamepolicyctl game-mode set on|auto`** — provided by Xcode; controls Game Mode.
- **App observation** — observes app launch/terminate via `NSWorkspace`, plus a fullscreen check timer. Keeps selected bundle IDs in UserDefaults.
- **Keyboard (Modifier Keys)** — KeySwap integration: IOKit enumerates HID keyboards, `hidutil` applies `UserKeyMapping`. Launch Agent option for login persistence; optional swap-only-when-Game-Mode-on.
- **Game Mode shortcut** — `NSEvent.addGlobalMonitorForEvents` captures the key combo globally; triggers `syncGameModeForFrontmostApp()` (same logic as the automatic fullscreen check).
- **Accessibility** — required for fullscreen detection and global key monitoring. App Sandbox is disabled (needed for `hidutil`).

## Project structure

- **GameMode4AllApp.swift** — App entry, main window scene, FirstRunState.
- **SettingsPaneView.swift** — Main pane: Status, Mac Apps, CrossOver, Keyboard, Settings (with collapsible searchable lists).
- **InstalledAppsProvider.swift** — Enumerates `.app` bundles; excludes CrossOver apps from the main list.
- **InstalledAppStore.swift** — Persists selected bundle IDs, CrossOver folders, and app lists.
- **GameModeController.swift** — Runs `gamepolicyctl`, observes apps, fullscreen check, `syncGameModeForFrontmostApp()`.
- **GameModeHotKeyManager.swift** — Global shortcut registration and recording.
- **KeyboardInfo.swift** / **KeyboardManager.swift** — KeySwap: IOKit + `hidutil`, Save at login / Swap in Game Mode.
- **StatusBarController.swift** — Menu bar icon (green when Game Mode is on).
- **MenuBarMenuView.swift** — Menu bar dropdown: status, "Open GameMode4All…", Quit.
- **SetupChecklistView.swift** — First-run setup (Xcode, Accessibility).
- **UninstallHelper.swift** — Uninstall flow.

## License

Use and modify as you like.
