import SwiftUI

/// 默认请求头编辑器（每行 键:值）
struct HeaderEditorView: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.caption.monospaced())
                    .frame(minHeight: 260)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("每行一个请求头，格式：键: 值")
            } footer: {
                Text("例如：\nUser-Agent: Mozilla/5.0 ...\nReferer: https://example.com/\nCookie: xxx")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("默认 Headers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}
