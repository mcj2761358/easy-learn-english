import SwiftUI
import UniformTypeIdentifiers

struct MediaLibraryView: View {
    @ObservedObject var appModel: AppViewModel
    @Binding var selection: SidebarSelection?
    @State private var showImporter = false

    private let transcriptStore = TranscriptStore()
    private let supportedContentTypes: [UTType] = MediaLibrary.supportedExtensions.compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.full")
                    .foregroundColor(.secondary)
                Text("媒体库")
                    .font(.headline)
                Spacer()
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(appModel.mediaLibrary.lastImportMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !appModel.mediaLibrary.lastImportDetail.isEmpty {
                        Text(appModel.mediaLibrary.lastImportDetail)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 8)
            }

            List(selection: $selection) {
                Section {
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
                            .tag(SidebarSelection.media(item.id))
                            .contextMenu {
                                Button("移除") {
                                    appModel.mediaLibrary.remove(item: item)
                                    if case .media(let id) = selection, id == item.id {
                                        selection = nil
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
                            if case .media(let id) = selection, items.contains(where: { $0.id == id }) {
                                selection = nil
                                appModel.selectedMedia = nil
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selection) { newValue in
                switch newValue {
                case .media(let id):
                    appModel.selectedMedia = appModel.mediaLibrary.items.first { $0.id == id }
                case .settings:
                    appModel.selectedMedia = nil
                case .none:
                    appModel.selectedMedia = nil
                }
            }
            .onChange(of: appModel.mediaLibrary.items) { _ in
                if case .media(let id) = selection,
                   appModel.mediaLibrary.items.contains(where: { $0.id == id }) {
                    return
                }
                if let first = appModel.mediaLibrary.items.first {
                    selection = .media(first.id)
                    appModel.selectedMedia = first
                }
            }
            .onAppear {
                if selection == nil, let first = appModel.mediaLibrary.items.first {
                    selection = .media(first.id)
                    appModel.selectedMedia = first
                }
            }

            Spacer(minLength: 0)

            Button {
                selection = .settings
                appModel.selectedMedia = nil
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("设置")
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(selection == .settings ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: supportedContentTypes.isEmpty ? [UTType.audio, UTType.movie] : supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    let result = await appModel.mediaLibrary.importMedia(urls: urls)
                    if let last = result.imported.last {
                        selection = .media(last.id)
                        appModel.selectedMedia = last
                    }
                }
            case .failure:
                break
            }
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
