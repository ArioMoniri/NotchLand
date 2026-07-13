//
//  FileShelfView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  A persistent file "shelf" / tray. Drop files onto the window to park them and
//  drag them back out later. Each dropped file is persisted as a security-scoped
//  bookmark (mirroring QuickLaunchController) so the shelf keeps resolving across
//  relaunches. Bookmarks are JSON-encoded into UserDefaults so the standalone
//  Shelf window can simply observe the controller.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Part A — Controller

@MainActor
final class FileShelfController: ObservableObject {
    /// A single parked file, referenced by a security-scoped bookmark so it keeps
    /// resolving across launches.
    struct ShelfItem: Identifiable, Equatable, Codable {
        let id: UUID
        let name: String
        let bookmark: Data

        init(id: UUID = UUID(), name: String, bookmark: Data) {
            self.id = id
            self.name = name
            self.bookmark = bookmark
        }

        /// Transient (non-persisted) resolution of the security-scoped bookmark.
        /// Handles stale bookmarks gracefully and returns nil on any failure.
        var resolvedURL: URL? {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }
            return url
        }
    }

    @Published private(set) var items: [ShelfItem] = []

    private enum Keys {
        static let items = "notch.fileShelfItems"
    }

    init() {
        items = Self.load()
    }

    // MARK: - Mutators

    /// Park one or more files on the shelf. Each URL is stored as a security-scoped
    /// bookmark (falling back to a plain bookmark). Duplicates (by resolved path)
    /// are ignored. Persists once after processing the batch.
    func add(urls: [URL]) {
        var didChange = false

        for url in urls {
            let bookmark: Data
            do {
                bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                guard let fallback = try? url.bookmarkData() else { continue }
                bookmark = fallback
            }

            // Dedupe by resolved path.
            let newPath = url.standardizedFileURL.path
            let alreadyOnShelf = items.contains { item in
                if let existingPath = Self.resolvePath(from: item.bookmark) {
                    return existingPath == newPath
                }
                return false
            }
            guard !alreadyOnShelf else { continue }

            items.append(ShelfItem(name: url.lastPathComponent, bookmark: bookmark))
            didChange = true
        }

        if didChange {
            save()
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Keys.items)
    }

    private static func load() -> [ShelfItem] {
        guard let data = UserDefaults.standard.data(forKey: Keys.items),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - Helpers

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

// MARK: - Part B — Views

/// Standalone Shelf window. Drop files in, drag them back out.
struct FileShelfView: View {
    @ObservedObject var controller: FileShelfController
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 300, minHeight: 220)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Subviews

    private var toolbar: some View {
        HStack {
            Text(itemCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") {
                controller.clear()
            }
            .controlSize(.small)
            .disabled(controller.items.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if controller.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(controller.items) { item in
                        ShelfItemCell(item: item) {
                            controller.remove(item)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var emptyState: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundStyle(.secondary.opacity(0.5))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text("Drop files here")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
        }
    }

    private var itemCountLabel: String {
        let count = controller.items.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    // MARK: Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    Task { @MainActor in
                        controller.add(urls: [url])
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    } else {
                        url = nil
                    }
                    guard let resolved = url, resolved.isFileURL else { return }
                    Task { @MainActor in
                        controller.add(urls: [resolved])
                    }
                }
            }
        }

        return handled
    }
}

/// A single shelf tile: file icon, name, drag-out source, remove affordances.
private struct ShelfItemCell: View {
    let item: FileShelfController.ShelfItem
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            iconImage
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(width: 88, height: 84)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(.background))
                }
                .buttonStyle(.plain)
                .help("Remove")
                .padding(2)
            }
        }
        .onHover { isHovering = $0 }
        .onDrag {
            if let url = item.resolvedURL {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
            return NSItemProvider()
        }
        .contextMenu {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let url = item.resolvedURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "doc")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .padding(4)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
