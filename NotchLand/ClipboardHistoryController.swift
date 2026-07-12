//
//  ClipboardHistoryController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Polls the general pasteboard and keeps a short rolling history of copied
//  text, surfaced through the menu-bar menu. Password-manager / transient
//  clipboard entries are ignored.
//

import AppKit
import Combine

@MainActor
final class ClipboardHistoryController: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 15
    private let pasteboard = NSPasteboard.general
    private let pollInterval: TimeInterval = 0.6
    private var lastChangeCount: Int
    private var timer: Timer?
    private var isWritingBack = false

    // Clipboard sources that should never be stored (password managers etc.).
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-copy a stored entry to the pasteboard and move it to the front.
    func copy(_ entry: Entry) {
        isWritingBack = true
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        isWritingBack = false

        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
    }

    func entry(with id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    func clear() {
        entries.removeAll()
    }

    private func poll() {
        let change = pasteboard.changeCount
        guard change != lastChangeCount else { return }
        lastChangeCount = change
        guard !isWritingBack else { return }

        let types = pasteboard.types ?? []
        guard !types.contains(Self.concealedType), !types.contains(Self.transientType) else { return }

        guard let string = pasteboard.string(forType: .string) else { return }
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        entries.removeAll { $0.text == string }
        entries.insert(Entry(text: string), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
