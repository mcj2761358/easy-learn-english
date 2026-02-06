import SwiftUI
import WebKit
import Foundation
import AVFoundation

private let importSupportedAudioExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "caf"]
private let importSupportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]

final class OnlineResourcesStore: ObservableObject {
    private let mediaLibrary: MediaLibrary
    @Published var currentURL: String = ""
    @Published var address: String = "https://www.youtube.com"
    @Published var downloadStatus: String = ""
    @Published var isDownloading = false
    @Published var lastCommand: String = ""
    @Published var downloadProgress: Double = 0
    @Published var downloadProgressText: String = ""
    @Published var isImporting = false
    @Published var importStage: String = ""
    @Published var importStatus: String = ""
    @Published var importProgress: Double = 0
    @Published var importProgressText: String = ""
    @Published var importFilePath: String = ""
    @Published var importOverallProgress: Double = 0

    init(mediaLibrary: MediaLibrary) {
        self.mediaLibrary = mediaLibrary
    }

    @MainActor
    func resetForNewResource() {
        guard !isDownloading && !isImporting else { return }
        downloadStatus = ""
        lastCommand = ""
        downloadProgress = 0
        downloadProgressText = ""
        importStage = ""
        importStatus = ""
        importProgress = 0
        importProgressText = ""
        importFilePath = ""
        importOverallProgress = 0
    }

    func downloadCurrentURL() {
        let trimmed = currentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            downloadStatus = "暂无可下载的链接。"
            return
        }

        isDownloading = true
        downloadStatus = "导出内置浏览器 Cookies…"
        lastCommand = ""
        downloadProgress = 0
        downloadProgressText = ""

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let cookiesFile = try await self.exportCookiesFile()

                let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                let outputTemplate = downloadsDirectory.appendingPathComponent("%(title)s.%(ext)s").path
                let args = ["--newline", "--progress", "--cookies", cookiesFile.path, "-o", outputTemplate, trimmed]

                await MainActor.run {
                    self.lastCommand = (["yt-dlp"] + args).joined(separator: " ")
                    self.downloadStatus = "开始下载…"
                }

                await self.runDownload(arguments: args, downloadsPath: downloadsDirectory.path)
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadStatus = "导出 Cookies 失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func importCurrentURL() {
        let trimmed = currentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            importStatus = "暂无可导入的链接。"
            return
        }

        isImporting = true
        importStage = "准备导入"
        importStatus = "导出内置浏览器 Cookies…"
        importProgress = 0
        importProgressText = ""
        importFilePath = ""
        importOverallProgress = 0

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let cookiesFile = try await self.exportCookiesFile()
                await self.updateImportUI(stage: "导出 Cookies", status: "完成", progress: 1, overall: 0.05)

                let stagingDir = self.makeImportStagingDir()
                await self.updateImportUI(stage: "下载视频", status: "下载中…", progress: 0, overall: 0.05)
                let downloadedURL = try await self.downloadForImport(url: trimmed, cookiesFile: cookiesFile, stagingDir: stagingDir)
                await self.updateImportUI(stage: "下载视频", status: "下载完成", progress: 1, overall: 0.65, detail: downloadedURL.lastPathComponent, filePath: downloadedURL.path)

                await self.updateImportUI(stage: "检测格式", status: "检查文件类型…", progress: 1, overall: 0.7)
                var importURL = downloadedURL
                let isSupported = await self.isDirectlySupported(url: downloadedURL)

                if isSupported {
                    await self.updateImportUI(
                        stage: "检测格式",
                        status: "格式已支持，跳过转码",
                        progress: 1,
                        overall: 0.7,
                        detail: downloadedURL.lastPathComponent,
                        filePath: downloadedURL.path
                    )
                } else {
                    let duration = await self.mediaDuration(url: downloadedURL)
                    let outputURL = stagingDir.appendingPathComponent(downloadedURL.deletingPathExtension().lastPathComponent + ".mp4")
                    await self.updateImportUI(stage: "转码为 MP4", status: "转码中…", progress: 0, overall: 0.7, detail: outputURL.lastPathComponent, filePath: outputURL.path)
                    importURL = try await self.transcodeToMp4(inputURL: downloadedURL, outputURL: outputURL, duration: duration)
                    await self.updateImportUI(stage: "转码为 MP4", status: "转码完成", progress: 1, overall: 0.9, detail: outputURL.lastPathComponent, filePath: outputURL.path)
                }

                await self.updateImportUI(stage: "导入媒体库", status: "正在导入…", progress: 0.5, overall: 0.95, detail: importURL.lastPathComponent, filePath: importURL.path)
                let folder = await self.mediaLibrary.ensureFolder(name: "自动导入", parentID: nil)
                let importResult = await self.mediaLibrary.importMedia(urls: [importURL], targetFolderID: folder.id)
                if importResult.imported.isEmpty {
                    let detail = importResult.failures.first ?? "导入失败"
                    throw ImportPipelineError.downloadFailed(detail)
                }

                try? FileManager.default.removeItem(at: stagingDir)

                await self.updateImportUI(stage: "完成", status: "导入完成", progress: 1, overall: 1)
                await MainActor.run {
                    self.isImporting = false
                }
            } catch {
                await self.updateImportUI(stage: "失败", status: "导入失败：\(error.localizedDescription)", progress: 0, overall: 0)
                await MainActor.run {
                    self.isImporting = false
                }
            }
        }
    }

    private func runDownload(arguments: [String], downloadsPath: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yt-dlp"] + arguments

        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = ([existingPath] + extraPaths)
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var recentLines: [String] = []

        do {
            try process.run()
        } catch {
            await MainActor.run {
                isDownloading = false
                downloadStatus = "无法启动 yt-dlp：\(error.localizedDescription)"
            }
            return
        }

        let handle = pipe.fileHandleForReading
        var buffer = Data()
        do {
            for try await byte in handle.bytes {
                if byte == 10 { // "\n"
                    let line = String(data: buffer, encoding: .utf8) ?? ""
                    buffer.removeAll(keepingCapacity: true)
                    processOutputLine(line, recentLines: &recentLines)
                } else {
                    buffer.append(byte)
                }
            }
            if !buffer.isEmpty {
                let line = String(data: buffer, encoding: .utf8) ?? ""
                processOutputLine(line, recentLines: &recentLines)
            }
        } catch {
            Task { @MainActor in
                downloadProgressText = "读取下载输出失败：\(error.localizedDescription)"
            }
        }

        process.waitUntilExit()
        let finalOutput = recentLines.suffix(8).joined(separator: "\n")

        await MainActor.run {
            isDownloading = false
            if process.terminationStatus == 0 {
                if downloadProgress < 1 {
                    downloadProgress = 1
                }
                downloadStatus = "下载完成，已保存到 \(downloadsPath)"
            } else {
                if finalOutput.isEmpty {
                    downloadStatus = "下载失败（退出码 \(process.terminationStatus)）。"
                } else {
                    downloadStatus = "下载失败（退出码 \(process.terminationStatus)）：\n\(finalOutput)"
                }
            }
        }
    }

    private func processOutputLine(_ line: String, recentLines: inout [String]) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentLines.append(trimmed)
        if recentLines.count > 12 {
            recentLines.removeFirst(recentLines.count - 12)
        }

        if let percent = parsePercent(from: trimmed) {
            Task { @MainActor in
                downloadProgress = percent
                downloadProgressText = trimmed
            }
        } else {
            Task { @MainActor in
                downloadProgressText = trimmed
            }
        }
    }

    private func parsePercent(from line: String) -> Double? {
        guard let percentIndex = line.firstIndex(of: "%") else { return nil }
        let prefix = line[..<percentIndex]
        let number = prefix.split(whereSeparator: { !$0.isNumber && $0 != "." }).last
        guard let number, let value = Double(number) else { return nil }
        return min(max(value / 100.0, 0), 1)
    }

    private func updateImportUI(stage: String? = nil, status: String? = nil, progress: Double? = nil, overall: Double? = nil, detail: String? = nil, filePath: String? = nil) async {
        await MainActor.run {
            if let stage { importStage = stage }
            if let status { importStatus = status }
            if let progress { importProgress = progress }
            if let overall { importOverallProgress = overall }
            if let detail { importProgressText = detail }
            if let filePath { importFilePath = filePath }
        }
    }

    private func makeImportStagingDir() -> URL {
        let base = AppPaths.importStagingDir
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func downloadForImport(url: String, cookiesFile: URL, stagingDir: URL) async throws -> URL {
        let outputTemplate = stagingDir.appendingPathComponent("%(title)s.%(ext)s").path
        let preferredFormat = "bv*[ext=mp4][vcodec^=avc1]+ba[ext=m4a]/b[ext=mp4][vcodec^=avc1]/bv*[ext=mp4]+ba[ext=m4a]/b"
        let args = [
            "--newline",
            "--progress",
            "--no-playlist",
            "--cookies", cookiesFile.path,
            "--format", preferredFormat,
            "--merge-output-format", "mp4",
            "-o", outputTemplate,
            "--print", "after_move:FILEPATH:%(filepath)s",
            url
        ]

        await MainActor.run {
            lastCommand = (["yt-dlp"] + args).joined(separator: " ")
        }

        var resolvedPath: String?
        var recentLines: [String] = []

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yt-dlp"] + args

        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = ([existingPath] + extraPaths)
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw ImportPipelineError.launchFailed("无法启动 yt-dlp：\(error.localizedDescription)")
        }

        let handle = pipe.fileHandleForReading
        var buffer = Data()
        do {
            for try await byte in handle.bytes {
                if byte == 10 { // "\n"
                    let line = String(data: buffer, encoding: .utf8) ?? ""
                    buffer.removeAll(keepingCapacity: true)
                    if let path = extractFilePath(from: line) {
                        resolvedPath = path
                        await updateImportUI(filePath: path)
                    }
                    updateImportFromDownloadLine(line, recentLines: &recentLines)
                } else {
                    buffer.append(byte)
                }
            }
            if !buffer.isEmpty {
                let line = String(data: buffer, encoding: .utf8) ?? ""
                if let path = extractFilePath(from: line) {
                    resolvedPath = path
                    await updateImportUI(filePath: path)
                }
                updateImportFromDownloadLine(line, recentLines: &recentLines)
            }
        } catch {
            await updateImportUI(detail: "读取下载输出失败：\(error.localizedDescription)")
        }

        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let snippet = recentLines.suffix(8).joined(separator: "\n")
            throw ImportPipelineError.downloadFailed(snippet.isEmpty ? "下载失败（退出码 \(process.terminationStatus)）。" : snippet)
        }

        if let resolvedPath, FileManager.default.fileExists(atPath: resolvedPath) {
            return URL(fileURLWithPath: resolvedPath)
        }

        if let fallback = latestFile(in: stagingDir) {
            return fallback
        }

        throw ImportPipelineError.downloadFailed("未找到下载文件。")
    }

    private func updateImportFromDownloadLine(_ line: String, recentLines: inout [String]) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentLines.append(trimmed)
        if recentLines.count > 12 {
            recentLines.removeFirst(recentLines.count - 12)
        }

        if let percent = parsePercent(from: trimmed) {
            Task { [weak self] in
                await self?.updateImportUI(progress: percent, overall: 0.05 + percent * 0.6, detail: trimmed)
            }
        } else {
            Task { [weak self] in
                await self?.updateImportUI(detail: trimmed)
            }
        }
    }

    private func extractFilePath(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "FILEPATH:") {
            let value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if value == "NA" { return nil }
            return value
        }
        if let range = trimmed.range(of: "Destination: ") {
            let value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty { return nil }
            return value
        }
        if let range = trimmed.range(of: "Merging formats into ") {
            let tail = String(trimmed[range.upperBound...])
            let start = tail.firstIndex(of: "\"")
            let end = tail.lastIndex(of: "\"")
            if let start, let end, start < end {
                return String(tail[tail.index(after: start)..<end])
            }
        }
        return nil
    }

    private func latestFile(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var newestURL: URL?
        var newestDate: Date = .distantPast

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }
            let date = values.contentModificationDate ?? .distantPast
            if date > newestDate {
                newestDate = date
                newestURL = fileURL
            }
        }

        return newestURL
    }

    private func transcodeToMp4(inputURL: URL, outputURL: URL, duration: Double) async throws -> URL {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try await runTranscode(
                inputURL: inputURL,
                outputURL: outputURL,
                duration: duration,
                videoArgs: ["-c:v", "h264_videotoolbox", "-q:v", "60", "-pix_fmt", "yuv420p"],
                status: "硬件转码中…"
            )
        } catch {
            await updateImportUI(status: "硬件转码失败，改用软件…", progress: 0, overall: 0.7, detail: "软件转码准备中…")
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try await runTranscode(
                inputURL: inputURL,
                outputURL: outputURL,
                duration: duration,
                videoArgs: ["-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p"],
                status: "软件转码中…"
            )
        }

        return outputURL
    }

    private func runTranscode(
        inputURL: URL,
        outputURL: URL,
        duration: Double,
        videoArgs: [String],
        status: String
    ) async throws {
        await updateImportUI(status: status)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ffmpeg",
            "-y",
            "-i", inputURL.path
        ] + videoArgs + [
            "-c:a", "aac",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            outputURL.path
        ]

        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = ([existingPath] + extraPaths)
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw ImportPipelineError.launchFailed("无法启动 ffmpeg：\(error.localizedDescription)")
        }

        let handle = pipe.fileHandleForReading
        var buffer = Data()
        var recentLines: [String] = []
        var lastOutTime: Double = 0
        var totalDuration: Double = duration
        var lastSpeed: String?

        do {
            for try await byte in handle.bytes {
                if byte == 10 { // "\n"
                    let line = String(data: buffer, encoding: .utf8) ?? ""
                    buffer.removeAll(keepingCapacity: true)
                    if totalDuration <= 0, let parsed = parseDuration(from: line) {
                        totalDuration = parsed
                    }
                    if let speed = parseSpeed(from: line) {
                        lastSpeed = speed
                    }
                    if let outTime = parseOutTimeMs(from: line) {
                        lastOutTime = outTime
                        let progress = totalDuration > 0 ? min(max(outTime / totalDuration, 0), 1) : 0
                        await updateImportUI(progress: progress, overall: 0.7 + progress * 0.2, detail: transcodeDetail(current: outTime, total: totalDuration, speed: lastSpeed))
                    } else if line.hasPrefix("progress=") {
                        await updateImportUI(detail: transcodeDetail(current: lastOutTime, total: totalDuration, speed: lastSpeed))
                    }
                    appendRecent(line, to: &recentLines)
                } else {
                    buffer.append(byte)
                }
            }
            if !buffer.isEmpty {
                let line = String(data: buffer, encoding: .utf8) ?? ""
                if totalDuration <= 0, let parsed = parseDuration(from: line) {
                    totalDuration = parsed
                }
                if let speed = parseSpeed(from: line) {
                    lastSpeed = speed
                }
                if let outTime = parseOutTimeMs(from: line) {
                    lastOutTime = outTime
                    let progress = totalDuration > 0 ? min(max(outTime / totalDuration, 0), 1) : 0
                    await updateImportUI(progress: progress, overall: 0.7 + progress * 0.2, detail: transcodeDetail(current: outTime, total: totalDuration, speed: lastSpeed))
                }
                appendRecent(line, to: &recentLines)
            }
        } catch {
            await updateImportUI(detail: "读取转码输出失败：\(error.localizedDescription)")
        }

        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let snippet = recentLines.suffix(8).joined(separator: "\n")
            throw ImportPipelineError.transcodeFailed(snippet.isEmpty ? "转码失败（退出码 \(process.terminationStatus)）。" : snippet)
        }

        if totalDuration > 0 && lastOutTime < totalDuration {
            await updateImportUI(progress: 1, overall: 0.9, detail: transcodeDetail(current: totalDuration, total: totalDuration, speed: lastSpeed))
        }
    }

    private func appendRecent(_ line: String, to recentLines: inout [String]) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentLines.append(trimmed)
        if recentLines.count > 12 {
            recentLines.removeFirst(recentLines.count - 12)
        }
    }

    private func parseOutTimeMs(from line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("out_time_ms=") {
            let value = trimmed.replacingOccurrences(of: "out_time_ms=", with: "")
            guard let ms = Double(value) else { return nil }
            return ms / 1_000_000.0
        }
        if trimmed.hasPrefix("out_time_us=") {
            let value = trimmed.replacingOccurrences(of: "out_time_us=", with: "")
            guard let us = Double(value) else { return nil }
            return us / 1_000_000.0
        }
        return nil
    }

    private func parseDuration(from line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "Duration: ") else { return nil }
        let tail = trimmed[range.upperBound...]
        let timePart = tail.split(separator: ",").first
        guard let timePart else { return nil }
        return parseTimecode(String(timePart))
    }

    private func parseSpeed(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("speed=") else { return nil }
        let value = trimmed.replacingOccurrences(of: "speed=", with: "").trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func parseTimecode(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private func transcodeDetail(current: Double, total: Double, speed: String?) -> String {
        if total <= 0 {
            if let speed, !speed.isEmpty {
                return "转码进度：\(formatTime(current)) 速度 \(speed)"
            }
            return "转码进度：\(formatTime(current))"
        }
        let percent = min(max(current / total, 0), 1) * 100
        if let speed, !speed.isEmpty {
            return String(format: "转码进度：%@ / %@ (%.1f%%) 速度 %@", formatTime(current), formatTime(total), percent, speed)
        }
        return String(format: "转码进度：%@ / %@ (%.1f%%)", formatTime(current), formatTime(total), percent)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func mediaDuration(url: URL) async -> Double {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            if duration.isIndefinite || duration.seconds.isNaN {
                return 0
            }
            return duration.seconds
        } catch {
            return 0
        }
    }

    private func isDirectlySupported(url: URL) async -> Bool {
        let ext = url.pathExtension.lowercased()
        if importSupportedAudioExtensions.contains(ext) {
            return (try? AVAudioFile(forReading: url)) != nil
        }
        guard importSupportedVideoExtensions.contains(ext) else {
            return false
        }
        let asset = AVAsset(url: url)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        let isExportable = (try? await asset.load(.isExportable)) ?? false
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        return (isPlayable || isExportable) && !audioTracks.isEmpty
    }

    @MainActor
    private func exportCookiesFile() async throws -> URL {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        var lines: [String] = [
            "# Netscape HTTP Cookie File",
            "# Generated by EasyLearnEnglish for yt-dlp",
            ""
        ]

        for cookie in cookies {
            let domain = cookie.domain
            let includeSubdomains = domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let path = cookie.path
            let secure = cookie.isSecure ? "TRUE" : "FALSE"
            let expires = cookie.expiresDate?.timeIntervalSince1970 ?? 0
            let expiryString = String(Int(expires))
            let name = cookie.name.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            let value = cookie.value.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")

            lines.append("\(domain)\t\(includeSubdomains)\t\(path)\t\(secure)\t\(expiryString)\t\(name)\t\(value)")
        }

        let content = lines.joined(separator: "\n")
        let fileURL = AppPaths.ytDlpCookiesFile
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

private enum ImportPipelineError: LocalizedError {
    case launchFailed(String)
    case downloadFailed(String)
    case transcodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message),
             .downloadFailed(let message),
             .transcodeFailed(let message):
            return message
        }
    }
}

final class WebViewStore: ObservableObject {
    let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView
    }
}

struct OnlineResourcesView: View {
    @ObservedObject var store: OnlineResourcesStore
    @ObservedObject var webStore: WebViewStore
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if webStore.webView.canGoBack {
                        webStore.webView.goBack()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)

                Button {
                    if webStore.webView.canGoForward {
                        webStore.webView.goForward()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)

                Button {
                    webStore.webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                TextField("输入网址", text: $store.address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { navigate() }

                Button("前往") {
                    navigate()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 8)

            ZStack(alignment: .topTrailing) {
                WebViewRepresentable(
                    webView: webStore.webView,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    currentURL: $store.currentURL
                )
                .cornerRadius(8)

                if isLoading {
                    ProgressView()
                        .padding(8)
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            navigateIfNeeded()
        }
    }

    private func navigateIfNeeded() {
        if webStore.webView.url == nil {
            navigate()
        }
    }

    private func navigate() {
        let trimmed = store.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }
        if webStore.webView.url?.absoluteString != url.absoluteString {
            webStore.webView.load(URLRequest(url: url))
        }
    }
}

struct OnlineResourcesDetailView: View {
    @ObservedObject var store: OnlineResourcesStore
    @StateObject private var tools = ToolsStatusModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前链接")
                .font(.headline)
            Text(store.currentURL.isEmpty ? "暂无" : store.currentURL)
                .textSelection(.enabled)
                .font(.footnote)
                .foregroundColor(store.currentURL.isEmpty ? .secondary : .primary)

            Divider()

            Text("下载")
                .font(.headline)

            Button(store.isDownloading ? "下载中…" : "下载到本地") {
                store.downloadCurrentURL()
            }
            .disabled(store.isDownloading)

            if store.isDownloading || store.downloadProgress > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: store.downloadProgress)
                    Text(String(format: "%.1f%%", store.downloadProgress * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !store.downloadProgressText.isEmpty {
                        Text(store.downloadProgressText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if !store.lastCommand.isEmpty {
                Text(store.lastCommand)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if !store.downloadStatus.isEmpty {
                Text(store.downloadStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            Text("导入")
                .font(.headline)

            Button(store.isImporting ? "导入中…" : "导入到媒体库") {
                store.importCurrentURL()
            }
            .disabled(store.isImporting)

            if store.isImporting || store.importOverallProgress > 0 || !store.importStatus.isEmpty || !store.importStage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !store.importStage.isEmpty {
                        Text("阶段：\(store.importStage)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: store.importOverallProgress)
                    Text(String(format: "总体 %.1f%%", store.importOverallProgress * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ProgressView(value: store.importProgress)
                    Text(String(format: "当前阶段 %.1f%%", store.importProgress * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !store.importProgressText.isEmpty {
                        Text(store.importProgressText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    if !store.importFilePath.isEmpty {
                        Text("路径：\(store.importFilePath)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    if !store.importStatus.isEmpty {
                        Text(store.importStatus)
                            .font(.caption2)
                            .foregroundColor(store.importStage == "失败" ? .red : .secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Divider()

            Text("工具版本")
                .font(.headline)
            toolRow(title: "yt-dlp", result: tools.ytDlp)
            toolRow(title: "ffmpeg", result: tools.ffmpeg)
            HStack {
                if let last = tools.lastUpdated {
                    Text("更新于：\(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("更新于：--")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("刷新") {
                    tools.refresh()
                }
            }

            Spacer()
        }
        .padding(16)
        .onAppear {
            tools.refresh()
        }
        .onChange(of: store.currentURL) { _ in
            store.resetForNewResource()
        }
    }

    @ViewBuilder
    private func toolRow(title: String, result: ToolCheckResult?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .frame(width: 72, alignment: .leading)
                Spacer()
                if let result {
                    Text(result.found ? "已安装" : "未安装")
                        .foregroundColor(result.found ? .secondary : .red)
                } else {
                    Text("检测中…")
                        .foregroundColor(.secondary)
                }
            }
            if let result, result.found {
                if !result.version.isEmpty {
                    Text(result.version)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let path = result.path {
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if let result, let error = result.error, !error.isEmpty {
                Text("错误：\(error)")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var currentURL: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        context.coordinator.startObserving(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebViewRepresentable
        private var urlObservation: NSKeyValueObservation?

        init(parent: WebViewRepresentable) {
            self.parent = parent
        }

        func startObserving(_ webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                self?.updateNavigationState(from: webView)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateNavigationState(from: webView)
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateNavigationState(from: webView)
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateNavigationState(from: webView)
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateNavigationState(from: webView)
            parent.isLoading = false
        }

        func updateNavigationState(from webView: WKWebView) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            if let url = webView.url?.absoluteString, !url.isEmpty {
                parent.currentURL = url
            }
        }
    }
}
