import SwiftUI
import UniformTypeIdentifiers

struct MediaLibraryView: View {
    @ObservedObject var appModel: AppViewModel
    @State private var showImporter = false
    @State private var showStorage = false
    @State private var selectionID: UUID?

    private let transcriptStore = TranscriptStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("媒体库")
                    .font(.headline)
                Spacer()
                Button("存储") {
                    showStorage = true
                }
                Button("导入") {
                    showImporter = true
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if appModel.mediaLibrary.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在导入…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
            } else if !appModel.mediaLibrary.lastImportMessage.isEmpty {
                Text(appModel.mediaLibrary.lastImportMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }

            List(selection: $selectionID) {
                if appModel.mediaLibrary.items.isEmpty {
                    Text("暂无媒体，点击“导入”添加。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appModel.mediaLibrary.items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(timeString(item.duration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        if transcriptStore.isUsable(fingerprint: item.fingerprint) {
                            Text("已转写")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                        .tag(item.id)
                        .contextMenu {
                            Button("移除") {
                                appModel.mediaLibrary.remove(item: item)
                                if selectionID == item.id {
                                    selectionID = nil
                                    appModel.selectedMedia = nil
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let items = indexSet.map { appModel.mediaLibrary.items[$0] }
                        for item in items {
                            appModel.mediaLibrary.remove(item: item)
                        }
                        if let selected = selectionID, items.contains(where: { $0.id == selected }) {
                            selectionID = nil
                            appModel.selectedMedia = nil
                        }
                    }
                }
            }
            .onChange(of: selectionID) { newValue in
                guard let id = newValue else { return }
                appModel.selectedMedia = appModel.mediaLibrary.items.first { $0.id == id }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.audio, UTType.movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    let result = await appModel.mediaLibrary.importMedia(urls: urls)
                    if let last = result.imported.last {
                        selectionID = last.id
                        appModel.selectedMedia = last
                    }
                }
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showStorage) {
            StorageManagementView()
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds > 0 else { return "--:--" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
