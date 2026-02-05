import Foundation

final class TranslationCacheStore {
    private var cache: [String: TranslationSnapshot] = [:]
    private let url: URL = AppPaths.translationCacheFile

    init() {
        load()
    }

    func snapshot(for key: String) -> TranslationSnapshot? {
        cache[key]
    }

    func save(_ snapshot: TranslationSnapshot, for key: String) {
        cache[key] = snapshot
        persist()
    }

    func remove(key: String) {
        cache.removeValue(forKey: key)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([String: TranslationSnapshot].self, from: data) {
            cache = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cache) {
            try? data.write(to: url)
        }
    }
}
