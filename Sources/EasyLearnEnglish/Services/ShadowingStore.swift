import Foundation

struct ShadowingStore {
    func load(fingerprint: String) -> [ShadowingSegment] {
        let url = AppPaths.shadowingFile(fingerprint: fingerprint)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([ShadowingSegment].self, from: data)) ?? []
    }

    func save(fingerprint: String, segments: [ShadowingSegment]) {
        let url = AppPaths.shadowingFile(fingerprint: fingerprint)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(segments) {
            try? data.write(to: url)
        }
    }

    func delete(fingerprint: String) {
        let url = AppPaths.shadowingFile(fingerprint: fingerprint)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
