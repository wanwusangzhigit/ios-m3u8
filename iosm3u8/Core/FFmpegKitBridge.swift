import Foundation

/// MP4 转换桥接（ffmpeg-kit，可选依赖）
/// - 未链接 FFmpegKit 框架时 isAvailable == false，转换调用将抛错并降级为 TS
/// - 使用 `-c copy` 快速转封装（不重编码），`+faststart` 便于流式播放
enum FFmpegKitBridge {

    struct ConversionError: LocalizedError {
        let message: String
        var errorDescription: String? { "转码失败：\(message)" }
    }

    /// 是否已集成 ffmpeg-kit 二进制
    static var isAvailable: Bool {
        #if canImport(FFmpegKit)
        return true
        #else
        return false
        #endif
    }

    /// 转封装 TS → MP4；onProgress 回调 0...1
    static func convertToMP4(
        input: URL,
        output: URL,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        #if canImport(FFmpegKit)
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                FFmpegKitConfig.enableStatisticsCallback { statistics in
                    let time = statistics?.getTime() ?? 0
                    let duration = statistics?.getDuration() ?? 0
                    if duration > 0 {
                        onProgress(min(1, Double(time) / Double(duration)))
                    }
                }
                let command = "-y -i \"\(input.path)\" -c copy -movflags +faststart \"\(output.path)\""
                let session = FFmpegKit.execute(command)
                FFmpegKitConfig.enableStatisticsCallback(nil)

                if let rc = session?.getReturnCode(), rc.isSuccess() {
                    cont.resume(returning: output)
                } else if let rc = session?.getReturnCode(), rc.isCancel() {
                    cont.resume(throwing: ConversionError(message: "转码被取消"))
                } else {
                    let log = session?.getOutput() ?? ""
                    cont.resume(throwing: ConversionError(message: log.isEmpty ? "ffmpeg 执行失败" : String(log.prefix(500))))
                }
            }
        }
        #else
        throw ConversionError(message: "未集成 ffmpeg-kit（请按 README 添加 FFmpegKit.xcframework 后重新生成工程）")
        #endif
    }
}
