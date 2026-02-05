import Foundation

struct MediaItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let url: URL
    var title: String
    var duration: Double
    let addedAt: Date
    let fingerprint: String

    init(id: UUID = UUID(), url: URL, title: String, duration: Double, addedAt: Date = Date(), fingerprint: String) {
        self.id = id
        self.url = url
        self.title = title
        self.duration = duration
        self.addedAt = addedAt
        self.fingerprint = fingerprint
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
    let definitionEn: String
    let translationZh: String
    let addedAt: Date
    let sourceTitle: String

    init(id: UUID = UUID(), word: String, definitionEn: String, translationZh: String, addedAt: Date = Date(), sourceTitle: String) {
        self.id = id
        self.word = word
        self.definitionEn = definitionEn
        self.translationZh = translationZh
        self.addedAt = addedAt
        self.sourceTitle = sourceTitle
    }
}

struct TranslationResult {
    let definitionEn: String
    let translationZh: String
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
