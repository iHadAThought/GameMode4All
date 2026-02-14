//
//  UninstallHelper.swift
//  GameMode4All
//
//  Removes app data and opens System Settings so the user can remove
//  the app from Accessibility. Cannot remove privacy permissions programmatically.
//

import AppKit
import Foundation

enum UninstallHelper {
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

    /// Performs uninstall: removes configurations and user data; opens Accessibility; then terminates.
    static func performUninstall() {
        let fm = FileManager.default

        // 1. Clear UserDefaults (app preferences and state)
        let defaults = UserDefaults.standard
        for key in userDefaultsKeysToRemove {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        // 2. Remove Application Support data (e.g. GameMode4All debug log folder)
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let gameModeFolder = appSupport.appendingPathComponent("GameMode4All", isDirectory: true)
            try? fm.removeItem(at: gameModeFolder)
        }

        // 3. Open System Settings so user can remove app from Accessibility
        if let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(accessibility)
        }

        // 4. Quit the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}
