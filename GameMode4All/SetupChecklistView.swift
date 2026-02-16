//
//  SetupChecklistView.swift
//  GameMode4All
//
//  First-run checklist: Xcode/CLI, accessibility.
//

import ApplicationServices
import AppKit
import SwiftUI

struct SetupChecklistView: View {
    @ObservedObject var gameMode: GameModeController
    @Binding var hasCompletedFirstRun: Bool
    @State private var accessibilityEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Setup")
                .font(.title.weight(.semibold))
            Text("Complete these steps so GameMode4All can run correctly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                checklistRow(
                    checked: gameMode.isGamePolicyCtlAvailable,
                    title: "Xcode or Command Line Tools",
                    subtitle: "Required for Game Mode control."
                ) {
                    installCommandLineTools()
                }
                checklistRow(
                    checked: accessibilityEnabled,
                    title: "Accessibility",
                    subtitle: "Optional: detect fullscreen for “match Apple” behavior."
                ) {
                    openAccessibilitySettings()
                }
            }

            Spacer(minLength: 20)
            Button("Continue") {
                hasCompletedFirstRun = true
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 380)
        .onAppear {
            gameMode.refreshStatus()
            refreshAccessibilityStatus()
        }
    }

    private func checklistRow(
        checked: Bool,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(checked ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !checked {
                    Button(buttonTitle(for: title)) { action() }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func buttonTitle(for title: String) -> String {
        switch title {
        case "Xcode or Command Line Tools": return "Install Command Line Tools"
        case "Accessibility": return "Open Accessibility Settings"
        default: return "Open Settings"
        }
    }

    private func installCommandLineTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcode-select", "--install"]
        try? process.run()
        // Dialog appears; user installs. Refresh status when they return.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { gameMode.refreshStatus() }
    }

    private func refreshAccessibilityStatus() {
        let trustedByAPI = AXIsProcessTrustedWithOptions(nil)
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            // No frontmost app, or we're frontmost (setup window): only trust the API. Querying our own app can succeed without Accessibility.
            accessibilityEnabled = trustedByAPI
            return
        }
        // Another app is frontmost: probe by querying its windows. If we get -25211 we're not in Accessibility.
        let denied = accessibilityReturnsAPIDisabled()
        accessibilityEnabled = trustedByAPI || !denied
    }

    /// Returns true if our process gets kAXErrorAPIDisabled (-25211) when querying the frontmost app's windows.
    private func accessibilityReturnsAPIDisabled() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return true }
        let appRef = AXUIElementCreateApplication(frontmost.processIdentifier)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
        return err.rawValue == -25211 // kAXErrorAPIDisabled
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        // User may add the app and return; refresh after a delay when window regains focus if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshAccessibilityStatus() }
    }

}
