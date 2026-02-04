import Foundation
import AVFoundation
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

    func transcribe(mediaURL: URL, language: String) async throws -> [TranscriptSegment] {
        let auth = await requestSpeechAuth()
        guard auth == .authorized else {
            throw TranscriptionError.authorizationDenied
        }

        let audioURL = try await ensureAudioURL(for: mediaURL)
        let audioDuration = (try? await AVAsset(url: audioURL).load(.duration).seconds) ?? 0
        if let issue = validateAudioReadable(audioURL) {
            throw TranscriptionError.failed("音频文件不可读取：\(issue)")
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        guard let recognizer else {
            throw TranscriptionError.speechNotAvailable
        }

        do {
            return try await recognize(
                recognizer: recognizer,
                audioURL: audioURL,
                requiresOnDevice: recognizer.supportsOnDeviceRecognition,
                audioDuration: audioDuration
            )
        } catch {
            if case TranscriptionError.noSpeechDetected = error, recognizer.supportsOnDeviceRecognition {
                return try await recognize(
                    recognizer: recognizer,
                    audioURL: audioURL,
                    requiresOnDevice: false,
                    audioDuration: audioDuration
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

    private func ensureAudioURL(for mediaURL: URL) async throws -> URL {
        let ext = mediaURL.pathExtension.lowercased()
        if ["m4a", "mp3", "wav", "aiff", "caf"].contains(ext) {
            return mediaURL
        }
        return try await AudioExtractor.extractAudio(from: mediaURL)
    }

    private func recognize(
        recognizer: SFSpeechRecognizer,
        audioURL: URL,
        requiresOnDevice: Bool,
        audioDuration: Double
    ) async throws -> [TranscriptSegment] {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = requiresOnDevice
        request.taskHint = .dictation
        request.shouldReportPartialResults = true

        let tracker = ContinuationTracker<[TranscriptSegment]>()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[TranscriptSegment], Error>) in
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 120_000_000_000)
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
                
                if result.isFinal {
                    timeoutTask.cancel()
                    let segments = TranscriptSegmentBuilder.build(from: result.bestTranscription.segments)
                    if !segments.isEmpty {
                        Task {
                            await tracker.resumeWithResult(continuation, result: segments)
                        }
                        return
                    }

                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let tokens = text.split { $0.isWhitespace }.map(String.init)
                        let end = max(audioDuration, 1.0)
                        let fallback = TranscriptSegment(start: 0, end: end, text: text, tokens: tokens)
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

enum TranscriptSegmentBuilder {
    static func build(from wordSegments: [SFTranscriptionSegment]) -> [TranscriptSegment] {
        guard !wordSegments.isEmpty else { return [] }

        var result: [TranscriptSegment] = []
        var currentWords: [String] = []
        var currentStart: Double = wordSegments[0].timestamp
        var currentEnd: Double = wordSegments[0].timestamp + wordSegments[0].duration

        func flush() {
            guard !currentWords.isEmpty else { return }
            let text = currentWords.joined(separator: " ")
            let segment = TranscriptSegment(start: currentStart, end: currentEnd, text: text, tokens: currentWords)
            result.append(segment)
            currentWords = []
        }

        for seg in wordSegments {
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
        }

        flush()
        return result
    }
}

enum AudioExtractor {
    static func extractAudio(from mediaURL: URL) async throws -> URL {
        let asset = AVAsset(url: mediaURL)
        let duration = try await asset.load(.duration)
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if audioTracks.isEmpty {
            throw TranscriptionError.failed("视频没有音轨，无法提取音频。")
        }

        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        guard presets.contains(AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.failed("该视频格式不支持导出音频，请先转换格式后再导入。")
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.failed("创建音频导出会话失败。")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: .zero, duration: duration)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        await session.export()
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
