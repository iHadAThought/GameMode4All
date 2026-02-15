//
//  GameModeHotKeyManager.swift
//  GameMode4All
//
//  Registers a global hotkey to sync Game Mode based on the frontmost fullscreen app.
//

import AppKit
import Foundation

private let hotKeyEnabledKey = "GameModeHotKeyEnabled"
private let hotKeyCodeKey = "GameModeHotKeyCode"
private let hotKeyModifiersKey = "GameModeHotKeyModifiers"

// Default: ⌘⇧G
private let defaultKeyCode: UInt16 = 5  // kVK_ANSI_G
private let defaultModifiers: UInt = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue

@MainActor
final class GameModeHotKeyManager: ObservableObject {
    static let shared = GameModeHotKeyManager()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: hotKeyEnabledKey)
            updateMonitor()
        }
    }

    @Published var shortcutDisplay: String = "⌘⇧G"
    @Published var isRecording: Bool = false

    private var globalMonitor: Any?
    private var recordingMonitor: Any?

    private var keyCode: UInt16 {
        let stored = UserDefaults.standard.object(forKey: hotKeyCodeKey) as? Int
        return stored.map { UInt16($0) } ?? defaultKeyCode
    }

    private var modifiers: UInt {
        let stored = UserDefaults.standard.object(forKey: hotKeyModifiersKey) as? UInt
        return stored ?? defaultModifiers
    }

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: hotKeyEnabledKey)
        updateShortcutDisplay()
    }

    func start() {
        updateMonitor()
    }

    /// Saves the given key combo and updates the monitor. Call after user records a shortcut.
    func setShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let deviceIndependent = modifiers.intersection(.deviceIndependentFlagsMask)
        UserDefaults.standard.set(Int(keyCode), forKey: hotKeyCodeKey)
        UserDefaults.standard.set(deviceIndependent.rawValue, forKey: hotKeyModifiersKey)
        updateShortcutDisplay()
        updateMonitor()
    }

    /// Enters recording mode: the next key press (global) becomes the shortcut. Call from main thread.
    func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        recordingMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.isRecording = false
                NSEvent.removeMonitor(self.recordingMonitor!)
                self.recordingMonitor = nil

                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.setShortcut(keyCode: event.keyCode, modifiers: mods)
            }
        }
    }

    /// Cancels recording. Call if user dismisses without pressing a key.
    func cancelRecording() {
        guard isRecording, let mon = recordingMonitor else { return }
        isRecording = false
        NSEvent.removeMonitor(mon)
        recordingMonitor = nil
    }

    private func updateShortcutDisplay() {
        shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        var parts: [String] = []
        let m = NSEvent.ModifierFlags(rawValue: modifiers)
        if m.contains(.command) { parts.append("⌘") }
        if m.contains(.shift) { parts.append("⇧") }
        if m.contains(.option) { parts.append("⌥") }
        if m.contains(.control) { parts.append("⌃") }
        if let char = keyCodeToCharacter(keyCode) {
            parts.append(String(char))
        } else {
            parts.append("Key \(keyCode)")
        }
        return parts.joined()
    }

    private func keyCodeToCharacter(_ code: UInt16) -> Character? {
        let map: [UInt16: Character] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↵",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "␣",
            50: "⌫", 53: "⎋"
        ]
        return map[code]
    }

    private func updateMonitor() {
        if let mon = globalMonitor {
            NSEvent.removeMonitor(mon)
            globalMonitor = nil
        }

        guard isEnabled else { return }

        let kc = keyCode
        let mods = modifiers

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            if event.keyCode == kc && eventMods == mods {
                Task { @MainActor in
                    GameModeController.shared.syncGameModeForFrontmostApp()
                }
            }
        }
    }
}
