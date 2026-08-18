import SwiftUI

/// 任务卡片：状态、进度、统计、快捷操作
struct TaskCardView: View {
    let engine: TaskEngine
    var isSelected = false

    @Environment(DownloadManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: engine.status.systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.color(for: engine.status))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.task.title.isEmpty ? "未命名任务" : engine.task.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(engine.task.urlString)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }

            ProgressView(value: engine.progress)
                .tint(Theme.color(for: engine.status))

            HStack {
                Text(Formatters.percent(engine.progress))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(Formatters.speed(engine.speedBPS))
                    .font(.caption.monospacedDigit())
                Text(engine.status.label)
                    .font(.caption)
                    .foregroundStyle(Theme.color(for: engine.status))
            }

            HStack(spacing: 14) {
                Label("\(engine.downloadedSegments)/\(engine.totalSegments)", systemImage: "shippingbox")
                if engine.failedSegments > 0 {
                    Label("\(engine.failedSegments)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.danger)
                }
                if engine.task.convertToMP4 {
                    Label("MP4", systemImage: "film")
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 18) {
                actionButtons
                Spacer()
                Text(engine.task.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch engine.status {
        case .idle, .ready:
            Button {
                manager.start(engine.task.id)
            } label: {
                Label("开始", systemImage: "play.fill")
            }
            .buttonStyle(.borderless)
        case .downloading:
            Button {
                manager.pause(engine.task.id)
            } label: {
                Label("暂停", systemImage: "pause.fill")
            }
            .buttonStyle(.borderless)
            Button {
                manager.cancel(engine.task.id)
            } label: {
                Label("取消", systemImage: "stop.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.danger)
        case .paused:
            Button {
                manager.resume(engine.task.id)
            } label: {
                Label("继续", systemImage: "play.fill")
            }
            .buttonStyle(.borderless)
            Button {
                manager.cancel(engine.task.id)
            } label: {
                Label("取消", systemImage: "stop.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.danger)
        case .failed:
            Button {
                manager.retry(engine.task.id)
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        case .merging:
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
        case .completed, .canceled:
            Button {
                manager.delete(engine.task.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.danger)
        }
    }
}
