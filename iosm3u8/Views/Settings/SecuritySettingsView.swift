import SwiftUI

/// 安全设置：启用/修改/移除密码、生物识别开关
struct SecuritySettingsView: View {
    let config: AppConfig
    @Environment(\.modelContext) private var modelContext

    @State private var showSetSheet = false
    @State private var showChangeSheet = false

    var body: some View {
        Form {
            Section {
                Toggle("启用密码保护", isOn: Binding(
                    get: { config.requirePassword },
                    set: { enabled in
                        config.requirePassword = enabled
                        if enabled, !PasswordManager.hasPassword {
                            showSetSheet = true
                        } else if !enabled {
                            PasswordManager.removePassword()
                        }
                        save()
                    }
                ))
                Text(PasswordManager.hasPassword ? "已设置密码" : "未设置密码")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } header: {
                Text("密码保护")
            }

            if config.requirePassword || PasswordManager.hasPassword {
                Section {
                    Button("修改密码") { showChangeSheet = true }
                    Button("移除密码", role: .destructive) {
                        PasswordManager.removePassword()
                        config.requirePassword = false
                        save()
                    }
                }
            }

            if config.requirePassword {
                Section {
                    Toggle("Face ID / Touch ID 解锁", isOn: Binding(
                        get: { config.useBiometric },
                        set: { config.useBiometric = $0; save() }
                    ))
                    Text("开启后，启动应用时可使用生物识别快速解锁")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } header: {
                    Text("生物识别")
                }
            }

            Section {
                Text("密码以加盐哈希形式保存在 Keychain 中，不会明文存储。")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("密码保护")
        .sheet(isPresented: $showSetSheet) {
            PinEntrySheet(title: "设置密码", requiresCurrent: false) { pin in
                if PasswordManager.setPassword(pin) {
                    config.requirePassword = true
                    save()
                }
            }
        }
        .sheet(isPresented: $showChangeSheet) {
            PinEntrySheet(title: "修改密码", requiresCurrent: true, verifyCurrent: { old in
                PasswordManager.verify(old)
            }) { pin in
                PasswordManager.setPassword(pin)
                save()
            }
        }
    }

    private func save() {
        config.updatedAt = Date()
        try? modelContext.save()
    }
}

/// 密码设置/修改通用弹窗（两步：输入 → 确认）
struct PinEntrySheet: View {
    let title: String
    let requiresCurrent: Bool
    var verifyCurrent: (String) -> Bool = { _ in true }
    var onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var pin = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    private var stepLabel: String {
        if step == 1 {
            return requiresCurrent ? "请输入当前密码" : "请输入 4 位新密码"
        }
        return "请再次输入确认"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(stepLabel)
                    .font(.headline)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }

                PinKeypad(pin: $pin, onComplete: { _ in handleInput() })

                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func handleInput() {
        defer { pin = "" }
        if step == 1 {
            if requiresCurrent, !verifyCurrent(pin) {
                errorMessage = "当前密码错误"
                return
            }
            step = 2
        } else {
            guard pin == confirm else {
                errorMessage = "两次输入不一致"
                confirm = ""
                step = 1
                return
            }
            onComplete(pin)
            dismiss()
        }
    }
}
