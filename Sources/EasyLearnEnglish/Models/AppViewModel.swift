import Foundation
import AVFoundation
import SwiftUI
import Combine

struct TokenRef: Equatable {
    let segmentIndex: Int
    let tokenIndex: Int
}

@MainActor
final class AppViewModel: ObservableObject {
    struct OnlineFallbackPrompt: Identifiable, Equatable {
        let id = UUID()
        let mediaID: UUID
        let reason: String
    }

    @Published var selectedMedia: MediaItem? {
        didSet { handleSelectionChange(from: oldValue) }
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
    @Published var onlineFallbackPrompt: OnlineFallbackPrompt?
    @Published var manualLookupText: String = ""
    @Published var shadowingSegments: [ShadowingSegment] = [] {
        didSet {
            saveShadowingSegmentsIfNeeded()
        }
    }
    @Published var selectedShadowingSegmentID: UUID?
    @Published var loopSegmentID: UUID?
    @Published var selectedTokens: [String] = []
    @Published var translation: TranslationSnapshot?
    @Published var translationKey: String?
    @Published var isFetchingTranslation: Bool = false

    let mediaLibrary: MediaLibrary
    let vocabularyStore: VocabularyStore
    let settings: SettingsStore

    private let transcriptStore = TranscriptStore()
    private let shadowingStore = ShadowingStore()
    private let transcriptionService = TranscriptionService()
    private let translationService = TranslationService()

    private var selectionStart: TokenRef?
    private var selectionEnd: TokenRef?
    private struct TranscriptionSession {
        var runID: UUID
        var task: Task<Void, Never>?
        var retryTask: Task<Void, Never>?
        var pendingErrorTask: Task<Void, Never>?
        var isTranscribing: Bool
        var progress: TranscriptionProgress?
        var error: TranscriptionErrorInfo?
        var allowOnlineFallback: Bool
    }
    private var transcriptionSessions: [UUID: TranscriptionSession] = [:]
    private var onlineFallbackApproved: Set<UUID> = []
    private var translationTask: Task<Void, Never>?
    private var lastAuthorizationDenied = false
    private var transcriptOwnerID: UUID?
    private var shadowingFingerprint: String?
    private var cancellables: Set<AnyCancellable> = []

    let player = AVPlayer()
    private var timeObserverToken: Any?
    private var loopStart: Double?
    private var loopEnd: Double?

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
        vocabularyStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
        translationTask?.cancel()
        selectionStart = nil
        selectionEnd = nil
        selectedTokens = []
        translation = nil
        translationKey = nil
        isFetchingTranslation = false
    }

    func saveSelectionToVocabulary() {
        guard let selectedText = selectedText, !selectedText.isEmpty else { return }
        let snapshot = translation ?? translationService.cachedSnapshot(for: selectedText)
        let definition = snapshot?.primaryEnglish ?? ""
        let zh = snapshot?.primaryChinese ?? ""
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

    func isWordSaved(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return vocabularyStore.isSaved(word: trimmed)
    }

    func saveWord(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let snapshot = snapshotForLookup(text: trimmed)
        let definition = snapshot?.primaryEnglish ?? ""
        let zh = snapshot?.primaryChinese ?? ""
        let sourceTitle = selectedMedia?.title ?? ""
        vocabularyStore.save(word: trimmed, definitionEn: definition, translationZh: zh, sourceTitle: sourceTitle)
    }

    func removeWord(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        vocabularyStore.remove(word: trimmed)
    }

    private func updateSelectedTokens() {
        guard let transcript = activeTranscript, let start = selectionStart, let end = selectionEnd else {
            selectedTokens = []
            translation = nil
            translationKey = nil
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
        let manual = manualLookupText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty {
            manualLookupText = ""
        }
        if let text = selectedText {
            fetchTranslation(for: text, forceRefresh: false)
        }
    }

    func fetchTranslation(for text: String, forceRefresh: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translation = nil
            translationKey = nil
            return
        }

        let key = TranslationService.normalizedKey(trimmed)
        translationTask?.cancel()

        if !forceRefresh, let cached = translationService.cachedSnapshot(for: trimmed) {
            translation = cached
            translationKey = key
            isFetchingTranslation = false
            return
        }

        if !forceRefresh || translationKey != key {
            translation = nil
        }
        translationKey = key
        isFetchingTranslation = true
        translationTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await translationService.fetch(
                wordOrPhrase: trimmed,
                forceRefresh: forceRefresh,
                config: translationConfig()
            )
            if Task.isCancelled { return }
            self.translation = snapshot
            self.translationKey = key
            self.isFetchingTranslation = false
        }
    }

    func refreshTranslation(for text: String) {
        fetchTranslation(for: text, forceRefresh: true)
    }

    func normalizedTranslationKey(for text: String?) -> String? {
        guard let text else { return nil }
        return TranslationService.normalizedKey(text)
    }

    func cachedTranslation(for text: String) -> TranslationSnapshot? {
        translationService.cachedSnapshot(for: text)
    }

    private func snapshotForLookup(text: String) -> TranslationSnapshot? {
        let key = TranslationService.normalizedKey(text)
        if key == translationKey {
            return translation
        }
        return translationService.cachedSnapshot(for: text)
    }

    private func translationConfig() -> TranslationServiceConfig {
        TranslationServiceConfig(
            youdaoAppKey: settings.youdaoAppKey,
            youdaoAppSecret: settings.youdaoAppSecret,
            baiduAppId: settings.baiduAppId,
            baiduAppSecret: settings.baiduAppSecret,
            azureTranslatorKey: settings.azureTranslatorKey,
            azureTranslatorRegion: settings.azureTranslatorRegion
        )
    }

    private func handleSelectionChange(from previous: MediaItem?) {
        if let previous, let current = selectedMedia, previous.id == current.id {
            return
        }
        clearSelection()
        transcriptionError = nil
        transcript = nil
        transcriptOwnerID = nil
        currentSegmentIndex = 0
        isTranscribing = false
        transcriptionProgress = nil
        resetShadowingState()

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
                loadShadowingSegments(for: media)
                return
            }
        }

        if let session = transcriptionSessions[media.id] {
            applySession(session, for: media.id)
            if session.isTranscribing || session.progress != nil || session.error != nil {
                loadShadowingSegments(for: media)
                return
            }
        }

        loadShadowingSegments(for: media)
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
                self?.handleLoop(currentTime: time.seconds)
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
        let mediaID = media.id
        if let session = transcriptionSessions[mediaID], session.isTranscribing {
            applySession(session, for: mediaID)
            return
        }
        let runID = UUID()
        let allowOnlineFallback = onlineFallbackApproved.contains(mediaID)
        var session = transcriptionSessions[mediaID] ?? TranscriptionSession(
            runID: runID,
            task: nil,
            retryTask: nil,
            pendingErrorTask: nil,
            isTranscribing: false,
            progress: nil,
            error: nil,
            allowOnlineFallback: allowOnlineFallback
        )
        session.runID = runID
        session.task?.cancel()
        session.retryTask?.cancel()
        session.pendingErrorTask?.cancel()
        session.isTranscribing = true
        session.error = nil
        session.progress = TranscriptionProgress(stage: .preparing, detail: nil)
        session.allowOnlineFallback = allowOnlineFallback
        session.task = Task { [weak self] in
            await self?.transcribe(media: media, runID: runID, isRetry: false)
        }
        transcriptionSessions[mediaID] = session
        applySession(session, for: mediaID)
    }

    private func transcribe(media: MediaItem, runID: UUID, isRetry: Bool) async {
        let mediaID = media.id
        guard isActiveSession(mediaID: mediaID, runID: runID) else { return }
        if Task.isCancelled { return }

        updateSession(mediaID: mediaID) { session in
            session.isTranscribing = true
            session.error = nil
            session.progress = TranscriptionProgress(stage: .preparing, detail: isRetry ? "准备重试转写" : nil)
        }
        lastAuthorizationDenied = false
        diagnosticsText = nil
        updateSession(mediaID: mediaID) { session in
            session.pendingErrorTask?.cancel()
            session.pendingErrorTask = nil
        }

        let progressHandler: @Sendable (TranscriptionProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self else { return }
                guard self.isActiveSession(mediaID: mediaID, runID: runID) else { return }
                self.updateSession(mediaID: mediaID) { session in
                    session.progress = progress
                }
            }
        }

        let allowOnlineFallback = transcriptionSessions[mediaID]?.allowOnlineFallback ?? false
        let provider = transcriptionService.provider(
            for: settings.provider,
            settings: settings,
            allowOnlineFallback: allowOnlineFallback
        )
        do {
            let segments = try await provider.transcribe(
                mediaURL: media.url,
                language: "en-US",
                progress: progressHandler
            )
            guard !segments.isEmpty else {
                throw TranscriptionError.failed("转写完成但没有识别到文本。请检查音频是否有人声，或更换转写提供商。")
            }
            if !isActiveSession(mediaID: mediaID, runID: runID) { return }
            progressHandler(.init(stage: .parsingSegments, detail: "解析字幕结构", fraction: 1))
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
            progressHandler(.init(stage: .savingTranscript, detail: "保存字幕到本地", fraction: 1))
            transcriptStore.save(transcript)
            if selectedMedia?.id == mediaID {
                self.transcript = transcript
                self.transcriptOwnerID = media.id
                self.transcriptionError = nil
            }
            updateSession(mediaID: mediaID) { session in
                session.isTranscribing = false
                session.progress = nil
                session.error = nil
                session.allowOnlineFallback = false
                session.runID = UUID()
            }
            if selectedMedia?.id == mediaID {
                isTranscribing = false
                transcriptionProgress = nil
            }
            onlineFallbackApproved.remove(mediaID)
        } catch {
            if !isActiveSession(mediaID: mediaID, runID: runID) { return }
            if let te = error as? TranscriptionError {
                switch te {
                case .authorizationDenied:
                    lastAuthorizationDenied = true
                case .onlineFallbackRequired(let reason):
                    let info = TranscriptionErrorInfo(
                        title: "本地识别未完成",
                        message: "\(reason) 是否改用联网识别？（可能产生费用）",
                        actions: []
                    )
                    updateSession(mediaID: mediaID) { session in
                        session.isTranscribing = false
                        session.error = info
                        session.progress = session.progress ?? TranscriptionProgress(stage: .recognizingOnDevice, detail: "等待确认是否联网继续", fraction: 1)
                        session.runID = UUID()
                    }
                    if let current = selectedMedia, current.id == mediaID {
                        transcriptionError = info
                        onlineFallbackPrompt = OnlineFallbackPrompt(mediaID: mediaID, reason: reason)
                    }
                    return
                default:
                    break
                }
            }

            if !isRetry, shouldAutoRetry(error) {
                updateSession(mediaID: mediaID) { session in
                    session.retryTask?.cancel()
                    session.retryTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await self?.transcribe(media: media, runID: runID, isRetry: true)
                    }
                }
                return
            }

            updateSession(mediaID: mediaID) { session in
                session.isTranscribing = false
                session.progress = nil
                session.allowOnlineFallback = false
                session.runID = UUID()
            }
            onlineFallbackApproved.remove(mediaID)
            let info = TranscriptionErrorMapper.describe(error)
            scheduleError(info, mediaID: mediaID, runID: runID)
        }
    }

    private func isActiveSession(mediaID: UUID, runID: UUID) -> Bool {
        guard let session = transcriptionSessions[mediaID] else { return false }
        return session.runID == runID
    }

    private func updateSession(mediaID: UUID, _ update: (inout TranscriptionSession) -> Void) {
        guard var session = transcriptionSessions[mediaID] else { return }
        update(&session)
        transcriptionSessions[mediaID] = session
        applySession(session, for: mediaID)
    }

    private func applySession(_ session: TranscriptionSession, for mediaID: UUID) {
        guard selectedMedia?.id == mediaID else { return }
        isTranscribing = session.isTranscribing
        transcriptionProgress = session.progress
        transcriptionError = session.error
    }

    private func cancelSession(for mediaID: UUID) {
        guard var session = transcriptionSessions[mediaID] else { return }
        session.task?.cancel()
        session.retryTask?.cancel()
        session.pendingErrorTask?.cancel()
        session.task = nil
        session.retryTask = nil
        session.pendingErrorTask = nil
        session.isTranscribing = false
        session.progress = nil
        session.error = nil
        transcriptionSessions[mediaID] = session
        applySession(session, for: mediaID)
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

    private func scheduleError(_ info: TranscriptionErrorInfo, mediaID: UUID, runID: UUID) {
        updateSession(mediaID: mediaID) { session in
            session.pendingErrorTask?.cancel()
            session.pendingErrorTask = nil
            session.error = info
            if session.runID == runID {
                session.runID = UUID()
            }
        }
        if let current = selectedMedia, current.id == mediaID {
            guard (transcript?.segments.isEmpty ?? true) else { return }
            transcriptionError = info
        }
    }

    func retranscribe() {
        guard let media = selectedMedia else { return }
        cancelSession(for: media.id)
        onlineFallbackApproved.remove(media.id)
        onlineFallbackPrompt = nil
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
        guard let media = selectedMedia else { return }
        if let session = transcriptionSessions[media.id], session.isTranscribing {
            return
        }
        guard transcript == nil else { return }
        lastAuthorizationDenied = false
        startTranscription(for: media)
    }

    var currentPlaybackSeconds: Double {
        max(0, player.currentTime().seconds)
    }

    func addShadowingSegment(start: Double, end: Double, title: String) {
        guard let media = selectedMedia else { return }
        let (clampedStart, clampedEnd) = clampSegment(start: start, end: end, duration: media.duration)
        let segment = ShadowingSegment(title: title, start: clampedStart, end: clampedEnd)
        shadowingSegments.append(segment)
        selectedShadowingSegmentID = segment.id
    }

    func updateShadowingSegment(_ segment: ShadowingSegment) {
        guard let media = selectedMedia else { return }
        let (clampedStart, clampedEnd) = clampSegment(start: segment.start, end: segment.end, duration: media.duration)
        if let index = shadowingSegments.firstIndex(where: { $0.id == segment.id }) {
            shadowingSegments[index].title = segment.title
            shadowingSegments[index].start = clampedStart
            shadowingSegments[index].end = clampedEnd
        }
        if loopSegmentID == segment.id {
            loopStart = clampedStart
            loopEnd = clampedEnd
        }
    }

    func deleteShadowingSegment(id: UUID) {
        shadowingSegments.removeAll { $0.id == id }
        if selectedShadowingSegmentID == id {
            selectedShadowingSegmentID = shadowingSegments.first?.id
        }
        if loopSegmentID == id {
            stopLoop()
        }
    }

    func selectShadowingSegment(id: UUID?) {
        selectedShadowingSegmentID = id
    }

    func playSegment(_ segment: ShadowingSegment) {
        stopLoop()
        seek(to: segment.start)
        player.play()
    }

    func toggleLoop(for segment: ShadowingSegment) {
        if loopSegmentID == segment.id {
            stopLoop()
        } else {
            loopStart = segment.start
            loopEnd = segment.end
            loopSegmentID = segment.id
            seek(to: segment.start)
            player.play()
        }
    }

    func stopLoop() {
        loopStart = nil
        loopEnd = nil
        loopSegmentID = nil
    }

    private func handleLoop(currentTime: Double) {
        guard let start = loopStart, let end = loopEnd else { return }
        guard end > start else { return }
        if currentTime >= end {
            let time = CMTime(seconds: start, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func clampSegment(start: Double, end: Double, duration: Double) -> (Double, Double) {
        let lower = max(0, min(start, duration))
        var upper = max(0, min(end, duration))
        if upper <= lower {
            upper = min(lower + 0.5, duration)
        }
        return (lower, upper)
    }

    private func loadShadowingSegments(for media: MediaItem) {
        shadowingFingerprint = media.fingerprint
        shadowingSegments = shadowingStore.load(fingerprint: media.fingerprint)
        if selectedShadowingSegmentID == nil || !shadowingSegments.contains(where: { $0.id == selectedShadowingSegmentID }) {
            selectedShadowingSegmentID = shadowingSegments.first?.id
        }
    }

    private func resetShadowingState() {
        shadowingFingerprint = nil
        shadowingSegments = []
        selectedShadowingSegmentID = nil
        stopLoop()
    }

    private func saveShadowingSegmentsIfNeeded() {
        guard let fingerprint = shadowingFingerprint else { return }
        shadowingStore.save(fingerprint: fingerprint, segments: shadowingSegments)
    }

    func confirmOnlineFallback(for mediaID: UUID) {
        onlineFallbackApproved.insert(mediaID)
        if let current = selectedMedia, current.id == mediaID {
            transcriptionError = nil
            onlineFallbackPrompt = nil
            cancelSession(for: mediaID)
            startTranscription(for: current)
        } else {
            onlineFallbackPrompt = nil
        }
    }

    func cancelOnlineFallback() {
        onlineFallbackPrompt = nil
    }

    private func isTranscriptCompatible(_ transcript: Transcript, media: MediaItem) -> Bool {
        guard transcript.mediaFingerprint == media.fingerprint else { return false }
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
        return true
    }
}
