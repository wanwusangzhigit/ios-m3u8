import SwiftUI

/// 全局暗色主题配色（参考 m3u8dl WebUI 风格）
enum Theme {
    static let background = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let surface = Color(red: 0.13, green: 0.15, blue: 0.19)
    static let surfaceElevated = Color(red: 0.17, green: 0.19, blue: 0.24)
    static let border = Color.white.opacity(0.08)
    static let accent = Color(red: 1.0, green: 0.584, blue: 0.0)   // 橙色
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let success = Color(red: 0.29, green: 0.80, blue: 0.43)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.03)
    static let danger = Color(red: 0.95, green: 0.31, blue: 0.28)

    /// 任务状态对应颜色
    static func color(for status: DownloadStatus) -> Color {
        switch status {
        case .downloading: return accent
        case .merging: return accent
        case .parsing: return accent
        case .completed: return success
        case .failed: return danger
        case .paused: return warning
        case .idle, .ready: return textSecondary
        case .canceled: return textSecondary
        }
    }
}
