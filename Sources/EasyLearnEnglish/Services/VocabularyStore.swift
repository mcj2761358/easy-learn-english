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

    func entry(id: UUID) -> VocabularyEntry? {
        entries.first { $0.id == id }
    }

    func save(
        word: String,
        definitionEn: String,
        translationZh: String,
        sourceTitle: String,
        familiarity: VocabularyFamiliarity = .unfamiliar
    ) {
        if isSaved(word: word) { return }
        let entry = VocabularyEntry(
            word: word,
            definitionEn: definitionEn,
            translationZh: translationZh,
            sourceTitle: sourceTitle,
            familiarity: familiarity
        )
        entries.insert(entry, at: 0)
        persist()
    }

    func remove(word: String) {
        entries.removeAll { $0.word.caseInsensitiveCompare(word) == .orderedSame }
        persist()
    }

    func updateFamiliarity(id: UUID, familiarity: VocabularyFamiliarity) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].familiarity = familiarity
        persist()
    }

    var report: VocabularyReport {
        VocabularyReport(entries: entries)
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

struct VocabularyReport {
    let total: Int
    let addedLast7Days: Int
    let addedLast30Days: Int
    let familiarityCounts: [VocabularyFamiliarity: Int]
    let topSources: [(String, Int)]

    init(entries: [VocabularyEntry], now: Date = Date()) {
        total = entries.count
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        addedLast7Days = entries.filter { $0.addedAt >= sevenDaysAgo }.count
        addedLast30Days = entries.filter { $0.addedAt >= thirtyDaysAgo }.count

        var counts: [VocabularyFamiliarity: Int] = [:]
        for familiarity in VocabularyFamiliarity.allCases {
            counts[familiarity] = 0
        }
        for entry in entries {
            counts[entry.familiarity, default: 0] += 1
        }
        familiarityCounts = counts

        var sourceCounts: [String: Int] = [:]
        for entry in entries {
            guard !entry.sourceTitle.isEmpty else { continue }
            sourceCounts[entry.sourceTitle, default: 0] += 1
        }
        topSources = sourceCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { ($0.key, $0.value) }
    }
}
