import Foundation

/// 媒体播放列表解析结果
struct MediaPlaylist {
    var segments: [Segment]
    var key: KeyInfo?
    var targetDuration: Double
    var totalDuration: Double
    var isEndList: Bool
    var mediaSequence: Int64
    var version: Int?
}

enum M3U8ParseError: LocalizedError {
    case notPlaylist
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .notPlaylist:
            return "不是有效的 M3U8 播放列表"
        case .invalidURL(let s):
            return "无效的 URL：\(s)"
        }
    }
}

/// M3U8 播放列表解析器
/// - 支持 master（多码率）与 media（分片）两种列表
/// - 相对 URL 按列表地址补全
/// - 支持 #EXT-X-KEY (AES-128)、#EXT-X-BYTERANGE、#EXT-X-MEDIA-SEQUENCE、
///   #EXT-X-DISCONTINUITY、#EXTINF、#EXT-X-ENDLIST、#EXT-X-STREAM-INF
enum M3U8Parser {

    /// 解析主列表，返回多码率变体列表；非主列表返回空数组
    static func parseMaster(_ text: String, baseURL: URL) throws -> [Variant] {
        let lines = cleanedLines(text)
        guard lines.first?.hasPrefix("#EXTM3U") == true else {
            throw M3U8ParseError.notPlaylist
        }
        var variants: [Variant] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attrs = parseAttributes(line)
                // 下一行是变体 URI（跳过中间注释行）
                var next = index + 1
                while next < lines.count, lines[next].hasPrefix("#") {
                    next += 1
                }
                if next < lines.count, !lines[next].isEmpty {
                    guard let url = resolveURL(lines[next], relativeTo: baseURL) else {
                        throw M3U8ParseError.invalidURL(lines[next])
                    }
                    variants.append(Variant(
                        url: url,
                        bandwidth: attrs.int("BANDWIDTH"),
                        resolution: attrs.string("RESOLUTION"),
                        codecs: attrs.string("CODECS"),
                        frameRate: attrs.double("FRAME-RATE"),
                        name: attrs.string("NAME")
                    ))
                }
                index = next + 1
            } else {
                index += 1
            }
        }
        return variants
    }

    /// 解析媒体播放列表，返回分片列表
    static func parseMedia(_ text: String, baseURL: URL) throws -> MediaPlaylist {
        let lines = cleanedLines(text)
        guard lines.first?.hasPrefix("#EXTM3U") == true else {
            throw M3U8ParseError.notPlaylist
        }

        var segments: [Segment] = []
        var currentKey: KeyInfo?
        var sequence: Int64 = 0
        var targetDuration: Double = 0
        var isEndList = false
        var version: Int?
        var pendingDuration: Double = 0
        var pendingByteRange: ByteRange?

        for line in lines {
            if line.hasPrefix("#EXT-X-VERSION:") {
                version = Int(line.dropFirst("#EXT-X-VERSION:".count).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                sequence = Int64(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let attrs = parseAttributes(line)
                let method = attrs.string("METHOD") ?? "NONE"
                let uriRaw = attrs.string("URI")
                let ivHex = attrs.string("IV")
                currentKey = KeyInfo(
                    method: method,
                    uri: uriRaw.flatMap { resolveURL($0, relativeTo: baseURL) },
                    ivHex: ivHex
                )
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingByteRange = parseByteRange(
                    line.dropFirst("#EXT-X-BYTERANGE:".count).trimmingCharacters(in: .whitespaces)
                )
            } else if line.hasPrefix("#EXTINF:") {
                let body = line.dropFirst("#EXTINF:".count)
                let parts = body.split(separator: ",", maxSplits: 1)
                let durText = parts.first.map(String.init) ?? ""
                // 兼容 "9.009" 与 "9.009:live" 两种写法
                let durValue = durText.split(separator: ":").first.map(String.init) ?? ""
                pendingDuration = Double(durValue) ?? 0
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                isEndList = true
            } else if line.hasPrefix("#") {
                // 其余标签（DISCONTINUITY 等）不影响分片顺序，忽略
                continue
            } else if !line.isEmpty {
                // 分片 URI
                guard let url = resolveURL(line, relativeTo: baseURL) else {
                    throw M3U8ParseError.invalidURL(line)
                }
                segments.append(Segment(
                    index: segments.count,
                    url: url,
                    duration: pendingDuration,
                    sequence: sequence + Int64(segments.count),
                    byteRange: pendingByteRange,
                    key: currentKey,          // 该分片生效的密钥（支持轮换；nil = 明文）
                    state: .pending,
                    fileName: "\(segments.count).ts"
                ))
                pendingDuration = 0
                pendingByteRange = nil
            }
        }

        let total = segments.reduce(0.0) { $0 + $1.duration }
        return MediaPlaylist(
            segments: segments,
            key: currentKey,
            targetDuration: targetDuration,
            totalDuration: total,
            isEndList: isEndList,
            mediaSequence: sequence,
            version: version
        )
    }

    /// 多码率：拉取并解析选中变体的媒体列表
    static func fetchVariantPlaylist(
        variant: Variant,
        headers: [String: String]
    ) async throws -> MediaPlaylist {
        let text = try await HTTPClient.shared.getString(from: variant.url, headers: headers)
        return try parseMedia(text, baseURL: variant.url)
    }

    /// 分片过滤：正则命中 URL 的分片保留
    static func applyFilter(_ segments: [Segment], filter: String?) -> [Segment] {
        guard let filter, !filter.isEmpty,
              let regex = try? NSRegularExpression(pattern: filter) else {
            return segments
        }
        return segments.filter { seg in
            let urlString = seg.url.absoluteString
            let range = NSRange(urlString.startIndex..., in: urlString)
            return regex.firstMatch(in: urlString, range: range) != nil
        }
    }

    // MARK: - 工具

    /// 清洗：去 BOM、逐行去空白
    static func cleanedLines(_ text: String) -> [String] {
        let t = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        return t
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 相对 URL 补全：已是绝对地址直接返回，否则相对 base 解析
    static func resolveURL(_ raw: String, relativeTo base: URL) -> URL? {
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }

    /// 解析 "KEY=VALUE,KEY2=VALUE2" 属性串（支持引号包裹、含逗号的值）
    static func parseAttributes(_ line: String) -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        let body = String(line[line.index(after: colon)...])

        var result: [String: String] = [:]
        var currentKey = ""
        var currentValue = ""
        var inQuotes = false

        func commit() {
            let key = currentKey.trimmingCharacters(in: .whitespaces)
            let value = currentValue.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                result[key] = value
            }
            currentKey = ""
            currentValue = ""
        }

        for ch in body {
            switch ch {
            case "\"":
                inQuotes.toggle()
            case ",":
                if inQuotes {
                    currentValue.append(ch)
                } else {
                    commit()
                }
            case "=":
                if inQuotes {
                    currentValue.append(ch)
                } else {
                    currentKey = currentValue.trimmingCharacters(in: .whitespaces)
                    currentValue = ""
                }
            default:
                currentValue.append(ch)
            }
        }
        commit()
        return result
    }

    /// 解析 BYTERANGE："length[@offset]"
    static func parseByteRange(_ text: String) -> ByteRange {
        let parts = text.split(separator: "@")
        let length = parts.first.flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
        let offset = parts.count > 1 ? Int64(parts[1].trimmingCharacters(in: .whitespaces)) : nil
        return ByteRange(length: length, offset: offset)
    }
}

// MARK: - 属性串取值辅助

private extension Dictionary where Key == String, Value == String {
    func string(_ key: String) -> String? {
        self[key]?.isEmpty == false ? self[key] : nil
    }

    func int(_ key: String) -> Int64? {
        string(key).flatMap { Int64($0) }
    }

    func double(_ key: String) -> Double? {
        string(key).flatMap { Double($0) }
    }
}
