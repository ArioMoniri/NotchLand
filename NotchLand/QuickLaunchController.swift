//
//  QuickLaunchController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Stores a user-curated list of pinned applications and Shortcuts and launches
//  them on demand. Apps are persisted as security-scoped bookmarks so they keep
//  resolving across relaunches; Shortcuts are stored by name and run through the
//  `shortcuts` CLI (with a URL-scheme fallback). All persistence is JSON-encoded
//  into UserDefaults so the settings UI and menu-bar submenu can simply observe.
//

import AppKit
import Combine
import Foundation

@MainActor
final class QuickLaunchController: ObservableObject {
    /// A single pinned launch target — either an application (referenced by a
    /// security-scoped bookmark) or a named Shortcut.
    enum Item: Codable, Identifiable, Equatable, Hashable {
        case app(bookmark: Data, name: String)
        case shortcut(name: String)

        /// Stable identifier, safe to use as a `ForEach`/menu key.
        var id: String {
            switch self {
            case let .app(bookmark, name):
                // Bookmark bytes make the id stable and distinct per app,
                // even if two apps happened to share a display name.
                return "app:\(name):\(bookmark.hashValue)"
            case let .shortcut(name):
                return "shortcut:\(name)"
            }
        }

        var displayName: String {
            switch self {
            case let .app(_, name): return name
            case let .shortcut(name): return name
            }
        }

        // Explicit Codable conformance keeps the on-disk JSON shape stable and
        // independent of the compiler's synthesized representation.
        private enum Kind: String, Codable {
            case app
            case shortcut
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case bookmark
            case name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .app:
                let bookmark = try container.decode(Data.self, forKey: .bookmark)
                let name = try container.decode(String.self, forKey: .name)
                self = .app(bookmark: bookmark, name: name)
            case .shortcut:
                let name = try container.decode(String.self, forKey: .name)
                self = .shortcut(name: name)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .app(bookmark, name):
                try container.encode(Kind.app, forKey: .kind)
                try container.encode(bookmark, forKey: .bookmark)
                try container.encode(name, forKey: .name)
            case let .shortcut(name):
                try container.encode(Kind.shortcut, forKey: .kind)
                try container.encode(name, forKey: .name)
            }
        }
    }

    @Published private(set) var items: [Item] = []

    private enum Keys {
        static let items = "notch.quickLaunchItems"
    }

    init() {
        items = Self.load()
    }

    // MARK: - Mutators

    /// Pin an application by URL. Creates a security-scoped bookmark (falling
    /// back to a plain bookmark) and derives the display name from the bundle.
    /// Duplicate apps (by resolved path) are ignored.
    func addApp(url: URL) {
        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            guard let fallback = try? url.bookmarkData() else { return }
            bookmark = fallback
        }

        let name = Self.displayName(for: url)

        // Avoid duplicates by resolved path.
        let newPath = url.standardizedFileURL.path
        let alreadyPinned = items.contains { item in
            if case let .app(existingBookmark, _) = item,
               let existingURL = Self.resolvePath(from: existingBookmark) {
                return existingURL == newPath
            }
            return false
        }
        guard !alreadyPinned else { return }

        items.append(.app(bookmark: bookmark, name: name))
        save()
    }

    /// Pin a Shortcut by name. Duplicate names are ignored.
    func addShortcut(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let alreadyPinned = items.contains { item in
            if case let .shortcut(existingName) = item {
                return existingName == trimmed
            }
            return false
        }
        guard !alreadyPinned else { return }

        items.append(.shortcut(name: trimmed))
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        save()
    }

    /// Reorder pinned items (e.g. from a SwiftUI `onMove`).
    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Launching

    func launch(_ item: Item) {
        switch item {
        case let .app(bookmark, _):
            launchApp(bookmark: bookmark)
        case let .shortcut(name):
            launchShortcut(named: name)
        }
    }

    private func launchApp(bookmark: Data) {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // Stale / unresolvable bookmark — no-op gracefully.
            return
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func launchShortcut(named name: String) {
        // Run off the main thread; fall back to the URL scheme on failure.
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]

            var launched = false
            do {
                try process.run()
                launched = true
            } catch {
                launched = false
            }

            if !launched {
                Task { @MainActor in
                    Self.openShortcutViaURLScheme(named: name)
                }
            }
        }
    }

    private static func openShortcutViaURLScheme(named name: String) {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        guard let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Keys.items)
    }

    private static func load() -> [Item] {
        guard let data = UserDefaults.standard.data(forKey: Keys.items),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - Helpers

    private static func displayName(for url: URL) -> String {
        let last = url.lastPathComponent
        if last.hasSuffix(".app") {
            return String(last.dropLast(".app".count))
        }
        return last
    }

    /// Resolve a bookmark to its standardized filesystem path, for duplicate
    /// detection. Returns nil if the bookmark cannot be resolved.
    private static func resolvePath(from bookmark: Data) -> String? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return url.standardizedFileURL.path
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
