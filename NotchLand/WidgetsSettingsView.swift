//
//  WidgetsSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Settings surface for the extra widgets: Quick Launch, Reminders, Weather,
//  device battery, camera mirror, file shelf, and clipboard history.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WidgetsSettingsView: View {
    @EnvironmentObject var quickLaunch: QuickLaunchController
    @EnvironmentObject var reminders: RemindersController
    @EnvironmentObject var weather: WeatherController
    @EnvironmentObject var btBattery: BluetoothBatteryController
    @EnvironmentObject var cameraMirror: CameraMirrorController
    @EnvironmentObject var fileShelf: FileShelfController
    @EnvironmentObject var clipboard: ClipboardHistoryController

    var body: some View {
        Form {
            quickLaunchSection
            remindersSection
            weatherSection
            batterySection
            cameraSection
            shelfSection
            clipboardSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Quick Launch

    private var quickLaunchSection: some View {
        Section("Quick Launch") {
            if quickLaunch.items.isEmpty {
                Text("Pin apps and Shortcuts to launch them from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(quickLaunch.items) { item in
                    HStack {
                        Image(systemName: iconName(for: item))
                            .foregroundStyle(.secondary)
                        Text(item.displayName)
                        Spacer()
                        Button(role: .destructive) {
                            quickLaunch.remove(item)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                Button("Add App…") { addApp() }
                Button("Add Shortcut…") { addShortcut() }
            }
        }
    }

    private func iconName(for item: QuickLaunchController.Item) -> String {
        switch item {
        case .app: return "app"
        case .shortcut: return "square.stack.3d.up"
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            quickLaunch.addApp(url: url)
        }
    }

    private func addShortcut() {
        let alert = NSAlert()
        alert.messageText = "Add Shortcut"
        alert.informativeText = "Enter the exact name of a Shortcut to run."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Shortcut name"
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { quickLaunch.addShortcut(named: name) }
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section("Reminders") {
            if !reminders.canRead {
                HStack {
                    Text("Reminders access is not enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Enable") { reminders.requestAccess() }
                }
                if let error = reminders.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } else if reminders.reminders.isEmpty {
                Text("No upcoming reminders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reminders.reminders) { reminder in
                    Button {
                        reminders.toggleCompletion(reminder)
                    } label: {
                        HStack {
                            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(reminder.isCompleted ? .green : .secondary)
                            Text(reminder.title)
                                .strikethrough(reminder.isCompleted)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Weather

    private var weatherSection: some View {
        Section("Weather") {
            if let current = weather.weather {
                HStack {
                    Image(systemName: current.sfSymbol)
                    Text(current.temperatureString)
                        .font(.title3.weight(.semibold))
                    if let location = current.locationName {
                        Text(location).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { weather.refresh() }
                }
            } else {
                HStack {
                    Text(weather.errorMessage ?? "Waiting for location…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { weather.refresh() }
                }
            }
        }
    }

    // MARK: - Device battery

    private var batterySection: some View {
        Section("Device Battery") {
            if btBattery.devices.isEmpty {
                Text("No Bluetooth devices reporting battery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(btBattery.devices) { device in
                    HStack {
                        Text(device.name)
                        Spacer()
                        Text(batteryDetail(for: device))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func batteryDetail(for device: BTDevice) -> String {
        var parts: [String] = []
        if let left = device.left { parts.append("L \(left)%") }
        if let right = device.right { parts.append("R \(right)%") }
        if let box = device.batteryCase { parts.append("Case \(box)%") }
        if parts.isEmpty, let main = device.main { parts.append("\(main)%") }
        return parts.joined(separator: "  ")
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section("Camera Mirror") {
            CameraMirrorView(controller: cameraMirror)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - File shelf

    private var shelfSection: some View {
        Section("File Shelf") {
            FileShelfView(controller: fileShelf)
                .frame(height: 200)
        }
    }

    // MARK: - Clipboard

    private var clipboardSection: some View {
        Section("Clipboard History") {
            if clipboard.entries.isEmpty {
                Text("Copied text will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(clipboard.entries) { entry in
                    Button {
                        clipboard.copy(entry)
                    } label: {
                        Text(entry.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                Button("Clear History") { clipboard.clear() }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
