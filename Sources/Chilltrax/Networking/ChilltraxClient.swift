import Foundation

public struct StationDiscoveryResult: Equatable, Sendable {
    public let station: RadioStation
    public let streams: [StationStream]
    public let apiEndpoints: StationAPIEndpoints
    public let didChangeAPIEndpoints: Bool

    public init(
        station: RadioStation,
        streams: [StationStream],
        apiEndpoints: StationAPIEndpoints,
        didChangeAPIEndpoints: Bool
    ) {
        self.station = station
        self.streams = streams
        self.apiEndpoints = apiEndpoints
        self.didChangeAPIEndpoints = didChangeAPIEndpoints
    }
}

public final class ChilltraxClient: Sendable {
    public static let websiteURL = RadioStation.chilltrax.websiteURL
    public static let songInfoURL = URL(string: RadioStation.chilltrax.defaultAPIEndpoints.songInfoURLString)!
    public static let coverImageURL = URL(string: RadioStation.chilltrax.defaultAPIEndpoints.coverImageURLString)!
    public static let lastTenURL = URL(string: RadioStation.chilltrax.defaultAPIEndpoints.lastTenURLString)!

    public static let radioDanzWebsiteURL = RadioStation.radioDanz.websiteURL
    public static let radioDanzSongInfoURL = URL(string: RadioStation.radioDanz.defaultAPIEndpoints.songInfoURLString)!
    public static let radioDanzCoverImageURL = URL(string: RadioStation.radioDanz.defaultAPIEndpoints.coverImageURLString)!
    public static let radioDanzLastTenURL = URL(string: RadioStation.radioDanz.defaultAPIEndpoints.lastTenURLString)!

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 20
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Current Song & Cover Art

    public func fetchNowPlaying(
        station: RadioStation = .chilltrax,
        endpoints: StationAPIEndpoints? = nil,
        fetchAlbumCover: Bool
    ) async throws -> SongMetadata {
        let resolvedEndpoints = endpoints ?? station.defaultAPIEndpoints
        let infoURL = resolvedEndpoints.songInfoURL ?? station.defaultAPIEndpoints.songInfoURL!
        async let infoData = fetchData(from: infoURL)
        let rawInfo = try await infoData
        let decodedInfo = try JSONDecoder().decode(ChilltraxNowPlayingResponse.self, from: rawInfo)

        var coverURLString: String?
        if fetchAlbumCover {
            coverURLString = try? await fetchCurrentAlbumCoverURLString(
                station: station,
                endpoints: resolvedEndpoints
            )
        }

        return decodedInfo.toSongMetadata(coverURLString: coverURLString)
    }

    public func fetchCurrentAlbumCoverURLString(
        station: RadioStation = .chilltrax,
        endpoints: StationAPIEndpoints? = nil
    ) async throws -> String? {
        let resolvedEndpoints = endpoints ?? station.defaultAPIEndpoints
        let coverURL = resolvedEndpoints.coverImageURL ?? station.defaultAPIEndpoints.coverImageURL!
        let data = try await fetchData(from: coverURL)
        let response = try JSONDecoder().decode(ChilltraxCoverResponse.self, from: data)
        guard let rawCover = response.cover?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawCover.isEmpty else {
            return nil
        }

        if rawCover.hasPrefix("http://") || rawCover.hasPrefix("https://") {
            return rawCover
        }
        let cleaned = rawCover.hasPrefix("/") ? String(rawCover.dropFirst()) : rawCover
        return "\(station.websiteURL.absoluteString)\(cleaned)"
    }

    public func fetchLastTenTracks(
        station: RadioStation = .chilltrax,
        endpoints: StationAPIEndpoints? = nil
    ) async throws -> [SongMetadata] {
        let resolvedEndpoints = endpoints ?? station.defaultAPIEndpoints
        let url = resolvedEndpoints.lastTenURL ?? station.defaultAPIEndpoints.lastTenURL!
        let data = try await fetchData(from: url)
        let items = try JSONDecoder().decode([ChilltraxLastTenItem].self, from: data)
        return items.compactMap { item in
            let artist = ChilltraxNowPlayingResponse.decodeHTMLEntities(item.artist ?? "")
            let title = ChilltraxNowPlayingResponse.decodeHTMLEntities(item.title ?? "")
            guard !artist.isEmpty || !title.isEmpty else { return nil }
            let rawPicture = item.picture?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCover: String?
            if let rawPicture, !rawPicture.isEmpty {
                if rawPicture.hasPrefix("http://") || rawPicture.hasPrefix("https://") {
                    resolvedCover = rawPicture
                } else {
                    let cleaned = rawPicture.hasPrefix("/") ? String(rawPicture.dropFirst()) : rawPicture
                    resolvedCover = "\(station.websiteURL.absoluteString)\(cleaned)"
                }
            } else {
                resolvedCover = nil
            }
            return SongMetadata(
                artist: artist,
                title: title,
                albumOrMix: ChilltraxNowPlayingResponse.decodeHTMLEntities(item.mix ?? ""),
                year: item.year ?? "",
                buyURLString: item.buycd ?? "",
                coverURLString: resolvedCover
            )
        }
    }

    // MARK: - Discover Broadcast Streams & API URLs from chilltrax.com and radiodanz.com

    public func discoverBroadcastStreamsFromWebsite(for station: RadioStation = .chilltrax) async throws -> [StationStream] {
        let result = try await discoverStationConfiguration(for: station)
        return result.streams
    }

    public func discoverStationConfiguration(
        for station: RadioStation,
        previousEndpoints: StationAPIEndpoints? = nil
    ) async throws -> StationDiscoveryResult {
        let data = try await fetchData(from: station.websiteURL)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            let defaults = station.defaultAPIEndpoints
            return StationDiscoveryResult(
                station: station,
                streams: station.defaultStreams,
                apiEndpoints: defaults,
                didChangeAPIEndpoints: false
            )
        }
        let discoveredStreams = Self.parseBroadcastStreams(fromHTML: html, station: station)
        let streams = discoveredStreams.isEmpty ? station.defaultStreams : discoveredStreams
        let discoveredEndpoints = Self.parseAPIEndpoints(fromHTML: html, station: station)
        let baseline = previousEndpoints ?? station.defaultAPIEndpoints
        return StationDiscoveryResult(
            station: station,
            streams: streams,
            apiEndpoints: discoveredEndpoints,
            didChangeAPIEndpoints: discoveredEndpoints != baseline
        )
    }

    /// Scans both `chilltrax.com` and `radiodanz.com` concurrently for broadcast streams and API URL changes.
    public func discoverAllStationsConfiguration(
        previousEndpointsByStation: [RadioStation: StationAPIEndpoints] = [:]
    ) async throws -> [RadioStation: StationDiscoveryResult] {
        var results: [RadioStation: StationDiscoveryResult] = [:]
        var lastError: Error?

        for station in RadioStation.allCases {
            do {
                let result = try await discoverStationConfiguration(
                    for: station,
                    previousEndpoints: previousEndpointsByStation[station]
                )
                results[station] = result
            } catch {
                lastError = error
            }
        }

        if results.isEmpty, let lastError {
            throw lastError
        }

        return results
    }

    public static func parseAPIEndpoints(fromHTML html: String, station: RadioStation = .chilltrax) -> StationAPIEndpoints {
        var endpoints = station.defaultAPIEndpoints

        func resolveEndpoint(_ rawPath: String) -> String {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return trimmed
            }
            if let resolved = URL(string: trimmed, relativeTo: station.websiteURL)?.absoluteURL {
                return resolved.absoluteString
            }
            let cleaned = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
            return "\(station.websiteURL.absoluteString)\(cleaned)"
        }

        func firstMatch(pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                return nil
            }
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return String(html[range])
        }

        if let songPath = firstMatch(pattern: #"function\s+getSongInformation\s*\(\s*\)\s*\{[^}]*?(?:getJSON|fetch|ajax)\s*\(\s*["']([^"']+\.php[^"']*)["']"#)
            ?? firstMatch(pattern: #"["']((?:https?://[^"']+/)?php/GetSongInformation[^"']*\.php[^"']*)["']"#) {
            endpoints.songInfoURLString = resolveEndpoint(songPath)
        }

        if let coverPath = firstMatch(pattern: #"function\s+getCover\s*\(\s*\)\s*\{[^}]*?(?:getJSON|fetch|ajax)\s*\(\s*["']([^"']+\.php[^"']*)["']"#)
            ?? firstMatch(pattern: #"["']((?:https?://[^"']+/)?php/GetCoverImage[^"']*\.php[^"']*)["']"#) {
            endpoints.coverImageURLString = resolveEndpoint(coverPath)
        }

        if let lastTenPath = firstMatch(pattern: #"function\s+updateLast10\s*\(\s*\)\s*\{[^}]*?(?:getJSON|fetch|ajax)\s*\(\s*["']([^"']+\.php[^"']*)["']"#)
            ?? firstMatch(pattern: #"["']((?:https?://[^"']+/)?php/GetLastTen[^"']*\.php[^"']*)["']"#) {
            endpoints.lastTenURLString = resolveEndpoint(lastTenPath)
        }

        return endpoints
    }

    public static func parseBroadcastStreams(fromHTML html: String, station: RadioStation = .chilltrax) -> [StationStream] {
        var streams: [StationStream] = []
        var seenURLs = Set<String>()
        let stationTitle = station.title
        let lowerStationTitle = stationTitle.lowercased()

        func appendStream(_ stream: StationStream) {
            let key = stream.urlString.lowercased()
            guard !seenURLs.contains(key) else { return }
            seenURLs.insert(key)
            streams.append(stream)
        }

        // 1. Extract web player `streamurl: "..."` if present in page script
        let playerRegexPattern = #"streamurl\s*:\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: playerRegexPattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, options: [], range: nsRange) {
                if match.numberOfRanges > 1,
                   let urlRange = Range(match.range(at: 1), in: html) {
                    let rawURL = String(html[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if rawURL.hasPrefix("http") {
                        appendStream(
                            StationStream(
                                id: rawURL,
                                name: "\(stationTitle) — Web Player Live Stream (128Kbps MP3 HTTPS)",
                                urlString: rawURL,
                                formatDetails: "128Kbps MP3 • HTTPS Direct",
                                isChilltraxOfficial: true,
                                station: station
                            )
                        )
                    }
                }
            }
        }

        // 2. Extract `<a ... href="...">Label</a>` links from the "HOW TO LISTEN" section
        let anchorPattern = #"<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, options: [], range: nsRange) {
                guard match.numberOfRanges > 2,
                      let hrefRange = Range(match.range(at: 1), in: html),
                      let labelRange = Range(match.range(at: 2), in: html) else {
                    continue
                }
                let href = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawLabel = String(html[labelRange])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let label = ChilltraxNowPlayingResponse.decodeHTMLEntities(rawLabel)

                let lowerHref = href.lowercased()
                let isStreamLink = lowerHref.contains("streams.electronicmusicradiogroup.org")
                    || lowerHref.contains("chilltrax.com/listen")
                    || lowerHref.contains("streamssleu.chilltrax.com")
                    || lowerHref.contains("radiodanz.com/results")
                    || lowerHref.contains("streamssl.radiodanz.com")
                    || lowerHref.hasSuffix(".pls")
                    || lowerHref.contains(".pls?")
                    || lowerHref.hasSuffix(".m3u")
                    || lowerHref.hasSuffix(".m3u8")

                guard isStreamLink, !label.isEmpty else { continue }

                let formatDetails = extractFormatBadge(from: label)
                let displayName = label.lowercased().contains(lowerStationTitle) ? label : "\(stationTitle) — \(label)"
                appendStream(
                    StationStream(
                        id: href,
                        name: displayName,
                        urlString: href,
                        formatDetails: formatDetails,
                        isChilltraxOfficial: true,
                        station: station
                    )
                )
            }
        }

        // 3. Ensure direct SSL stream is also available for the station
        switch station {
        case .chilltrax:
            if seenURLs.contains("https://www.chilltrax.com/listen") || seenURLs.contains("https://www.chilltrax.com/listen/?mode=redirect") {
                appendStream(
                    StationStream(
                        id: "https://streamssleu.chilltrax.com/stream?sid=1",
                        name: "Chilltrax — Direct SSL Stream (128Kbps MP3)",
                        urlString: "https://streamssleu.chilltrax.com/stream?sid=1",
                        formatDetails: "128Kbps MP3 • Direct SSL",
                        isChilltraxOfficial: true,
                        station: .chilltrax
                    )
                )
            }
        case .radioDanz:
            if seenURLs.contains("https://www.radiodanz.com/results/?mode=redirect")
                || seenURLs.contains("http://streamssl.radiodanz.com/listen.pls?sid=1") {
                appendStream(
                    StationStream(
                        id: "https://streamssl.radiodanz.com/live",
                        name: "Radio Danz — Direct SSL Stream (128Kbps MP3)",
                        urlString: "https://streamssl.radiodanz.com/live",
                        formatDetails: "128Kbps MP3 • Direct SSL",
                        isChilltraxOfficial: true,
                        station: .radioDanz
                    )
                )
            }
        }

        return streams
    }

    // MARK: - Stream / Playlist URL Resolution

    /// Resolves `.pls` playlists, `.m3u` playlists, and Shoutcast base URLs into a playable audio stream URL for `AVPlayer`.
    public func resolvePlayableStreamURL(for originalURL: URL) async -> URL {
        let urlString = originalURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = urlString.lowercased()

        // Direct chilltrax.com/listen or any .pls playlist URL
        if lower == "https://www.chilltrax.com/listen"
            || lower == "https://www.chilltrax.com/listen/"
            || lower.hasSuffix(".pls")
            || lower.contains(".pls?") {
            if let resolved = await resolvePLSPlaylist(from: originalURL) {
                return resolved
            }
            if lower.contains("chilltrax.com/listen") {
                return URL(string: "https://streamssleu.chilltrax.com/stream?sid=1") ?? originalURL
            }
            if lower.contains("radiodanz.com") {
                return URL(string: "https://streamssl.radiodanz.com/live") ?? originalURL
            }
            if let components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false),
               components.port != nil {
                var streamComponents = components
                streamComponents.path = "/;stream.mp3"
                streamComponents.query = nil
                if let candidate = streamComponents.url {
                    return candidate
                }
            }
        }

        // Shoutcast v1/v2 bare host:port URLs (e.g. http://streams.electronicmusicradiogroup.org:9050)
        if let components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false),
           components.port != nil,
           (components.path.isEmpty || components.path == "/") {
            var streamComponents = components
            streamComponents.path = "/;stream.mp3"
            if let candidate = streamComponents.url {
                return candidate
            }
        }

        return originalURL
    }

    public static func parsePLSStreamURL(from plsContent: String) -> URL? {
        for rawLine in plsContent.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("file1=") {
                let value = String(line.dropFirst("file1=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: value) {
                    return url
                }
            }
        }
        return nil
    }

    private func resolvePLSPlaylist(from url: URL) async -> URL? {
        guard let data = try? await fetchData(from: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        return Self.parsePLSStreamURL(from: text)
    }

    private static func extractFormatBadge(from label: String) -> String {
        let pattern = #"(\d+\s*Kbps\s*(?:AAC\+|AAC|MP3|OGG|FLAC)?)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: label, options: [], range: NSRange(label.startIndex..<label.endIndex, in: label)),
           let range = Range(match.range(at: 1), in: label) {
            return String(label[range])
        }
        return "Live Stream"
    }

    // MARK: - iTunes Search API Fallback for Missing Album Covers

    private struct ITunesSearchResponse: Decodable {
        struct Item: Decodable {
            let artistName: String?
            let trackName: String?
            let collectionName: String?
            let artworkUrl100: String?
        }
        let results: [Item]
    }

    public func searchAlbumCoverURLString(artist: String, title: String, album: String = "") async throws -> String? {
        let query = [artist, title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components?.url else { return nil }

        let data = try await fetchData(from: url)
        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        guard let firstWithArtwork = decoded.results.first(where: { !($0.artworkUrl100 ?? "").isEmpty }),
              let rawArtwork = firstWithArtwork.artworkUrl100?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawArtwork.isEmpty else {
            return nil
        }
        return rawArtwork.replacingOccurrences(of: "100x100bb", with: "300x300bb")
    }

    public func fetchImageData(from url: URL) async throws -> Data {
        try await fetchData(from: url)
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("ChilltraxMacOS/1.2 (macOS 14.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
