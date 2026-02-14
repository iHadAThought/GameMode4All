//
//  KeyboardInfo.swift
//  GameMode4All
//
//  From KeySwap: HID keyboard device info for modifier key mapping.
//

import Foundation

struct KeyboardInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let isBuiltIn: Bool

    var displayName: String {
        if name.isEmpty || name == "(null)" {
            if isBuiltIn {
                return "Apple Internal Keyboard"
            }
            return "Keyboard (\(String(format: "0x%04X", vendorID)), \(String(format: "0x%04X", productID)))"
        }
        return name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: KeyboardInfo, rhs: KeyboardInfo) -> Bool {
        lhs.id == rhs.id
    }

    var matchingDictionary: [String: Int] {
        var dict: [String: Int] = [:]
        if vendorID != 0 {
            dict["VendorID"] = vendorID
        }
        if productID != 0 {
            dict["ProductID"] = productID
        }
        return dict
    }
}
