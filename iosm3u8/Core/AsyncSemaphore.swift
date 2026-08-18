import Foundation

/// 异步信号量：限制同时进行的分片下载数（actor 实现，线程安全）
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) {
        self.count = max(1, count)
    }

    /// 获取一个许可；无可用许可时挂起等待
    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    /// 归还许可；唤醒最早等待者
    func signal() {
        if waiters.isEmpty {
            count += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
