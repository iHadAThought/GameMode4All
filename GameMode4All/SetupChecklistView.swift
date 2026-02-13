//
//  SetupChecklistView.swift
//  GameMode4All
//
//  First-run checklist: Xcode/CLI, notifications, accessibility.
//

import ApplicationServices
import AppKit
import SwiftUI
import UserNotifications

struct SetupChecklistView: View {
    @ObservedObject var gameMode: GameModeController
    @Binding var hasCompletedFirstRun: Bool
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var accessibilityEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Setup")
                .font(.title.weight(.semibold))
            Text("Complete these steps so Game Mode for All can run correctly.")
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
                    checked: notificationStatus == .authorized,
                    title: "Notifications",
                    subtitle: "Optional: get notified when Game Mode turns on or off."
                ) {
                    requestOrOpenNotificationSettings()
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
            refreshNotificationStatus()
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
        case "Notifications": return notificationStatus == .denied ? "Open System Settings" : "Enable Notifications"
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

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { notificationStatus = settings.authorizationStatus }
        }
    }

    private func requestOrOpenNotificationSettings() {
        if notificationStatus == .denied {
            openNotificationSettings()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async { refreshNotificationStatus() }
        }
    }

    private func openNotificationSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshAccessibilityStatus() {
        // AXIsProcessTrustedWithOptions can be false even when the app is in Accessibility (e.g. after rebuild).
        // Fallback: try the same AX call we use for fullscreen; if we don't get -25211 (APIDisabled), we have access.
        let trustedByAPI = AXIsProcessTrustedWithOptions(nil)
        let trustedByProbe = !accessibilityReturnsAPIDisabled()
        accessibilityEnabled = trustedByAPI || trustedByProbe
    }

    /// Returns true if our process gets kAXErrorAPIDisabled (-25211) when querying another app. Means we're not in Accessibility.
    private func accessibilityReturnsAPIDisabled() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
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
