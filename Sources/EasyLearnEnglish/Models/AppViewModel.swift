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
    @Published var transcript: Transcript?
    @Published var isTranscribing: Bool = false
    @Published var transcriptionError: TranscriptionErrorInfo?
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

    let player = AVPlayer()
    private var timeObserverToken: Any?

    init(mediaLibrary: MediaLibrary, vocabularyStore: VocabularyStore, settings: SettingsStore) {
        self.mediaLibrary = mediaLibrary
        self.vocabularyStore = vocabularyStore
        self.settings = settings
    }

    func selectToken(segmentIndex: Int, tokenIndex: Int, extend: Bool) {
        guard let transcript else { return }
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
        guard let transcript, let start = selectionStart, let end = selectionEnd else {
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
        transcriptionError = nil
        transcript = nil
        isTranscribing = false

        guard let media = selectedMedia else { return }
        preparePlayer(with: media.url)

        if let cached = transcriptStore.load(fingerprint: media.fingerprint) {
            if cached.segments.isEmpty {
                transcriptStore.delete(fingerprint: media.fingerprint)
            } else {
                transcript = cached
                return
            }
        }

        Task {
            await transcribe(media: media)
        }
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
        guard let transcript else { return }
        guard !transcript.segments.isEmpty else { return }
        let idx = transcript.segments.firstIndex { currentTime >= $0.start && currentTime <= $0.end }
        if let idx {
            currentSegmentIndex = idx
        }
    }

    private func transcribe(media: MediaItem) async {
        isTranscribing = true
        transcriptionError = nil
        let provider = transcriptionService.provider(for: settings.provider, settings: settings)
        do {
            let segments = try await provider.transcribe(mediaURL: media.url, language: "en-US")
            guard !segments.isEmpty else {
                throw TranscriptionError.failed("转写完成但没有识别到文本。请检查音频是否有人声，或更换转写提供商。")
            }
            let transcript = Transcript(mediaFingerprint: media.fingerprint, provider: provider.name, language: "en-US", segments: segments)
            transcriptStore.save(transcript)
            self.transcript = transcript
            isTranscribing = false
        } catch {
            transcriptionError = TranscriptionErrorMapper.describe(error)
            isTranscribing = false
        }
    }

    func retranscribe() {
        guard let media = selectedMedia else { return }
        transcriptStore.delete(fingerprint: media.fingerprint)
        transcript = nil
        transcriptionError = nil
        Task {
            await transcribe(media: media)
        }
    }
}
