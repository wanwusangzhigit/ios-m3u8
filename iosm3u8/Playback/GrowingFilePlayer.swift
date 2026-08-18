import Foundation

/// 边下边播助手：为任务的合并输出创建播放器模型
enum GrowingFilePlayer {

    /// 输出文件仍在增量合并（merged.ts 增长中）→ 使用 growingFile 模式
    /// 已完成/静态文件 → 使用 file 模式
    static func makeModel(for task: DownloadTask) -> PlayerModel {
        let model = PlayerModel()
        if let merged = task.mergedFileURL,
           FileManager.default.fileExists(atPath: merged.path),
           task.mergedSegments > 0,
           task.status.isActive {
            model.load(source: .growingFile(merged))
        } else if let out = task.outputFileURL,
                  FileManager.default.fileExists(atPath: out.path) {
            model.load(source: .file(out))
        }
        return model
    }
}
