import Foundation
import AppKit

@MainActor
final class StorageUsageModel: ObservableObject {
    struct StorageEntry: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        let isDirectory: Bool
        let bytes: Int64
    }

    @Published var mediaBytes: Int64 = 0
    @Published var transcriptBytes: Int64 = 0
    @Published var importStagingBytes: Int64 = 0
    @Published var libraryBytes: Int64 = 0
    @Published var vocabularyBytes: Int64 = 0
    @Published var translationCacheBytes: Int64 = 0
    @Published var cookiesBytes: Int64 = 0
    @Published var appSupportEntries: [StorageEntry] = []
    @Published var lastUpdated: Date?

    func refresh() {
        Task.detached {
            let media = FileSize.folderSize(AppPaths.mediaDir)
            let transcripts = FileSize.folderSize(AppPaths.transcriptsDir)
            let importStaging = FileSize.folderSize(AppPaths.importStagingDir)
            let library = FileSize.fileSize(AppPaths.libraryFile)
            let vocabulary = FileSize.fileSize(AppPaths.vocabularyFile)
            let translationCache = FileSize.fileSize(AppPaths.translationCacheFile)
            let cookies = FileSize.fileSize(AppPaths.ytDlpCookiesFile)
            let entries = Self.loadAppSupportEntries()
            await MainActor.run {
                self.mediaBytes = media
                self.transcriptBytes = transcripts
                self.importStagingBytes = importStaging
                self.libraryBytes = library
                self.vocabularyBytes = vocabulary
                self.translationCacheBytes = translationCache
                self.cookiesBytes = cookies
                self.appSupportEntries = entries
                self.lastUpdated = Date()
            }
        }
    }

    func openMediaFolder() {
        NSWorkspace.shared.open(AppPaths.mediaDir)
    }

    func openTranscriptsFolder() {
        NSWorkspace.shared.open(AppPaths.transcriptsDir)
    }

    func openImportStagingFolder() {
        NSWorkspace.shared.open(AppPaths.importStagingDir)
    }

    func openLibraryFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.libraryFile])
    }

    func openVocabularyFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.vocabularyFile])
    }

    func openTranslationCacheFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.translationCacheFile])
    }

    func openCookiesFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.ytDlpCookiesFile])
    }

    func openEntry(_ entry: StorageEntry) {
        if entry.isDirectory {
            NSWorkspace.shared.open(entry.url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        }
    }

    func openAppSupportFolder() {
        NSWorkspace.shared.open(AppPaths.appSupport)
    }

    func clearCookiesFile() {
        if FileManager.default.fileExists(atPath: AppPaths.ytDlpCookiesFile.path) {
            try? FileManager.default.removeItem(at: AppPaths.ytDlpCookiesFile)
        }
        refresh()
    }

    nonisolated private static func loadAppSupportEntries() -> [StorageEntry] {
        let base = AppPaths.appSupport
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let entries: [StorageEntry] = items.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let isDir = values?.isDirectory ?? false
            let isFile = values?.isRegularFile ?? false
            guard isDir || isFile else { return nil }
            let size: Int64 = isDir ? FileSize.folderSize(url) : FileSize.fileSize(url)
            return StorageEntry(
                name: url.lastPathComponent,
                url: url,
                isDirectory: isDir,
                bytes: size
            )
        }

        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum FileSize {
    static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

extension Int64 {
    var byteCountString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
