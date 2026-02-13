//
//  GameMode4AllApp.swift
//  GameMode4All
//
//  macOS app: enable Game Mode for any app when fullscreen and frontmost.
//

import SwiftUI

@main
struct GameMode4AllApp: App {
    @StateObject private var gameMode = GameModeController.shared
    @StateObject private var appStore = InstalledAppStore.shared
    @StateObject private var scrollPrefs = ScrollPreferences.shared
    @AppStorage("HasCompletedFirstRunSetup") private var hasCompletedFirstRun = false

    var body: some Scene {
        WindowGroup("Game Mode for All", id: "main") {
            Group {
                if hasCompletedFirstRun {
                    MainAppView()
                        .environmentObject(gameMode)
                        .environmentObject(appStore)
                        .environmentObject(scrollPrefs)
                } else {
                    SetupChecklistView(gameMode: gameMode, hasCompletedFirstRun: $hasCompletedFirstRun)
                }
            }
            .environmentObject(gameMode)
            .environmentObject(appStore)
            .environmentObject(scrollPrefs)
        }
        .defaultSize(width: 480, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(gameMode)
                .environmentObject(appStore)
                .environmentObject(scrollPrefs)
        } label: {
            Image(systemName: "gamecontroller.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
