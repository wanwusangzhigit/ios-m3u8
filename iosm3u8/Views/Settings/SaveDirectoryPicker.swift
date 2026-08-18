import SwiftUI

/// 应用内保存目录选择器（浏览 Documents 子目录，可新建文件夹）
struct SaveDirectoryPicker: View {
    let initialPath: String
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPath: String
    @State private var newFolderName = ""

    init(initialPath: String, onSelect: @escaping (String) -> Void) {
        self.initialPath = initialPath
        self.onSelect = onSelect
        _currentPath = State(initialValue: initialPath)
    }

    /// 当前浏览的绝对目录（Documents 下）
    private var currentURL: URL {
        let base = FileManager.default.documentsDirectory
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return currentPath.isEmpty
            ? base
            : base.appendingPathComponent(currentPath, isDirectory: true)
    }

    private var displayPath: String {
        currentPath.isEmpty ? "Documents" : "Documents/\(currentPath)"
    }

    private var subdirectories: [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .map { $0.lastPathComponent }
            .sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("当前目录") {
                    HStack {
                        Text(displayPath)
                            .font(.caption.monospaced())
                        Spacer()
                        Button("选择此处") {
                            onSelect(currentPath.isEmpty ? "Documents" : currentPath)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("子目录") {
                    if subdirectories.isEmpty {
                        Text("（无子目录）")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(subdirectories, id: \.self) { name in
                        Button {
                            currentPath = currentPath.isEmpty ? name : "\(currentPath)/\(name)"
                        } label: {
                            Label(name, systemImage: "folder")
                        }
                    }
                    if !currentPath.isEmpty {
                        Button {
                            if let idx = currentPath.lastIndex(of: "/") {
                                currentPath = String(currentPath[..<idx])
                            } else {
                                currentPath = ""
                            }
                        } label: {
                            Label("上一级", systemImage: "arrow.up")
                        }
                    }
                }

                Section("新建文件夹") {
                    TextField("文件夹名", text: $newFolderName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("创建并进入") {
                        let dir = currentURL.appendingPathComponent(newFolderName, isDirectory: true)
                        if FileManager.default.ensureDirectory(at: dir) {
                            currentPath = currentPath.isEmpty
                                ? newFolderName
                                : "\(currentPath)/\(newFolderName)"
                            newFolderName = ""
                        }
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("保存目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
