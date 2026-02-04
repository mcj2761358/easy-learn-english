import Foundation

@MainActor
final class VocabularyStore: ObservableObject {
    @Published private(set) var entries: [VocabularyEntry] = []

    init() {
        load()
    }

    func isSaved(word: String) -> Bool {
        entries.contains { $0.word.caseInsensitiveCompare(word) == .orderedSame }
    }

    func save(word: String, definitionEn: String, translationZh: String, sourceTitle: String) {
        if isSaved(word: word) { return }
        let entry = VocabularyEntry(word: word, definitionEn: definitionEn, translationZh: translationZh, sourceTitle: sourceTitle)
        entries.insert(entry, at: 0)
        persist()
    }

    func remove(word: String) {
        entries.removeAll { $0.word.caseInsensitiveCompare(word) == .orderedSame }
        persist()
    }

    private func load() {
        let url = AppPaths.vocabularyFile
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([VocabularyEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        let url = AppPaths.vocabularyFile
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url)
        }
    }
}
