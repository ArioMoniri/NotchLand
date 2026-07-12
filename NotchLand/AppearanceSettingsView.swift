//
//  AppearanceSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(NotchSettings.Theme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            if screens.count > 1 {
                Section("Display") {
                    Picker("Show notch on", selection: $settings.preferredDisplayID) {
                        Text("Automatic").tag(0)
                        ForEach(screens, id: \.self) { screen in
                            if let id = screen.displayID {
                                Text(displayLabel(for: screen)).tag(Int(id))
                            }
                        }
                    }

                    Text("Automatic uses the display with the notch, or the built-in display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Material") {
                Toggle("Use Blur Material Background", isOn: $settings.useBlurMaterial)
            }
        }
        .formStyle(.grouped)
    }

    /// Connected screens, read fresh each render so newly (dis)connected
    /// displays appear the next time Settings is opened.
    private var screens: [NSScreen] {
        NSScreen.screens
    }

    private func displayLabel(for screen: NSScreen) -> String {
        var name = screen.localizedName
        if screen.hasNotch {
            name += " • Notch"
        } else if screen.isBuiltIn {
            name += " • Built-in"
        }
        return name
    }
}

#if DEBUG
#Preview("Appearance Settings") {
    NotchPreviewContainer {
        AppearanceSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
