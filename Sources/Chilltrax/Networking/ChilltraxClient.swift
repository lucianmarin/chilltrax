import Foundation

public final class ChilltraxClient: Sendable {
    public static let websiteURL = URL(string: "https://www.chilltrax.com/")!
    public static let songInfoURL = URL(string: "https://www.chilltrax.com/php/GetSongInformationNew.php")!
    public static let coverImageURL = URL(string: "https://www.chilltrax.com/php/GetCoverImageNew.php")!
    public static let lastTenURL = URL(string: "https://www.chilltrax.com/php/GetLastTenNew.php")!

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

    public func fetchNowPlaying(fetchAlbumCover: Bool) async throws -> SongMetadata {
        async let infoData = fetchData(from: Self.songInfoURL)
        let rawInfo = try await infoData
        let decodedInfo = try JSONDecoder().decode(ChilltraxNowPlayingResponse.self, from: rawInfo)

        var coverURLString: String?
        if fetchAlbumCover {
            coverURLString = try? await fetchCurrentAlbumCoverURLString()
        }

        return decodedInfo.toSongMetadata(coverURLString: coverURLString)
    }

    public func fetchCurrentAlbumCoverURLString() async throws -> String? {
        let data = try await fetchData(from: Self.coverImageURL)
        let response = try JSONDecoder().decode(ChilltraxCoverResponse.self, from: data)
        guard let rawCover = response.cover?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawCover.isEmpty else {
            return nil
        }

        if rawCover.hasPrefix("http://") || rawCover.hasPrefix("https://") {
            return rawCover
        }
        let cleaned = rawCover.hasPrefix("/") ? String(rawCover.dropFirst()) : rawCover
        return "https://www.chilltrax.com/\(cleaned)"
    }

    public func fetchLastTenTracks() async throws -> [SongMetadata] {
        let data = try await fetchData(from: Self.lastTenURL)
        let items = try JSONDecoder().decode([ChilltraxLastTenItem].self, from: data)
        return items.compactMap { item in
            let artist = ChilltraxNowPlayingResponse.decodeHTMLEntities(item.artist ?? "")
            let title = ChilltraxNowPlayingResponse.decodeHTMLEntities(item.title ?? "")
            guard !artist.isEmpty || !title.isEmpty else { return nil }
            return SongMetadata(
                artist: artist,
                title: title,
                albumOrMix: ChilltraxNowPlayingResponse.decodeHTMLEntities(item.mix ?? ""),
                year: item.year ?? "",
                buyURLString: item.buycd ?? "",
                coverURLString: item.picture
            )
        }
    }

    // MARK: - Discover Broadcast Streams from chilltrax.com

    /// Fetches `https://www.chilltrax.com/` and extracts all broadcast stream URLs advertised on the website,
    /// including both the web player stream URL (`streamurl:`) and the `HOW TO LISTEN` stream links.
    public func discoverBroadcastStreamsFromWebsite() async throws -> [StationStream] {
        let data = try await fetchData(from: Self.websiteURL)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return StationStream.defaultChilltraxStreams
        }
        let discovered = Self.parseBroadcastStreams(fromHTML: html)
        return discovered.isEmpty ? StationStream.defaultChilltraxStreams : discovered
    }

    public static func parseBroadcastStreams(fromHTML html: String) -> [StationStream] {
        var streams: [StationStream] = []
        var seenURLs = Set<String>()

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
                                name: "Chilltrax — Web Player Live Stream (128Kbps MP3 HTTPS)",
                                urlString: rawURL,
                                formatDetails: "128Kbps MP3 • HTTPS Direct",
                                isChilltraxOfficial: true
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
                    || lowerHref.hasSuffix(".pls")
                    || lowerHref.hasSuffix(".m3u")
                    || lowerHref.hasSuffix(".m3u8")

                guard isStreamLink, !label.isEmpty else { continue }

                let formatDetails = extractFormatBadge(from: label)
                let displayName = label.lowercased().contains("chilltrax") ? label : "Chilltrax — \(label)"
                appendStream(
                    StationStream(
                        id: href,
                        name: displayName,
                        urlString: href,
                        formatDetails: formatDetails,
                        isChilltraxOfficial: true
                    )
                )
            }
        }

        // 3. Ensure direct EU SSL stream is also available if chilltrax.com/listen was found
        if seenURLs.contains("https://www.chilltrax.com/listen") || seenURLs.contains("https://www.chilltrax.com/listen/?mode=redirect") {
            appendStream(
                StationStream(
                    id: "https://streamssleu.chilltrax.com/stream?sid=1",
                    name: "Chilltrax — Direct SSL Stream (128Kbps MP3)",
                    urlString: "https://streamssleu.chilltrax.com/stream?sid=1",
                    formatDetails: "128Kbps MP3 • Direct SSL",
                    isChilltraxOfficial: true
                )
            )
        }

        return streams
    }

    // MARK: - Stream / Playlist URL Resolution

    /// Resolves `.pls` playlists, `.m3u` playlists, and Shoutcast base URLs into a playable audio stream URL for `AVPlayer`.
    public func resolvePlayableStreamURL(for originalURL: URL) async -> URL {
        let urlString = originalURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = urlString.lowercased()

        // Direct chilltrax.com/listen (without ?mode=redirect) serves a PLS playlist
        if lower == "https://www.chilltrax.com/listen" || lower == "https://www.chilltrax.com/listen/" || lower.hasSuffix(".pls") {
            if let resolved = await resolvePLSPlaylist(from: originalURL) {
                return resolved
            }
            if lower.contains("chilltrax.com/listen") {
                return URL(string: "https://streamssleu.chilltrax.com/stream?sid=1") ?? originalURL
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
