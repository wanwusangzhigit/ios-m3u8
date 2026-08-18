import SwiftUI

/// 任务列表：搜索 + 过滤 + 批量操作 + 卡片网格
struct TaskListView: View {
    let filter: TaskFilter

    @Environment(DownloadManager.self) private var manager
    @State private var searchText = ""
    @State private var selection: UUID?
    @State private var showBatchBar = false
    @State private var selectedIDs = Set<UUID>()
    @State private var showDeleteConfirm = false

    private var engines: [TaskEngine] {
        manager.allEngines.filter { engine in
            guard filter.matches(engine) else { return false }
            if searchText.isEmpty { return true }
            return engine.task.title.localizedCaseInsensitiveContains(searchText)
                || engine.task.urlString.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if engines.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(engines) { engine in
                            TaskCardView(
                                engine: engine,
                                isSelected: selectedIDs.contains(engine.task.id)
                            )
                            .onTapGesture {
                                if showBatchBar {
                                    toggleSelection(engine.task.id)
                                } else {
                                    selection = engine.task.id
                                }
                            }
                            .contextMenu {
                                contextMenuItems(for: engine)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(filter.rawValue)
        .searchable(text: $searchText, prompt: "搜索标题或链接")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation { showBatchBar.toggle() }
                    selectedIDs.removeAll()
                } label: {
                    Label(
                        showBatchBar ? "完成" : "批量",
                        systemImage: showBatchBar ? "checkmark" : "checkmark.circle"
                    )
                }
                .help("批量操作")

                Menu {
                    Button("全部暂停", systemImage: "pause.fill") { manager.pauseAll() }
                    Button("全部恢复", systemImage: "play.fill") { manager.resumeAll() }
                    Divider()
                    Button("全部取消", systemImage: "stop.fill", role: .destructive) { manager.cancelAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(item: $selection) { id in
            TaskDetailView(engineID: id)
        }
        .safeAreaInset(edge: .bottom) {
            if showBatchBar {
                batchBar
            }
        }
        .confirmationDialog("删除所选任务？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除任务及文件", role: .destructive) {
                for id in selectedIDs { manager.delete(id, includingFiles: true) }
                selectedIDs.removeAll()
            }
            Button("仅删除任务记录", role: .destructive) {
                for id in selectedIDs { manager.delete(id, includingFiles: false) }
                selectedIDs.removeAll()
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView {
            Label(filter == .all ? "暂无任务" : "没有\(filter.rawValue)的任务", systemImage: "tray")
        } description: {
            Text("点击右上角「+」新建下载任务")
        }
    }

    // MARK: - 批量栏

    private var batchBar: some View {
        HStack(spacing: 20) {
            Text("已选 \(selectedIDs.count) 项")
                .font(.subheadline)
            Spacer()
            Button("全选") {
                if selectedIDs.count == engines.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(engines.map { $0.task.id })
                }
            }
            Button {
                for id in selectedIDs { manager.pause(id) }
            } label: {
                Label("暂停", systemImage: "pause.fill")
            }
            Button {
                for id in selectedIDs { manager.resume(id) }
            } label: {
                Label("恢复", systemImage: "play.fill")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func contextMenuItems(for engine: TaskEngine) -> some View {
        switch engine.status {
        case .idle, .ready:
            Button("开始", systemImage: "play.fill") { manager.start(engine.task.id) }
        case .downloading:
            Button("暂停", systemImage: "pause.fill") { manager.pause(engine.task.id) }
            Button("取消", systemImage: "stop.fill", role: .destructive) { manager.cancel(engine.task.id) }
        case .paused:
            Button("继续", systemImage: "play.fill") { manager.resume(engine.task.id) }
            Button("取消", systemImage: "stop.fill", role: .destructive) { manager.cancel(engine.task.id) }
        case .failed:
            Button("重试", systemImage: "arrow.clockwise") { manager.retry(engine.task.id) }
        case .merging:
            EmptyView()
        case .completed, .canceled:
            Button("删除", systemImage: "trash", role: .destructive) { manager.delete(engine.task.id) }
        }
    }
}
