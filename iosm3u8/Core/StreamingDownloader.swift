import Foundation

/// HTTP 状态错误
struct HTTPStatusError: LocalizedError {
    let statusCode: Int

    var errorDescription: String? { "HTTP \(statusCode)" }
}

/// 流式下载器（共享会话，按 taskID 分发）
/// - 数据边下边写磁盘（FileHandle 流式写入，不占内存）
/// - Range 续传：从已有字节末尾继续；服务器忽略 Range（返回 200）时自动截断重写
/// - 支持 BYTERANGE 分片（#EXT-X-BYTERANGE）
final class StreamingDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = StreamingDownloader()

    private final class Handler {
        let file: FileHandle
        let destination: URL
        var startOffset: Int64
        let requestedRange: Bool
        let byteRangeExpectedLength: Int64?
        var expectedTotal: Int64?
        var finalError: Error?
        let onResponse: @Sendable (HTTPURLResponse) -> Void
        let onProgress: @Sendable (Int64, Int64?) -> Void
        let onCompletion: @Sendable (Result<URL, Error>) -> Void

        init(
            file: FileHandle,
            destination: URL,
            startOffset: Int64,
            requestedRange: Bool,
            byteRangeExpectedLength: Int64?,
            onResponse: @escaping @Sendable (HTTPURLResponse) -> Void,
            onProgress: @escaping @Sendable (Int64, Int64?) -> Void,
            onCompletion: @escaping @Sendable (Result<URL, Error>) -> Void
        ) {
            self.file = file
            self.destination = destination
            self.startOffset = startOffset
            self.requestedRange = requestedRange
            self.byteRangeExpectedLength = byteRangeExpectedLength
            self.onResponse = onResponse
            self.onProgress = onProgress
            self.onCompletion = onCompletion
        }
    }

    private let lock = NSLock()
    private var handlers: [Int: Handler] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    /// 下载到本地文件。
    /// - 参数 resumeFrom：已有 .part 大小（>0 时发起 Range 续传）
    /// - 参数 byteRange：HLS BYTERANGE 分片（优先级高于 resumeFrom）
    /// - 返回 dataTask 供调用方取消；文件创建失败返回 nil
    @discardableResult
    func download(
        to url: URL,
        from source: URL,
        headers: [String: String] = [:],
        byteRange: ByteRange? = nil,
        resumeFrom existingSize: Int64 = 0,
        onResponse: @escaping @Sendable (HTTPURLResponse) -> Void = { _ in },
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in },
        onCompletion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) -> URLSessionDataTask? {
        var request = URLRequest(url: source)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let resume: Bool
        if let br = byteRange {
            let start = br.offset ?? 0
            let rangeStr = br.length.map { "bytes=\(start)-\(start + $0 - 1)" } ?? "bytes=\(start)-"
            request.setValue(rangeStr, forHTTPHeaderField: "Range")
            resume = false
        } else if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
            resume = true
        } else {
            resume = false
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            onCompletion(.failure(NSError(
                domain: "StreamingDownloader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法写入文件 \(url.lastPathComponent)"]
            )))
            return nil
        }
        if resume {
            try? handle.seek(toOffset: UInt64(existingSize))
        } else {
            try? handle.truncate(atOffset: 0)
            try? handle.seek(toOffset: 0)
        }

        let task = session.dataTask(with: request)
        lock.lock()
        handlers[task.taskIdentifier] = Handler(
            file: handle,
            destination: url,
            startOffset: resume ? existingSize : 0,
            requestedRange: resume,
            byteRangeExpectedLength: byteRange?.length,
            onResponse: onResponse,
            onProgress: onProgress,
            onCompletion: onCompletion
        )
        lock.unlock()
        task.resume()
        return task
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        lock.lock()
        guard let handler = handlers[dataTask.taskIdentifier] else {
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        guard (200...299).contains(http.statusCode) else {
            handler.finalError = HTTPStatusError(statusCode: http.statusCode)
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        // 请求了 Range 但服务器返回 200：截断重写
        if handler.requestedRange, http.statusCode == 200 {
            try? handler.file.truncate(atOffset: 0)
            try? handler.file.seek(toOffset: 0)
            handler.startOffset = 0
        }
        // 期望总大小（进度计算用）
        if let cl = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init) {
            handler.expectedTotal = handler.startOffset + cl
        } else if let expected = handler.byteRangeExpectedLength {
            handler.expectedTotal = expected
        }
        lock.unlock()
        handler.onResponse(http)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let handler = handlers[dataTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        try? handler.file.write(contentsOf: data)
        let received = handler.file.offsetInFile - handler.startOffset
        let expected = handler.expectedTotal
        lock.unlock()
        handler.onProgress(received, expected)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let handler = handlers.removeValue(forKey: task.taskIdentifier) else {
            lock.unlock()
            return
        }
        lock.unlock()

        try? handler.file.close()
        if let error {
            handler.onCompletion(.failure(error))
        } else if let finalError = handler.finalError {
            handler.onCompletion(.failure(finalError))
        } else {
            handler.onCompletion(.success(handler.destination))
        }
    }
}
