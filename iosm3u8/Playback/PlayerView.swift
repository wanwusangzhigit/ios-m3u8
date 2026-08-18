import AVKit
import SwiftUI

/// 播放器视图：视频层 + 自动隐藏的控制条
/// - fullscreenMode：全屏展示时隐藏额外 UI（由外层全屏容器使用）
struct PlayerView: View {
    @Bindable var model: PlayerModel
    var fullscreenMode = false

    @State private var showControls = true
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AVPlayerLayerContainer(player: model.player) { controller in
                model.attachPiPController(controller)
            }
            .ignoresSafeArea()

            if showControls {
                PlayerControlsView(
                    model: model,
                    fullscreenMode: fullscreenMode,
                    isScrubbing: $isScrubbing,
                    scrubValue: $scrubValue
                )
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
        // 控制条显示 4 秒后自动隐藏
        .task(id: showControls) {
            guard showControls else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !isScrubbing {
                withAnimation(.easeInOut(duration: 0.2)) { showControls = false }
            }
        }
    }
}

#Preview {
    PlayerView(model: PlayerModel())
        .frame(height: 300)
}
