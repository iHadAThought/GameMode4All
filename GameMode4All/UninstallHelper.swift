//
//  UninstallHelper.swift
//  GameMode4All
//
//  Removes app data, Launch Agent, and opens System Settings so the user can remove
//  the app from Accessibility and Input Monitoring. Cannot remove privacy permissions programmatically.
//

import AppKit
import Foundation

enum UninstallHelper {
    private static let keySwapLaunchAgentLabel = "com.gamemode4all.keyswap"

    /// UserDefaults keys used by the app (so we can clear them).
    private static let userDefaultsKeysToRemove: [String] = [
        "SelectedAppBundleIDsForGameMode",
        "CrossOverFolders",
        "CrossOverFolderBookmark",
        "CrossOverFolderDisplayPath",
        "DebugLoggingEnabled",
        "DebugLogFileCustomPath",
        "ProcessNamesToWatch",
        "ProcessNamesByApp",
        "HasCompletedFirstRunSetup",
    ]

    /// Performs uninstall: removes configurations, user data, Launch Agent; opens Accessibility and Input Monitoring; then terminates.
    static func performUninstall() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. Remove External Keyboard Launch Agent
        let launchAgentPath = home
            .appendingPathComponent("Library/LaunchAgents/\(keySwapLaunchAgentLabel).plist")
        try? fm.removeItem(at: launchAgentPath)

        // 2. Clear UserDefaults (app preferences and state)
        let defaults = UserDefaults.standard
        for key in userDefaultsKeysToRemove {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        // 3. Remove Application Support data (e.g. GameMode4All debug log folder)
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let gameModeFolder = appSupport.appendingPathComponent("GameMode4All", isDirectory: true)
            try? fm.removeItem(at: gameModeFolder)
        }

        // 4. Open System Settings so user can remove app from Accessibility and Input Monitoring
        //    (macOS does not provide an API to remove the app from these lists.)
        if let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(accessibility)
        }
        if let inputMonitoring = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring") {
            NSWorkspace.shared.open(inputMonitoring)
        }

        // 5. Quit the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}
