import SwiftUI

/// 侧边栏：任务分类 + 工具入口
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Binding var showNewTask: Bool
    @Environment(DownloadManager.self) private var manager

    var body: some View {
        List(selection: $selection) {
            Section("任务") {
                ForEach(TaskFilter.allCases) { filter in
                    Label {
                        HStack {
                            Text(filter.rawValue)
                            Spacer()
                            Text("\(count(for: filter))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } icon: {
                        Image(systemName: filter.systemImage)
                    }
                    .tag(SidebarItem.tasks(filter: filter))
                }
            }

            Section("工具") {
                Label("链接解析", systemImage: "wand.and.stars")
                    .tag(SidebarItem.parse)
                Label("设置", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .navigationTitle("M3U8 下载器")
        .safeAreaInset(edge: .bottom) {
            Button {
                showNewTask = true
            } label: {
                Label("新建下载任务", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func count(for filter: TaskFilter) -> Int {
        switch filter {
        case .all: return manager.engines.count
        case .downloading: return manager.activeCount
        case .paused: return manager.pausedCount
        case .completed: return manager.completedCount
        case .failed: return manager.failedCount
        }
    }
}
