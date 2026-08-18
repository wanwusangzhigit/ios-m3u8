import BackgroundTasks
import UIKit

/// 应用生命周期委托
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 后台续传任务注册（须在启动完成前）
        BackgroundTaskManager.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 进入后台：调度系统续传任务
        BackgroundTaskManager.scheduleRefresh()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // 回前台：界面层负责检查并续传
    }
}
