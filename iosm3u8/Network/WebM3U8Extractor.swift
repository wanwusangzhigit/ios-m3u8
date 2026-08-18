import Foundation

/// 通用网页 m3u8 自动提取：抓取任意网页，找出其中全部 m3u8 地址
enum WebM3U8Extractor {

    static func extract(from url: URL, headers: [String: String] = [:]) async throws -> [ParsedMedia] {
        let html = try await HTTPClient.shared.getString(from: url, headers: headers)
        let title = LinkParserSupport.title(from: html, fallback: url.lastPathComponent.isEmpty ? "网页视频" : url.lastPathComponent)
        let urls = LinkParserSupport.extractM3U8URLs(from: html, baseURL: url)
        guard !urls.isEmpty else { throw LinkParserError.noMedia }
        return urls.map { ParsedMedia(title: title, url: $0, kind: .m3u8, source: "网页") }
    }
}
