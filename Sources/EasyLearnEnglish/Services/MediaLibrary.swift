import Foundation
import AVFoundation

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
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

    init() {
        load()
    }

    func importMedia(urls: [URL]) async -> ImportResult {
        guard !urls.isEmpty else {
            return ImportResult(imported: [], skipped: 0, failed: 0, failures: [])
        }

        isImporting = true
        let result = await importMediaAsync(urls: urls)
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

    private func load() {
        let url = AppPaths.libraryFile
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([MediaItem].self, from: data) {
            items = decoded
        }
    }

    private func save() {
        let url = AppPaths.libraryFile
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: url)
        }
    }

    private func importMediaAsync(urls: [URL]) async -> ImportResult {
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
            let item = MediaItem(url: localURL, title: title, duration: duration, fingerprint: fingerprint)
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
