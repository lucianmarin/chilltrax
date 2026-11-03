import Foundation
import AppKit
import CryptoKit

/// Manages local disk and in-memory caching of fetched album cover images for song history entries.
public final class AlbumCoverCache: @unchecked Sendable {
    public let directoryURL: URL
    private let memoryCache = NSCache<NSString, NSImage>()
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]
    private let lock = NSLock()
    private let client: ChilltraxClient

    public init(directoryURL: URL? = nil, client: ChilltraxClient = ChilltraxClient()) {
        self.client = client
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directoryURL = appSupport
                .appendingPathComponent("Chilltrax", isDirectory: true)
                .appendingPathComponent("Covers", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        memoryCache.countLimit = 250
    }

    /// Computes a deterministic local file URL for a given remote cover URL.
    public func localFileURL(for remoteURL: URL) -> URL {
        let key = Self.cacheKey(for: remoteURL)
        let ext = Self.preferredFileExtension(for: remoteURL)
        return directoryURL.appendingPathComponent("\(key).\(ext)")
    }

    /// Returns true if the cover image for the given remote URL is cached on disk.
    public func isCachedOnDisk(for remoteURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: localFileURL(for: remoteURL).path)
    }

    /// Synchronously retrieves a cached `NSImage` from memory or disk if available.
    public func cachedImage(for remoteURL: URL) -> NSImage? {
        let key = Self.cacheKey(for: remoteURL) as NSString
        if let memImage = memoryCache.object(forKey: key) {
            return memImage
        }

        let fileURL = localFileURL(for: remoteURL)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = NSImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key)
        return image
    }

    /// Stores raw image data locally on disk and in memory for the given remote URL.
    @discardableResult
    public func storeImageData(_ data: Data, for remoteURL: URL) -> NSImage? {
        guard !data.isEmpty, let image = NSImage(data: data) else {
            return nil
        }

        let fileURL = localFileURL(for: remoteURL)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Even if disk write fails, keep in memory cache
        }

        let key = Self.cacheKey(for: remoteURL) as NSString
        memoryCache.setObject(image, forKey: key)
        return image
    }

    /// Returns the locally cached image if present, or downloads and caches it on disk.
    @discardableResult
    public func image(for remoteURL: URL) async -> NSImage? {
        if let existing = cachedImage(for: remoteURL) {
            return existing
        }

        let key = Self.cacheKey(for: remoteURL)
        let task: Task<NSImage?, Never> = lock.withLock {
            if let existingTask = inFlightTasks[key] {
                return existingTask
            }
            let newTask = Task<NSImage?, Never> { [weak self] in
                guard let self else { return nil }
                defer {
                    _ = self.lock.withLock {
                        self.inFlightTasks.removeValue(forKey: key)
                    }
                }
                guard let data = try? await self.client.fetchImageData(from: remoteURL) else {
                    return nil
                }
                return self.storeImageData(data, for: remoteURL)
            }
            inFlightTasks[key] = newTask
            return newTask
        }

        return await task.value
    }

    /// Ensures the cover for a remote URL is downloaded and cached locally on disk.
    public func cacheCoverIfNeeded(for remoteURL: URL?) async {
        guard let remoteURL else { return }
        _ = await image(for: remoteURL)
    }

    /// Deletes all cached album cover files from disk and clears the in-memory cache.
    public func clearAll() {
        let tasksToCancel: [Task<NSImage?, Never>] = lock.withLock {
            let tasks = Array(inFlightTasks.values)
            inFlightTasks.removeAll()
            return tasks
        }
        for task in tasksToCancel {
            task.cancel()
        }

        memoryCache.removeAllObjects()

        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) {
            for fileURL in contents {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// Total size in bytes of all cached album cover files on disk.
    public var cachedFilesSizeBytes: Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for fileURL in contents {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = values.fileSize {
                total += Int64(fileSize)
            }
        }
        return total
    }

    /// Number of cached album cover files on disk.
    public var cachedFileCount: Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return contents.filter { !$0.lastPathComponent.hasPrefix(".") }.count
    }

    public static func cacheKey(for url: URL) -> String {
        let normalized = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func preferredFileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "webp", "gif", "heic":
            return ext
        default:
            return "jpg"
        }
    }
}
