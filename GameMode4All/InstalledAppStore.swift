//
//  InstalledAppStore.swift
//  GameMode4All
//

import AppKit
import Foundation
import SwiftUI

private let selectedBundleIDsKey = "SelectedAppBundleIDsForGameMode"
private let crossOverFoldersKey = "CrossOverFolders"
private let crossOverFolderBookmarkKey = "CrossOverFolderBookmark"
private let crossOverFolderDisplayPathKey = "CrossOverFolderDisplayPath"

private struct CrossOverFolderEntry: Codable {
    let path: String
    let bookmarkBase64: String
}

final class InstalledAppStore: ObservableObject {
    static let shared = InstalledAppStore()

    @Published private(set) var installedApps: [InstalledApp] = []
    /// Apps found in all user-added CrossOver folders (shown in CrossOver section, not in main list).
    @Published private(set) var crossOverApps: [InstalledApp] = []
    @Published var selectedBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedBundleIDs), forKey: selectedBundleIDsKey)
        }
    }

    /// Paths of added CrossOver folders (for UI list).
    @Published private(set) var crossOverFolderPaths: [String] = []

    private var crossOverFolderEntries: [CrossOverFolderEntry] = [] {
        didSet {
            crossOverFolderPaths = crossOverFolderEntries.map(\.path)
            saveCrossOverFolders()
        }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: selectedBundleIDsKey) ?? []
        self.selectedBundleIDs = Set(saved)
        loadCrossOverFolders()
    }

    private func loadCrossOverFolders() {
        if let data = UserDefaults.standard.data(forKey: crossOverFoldersKey),
           let decoded = try? JSONDecoder().decode([CrossOverFolderEntry].self, from: data) {
            crossOverFolderEntries = decoded
            crossOverFolderPaths = decoded.map(\.path)
            return
        }
        // Migrate from legacy single-folder keys
        if let bookmarkData = UserDefaults.standard.data(forKey: crossOverFolderBookmarkKey),
           let path = UserDefaults.standard.string(forKey: crossOverFolderDisplayPathKey) {
            let entry = CrossOverFolderEntry(path: path, bookmarkBase64: bookmarkData.base64EncodedString())
            crossOverFolderEntries = [entry]
            crossOverFolderPaths = [path]
            UserDefaults.standard.removeObject(forKey: crossOverFolderBookmarkKey)
            UserDefaults.standard.removeObject(forKey: crossOverFolderDisplayPathKey)
            saveCrossOverFolders()
        }
    }

    private func saveCrossOverFolders() {
        guard let data = try? JSONEncoder().encode(crossOverFolderEntries) else { return }
        UserDefaults.standard.set(data, forKey: crossOverFoldersKey)
    }

    func loadApps() {
        installedApps = InstalledAppsProvider.loadInstalledApplications(extraFolders: nil)

        var urls: [URL] = []
        for entry in crossOverFolderEntries {
            guard let bookmarkData = Data(base64Encoded: entry.bookmarkBase64) else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                urls.append(url)
            }
        }
        defer { urls.forEach { $0.stopAccessingSecurityScopedResource() } }
        crossOverApps = urls.isEmpty ? [] : InstalledAppsProvider.loadApplications(fromFolders: urls)
    }

    /// Presents an open panel to add a CrossOver applications folder. Call from main thread.
    func addCrossOverFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose CrossOver Applications Folder"
        panel.message = "Select a folder that contains your CrossOver launchers (e.g. Steam, Roberts Space Industries). You can add more than one folder."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let entry = CrossOverFolderEntry(path: url.path, bookmarkBase64: bookmark.base64EncodedString())
            if !crossOverFolderEntries.contains(where: { $0.path == url.path }) {
                crossOverFolderEntries.append(entry)
            }
            loadApps()
        } catch {
            // Could show an alert
        }
    }

    func removeCrossOverFolder(at index: Int) {
        guard index >= 0, index < crossOverFolderEntries.count else { return }
        crossOverFolderEntries.remove(at: index)
        loadApps()
    }

    func isSelected(_ app: InstalledApp) -> Bool {
        selectedBundleIDs.contains(app.bundleID)
    }

    func toggleSelection(_ app: InstalledApp) {
        if selectedBundleIDs.contains(app.bundleID) {
            selectedBundleIDs.remove(app.bundleID)
        } else {
            selectedBundleIDs.insert(app.bundleID)
        }
    }
}
