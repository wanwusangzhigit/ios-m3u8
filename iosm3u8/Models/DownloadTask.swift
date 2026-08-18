import Foundation
import SwiftData

// MARK: - 任务状态机

enum DownloadStatus: String, Codable, CaseIterable, Sendable {
    case idle          // 已创建，未开始
    case parsing       // 正在解析播放列表
    case ready         // 已就绪，等待下载
    case downloading   // 下载中
    case paused        // 已暂停
    case merging       // 合并/转码中
    case completed     // 已完成
    case failed        // 失败
    case canceled      // 已取消

    /// 活跃中（UI 显示动态样式）
    var isActive: Bool {
        self == .downloading || self == .merging || self == .parsing
    }

    /// 终态（不可再继续）
    var isTerminal: Bool {
        self == .completed || self == .failed || self == .canceled
    }

    var label: String {
        switch self {
        case .idle: return "待开始"
        case .parsing: return "解析中"
        case .ready: return "就绪"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .merging: return "合并中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .canceled: return "已取消"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .parsing: return "magnifyingglass"
        case .ready: return "play.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .merging: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .canceled: return "stop.circle"
        }
    }
}

// MARK: - 可持久化的解析结构

/// 分片 BYTERANGE（#EXT-X-BYTERANGE）
struct ByteRange: Codable, Hashable, Sendable {
    var length: Int64?
    var offset: Int64?
}

/// 单个 TS 分片。
/// 下载期间实时状态由引擎内存态驱动（避免对 SwiftData 的海量写入），
/// 暂停/结束/周期性地以 JSON 快照（segmentsJSON）持久化。
struct Segment: Codable, Identifiable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case pending      // 未开始
        case downloading  // 下载中
        case downloaded   // 已完成
        case failed       // 失败
        case skipped      // 被过滤跳过
    }

    var index: Int            // 顺序索引（合并顺序、磁盘文件名）
    var url: URL              // 绝对地址（已补全相对路径）
    var duration: Double
    var sequence: Int64       // HLS 序号（AES IV 派生用）
    var byteRange: ByteRange?
    var key: KeyInfo? = nil   // 该分片生效的密钥（密钥轮换时每个分片各不相同；nil = 明文）
    var state: State
    var fileName: String      // "<index>.ts"

    var id: Int { index }
}

/// AES-128 密钥信息（来自 #EXT-X-KEY）
struct KeyInfo: Codable, Hashable, Sendable {
    var method: String        // "AES-128" / "NONE"
    var uri: URL?
    var ivHex: String?        // 十六进制 IV；缺省时按分片序号派生
}

/// 主列表变体（多码率）
struct Variant: Codable, Identifiable, Hashable, Sendable {
    var url: URL
    var bandwidth: Int64?
    var resolution: String?
    var codecs: String?
    var frameRate: Double?
    var name: String?

    var id: String { url.absoluteString }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let resolution, !resolution.isEmpty { return resolution }
        if let bandwidth { return "\(Int(Double(bandwidth) / 1000))kbps" }
        return url.lastPathComponent
    }
}

// MARK: - 下载任务模型

@Model
final class DownloadTask {
    @Attribute(.unique) var id: UUID

    var urlString: String          // m3u8 地址
    var title: String
    var statusRaw: String
    var progress: Double           // 0...1
    var totalSegments: Int
    var downloadedSegments: Int
    var failedSegments: Int
    var totalBytes: Int64
    var downloadedBytes: Int64
    var speedBPS: Double
    var savePath: String           // Documents 下相对目录
    var outputFileName: String     // 输出文件名（不含扩展名）
    var isOutputMP4: Bool
    var threadCount: Int
    var headersJSON: String        // 附加请求头 JSON 字典
    var segmentFilter: String?     // 分片 URI 过滤正则
    var convertToMP4: Bool
    var variantIndex: Int          // 选中的多码率变体下标（-1 = 直接媒体列表）
    var variantsJSON: String?      // 主列表变体快照
    var segmentsJSON: String?      // 分片快照（暂停/结束/周期落盘）
    var keyJSON: String?           // AES 密钥信息
    var mergedSegments: Int        // 已合并进输出文件的分片数（边下边播/续传）
    var createdAt: Date
    var updatedAt: Date
    var errorMessage: String?
    var logJSON: String            // 最近日志（JSON 数组，上限 200 条）

    init(
        id: UUID = UUID(),
        urlString: String,
        title: String = "",
        threadCount: Int = 4,
        headers: [String: String] = [:],
        segmentFilter: String? = nil,
        convertToMP4: Bool = false,
        savePath: String = "Downloads"
    ) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.statusRaw = DownloadStatus.idle.rawValue
        self.progress = 0
        self.totalSegments = 0
        self.downloadedSegments = 0
        self.failedSegments = 0
        self.totalBytes = 0
        self.downloadedBytes = 0
        self.speedBPS = 0
        self.savePath = savePath
        self.outputFileName = ""
        self.isOutputMP4 = false
        self.threadCount = threadCount
        self.headersJSON = Self.encodeHeaders(headers)
        self.segmentFilter = segmentFilter
        self.convertToMP4 = convertToMP4
        self.variantIndex = -1
        self.variantsJSON = nil
        self.segmentsJSON = nil
        self.keyJSON = nil
        self.mergedSegments = 0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.errorMessage = nil
        self.logJSON = "[]"
    }

    // MARK: - 便捷访问

    var status: DownloadStatus {
        get { DownloadStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    var headers: [String: String] {
        get { Self.decodeHeaders(headersJSON) }
        set { headersJSON = Self.encodeHeaders(newValue) }
    }

    var segments: [Segment] {
        get {
            guard let data = segmentsJSON?.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Segment].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                segmentsJSON = String(data: data, encoding: .utf8)
            } else {
                segmentsJSON = nil
            }
        }
    }

    var variants: [Variant] {
        get {
            guard let data = variantsJSON?.data(using: .utf8),
                  let list = try? JSONDecoder().decode([Variant].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                variantsJSON = String(data: data, encoding: .utf8)
            } else {
                variantsJSON = nil
            }
        }
    }

    var key: KeyInfo? {
        get {
            guard let data = keyJSON?.data(using: .utf8),
                  let info = try? JSONDecoder().decode(KeyInfo.self, from: data) else { return nil }
            return info
        }
        set {
            if let info = newValue, let data = try? JSONEncoder().encode(info) {
                keyJSON = String(data: data, encoding: .utf8)
            } else {
                keyJSON = nil
            }
        }
    }

    var logEntries: [String] {
        get {
            guard let data = logJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return list
        }
        set {
            let capped = Array(newValue.suffix(200))
            if let data = try? JSONEncoder().encode(capped) {
                logJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    func appendLog(_ message: String) {
        var entries = logEntries
        entries.append("[\(Self.timeFormatter.string(from: Date()))] \(message)")
        logEntries = entries
    }

    /// 任务工作目录：Documents/<savePath>/<taskID>/
    var taskDirectory: URL? {
        guard let base = FileManager.default.documentsDirectory else { return nil }
        return base
            .appendingPathComponent(savePath, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// 输出文件的绝对 URL：Documents/<savePath>/<outputFileName>.<ext>
    var outputFileURL: URL? {
        guard let base = FileManager.default.documentsDirectory else { return nil }
        let dir = base.appendingPathComponent(savePath, isDirectory: true)
        let ext = isOutputMP4 ? "mp4" : "ts"
        let name = outputFileName.isEmpty ? "\(title).\(ext)" : "\(outputFileName).\(ext)"
        return dir.appendingPathComponent(name)
    }

    /// 合并中间文件（边下边播/转码输入）：Documents/<savePath>/<taskID>/merged.ts
    var mergedFileURL: URL? {
        taskDirectory?.appendingPathComponent("merged.ts")
    }

    // MARK: - 序列化辅助

    private static func encodeHeaders(_ headers: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(headers) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodeHeaders(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
