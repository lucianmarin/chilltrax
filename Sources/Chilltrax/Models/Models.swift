import Foundation

public enum VisualizerMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case waveform = "waveform"
    case spectrum = "spectrum"

    public static var bars: VisualizerMode { .spectrum }

    public init?(persistedRawValue: String) {
        if persistedRawValue == "bars" {
            self = .spectrum
        } else {
            self.init(rawValue: persistedRawValue)
        }
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .waveform: return "Waveform"
        case .spectrum: return "Spectrum"
        }
    }

    public var systemImage: String {
        switch self {
        case .waveform: return "waveform.path.ecg"
        case .spectrum: return "chart.bar.xaxis"
        }
    }
}

public struct StationStream: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var urlString: String
    public var formatDetails: String
    public var isChilltraxOfficial: Bool

    public init(
        id: String? = nil,
        name: String,
        urlString: String,
        formatDetails: String = "",
        isChilltraxOfficial: Bool = true
    ) {
        self.id = id ?? urlString
        self.name = name
        self.urlString = urlString
        self.formatDetails = formatDetails
        self.isChilltraxOfficial = isChilltraxOfficial
    }

    public var url: URL? {
        URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static let defaultStream = StationStream(
        id: "https://www.chilltrax.com/listen/?mode=redirect",
        name: "Chilltrax — 128Kbps MP3 (Firewall Friendly HTTPS)",
        urlString: "https://www.chilltrax.com/listen/?mode=redirect",
        formatDetails: "128Kbps MP3 • HTTPS Direct",
        isChilltraxOfficial: true
    )

    public static let defaultChilltraxStreams: [StationStream] = [
        defaultStream,
        StationStream(
            id: "https://streamssleu.chilltrax.com/stream?sid=1",
            name: "Chilltrax — EU SSL Direct Stream (128Kbps MP3)",
            urlString: "https://streamssleu.chilltrax.com/stream?sid=1",
            formatDetails: "128Kbps MP3 • Shoutcast SSL",
            isChilltraxOfficial: true
        ),
        StationStream(
            id: "https://www.chilltrax.com/listen",
            name: "Chilltrax — High Quality 128Kbps MP3 (PLS)",
            urlString: "https://www.chilltrax.com/listen",
            formatDetails: "128Kbps MP3 • Playlist",
            isChilltraxOfficial: true
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9050",
            name: "Chilltrax — Highest (HD) Quality 128Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:9050",
            formatDetails: "128Kbps AAC+",
            isChilltraxOfficial: true
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9000",
            name: "Chilltrax — High Quality 128Kbps MP3",
            urlString: "http://streams.electronicmusicradiogroup.org:9000",
            formatDetails: "128Kbps MP3",
            isChilltraxOfficial: true
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9020",
            name: "Chilltrax — High Quality 80Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:9020",
            formatDetails: "80Kbps AAC+",
            isChilltraxOfficial: true
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9010",
            name: "Chilltrax — High Quality 64Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:9010",
            formatDetails: "64Kbps AAC+",
            isChilltraxOfficial: true
        )
    ]
}

public struct SongMetadata: Equatable, Codable, Sendable {
    public var artist: String
    public var title: String
    public var albumOrMix: String
    public var label: String
    public var year: String
    public var buyURLString: String
    public var coverURLString: String?
    public var songID: Int?

    public init(
        artist: String,
        title: String,
        albumOrMix: String = "",
        label: String = "",
        year: String = "",
        buyURLString: String = "",
        coverURLString: String? = nil,
        songID: Int? = nil
    ) {
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.albumOrMix = albumOrMix.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.year = year.trimmingCharacters(in: .whitespacesAndNewlines)
        self.buyURLString = buyURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.coverURLString = coverURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.songID = songID
    }

    public var displayName: String {
        if !isMeaningfulTrack {
            return "Artist — Title"
        }
        if artist.isEmpty {
            return title
        }
        if title.isEmpty {
            return artist
        }
        return "\(artist) — \(title)"
    }

    public var normalizedKey: String {
        "\(artist.lowercased())|\(title.lowercased())"
    }

    public var isMeaningfulTrack: Bool {
        let lowerTitle = title.lowercased()
        let lowerArtist = artist.lowercased()
        if title.isEmpty && artist.isEmpty { return false }
        if lowerTitle == "title" && (lowerArtist.isEmpty || lowerArtist == "artist") { return false }
        if lowerTitle == "chilltrax" && lowerArtist.isEmpty { return false }
        if lowerTitle.contains("the world's chillout channel") { return false }
        return true
    }

    public var coverURL: URL? {
        guard let raw = coverURLString, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let trimmed = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        return URL(string: "https://www.chilltrax.com/\(trimmed)")
    }

    public var buyURL: URL? {
        guard !buyURLString.isEmpty else { return nil }
        return URL(string: buyURLString)
    }

    /// Parses an ICY `StreamTitle` string like `"Artist - Title"` into `SongMetadata`.
    public static func fromICYStreamTitle(_ rawTitle: String) -> SongMetadata? {
        let cleaned = rawTitle
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let range = cleaned.range(of: " - ") {
            let artist = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return SongMetadata(artist: artist, title: title)
        } else {
            return SongMetadata(artist: "", title: cleaned)
        }
    }

    public static let placeholder = SongMetadata(
        artist: "Artist",
        title: "Title",
        albumOrMix: "Album"
    )
}

public struct SongHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let playedAt: Date
    public var artist: String
    public var title: String
    public var albumOrMix: String
    public var year: String
    public var coverURLString: String
    public var buyURLString: String
    public var stationName: String
    public var stationURLString: String

    public init(
        id: UUID = UUID(),
        playedAt: Date = Date(),
        artist: String,
        title: String,
        albumOrMix: String = "",
        year: String = "",
        coverURLString: String = "",
        buyURLString: String = "",
        stationName: String = "Chilltrax",
        stationURLString: String = StationStream.defaultStream.urlString
    ) {
        self.id = id
        self.playedAt = playedAt
        self.artist = artist
        self.title = title
        self.albumOrMix = albumOrMix
        self.year = year
        self.coverURLString = coverURLString
        self.buyURLString = buyURLString
        self.stationName = stationName
        self.stationURLString = stationURLString
    }

    public var displayName: String {
        if artist.isEmpty { return title }
        if title.isEmpty { return artist }
        return "\(artist) — \(title)"
    }

    public var normalizedKey: String {
        "\(artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    public var coverURL: URL? {
        guard !coverURLString.isEmpty else { return nil }
        if coverURLString.hasPrefix("http://") || coverURLString.hasPrefix("https://") {
            return URL(string: coverURLString)
        }
        let trimmed = coverURLString.hasPrefix("/") ? String(coverURLString.dropFirst()) : coverURLString
        return URL(string: "https://www.chilltrax.com/\(trimmed)")
    }

    public var buyURL: URL? {
        guard !buyURLString.isEmpty else { return nil }
        return URL(string: buyURLString)
    }

    public func matches(searchQuery: String) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let terms = query.split(whereSeparator: \.isWhitespace)
        let haystack = "\(title) \(artist) \(albumOrMix) \(year) \(stationName)".lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

// MARK: - Chilltrax JSON API Models

public struct ChilltraxNowPlayingResponse: Codable, Equatable, Sendable {
    public let artist: String?
    public let title: String?
    public let mix: String?
    public let label: String?
    public let year: String?
    public let buycd: String?
    public let newSong: String?
    public let songID: Int?

    public func toSongMetadata(coverURLString: String? = nil) -> SongMetadata {
        SongMetadata(
            artist: Self.decodeHTMLEntities(artist ?? ""),
            title: Self.decodeHTMLEntities(title ?? ""),
            albumOrMix: Self.decodeHTMLEntities(mix ?? ""),
            label: Self.decodeHTMLEntities(label ?? ""),
            year: year ?? "",
            buyURLString: buycd ?? "",
            coverURLString: coverURLString,
            songID: songID
        )
    }

    public static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

public struct ChilltraxCoverResponse: Codable, Equatable, Sendable {
    public let cover: String?
}

public struct ChilltraxLastTenItem: Codable, Equatable, Sendable {
    public let artist: String?
    public let title: String?
    public let mix: String?
    public let date_played: String?
    public let picture: String?
    public let year: String?
    public let buycd: String?
}
