import SwiftUI

/// 任务详情：大进度、信息、操作、播放（边下边播）、日志、分片状态
struct TaskDetailView: View {
    let engineID: UUID

    @Environment(DownloadManager.self) private var manager
    @State private var playerModel: PlayerModel?
    @State private var showPlayer = false
    @State private var showDeleteConfirm = false
    @State private var showSegmentList = false

    private var engine: TaskEngine? { manager.engine(for: engineID) }

    var body: some View {
        Group {
            if let engine {
                content(engine)
            } else {
                ContentUnavailableView("任务不存在", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(engine?.task.title ?? "任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let engine, canPlay(engine) {
                    Button {
                        openPlayer(engine)
                    } label: {
                        Label("播放", systemImage: "play.rectangle")
                    }
                }
                if let engine, let url = engine.task.outputFileURL,
                   FileManager.default.fileExists(atPath: url.path) {
                    Menu {
                        ShareLink(item: url)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let playerModel {
                ZStack(alignment: .topTrailing) {
                    PlayerView(model: playerModel, fullscreenMode: true)
                        .ignoresSafeArea()
                    Button {
                        playerModel.pause()
                        playerModel.exitFullscreen()
                        showPlayer = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .padding(16)
                    }
                }
            }
        }
        .confirmationDialog("删除任务？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除任务及文件", role: .destructive) {
                manager.delete(engineID)
            }
            Button("仅删除任务记录", role: .destructive) {
                manager.delete(engineID, includingFiles: false)
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ engine: TaskEngine) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressSection(engine)
                infoSection(engine)
                actionSection(engine)
                logSection(engine)
                segmentSection(engine)
            }
            .padding()
        }
    }

    private func progressSection(_ engine: TaskEngine) -> some View {
        VStack(spacing: 10) {
            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)
                .tint(Theme.color(for: engine.status))

            HStack {
                Text(Formatters.percent(engine.progress))
                    .font(.title2.bold())
                Spacer()
                Label(engine.status.label, systemImage: engine.status.systemImage)
                    .foregroundStyle(Theme.color(for: engine.status))
                Text(Formatters.speed(engine.speedBPS))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack {
                Text("已下载 \(Formatters.bytes(engine.downloadedBytes))")
                Spacer()
                Text("分片 \(engine.downloadedSegments)/\(engine.totalSegments)")
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoSection(_ engine: TaskEngine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("信息").font(.headline)
            LabeledContent("地址", value: engine.task.urlString)
            LabeledContent("线程数", value: "\(engine.task.threadCount)")
            LabeledContent("保存目录", value: "Documents/\(engine.task.savePath)")
            LabeledContent("创建时间", value: engine.task.createdAt.formatted(date: .abbreviated, time: .shortened))
            if engine.task.convertToMP4 {
                LabeledContent("输出格式", value: "MP4")
            }
            if let error = engine.task.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func actionSection(_ engine: TaskEngine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("操作").font(.headline)
            HStack(spacing: 16) {
                switch engine.status {
                case .idle, .ready:
                    Button { manager.start(engine.task.id) } label: { Label("开始", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                case .downloading:
                    Button { manager.pause(engine.task.id) } label: { Label("暂停", systemImage: "pause.fill") }
                        .buttonStyle(.bordered)
                    Button { manager.cancel(engine.task.id) } label: { Label("取消", systemImage: "stop.fill") }
                        .buttonStyle(.bordered)
                        .tint(Theme.danger)
                case .paused:
                    Button { manager.resume(engine.task.id) } label: { Label("继续", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                    Button { manager.cancel(engine.task.id) } label: { Label("取消", systemImage: "stop.fill") }
                        .buttonStyle(.bordered)
                        .tint(Theme.danger)
                case .failed:
                    Button { manager.retry(engine.task.id) } label: { Label("重试", systemImage: "arrow.clockwise") }
                        .buttonStyle(.borderedProminent)
                case .merging:
                    ProgressView("正在合并/转码…").tint(Theme.accent)
                case .completed:
                    Button { openPlayer(engine) } label: { Label("播放", systemImage: "play.rectangle") }
                        .buttonStyle(.borderedProminent)
                case .canceled:
                    Button { manager.start(engine.task.id) } label: { Label("重新开始", systemImage: "play.fill") }
                        .buttonStyle(.bordered)
                }

                if let url = engine.task.outputFileURL,
                   FileManager.default.fileExists(atPath: url.path) {
                    ShareLink(item: url) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func logSection(_ engine: TaskEngine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日志").font(.headline)
            let logs = engine.task.logEntries
            if logs.isEmpty {
                Text("暂无日志")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logs.reversed().enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func segmentSection(_ engine: TaskEngine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分片状态").font(.headline)
                Spacer()
                Button(showSegmentList ? "收起" : "展开") {
                    withAnimation { showSegmentList.toggle() }
                }
                .font(.caption)
            }

            if showSegmentList {
                let segs = engine.segments
                if segs.isEmpty {
                    Text("尚未解析")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    // 分片过多时只展示前 200 个色块
                    let shown = segs.prefix(200)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 10), spacing: 3)],
                        spacing: 3
                    ) {
                        ForEach(shown) { seg in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: seg.state))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    HStack(spacing: 12) {
                        legendItem("完成", .success)
                        legendItem("下载中", .accent)
                        legendItem("失败", .danger)
                        legendItem("等待", .secondary)
                        if segs.count > 200 {
                            Spacer()
                            Text("仅显示前 200 / \(segs.count)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .font(.caption2)
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
        .foregroundStyle(Theme.textSecondary)
    }

    private func color(for state: Segment.State) -> Color {
        switch state {
        case .downloaded: return Theme.success
        case .downloading: return Theme.accent
        case .failed: return Theme.danger
        case .pending: return Theme.textSecondary.opacity(0.35)
        case .skipped: return Color.gray.opacity(0.25)
        }
    }

    // MARK: - 播放

    private func canPlay(_ engine: TaskEngine) -> Bool {
        if let out = engine.task.outputFileURL,
           FileManager.default.fileExists(atPath: out.path) {
            return true
        }
        if let merged = engine.task.mergedFileURL,
           FileManager.default.fileExists(atPath: merged.path),
           engine.task.mergedSegments > 0 {
            return true
        }
        return false
    }

    private func openPlayer(_ engine: TaskEngine) {
        let model = GrowingFilePlayer.makeModel(for: engine.task)
        playerModel = model
        model.play()
        showPlayer = true
    }
}
