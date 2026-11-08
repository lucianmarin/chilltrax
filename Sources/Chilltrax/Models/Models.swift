import Foundation

public enum VisualizerMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off = "off"
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

    public var isVisible: Bool {
        self != .off
    }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .waveform: return "Waveform"
        case .spectrum: return "Spectrum"
        }
    }

    public var systemImage: String {
        switch self {
        case .off: return "text.alignleft"
        case .waveform: return "waveform.path.ecg"
        case .spectrum: return "chart.bar.xaxis"
        }
    }
}

public enum RadioStation: String, CaseIterable, Codable, Identifiable, Sendable {
    case chilltrax = "chilltrax"
    case radioDanz = "radiodanz"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chilltrax: return "Chilltrax"
        case .radioDanz: return "Radio Danz"
        }
    }

    public var badgeLabel: String {
        switch self {
        case .chilltrax: return "TRAX"
        case .radioDanz: return "DANZ"
        }
    }

    public var nextStation: RadioStation {
        switch self {
        case .chilltrax: return .radioDanz
        case .radioDanz: return .chilltrax
        }
    }

    public var domain: String {
        switch self {
        case .chilltrax: return "chilltrax.com"
        case .radioDanz: return "radiodanz.com"
        }
    }

    public var websiteURL: URL {
        switch self {
        case .chilltrax: return URL(string: "https://www.chilltrax.com/")!
        case .radioDanz: return URL(string: "https://www.radiodanz.com/")!
        }
    }

    public var defaultAPIEndpoints: StationAPIEndpoints {
        StationAPIEndpoints(
            songInfoURLString: "\(websiteURL.absoluteString)php/GetSongInformationNew.php",
            coverImageURLString: "\(websiteURL.absoluteString)php/GetCoverImageNew.php",
            lastTenURLString: "\(websiteURL.absoluteString)php/GetLastTenNew.php"
        )
    }

    public var defaultStream: StationStream {
        StationStream.preferredDefaultStream(for: self)
    }

    public func preferredDefaultStream(from streams: [StationStream]) -> StationStream {
        StationStream.preferredDefaultStream(for: self, in: streams)
    }

    public var defaultStreams: [StationStream] {
        switch self {
        case .chilltrax: return StationStream.defaultChilltraxStreams
        case .radioDanz: return StationStream.defaultRadioDanzStreams
        }
    }

    public static func infer(stationName: String, stationURLString: String) -> RadioStation {
        let lowerName = stationName.lowercased()
        let lowerURL = stationURLString.lowercased()
        if lowerName.contains("danz")
            || lowerURL.contains("radiodanz")
            || lowerURL.contains(":8000")
            || lowerURL.contains(":8010")
            || lowerURL.contains(":8020")
            || lowerURL.contains(":8030") {
            return .radioDanz
        }
        return .chilltrax
    }
}

public struct StationAPIEndpoints: Codable, Equatable, Hashable, Sendable {
    public var songInfoURLString: String
    public var coverImageURLString: String
    public var lastTenURLString: String

    public init(
        songInfoURLString: String,
        coverImageURLString: String,
        lastTenURLString: String
    ) {
        self.songInfoURLString = songInfoURLString
        self.coverImageURLString = coverImageURLString
        self.lastTenURLString = lastTenURLString
    }

    public var songInfoURL: URL? { URL(string: songInfoURLString) }
    public var coverImageURL: URL? { URL(string: coverImageURLString) }
    public var lastTenURL: URL? { URL(string: lastTenURLString) }
}

public struct StationStream: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var urlString: String
    public var formatDetails: String
    public var isChilltraxOfficial: Bool
    public var station: RadioStation

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case urlString
        case formatDetails
        case isChilltraxOfficial
        case station
    }

    public init(
        id: String? = nil,
        name: String,
        urlString: String,
        formatDetails: String = "",
        isChilltraxOfficial: Bool = true,
        station: RadioStation? = nil
    ) {
        self.id = id ?? urlString
        self.name = name
        self.urlString = urlString
        self.formatDetails = formatDetails
        self.isChilltraxOfficial = isChilltraxOfficial
        self.station = station ?? RadioStation.infer(stationName: name, stationURLString: urlString)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlString = try container.decode(String.self, forKey: .urlString)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? urlString
        let name = try container.decode(String.self, forKey: .name)
        let formatDetails = try container.decodeIfPresent(String.self, forKey: .formatDetails) ?? ""
        let isChilltraxOfficial = try container.decodeIfPresent(Bool.self, forKey: .isChilltraxOfficial) ?? true
        let station = try container.decodeIfPresent(RadioStation.self, forKey: .station)
            ?? RadioStation.infer(stationName: name, stationURLString: urlString)

        self.init(
            id: id,
            name: name,
            urlString: urlString,
            formatDetails: formatDetails,
            isChilltraxOfficial: isChilltraxOfficial,
            station: station
        )
    }

    public var url: URL? {
        URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static let defaultStream = StationStream(
        id: "https://www.chilltrax.com/listen/?mode=redirect",
        name: "Chilltrax — 128Kbps MP3 (Firewall Friendly HTTPS)",
        urlString: "https://www.chilltrax.com/listen/?mode=redirect",
        formatDetails: "128Kbps MP3 • HTTPS Direct",
        isChilltraxOfficial: true,
        station: .chilltrax
    )

    public static let defaultRadioDanzStream = StationStream(
        id: "https://www.radiodanz.com/results/?mode=redirect",
        name: "Radio Danz — 128Kbps MP3 (Firewall Friendly HTTPS)",
        urlString: "https://www.radiodanz.com/results/?mode=redirect",
        formatDetails: "128Kbps MP3 • HTTPS Direct",
        isChilltraxOfficial: true,
        station: .radioDanz
    )

    public static let defaultChilltraxStreams: [StationStream] = [
        defaultStream,
        StationStream(
            id: "https://streamssleu.chilltrax.com/stream?sid=1",
            name: "Chilltrax — EU SSL Direct Stream (128Kbps MP3)",
            urlString: "https://streamssleu.chilltrax.com/stream?sid=1",
            formatDetails: "128Kbps MP3 • Shoutcast SSL",
            isChilltraxOfficial: true,
            station: .chilltrax
        ),
        StationStream(
            id: "https://www.chilltrax.com/listen",
            name: "Chilltrax — High Quality 128Kbps MP3 (PLS)",
            urlString: "https://www.chilltrax.com/listen",
            formatDetails: "128Kbps MP3 • Playlist",
            isChilltraxOfficial: true,
            station: .chilltrax
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9050",
            name: "Chilltrax — Highest (HD) Quality 128Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:9050",
            formatDetails: "128Kbps AAC+",
            isChilltraxOfficial: true,
            station: .chilltrax
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9000",
            name: "Chilltrax — High Quality 128Kbps MP3",
            urlString: "http://streams.electronicmusicradiogroup.org:9000",
            formatDetails: "128Kbps MP3",
            isChilltraxOfficial: true,
            station: .chilltrax
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9020",
            name: "Chilltrax — High Quality 80Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:9020",
            formatDetails: "80Kbps AAC+",
            isChilltraxOfficial: true,
            station: .chilltrax
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:9010",
            name: "Chilltrax — High Quality 64Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:9010",
            formatDetails: "64Kbps AAC+",
            isChilltraxOfficial: true,
            station: .chilltrax
        )
    ]

    public static let defaultRadioDanzStreams: [StationStream] = [
        defaultRadioDanzStream,
        StationStream(
            id: "https://streamssl.radiodanz.com/live",
            name: "Radio Danz — Direct SSL Stream (128Kbps MP3)",
            urlString: "https://streamssl.radiodanz.com/live",
            formatDetails: "128Kbps MP3 • Direct SSL",
            isChilltraxOfficial: true,
            station: .radioDanz
        ),
        StationStream(
            id: "http://streamssl.radiodanz.com/listen.pls?sid=1",
            name: "Radio Danz — High Quality 128Kbps MP3 (firewall friendly)",
            urlString: "http://streamssl.radiodanz.com/listen.pls?sid=1",
            formatDetails: "128Kbps MP3 • Playlist",
            isChilltraxOfficial: true,
            station: .radioDanz
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:8030/listen.pls",
            name: "Radio Danz — Highest (HD) Quality 128Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:8030/listen.pls",
            formatDetails: "128Kbps AAC+",
            isChilltraxOfficial: true,
            station: .radioDanz
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:8000/listen.pls",
            name: "Radio Danz — High Quality 128Kbps MP3",
            urlString: "http://streams.electronicmusicradiogroup.org:8000/listen.pls",
            formatDetails: "128Kbps MP3",
            isChilltraxOfficial: true,
            station: .radioDanz
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:8020/listen.pls",
            name: "Radio Danz — High Quality 80Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:8020/listen.pls",
            formatDetails: "80Kbps AAC+",
            isChilltraxOfficial: true,
            station: .radioDanz
        ),
        StationStream(
            id: "http://streams.electronicmusicradiogroup.org:8010/listen.pls",
            name: "Radio Danz — High Quality 64Kbps AAC+",
            urlString: "http://streams.electronicmusicradiogroup.org:8010/listen.pls",
            formatDetails: "64Kbps AAC+",
            isChilltraxOfficial: true,
            station: .radioDanz
        )
    ]

    public static var defaultAllStreams: [StationStream] {
        defaultChilltraxStreams + defaultRadioDanzStreams
    }

    public static func defaultStreams(for station: RadioStation) -> [StationStream] {
        switch station {
        case .chilltrax: return defaultChilltraxStreams
        case .radioDanz: return defaultRadioDanzStreams
        }
    }

    public static func preferredDefaultStream(
        for station: RadioStation,
        in streams: [StationStream]? = nil
    ) -> StationStream {
        let stationStreams = (streams ?? defaultStreams(for: station)).filter { $0.station == station }
        let candidates = stationStreams.isEmpty ? defaultStreams(for: station) : stationStreams
        if let redirectStream = candidates.first(where: { $0.urlString.localizedCaseInsensitiveContains("redirect") }) {
            return redirectStream
        }
        if let secondBest = candidates.first(where: { !$0.urlString.localizedCaseInsensitiveContains("redirect") }) {
            return secondBest
        }
        let fallbackCandidates = defaultStreams(for: station).filter {
            !$0.urlString.localizedCaseInsensitiveContains("redirect")
        }
        return fallbackCandidates.first ?? defaultStreams(for: station).first!
    }
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

    public var clipboardText: String {
        if artist.isEmpty { return title }
        if title.isEmpty { return artist }
        return "\(artist) - \(title)"
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
        if lowerTitle == "radio danz" && lowerArtist.isEmpty { return false }
        if lowerTitle.contains("the world's chillout channel") { return false }
        if lowerTitle.contains("the world's pure dance channel") { return false }
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

    public var clipboardText: String {
        if artist.isEmpty { return title }
        if title.isEmpty { return artist }
        return "\(artist) - \(title)"
    }

    public var normalizedKey: String {
        "\(artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    public var station: RadioStation {
        RadioStation.infer(stationName: stationName, stationURLString: stationURLString)
    }

    public var stationBadgeLabel: String {
        station.badgeLabel
    }

    public var coverURL: URL? {
        guard !coverURLString.isEmpty else { return nil }
        if coverURLString.hasPrefix("http://") || coverURLString.hasPrefix("https://") {
            return URL(string: coverURLString)
        }
        let trimmed = coverURLString.hasPrefix("/") ? String(coverURLString.dropFirst()) : coverURLString
        return URL(string: "\(station.websiteURL.absoluteString)\(trimmed)")
    }

    public var buyURL: URL? {
        guard !buyURLString.isEmpty else { return nil }
        return URL(string: buyURLString)
    }

    public func matches(searchQuery: String) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let terms = query.split(whereSeparator: \.isWhitespace)
        let haystack = "\(title) \(artist) \(albumOrMix) \(year) \(stationName) \(stationBadgeLabel)".lowercased()
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
