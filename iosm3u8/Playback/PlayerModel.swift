import AVFoundation
import AVKit
import Foundation
import Observation

/// 播放器模型：AVPlayer 封装 + 边下边播 + 倍速 + 画中画 + 全屏
@MainActor
@Observable
final class PlayerModel: NSObject {

    enum Source {
        case file(URL)          // 静态本地文件
        case growingFile(URL)   // 正在增量合并的文件（边下边播）
    }

    let player = AVPlayer()

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isFullscreen = false
    private(set) var isPiPPossible = false
    private(set) var isStalled = false
    var playbackRate: Float = 1.0

    private(set) var source: Source?
    private var lastKnownSize: Int64 = 0

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var monitorTimer: Timer?
    private weak var pipController: AVPictureInPictureController?

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
        monitorTimer?.invalidate()
    }

    // MARK: - 加载

    func load(source: Source) {
        self.source = source
        let url: URL
        switch source {
        case .file(let u): url = u
        case .growingFile(let u): url = u
        }
        lastKnownSize = FileManager.default.fileSize(at: url) ?? 0

        let item = AVPlayerItem(url: url)
        removeObservers()
        addObservers(item)

        // 边下边播：不等待缓冲，立即播放已有内容
        if case .growingFile = source {
            player.automaticallyWaitsToMinimizeStalling = false
        }
        player.replaceCurrentItem(with: item)
        startMonitorIfNeeded()
    }

    private func addObservers(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
            }
        }
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isStalled = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    private func removeObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
    }

    // MARK: - 播放控制

    func play() {
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
    }

    func enterFullscreen() {
        isFullscreen = true
    }

    func exitFullscreen() {
        isFullscreen = false
    }

    // MARK: - 画中画

    /// 由 AVPlayerLayerContainer 在视图入窗后注入控制器
    func attachPiPController(_ controller: AVPictureInPictureController) {
        pipController = controller
        isPiPPossible = AVPictureInPictureController.isPictureInPictureSupported()
    }

    func startPiP() {
        pipController?.startPictureInPicture()
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    // MARK: - 边下边播（文件增长检测）

    private func startMonitorIfNeeded() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        guard case .growingFile = source else { return }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitorGrowingFile()
            }
        }
    }

    private func monitorGrowingFile() {
        guard case .growingFile(let url) = source else { return }
        let size = FileManager.default.fileSize(at: url) ?? 0
        let grew = size > lastKnownSize + (1 << 20)   // 增长超过 1MB
        if grew { lastKnownSize = size }
        // 播放到当前文件末尾附近且文件仍在增长 → 重建 item 继续播
        let nearEnd = duration > 0 && currentTime >= duration - 1.5
        if grew && nearEnd {
            refreshItem(at: url)
        }
    }

    private func refreshItem(at url: URL) {
        let pos = currentTime
        let rate = player.rate
        let item = AVPlayerItem(url: url)

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }

        player.replaceCurrentItem(with: item)
        player.rate = rate
        player.seek(to: CMTime(seconds: max(0, pos - 0.5), preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                self?.duration = self?.player.currentItem?.duration.seconds ?? 0
            }
        }
    }
}
