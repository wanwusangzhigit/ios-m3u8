import SwiftData
import SwiftUI

@main
struct iOSM3U8App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer
    private let appConfig: AppConfig
    @State private var isLocked = false

    init() {
        do {
            container = try ModelContainer(
                for: DownloadTask.self, AppConfig.self
            )
        } catch {
            fatalError("无法创建数据容器：\(error)")
        }
        // 初始化下载管理器：注入存储与配置，加载任务并自动续传
        let context = ModelContext(container)
        let config = AppConfigStore.fetchOrCreate(in: context)
        appConfig = config
        let manager = DownloadManager.shared
        manager.setup(context: context, config: config)
        manager.loadTasks()
        manager.resumeReadyTasks()
        // 启动密码保护
        _isLocked = State(initialValue: config.requirePassword)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                if isLocked {
                    LockView(allowBiometric: appConfig.useBiometric) {
                        isLocked = false
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isLocked)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // 进入后台后重新锁定
            if phase == .background, appConfig.requirePassword {
                isLocked = true
            }
        }
    }
}
