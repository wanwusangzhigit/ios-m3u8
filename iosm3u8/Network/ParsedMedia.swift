import Foundation

/// 解析出的媒体资源
struct ParsedMedia: Identifiable, Hashable {
    enum Kind: String {
        case m3u8
        case mp4
    }

    let id: UUID
    var title: String
    var url: URL
    var kind: Kind
    var source: String    // 来源说明（抖音/微博/皮皮虾/网页）

    init(id: UUID = UUID(), title: String, url: URL, kind: Kind, source: String) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.source = source
    }
}

enum LinkParserError: LocalizedError {
    case noURL
    case noMedia

    var errorDescription: String? {
        switch self {
        case .noURL: return "未找到有效链接"
        case .noMedia: return "未解析到可用媒体地址"
        }
    }
}

/// 分享链接解析器协议
protocol ShareLinkParser {
    /// 是否识别该分享文本/链接
    static func canParse(_ input: String) -> Bool
    /// 解析分享文本 → 媒体列表（可能为空）
    static func parse(_ input: String, headers: [String: String]) async throws -> [ParsedMedia]
}

/// 解析器总入口：平台优先，未命中则按通用网页提取
enum LinkParserHub {
    static let parsers: [any ShareLinkParser.Type] = [
        DouyinParser.self,
        WeiboParser.self,
        PipixiaParser.self,
    ]

    static func parse(_ input: String, headers: [String: String] = [:]) async throws -> [ParsedMedia] {
        for parser in parsers where parser.canParse(input) {
            if let media = try? await parser.parse(input, headers: headers), !media.isEmpty {
                return media
            }
        }
        // 通用网页 m3u8 提取
        if let url = LinkParserSupport.extractURLs(from: input).first {
            return try await WebM3U8Extractor.extract(from: url, headers: headers)
        }
        throw LinkParserError.noURL
    }
}
