import Foundation

/// 轻量 HTTP 客户端
/// - 自定义请求头（User-Agent / Referer / Cookie 等）
/// - 短链重定向追踪（抖音等分享短链展开）
/// - 文本解码支持 GB18030 等非 UTF-8 站点
final class HTTPClient: @unchecked Sendable {
    static let shared = HTTPClient()

    /// 重定向追踪：记录每个 task 的最终 URL
    private final class RedirectTrackingDelegate: NSObject, URLSessionTaskDelegate {
        static let shared = RedirectTrackingDelegate()

        private let lock = NSLock()
        private var finalURLs: [Int: URL] = [:]

        func finalURL(for taskID: Int) -> URL? {
            lock.lock(); defer { lock.unlock() }
            return finalURLs[taskID]
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            lock.lock()
            finalURLs[task.taskIdentifier] = request.url
            lock.unlock()
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            if finalURLs[task.taskIdentifier] == nil {
                finalURLs[task.taskIdentifier] = task.originalRequest?.url
            }
            lock.unlock()
        }
    }

    private let session: URLSession
    private let redirectDelegate = RedirectTrackingDelegate.shared

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }

    /// GET 数据
    func getData(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        apply(headers, to: &request)
        let (data, response) = try await perform(request)
        try validate(response, url: url)
        return data
    }

    /// GET 文本（播放列表/网页），支持 UTF-8 / GB18030
    func getString(from url: URL, headers: [String: String] = [:]) async throws -> String {
        let data = try await getData(from: url, headers: headers)
        if let text = String(data: data, encoding: .utf8) { return text }
        let gbk = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: gbk) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    /// 短链展开：跟随重定向返回最终 URL（优先 HEAD，失败回退 GET）
    func resolveRedirects(of url: URL, headers: [String: String] = [:]) async throws -> URL {
        var task: URLSessionDataTask?

        var head = URLRequest(url: url)
        apply(headers, to: &head)
        head.httpMethod = "HEAD"

        let headResult: (Data?, URLResponse?, Error?) = await withCheckedContinuation { cont in
            task = session.dataTask(with: head) { data, response, error in
                cont.resume(returning: (data, response, error))
            }
            task?.resume()
        }
        if let error = headResult.2 {
            // 部分服务器不支持 HEAD → 回退 GET
            var get = URLRequest(url: url)
            apply(headers, to: &get)
            _ = try await withCheckedContinuation { (cont: CheckedContinuation<Data, Error>) in
                task = session.dataTask(with: get) { data, _, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if let data {
                        cont.resume(returning: data)
                    } else {
                        cont.resume(throwing: URLError(.badServerResponse))
                    }
                }
                task?.resume()
            }
        }

        if let id = task?.taskIdentifier, let final = redirectDelegate.finalURL(for: id) {
            return final
        }
        return url
    }

    // MARK: - 内部

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data, let response {
                    cont.resume(returning: (data, response))
                } else {
                    cont.resume(throwing: URLError(.badServerResponse))
                }
            }
            task.resume()
        }
    }

    private func validate(_ response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...399).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: [
                NSURLErrorFailingURLErrorKey: url,
                "statusCode": http.statusCode,
            ])
        }
    }

    private func apply(_ headers: [String: String], to request: inout URLRequest) {
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
