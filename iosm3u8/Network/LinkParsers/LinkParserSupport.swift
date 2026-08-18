import Foundation

/// 链接解析通用工具：URL 提取、HTML m3u8 提取、标题提取
enum LinkParserSupport {

    /// 从文本提取所有 http(s) URL（跳过中文标点）
    static func extractURLs(from text: String) -> [URL] {
        let pattern = #"https?://[^\s，。；、""''<>()\[\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var urls: [URL] = []
        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let raw = String(text[r]).trimmingCharacters(in: .punctuationCharacters)
            if let url = URL(string: raw) {
                urls.append(url)
            }
        }
        return urls
    }

    /// 从 HTML/JS 文本提取 m3u8 地址（处理 \/ 转义，相对地址按 baseURL 补全，去重保序）
    static func extractM3U8URLs(from text: String, baseURL: URL?) -> [URL] {
        let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
        let pattern = #"[^\s"'<>\\]+?\.m3u8[^\s"'<>\\]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(unescaped.startIndex..., in: unescaped)
        let matches = regex.matches(in: unescaped, range: range)

        var results: [URL] = []
        for match in matches {
            guard let r = Range(match.range, in: unescaped) else { continue }
            let raw = String(unescaped[r])
            var url: URL?
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                url = URL(string: raw)
            } else if let base = baseURL {
                url = URL(string: raw, relativeTo: base)?.absoluteURL
            }
            if let url, !results.contains(url) {
                results.append(url)
            }
        }
        return results
    }

    /// 提取 <title>，做基本实体解码；失败返回 fallback
    static func title(from html: String, fallback: String = "视频") -> String {
        let pattern = #"<title[^>]*>(.*?)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(
                  in: html,
                  range: NSRange(html.startIndex..., in: html)
              ),
              let r = Range(match.range(at: 1), in: html) else {
            return fallback
        }
        var t = String(html[r])
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&nbsp;": " ",
        ]
        for (k, v) in entities {
            t = t.replacingOccurrences(of: k, with: v)
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    /// 提取 JSON 字段值："key":"value"
    static func jsonString(_ key: String, from text: String) -> String? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[r])
        return value.replacingOccurrences(of: "\\/", with: "/")
    }

    /// 提取 JSON 数字字段："key":123
    static func jsonNumber(_ key: String, from text: String) -> String? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }
}
