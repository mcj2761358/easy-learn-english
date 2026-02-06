import SwiftUI
import UniformTypeIdentifiers

struct MediaLibraryView: View {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var mediaLibrary: MediaLibrary
    @Binding var selection: SidebarSelection?
    @State private var selectionSet: Set<SidebarSelection> = []
    @State private var showImporter = false
    @State private var showNewFolderSheet = false
    @State private var newFolderParentID: UUID? = nil
    @State private var newFolderName = ""
    @State private var showRenameFolderSheet = false
    @State private var renameFolderID: UUID? = nil
    @State private var renameFolderName = ""
    @State private var showRenameItemSheet = false
    @State private var renameItemID: UUID? = nil
    @State private var renameItemName = ""
    @State private var moveAction: MoveAction? = nil
    @State private var showFolderDeleteBlockedAlert = false
    @State private var folderDeleteBlockedName = ""

    private let transcriptStore = TranscriptStore()
    private let supportedContentTypes: [UTType] = MediaLibrary.supportedExtensions.compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mediaLibrary.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在导入…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
            } else if !mediaLibrary.lastImportMessage.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mediaLibrary.lastImportMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !mediaLibrary.lastImportDetail.isEmpty {
                        Text(mediaLibrary.lastImportDetail)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 8)
            }

            List(selection: $selectionSet) {
                Section {
                    HStack {
                        Image(systemName: "book")
                            .foregroundColor(.secondary)
                        Text("生词本")
                    }
                    .tag(SidebarSelection.vocabulary)

                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.secondary)
                        Text("在线资源")
                    }
                    .tag(SidebarSelection.onlineResources)

                    HStack {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                        Text("设置")
                    }
                    .tag(SidebarSelection.settings)
                } header: {
                    Text("菜单")
                }

                Section {
                    if libraryNodes.isEmpty {
                        Text("暂无媒体或文件夹，点击“导入”或“新建文件夹”。")
                            .foregroundColor(.secondary)
                    } else {
                        OutlineGroup(libraryNodes, children: \.children) { node in
                            libraryRow(for: node)
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "tray.full")
                            .foregroundColor(.secondary)
                        Text("媒体库")
                        Spacer()
                        Button("新建文件夹") {
                            beginNewFolder(parentID: nil)
                        }
                        Button("导入") {
                            showImporter = true
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectionSet) { newValue in
                handleSelectionChange(newValue)
            }
            .onChange(of: mediaLibrary.items) { _ in
                reconcileSelectionAfterDataChange()
            }
            .onChange(of: mediaLibrary.folders) { _ in
                reconcileSelectionAfterDataChange()
            }
            .onAppear {
                if selectionSet.isEmpty, let selection {
                    selectionSet = [selection]
                }
                if selection == nil, let first = mediaLibrary.items.first {
                    selectMedia(first)
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: supportedContentTypes.isEmpty ? [UTType.audio, UTType.movie] : supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    let result = await mediaLibrary.importMedia(urls: urls)
                    if let last = result.imported.last {
                        selectMedia(last)
                    }
                }
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NameInputSheet(
                title: "新建文件夹",
                initialName: newFolderName,
                confirmLabel: "创建"
            ) { name in
                _ = mediaLibrary.createFolder(name: name, parentID: newFolderParentID)
                newFolderName = ""
            }
        }
        .sheet(isPresented: $showRenameFolderSheet) {
            NameInputSheet(
                title: "重命名文件夹",
                initialName: renameFolderName,
                confirmLabel: "保存"
            ) { name in
                if let id = renameFolderID {
                    mediaLibrary.renameFolder(id: id, newName: name)
                }
            }
            .id(renameFolderID)
        }
        .sheet(isPresented: $showRenameItemSheet) {
            NameInputSheet(
                title: "重命名文件",
                initialName: renameItemName,
                confirmLabel: "保存"
            ) { name in
                if let id = renameItemID {
                    mediaLibrary.renameItem(id: id, newTitle: name)
                }
            }
            .id(renameItemID)
        }
        .sheet(item: $moveAction) { action in
            MoveDestinationSheet(
                title: "移动到",
                options: folderOptions(for: action),
                initialSelection: initialMoveSelection(for: action)
            ) { destinationID in
                performMove(action: action, destinationID: destinationID)
            }
        }
        .alert("无法删除文件夹", isPresented: $showFolderDeleteBlockedAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("“\(folderDeleteBlockedName)”不为空，请先移除里面的文件或子文件夹。")
        }
    }

    private var libraryNodes: [LibraryNode] {
        buildNodes(parentID: nil)
    }

    private func buildNodes(parentID: UUID?) -> [LibraryNode] {
        let folders = mediaLibrary.folders
            .filter { $0.parentID == parentID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let items = mediaLibrary.items
            .filter { $0.parentFolderID == parentID }
            .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }

        var nodes: [LibraryNode] = []
        for folder in folders {
            let children = buildNodes(parentID: folder.id)
            nodes.append(LibraryNode.folder(folder, children: children))
        }
        for item in items {
            nodes.append(LibraryNode.item(item))
        }
        return nodes
    }

    @ViewBuilder
    private func libraryRow(for node: LibraryNode) -> some View {
        switch node.kind {
        case .folder(let folder):
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(folder.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .tag(SidebarSelection.folder(folder.id))
            .contextMenu {
                Button("在此新建文件夹") {
                    beginNewFolder(parentID: folder.id)
                }
                Button("重命名") {
                    beginRenameFolder(folder)
                }
                Button("移动到…") {
                    beginMoveFolder(folder)
                }
                Button("删除") {
                    deleteFolder(folder)
                }
            }
        case .item(let item):
            HStack {
                VStack(alignment: .leading) {
                    Text(displayName(for: item))
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                let targetIDs = targetItemIDs(for: item)
                Button("重命名") {
                    beginRenameItem(item)
                }
                Button("移动到…") {
                    beginMoveItems(ids: targetIDs)
                }
                Button("删除") {
                    deleteItems(ids: targetIDs)
                }
            }
        }
    }

    private func handleSelectionChange(_ newValue: Set<SidebarSelection>) {
        if let menuSelection = newValue.first(where: { $0.isMenu }) {
            if newValue != [menuSelection] {
                selectionSet = [menuSelection]
                return
            }
            selection = menuSelection
            appModel.clearSelection()
            return
        }

        let mediaIDs = newValue.compactMap { selection in
            if case .media(let id) = selection { return id }
            return nil
        }
        let folderIDs = newValue.compactMap { selection in
            if case .folder(let id) = selection { return id }
            return nil
        }

        if mediaIDs.isEmpty {
            if !folderIDs.isEmpty {
                selection = nil
                appModel.selectedMedia = nil
                return
            }
            selection = nil
            appModel.selectedMedia = nil
            return
        }

        if mediaIDs.count == 1, let id = mediaIDs.first,
           let item = mediaLibrary.items.first(where: { $0.id == id }) {
            selection = .media(id)
            appModel.selectedMedia = item
            appModel.clearSelection()
            return
        }

        if case .media(let currentID) = selection, mediaIDs.contains(currentID) {
            return
        }

        if let firstID = mediaIDs.first,
           let item = mediaLibrary.items.first(where: { $0.id == firstID }) {
            selection = .media(firstID)
            appModel.selectedMedia = item
            appModel.clearSelection()
        }
    }

    private func reconcileSelectionAfterDataChange() {
        let validMediaIDs = Set(mediaLibrary.items.map { $0.id })
        let validFolderIDs = Set(mediaLibrary.folders.map { $0.id })
        selectionSet = selectionSet.filter { selection in
            switch selection {
            case .media(let id):
                return validMediaIDs.contains(id)
            case .folder(let id):
                return validFolderIDs.contains(id)
            case .settings, .vocabulary, .onlineResources:
                return true
            }
        }

        if case .media(let id) = selection, !validMediaIDs.contains(id) {
            selection = nil
            appModel.selectedMedia = nil
        }

        if selection == nil, let first = mediaLibrary.items.first {
            selectMedia(first)
        }
    }

    private func selectMedia(_ item: MediaItem) {
        selection = .media(item.id)
        selectionSet = Set([selection].compactMap { $0 })
        appModel.selectedMedia = item
        appModel.clearSelection()
    }

    private func targetItemIDs(for item: MediaItem) -> [UUID] {
        let selectedIDs = selectionSet.compactMap { selection in
            if case .media(let id) = selection { return id }
            return nil
        }
        if selectedIDs.contains(item.id) {
            return selectedIDs
        }
        return [item.id]
    }

    private func beginNewFolder(parentID: UUID?) {
        newFolderParentID = parentID
        newFolderName = ""
        showNewFolderSheet = true
    }

    private func beginRenameFolder(_ folder: MediaFolder) {
        renameFolderID = folder.id
        renameFolderName = folder.name
        showRenameFolderSheet = true
    }

    private func beginRenameItem(_ item: MediaItem) {
        renameItemID = item.id
        renameItemName = displayName(for: item)
        showRenameItemSheet = true
    }

    private func beginMoveItems(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        moveAction = MoveAction(kind: .items(ids))
    }

    private func beginMoveFolder(_ folder: MediaFolder) {
        moveAction = MoveAction(kind: .folder(folder.id))
    }

    private func deleteItems(ids: [UUID]) {
        mediaLibrary.deleteItems(ids: ids)
        selectionSet = selectionSet.filter { selection in
            if case .media(let id) = selection {
                return !ids.contains(id)
            }
            return true
        }
        if case .media(let id) = selection, ids.contains(id) {
            selection = nil
            appModel.selectedMedia = nil
        }
    }

    private func deleteFolder(_ folder: MediaFolder) {
        if mediaLibrary.deleteFolder(id: folder.id) {
            return
        }
        folderDeleteBlockedName = folder.name
        showFolderDeleteBlockedAlert = true
    }

    private func performMove(action: MoveAction, destinationID: UUID?) {
        switch action.kind {
        case .items(let ids):
            mediaLibrary.moveItems(ids: ids, to: destinationID)
        case .folder(let id):
            _ = mediaLibrary.moveFolder(id: id, to: destinationID)
        }
    }

    private func initialMoveSelection(for action: MoveAction) -> UUID? {
        switch action.kind {
        case .items(let ids):
            let parentIDs = Set(mediaLibrary.items.compactMap { item in
                ids.contains(item.id) ? item.parentFolderID : nil
            })
            if parentIDs.count == 1 {
                return parentIDs.first ?? nil
            }
            return nil
        case .folder(let id):
            return mediaLibrary.folders.first(where: { $0.id == id })?.parentID
        }
    }

    private func folderOptions(for action: MoveAction) -> [FolderOption] {
        let availableFolders: [MediaFolder]
        switch action.kind {
        case .items:
            availableFolders = mediaLibrary.folders
        case .folder(let id):
            availableFolders = mediaLibrary.availableFolderTargets(excluding: id)
        }

        func build(parentID: UUID?, depth: Int) -> [FolderOption] {
            let children = availableFolders
                .filter { $0.parentID == parentID }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            var result: [FolderOption] = []
            for folder in children {
                result.append(FolderOption(id: folder.id, name: folder.name, depth: depth))
                result.append(contentsOf: build(parentID: folder.id, depth: depth + 1))
            }
            return result
        }

        return build(parentID: nil, depth: 0)
    }

    private func baseName(for item: MediaItem) -> String {
        let base = item.title.isEmpty ? item.url.deletingPathExtension().lastPathComponent : item.title
        let ext = item.url.pathExtension
        if ext.isEmpty { return base }
        let lowerBase = base.lowercased()
        let lowerExt = ".\(ext.lowercased())"
        if lowerBase.hasSuffix(lowerExt) {
            return String(base.dropLast(lowerExt.count))
        }
        return base
    }

    private func displayName(for item: MediaItem) -> String {
        let base = baseName(for: item)
        let ext = item.url.pathExtension
        if ext.isEmpty { return base }
        return "\(base).\(ext)"
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds > 0 else { return "--:--" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

private struct LibraryNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder(MediaFolder)
        case item(MediaItem)
    }

    let id: UUID
    let kind: Kind
    var children: [LibraryNode]?

    static func folder(_ folder: MediaFolder, children: [LibraryNode]) -> LibraryNode {
        LibraryNode(id: folder.id, kind: .folder(folder), children: children.isEmpty ? nil : children)
    }

    static func item(_ item: MediaItem) -> LibraryNode {
        LibraryNode(id: item.id, kind: .item(item), children: nil)
    }
}

private struct MoveAction: Identifiable {
    enum Kind {
        case items([UUID])
        case folder(UUID)
    }

    let id = UUID()
    let kind: Kind
}

private struct FolderOption: Identifiable {
    let id: UUID
    let name: String
    let depth: Int
}

private struct MoveDestinationSheet: View {
    let title: String
    let options: [FolderOption]
    let initialSelection: UUID?
    let onMove: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?

    init(title: String, options: [FolderOption], initialSelection: UUID?, onMove: @escaping (UUID?) -> Void) {
        self.title = title
        self.options = options
        self.initialSelection = initialSelection
        self.onMove = onMove
        _selectedID = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            List {
                Button {
                    selectedID = nil
                } label: {
                    destinationRow(title: "根目录", depth: 0, selected: selectedID == nil)
                }
                .buttonStyle(.plain)

                ForEach(options) { option in
                    Button {
                        selectedID = option.id
                    } label: {
                        destinationRow(title: option.name, depth: option.depth, selected: selectedID == option.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("移动") {
                    onMove(selectedID)
                    dismiss()
                }
            }
        }
        .padding(16)
        .frame(width: 420, height: 360)
    }

    private func destinationRow(title: String, depth: Int, selected: Bool) -> some View {
        HStack(spacing: 8) {
            if depth > 0 {
                Spacer()
                    .frame(width: CGFloat(depth) * 12)
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NameInputSheet: View {
    let title: String
    let initialName: String
    let confirmLabel: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(title: String, initialName: String, confirmLabel: String, onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.initialName = initialName
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button(confirmLabel) {
                    onConfirm(name)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

private extension SidebarSelection {
    var isMenu: Bool {
        switch self {
        case .settings, .vocabulary, .onlineResources:
            return true
        case .folder:
            return false
        case .media:
            return false
        }
    }
}
