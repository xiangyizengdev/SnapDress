import AppKit
import SwiftUI

/// Persists the last N screenshots produced by SnapDress so the menu bar popover
/// can re-surface them. Files live in `~/Library/Application Support/SnapDress/recent/`.
/// Stored images are the *processed* (beautified) ones — the same bytes that get
/// placed on the clipboard, so re-using them doesn't require re-processing.
@MainActor
final class RecentScreenshotsStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let url: URL
        let createdAt: Date

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    static let shared = RecentScreenshotsStore()

    @Published private(set) var items: [Item] = []

    private let maxCount = 10
    private let directory: URL
    private var thumbnailCache: [UUID: NSImage] = [:]

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("SnapDress/recent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        loadFromDisk()
    }

    // MARK: - Mutations

    func add(image: NSImage) {
        guard let data = image.pngRepresentation() else { return }
        let id = UUID()
        let url = directory.appendingPathComponent("\(id.uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("[RecentScreenshotsStore] failed to write \(url): \(error)")
            return
        }
        thumbnailCache[id] = image
        items.insert(Item(id: id, url: url, createdAt: Date()), at: 0)
        enforceLimit()
    }

    func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
        thumbnailCache.removeValue(forKey: item.id)
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        for item in items {
            try? FileManager.default.removeItem(at: item.url)
        }
        thumbnailCache.removeAll()
        items.removeAll()
    }

    // MARK: - Lookup

    func image(for item: Item) -> NSImage? {
        if let cached = thumbnailCache[item.id] { return cached }
        guard let img = NSImage(contentsOf: item.url) else { return nil }
        thumbnailCache[item.id] = img
        return img
    }

    // MARK: - Disk I/O

    private func loadFromDisk() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        let parsed: [Item] = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "png" else { return nil }
            let mtime = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            return Item(id: id, url: url, createdAt: mtime)
        }

        items = Array(parsed.sorted { $0.createdAt > $1.createdAt }.prefix(maxCount))
    }

    private func enforceLimit() {
        while items.count > maxCount {
            if let last = items.popLast() {
                try? FileManager.default.removeItem(at: last.url)
                thumbnailCache.removeValue(forKey: last.id)
            } else {
                break
            }
        }
    }
}

private extension NSImage {
    func pngRepresentation() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
