import SwiftUI

struct StorageManagementView: View {
    @StateObject private var storage = StorageUsageModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("存储") {
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
