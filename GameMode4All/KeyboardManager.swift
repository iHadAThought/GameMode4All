//
//  KeyboardManager.swift
//  GameMode4All
//
//  From KeySwap: enumerates HID keyboards and applies Command/Option swap via hidutil.
//

import Foundation
import IOKit
import IOKit.hid

/// Enumerates HID keyboards and applies Command/Option swap via hidutil (device-specific when possible).
final class KeyboardManager: ObservableObject {
    @Published private(set) var keyboards: [KeyboardDevice] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    private let builtInVendorID = 0x05AC // Apple Inc.

    init() {
        refreshKeyboards()
    }

    func refreshKeyboards() {
        isRefreshing = true
        lastError = nil
        keyboards = Self.enumerateKeyboards(builtInVendorID: builtInVendorID)
        isRefreshing = false
    }

    /// Swap Command and Option for the given keyboard (nil = all keyboards).
    func setSwapCommandOption(_ enabled: Bool, for keyboard: KeyboardDevice?) -> Bool {
        lastError = nil
        let mapping = enabled ? Self.swapCommandOptionMapping() : []
        let json = Self.userKeyMappingJSON(mapping)

        if let kb = keyboard {
            return runHidUtil(set: json, match: kb.hidMatchJSON)
        } else {
            return runHidUtil(set: json, match: nil)
        }
    }

    /// Clear any remapping for the given keyboard (or all).
    func clearRemapping(for keyboard: KeyboardDevice?) -> Bool {
        lastError = nil
        let json = Self.userKeyMappingJSON([])
        if let kb = keyboard {
            return runHidUtil(set: json, match: kb.hidMatchJSON)
        } else {
            return runHidUtil(set: json, match: nil)
        }
    }

    private func runHidUtil(set json: String, match: String?) -> Bool {
        let args: [String] = {
            var a = ["property", "--set", json]
            if let m = match, !m.isEmpty {
                a.insert(contentsOf: ["--match", m], at: 1)
            }
            return a
        }()
        let result = runProcess(executable: "/usr/bin/hidutil", arguments: args)
        if !result.success, let err = result.stderr, !err.isEmpty {
            lastError = err.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result.success
    }

    private func runProcess(executable path: String, arguments: [String]) -> (success: Bool, stdout: String?, stderr: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outData, encoding: .utf8)
            let stderr = String(data: errData, encoding: .utf8)
            return (process.terminationStatus == 0, stdout, stderr)
        } catch {
            lastError = error.localizedDescription
            return (false, nil, nil)
        }
    }

    /// Call during setup so the app is added to Input Monitoring (required for External Keyboard).
    /// Does not need the result; the HID access itself triggers the system to add the app to the list.
    static func triggerInputMonitoringPrompt() {
        _ = enumerateKeyboards(builtInVendorID: 0x05AC)
    }

    // MARK: - Static helpers (including for Launch Agent)

    private static let leftAlt    = 0x7000000E2
    private static let leftGUI    = 0x7000000E3
    private static let rightAlt   = 0x7000000E6
    private static let rightGUI   = 0x7000000E7

    private static func swapCommandOptionMapping() -> [[String: Int]] {
        [
            ["HIDKeyboardModifierMappingSrc": leftAlt,  "HIDKeyboardModifierMappingDst": leftGUI],
            ["HIDKeyboardModifierMappingSrc": leftGUI,  "HIDKeyboardModifierMappingDst": leftAlt],
            ["HIDKeyboardModifierMappingSrc": rightAlt, "HIDKeyboardModifierMappingDst": rightGUI],
            ["HIDKeyboardModifierMappingSrc": rightGUI, "HIDKeyboardModifierMappingDst": rightAlt],
        ]
    }

    private static func userKeyMappingJSON(_ mapping: [[String: Int]]) -> String {
        let items = mapping.map { m in
            let src = m["HIDKeyboardModifierMappingSrc"]!
            let dst = m["HIDKeyboardModifierMappingDst"]!
            return "{\"HIDKeyboardModifierMappingSrc\":\(src),\"HIDKeyboardModifierMappingDst\":\(dst)}"
        }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    /// For Launch Agent plist: same mapping as swapCommandOptionMapping.
    static func swapCommandOptionMappingForLaunchAgent() -> [[String: Int]] {
        [
            ["HIDKeyboardModifierMappingSrc": 0x7000000E2, "HIDKeyboardModifierMappingDst": 0x7000000E3],
            ["HIDKeyboardModifierMappingSrc": 0x7000000E3, "HIDKeyboardModifierMappingDst": 0x7000000E2],
            ["HIDKeyboardModifierMappingSrc": 0x7000000E6, "HIDKeyboardModifierMappingDst": 0x7000000E7],
            ["HIDKeyboardModifierMappingSrc": 0x7000000E7, "HIDKeyboardModifierMappingDst": 0x7000000E6],
        ]
    }

    static func userKeyMappingJSONForLaunchAgent(_ mapping: [[String: Int]]) -> String {
        let items = mapping.map { m in
            let src = m["HIDKeyboardModifierMappingSrc"]!
            let dst = m["HIDKeyboardModifierMappingDst"]!
            return "{\"HIDKeyboardModifierMappingSrc\":\(src),\"HIDKeyboardModifierMappingDst\":\(dst)}"
        }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    private static func enumerateKeyboards(builtInVendorID: Int) -> [KeyboardDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let usagePage = kHIDPage_GenericDesktop
        let usage = kHIDUsage_GD_Keyboard
        let matching = [kIOHIDDeviceUsagePageKey: usagePage, kIOHIDDeviceUsageKey: usage] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, matching)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return []
        }

        let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var result: [KeyboardDevice] = []
        for device in deviceSet {
            guard let vid = getHIDVendorID(device),
                  let pid = getHIDProductID(device) else { continue }
            let name = getHIDProductName(device) ?? ""
            let id = "\(vid)-\(pid)-\(name.hashValue)"
            let isBuiltIn = (Int(truncating: vid) == builtInVendorID)
            result.append(KeyboardDevice(
                id: id,
                name: name.isEmpty ? "Keyboard (\(vid):\(pid))" : name,
                vendorID: Int(truncating: vid),
                productID: Int(truncating: pid),
                isBuiltIn: isBuiltIn
            ))
        }
        return result.sorted { k1, k2 in
            if k1.isBuiltIn != k2.isBuiltIn { return k1.isBuiltIn }
            return k1.name.localizedCaseInsensitiveCompare(k2.name) == .orderedAscending
        }
    }
}

// MARK: - IOHIDDevice property helpers

private func getHIDDeviceProperty(_ device: IOHIDDevice, key: String) -> Any? {
    let keyCF = key as CFString
    guard let ref = IOHIDDeviceGetProperty(device, keyCF) else { return nil }
    return (ref as Any as? NSObject)
}

private func getHIDProductName(_ device: IOHIDDevice) -> String? {
    getHIDDeviceProperty(device, key: "Product") as? String
}

private func getHIDVendorID(_ device: IOHIDDevice) -> NSNumber? {
    getHIDDeviceProperty(device, key: "VendorID") as? NSNumber
}

private func getHIDProductID(_ device: IOHIDDevice) -> NSNumber? {
    getHIDDeviceProperty(device, key: "ProductID") as? NSNumber
}
