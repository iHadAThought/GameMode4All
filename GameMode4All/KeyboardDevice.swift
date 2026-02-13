//
//  KeyboardDevice.swift
//  GameMode4All
//
//  From KeySwap: HID keyboard device model.
//

import Foundation

struct KeyboardDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let isBuiltIn: Bool

    var hidMatchJSON: String {
        "{\"VendorID\":\(vendorID),\"ProductID\":\(productID)}"
    }
}
