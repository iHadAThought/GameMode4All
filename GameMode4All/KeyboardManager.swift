//
//  KeyboardManager.swift
//  GameMode4All
//
//  From KeySwap: enumerate keyboards via IOKit and apply Command ⇄ Option swap via hidutil.
//

import Foundation
import IOKit
import IOKit.hid

/// HID Usage codes for modifier keys (from HID Usage Tables)
/// Prefix 0x7000000 for keyboard usage page
private enum ModifierKeyCode: Int {
    case leftControl  = 0x7000000E0
    case leftShift    = 0x7000000E1
    case leftOption   = 0x7000000E2
    case leftCommand  = 0x7000000E3
    case rightControl = 0x7000000E4
    case rightShift   = 0x7000000E5
    case rightOption  = 0x7000000E6
    case rightCommand = 0x7000000E7
}

/// Mapping to swap Command and Option keys (both sides)
private let commandOptionSwapMapping: [[String: Int]] = [
    ["HIDKeyboardModifierMappingSrc": ModifierKeyCode.leftCommand.rawValue,  "HIDKeyboardModifierMappingDst": ModifierKeyCode.leftOption.rawValue],
    ["HIDKeyboardModifierMappingSrc": ModifierKeyCode.leftOption.rawValue,   "HIDKeyboardModifierMappingDst": ModifierKeyCode.leftCommand.rawValue],
    ["HIDKeyboardModifierMappingSrc": ModifierKeyCode.rightCommand.rawValue, "HIDKeyboardModifierMappingDst": ModifierKeyCode.rightOption.rawValue],
    ["HIDKeyboardModifierMappingSrc": ModifierKeyCode.rightOption.rawValue,  "HIDKeyboardModifierMappingDst": ModifierKeyCode.rightCommand.rawValue]
]

@MainActor
final class KeyboardManager: ObservableObject {
    @Published var keyboards: [KeyboardInfo] = []
    @Published var selectedKeyboard: KeyboardInfo?
    @Published var isSwapped: Bool = false
    @Published var statusMessage: String = ""
    @Published var isLoading: Bool = false

    init() {
        refreshKeyboards()
    }

    func refreshKeyboards() {
        keyboards = Self.enumerateKeyboards()
        if selectedKeyboard == nil, let first = keyboards.first {
            selectedKeyboard = first
        }
        checkCurrentMapping()
    }

    func swapCommandAndOption() {
        guard let keyboard = selectedKeyboard else {
            statusMessage = "Select a keyboard first"
            return
        }
        applyMapping(commandOptionSwapMapping, for: keyboard)
        isSwapped = true
        statusMessage = "Swapped ⌘ Command ⇄ ⌥ Option for \(keyboard.displayName)"
    }

    func resetModifiers() {
        guard let keyboard = selectedKeyboard else {
            statusMessage = "Select a keyboard first"
            return
        }
        applyMapping([], for: keyboard)
        isSwapped = false
        statusMessage = "Reset modifier keys for \(keyboard.displayName)"
    }

    private func applyMapping(_ mapping: [[String: Int]], for keyboard: KeyboardInfo) {
        let matching = keyboard.matchingDictionary
        let mappingJSON: String
        if mapping.isEmpty {
            mappingJSON = "{\"UserKeyMapping\":[]}"
        } else {
            let mapped = mapping.map { m in
                "{\"HIDKeyboardModifierMappingSrc\":\(m["HIDKeyboardModifierMappingSrc"]!),\"HIDKeyboardModifierMappingDst\":\(m["HIDKeyboardModifierMappingDst"]!)}"
            }.joined(separator: ",")
            mappingJSON = "{\"UserKeyMapping\":[\(mapped)]}"
        }

        var args = ["property", "--set", mappingJSON]
        if !matching.isEmpty {
            let matchJSON = matching.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
            args.insert("--matching", at: 1)
            args.insert("{\(matchJSON)}", at: 2)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = args

        do {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            statusMessage = process.terminationStatus == 0 ? "Success" : "Command may have failed (exit \(process.terminationStatus))"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func checkCurrentMapping() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--get", "UserKeyMapping"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.contains("null"), output.contains("UserKeyMapping") {
                isSwapped = output.contains("E2") && output.contains("E3")  // Swap uses E2/E3
            } else {
                isSwapped = false
            }
        } catch {
            isSwapped = false
        }
    }

    static func enumerateKeyboards() -> [KeyboardInfo] {
        var result: [KeyboardInfo] = []

        let managerRef = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let manager = managerRef as IOHIDManager?
        guard let manager else {
            return result
        }

        // Match keyboards: Usage Page 1 (Generic Desktop), Usage 6 (Keyboard)
        let keyboardUsage = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary

        IOHIDManagerSetDeviceMatching(manager, keyboardUsage)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return result
        }

        for device in devices {
            let vendorID = Int(IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int32 ?? 0)
            let productID = Int(IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int32 ?? 0)
            let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
            let builtIn = IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? Bool ?? false

            let id = "\(vendorID)-\(productID)-\(builtIn)"
            let info = KeyboardInfo(
                id: id,
                name: productName,
                vendorID: vendorID,
                productID: productID,
                isBuiltIn: builtIn
            )

            // Dedupe by vendor/product - internal keyboard often has 0,0
            if result.contains(where: { $0.vendorID == vendorID && $0.productID == productID && $0.isBuiltIn == builtIn }) {
                continue
            }
            result.append(info)
        }

        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Sort: built-in first, then by name
        result.sort { a, b in
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }

        return result
    }
}
