//
//  SettingsPaneView.swift
//  GameMode4All
//
//  System Settings–style pane: list of installed apps with checkboxes to enable Game Mode when launched.
//

import AppKit
import SwiftUI

struct SettingsPaneView: View {
    @EnvironmentObject private var gameMode: GameModeController
    @EnvironmentObject private var appStore: InstalledAppStore
    @State private var searchText = ""
    @State private var isLoading = true

    var body: some View {
        Form {
            Section {
                GameModeStatusRow(
                    isAvailable: gameMode.isGamePolicyCtlAvailable,
                    gameModeState: gameMode.gameModeState,
                    policyState: gameMode.policyState
                )
            } header: {
                SectionHeaderView(title: "Status", help: "Current Game Mode and policy status.")
            }

            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading applications…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else if filteredApps.isEmpty {
                    Text("No applications found.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredApps, id: \.bundleID) { app in
                                AppRowView(
                                    app: app,
                                    isSelected: appStore.isSelected(app),
                                    onToggle: { appStore.toggleSelection(app) }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 280)
                }
            } header: {
                SectionHeaderView(title: "Enable Game Mode when these apps launch", help: "Selected apps turn on Game Mode when full screen and frontmost (same as Apple); it turns off when you switch away. To detect fullscreen, add this app in System Settings → Privacy & Security → Accessibility. Requires Xcode (for gamepolicyctl) and Apple Silicon.")
            }

            Section {
                if !appStore.crossOverFolderPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appStore.crossOverFolderPaths, id: \.self) { path in
                            HStack {
                                Text(path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    if let index = appStore.crossOverFolderPaths.firstIndex(of: path) {
                                        appStore.removeCrossOverFolder(at: index)
                                    }
                                }
                            }
                        }
                        Button("Add CrossOver applications folder…") { appStore.addCrossOverFolder() }
                        if appStore.crossOverApps.isEmpty {
                            Text("No applications found in the added folders.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(appStore.crossOverApps, id: \.bundleID) { app in
                                        CrossOverAppRowView(
                                            app: app,
                                            appStore: appStore,
                                            gameMode: gameMode
                                        )
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(height: 280)
                        }
                    }
                } else {
                    Button("Add CrossOver applications folder…") { appStore.addCrossOverFolder() }
                }
            } header: {
                SectionHeaderView(title: "CrossOver (CodeWeavers)", help: "If CrossOver games (e.g. Risk of Rain 2, Steam) don't appear above, click \"Add CrossOver applications folder…\" and choose the CrossOver folder (e.g. in your Applications folder). Applications in that folder appear in the list below; select them to enable Game Mode when CrossOver is frontmost. Opening a CrossOver game launches CrossOver first.")
            }

            Section {
                if let url = gameMode.debugLogFileURL {
                    HStack {
                        Text(url.path)
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open debug log") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                SectionHeaderView(title: "Debug", help: "If Game Mode doesn't turn on, open the debug log after reproducing the issue (e.g. select an app, put it fullscreen) and share the last lines to diagnose. The log records frontmost app, fullscreen detection, and policy changes.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Game Mode for All")
        .searchable(text: $searchText, prompt: "Search applications")
        .onAppear {
            gameMode.refreshStatus()
            gameMode.startObservingAppLaunches()
            loadApps()
        }
        .onDisappear {
            gameMode.refreshStatus()
        }
    }

    private var filteredApps: [InstalledApp] {
        if searchText.isEmpty { return appStore.installedApps }
        return appStore.installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadApps() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let _ = InstalledAppsProvider.loadInstalledApplications()
            DispatchQueue.main.async {
                appStore.loadApps()
                isLoading = false
            }
        }
    }
}

// MARK: - CrossOver app row with process names under it

private struct CrossOverAppRowView: View {
    let app: InstalledApp
    @ObservedObject var appStore: InstalledAppStore
    @ObservedObject var gameMode: GameModeController
    @State private var newProcessName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppRowView(
                app: app,
                isSelected: appStore.isSelected(app),
                onToggle: { appStore.toggleSelection(app) }
            )
            VStack(alignment: .leading, spacing: 4) {
                ForEach(gameMode.processNames(forApp: app.bundleID), id: \.self) { name in
                    HStack {
                        Text(name)
                            .font(.caption)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            gameMode.removeProcessName(name, forApp: app.bundleID)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.leading, 34)
                }
                HStack(spacing: 6) {
                    TextField("Process name (e.g. helldivers2.exe)", text: $newProcessName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.leading, 34)
                    Button("Add") {
                        gameMode.addProcessName(newProcessName, forApp: app.bundleID)
                        newProcessName = ""
                    }
                    .disabled(newProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Section header with help tooltip

private struct SectionHeaderView: View {
    let title: String
    let help: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .background(TooltipBackground(tooltip: help))
        }
    }
}

// Native AppKit tooltip for reliable hover on macOS (SwiftUI .help can be unreliable in Form headers).
private struct TooltipBackground: NSViewRepresentable {
    let tooltip: String

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.toolTip = tooltip
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = tooltip
    }
}

// MARK: - Status row

private struct GameModeStatusRow: View {
    let isAvailable: Bool
    let gameModeState: GameModeController.GameModeState
    let policyState: GameModeController.PolicyState

    var body: some View {
        if !isAvailable {
            Label("Game Mode control unavailable (install Xcode for gamepolicyctl)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            HStack {
                Label(statusText, systemImage: statusIcon)
                Spacer()
                Text(modeText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch gameModeState {
        case .on: return "Game Mode is on"
        case .off: return "Game Mode is off"
        case .temporary: return "Game Mode is on (temporary)"
        case .unknown: return "Game Mode status unknown"
        }
    }

    private var statusIcon: String {
        switch gameModeState {
        case .on, .temporary: return "gamecontroller.fill"
        case .off: return "gamecontroller"
        case .unknown: return "questionmark.circle"
        }
    }

    private var modeText: String {
        switch policyState {
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        case .unknown: return "—"
        }
    }
}

// MARK: - App row with icon and checkbox

private struct AppRowView: View {
    let app: InstalledApp
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.body)
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsPaneView()
        .environmentObject(GameModeController.shared)
        .environmentObject(InstalledAppStore.shared)
        .frame(width: 420, height: 500)
}
