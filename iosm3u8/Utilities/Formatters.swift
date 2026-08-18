import Foundation

/// 字节/速率/时长格式化
enum Formatters {

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }

    static func speed(_ bps: Double) -> String {
        guard bps.isFinite, bps > 0 else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(bps)) + "/s"
    }

    static func percent(_ p: Double) -> String {
        String(format: "%.1f%%", p * 100)
    }
}
