import SwiftData
import SwiftUI

/// 设置页：下载参数、保存目录、Headers、分片过滤、安全、关于
struct SettingsView: View {
    @Query(filter: #Predicate<AppConfig> { $0.id == "default" }) private var configs: [AppConfig]
    @Environment(\.modelContext) private var modelContext

    @State private var showSaveDirPicker = false

    private var config: AppConfig? { configs.first }

    var body: some View {
        NavigationStack {
            Form {
                if let config {
                    downloadSection(config)
                    saveDirectorySection(config)
                    headersSection(config)
                    filterSection(config)
                    securitySection(config)
                    aboutSection
                }
            }
            .navigationTitle("设置")
        }
        .sheet(isPresented: $showSaveDirPicker) {
            if let config {
                SaveDirectoryPicker(initialPath: config.saveDirectory) { newPath in
                    config.saveDirectory = newPath
                    save()
                }
            }
        }
    }

    // MARK: - 分区

    private func downloadSection(_ config: AppConfig) -> some View {
        Section("下载") {
            Stepper(
                "默认线程数：\(config.threadCount)",
                value: Binding(
                    get: { config.threadCount },
                    set: { config.threadCount = $0; save() }
                ),
                in: 1...16
            )
            Stepper(
                "并发任务数：\(config.maxConcurrentTasks)",
                value: Binding(
                    get: { config.maxConcurrentTasks },
                    set: { config.maxConcurrentTasks = $0; save() }
                ),
                in: 1...5
            )
            Stepper(
                "分片重试次数：\(config.retryCount)",
                value: Binding(
                    get: { config.retryCount },
                    set: { config.retryCount = $0; save() }
                ),
                in: 0...10
            )
            Toggle(
                "启动自动续传",
                isOn: Binding(
                    get: { config.autoResumeOnLaunch },
                    set: { config.autoResumeOnLaunch = $0; save() }
                )
            )
            Toggle(
                "默认转 MP4",
                isOn: Binding(
                    get: { config.convertToMP4 },
                    set: { config.convertToMP4 = $0; save() }
                )
            )
        }
    }

    private func saveDirectorySection(_ config: AppConfig) -> some View {
        Section {
            HStack {
                Text("保存目录")
                Spacer()
                Text("Documents/\(config.saveDirectory)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                Button("选择") { showSaveDirPicker = true }
                    .buttonStyle(.bordered)
            }
            Text("文件保存在应用沙盒内；已开启文件共享，可在「文件」App 的「我的 iPhone/iPad」中访问。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("保存目录")
        }
    }

    private func headersSection(_ config: AppConfig) -> some View {
        Section {
            let headers = config.defaultHeaders
            Text(headers.isEmpty ? "（无）" : headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textSecondary)
            NavigationLink("编辑默认 Headers") {
                HeaderEditorView(text: Binding(
                    get: {
                        config.defaultHeaders
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: "\n")
                    },
                    set: { text in
                        config.defaultHeaders = parseHeaders(text)
                        save()
                    }
                ))
            }
        } header: {
            Text("请求头")
        }
    }

    private func filterSection(_ config: AppConfig) -> some View {
        Section {
            TextField(
                "默认分片过滤正则（可选）",
                text: Binding(
                    get: { config.segmentFilter ?? "" },
                    set: { config.segmentFilter = $0.isEmpty ? nil : $0; save() }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Text("命中正则的分片会被保留，例如：seg\\d+\\.ts$")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("分片过滤")
        }
    }

    private func securitySection(_ config: AppConfig) -> some View {
        Section {
            NavigationLink("密码保护") {
                SecuritySettingsView(config: config)
            }
        } header: {
            Text("安全")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: "1.0.0")
            LabeledContent(
                "ffmpeg-kit",
                value: FFmpegKitBridge.isAvailable ? "已集成" : "未集成（MP4 转换不可用）"
            )
            LabeledContent("数据存储", value: "SwiftData")
        }
    }

    // MARK: - 工具

    private func save() {
        config?.updatedAt = Date()
        try? modelContext.save()
    }

    private func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { result[key] = value }
            }
        }
        return result
    }
}
