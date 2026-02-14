//
//  GameMode4AllApp.swift
//  GameMode4All
//
//  macOS app: enable Game Mode for any app when fullscreen and frontmost.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GameModeController.shared.refreshStatus()
        statusBarController = StatusBarController()
        // Don't show the main window at launch (e.g. when starting at login) — only the menu bar icon.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.hideMainWindow()
        }
    }

    private func hideMainWindow() {
        NSApp.windows.first { $0.title.contains("Game Mode") }?.orderOut(nil)
    }
}

@main
struct GameMode4AllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var gameMode = GameModeController.shared
    @StateObject private var appStore = InstalledAppStore.shared
    @AppStorage("HasCompletedFirstRunSetup") private var hasCompletedFirstRun = false

    var body: some Scene {
        WindowGroup("Game Mode for All", id: "main") {
            Group {
                if hasCompletedFirstRun {
                    MainAppView()
                        .environmentObject(gameMode)
                        .environmentObject(appStore)
                } else {
                    SetupChecklistView(gameMode: gameMode, hasCompletedFirstRun: $hasCompletedFirstRun)
                }
            }
            .environmentObject(gameMode)
            .environmentObject(appStore)
        }
        .defaultSize(width: 480, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
