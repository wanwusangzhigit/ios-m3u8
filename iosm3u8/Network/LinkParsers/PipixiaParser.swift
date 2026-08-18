import Foundation

/// 皮皮虾链接解析
/// - 短链 www.pipix.com/s/xxx 展开 → 页面 HTML 提取 m3u8 / mp4
enum PipixiaParser: ShareLinkParser {

    static func canParse(_ input: String) -> Bool {
        input.contains("pipix.com") || input.contains("皮皮虾")
    }

    static func parse(_ input: String, headers: [String: String] = [:]) async throws -> [ParsedMedia] {
        let urls = LinkParserSupport.extractURLs(from: input)
        guard let first = urls.first(where: { $0.host?.contains("pipix") == true }) ?? urls.first else {
            throw LinkParserError.noURL
        }

        var pageURL = first
        if pageURL.host?.hasPrefix("www.pipix") == true && pageURL.path.hasPrefix("/s/") {
            pageURL = try await HTTPClient.shared.resolveRedirects(of: pageURL, headers: headers)
        }

        let html = try await HTTPClient.shared.getString(from: pageURL, headers: headers)
        let title = LinkParserSupport.title(from: html, fallback: "皮皮虾视频")

        var media: [ParsedMedia] = LinkParserSupport.extractM3U8URLs(from: html, baseURL: pageURL)
            .map { ParsedMedia(title: title, url: $0, kind: .m3u8, source: "皮皮虾") }

        if media.isEmpty {
            let unescaped = html.replacingOccurrences(of: "\\/", with: "/")
            let pattern = #"https?://[^\s"'<>\\]+?\.mp4[^\s"'<>\\]*"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(unescaped.startIndex..., in: unescaped)
                for match in regex.matches(in: unescaped, range: range) {
                    if let r = Range(match.range, in: unescaped),
                       let url = URL(string: String(unescaped[r])) {
                        media.append(ParsedMedia(title: title, url: url, kind: .mp4, source: "皮皮虾"))
                    }
                }
            }
        }

        guard !media.isEmpty else { throw LinkParserError.noMedia }
        return media
    }
}
