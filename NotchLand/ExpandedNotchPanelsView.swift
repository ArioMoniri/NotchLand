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

enum NotchPanel: String, CaseIterable, Identifiable {
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
}

struct ExpandedNotchPanelsView: View {
    var morphNamespace: Namespace.ID?

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var cameraMirror: CameraMirrorController
    @EnvironmentObject var fileShelf: FileShelfController

    @State private var selected: NotchPanel?

    private var availablePanels: [NotchPanel] {
        NotchPanel.allCases.filter { panel in
            panel != .music || nowPlaying.track != nil
        }
    }

    private var activePanel: NotchPanel {
        let resolved = selected ?? (nowPlaying.track != nil ? .music : .calendar)
        return availablePanels.contains(resolved) ? resolved : .calendar
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            panelContent(activePanel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, 30)

            switcherBar
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func panelContent(_ panel: NotchPanel) -> some View {
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
            WeatherNotchPanel()
        case .reminders:
            RemindersNotchPanel()
        case .camera:
            CameraMirrorView(controller: cameraMirror)
                .padding(.horizontal, 18)
                .padding(.top, 14)
        case .shelf:
            FileShelfView(controller: fileShelf)
                .padding(.horizontal, 12)
                .padding(.top, 8)
        case .clipboard:
            ClipboardNotchPanel()
        case .quickLaunch:
            QuickLaunchNotchPanel()
        }
    }

    private var switcherBar: some View {
        HStack(spacing: 4) {
            ForEach(availablePanels) { panel in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selected = panel
                    }
                } label: {
                    Image(systemName: panel.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(panel == activePanel ? Color.white : Color.white.opacity(0.5))
                        .frame(width: 26, height: 22)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(panel == activePanel ? Color.white.opacity(0.18) : Color.clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Lightweight panels

private struct WeatherNotchPanel: View {
    @EnvironmentObject var weather: WeatherController

    var body: some View {
        VStack(spacing: 10) {
            if let current = weather.weather {
                Image(systemName: current.sfSymbol)
                    .font(.system(size: 46, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(current.temperatureString)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let location = current.locationName {
                    Text(location)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Image(systemName: "location.slash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(weather.errorMessage ?? "Waiting for location…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button("Refresh") { weather.refresh() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 18)
    }
}

private struct RemindersNotchPanel: View {
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

private struct ClipboardNotchPanel: View {
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

private struct QuickLaunchNotchPanel: View {
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
