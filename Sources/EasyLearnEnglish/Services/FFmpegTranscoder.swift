import Foundation

enum FFmpegTranscoder {
    static func ffmpegPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let path = String(dir) + "/ffmpeg"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func extractAudio(from inputURL: URL) throws -> URL {
        guard let ffmpeg = ffmpegPath() else {
            throw TranscriptionError.failed("未检测到 ffmpeg。该视频格式当前无法解析，请先安装 ffmpeg 或将视频转换为 mp4/m4a 后重试。")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y",
            "-i", inputURL.path,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            outputURL.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return outputURL
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let log = String(data: data, encoding: .utf8) ?? ""
        throw TranscriptionError.failed("ffmpeg 转换失败：\(log.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}
