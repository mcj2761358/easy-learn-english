import Foundation
import AppKit

@MainActor
final class StorageUsageModel: ObservableObject {
    @Published var mediaBytes: Int64 = 0
    @Published var transcriptBytes: Int64 = 0
    @Published var importStagingBytes: Int64 = 0
    @Published var libraryBytes: Int64 = 0
    @Published var vocabularyBytes: Int64 = 0
    @Published var translationCacheBytes: Int64 = 0
    @Published var cookiesBytes: Int64 = 0
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
            await MainActor.run {
                self.mediaBytes = media
                self.transcriptBytes = transcripts
                self.importStagingBytes = importStaging
                self.libraryBytes = library
                self.vocabularyBytes = vocabulary
                self.translationCacheBytes = translationCache
                self.cookiesBytes = cookies
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

    func clearCookiesFile() {
        if FileManager.default.fileExists(atPath: AppPaths.ytDlpCookiesFile.path) {
            try? FileManager.default.removeItem(at: AppPaths.ytDlpCookiesFile)
        }
        refresh()
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
