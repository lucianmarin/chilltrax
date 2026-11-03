import Foundation
import Compression

/// Persists played song history locally across app restarts in an efficiently compressed text file
/// (`history.tsv.lzfse`) using UTF-8 tab-separated values compressed via Apple's native LZFSE compression (matching `../monochrome`).
public final class CompressedHistoryStore {
    public static let fileHeader = "#CHILLTRAX_HISTORY_V1\tid\tplayedAtISO8601\tartist\ttitle\talbumOrMix\tyear\tcoverURL\tbuyURL\tstationName\tstationURL"

    public let fileURL: URL
    private let isoFormatter: ISO8601DateFormatter

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let directory = appSupport.appendingPathComponent("Chilltrax", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let lzfseURL = directory.appendingPathComponent("history.tsv.lzfse")
            let legacyZlibURL = directory.appendingPathComponent("history.tsv.zlib")
            self.fileURL = lzfseURL

            // Automatically migrate existing legacy zlib history file to LZFSE if present
            if !FileManager.default.fileExists(atPath: lzfseURL.path),
               FileManager.default.fileExists(atPath: legacyZlibURL.path),
               let legacyRaw = try? Data(contentsOf: legacyZlibURL),
               let decompressed = try? (legacyRaw as NSData).decompressed(using: .zlib) as Data,
               let recompressed = try? (decompressed as NSData).compressed(using: .lzfse) as Data {
                try? recompressed.write(to: lzfseURL, options: .atomic)
                try? FileManager.default.removeItem(at: legacyZlibURL)
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    /// Loads all saved song history entries from the LZFSE-compressed text file, newest first.
    public func load() -> [SongHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let rawData = try? Data(contentsOf: fileURL),
              !rawData.isEmpty else {
            return []
        }

        let textData: Data
        if let decompressed = try? (rawData as NSData).decompressed(using: .lzfse) as Data {
            textData = decompressed
        } else if let decompressedZlib = try? (rawData as NSData).decompressed(using: .zlib) as Data {
            textData = decompressedZlib
        } else {
            // Graceful fallback if the file was written as plain UTF-8 text
            textData = rawData
        }

        guard let text = String(data: textData, encoding: .utf8) else {
            return []
        }

        return decodeText(text)
    }

    /// Saves the entire list of song history entries to the LZFSE-compressed text file atomically.
    @discardableResult
    public func save(_ entries: [SongHistoryEntry]) -> Bool {
        let text = encodeText(entries)
        guard let textData = text.data(using: .utf8) else {
            return false
        }

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let compressedData = try (textData as NSData).compressed(using: .lzfse) as Data
            try compressedData.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Appends a new song to history if it differs from the most recent entry (or updates cover URL if missing).
    @discardableResult
    public func recordSong(
        _ metadata: SongMetadata,
        station: StationStream,
        playedAt: Date = Date(),
        existingEntries: [SongHistoryEntry]? = nil
    ) -> [SongHistoryEntry] {
        var entries = existingEntries ?? load()
        guard metadata.isMeaningfulTrack else { return entries }

        let key = metadata.normalizedKey
        if let latest = entries.first, latest.normalizedKey == key {
            // If the song is identical to the most recent entry, enrich missing cover/album metadata without duplicating
            var updatedLatest = latest
            var changed = false
            if updatedLatest.coverURLString.isEmpty, let cover = metadata.coverURLString, !cover.isEmpty {
                updatedLatest.coverURLString = cover
                changed = true
            }
            if updatedLatest.albumOrMix.isEmpty, !metadata.albumOrMix.isEmpty {
                updatedLatest.albumOrMix = metadata.albumOrMix
                changed = true
            }
            if updatedLatest.buyURLString.isEmpty, !metadata.buyURLString.isEmpty {
                updatedLatest.buyURLString = metadata.buyURLString
                changed = true
            }
            if changed {
                entries[0] = updatedLatest
                save(entries)
            }
            return entries
        }

        let newEntry = SongHistoryEntry(
            playedAt: playedAt,
            artist: metadata.artist,
            title: metadata.title,
            albumOrMix: metadata.albumOrMix,
            year: metadata.year,
            coverURLString: metadata.coverURLString ?? "",
            buyURLString: metadata.buyURLString,
            stationName: station.name,
            stationURLString: station.urlString
        )
        entries.insert(newEntry, at: 0)
        save(entries)
        return entries
    }

    // MARK: - Text Serialization (TSV)

    public func encodeText(_ entries: [SongHistoryEntry]) -> String {
        var lines: [String] = [Self.fileHeader]
        lines.reserveCapacity(entries.count + 1)

        for entry in entries {
            let fields: [String] = [
                entry.id.uuidString,
                isoFormatter.string(from: entry.playedAt),
                Self.escapeField(entry.artist),
                Self.escapeField(entry.title),
                Self.escapeField(entry.albumOrMix),
                Self.escapeField(entry.year),
                Self.escapeField(entry.coverURLString),
                Self.escapeField(entry.buyURLString),
                Self.escapeField(entry.stationName),
                Self.escapeField(entry.stationURLString)
            ]
            lines.append(fields.joined(separator: "\t"))
        }

        return lines.joined(separator: "\n")
    }

    public func decodeText(_ text: String) -> [SongHistoryEntry] {
        let fallbackISO = ISO8601DateFormatter()
        var entries: [SongHistoryEntry] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 4 else { continue }

            let id = UUID(uuidString: columns[0]) ?? UUID()
            let playedAt = isoFormatter.date(from: columns[1])
                ?? fallbackISO.date(from: columns[1])
                ?? Date()
            let artist = Self.unescapeField(columns[2])
            let title = Self.unescapeField(columns[3])
            let albumOrMix = columns.count > 4 ? Self.unescapeField(columns[4]) : ""
            let year = columns.count > 5 ? Self.unescapeField(columns[5]) : ""
            let coverURLString = columns.count > 6 ? Self.unescapeField(columns[6]) : ""
            let buyURLString = columns.count > 7 ? Self.unescapeField(columns[7]) : ""
            let stationName = columns.count > 8 ? Self.unescapeField(columns[8]) : "Chilltrax"
            let stationURLString = columns.count > 9 ? Self.unescapeField(columns[9]) : StationStream.defaultStream.urlString

            entries.append(
                SongHistoryEntry(
                    id: id,
                    playedAt: playedAt,
                    artist: artist,
                    title: title,
                    albumOrMix: albumOrMix,
                    year: year,
                    coverURLString: coverURLString,
                    buyURLString: buyURLString,
                    stationName: stationName,
                    stationURLString: stationURLString
                )
            )
        }

        return entries.sorted { $0.playedAt > $1.playedAt }
    }

    public var compressedFileSizeBytes: Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private static func escapeField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func unescapeField(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var iterator = value.makeIterator()
        while let ch = iterator.next() {
            if ch == "\\", let next = iterator.next() {
                switch next {
                case "t": result.append("\t")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "\\": result.append("\\")
                default:
                    result.append("\\")
                    result.append(next)
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }
}
