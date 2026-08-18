import SwiftData
import SwiftUI

/// 链接解析页：粘贴分享文本 → 解析 → 预览 → 添加任务
struct ParseView: View {
    @Environment(DownloadManager.self) private var manager
    @Query(filter: #Predicate<AppConfig> { $0.id == "default" }) private var configs: [AppConfig]

    @State private var inputText = ""
    @State private var results: [ParsedMedia] = []
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var showMP4Unsupported = false

    private var config: AppConfig? { configs.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextEditor(text: $inputText)
                    .frame(minHeight: 110)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    .overlay(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("粘贴抖音/微博/皮皮虾分享文本，或任意网页/直链")
                                .foregroundStyle(Theme.textSecondary)
                                .padding(14)
                        }
                    }

                HStack {
                    Button {
                        Task { await parse() }
                    } label: {
                        if isParsing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("解析", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isParsing || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Button("清空") {
                        inputText = ""
                        results = []
                        errorMessage = nil
                    }
                    .disabled(inputText.isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !results.isEmpty {
                    List {
                        ForEach(results) { media in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(media.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(media.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                    Text(media.source)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()

                                Text(media.kind == .m3u8 ? "m3u8" : "mp4")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        media.kind == .m3u8 ? Theme.accent.opacity(0.2) : Theme.warning.opacity(0.2),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(media.kind == .m3u8 ? Theme.accent : Theme.warning)

                                Button {
                                    addTask(media)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .disabled(media.kind == .mp4)
                                .help(media.kind == .mp4 ? "暂不支持 mp4 直链下载" : "添加为下载任务")
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 200)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("链接解析")
        }
        .alert("暂不支持", isPresented: $showMP4Unsupported) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("解析结果中的 mp4 直链暂不支持下载，请使用 m3u8 地址")
        }
    }

    // MARK: - 解析

    private func parse() async {
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isParsing = true
        errorMessage = nil
        results = []
        defer { isParsing = false }

        do {
            let media = try await LinkParserHub.parse(raw, headers: config?.defaultHeaders ?? [:])
            results = media
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addTask(_ media: ParsedMedia) {
        guard media.kind == .m3u8 else {
            showMP4Unsupported = true
            return
        }
        manager.createTask(
            urlString: media.url.absoluteString,
            title: media.title,
            autoStart: true
        )
    }
}
