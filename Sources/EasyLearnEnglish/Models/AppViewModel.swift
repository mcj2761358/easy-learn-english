import Foundation
import AVFoundation
import SwiftUI

struct TokenRef: Equatable {
    let segmentIndex: Int
    let tokenIndex: Int
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedMedia: MediaItem? {
        didSet { handleSelectionChange() }
    }
    @Published var transcript: Transcript? {
        didSet {
            if let transcript, !transcript.segments.isEmpty {
                transcriptionError = nil
            }
        }
    }
    @Published var isTranscribing: Bool = false
    @Published var transcriptionError: TranscriptionErrorInfo?
    @Published var transcriptionProgress: TranscriptionProgress?
    @Published var diagnosticsText: String?
    @Published var showDiagnostics: Bool = false
    @Published var currentSegmentIndex: Int = 0
    @Published var selectedTokens: [String] = []
    @Published var translation: TranslationResult?

    let mediaLibrary: MediaLibrary
    let vocabularyStore: VocabularyStore
    let settings: SettingsStore

    private let transcriptStore = TranscriptStore()
    private let transcriptionService = TranscriptionService()
    private let translationService = TranslationService()

    private var selectionStart: TokenRef?
    private var selectionEnd: TokenRef?
    private var currentTranscriptionID = UUID()
    private var pendingErrorTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var lastAuthorizationDenied = false
    private var transcriptOwnerID: UUID?

    let player = AVPlayer()
    private var timeObserverToken: Any?

    var activeTranscript: Transcript? {
        guard let media = selectedMedia else { return nil }
        if let transcript,
           transcriptOwnerID == media.id,
           isTranscriptCompatible(transcript, media: media) {
            return transcript
        }
        if let cached = transcriptStore.load(fingerprint: media.fingerprint),
           isTranscriptCompatible(cached, media: media) {
            transcript = cached
            transcriptOwnerID = media.id
            return cached
        }
        return nil
    }

    init(mediaLibrary: MediaLibrary, vocabularyStore: VocabularyStore, settings: SettingsStore) {
        self.mediaLibrary = mediaLibrary
        self.vocabularyStore = vocabularyStore
        self.settings = settings
    }

    func selectToken(segmentIndex: Int, tokenIndex: Int, extend: Bool) {
        guard let transcript = activeTranscript else { return }
        guard transcript.segments.indices.contains(segmentIndex) else { return }
        let segment = transcript.segments[segmentIndex]
        guard segment.tokens.indices.contains(tokenIndex) else { return }

        let ref = TokenRef(segmentIndex: segmentIndex, tokenIndex: tokenIndex)
        if extend, let start = selectionStart, start.segmentIndex == segmentIndex {
            selectionEnd = ref
        } else {
            selectionStart = ref
            selectionEnd = ref
        }
        updateSelectedTokens()
    }

    func isTokenSelected(segmentIndex: Int, tokenIndex: Int) -> Bool {
        guard let start = selectionStart, let end = selectionEnd else { return false }
        guard start.segmentIndex == end.segmentIndex else { return false }
        guard start.segmentIndex == segmentIndex else { return false }
        let low = min(start.tokenIndex, end.tokenIndex)
        let high = max(start.tokenIndex, end.tokenIndex)
        return tokenIndex >= low && tokenIndex <= high
    }

    func clearSelection() {
        selectionStart = nil
        selectionEnd = nil
        selectedTokens = []
        translation = nil
    }

    func saveSelectionToVocabulary() {
        guard let selectedText = selectedText, !selectedText.isEmpty else { return }
        let definition = translation?.definitionEn ?? ""
        let zh = translation?.translationZh ?? ""
        let sourceTitle = selectedMedia?.title ?? ""
        vocabularyStore.save(word: selectedText, definitionEn: definition, translationZh: zh, sourceTitle: sourceTitle)
    }

    func removeSelectionFromVocabulary() {
        guard let selectedText = selectedText, !selectedText.isEmpty else { return }
        vocabularyStore.remove(word: selectedText)
    }

    var selectedText: String? {
        guard !selectedTokens.isEmpty else { return nil }
        return selectedTokens.joined(separator: " ")
    }

    var isSelectionSaved: Bool {
        guard let selectedText else { return false }
        return vocabularyStore.isSaved(word: selectedText)
    }

    private func updateSelectedTokens() {
        guard let transcript = activeTranscript, let start = selectionStart, let end = selectionEnd else {
            selectedTokens = []
            translation = nil
            return
        }

        let segmentIndex = start.segmentIndex
        guard segmentIndex == end.segmentIndex else {
            selectedTokens = []
            translation = nil
            return
        }

        let segment = transcript.segments[segmentIndex]
        let low = min(start.tokenIndex, end.tokenIndex)
        let high = max(start.tokenIndex, end.tokenIndex)
        guard segment.tokens.indices.contains(low), segment.tokens.indices.contains(high) else { return }
        selectedTokens = Array(segment.tokens[low...high])
        if let text = selectedText {
            translation = translationService.translate(wordOrPhrase: text)
        }
    }

    private func handleSelectionChange() {
        clearSelection()
        cancelTranscriptionTasks()
        transcriptionError = nil
        transcript = nil
        transcriptOwnerID = nil
        currentSegmentIndex = 0
        isTranscribing = false
        transcriptionProgress = nil

        guard let media = selectedMedia else { return }
        if !FileManager.default.fileExists(atPath: media.url.path) {
            transcriptionError = TranscriptionErrorInfo(
                title: "媒体文件不可访问",
                message: "导入的媒体文件无法读取，请重新导入该文件。",
                actions: []
            )
            return
        }
        preparePlayer(with: media.url)

        if let cached = transcriptStore.load(fingerprint: media.fingerprint) {
            if cached.segments.isEmpty {
                transcriptStore.delete(fingerprint: media.fingerprint)
            } else if !isTranscriptCompatible(cached, media: media) {
                transcriptStore.delete(fingerprint: media.fingerprint)
            } else {
                transcript = cached
                transcriptOwnerID = media.id
                return
            }
        }

        startTranscription(for: media)
    }

    private func preparePlayer(with url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        installTimeObserver()
    }

    private func installTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateCurrentSegment(currentTime: time.seconds)
            }
        }
    }

    private func updateCurrentSegment(currentTime: Double) {
        guard let transcript = activeTranscript else { return }
        guard !transcript.segments.isEmpty else { return }
        let idx = transcript.segments.firstIndex { currentTime >= $0.start && currentTime <= $0.end }
        if let idx {
            currentSegmentIndex = idx
        }
    }

    private func startTranscription(for media: MediaItem) {
        let runID = UUID()
        currentTranscriptionID = runID
        transcriptionTask?.cancel()
        retryTask?.cancel()
        transcriptionTask = Task { [weak self] in
            await self?.transcribe(media: media, runID: runID, isRetry: false)
        }
    }

    private func transcribe(media: MediaItem, runID: UUID, isRetry: Bool) async {
        guard currentTranscriptionID == runID else { return }
        if Task.isCancelled { return }

        isTranscribing = true
        lastAuthorizationDenied = false
        transcriptionError = nil
        diagnosticsText = nil
        pendingErrorTask?.cancel()
        transcriptionProgress = TranscriptionProgress(stage: .preparing, detail: isRetry ? "准备重试转写" : nil)

        let progressHandler: @Sendable (TranscriptionProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self else { return }
                guard self.currentTranscriptionID == runID else { return }
                self.transcriptionProgress = progress
            }
        }

        let provider = transcriptionService.provider(for: settings.provider, settings: settings)
        do {
            let segments = try await provider.transcribe(
                mediaURL: media.url,
                language: "en-US",
                progress: progressHandler
            )
            guard !segments.isEmpty else {
                throw TranscriptionError.failed("转写完成但没有识别到文本。请检查音频是否有人声，或更换转写提供商。")
            }
            if runID != currentTranscriptionID { return }
            progressHandler(.init(stage: .parsingSegments, detail: "解析字幕结构"))
            let transcript = Transcript(
                mediaFingerprint: media.fingerprint,
                mediaTitle: media.title,
                mediaDuration: media.duration,
                mediaSignature: MediaSignature.forFile(url: media.url),
                provider: provider.name,
                language: "en-US",
                segments: segments
            )
            if !isTranscriptCompatible(transcript, media: media) {
                throw TranscriptionError.failed("识别结果与媒体时长不匹配，将自动重试。")
            }
            progressHandler(.init(stage: .savingTranscript, detail: "保存字幕到本地"))
            transcriptStore.save(transcript)
            self.transcript = transcript
            self.transcriptOwnerID = media.id
            self.transcriptionError = nil
            isTranscribing = false
            transcriptionProgress = nil
        } catch {
            if runID != currentTranscriptionID { return }
            if let te = error as? TranscriptionError {
                if case .authorizationDenied = te {
                    lastAuthorizationDenied = true
                }
            }

            if !isRetry, shouldAutoRetry(error) {
                retryTask?.cancel()
                retryTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await self?.transcribe(media: media, runID: runID, isRetry: true)
                }
                return
            }

            isTranscribing = false
            transcriptionProgress = nil
            let info = TranscriptionErrorMapper.describe(error)
            scheduleError(info, runID: runID)
        }
    }

    private func shouldAutoRetry(_ error: Error) -> Bool {
        if let te = error as? TranscriptionError {
            switch te {
            case .noSpeechDetected, .speechNotAvailable:
                return true
            case .failed(let message):
                return message.lowercased().contains("cannot open") == false
            default:
                return false
            }
        }
        return false
    }

    private func scheduleError(_ info: TranscriptionErrorInfo, runID: UUID) {
        pendingErrorTask?.cancel()
        pendingErrorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.currentTranscriptionID == runID else { return }
                guard (self.transcript?.segments.isEmpty ?? true) else { return }
                self.transcriptionError = info
            }
        }
    }

    func retranscribe() {
        guard let media = selectedMedia else { return }
        transcriptStore.delete(fingerprint: media.fingerprint)
        transcript = nil
        transcriptOwnerID = nil
        transcriptionError = nil
        diagnosticsText = nil
        startTranscription(for: media)
    }

    func runDiagnostics() {
        guard let media = selectedMedia else { return }
        Task {
            let text = await TranscriptionDiagnostics.run(mediaURL: media.url)
            await MainActor.run {
                diagnosticsText = text
                showDiagnostics = true
            }
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func handleAppBecameActive() {
        guard lastAuthorizationDenied else { return }
        guard SpeechAuthorizationHelper.status() == .authorized else { return }
        guard !isTranscribing, transcript == nil, let media = selectedMedia else { return }
        lastAuthorizationDenied = false
        startTranscription(for: media)
    }

    private func cancelTranscriptionTasks() {
        currentTranscriptionID = UUID()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        retryTask?.cancel()
        retryTask = nil
        pendingErrorTask?.cancel()
        pendingErrorTask = nil
    }

    private func isTranscriptCompatible(_ transcript: Transcript, media: MediaItem) -> Bool {
        guard transcript.mediaFingerprint == media.fingerprint else { return false }
        if let title = transcript.mediaTitle, title != media.title { return false }
        if let duration = transcript.mediaDuration {
            if abs(duration - media.duration) > 1.0 { return false }
        }
        guard let signature = transcript.mediaSignature else { return false }
        if signature != MediaSignature.forFile(url: media.url) { return false }
        guard media.duration > 0 else { return true }
        guard !transcript.segments.isEmpty else { return false }
        let minStart = transcript.segments.map { $0.start }.min() ?? 0
        let maxEnd = transcript.segments.map { $0.end }.max() ?? 0
        if maxEnd > media.duration + 1.5 { return false }
        if media.duration >= 60 {
            if minStart > min(8, media.duration * 0.1) { return false }
            if maxEnd < media.duration - 8 { return false }
            if (maxEnd - minStart) < media.duration * 0.5 { return false }
        }
        return true
    }
}
