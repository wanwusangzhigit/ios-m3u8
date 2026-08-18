import SwiftData
import SwiftUI

/// 侧边栏导航项
enum SidebarItem: Hashable {
    case tasks(filter: TaskFilter)
    case parse
    case settings
}

/// 任务列表过滤
enum TaskFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "全部"
    case downloading = "下载中"
    case paused = "暂停"
    case completed = "已完成"
    case failed = "失败"

    var id: String { rawValue }

    func matches(_ engine: TaskEngine) -> Bool {
        switch self {
        case .all: return true
        case .downloading: return engine.status.isActive
        case .paused: return engine.status == .paused
        case .completed: return engine.status == .completed
        case .failed: return engine.status == .failed
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

/// 应用根视图：侧边栏 + 主区，适配横屏/分屏
struct RootView: View {
    @State private var selection: SidebarItem? = .tasks(filter: .all)
    @State private var showNewTask = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, showNewTask: $showNewTask)
                .navigationSplitViewColumnWidth(min: 190, ideal: 230)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNewTask = true
                        } label: {
                            Label("新建", systemImage: "plus")
                        }
                        .help("新建下载任务")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(Theme.colorScheme)
        .tint(Theme.accent)
        .environment(DownloadManager.shared)
        .sheet(isPresented: $showNewTask) {
            NewTaskView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .tasks(filter: .all) {
        case .tasks(let filter):
            TaskListView(filter: filter)
        case .parse:
            ParseView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [DownloadTask.self, AppConfig.self], inMemory: true)
}
