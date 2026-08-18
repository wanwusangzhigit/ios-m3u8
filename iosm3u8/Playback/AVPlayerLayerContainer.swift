import AVKit
import SwiftUI

/// 承载 AVPlayerLayer 的 UIViewRepresentable，并创建画中画控制器
struct AVPlayerLayerContainer: UIViewRepresentable {
    let player: AVPlayer
    var onPiPControllerReady: (AVPictureInPictureController) -> Void

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView(player: player)
        view.onPiPControllerReady = onPiPControllerReady
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

/// 承载 AVPlayerLayer 的 UIView，负责在入窗后创建画中画控制器
final class PlayerContainerView: UIView {
    let playerLayer = AVPlayerLayer()
    var onPiPControllerReady: ((AVPictureInPictureController) -> Void)?
    private var pipController: AVPictureInPictureController?

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        // 视图进入窗口后创建画中画控制器（需已附加到 window）
        if window != nil, pipController == nil {
            let controller = AVPictureInPictureController(playerLayer: playerLayer)
            pipController = controller
            if let controller {
                onPiPControllerReady?(controller)
            }
        }
    }
}
