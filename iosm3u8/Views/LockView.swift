import SwiftUI

/// 数字键盘 + 4 位圆点指示（锁屏/密码设置共用）
struct PinKeypad: View {
    @Binding var pin: String
    var maxLength = 4
    var onComplete: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                ForEach(0..<maxLength, id: \.self) { i in
                    Circle()
                        .strokeBorder(Theme.border, lineWidth: 1.5)
                        .background(Circle().fill(i < pin.count ? Theme.accent : Color.clear))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 6)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(1...9, id: \.self) { n in
                    digit("\(n)")
                }
                Color.clear.frame(height: 52)
                digit("0")
                Button {
                    if !pin.isEmpty { pin.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: 260)
        }
    }

    private func digit(_ label: String) -> some View {
        Button {
            guard pin.count < maxLength else { return }
            pin.append(label)
            if pin.count == maxLength {
                onComplete(pin)
            }
        } label: {
            Text(label)
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 启动锁定屏：数字密码 + 生物识别
struct LockView: View {
    var allowBiometric: Bool
    var onUnlock: () -> Void

    @State private var pin = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)

            Text("M3U8 下载器")
                .font(.title2.bold())

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }

            PinKeypad(pin: $pin, onComplete: { _ in submit() })

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if allowBiometric {
                biometricUnlock()
            }
        }
    }

    private func submit() {
        if PasswordManager.verify(pin) {
            pin = ""
            onUnlock()
        } else {
            errorMessage = "密码错误，请重试"
            pin = ""
        }
    }

    private func biometricUnlock() {
        Task {
            if await PasswordManager.authenticateWithBiometrics() {
                onUnlock()
            }
        }
    }
}
