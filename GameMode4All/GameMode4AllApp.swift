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

    var body: some Scene {
        WindowGroup("Game Mode for All", id: "main") {
            MainAppView()
                .environmentObject(gameMode)
                .environmentObject(appStore)
        }
        .defaultSize(width: 480, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(gameMode)
                .environmentObject(appStore)
        } label: {
            Image(systemName: "gamecontroller.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
