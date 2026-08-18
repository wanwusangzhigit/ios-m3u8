import Foundation

/// 微博视频解析
/// - 支持 tv 页（weibo.com/tv/show/1034:xxx）、m.weibo.cn 状态页、video.weibo.com
/// - 页面 HTML 提取 m3u8；兜底按 fid 调 media/play 接口取流
enum WeiboParser: ShareLinkParser {

    static func canParse(_ input: String) -> Bool {
        input.contains("weibo.com") || input.contains("weibo.cn") || input.contains("微博")
    }

    static func parse(_ input: String, headers: [String: String] = [:]) async throws -> [ParsedMedia] {
        let urls = LinkParserSupport.extractURLs(from: input)
        guard let first = urls.first(where: { $0.host?.contains("weibo") == true }) ?? urls.first else {
            throw LinkParserError.noURL
        }

        var html = try await HTTPClient.shared.getString(from: first, headers: headers)
        let title = LinkParserSupport.title(from: html, fallback: "微博视频")

        var media: [ParsedMedia] = LinkParserSupport.extractM3U8URLs(from: html, baseURL: first)
            .map { ParsedMedia(title: title, url: $0, kind: .m3u8, source: "微博") }

        // fid 兜底：media/play 接口返回含 m3u8 的 JSON
        if media.isEmpty, let fid = fid(from: html) ?? fid(from: first.absoluteString) {
            let api = URL(string: "https://video.weibo.com/media/play?fid=\(fid)")!
            let json = try await HTTPClient.shared.getString(from: api, headers: headers)
            let streams = LinkParserSupport.extractM3U8URLs(from: json, baseURL: api)
            media = streams.map { ParsedMedia(title: title, url: $0, kind: .m3u8, source: "微博") }
        }

        guard !media.isEmpty else { throw LinkParserError.noMedia }
        return media
    }

    /// 提取 1034:xxxx fid（页面或链接中）
    private static func fid(from text: String) -> String? {
        let pattern = #"1034:(\d{4,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }
}
