import Foundation

enum AppPaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("EasyLearnEnglish", isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    static var transcriptsDir: URL {
        let dir = appSupport.appendingPathComponent("transcripts", isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    static var mediaDir: URL {
        let dir = appSupport.appendingPathComponent("media", isDirectory: true)
        ensureDirectory(dir)
        return dir
    }

    static var libraryFile: URL {
        appSupport.appendingPathComponent("library.json")
    }

    static var vocabularyFile: URL {
        appSupport.appendingPathComponent("vocabulary.json")
    }

    static var translationCacheFile: URL {
        appSupport.appendingPathComponent("translation-cache.json")
    }

    static func transcriptFile(fingerprint: String) -> URL {
        transcriptsDir.appendingPathComponent("\(fingerprint).json")
    }

    static func mediaFile(fingerprint: String, ext: String) -> URL {
        mediaDir.appendingPathComponent("\(fingerprint).\(ext)")
    }

    private static func ensureDirectory(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
