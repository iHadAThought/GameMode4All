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
        NSApp.windows.first { $0.title.contains("GameMode4All") }?.orderOut(nil)
    }
}

@main
struct GameMode4AllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var gameMode = GameModeController.shared
    @StateObject private var appStore = InstalledAppStore.shared
    @StateObject private var firstRunState = FirstRunState()

    var body: some Scene {
        WindowGroup("GameMode4All", id: "main") {
            Group {
                if firstRunState.hasCompletedFirstRun {
                    MainAppView()
                        .environmentObject(gameMode)
                        .environmentObject(appStore)
                        .environmentObject(firstRunState)
                } else {
                    SetupChecklistView(gameMode: gameMode, hasCompletedFirstRun: Binding(
                        get: { firstRunState.hasCompletedFirstRun },
                        set: { firstRunState.hasCompletedFirstRun = $0 }
                    ))
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

// MARK: - First run state (reopen setup from Settings)

private let kHasCompletedFirstRunSetup = "HasCompletedFirstRunSetup"

final class FirstRunState: ObservableObject {
    @Published var hasCompletedFirstRun: Bool {
        didSet { UserDefaults.standard.set(hasCompletedFirstRun, forKey: kHasCompletedFirstRunSetup) }
    }

    init() {
        self.hasCompletedFirstRun = UserDefaults.standard.bool(forKey: kHasCompletedFirstRunSetup)
    }
}
