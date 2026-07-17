//
//  ExpandedNotchPanelsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  The expanded-notch panel switcher. Hosts every expandable surface — music,
//  calendar, weather, reminders, camera mirror, file shelf, clipboard, quick
//  launch — behind a compact icon bar so the user can move between them even
//  while media is playing. Rendered at the calendar size so switching never
//  resizes the notch.
//

import SwiftUI

enum NotchPanelTab: String, CaseIterable, Identifiable {
    case music, calendar, weather, reminders, camera, shelf, clipboard, quickLaunch

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .music: "play.circle"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .reminders: "checklist"
        case .camera: "camera"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .quickLaunch: "square.grid.2x2"
        }
    }

    var title: String {
        switch self {
        case .music: "Music"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .reminders: "Reminders"
        case .camera: "Camera"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .quickLaunch: "Quick Launch"
        }
    }
}

struct ExpandedNotchPanelsView: View {
    var morphNamespace: Namespace.ID?

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var cameraMirror: CameraMirrorController
    @EnvironmentObject var fileShelf: FileShelfController

    @State private var selected: NotchPanelTab?

    private var availablePanels: [NotchPanelTab] {
        NotchPanelTab.allCases.filter { panel in
            panel != .music || nowPlaying.track != nil
        }
    }

    private var activePanel: NotchPanelTab {
        let resolved = selected ?? (nowPlaying.track != nil ? .music : .calendar)
        return availablePanels.contains(resolved) ? resolved : .calendar
    }

    var body: some View {
        VStack(spacing: 0) {
            panelContent(activePanel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            switcherBar
                .padding(.top, 3)
                .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func panelContent(_ panel: NotchPanelTab) -> some View {
        switch panel {
        case .music:
            if let track = nowPlaying.track {
                NowPlayingExpandedView(track: track, morphNamespace: morphNamespace)
            } else {
                CalendarNotchView()
            }
        case .calendar:
            CalendarNotchView()
        case .weather:
            WeatherNotchPanelTab()
        case .reminders:
            RemindersNotchPanelTab()
        case .camera:
            CameraMirrorView(controller: cameraMirror)
                .padding(.horizontal, 18)
                .padding(.top, 14)
        case .shelf:
            FileShelfView(controller: fileShelf, compact: true)
        case .clipboard:
            ClipboardNotchPanelTab()
        case .quickLaunch:
            QuickLaunchNotchPanelTab()
        }
    }

    private var switcherBar: some View {
        HStack(spacing: 2) {
            ForEach(availablePanels) { panel in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selected = panel
                    }
                } label: {
                    Image(systemName: panel.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(panel == activePanel ? Color.white : Color.white.opacity(0.5))
                        .frame(width: 30, height: 24)
                        .background {
                            if panel == activePanel {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.white.opacity(0.16))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(panel.title)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }
}

// MARK: - Lightweight panels

private struct WeatherNotchPanelTab: View {
    @EnvironmentObject var weather: WeatherController

    var body: some View {
        Group {
            if let current = weather.weather {
                VStack(spacing: 4) {
                    Image(systemName: current.sfSymbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 46, weight: .medium))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

                    Text(current.temperatureString)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Text(Self.condition(for: current.code))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))

                    HStack(spacing: 12) {
                        if let feels = current.apparentC {
                            Label("Feels \(Int(feels.rounded()))°", systemImage: "thermometer.medium")
                        }
                        if let location = current.locationName {
                            Label(location, systemImage: "location.fill")
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 2)
                }
            } else {
                Button {
                    weather.refresh()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("Enable Weather")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(weather.errorMessage ?? "Tap to allow Location access.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func condition(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67: "Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow Showers"
        case 95, 96, 99: "Thunderstorm"
        default: "—"
        }
    }
}

private struct RemindersNotchPanelTab: View {
    @EnvironmentObject var reminders: RemindersController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminders")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            if !reminders.canRead {
                Button("Enable Reminders…") { reminders.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            } else if reminders.reminders.isEmpty {
                Text("No upcoming reminders.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(reminders.reminders) { reminder in
                            Button {
                                reminders.toggleCompletion(reminder)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(reminder.isCompleted ? Color.green : Color.white.opacity(0.6))
                                    Text(reminder.title)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .strikethrough(reminder.isCompleted)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

private struct ClipboardNotchPanelTab: View {
    @EnvironmentObject var clipboard: ClipboardHistoryController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clipboard")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            if clipboard.entries.isEmpty {
                Text("Copied text will appear here.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(clipboard.entries) { entry in
                            Button {
                                clipboard.copy(entry)
                            } label: {
                                Text(entry.text)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

private struct QuickLaunchNotchPanelTab: View {
    @EnvironmentObject var quickLaunch: QuickLaunchController

    private let columns = [GridItem(.adaptive(minimum: 70, maximum: 100), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Launch")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            if quickLaunch.items.isEmpty {
                Text("Pin apps and Shortcuts in Settings → Widgets.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(quickLaunch.items) { item in
                            Button {
                                quickLaunch.launch(item)
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: item.isShortcut ? "square.stack.3d.up" : "app.fill")
                                        .font(.system(size: 22, weight: .medium))
                                    Text(item.displayName)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.07))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

private extension QuickLaunchController.Item {
    var isShortcut: Bool {
        if case .shortcut = self { return true }
        return false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
