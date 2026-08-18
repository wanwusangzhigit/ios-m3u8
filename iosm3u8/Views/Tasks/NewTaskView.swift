import SwiftData
import SwiftUI

/// 新建下载任务表单：URL/标题 + 自动解析（多码率选择）+ 选项
struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var manager
    @Query(filter: #Predicate<AppConfig> { $0.id == "default" }) private var configs: [AppConfig]

    @State private var urlString = ""
    @State private var title = ""
    @State private var threadCount = 4
    @State private var headersText = ""
    @State private var segmentFilter = ""
    @State private var convertToMP4 = false
    @State private var savePath = "Downloads"

    @State private var variants: [Variant] = []
    @State private var selectedVariant = 0
    @State private var isParsing = false
    @State private var parseError: String?
    @State private var parseHint: String?
    @State private var lastParsedURL = ""
    @State private var parseTask: Task<Void, Never>?

    private var config: AppConfig? { configs.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("播放列表") {
                    TextField("M3U8 地址、网页或分享链接", text: $urlString, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("标题（可选，自动填充）", text: $title)
                }

                if !variants.isEmpty {
                    Section("清晰度") {
                        Picker("码率", selection: $selectedVariant) {
                            ForEach(Array(variants.enumerated()), id: \.offset) { i, v in
                                Text(v.displayName).tag(i)
                            }
                        }
                    }
                }

                if let parseHint {
                    Section {
                        Text(parseHint)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section("选项") {
                    Stepper("并发线程：\(threadCount)", value: $threadCount, in: 1...16)
                    Toggle("转 MP4（需 ffmpeg-kit）", isOn: $convertToMP4)
                    TextField("保存目录（Documents 下）", text: $savePath)
                        .textInputAutocapitalization(.never)
                    TextField("分片过滤正则（可选）", text: $segmentFilter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("额外 Headers（每行 键:值）", text: $headersText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.caption.monospaced())
                }

                if isParsing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在解析…")
                        }
                    }
                }
                if let parseError {
                    Section {
                        Text(parseError)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { addTask() }
                        .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: urlString) { _, newValue in
                debounceParse(newValue)
            }
            .onAppear {
                threadCount = config?.threadCount ?? 4
                savePath = config?.saveDirectory ?? "Downloads"
                segmentFilter = config?.segmentFilter ?? ""
                convertToMP4 = config?.convertToMP4 ?? false
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 解析（防抖）

    private func debounceParse(_ raw: String) {
        parseTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastParsedURL else { return }
        parseTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await parsePlaylist(trimmed)
        }
    }

    private func parsePlaylist(_ raw: String) async {
        guard let url = URL(string: raw), url.scheme != nil else {
            variants = []
            parseHint = nil
            return
        }
        isParsing = true
        parseError = nil
        lastParsedURL = raw
        defer { isParsing = false }

        let headers = config?.defaultHeaders ?? [:]
        do {
            if raw.lowercased().contains(".m3u8") {
                let text = try await HTTPClient.shared.getString(from: url, headers: headers)
                let masterVariants = try M3U8Parser.parseMaster(text, baseURL: url)
                if !masterVariants.isEmpty {
                    variants = masterVariants
                    parseHint = "检测到 \(masterVariants.count) 档码率，请选择"
                    if title.isEmpty { title = url.lastPathComponent }
                } else {
                    let media = try M3U8Parser.parseMedia(text, baseURL: url)
                    variants = []
                    parseHint = "共 \(media.segments.count) 个分片，时长约 \(Int(media.totalDuration)) 秒"
                    if title.isEmpty { title = url.lastPathComponent }
                }
            } else {
                let results = try await LinkParserHub.parse(raw, headers: headers)
                guard let m3u8 = results.first(where: { $0.kind == .m3u8 }) else {
                    parseError = "未找到 m3u8 地址（当前仅支持 m3u8 流下载）"
                    return
                }
                urlString = m3u8.url.absoluteString
                variants = []
                parseHint = "已识别媒体：\(m3u8.title)（\(m3u8.source)）"
                if title.isEmpty { title = m3u8.title }
            }
        } catch {
            parseError = error.localizedDescription
        }
    }

    // MARK: - 添加

    private func addTask() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }

        let task = manager.createTask(
            urlString: trimmed,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            headers: parseHeaders(headersText),
            segmentFilter: segmentFilter.isEmpty ? nil : segmentFilter,
            threadCount: threadCount,
            convertToMP4: convertToMP4,
            savePath: savePath.isEmpty ? "Downloads" : savePath,
            autoStart: true
        )
        if let task, !variants.isEmpty, selectedVariant < variants.count {
            task.variantIndex = selectedVariant
            task.variants = variants
            try? task.modelContext?.save()
        }
        dismiss()
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
