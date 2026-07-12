//
//  RemindersController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  EventKit-backed source for the user's incomplete reminders, surfaced in the
//  expanded notch and the menu-bar menu.
//

import Combine
import EventKit
import Foundation

@MainActor
final class RemindersController: ObservableObject {
    struct Reminder: Identifiable, Equatable {
        let id: String
        let title: String
        let dueDate: Date?
        let isCompleted: Bool
        let calendarTitle: String
        let priority: Int
    }

    /// How far into the future dated reminders are surfaced. Reminders with no
    /// due date are always included; dated ones must be overdue or fall inside
    /// this window.
    private static let lookaheadDays = 7

    /// Reminders change through `.EKEventStoreChanged`, but a light periodic
    /// refresh keeps overdue/relative state honest without a busy loop.
    private static let refreshInterval: TimeInterval = 5 * 60

    private static let maxReminders = 20

    @Published private(set) var authorizationStatus: EKAuthorizationStatus =
        EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var reminders: [Reminder] = []
    @Published private(set) var errorMessage: String?

    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?
    private var storeChangedObserver: NSObjectProtocol?

    var canRead: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    func start() {
        refreshAuthorizationStatus()
        observeEventStoreChanges()
        refresh()
        startRefreshTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        if let storeChangedObserver {
            NotificationCenter.default.removeObserver(storeChangedObserver)
            self.storeChangedObserver = nil
        }
    }

    func requestAccess() {
        refreshAuthorizationStatus()

        guard authorizationStatus == .notDetermined else {
            refresh()
            return
        }

        errorMessage = nil

        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                    } else if !granted {
                        self.errorMessage = "Reminders access was not granted."
                    }
                    self.refresh()
                }
            }
        }
    }

    func refresh() {
        refreshAuthorizationStatus()

        guard canRead else {
            reminders = []
            return
        }

        errorMessage = nil

        let calendar = Foundation.Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        // A `nil` start lets the predicate include reminders with no start/due
        // date as well as overdue ones; the end bounds the future window.
        let endDate = calendar.date(byAdding: .day, value: Self.lookaheadDays, to: startOfDay)

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: endDate,
            calendars: nil
        )

        eventStore.fetchReminders(matching: predicate) { [weak self] fetched in
            let mapped = (fetched ?? []).map(Self.makeReminder(from:))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reminders = Self.sortAndCap(mapped, now: Date())
                }
            }
        }
    }

    func toggleCompletion(_ reminder: Reminder) {
        guard let ekReminder = eventStore.calendarItem(
            withIdentifier: reminder.id
        ) as? EKReminder else {
            return
        }

        ekReminder.isCompleted.toggle()
        try? eventStore.save(ekReminder, commit: true)
        refresh()
    }

    private func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    private func observeEventStoreChanges() {
        guard storeChangedObserver == nil else { return }

        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private nonisolated static func makeReminder(from reminder: EKReminder) -> Reminder {
        let dueDate: Date?
        if let components = reminder.dueDateComponents {
            dueDate = components.date ?? Foundation.Calendar.current.date(from: components)
        } else {
            dueDate = nil
        }
        let title = reminder.title?.isEmpty == false ? (reminder.title ?? "Untitled Reminder") : "Untitled Reminder"

        return Reminder(
            id: reminder.calendarItemIdentifier,
            title: title,
            dueDate: dueDate,
            isCompleted: reminder.isCompleted,
            calendarTitle: reminder.calendar?.title ?? "",
            priority: reminder.priority
        )
    }

    /// Sort order: overdue reminders first, then dated reminders by ascending
    /// due date, then undated reminders last. Result is capped.
    private nonisolated static func sortAndCap(_ reminders: [Reminder], now: Date) -> [Reminder] {
        let sorted = reminders.sorted { lhs, rhs in
            let lhsOverdue = isOverdue(lhs, now: now)
            let rhsOverdue = isOverdue(rhs, now: now)
            if lhsOverdue != rhsOverdue {
                return lhsOverdue && !rhsOverdue
            }

            switch (lhs.dueDate, rhs.dueDate) {
            case let (lhsDue?, rhsDue?):
                if lhsDue != rhsDue {
                    return lhsDue < rhsDue
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        return Array(sorted.prefix(maxReminders))
    }

    private nonisolated static func isOverdue(_ reminder: Reminder, now: Date) -> Bool {
        guard let dueDate = reminder.dueDate else { return false }
        return dueDate < now
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
