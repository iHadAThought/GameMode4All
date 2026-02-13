//
//  MenuBarMenuView.swift
//  GameMode4All
//

import SwiftUI

struct MenuBarMenuView: View {
    @EnvironmentObject private var gameMode: GameModeController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if !gameMode.isGamePolicyCtlAvailable {
                Text("Game Mode — Xcode required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(gameModeStatusText)
                    .font(.caption)
            }

            Divider()

            Button("Open Game Mode Settings…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Game Mode for All") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            gameMode.refreshStatus()
        }
    }

    private var gameModeStatusText: String {
        switch gameMode.gameModeState {
        case .on, .temporary:
            return "Game Mode: On"
        case .off:
            return "Game Mode: Off"
        case .unknown:
            return "Game Mode: —"
        }
    }
}
