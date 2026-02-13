//
//  NaturalScrollingView.swift
//  GameMode4All
//
//  From ScrollSplit: per-device natural scrolling (trackpad vs mouse). Requires Accessibility for event tap.
//

import SwiftUI

struct NaturalScrollingView: View {
    @EnvironmentObject var scrollPrefs: ScrollPreferences
    @State private var showTapFailedAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Use separate scroll direction for trackpad and mouse")
                Spacer()
                Toggle("Use separate scroll direction for trackpad and mouse", isOn: $scrollPrefs.separateNaturalScroll)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Text("When on, you can set natural scrolling independently for the trackpad and for an external mouse. The app must stay running for this to work. Requires Accessibility permission.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if scrollPrefs.separateNaturalScroll {
                HStack {
                    Text("Natural scrolling for trackpad")
                    Spacer()
                    Toggle("Natural scrolling for trackpad", isOn: $scrollPrefs.trackpadNatural)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                HStack {
                    Text("Natural scrolling for mouse")
                    Spacer()
                    Toggle("Natural scrolling for mouse", isOn: $scrollPrefs.mouseNatural)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            } else {
                HStack {
                    Text("Natural scrolling")
                    Spacer()
                    Toggle("Natural scrolling", isOn: $scrollPrefs.globalNatural)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text("Uses the system setting. You may need to log out and back in for a change to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollTapFailed)) { _ in
            showTapFailedAlert = true
        }
        .alert("Accessibility permission required", isPresented: $showTapFailedAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use separate scroll direction for trackpad and mouse, add Game Mode for All to Accessibility in Privacy & Security and try again.")
        }
    }
}
