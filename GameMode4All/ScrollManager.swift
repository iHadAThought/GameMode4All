//
//  ScrollManager.swift
//  GameMode4All
//
//  From ScrollSplit: applies per-device natural scrolling via event tap when "separate" mode is on.
//

import AppKit
import CoreGraphics
import Foundation

/// Applies per-device natural scrolling by reversing scroll events when "separate" mode is on.
/// System is kept at "not natural"; we reverse trackpad/mouse scroll to achieve desired behavior.
final class ScrollManager {
    static let shared = ScrollManager()

    var isEnabled: Bool = false {
        didSet {
            if isEnabled != oldValue {
                DispatchQueue.main.async { [weak self] in
                    if self?.isEnabled == true { self?.startTap() } else { self?.stopTap() }
                }
            }
        }
    }

    var trackpadNatural: Bool = true
    var mouseNatural: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    private func startTap() {
        guard eventTap == nil else { return }

        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<ScrollManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleScrollEvent(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NotificationCenter.default.post(name: .scrollTapFailed, object: nil)
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleScrollEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let isTrackpad = continuous != 0

        let shouldReverse: Bool
        if isTrackpad {
            shouldReverse = trackpadNatural
        } else {
            shouldReverse = mouseNatural
        }

        guard shouldReverse else { return Unmanaged.passUnretained(event) }

        // Reverse vertical
        let a1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let pt1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fp1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -a1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pt1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fp1)

        // Reverse horizontal
        let a2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let pt2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let fp2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -a2)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pt2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fp2)

        return Unmanaged.passUnretained(event)
    }
}

extension Notification.Name {
    static let scrollTapFailed = Notification.Name("scrollTapFailed")
}
