//
//  InstalledAppsProvider.swift
//  GameMode4All
//
//  Enumerates installed applications from /Applications, ~/Applications,
//  and CrossOver (CodeWeavers) launchers in ~/Applications/Crossover (or CrossOver).
//  In a sandboxed app, we must use the real user home (getpwuid) to reach ~/Applications;
//  homeDirectoryForCurrentUser points at the container and would miss CrossOver launchers.
//

import AppKit
import Foundation

import Darwin

enum InstalledAppsProvider {
    /// Real user home directory (e.g. /Users/username). In sandbox, homeDirectoryForCurrentUser is the container, so we use getpwuid to get the actual home for ~/Applications and CrossOver.
    private static func realUserHomeDirectory() -> String? {
        guard let pw = getpwuid(getuid()) else { return nil }
        return String(cString: pw.pointee.pw_dir)
    }

    private static let searchPaths: [URL] = {
        let fm = FileManager.default
        let realHome = realUserHomeDirectory()
        var paths: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.urls(for: .applicationDirectory, in: .localDomainMask).first,
        ].compactMap { $0 }

        // User's Applications and CrossOver: use real home so sandboxed app sees ~/Applications (entitlement allows read).
        if let home = realHome {
            paths.append(URL(fileURLWithPath: "\(home)/Applications", isDirectory: true))
            // CrossOver (CodeWeavers) stores launchers here; may be "CrossOver" or "Crossover" and nested (e.g. Steam/, Roberts Space Industries/).
            paths.append(URL(fileURLWithPath: "\(home)/Applications/CrossOver", isDirectory: true))
            paths.append(URL(fileURLWithPath: "\(home)/Applications/Crossover", isDirectory: true))
        }

        // Fallback if getpwuid failed (e.g. rare env): include standard user Applications URL
        if realHome == nil, let fallback = fm.urls(for: .applicationDirectory, in: .userDomainMask).first {
            paths.append(fallback)
        }

        // Optional: custom CrossOver bottle directory (user may have moved it)
        if let bottleDir = InstalledAppsProvider.crossOverBottleDir(), !bottleDir.isEmpty {
            let expanded = (bottleDir as NSString).expandingTildeInPath
            let customBottle = URL(fileURLWithPath: expanded)
            if fm.fileExists(atPath: customBottle.path) {
                paths.append(customBottle)
            }
        }

        return paths
    }()

    /// Recursively finds all .app bundles under the given directory (e.g. /Applications/Adobe/Acrobat.app or ~/Applications/CrossOver/Steam/Game.app).
    static func findAppBundles(in directory: URL, depth: Int = 0, maxDepth: Int = 4) -> [URL] {
        guard depth <= maxDepth else { return [] }
        let fm = FileManager.default
        var apps: [URL] = []

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for url in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if url.pathExtension == "app" && isDir.boolValue {
                apps.append(url)
            } else if isDir.boolValue && depth < maxDepth {
                apps.append(contentsOf: findAppBundles(in: url, depth: depth + 1, maxDepth: maxDepth))
            }
        }

        return apps
    }

    /// Loads only apps from the given folders (e.g. user-added CrossOver folder). Use for a separate CrossOver list.
    static func loadApplications(fromFolders folders: [URL]) -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for folderURL in folders {
            result.append(contentsOf: enumerateCrossOverApps(at: folderURL, seen: &seen))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns a list of installed applications. Excludes CrossOver apps (those appear only in the CrossOver section when the user adds the folder).
    static func loadInstalledApplications(extraFolders: [URL]? = nil) -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []

        for baseURL in searchPaths {
            let pathLower = baseURL.path.lowercased()
            if pathLower.contains("crossover") { continue }

            guard FileManager.default.fileExists(atPath: baseURL.path) else { continue }
            for appURL in findAppBundles(in: baseURL) {
                if let app = makeInstalledApp(from: appURL, seen: &seen) {
                    result.append(app)
                }
            }
        }

        // Exclude CrossOver apps (from ~/Applications/CrossOver, bottle dir, etc.) — they appear only in the CrossOver section
        result = result.filter { !$0.path.lowercased().contains("crossover") }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Enumerates .app bundles under a CrossOver launcher folder using DirectoryEnumerator (more reliable under sandbox).
    private static func enumerateCrossOverApps(at directoryURL: URL, seen: inout Set<String>) -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [InstalledApp] = []

        guard fm.fileExists(atPath: directoryURL.path),
              let enumerator = fm.enumerator(
                  at: directoryURL,
                  includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                  options: [.skipsHiddenFiles],
                  errorHandler: nil
              ) else { return apps }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "app" else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }

            if let app = makeInstalledApp(from: url, seen: &seen) {
                apps.append(app)
            }
        }

        return apps
    }

    /// Builds an InstalledApp from a .app URL; uses path-based id if bundle has no bundleIdentifier (e.g. some launchers). Returns nil if already in seen.
    private static func makeInstalledApp(from appURL: URL, seen: inout Set<String>) -> InstalledApp? {
        let bundle = Bundle(url: appURL)
        let bundleID: String = (bundle?.bundleIdentifier).flatMap { $0.isEmpty ? nil : $0 }
            ?? "path:\(appURL.path)"
        guard !seen.contains(bundleID) else { return nil }
        seen.insert(bundleID)

        let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        return InstalledApp(
            bundleID: bundleID,
            name: name,
            path: appURL.path,
            icon: icon
        )
    }

    /// Reads CrossOver's custom BottleDir from its preference domain, if set.
    private static func crossOverBottleDir() -> String? {
        let key = "BottleDir" as CFString
        let domain = "com.codeweavers.CrossOver" as CFString
        guard let value = CFPreferencesCopyAppValue(key, domain) else { return nil }
        return (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
