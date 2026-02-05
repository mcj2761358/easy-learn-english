import Foundation
import AppKit

@MainActor
final class StorageUsageModel: ObservableObject {
    @Published var mediaBytes: Int64 = 0
    @Published var transcriptBytes: Int64 = 0
    @Published var vocabularyBytes: Int64 = 0
    @Published var translationCacheBytes: Int64 = 0
    @Published var lastUpdated: Date?

    func refresh() {
        Task.detached {
            let media = FileSize.folderSize(AppPaths.mediaDir)
            let transcripts = FileSize.folderSize(AppPaths.transcriptsDir)
            let vocabulary = FileSize.fileSize(AppPaths.vocabularyFile)
            let translationCache = FileSize.fileSize(AppPaths.translationCacheFile)
            await MainActor.run {
                self.mediaBytes = media
                self.transcriptBytes = transcripts
                self.vocabularyBytes = vocabulary
                self.translationCacheBytes = translationCache
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

    func openVocabularyFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.vocabularyFile])
    }

    func openTranslationCacheFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.translationCacheFile])
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
