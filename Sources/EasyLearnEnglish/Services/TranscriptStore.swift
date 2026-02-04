import Foundation

struct TranscriptStore {
    func isUsable(fingerprint: String) -> Bool {
        guard let transcript = load(fingerprint: fingerprint) else { return false }
        return !transcript.segments.isEmpty
    }

    func exists(fingerprint: String) -> Bool {
        let url = AppPaths.transcriptFile(fingerprint: fingerprint)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func load(fingerprint: String) -> Transcript? {
        let url = AppPaths.transcriptFile(fingerprint: fingerprint)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(Transcript.self, from: data)
    }

    func save(_ transcript: Transcript) {
        let url = AppPaths.transcriptFile(fingerprint: transcript.mediaFingerprint)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(transcript) {
            try? data.write(to: url)
        }
    }

    func delete(fingerprint: String) {
        let url = AppPaths.transcriptFile(fingerprint: fingerprint)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
