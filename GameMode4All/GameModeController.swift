//
//  GameModeController.swift
//  GameMode4All
//
//  Uses xcrun gamepolicyctl (requires Xcode) to enable/disable Game Mode.
//
//  Apple’s rule (Support article 105118, Developer Forums): Game Mode turns on when
//  the app is full screen and is the frontmost app. It turns off when you exit
//  full screen or the app is no longer frontmost. We follow the same rule for
//  user-selected (and CrossOver/process-watch) trigger apps.
//

import AppKit
import ApplicationServices
import Combine
import Foundation
import ServiceManagement
import SwiftUI

// MARK: - Debug log
private let debugLoggingEnabledKey = "DebugLoggingEnabled"
private let debugLogFileCustomPathKey = "DebugLogFileCustomPath"

private enum GameModeDebugLog {
    static var defaultLogFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GameMode4All", isDirectory: true)
            .appendingPathComponent("gamemode-debug.log")
    }

    static func log(_ message: String) {
        guard UserDefaults.standard.object(forKey: debugLoggingEnabledKey) as? Bool ?? false else { return }
        guard let file = logFileURL else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let data = line.data(using: .utf8) {
            let dir = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                if let handle = try? FileHandle(forWritingTo: file) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: file)
            }
        }
    }

    static var logFileURL: URL? {
        if let custom = UserDefaults.standard.string(forKey: debugLogFileCustomPathKey), !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return defaultLogFileURL
    }
}

private let processNamesToWatchKey = "ProcessNamesToWatch"
private let processNamesByAppKey = "ProcessNamesByApp"

final class GameModeController: ObservableObject {
    static let shared = GameModeController()

    enum GameModeState {
        case unknown
        case on
        case off
        case temporary
    }

    enum PolicyState {
        case unknown
        case automatic
        case manual
    }

    @Published private(set) var gameModeState: GameModeState = .unknown
    @Published private(set) var policyState: PolicyState = .unknown
    @Published private(set) var isGamePolicyCtlAvailable: Bool = false

    /// Process names (e.g. "helldivers2.exe") that trigger Game Mode when running. Used for CrossOver/Wine games where the .exe is the real process.
    @Published var processNamesToWatch: [String] {
        didSet { UserDefaults.standard.set(processNamesToWatch, forKey: processNamesToWatchKey); processWatchTimerNeedsUpdate() }
    }

    /// Process names grouped by CrossOver app bundle ID (for display under each game in the CrossOver list).
    @Published var processNamesByApp: [String: [String]] {
        didSet { saveProcessNamesByApp(); processWatchTimerNeedsUpdate() }
    }

    /// Start at login (SMAppService.mainApp). Updated when the user toggles or when we refresh from system.
    @Published private(set) var startAtLoginEnabled: Bool = false

    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var fullscreenCheckTimer: Timer?
    private let fullscreenCheckInterval: TimeInterval = 1.5

    init() {
        self.processNamesToWatch = UserDefaults.standard.stringArray(forKey: processNamesToWatchKey) ?? []
        self.processNamesByApp = Self.loadProcessNamesByApp()
        self.debugLoggingEnabled = UserDefaults.standard.object(forKey: debugLoggingEnabledKey) as? Bool ?? false
        refreshStartAtLoginStatus()
        // Start observing at launch so Game Mode can turn on even if the user never opens Settings.
        startObservingAppLaunches()
    }

    /// Reads the current login item status from the system.
    func refreshStartAtLoginStatus() {
        let status = SMAppService.mainApp.status
        startAtLoginEnabled = (status == .enabled || status == .requiresApproval)
    }

    /// Enables or disables "Open at Login". Call from main thread.
    func setStartAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        refreshStartAtLoginStatus()
    }

    private static func loadProcessNamesByApp() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: processNamesByAppKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return decoded
    }

    private func saveProcessNamesByApp() {
        guard let data = try? JSONEncoder().encode(processNamesByApp) else { return }
        UserDefaults.standard.set(data, forKey: processNamesByAppKey)
    }

    func refreshStatus() {
        let (available, mode, policy) = runGamePolicyCtlStatus()
        DispatchQueue.main.async { [weak self] in
            self?.isGamePolicyCtlAvailable = available
            self?.gameModeState = mode
            self?.policyState = policy
        }
    }

    func addProcessNameToWatch(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !processNamesToWatch.contains(trimmed) else { return }
        processNamesToWatch.append(trimmed)
    }

    func removeProcessNameToWatch(_ name: String) {
        processNamesToWatch.removeAll { $0 == name }
        // Remove from any app grouping so UI stays in sync
        if let bundleID = processNamesByApp.first(where: { $0.value.contains(name) })?.key {
            let updated = processNamesByApp[bundleID]!.filter { $0 != name }
            if updated.isEmpty { processNamesByApp.removeValue(forKey: bundleID) }
            else { processNamesByApp[bundleID] = updated }
        }
    }

    /// Process names associated with a CrossOver app (shown under that game in the list).
    func processNames(forApp bundleID: String) -> [String] {
        processNamesByApp[bundleID] ?? []
    }

    func addProcessName(_ name: String, forApp bundleID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !processNamesToWatch.contains(trimmed) { processNamesToWatch.append(trimmed) }
        var list = processNamesByApp[bundleID] ?? []
        if !list.contains(trimmed) {
            list.append(trimmed)
            processNamesByApp[bundleID] = list
        }
    }

    func removeProcessName(_ name: String, forApp bundleID: String) {
        processNamesToWatch.removeAll { $0 == name }
        guard var list = processNamesByApp[bundleID] else { return }
        list.removeAll { $0 == name }
        if list.isEmpty { processNamesByApp.removeValue(forKey: bundleID) }
        else { processNamesByApp[bundleID] = list }
    }

    /// Process names not associated with any CrossOver app (shown in "Trigger when these processes are running").
    var orphanProcessNames: [String] {
        let underApp = Set(processNamesByApp.values.flatMap { $0 })
        return processNamesToWatch.filter { !underApp.contains($0) }
    }

    /// When true, debug messages are written to the log file. Defaults to true.
    @Published var debugLoggingEnabled: Bool {
        didSet { UserDefaults.standard.set(debugLoggingEnabled, forKey: debugLoggingEnabledKey) }
    }

    /// URL of the debug log file (for "Open debug log" in Settings). Uses custom path if set.
    var debugLogFileURL: URL? { GameModeDebugLog.logFileURL }

    /// Presents a save panel to choose where the debug log file is written. Call from main thread.
    func chooseDebugLogLocation() {
        let panel = NSSavePanel()
        panel.title = "Choose Debug Log Location"
        panel.message = "Select where to save the debug log file."
        panel.nameFieldStringValue = "gamemode-debug.log"
        if let current = debugLogFileURL {
            panel.directoryURL = current.deletingLastPathComponent()
            panel.nameFieldStringValue = current.lastPathComponent
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: debugLogFileCustomPathKey)
        objectWillChange.send()
    }

    func startObservingAppLaunches() {
        guard launchObserver == nil else { return }

        startFullscreenCheckTimer()

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkFullscreenAndUpdateGameMode()
        }

        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkFullscreenAndUpdateGameMode()
        }

        checkFullscreenAndUpdateGameMode()
    }

    func stopObservingAppLaunches() {
        if let o = launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        launchObserver = nil
        terminateObserver = nil
        fullscreenCheckTimer?.invalidate()
        fullscreenCheckTimer = nil
    }

    func setGameModeEnabled(_ enabled: Bool) {
        _ = runGamePolicyCtlSet(enabled ? "on" : "off")
        refreshStatus()
    }

    func setGameModeAutomatic() {
        _ = runGamePolicyCtlSet("auto")
        refreshStatus()
    }

    /// Re-evaluates the frontmost fullscreen app and sets Game Mode accordingly (same logic as automatic). Called by the manual shortcut.
    func syncGameModeForFrontmostApp() {
        checkFullscreenAndUpdateGameMode()
    }

    // MARK: - Private (match Apple: full screen + frontmost)

    private func startFullscreenCheckTimer() {
        fullscreenCheckTimer?.invalidate()
        fullscreenCheckTimer = Timer.scheduledTimer(withTimeInterval: fullscreenCheckInterval, repeats: true) { [weak self] _ in
            self?.checkFullscreenAndUpdateGameMode()
        }
        fullscreenCheckTimer?.tolerance = 0.3
        RunLoop.main.add(fullscreenCheckTimer!, forMode: .common)
    }

    private func processWatchTimerNeedsUpdate() {
        // Timer is unified (fullscreen check); no separate process timer
        checkFullscreenAndUpdateGameMode()
    }

    /// Apple behavior: Game Mode on when app is full screen and frontmost; off when not.
    private func checkFullscreenAndUpdateGameMode() {
        let selected = UserDefaults.standard.stringArray(forKey: "SelectedAppBundleIDsForGameMode") ?? []
        let hasCrossOverLauncherSelected = selected.contains { id in
            id.hasPrefix("com.codeweavers.CrossOverHelper") || (id.hasPrefix("path:") && id.lowercased().contains("crossover"))
        }
        let anyWatchedProcessRunning = !processNamesToWatch.isEmpty && processNamesToWatch.contains { isProcessRunning($0) }

        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier else {
            // Fullscreen games (e.g. CrossOver/Helldivers) often report no frontmost app or no bundleID.
            // Don't turn Game Mode off here — leave state unchanged so it stays on when the game goes fullscreen.
            GameModeDebugLog.log("check: no frontmost app or no bundleID → leave state unchanged")
            return
        }

        let appName = frontmost.localizedName ?? bundleID
        let isTriggerApp = selected.contains(bundleID)
            || (bundleID == "com.codeweavers.CrossOver" && hasCrossOverLauncherSelected)
            || anyWatchedProcessRunning

        guard isTriggerApp else {
            GameModeDebugLog.log("check: frontmost=\(appName) bundleID=\(bundleID) selectedCount=\(selected.count) inSelected=\(selected.contains(bundleID)) → not trigger → set auto")
            trySetGameModeOff()
            return
        }

        // Match Apple: Game Mode on only when trigger app is fullscreen and frontmost. When Accessibility isn't granted we can't read windows, so enable when frontmost.
        let (hasFullscreen, accessibilityDenied) = appHasFullscreenWindow(pid: frontmost.processIdentifier)
        let shouldEnable = hasFullscreen || accessibilityDenied
        if accessibilityDenied {
            GameModeDebugLog.log("check: frontmost=\(appName) bundleID=\(bundleID) trigger=yes accessibilityDenied=true → shouldEnable=true (enable when frontmost)")
        } else {
            GameModeDebugLog.log("check: frontmost=\(appName) bundleID=\(bundleID) trigger=yes hasFullscreen=\(hasFullscreen) → shouldEnable=\(shouldEnable)")
        }

        if shouldEnable {
            let ok = runGamePolicyCtlSet("on")
            GameModeDebugLog.log("check: set on → success=\(ok)")
            if ok {
                gameModeState = .on
                policyState = .manual
            }
        } else {
            GameModeDebugLog.log("check: shouldEnable=false → set auto")
            trySetGameModeOff()
        }
    }

    private func trySetGameModeOff() {
        let ok = runGamePolicyCtlSet("auto")
        GameModeDebugLog.log("set auto → success=\(ok)")
        if ok {
            policyState = .automatic
            gameModeState = .off
        }
    }

    private static let axErrorAPIDisabled: Int32 = -25211 // kAXErrorAPIDisabled = Accessibility not granted

    /// Returns (fullscreen, accessibilityDenied). When accessibilityDenied, caller should treat as "enable when frontmost".
    private func appHasFullscreenWindow(pid: pid_t) -> (Bool, accessibilityDenied: Bool) {
        let appRef = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let value = value, CFGetTypeID(value) == CFArrayGetTypeID() else {
            let denied = (err.rawValue == Self.axErrorAPIDisabled)
            GameModeDebugLog.log("fullscreen: pid=\(pid) getWindows err=\(err.rawValue) accessibilityDenied=\(denied) → false")
            return (false, denied)
        }
        let cfArray = unsafeDowncast(value, to: CFArray.self)
        let count = CFArrayGetCount(cfArray)
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let minFullscreenWidth = screenSize.width * 0.95
        let minFullscreenHeight = screenSize.height * 0.95

        for i in 0..<count {
            let windowPtr = CFArrayGetValueAtIndex(cfArray, i)
            let window = unsafeBitCast(windowPtr, to: AXUIElement.self)

            // 1) Prefer AXFullScreen if the app reports it (native fullscreen).
            var fsValue: CFTypeRef?
            let fsErr = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fsValue)
            if fsErr == .success, let num = fsValue as? NSNumber, num.boolValue {
                GameModeDebugLog.log("fullscreen: pid=\(pid) window[\(i)] AXFullScreen=true → true")
                return (true, false)
            }

            // 2) Fallback: window size fills the screen (many apps don't set AXFullScreen).
            var sizeValue: CFTypeRef?
            let sizeErr = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
            if sizeErr == .success, let axValue = sizeValue, CFGetTypeID(axValue) == AXValueGetTypeID() {
                var size = CGSize.zero
                if AXValueGetValue(axValue as! AXValue, .cgSize, &size), size.width >= minFullscreenWidth, size.height >= minFullscreenHeight {
                    GameModeDebugLog.log("fullscreen: pid=\(pid) window[\(i)] size=\(size.width)x\(size.height) >= screen → true")
                    return (true, false)
                }
            }
        }
        // Log first window's details to help debug why we didn't detect fullscreen
        if count > 0 {
            let windowPtr = CFArrayGetValueAtIndex(cfArray, 0)
            let window = unsafeBitCast(windowPtr, to: AXUIElement.self)
            var fsValue: CFTypeRef?
            let fsErr = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fsValue)
            var sizeValue: CFTypeRef?
            let sizeErr = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
            var size = CGSize.zero
            if let axValue = sizeValue, CFGetTypeID(axValue) == AXValueGetTypeID() { _ = AXValueGetValue(axValue as! AXValue, .cgSize, &size) }
            GameModeDebugLog.log("fullscreen: pid=\(pid) windows=\(count) AXFullScreenErr=\(fsErr.rawValue) sizeErr=\(sizeErr.rawValue) firstSize=\(size.width)x\(size.height) screen=\(screenSize.width)x\(screenSize.height) → false")
        } else {
            GameModeDebugLog.log("fullscreen: pid=\(pid) windows=\(count) → false")
        }
        return (false, false)
    }

    private func isProcessRunning(_ name: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", name]
        process.standardOutput = pipe
        process.standardError = nil
        process.qualityOfService = .utility
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runGamePolicyCtlStatus() -> (available: Bool, mode: GameModeState, policy: PolicyState) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["gamepolicyctl", "game-mode", "status"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.qualityOfService = .utility

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, .unknown, .unknown)
        }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else {
            return (false, .unknown, .unknown)
        }

        if output.contains("unable to find utility") {
            return (false, .unknown, .unknown)
        }

        var mode: GameModeState = .unknown
        if output.contains("Game mode is") && output.contains("on") {
            mode = output.contains("will soon turn off") ? .temporary : .on
        } else if output.contains("Game mode is") && output.contains("off") {
            mode = .off
        }

        var policy: PolicyState = .unknown
        if output.contains("enablement policy is currently automatic") { policy = .automatic }
        else if output.contains("enablement policy is currently disabled") { policy = .manual }

        return (true, mode, policy)
    }

    private func runGamePolicyCtlSet(_ policy: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["gamepolicyctl", "game-mode", "set", policy]
        process.standardOutput = pipe
        process.standardError = pipe
        process.qualityOfService = .userInitiated

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else {
            return false
        }
        return output.contains(policy)
    }

}
