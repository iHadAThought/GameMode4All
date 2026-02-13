//
//  GameMode4AllApp.swift
//  GameMode4All
//
//  macOS app: System Settings–style pane to select apps that enable Game Mode when launched.
//

import SwiftUI

@main
struct GameMode4AllApp: App {
    @StateObject private var gameMode = GameModeController.shared
    @StateObject private var appStore = InstalledAppStore.shared

    var body: some Scene {
        Settings {
            SettingsPaneView()
                .environmentObject(gameMode)
                .environmentObject(appStore)
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
