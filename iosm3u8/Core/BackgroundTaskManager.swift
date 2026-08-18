import BackgroundTasks
import Foundation

/// 后台续传：BGTaskScheduler 注册与调度
/// - 系统在合适时机（约每 15 分钟起，受系统调度）唤醒应用续传未完成任务
/// - 进入后台时调度；任务执行完重新调度下一轮
enum BackgroundTaskManager {
    static let refreshIdentifier = "com.m3u8dl.iosm3u8.refresh"

    /// 在 didFinishLaunching 中调用（须在启动完成前注册）
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { task in
            handleRefresh(task: task as? BGAppRefreshTask)
        }
    }

    /// 进入后台时调度下一轮续传
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(task: BGAppRefreshTask?) {
        guard let task else { return }
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        Task { @MainActor in
            await DownloadManager.shared.resumeUnfinishedTasksForBackground()
            task.setTaskCompleted(success: true)
            scheduleRefresh()
        }
    }
}
