import Foundation
import AppKit

@MainActor
final class StorageUsageModel: ObservableObject {
    @Published var mediaBytes: Int64 = 0
    @Published var transcriptBytes: Int64 = 0
    @Published var lastUpdated: Date?

    func refresh() {
        Task.detached {
            let media = FileSize.folderSize(AppPaths.mediaDir)
            let transcripts = FileSize.folderSize(AppPaths.transcriptsDir)
            await MainActor.run {
                self.mediaBytes = media
                self.transcriptBytes = transcripts
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
}

extension Int64 {
    var byteCountString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
