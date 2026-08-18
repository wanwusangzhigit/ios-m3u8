import Foundation
import SwiftData

/// 应用配置（单例行：id == "default"）
@Model
final class AppConfig {
    @Attribute(.unique) var id: String

    var threadCount: Int            // 每任务并发分片数
    var maxConcurrentTasks: Int     // 同时下载的任务数
    var retryCount: Int             // 分片失败重试次数
    var retryDelaySeconds: Double   // 重试退避基数（指数退避）
    var saveDirectory: String       // Documents 下相对路径
    var defaultHeadersJSON: String  // 新建任务的默认请求头
    var segmentFilter: String?      // 默认分片过滤正则
    var convertToMP4: Bool          // 默认是否转 MP4
    var autoResumeOnLaunch: Bool    // 启动时自动续传未完成任务
    var requirePassword: Bool       // 是否启用启动密码
    var useBiometric: Bool          // 是否启用 Face ID / Touch ID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "default",
        threadCount: Int = 4,
        maxConcurrentTasks: Int = 2,
        retryCount: Int = 3,
        retryDelaySeconds: Double = 2.0,
        saveDirectory: String = "Downloads",
        defaultHeaders: [String: String] = [:],
        segmentFilter: String? = nil,
        convertToMP4: Bool = false,
        autoResumeOnLaunch: Bool = true
    ) {
        self.id = id
        self.threadCount = threadCount
        self.maxConcurrentTasks = maxConcurrentTasks
        self.retryCount = retryCount
        self.retryDelaySeconds = retryDelaySeconds
        self.saveDirectory = saveDirectory
        self.defaultHeadersJSON = Self.encodeHeaders(defaultHeaders)
        self.segmentFilter = segmentFilter
        self.convertToMP4 = convertToMP4
        self.autoResumeOnLaunch = autoResumeOnLaunch
        self.requirePassword = false
        self.useBiometric = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var defaultHeaders: [String: String] {
        get {
            guard let data = defaultHeadersJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaultHeadersJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    private static func encodeHeaders(_ headers: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(headers) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 配置存取助手：确保单例配置行存在并返回
enum AppConfigStore {
    static func fetchOrCreate(in context: ModelContext) -> AppConfig {
        let descriptor = FetchDescriptor<AppConfig>(
            predicate: #Predicate { $0.id == "default" }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let config = AppConfig()
        context.insert(config)
        try? context.save()
        return config
    }
}
