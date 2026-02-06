import Foundation
@preconcurrency import AVFoundation
import Speech

private actor ContinuationTracker<T> {
    private var hasResumed = false
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Error>?

    func setTask(_ task: SFSpeechRecognitionTask, timeout: Task<Void, Error>) {
        self.recognitionTask = task
        self.timeoutTask = timeout
    }

    func resumeWithResult(_ continuation: CheckedContinuation<T, Error>, result: T) {
        guard !hasResumed else { return }
        hasResumed = true
        timeoutTask?.cancel()
        continuation.resume(returning: result)
    }

    func resumeWithError(_ continuation: CheckedContinuation<T, Error>, error: Error) {
        guard !hasResumed else { return }
        hasResumed = true
        timeoutTask?.cancel()
        recognitionTask?.cancel()
        continuation.resume(throwing: error)
    }
}

struct AppleSpeechTranscriber: TranscriptionProvider {
    let name: String = "Apple Speech (On-device)"
    let allowOnlineFallback: Bool

    init(allowOnlineFallback: Bool = true) {
        self.allowOnlineFallback = allowOnlineFallback
    }

    func transcribe(
        mediaURL: URL,
        language: String,
        progress: @Sendable @escaping (TranscriptionProgress) -> Void
    ) async throws -> [TranscriptSegment] {
        progress(.init(stage: .preparing, detail: "初始化语音识别"))
        progress(.init(stage: .requestingPermission, detail: "检查语音识别权限"))
        let auth = await requestSpeechAuth()
        guard auth == .authorized else {
            throw TranscriptionError.authorizationDenied
        }

        progress(.init(stage: .loadingMedia, detail: "读取媒体文件"))
        let audioURL = try await ensureAudioURL(for: mediaURL, progress: progress)
        progress(.init(stage: .loadingMedia, detail: "校验音频可读性"))
        let audioDuration = (try? await AVAsset(url: audioURL).load(.duration).seconds) ?? 0
        if let issue = validateAudioReadable(audioURL) {
            throw TranscriptionError.failed("音频文件不可读取：\(issue)")
        }
        progress(.init(stage: .loadingMedia, detail: "加载语音识别器"))
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        guard let recognizer else {
            throw TranscriptionError.speechNotAvailable
        }

        do {
            let segments = try await recognize(
                recognizer: recognizer,
                audioURL: audioURL,
                requiresOnDevice: recognizer.supportsOnDeviceRecognition,
                audioDuration: audioDuration,
                progress: progress
            )
            if recognizer.supportsOnDeviceRecognition,
               isLikelyIncomplete(segments, audioDuration: audioDuration) {
                let reason = incompleteReason(segments: segments, audioDuration: audioDuration)
                if !allowOnlineFallback {
                    progress(.init(stage: .recognizingOnDevice, detail: "本地识别不完整，等待确认是否联网继续", fraction: 1))
                    throw TranscriptionError.onlineFallbackRequired("本地识别结果不完整：\(reason) 建议改用联网识别继续。")
                }
                progress(.init(stage: .recognizingServer, detail: "本地识别不完整（\(reason)），切换为联网识别（进度将重新计算）", fraction: 0))
                return try await recognize(
                    recognizer: recognizer,
                    audioURL: audioURL,
                    requiresOnDevice: false,
                    audioDuration: audioDuration,
                    progress: progress
                )
            }
            return segments
        } catch {
            if case TranscriptionError.noSpeechDetected = error, recognizer.supportsOnDeviceRecognition {
                if !allowOnlineFallback {
                    progress(.init(stage: .recognizingOnDevice, detail: "本地识别无结果，等待确认是否联网继续", fraction: 1))
                    throw TranscriptionError.onlineFallbackRequired("本地识别未检测到人声，可尝试联网识别。")
                }
                progress(.init(stage: .recognizingServer, detail: "本地识别无结果，切换为联网识别（进度将重新计算）", fraction: 0))
                return try await recognize(
                    recognizer: recognizer,
                    audioURL: audioURL,
                    requiresOnDevice: false,
                    audioDuration: audioDuration,
                    progress: progress
                )
            }
            throw error
        }
    }

    private func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func ensureAudioURL(
        for mediaURL: URL,
        progress: @Sendable @escaping (TranscriptionProgress) -> Void
    ) async throws -> URL {
        let mediaDuration = (try? await AVAsset(url: mediaURL).load(.duration).seconds) ?? 0
        let ext = mediaURL.pathExtension.lowercased()
        if ["m4a", "mp3", "wav", "aiff", "caf"].contains(ext) {
            progress(.init(stage: .extractingAudio, detail: "音频文件已就绪", fraction: 1))
            return mediaURL
        }
        progress(.init(stage: .extractingAudio, detail: "从视频中提取音频", fraction: 0))
        return try await AudioExtractor.extractAudio(from: mediaURL) { fraction in
            let detail = extractionDetail(fraction: fraction, total: mediaDuration)
            progress(.init(stage: .extractingAudio, detail: detail, fraction: fraction))
        }
    }

    private func recognize(
        recognizer: SFSpeechRecognizer,
        audioURL: URL,
        requiresOnDevice: Bool,
        audioDuration: Double,
        progress: @Sendable @escaping (TranscriptionProgress) -> Void
    ) async throws -> [TranscriptSegment] {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = requiresOnDevice
        request.taskHint = .dictation
        request.shouldReportPartialResults = true

        let tracker = ContinuationTracker<[TranscriptSegment]>()
        let lock = NSLock()
        var lastSegments: [TranscriptSegment] = []
        var lastText: String = ""
        var wordSegmentsByKey: [WordKey: SFTranscriptionSegment] = [:]
        var lastProgressSecond: Int = -1

        let stage: TranscriptionStage = requiresOnDevice ? .recognizingOnDevice : .recognizingServer
        progress(.init(stage: stage, detail: requiresOnDevice ? "使用本地模型识别" : "使用联网模型识别", fraction: 0))

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[TranscriptSegment], Error>) in
            let timeoutTask = Task {
                let timeoutSeconds: Double
                if audioDuration > 0 {
                    timeoutSeconds = max(120.0, audioDuration * 2.0)
                } else {
                    timeoutSeconds = 600.0
                }
                let timeoutNanos = UInt64(timeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: timeoutNanos)
                await tracker.resumeWithError(continuation, error: TranscriptionError.failed("语音识别超时，请检查音频文件或网络连接。"))
            }

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    timeoutTask.cancel()
                    let transcriptionError = Self.mapError(error, audioURL: audioURL)
                    Task {
                        await tracker.resumeWithError(continuation, error: transcriptionError)
                    }
                    return
                }

                guard let result = result else { return }
                lock.lock()
                for segment in result.bestTranscription.segments {
                    let key = WordKey(
                        startMS: Int((segment.timestamp * 1000).rounded()),
                        durationMS: Int((segment.duration * 1000).rounded())
                    )
                    wordSegmentsByKey[key] = segment
                }
                let mergedWordSegments = wordSegmentsByKey.values.sorted { $0.timestamp < $1.timestamp }
                let maxEnd = mergedWordSegments.last.map { $0.timestamp + $0.duration } ?? 0
                if maxEnd > 0 {
                    let currentSecond = Int(maxEnd.rounded(.down))
                    if currentSecond > lastProgressSecond {
                        lastProgressSecond = currentSecond
                        let detail = progressDetail(current: maxEnd, total: audioDuration)
                        let fraction = progressFraction(current: maxEnd, total: audioDuration)
                        progress(.init(stage: stage, detail: detail, fraction: fraction))
                    }
                }
                lock.unlock()

                let currentSegments: [TranscriptSegment]
                if result.isFinal {
                    progress(.init(stage: .parsingSegments, detail: parsingDetail(current: 0, total: mergedWordSegments.count), fraction: 0))
                    currentSegments = TranscriptSegmentBuilder.build(from: mergedWordSegments) { fraction in
                        let current = Int((Double(mergedWordSegments.count) * fraction).rounded(.up))
                        let detail = parsingDetail(current: current, total: mergedWordSegments.count)
                        progress(.init(stage: .parsingSegments, detail: detail, fraction: fraction))
                    }
                    if mergedWordSegments.isEmpty {
                        progress(.init(stage: .parsingSegments, detail: parsingDetail(current: 0, total: 0), fraction: 1))
                    }
                } else {
                    currentSegments = TranscriptSegmentBuilder.build(from: mergedWordSegments)
                }
                let currentText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !currentSegments.isEmpty || !currentText.isEmpty {
                    lock.lock()
                    if !currentSegments.isEmpty {
                        lastSegments = currentSegments
                    }
                    if !currentText.isEmpty {
                        lastText = currentText
                    }
                    lock.unlock()
                }
                
                if result.isFinal {
                    timeoutTask.cancel()
                    let segments = currentSegments
                    if !segments.isEmpty {
                        Task {
                            await tracker.resumeWithResult(continuation, result: segments)
                        }
                        return
                    }

                    let text = currentText
                    if !text.isEmpty {
                        let tokens = text.split { $0.isWhitespace }.map(String.init)
                        let end = max(audioDuration, 1.0)
                        let fallback = TranscriptSegment(start: 0, end: end, text: text, tokens: tokens)
                        Task {
                            await tracker.resumeWithResult(continuation, result: [fallback])
                        }
                        return
                    }

                    lock.lock()
                    let cachedSegments = lastSegments
                    let cachedText = lastText
                    lock.unlock()
                    if !cachedSegments.isEmpty {
                        Task {
                            await tracker.resumeWithResult(continuation, result: cachedSegments)
                        }
                        return
                    }
                    if !cachedText.isEmpty {
                        let tokens = cachedText.split { $0.isWhitespace }.map(String.init)
                        let end = max(audioDuration, 1.0)
                        let fallback = TranscriptSegment(start: 0, end: end, text: cachedText, tokens: tokens)
                        Task {
                            await tracker.resumeWithResult(continuation, result: [fallback])
                        }
                        return
                    }
                    Task {
                        await tracker.resumeWithError(continuation, error: TranscriptionError.noSpeechDetected)
                    }
                }
            }

            Task {
                await tracker.setTask(task, timeout: timeoutTask)
            }
        }
    }

    private func isLikelyIncomplete(_ segments: [TranscriptSegment], audioDuration: Double) -> Bool {
        return false
    }

    private func incompleteReason(segments: [TranscriptSegment], audioDuration: Double) -> String {
        guard audioDuration > 0, !segments.isEmpty else {
            return "识别结果为空"
        }
        let minStart = segments.map { $0.start }.min() ?? 0
        let maxEnd = segments.map { $0.end }.max() ?? 0
        let coverage = max(0, maxEnd - minStart)
        let coverageRatio = audioDuration > 0 ? coverage / audioDuration : 0
        let showHours = audioDuration >= 3600
        if maxEnd < audioDuration - 8 {
            return "识别只到 \(formatProgressTime(maxEnd, showHours: showHours)) / \(formatProgressTime(audioDuration, showHours: showHours))"
        }
        let minStartThreshold = min(8, audioDuration * 0.1)
        if minStart > minStartThreshold {
            return "识别从 \(formatProgressTime(minStart, showHours: showHours)) 才开始"
        }
        if coverageRatio < 0.5 {
            let percent = Int((coverageRatio * 100).rounded())
            return "识别覆盖率仅 \(percent)%"
        }
        return "识别覆盖率不足"
    }

    private func progressDetail(current: Double, total: Double) -> String {
        let showHours = max(current, total) >= 3600
        let currentText = formatProgressTime(current, showHours: showHours)
        if total > 0 {
            let totalText = formatProgressTime(total, showHours: showHours)
            return "已识别 \(currentText) / \(totalText)"
        }
        return "已识别 \(currentText)"
    }

    private func progressFraction(current: Double, total: Double) -> Double? {
        guard total > 0 else { return nil }
        return min(max(current / total, 0), 1)
    }

    private func extractionDetail(fraction: Double, total: Double) -> String {
        guard total > 0 else {
            return String(format: "提取音频 %.0f%%", min(max(fraction, 0), 1) * 100)
        }
        let current = total * fraction
        let showHours = total >= 3600
        let currentText = formatProgressTime(current, showHours: showHours)
        let totalText = formatProgressTime(total, showHours: showHours)
        return "已提取 \(currentText) / \(totalText)"
    }

    private func parsingDetail(current: Int, total: Int) -> String {
        guard total > 0 else { return "解析字幕" }
        let clamped = min(max(current, 0), total)
        return "解析字幕 \(clamped)/\(total)"
    }

    private func formatProgressTime(_ seconds: Double, showHours: Bool) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if showHours || hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func mapError(_ error: Error) -> TranscriptionError {
        return mapError(error, audioURL: nil)
    }

    private static func mapError(_ error: Error, audioURL: URL?) -> TranscriptionError {
        if let nsError = error as NSError? {
            // kLSRErrorDomain: Apple 私有语音识别错误域（无官方文档）
            if nsError.domain == "kLSRErrorDomain" {
                switch nsError.code {
                case 301: return .siriDictationDisabled
                case 1110: return .noSpeechDetected
                case 1700: return .failed("本地语音识别模型不可用。请在「系统设置 → 键盘 → 听写」中下载英文语言包，或关闭「本地识别」选项。")
                default: break
                }
            }
            // kAFAssistantErrorDomain: Siri 网络错误域
            if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1101 {
                return .failed("语音识别服务连接失败，请检查网络连接。")
            }
            if nsError.localizedDescription.lowercased().contains("cannot open") {
                let fileInfo = audioURL?.path ?? "未知路径"
                let detail = "(domain: \(nsError.domain), code: \(nsError.code))"
                return .failed("语音识别无法打开音频文件：\(fileInfo) \(detail)。请尝试重新导入或转换为 mp3/m4a 后重试。")
            }
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("no speech detected") {
            return .noSpeechDetected
        }
        return .failed(error.localizedDescription)
    }

    private func validateAudioReadable(_ url: URL) -> String? {
        if !FileManager.default.fileExists(atPath: url.path) {
            return "文件不存在（\(url.path)）"
        }
        if !FileManager.default.isReadableFile(atPath: url.path) {
            return "文件不可读（\(url.path)）"
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value == 0 {
            return "文件大小为 0"
        }
        do {
            _ = try AVAudioFile(forReading: url)
        } catch {
            return "AVAudioFile 无法读取：\(error.localizedDescription)"
        }
        return nil
    }
}

private struct WordKey: Hashable {
    let startMS: Int
    let durationMS: Int
}

enum TranscriptSegmentBuilder {
    static func build(from wordSegments: [SFTranscriptionSegment], progress: ((Double) -> Void)? = nil) -> [TranscriptSegment] {
        guard !wordSegments.isEmpty else { return [] }

        var result: [TranscriptSegment] = []
        var currentWords: [String] = []
        var currentStart: Double = wordSegments[0].timestamp
        var currentEnd: Double = wordSegments[0].timestamp + wordSegments[0].duration
        let total = wordSegments.count
        let reportStride = max(1, total / 60)

        func flush() {
            guard !currentWords.isEmpty else { return }
            let text = currentWords.joined(separator: " ")
            let segment = TranscriptSegment(start: currentStart, end: currentEnd, text: text, tokens: currentWords)
            result.append(segment)
            currentWords = []
        }

        for (index, seg) in wordSegments.enumerated() {
            let word = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            if word.isEmpty {
                continue
            }
            let segStart = seg.timestamp
            let segEnd = seg.timestamp + seg.duration
            let gap = segStart - currentEnd

            if currentWords.count >= 7 || gap > 0.9 {
                flush()
                currentStart = segStart
            }

            if currentWords.isEmpty {
                currentStart = segStart
            }

            currentWords.append(word)
            currentEnd = segEnd

            if let progress, index % reportStride == 0 || index == total - 1 {
                let fraction = total > 0 ? Double(index + 1) / Double(total) : 1
                progress(min(max(fraction, 0), 1))
            }
        }

        flush()
        progress?(1)
        return result
    }
}

enum AudioExtractor {
    static func extractAudio(from mediaURL: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let asset = AVAsset(url: mediaURL)
        let duration = try await asset.load(.duration)
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if audioTracks.isEmpty {
            throw TranscriptionError.failed("视频没有音轨，无法提取音频。")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.failed("该视频格式不支持导出音频，请先转换格式后再导入。")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: .zero, duration: duration)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let progressTask = Task {
            while true {
                let status = session.status
                if status != .exporting && status != .waiting {
                    break
                }
                progress?(Double(session.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        await session.export()
        progressTask.cancel()
        progress?(1)
        if session.status == .completed {
            return outputURL
        }
        if let nsError = session.error as NSError? {
            let detail = "\(nsError.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))"
            throw TranscriptionError.failed("音频导出失败：\(detail)")
        }
        throw TranscriptionError.failed("音频导出失败")
    }
}
