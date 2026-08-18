import Foundation

extension FileManager {
    /// 沙盒 Documents 目录
    var documentsDirectory: URL? {
        urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// 创建目录（含中间目录）；已存在或创建成功返回 true
    @discardableResult
    func ensureDirectory(at url: URL) -> Bool {
        guard !fileExists(atPath: url.path) else { return true }
        do {
            try createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// 文件字节数；不存在返回 nil
    func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? attributesOfItem(atPath: url.path) else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }
}
