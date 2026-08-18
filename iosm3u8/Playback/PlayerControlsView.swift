import AVKit
import SwiftUI

/// 播放器控制条：进度条、时间、倍速、播放/暂停、画中画、全屏
struct PlayerControlsView: View {
    @Bindable var model: PlayerModel
    var fullscreenMode: Bool
    @Binding var isScrubbing: Bool
    @Binding var scrubValue: Double

    private let speeds: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : model.currentTime },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(model.duration, 0.01),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            model.seek(to: scrubValue)
                        }
                    }
                )
                .tint(.white)

                HStack {
                    Text(formatTime(isScrubbing ? scrubValue : model.currentTime))
                    Spacer()
                    if model.isStalled {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                    }
                    Text(formatTime(model.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal)

            HStack(spacing: 30) {
                Menu {
                    ForEach(speeds, id: \.self) { s in
                        Button("\(s, specifier: "%.2g")x") {
                            model.setRate(s)
                        }
                    }
                } label: {
                    Text("\(model.playbackRate, specifier: "%.2g")x")
                        .font(.body.bold())
                        .padding(10)
                        .background(.white.opacity(0.2), in: Capsule())
                }

                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 58))
                }
                .buttonStyle(.plain)

                if model.isPiPPossible {
                    Button {
                        model.startPiP()
                    } label: {
                        Image(systemName: "picture.in.picture")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }

                if !fullscreenMode {
                    Button {
                        model.enterFullscreen()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 14)
        }
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "00:00" }
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}
