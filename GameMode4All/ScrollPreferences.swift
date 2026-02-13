//
//  ScrollPreferences.swift
//  GameMode4All
//
//  From ScrollSplit: natural scrolling preferences and sync with system when not using separate mode.
//

import Foundation
import SwiftUI

private let kSeparateNaturalScroll = "separateNaturalScroll"
private let kTrackpadNatural = "trackpadNatural"
private let kMouseNatural = "mouseNatural"
private let kGlobalNatural = "globalNatural"

private let systemScrollKey = "com.apple.swipescrolldirection"

/// Manages natural scrolling preferences and syncs with system when not using separate mode.
final class ScrollPreferences: ObservableObject {
    static let shared = ScrollPreferences()

    @AppStorage(kSeparateNaturalScroll) var separateNaturalScroll: Bool = false {
        didSet { apply() }
    }

    @AppStorage(kTrackpadNatural) var trackpadNatural: Bool = true {
        didSet { apply() }
    }

    @AppStorage(kMouseNatural) var mouseNatural: Bool = false {
        didSet { apply() }
    }

    /// Used when separate mode is OFF — single natural scrolling for both.
    @AppStorage(kGlobalNatural) var globalNatural: Bool = true {
        didSet { apply() }
    }

    private init() {
        loadSystemNatural()
        apply()
    }

    /// Read current system natural scrolling (for initial sync when opening prefs).
    func loadSystemNatural() {
        let domain = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain") ?? [:]
        if let value = domain[systemScrollKey] as? Bool {
            globalNatural = value
        }
    }

    func apply() {
        if separateNaturalScroll {
            setSystemNatural(false)
            ScrollManager.shared.isEnabled = true
            ScrollManager.shared.trackpadNatural = trackpadNatural
            ScrollManager.shared.mouseNatural = mouseNatural
        } else {
            ScrollManager.shared.isEnabled = false
            setSystemNatural(globalNatural)
        }
    }

    private func setSystemNatural(_ natural: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "NSGlobalDomain", systemScrollKey, "-bool", natural ? "true" : "false"]
        try? task.run()
        task.waitUntilExit()
    }
}
