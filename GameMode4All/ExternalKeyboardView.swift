//
//  ExternalKeyboardView.swift
//  GameMode4All
//
//  KeySwap integration: swap Command (⌘) and Option (⌥) on external keyboards.
//

import SwiftUI

private let keySwapLaunchAgentLabel = "com.gamemode4all.keyswap"

struct ExternalKeyboardView: View {
    @StateObject private var keyboardManager = KeyboardManager()
    @State private var selectedKeyboard: KeyboardDevice?
    @State private var swapEnabled = false
    @State private var applyAtLogin = false

    private var externalKeyboards: [KeyboardDevice] {
        keyboardManager.keyboards.filter { !$0.isBuiltIn }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if keyboardManager.isRefreshing {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Detecting keyboards…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if externalKeyboards.isEmpty {
                Text("No external keyboard detected.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(externalKeyboards) { kb in
                    ExternalKeyboardRow(
                        keyboard: kb,
                        isSelected: selectedKeyboard?.id == kb.id,
                        swapEnabled: selectedKeyboard?.id == kb.id ? swapEnabled : false,
                        onSelect: {
                            selectedKeyboard = kb
                            swapEnabled = false
                        },
                        onSwapToggle: { enabled in
                            swapEnabled = enabled
                            applySwap(for: kb, enabled: enabled)
                        }
                    )
                }
            }

            if let err = keyboardManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Apply at login")
                Spacer()
                Toggle("Apply at login", isOn: $applyAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: applyAtLogin) { _, newValue in
                        if newValue { installLaunchAgent() }
                        else { removeLaunchAgent() }
                    }
                    .onChange(of: selectedKeyboard?.id) { _, _ in
                        if applyAtLogin, selectedKeyboard != nil { installLaunchAgent() }
                    }
            }
            .padding(.top, 4)
            Text("Re-apply the swap when you log in (recommended for external keyboards).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadApplyAtLoginState()
        }
    }

    private func applySwap(for keyboard: KeyboardDevice, enabled: Bool) {
        _ = keyboardManager.setSwapCommandOption(enabled, for: keyboard)
    }

    private func loadApplyAtLoginState() {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(keySwapLaunchAgentLabel).plist")
        applyAtLogin = FileManager.default.fileExists(atPath: plistPath.path)
    }

    private func installLaunchAgent() {
        guard let keyboard = selectedKeyboard else {
            applyAtLogin = false
            keyboardManager.lastError = "Select an external keyboard first."
            return
        }
        let agentDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let plistPath = agentDir.appendingPathComponent("\(keySwapLaunchAgentLabel).plist")
        do {
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            let mapping = KeyboardManager.swapCommandOptionMappingForLaunchAgent()
            let json = KeyboardManager.userKeyMappingJSONForLaunchAgent(mapping)
            let match = keyboard.hidMatchJSON
            let plist: [String: Any] = [
                "Label": keySwapLaunchAgentLabel,
                "ProgramArguments": [
                    "/usr/bin/hidutil",
                    "property",
                    "--match", match,
                    "--set", json,
                ],
                "RunAtLoad": true,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistPath)
            keyboardManager.lastError = nil
        } catch {
            keyboardManager.lastError = "Could not install login item: \(error.localizedDescription)"
        }
    }

    private func removeLaunchAgent() {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(keySwapLaunchAgentLabel).plist")
        try? FileManager.default.removeItem(at: plistPath)
    }
}

// MARK: - Row

private struct ExternalKeyboardRow: View {
    let keyboard: KeyboardDevice
    let isSelected: Bool
    let swapEnabled: Bool
    let onSelect: () -> Void
    let onSwapToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(keyboard.name).font(.body)
                        Text("Vendor \(keyboard.vendorID) · Product \(keyboard.productID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isSelected {
                Toggle("Swap ⌘ and ⌥", isOn: Binding(get: { swapEnabled }, set: { onSwapToggle($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}
