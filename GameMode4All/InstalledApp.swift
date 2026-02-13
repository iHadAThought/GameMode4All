//
//  InstalledApp.swift
//  GameMode4All
//

import AppKit

/// Represents an installed application discovered under /Applications or ~/Applications.
struct InstalledApp: Identifiable, Hashable {
    let id: String
    let bundleID: String
    let name: String
    let path: String
    let icon: NSImage?

    init(bundleID: String, name: String, path: String, icon: NSImage?) {
        self.id = bundleID
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.icon = icon
    }

    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.bundleID == rhs.bundleID }
}
