import SwiftUI
import WebKit
import Foundation

final class OnlineResourcesStore: ObservableObject {
    @Published var currentURL: String = ""
    @Published var address: String = "https://www.youtube.com"
    @Published var downloadStatus: String = ""
    @Published var isDownloading = false
    @Published var lastCommand: String = ""
    @Published var downloadProgress: Double = 0
    @Published var downloadProgressText: String = ""

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
