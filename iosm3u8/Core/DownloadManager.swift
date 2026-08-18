import Foundation
import Observation
import SwiftData

/// 下载管理器：单例，管理所有任务的状态机与生命周期
/// - CRUD：新建/解析/开始/暂停/恢复/重试/取消/删除（含文件）
/// - 批量：全部暂停/恢复/取消/删除
/// - 并发任务数限制（AppConfig.maxConcurrentTasks），空位自动启动等待任务
/// - 启动自动续传 + 后台 BGTask 续传
@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    private(set) var engines: [UUID: TaskEngine] = [:]
    private(set) var isRestoring = false

    private var context: ModelContext?
    private var config: AppConfig?

    private init() {}

    // MARK: - 初始化

    /// 注入存储与配置（App 启动时调用一次）
    func setup(context: ModelContext, config: AppConfig) {
        self.context = context
        self.config = config
    }

    /// 从 SwiftData 加载全部任务（App 启动时调用）
    func loadTasks() {
        guard let context else { return }
        let descriptor = FetchDescriptor<DownloadTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        for task in tasks {
            guard engines[task.id] == nil else { continue }
            let engine = TaskEngine(task: task, config: config ?? AppConfig())
            engine.onFinished = { [weak self] engine in
                self?.finalize(engine)
            }
            engines[task.id] = engine
            // 崩溃/杀进程后的恢复：运行中状态归位为可续传的就绪态
            if task.status.isActive || task.status == .ready {
                task.status = .ready
            }
        }
        try? context.save()
    }

    /// 启动时自动续传就绪任务（受并发上限约束）
    func resumeReadyTasks() {
        guard config?.autoResumeOnLaunch == true else { return }
        let max = max(1, config?.maxConcurrentTasks ?? 2)
        var slots = max - activeCount
        guard slots > 0 else { return }
        let candidates = engines.values
            .filter { $0.status == .ready }
            .sorted { $0.task.createdAt < $1.task.createdAt }
        for engine in candidates {
            guard slots > 0 else { break }
            engine.start()
            slots -= 1
        }
    }

    /// 后台唤醒续传（BGTask 回调）
    func resumeUnfinishedTasksForBackground() async {
        isRestoring = true
        defer { isRestoring = false }
        resumeReadyTasks()
    }

    // MARK: - CRUD

    @discardableResult
    func createTask(
        urlString: String,
        title: String = "",
        headers: [String: String]? = nil,
        segmentFilter: String? = nil,
        threadCount: Int? = nil,
        convertToMP4: Bool? = nil,
        savePath: String? = nil,
        autoStart: Bool = false
    ) -> DownloadTask? {
        guard let context else { return nil }
        let cfg = config ?? AppConfig()
        let task = DownloadTask(
            urlString: urlString,
            title: title,
            threadCount: threadCount ?? cfg.threadCount,
            headers: headers ?? cfg.defaultHeaders,
            segmentFilter: segmentFilter ?? cfg.segmentFilter,
            convertToMP4: convertToMP4 ?? cfg.convertToMP4,
            savePath: savePath ?? cfg.saveDirectory
        )
        context.insert(task)
        let engine = TaskEngine(task: task, config: cfg)
        engine.onFinished = { [weak self] engine in
            self?.finalize(engine)
        }
        engines[task.id] = engine
        try? context.save()
        if autoStart {
            start(task.id)
        }
        return task
    }

    func start(_ id: UUID) {
        guard let engine = engines[id] else { return }
        switch engine.status {
        case .idle:
            Task { [weak self] in
                await engine.prepare()
                guard let self, engine.status == .ready else { return }
                self.beginIfSlotAvailable(engine)
            }
        case .ready, .paused:
            beginIfSlotAvailable(engine)
        default:
            break
        }
    }

    func pause(_ id: UUID) {
        engines[id]?.pause()
        startQueued()
    }

    func resume(_ id: UUID) {
        guard let engine = engines[id], engine.status == .paused else { return }
        beginIfSlotAvailable(engine)
    }

    func cancel(_ id: UUID) {
        guard let engine = engines[id] else { return }
        engine.cancel()
        startQueued()
    }

    func retry(_ id: UUID) {
        guard let engine = engines[id] else { return }
        engine.task.appendLog("手动重试")
        engine.resetForRetry()
        start(id)
    }

    func delete(_ id: UUID, includingFiles: Bool = true) {
        guard let engine = engines.removeValue(forKey: id) else { return }
        engine.cancel()
        if includingFiles { engine.deleteFiles() }
        context?.delete(engine.task)
        try? context?.save()
        startQueued()
    }

    // MARK: - 批量操作

    func pauseAll() {
        for engine in engines.values { engine.pause() }
        persistAll()
    }

    func resumeAll() {
        let max = max(1, config?.maxConcurrentTasks ?? 2)
        var slots = max
        let candidates = engines.values
            .filter { $0.status == .paused || $0.status == .ready }
            .sorted { $0.task.createdAt < $1.task.createdAt }
        for engine in candidates {
            guard slots > 0 else { break }
            engine.start()
            slots -= 1
        }
    }

    func cancelAll() {
        for engine in engines.values { engine.cancel() }
        persistAll()
    }

    func deleteAll(includingFiles: Bool = true) {
        for id in engines.keys {
            delete(id, includingFiles: includingFiles)
        }
    }

    // MARK: - 查询（UI）

    var allEngines: [TaskEngine] {
        engines.values.sorted { $0.task.createdAt > $1.task.createdAt }
    }

    var activeCount: Int {
        engines.values.filter { $0.status.isActive }.count
    }

    var downloadingCount: Int {
        engines.values.filter { $0.status == .downloading }.count
    }

    var pausedCount: Int {
        engines.values.filter { $0.status == .paused }.count
    }

    var completedCount: Int {
        engines.values.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        engines.values.filter { $0.status == .failed }.count
    }

    func engine(for id: UUID) -> TaskEngine? {
        engines[id]
    }

    // MARK: - 收尾（转码/完成）

    private func finalize(_ engine: TaskEngine) {
        let task = engine.task
        let hasOutput = FileManager.default.fileExists(atPath: task.mergedFileURL?.path ?? "")
        if task.convertToMP4, hasOutput {
            convertToMP4(engine)
        } else {
            complete(engine)
        }
    }

    private func complete(_ engine: TaskEngine) {
        let task = engine.task
        guard let merged = task.mergedFileURL,
              FileManager.default.fileExists(atPath: merged.path) else {
            task.status = .failed
            task.errorMessage = "合并产物缺失"
            task.appendLog("合并产物缺失")
            persistTask(task)
            return
        }
        guard let outURL = task.outputFileURL else {
            task.status = .failed
            task.errorMessage = "输出路径无效"
            task.appendLog("输出路径无效")
            persistTask(task)
            return
        }
        FileManager.default.ensureDirectory(at: outURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: outURL.path) {
            try? FileManager.default.removeItem(at: outURL)
        }
        do {
            try FileManager.default.moveItem(at: merged, to: outURL)
        } catch {
            task.status = .failed
            task.errorMessage = "输出失败：\(error.localizedDescription)"
            task.appendLog("输出失败：\(error.localizedDescription)")
            persistTask(task)
            return
        }
        task.status = .completed
        task.progress = 1
        task.appendLog("任务完成：\(outURL.lastPathComponent)")
        persistTask(task)
        startQueued()
    }

    private func convertToMP4(_ engine: TaskEngine) {
        let task = engine.task
        guard let merged = task.mergedFileURL,
              let outURL = task.outputFileURL else {
            complete(engine)
            return
        }
        let mp4URL = outURL.deletingPathExtension().appendingPathExtension("mp4")
        task.appendLog("开始转码 MP4…")
        persistTask(task)

        Task {
            do {
                _ = try await FFmpegKitBridge.convertToMP4(
                    input: merged,
                    output: mp4URL
                ) { progress in
                    Task { @MainActor in
                        engine.reportFinalProgress(progress)
                    }
                }
                try? FileManager.default.removeItem(at: merged)
                task.isOutputMP4 = true
                task.status = .completed
                task.progress = 1
                task.appendLog("转码完成：\(mp4URL.lastPathComponent)")
                persistTask(task)
                startQueued()
            } catch {
                task.appendLog("转码失败，保留 TS 版本：\(error.localizedDescription)")
                persistTask(task)
                complete(engine)
            }
        }
    }

    // MARK: - 内部

    private func beginIfSlotAvailable(_ engine: TaskEngine) {
        let max = max(1, config?.maxConcurrentTasks ?? 2)
        if activeCount < max {
            engine.start()
        } else {
            engine.task.appendLog("并发任务已满，等待空位…")
            persistTask(engine.task)
        }
    }

    /// 有任务结束后，自动启动等待中的就绪任务
    private func startQueued() {
        let max = max(1, config?.maxConcurrentTasks ?? 2)
        var slots = max - activeCount
        guard slots > 0 else { return }
        let candidates = engines.values
            .filter { $0.status == .ready }
            .sorted { $0.task.createdAt < $1.task.createdAt }
        for engine in candidates {
            guard slots > 0 else { break }
            engine.start()
            slots -= 1
        }
    }

    private func persistTask(_ task: DownloadTask?) {
        task?.updatedAt = Date()
        try? context?.save()
    }

    private func persistAll() {
        try? context?.save()
    }
}
