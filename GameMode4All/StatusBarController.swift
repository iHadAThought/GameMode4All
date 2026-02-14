//
//  StatusBarController.swift
//  GameMode4All
//
//  AppKit status bar item so we can show a green icon when Game Mode is on.
//  SwiftUI MenuBarExtra does not respect custom icon colors in the menu bar.
//

import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?
    private let gameMode = GameModeController.shared

    private lazy var iconOff: NSImage? = {
        let img = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return img?.withSymbolConfiguration(config)
    }()

    private lazy var iconOn: NSImage? = {
        let img = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)
        let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: .systemGreen)
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let config = sizeConfig.applying(colorConfig)
        let tinted = img?.withSymbolConfiguration(config)
        tinted?.isTemplate = false
        return tinted
    }()

    override init() {
        super.init()
        setupMenu()
        updateIcon()
        cancellable = gameMode.$gameModeState
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                self?.updateMenuTitle()
            }
    }

    private func setupMenu() {
        statusItem.menu = NSMenu()
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let titleItem = NSMenuItem(
            title: gameModeStatusText,
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(
            title: "Open GameMode4All…",
            action: #selector(openMainWindow),
            keyEquivalent: ","
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit GameMode4All",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateMenuTitle() {
        statusItem.menu?.items.first?.title = gameModeStatusText
    }

    private var gameModeStatusText: String {
        if !gameMode.isGamePolicyCtlAvailable {
            return "Game Mode — Xcode required"
        }
        switch gameMode.gameModeState {
        case .on, .temporary: return "Game Mode: On"
        case .off: return "Game Mode: Off"
        case .unknown: return "Game Mode: —"
        }
    }

    private func updateIcon() {
        let isOn = (gameMode.gameModeState == .on || gameMode.gameModeState == .temporary)
        statusItem.button?.image = isOn ? iconOn : iconOff
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("GameMode4All") }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
