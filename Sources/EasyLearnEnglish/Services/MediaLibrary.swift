import Foundation
import AVFoundation

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var folders: [MediaFolder] = []
    @Published private(set) var isImporting: Bool = false
    @Published private(set) var lastImportMessage: String = ""
    @Published private(set) var lastImportDetail: String = ""
    @Published private(set) var lastImportAt: Date?

    struct ImportResult {
        let imported: [MediaItem]
        let skipped: Int
        let failed: Int
        let failures: [String]
    }

    static let supportedAudioExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "caf"]
    static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let supportedExtensions: Set<String> = supportedAudioExtensions.union(supportedVideoExtensions)

    private struct LibrarySnapshot: Codable {
        var items: [MediaItem]
        var folders: [MediaFolder]
    }

    init() {
        load()
    }

    func importMedia(urls: [URL], targetFolderID: UUID? = nil) async -> ImportResult {
        guard !urls.isEmpty else {
            return ImportResult(imported: [], skipped: 0, failed: 0, failures: [])
        }

        isImporting = true
        let result = await importMediaAsync(urls: urls, targetFolderID: targetFolderID)
        isImporting = false

        var message = result.imported.isEmpty ? "没有导入新媒体" : "已导入 \(result.imported.count) 个"
        if result.skipped > 0 {
            message += "，跳过 \(result.skipped) 个"
        }
        if result.failed > 0 {
            message += "，失败 \(result.failed) 个"
        }
        showImportMessage(message, detail: result.failures.first ?? "")
        return result
    }

    func remove(item: MediaItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            removeCachedFiles(for: item)
            save()
        }
    }

    func deleteItems(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var removed: [MediaItem] = []
        items.removeAll { item in
            if ids.contains(item.id) {
                removed.append(item)
                return true
            }
            return false
        }
        for item in removed {
            removeCachedFiles(for: item)
        }
        if !removed.isEmpty {
            save()
        }
    }

    func renameItem(id: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].title = trimmed
            save()
        }
    }

    func moveItems(ids: [UUID], to folderID: UUID?) {
        guard !ids.isEmpty else { return }
        var changed = false
        for index in items.indices {
            if ids.contains(items[index].id) {
                if items[index].parentFolderID != folderID {
                    items[index].parentFolderID = folderID
                    changed = true
                }
            }
        }
        if changed {
            save()
        }
    }

    func createFolder(name: String, parentID: UUID?) -> MediaFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = MediaFolder(name: trimmed, parentID: parentID)
        folders.append(folder)
        save()
        return folder
    }

    func ensureFolder(name: String, parentID: UUID?) -> MediaFolder {
        if let existing = folders.first(where: { $0.name == name && $0.parentID == parentID }) {
            return existing
        }
        let folder = MediaFolder(name: name, parentID: parentID)
        folders.append(folder)
        save()
        return folder
    }

    func renameFolder(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].name = trimmed
            save()
        }
    }

    func deleteFolder(id: UUID) -> Bool {
        guard isFolderEmpty(id: id) else { return false }
        folders.removeAll { $0.id == id }
        save()
        return true
    }

    func isFolderEmpty(id: UUID) -> Bool {
        let hasItems = items.contains { $0.parentFolderID == id }
        if hasItems { return false }
        let hasFolders = folders.contains { $0.parentID == id }
        return !hasFolders
    }

    func moveFolder(id: UUID, to parentID: UUID?) -> Bool {
        if parentID == id { return false }
        if let parentID, isDescendant(folderID: parentID, of: id) {
            return false
        }
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].parentID = parentID
            save()
            return true
        }
        return false
    }

    func folderPathExists(_ id: UUID) -> Bool {
        folders.contains { $0.id == id }
    }

    func availableFolderTargets(excluding folderID: UUID?) -> [MediaFolder] {
        guard let folderID else { return folders }
        return folders.filter { candidate in
            candidate.id != folderID && !isDescendant(folderID: candidate.id, of: folderID)
        }
    }

    private func isDescendant(folderID: UUID, of ancestorID: UUID) -> Bool {
        var currentID = folders.first(where: { $0.id == folderID })?.parentID
        while let id = currentID {
            if id == ancestorID {
                return true
            }
            currentID = folders.first(where: { $0.id == id })?.parentID
        }
        return false
    }

    private func load() {
        let url = AppPaths.libraryFile
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        if let snapshot = try? decoder.decode(LibrarySnapshot.self, from: data) {
            items = snapshot.items
            folders = snapshot.folders
            return
        }
        if let decoded = try? decoder.decode([MediaItem].self, from: data) {
            items = decoded
            folders = []
            save()
        }
    }

    private func save() {
        let url = AppPaths.libraryFile
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let snapshot = LibrarySnapshot(items: items, folders: folders)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url)
        }
    }

    private func importMediaAsync(urls: [URL], targetFolderID: UUID?) async -> ImportResult {
        var changed = false
        var imported: [MediaItem] = []
        var skipped = 0
        var failed = 0
        var failures: [String] = []
        for url in urls {
            guard url.isFileURL else {
                skipped += 1
                continue
            }
            let fingerprint = Fingerprint.forFile(url: url)
            if items.contains(where: { $0.fingerprint == fingerprint }) {
                skipped += 1
                continue
            }

            if let reason = await validateMedia(url: url) {
                failed += 1
                let title = url.deletingPathExtension().lastPathComponent
                failures.append("\(title)：\(reason)")
                continue
            }

            let title = url.deletingPathExtension().lastPathComponent
            guard let localURL = copyToAppSupportIfNeeded(url: url, fingerprint: fingerprint) else {
                failed += 1
                failures.append("\(title)：复制文件失败")
                continue
            }
            let duration = await mediaDuration(url: localURL)
            let item = MediaItem(url: localURL, title: title, duration: duration, fingerprint: fingerprint, parentFolderID: targetFolderID)
            items.append(item)
            imported.append(item)
            changed = true
        }

        if changed {
            save()
        }
        return ImportResult(imported: imported, skipped: skipped, failed: failed, failures: failures)
    }

    private func mediaDuration(url: URL) async -> Double {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            if duration.isIndefinite || duration.seconds.isNaN {
                return 0
            }
            return duration.seconds
        } catch {
            return 0
        }
    }

    private func copyToAppSupportIfNeeded(url: URL, fingerprint: String) -> URL? {
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let dest = AppPaths.mediaFile(fingerprint: fingerprint, ext: ext)
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func removeCachedFiles(for item: MediaItem) {
        let transcriptURL = AppPaths.transcriptFile(fingerprint: item.fingerprint)
        if FileManager.default.fileExists(atPath: transcriptURL.path) {
            try? FileManager.default.removeItem(at: transcriptURL)
        }

        if item.url.path.hasPrefix(AppPaths.mediaDir.path) {
            if FileManager.default.fileExists(atPath: item.url.path) {
                try? FileManager.default.removeItem(at: item.url)
            }
        }
    }

    private func showImportMessage(_ message: String, detail: String) {
        lastImportMessage = message
        lastImportDetail = detail
        let timestamp = Date()
        lastImportAt = timestamp
        Task { [timestamp] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if lastImportAt == timestamp {
                lastImportMessage = ""
                lastImportDetail = ""
            }
        }
    }

    private func validateMedia(url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        if !Self.supportedExtensions.contains(ext) {
            return "不支持的格式（.\(ext.isEmpty ? "未知" : ext)）"
        }

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if Self.supportedAudioExtensions.contains(ext) {
            do {
                _ = try AVAudioFile(forReading: url)
                return nil
            } catch {
                return "音频不可读取：\(error.localizedDescription)"
            }
        }

        let asset = AVAsset(url: url)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        let isExportable = (try? await asset.load(.isExportable)) ?? false
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        if !isPlayable && !isExportable {
            return "系统不支持该视频格式"
        }
        if audioTracks.isEmpty {
            return "视频没有音轨"
        }
        return nil
    }
}
