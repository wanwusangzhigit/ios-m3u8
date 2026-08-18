import Foundation

/// 抖音链接解析
/// - 支持分享口令文本（"8.88 xyz:/ 复制打开抖音…"）与直接链接
/// - 短链 v.douyin.com 展开 → 页面 HTML 提取 m3u8/mp4
/// - 兜底：从页面 JSON 提取 video_id 构造 play 接口地址
enum DouyinParser: ShareLinkParser {

    static func canParse(_ input: String) -> Bool {
        input.contains("douyin.com") || input.contains("iesdouyin.com") || input.contains("抖音")
    }

    static func parse(_ input: String, headers: [String: String] = [:]) async throws -> [ParsedMedia] {
        let urls = LinkParserSupport.extractURLs(from: input)
        guard let first = urls.first(where: { $0.host?.contains("douyin") == true || $0.host?.contains("iesdouyin") == true })
                ?? urls.first else {
            throw LinkParserError.noURL
        }

        // 短链展开
        var pageURL = first
        if pageURL.host?.hasPrefix("v.") == true || pageURL.host?.hasPrefix("www.iesdouyin") == true {
            pageURL = try await HTTPClient.shared.resolveRedirects(of: pageURL, headers: headers)
        }

        var html = try await HTTPClient.shared.getString(from: pageURL, headers: headers)
        let title = LinkParserSupport.title(from: html, fallback: "抖音视频")

        // 页面内 m3u8
        var media: [ParsedMedia] = LinkParserSupport.extractM3U8URLs(from: html, baseURL: pageURL)
            .map { ParsedMedia(title: title, url: $0, kind: .m3u8, source: "抖音") }

        // video_id 兜底 → play 接口（mp4）
        if media.isEmpty, let videoID = videoID(from: html) {
            let play = URL(string: "https://www.douyin.com/aweme/v1/play/?video_id=\(videoID)&ratio=720p&line=0")!
            media.append(ParsedMedia(title: title, url: play, kind: .mp4, source: "抖音"))
        }

        // 页面内 mp4 地址（play_addr）
        if media.isEmpty {
            for raw in mp4URLs(from: html) {
                if let url = URL(string: raw) {
                    media.append(ParsedMedia(title: title, url: url, kind: .mp4, source: "抖音"))
                }
            }
        }

        guard !media.isEmpty else { throw LinkParserError.noMedia }
        return media
    }

    /// 从页面数据提取 video_id
    private static func videoID(from text: String) -> String? {
        if let id = LinkParserSupport.jsonString("video_id", from: text), !id.isEmpty {
            return id
        }
        let pattern = #"video_id=([a-zA-Z0-9_-]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text) {
            return String(text[r])
        }
        return nil
    }

    /// 提取页面内 mp4 直链（play_addr 等）
    private static func mp4URLs(from text: String) -> [String] {
        let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
        let pattern = #"https?://[^\s"'<>\\]+?\.mp4[^\s"'<>\\]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(unescaped.startIndex..., in: unescaped)
        return regex.matches(in: unescaped, range: range).compactMap { match in
            guard let r = Range(match.range, in: unescaped) else { return nil }
            return String(unescaped[r])
        }
    }
}
