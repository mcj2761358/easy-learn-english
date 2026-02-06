import Foundation

enum TranscriptionError: Error, LocalizedError {
    case authorizationDenied
    case siriDictationDisabled
    case speechNotAvailable
    case noSpeechDetected
    case unsupported
    case onlineFallbackRequired(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "语音识别权限未授权。请到「系统设置 → 隐私与安全 → 语音识别」中允许 EasyLearnEnglish。"
        case .siriDictationDisabled:
            return "Siri 与听写已关闭。请在系统设置中启用 Siri 和听写功能。"
        case .speechNotAvailable:
            return "系统语音识别不可用。请检查系统语言、网络或稍后重试。"
        case .noSpeechDetected:
            return "未检测到语音。请确认音频有人声，或切换为联网识别后重试。"
        case .unsupported:
            return "不支持的媒体格式或系统语音识别不可用。"
        case .onlineFallbackRequired(let reason):
            return reason
        case .failed(let message):
            return message
        }
    }
}

protocol TranscriptionProvider {
    var name: String { get }
    func transcribe(
        mediaURL: URL,
        language: String,
        progress: @Sendable @escaping (TranscriptionProgress) -> Void
    ) async throws -> [TranscriptSegment]
}

extension TranscriptionProvider {
    func transcribe(mediaURL: URL, language: String) async throws -> [TranscriptSegment] {
        try await transcribe(mediaURL: mediaURL, language: language, progress: { _ in })
    }
}

struct TranscriptionService {
    @MainActor
    func provider(for kind: TranscriptionProviderKind, settings: SettingsStore, allowOnlineFallback: Bool = true) -> TranscriptionProvider {
        switch kind {
        case .appleSpeech:
            return AppleSpeechTranscriber(allowOnlineFallback: allowOnlineFallback)
        case .openAI:
            return ExternalProvider(name: kind.displayName, apiKey: settings.openaiApiKey)
        case .gemini:
            return ExternalProvider(name: kind.displayName, apiKey: settings.geminiApiKey)
        case .glm:
            return ExternalProvider(name: kind.displayName, apiKey: settings.glmApiKey)
        case .kimi:
            return ExternalProvider(name: kind.displayName, apiKey: settings.kimiApiKey)
        case .minmax:
            return ExternalProvider(name: kind.displayName, apiKey: settings.minmaxApiKey)
        }
    }
}

struct ExternalProvider: TranscriptionProvider {
    let name: String
    let apiKey: String

    func transcribe(
        mediaURL: URL,
        language: String,
        progress: @Sendable @escaping (TranscriptionProgress) -> Void
    ) async throws -> [TranscriptSegment] {
        progress(.init(stage: .preparing, detail: "准备连接 \(name)"))
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            throw TranscriptionError.failed("未配置 \(name) API Key。请在设置中填写后重试。")
        }
        throw TranscriptionError.failed("\(name) 联网识别未接入或 API 不可用。请检查 API Key 或网络。")
    }
}
