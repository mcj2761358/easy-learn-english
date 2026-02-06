import Foundation

struct MediaItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var duration: Double
    let addedAt: Date
    let fingerprint: String
    var parentFolderID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case duration
        case addedAt
        case fingerprint
        case parentFolderID
    }

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        duration: Double,
        addedAt: Date = Date(),
        fingerprint: String,
        parentFolderID: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.duration = duration
        self.addedAt = addedAt
        self.fingerprint = fingerprint
        self.parentFolderID = parentFolderID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        duration = try container.decode(Double.self, forKey: .duration)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(duration, forKey: .duration)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(parentFolderID, forKey: .parentFolderID)
    }
}

struct MediaFolder: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var parentID: UUID?
    let createdAt: Date

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
    }
}

struct Transcript: Codable {
    let mediaFingerprint: String
    let mediaTitle: String?
    let mediaDuration: Double?
    let mediaSignature: String?
    let provider: String
    let language: String
    let segments: [TranscriptSegment]

    init(
        mediaFingerprint: String,
        mediaTitle: String? = nil,
        mediaDuration: Double? = nil,
        mediaSignature: String? = nil,
        provider: String,
        language: String,
        segments: [TranscriptSegment]
    ) {
        self.mediaFingerprint = mediaFingerprint
        self.mediaTitle = mediaTitle
        self.mediaDuration = mediaDuration
        self.mediaSignature = mediaSignature
        self.provider = provider
        self.language = language
        self.segments = segments
    }
}

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    let start: Double
    let end: Double
    let text: String
    let tokens: [String]

    init(id: UUID = UUID(), start: Double, end: Double, text: String, tokens: [String]) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.tokens = tokens
    }
}

struct VocabularyEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let word: String
    var definitionEn: String
    var translationZh: String
    let addedAt: Date
    let sourceTitle: String
    var familiarity: VocabularyFamiliarity

    init(
        id: UUID = UUID(),
        word: String,
        definitionEn: String,
        translationZh: String,
        addedAt: Date = Date(),
        sourceTitle: String,
        familiarity: VocabularyFamiliarity = .unfamiliar
    ) {
        self.id = id
        self.word = word
        self.definitionEn = definitionEn
        self.translationZh = translationZh
        self.addedAt = addedAt
        self.sourceTitle = sourceTitle
        self.familiarity = familiarity
    }

    enum CodingKeys: String, CodingKey {
        case id
        case word
        case definitionEn
        case translationZh
        case addedAt
        case sourceTitle
        case familiarity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        definitionEn = try container.decode(String.self, forKey: .definitionEn)
        translationZh = try container.decode(String.self, forKey: .translationZh)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        sourceTitle = try container.decode(String.self, forKey: .sourceTitle)
        familiarity = (try? container.decode(VocabularyFamiliarity.self, forKey: .familiarity)) ?? .unfamiliar
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(definitionEn, forKey: .definitionEn)
        try container.encode(translationZh, forKey: .translationZh)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(sourceTitle, forKey: .sourceTitle)
        try container.encode(familiarity, forKey: .familiarity)
    }
}

enum VocabularyFamiliarity: String, CaseIterable, Identifiable, Codable {
    case unfamiliar
    case vague
    case known
    case familiar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unfamiliar: return "陌生"
        case .vague: return "模糊"
        case .known: return "认识"
        case .familiar: return "熟悉"
        }
    }
}

struct DefinitionProviderResult: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let text: String
    let isError: Bool
}

struct TranslationSnapshot: Codable, Hashable {
    let query: String
    let fetchedAt: Date
    let english: [DefinitionProviderResult]
    let chinese: [DefinitionProviderResult]
}

extension TranslationSnapshot {
    var primaryEnglish: String {
        english.first { !$0.isError && !$0.text.isEmpty }?.text ?? ""
    }

    var primaryChinese: String {
        chinese.first { !$0.isError && !$0.text.isEmpty }?.text ?? ""
    }
}

enum TranscriptionProviderKind: String, CaseIterable, Identifiable, Codable {
    case appleSpeech = "Apple Speech（本地）"
    case openAI = "OpenAI Whisper"
    case gemini = "Gemini"
    case glm = "GLM"
    case kimi = "Kimi"
    case minmax = "MinMax"

    var id: String { rawValue }
    var displayName: String { rawValue }
}
