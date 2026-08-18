import Foundation

/// 增量合并器：按顺序把已完成分片追加到输出文件
/// - 支持"边下边播"：分片按序完成后即时追加
/// - 支持续传：从 nextIndex 继续追加（配合 task.mergedSegments 持久化）
struct IncrementalMerger {
    let outputURL: URL
    private(set) var nextIndex: Int

    private let chunkSize = 1 << 20   // 1MB 分块读写，内存流式

    init(outputURL: URL, nextIndex: Int = 0) {
        self.outputURL = outputURL
        self.nextIndex = nextIndex
    }

    /// 追加 index 分片；仅当 index == nextIndex 且文件存在时执行，否则返回 false
    @discardableResult
    mutating func append(segmentFile url: URL, index: Int) -> Bool {
        guard index == nextIndex, FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        guard let input = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? input.close() }
        guard let output = try? FileHandle(forWritingTo: outputURL) else { return false }
        defer { try? output.close() }

        try? output.seekToEnd()
        while true {
            let data = input.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            try? output.write(contentsOf: data)
        }
        nextIndex += 1
        return true
    }
}
