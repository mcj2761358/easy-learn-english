import SwiftUI

struct StorageManagementView: View {
    @StateObject private var storage = StorageUsageModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("媒体缓存")
                        Text(AppPaths.mediaDir.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(storage.mediaBytes.byteCountString)
                        .font(.caption)
                    Button("打开") {
                        storage.openMediaFolder()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导入暂存")
                        Text(AppPaths.importStagingDir.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(storage.importStagingBytes.byteCountString)
                        .font(.caption)
                    Button("打开") {
                        storage.openImportStagingFolder()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("字幕缓存")
                        Text(AppPaths.transcriptsDir.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(storage.transcriptBytes.byteCountString)
                        .font(.caption)
                    Button("打开") {
                        storage.openTranscriptsFolder()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("媒体库索引")
                        Text(AppPaths.libraryFile.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(storage.libraryBytes.byteCountString)
                        .font(.caption)
                    Button("打开") {
                        storage.openLibraryFile()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("词汇表")
                        Text(AppPaths.vocabularyFile.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(storage.vocabularyBytes.byteCountString)
                        .font(.caption)
                    Button("打开") {
                        storage.openVocabularyFile()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("翻译缓存")
                        Text(AppPaths.translationCacheFile.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(storage.translationCacheBytes.byteCountString)
                        .font(.caption)
                    Button("打开") {
                        storage.openTranslationCacheFile()
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("内置浏览器 Cookies")
                        Text(AppPaths.ytDlpCookiesFile.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(storage.cookiesBytes.byteCountString)
                        .font(.caption)
                    Button("打开") {
                        storage.openCookiesFile()
                    }
                    Button("清除") {
                        storage.clearCookiesFile()
                    }
                }

                HStack {
                    if let last = storage.lastUpdated {
                        Text("更新于：\(last.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("更新于：--")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("刷新") {
                        storage.refresh()
                    }
                }
                    }
                } label: {
                    Text("存储")
                }

                GroupBox {
                    VStack(spacing: 12) {
                        if storage.appSupportEntries.isEmpty {
                            Text("暂无数据")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(storage.appSupportEntries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                        Text(entry.url.path)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.bytes.byteCountString)
                                        .font(.caption)
                                    Button("打开") {
                                        storage.openEntry(entry)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Text("应用数据")
                }
            }
        }
        .padding(12)
        .frame(width: 460)
        .onAppear {
            storage.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    dismiss()
                }
            }
        }
    }
}
