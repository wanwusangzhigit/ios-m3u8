import Foundation
import Observation

/// 单个任务的下载引擎：解析 → 并发下载分片（AES 解密/断点续传/重试） → 增量合并
/// UI 直接观察其状态属性；SwiftData 持久化经 task 模型进行
@MainActor
@Observable
final class TaskEngine {

    enum EngineError: LocalizedError {
        case parseFailed(String)
        case noSegments
        case allSegmentsFailed

        var errorDescription: String? {
            switch self {
            case .parseFailed(let msg): return "解析失败：\(msg)"
            case .noSegments: return "播放列表中没有分片（可能被过滤规则全部过滤）"
            case .allSegmentsFailed: return "所有分片下载失败"
            }
        }
    }

    // MARK: - 状态（UI 观察）

    private(set) var status: DownloadStatus = .idle
    private(set) var progress: Double = 0
    private(set) var downloadedSegments = 0
    private(set) var failedSegments = 0
    private(set) var totalSegments = 0
    private(set) var downloadedBytes: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var speedBPS: Double = 0
    private(set) var errorMessage: String?
    private(set) var segments: [Segment] = []

    /// 全部片段下载合并完成后的回调（DownloadManager 用于转码与终态收尾）
    var onFinished: ((TaskEngine) -> Void)?

    // MARK: - 内部

    let task: DownloadTask
    private let config: AppConfig
    private let limiter: AsyncSemaphore
    private var merger: IncrementalMerger?

    private var keyDataCache: [String: Data] = [:]   // key URI → 密钥数据
    private var downloadWork: Task<Void, Never>?
    private var inFlightTasks: [URLSessionDataTask] = []
    private var isPaused = false
    private var isCanceled = false
    private var speedWindow: [(Date, Int64)] = []
    private var taskDir: URL

    init(task: DownloadTask, config: AppConfig) {
        self.task = task
        self.config = config
        self.limiter = AsyncSemaphore(count: max(1, task.threadCount))
        self.taskDir = task.taskDirectory ?? FileManager.default.temporaryDirectory
    }

    // MARK: - 生命周期

    /// 解析播放列表，进入 ready
    func prepare() async {
        guard status == .idle else { return }
        status = .parsing
        task.status = .parsing
        task.appendLog("开始解析：\(task.urlString)")
        persist()

        do {
            let (segments, key) = try await fetchPlaylist()
            guard !segments.isEmpty else { throw EngineError.noSegments }
            self.segments = segments
            self.totalSegments = segments.count
            task.segments = segments
            task.key = key
            task.totalSegments = segments.count
            task.outputFileName = Self.sanitizeFileName(
                task.title.isEmpty ? Self.deriveTitle(from: task.urlString) : task.title
            )
            status = .ready
            task.status = .ready
            task.appendLog("解析完成：共 \(segments.count) 个分片")
            persist()
        } catch {
            fail(with: error)
        }
    }

    /// 开始/继续下载
    func start() {
        guard status == .ready || status == .paused else { return }
        isPaused = false
        status = .downloading
        task.status = .downloading
        task.appendLog("开始下载（并发 \(task.threadCount)）")
        persist()

        FileManager.default.ensureDirectory(at: taskDir)
        reconcileDiskState()
        startMergerIfNeeded()
        mergeRemaining()   // 补合并重启前已下载的分片

        let remaining = segments.indices.filter {
            segments[$0].state != .downloaded && segments[$0].state != .skipped
        }
        downloadWork = Task { [weak self] in
            await self?.processSegments(remaining)
        }
    }

    /// 暂停：停止调度新分片，允许在途分片自然完成
    func pause() {
        guard status == .downloading else { return }
        isPaused = true
        downloadWork?.cancel()
        status = .paused
        task.status = .paused
        task.appendLog("已暂停（已下载 \(downloadedSegments)/\(totalSegments)）")
        persist()
    }

    /// 取消：终止全部在途请求并清理
    func cancel() {
        isCanceled = true
        isPaused = false
        downloadWork?.cancel()
        for t in inFlightTasks { t.cancel() }
        inFlightTasks.removeAll()
        status = .canceled
        task.status = .canceled
        task.appendLog("已取消")
        persist()
    }

    /// 删除任务产生的全部文件（分片目录 + 输出文件）
    func deleteFiles() {
        let fm = FileManager.default
        if let dir = task.taskDirectory { try? fm.removeItem(at: dir) }
        if let out = task.outputFileURL { try? fm.removeItem(at: out) }
    }

    /// 重试前重置：失败分片恢复为待下载，清除错误信息
    func resetForRetry() {
        guard status.isTerminal || status == .paused || status == .ready else { return }
        isCanceled = false
        isPaused = false
        for i in segments.indices where segments[i].state == .failed {
            segments[i].state = .pending
        }
        failedSegments = 0
        task.failedSegments = 0
        task.errorMessage = nil
        status = .ready
        task.status = .ready
        persist()
    }

    /// 合并/转码阶段进度（整体进度映射到 0.9~1.0 区间）
    func reportFinalProgress(_ p: Double) {
        progress = min(1, 0.9 + 0.1 * max(0, p))
        task.progress = progress
    }

    // MARK: - 下载流程

    /// 启动/续传前校准磁盘与内存状态：
    /// - 重启后内存 segments 为空时，从 task.segments 快照恢复
    /// - 磁盘上已存在的完整分片标记为 downloaded 并累计字节
    /// - 下载中/失败状态在无对应文件时回退为 pending（允许重新调度）
    private func reconcileDiskState() {
        let fm = FileManager.default
        // 重启恢复：从持久化快照加载分片列表
        if segments.isEmpty, !task.segments.isEmpty {
            segments = task.segments
            totalSegments = segments.count
        }
        guard !segments.isEmpty else { return }

        var downloaded = 0
        var bytes: Int64 = 0
        for i in segments.indices {
            let fileURL = taskDir.appendingPathComponent(segments[i].fileName)
            if let size = fm.fileSize(at: fileURL), size > 0 {
                // 完整分片：直接计入已完成
                if segments[i].state != .downloaded {
                    segments[i].state = .downloaded
                }
                downloaded += 1
                bytes += size
            } else if segments[i].state == .downloaded || segments[i].state == .downloading {
                // 状态与磁盘不符：分片未完成，重置为待下载
                // （.part 保留，由 StreamingDownloader 的 Range 续传接续）
                segments[i].state = .pending
            }
        }
        downloadedSegments = downloaded
        downloadedBytes = bytes
        totalBytes = max(totalBytes, bytes)
        failedSegments = segments.filter { $0.state == .failed }.count
        updateProgress()
        persist()   // 将恢复后的分片状态落盘，避免重启丢失
    }

    private func processSegments(_ indices: [Int]) async {
        // 先捕获信号量：TaskGroup 闭包为非隔离上下文，避免直接访问 MainActor 存储属性
        let limiter = self.limiter
        await withTaskGroup(of: Void.self) { group in
            for index in indices {
                if isPaused || isCanceled { break }
                await limiter.wait()
                if isPaused || isCanceled {
                    await limiter.signal()
                    break
                }
                group.addTask { [weak self] in
                    await self?.downloadSegment(at: index)
                    await limiter.signal()
                }
            }
            await group.waitForAll()
        }

        if isCanceled {
            return
        } else if isPaused {
            return
        } else {
            finishAfterAllSegments()
        }
    }

    private func downloadSegment(at index: Int) async {
        guard index < segments.count, !isPaused, !isCanceled else { return }
        segments[index].state = .downloading
        let segment = segments[index]
        let segmentURL = taskDir.appendingPathComponent(segment.fileName)
        let partURL = taskDir.appendingPathComponent(segment.fileName + ".part")
        let fm = FileManager.default

        // 断点续传：磁盘已有完整分片 → 直接计为已完成
        if let size = fm.fileSize(at: segmentURL), size > 0 {
            markSegmentDownloaded(index)
            return
        }

        var attempts = 0
        let maxAttempts = max(1, config.retryCount + 1)
        while attempts < maxAttempts, !isPaused, !isCanceled {
            attempts += 1
            do {
                let existingSize = fm.fileSize(at: partURL) ?? 0
                try await downloadOne(segment: segment, partURL: partURL, existingSize: existingSize)

                // AES-128 解密（优先分片自身密钥，兼容密钥轮换；旧快照回退 task.key）
                let segKey = segment.key ?? task.key
                if let key = segKey, key.method == "AES-128" {
                    let keyData = try await fetchKey(key)
                    let iv = deriveIV(for: key, sequence: segment.sequence)
                    try AESDecrypter.decryptFile(at: partURL, key: keyData, iv: iv)
                } else if let key = segKey, key.method != "NONE" {
                    task.appendLog("提示：不支持的加密方式 \(key.method)，按明文处理")
                }

                // 校验非空后转正（.part → .ts）
                guard let size = fm.fileSize(at: partURL), size > 0 else {
                    throw NSError(domain: "TaskEngine", code: -3,
                                  userInfo: [NSLocalizedDescriptionKey: "分片内容为空"])
                }
                try fm.moveItem(at: partURL, to: segmentURL)
                markSegmentDownloaded(index)
                return
            } catch {
                if isPaused || isCanceled { return }
                try? fm.removeItem(at: partURL)
                if attempts < maxAttempts {
                    let delay = config.retryDelaySeconds * pow(2, Double(attempts - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        guard !isPaused, !isCanceled else { return }
        segments[index].state = .failed
        failedSegments += 1
        task.appendLog("分片 \(index) 下载失败（重试 \(maxAttempts) 次）")
        updateProgress()
        persist()
    }

    private func downloadOne(segment: Segment, partURL: URL, existingSize: Int64) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let dataTask = StreamingDownloader.shared.download(
                to: partURL,
                from: segment.url,
                headers: effectiveHeaders,
                byteRange: segment.byteRange,
                resumeFrom: existingSize,
                onCompletion: { result in
                    Task { @MainActor [weak self] in
                        self?.inFlightTasks.removeAll { $0 === dataTask }
                    }
                    switch result {
                    case .success: cont.resume()
                    case .failure(let error): cont.resume(throwing: error)
                    }
                }
            )
            if let dataTask {
                inFlightTasks.append(dataTask)
            }
        }
    }

    // MARK: - 收尾

    private func finishAfterAllSegments() {
        if downloadedSegments == 0 && failedSegments > 0 {
            fail(with: EngineError.allSegmentsFailed)
            return
        }
        // 补合并乱序完成的分片
        if (merger?.nextIndex ?? 0) < totalSegments {
            status = .merging
            task.status = .merging
            persist()
            mergeRemaining()
        }
        task.appendLog("分片下载完成（成功 \(downloadedSegments)，失败 \(failedSegments)）")
        persist()
        onFinished?(self)
    }

    private func fail(with error: Error) {
        errorMessage = error.localizedDescription
        status = .failed
        task.status = .failed
        task.errorMessage = error.localizedDescription
        task.appendLog("失败：\(error.localizedDescription)")
        persist()
    }

    /// 校验/重建合并文件（重启续传场景）
    private func rebuildMergedFileIfNeeded() {
        guard let mergedURL = task.mergedFileURL else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: mergedURL.path) else { return }
        let merged = task.mergedSegments
        var needRebuild = merged <= 0
        if !needRebuild {
            for i in 0..<min(merged, segments.count) {
                let f = taskDir.appendingPathComponent(segments[i].fileName)
                if fm.fileSize(at: f) == nil {
                    needRebuild = true
                    break
                }
            }
        }
        if needRebuild {
            try? fm.removeItem(at: mergedURL)
            task.mergedSegments = 0
        }
    }

    private func startMergerIfNeeded() {
        guard let mergedURL = task.mergedFileURL else { return }
        FileManager.default.ensureDirectory(at: taskDir)
        rebuildMergedFileIfNeeded()
        if !FileManager.default.fileExists(atPath: mergedURL.path) {
            FileManager.default.createFile(atPath: mergedURL.path, contents: nil)
        }
        merger = IncrementalMerger(outputURL: mergedURL, nextIndex: task.mergedSegments)
    }

    private func mergeRemaining() {
        guard var m = merger else { return }
        for i in 0..<segments.count {
            guard i >= m.nextIndex else { continue }
            let fileURL = taskDir.appendingPathComponent(segments[i].fileName)
            if FileManager.default.fileExists(atPath: fileURL.path),
               m.append(segmentFile: fileURL, index: i) {
                task.mergedSegments = m.nextIndex
            } else {
                break   // 顺序缺口，等待后续分片
            }
        }
        merger = m
    }

    private func appendToMerger(_ index: Int) {
        guard let m = merger, index == m.nextIndex else { return }
        var updated = m
        let fileURL = taskDir.appendingPathComponent(segments[index].fileName)
        if updated.append(segmentFile: fileURL, index: index) {
            task.mergedSegments = updated.nextIndex
            merger = updated
        }
    }

    // MARK: - 统计与持久化

    private func markSegmentDownloaded(_ index: Int) {
        guard index < segments.count else { return }
        segments[index].state = .downloaded
        downloadedSegments += 1
        if let size = FileManager.default.fileSize(at: taskDir.appendingPathComponent(segments[index].fileName)) {
            downloadedBytes += size
            totalBytes += size
        }
        updateProgress()
        persistPeriodically()
        appendToMerger(index)
    }

    private func updateProgress() {
        guard totalSegments > 0 else { return }
        progress = min(1, Double(downloadedSegments) / Double(totalSegments))
        computeSpeed()
        task.progress = progress
        task.downloadedSegments = downloadedSegments
        task.failedSegments = failedSegments
        task.downloadedBytes = downloadedBytes
        task.totalBytes = totalBytes
        task.speedBPS = speedBPS
    }

    private func computeSpeed() {
        let now = Date()
        speedWindow.append((now, downloadedBytes))
        speedWindow.removeAll { now.timeIntervalSince($0.0) > 10 }
        guard let first = speedWindow.first, speedWindow.count >= 2 else { return }
        let elapsed = now.timeIntervalSince(first.0)
        guard elapsed > 0.5 else { return }
        speedBPS = Double(downloadedBytes - first.1) / elapsed
    }

    private func persistPeriodically() {
        if downloadedSegments % 10 == 0 {
            persist()
        }
    }

    private func persist() {
        task.updatedAt = Date()
        task.segments = segments
        try? task.modelContext?.save()
    }

    // MARK: - 网络辅助

    private func fetchPlaylist() async throws -> (segments: [Segment], key: KeyInfo?) {
        guard let baseURL = URL(string: task.urlString) else {
            throw EngineError.parseFailed("URL 无效")
        }
        let headers = effectiveHeaders
        let text = try await HTTPClient.shared.getString(from: baseURL, headers: headers)

        // 主列表 → 多码率
        let variants = try M3U8Parser.parseMaster(text, baseURL: baseURL)
        if !variants.isEmpty {
            task.variants = variants
            var chosen = variants[0]
            if task.variantIndex >= 0, task.variantIndex < variants.count {
                chosen = variants[task.variantIndex]
            }
            task.appendLog("检测到多码率（\(variants.count) 档），选择：\(chosen.displayName)")
            let media = try await M3U8Parser.fetchVariantPlaylist(variant: chosen, headers: headers)
            return (media.segments, media.key)
        }

        // 直接媒体列表
        let media = try M3U8Parser.parseMedia(text, baseURL: baseURL)
        return (media.segments, media.key)
    }

    private func fetchKey(_ key: KeyInfo) async throws -> Data {
        guard let uri = key.uri else {
            throw NSError(domain: "TaskEngine", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "密钥缺少 URI"])
        }
        let cacheKey = uri.absoluteString
        if let cached = keyDataCache[cacheKey] { return cached }
        let data = try await HTTPClient.shared.getData(from: uri, headers: effectiveHeaders)
        keyDataCache[cacheKey] = data
        return data
    }

    private func deriveIV(for key: KeyInfo, sequence: Int64) -> Data {
        if let hex = key.ivHex, let data = AESDecrypter.ivData(fromHex: hex) {
            return data
        }
        return AESDecrypter.defaultIV(forSequence: sequence)
    }

    private var effectiveHeaders: [String: String] {
        var h = task.headers
        if h["User-Agent"] == nil {
            h["User-Agent"] = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }
        return h
    }

    // MARK: - 工具

    static func sanitizeFileName(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "download" : cleaned
    }

    static func deriveTitle(from urlString: String) -> String {
        URL(string: urlString)?.lastPathComponent ?? "download"
    }
}
