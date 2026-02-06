import SwiftUI
import Speech

struct SettingsDetailView: View {
    let section: SettingsSection
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            Group {
                switch section {
                case .provider:
                    ProviderSettingsView(settings: settings)
                case .tools:
                    ToolsSettingsView()
                case .storage:
                    StorageSettingsView()
                }
            }
            .padding(12)
        }
    }
}

struct ProviderSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: "转写提供商") {
                HStack {
                    rowLabel("提供商")
                    Picker("", selection: $settings.provider) {
                        ForEach(TranscriptionProviderKind.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Spacer()
                }
            }

            SettingsCard(title: "语音识别权限") {
                let status = SpeechAuthorizationHelper.status()
                if !SpeechAuthorizationHelper.hasUsageDescription {
                    Text("未检测到权限说明（NSSpeechRecognitionUsageDescription）。需要在 Xcode 的 Target → Info 中添加后才能授权。")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                HStack {
                    rowLabel("当前状态")
                    Text(SpeechAuthorizationHelper.statusText(status))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(buttonTitle(for: status)) {
                        handleSpeechAuthorization(status)
                    }
                    .disabled(!SpeechAuthorizationHelper.hasUsageDescription)
                }
            }

            SettingsCard(title: "API Key") {
                labeledField("OpenAI", text: $settings.openaiApiKey)
                labeledField("Gemini", text: $settings.geminiApiKey)
                labeledField("GLM", text: $settings.glmApiKey)
                labeledField("Kimi", text: $settings.kimiApiKey)
                labeledField("MinMax", text: $settings.minmaxApiKey)
                Text("Apple Speech 为默认选项，支持时优先使用本地识别以降低成本。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SettingsCard(title: "翻译 API") {
                labeledField("有道 AppKey", text: $settings.youdaoAppKey)
                labeledField("有道 Secret", text: $settings.youdaoAppSecret)
                labeledField("百度 AppID", text: $settings.baiduAppId)
                labeledField("百度 Key", text: $settings.baiduAppSecret)
                labeledField("微软 Key", text: $settings.azureTranslatorKey)
                labeledField("微软 Region", text: $settings.azureTranslatorRegion)
                Text("有道/百度/微软翻译需要在各平台申请 Key。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            rowLabel(title)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: 92, alignment: .leading)
    }

    private func buttonTitle(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied, .restricted:
            return "打开语音识别设置"
        case .authorized:
            return "已授权"
        case .notDetermined:
            return "请求授权"
        @unknown default:
            return "请求授权"
        }
    }

    private func handleSpeechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined:
            Task {
                _ = await SpeechAuthorizationHelper.request()
            }
        case .denied, .restricted:
            SettingsOpener.open(.openSpeechPrivacy)
        case .authorized:
            break
        @unknown default:
            Task {
                _ = await SpeechAuthorizationHelper.request()
            }
        }
    }
}

struct ToolsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: "外部工具") {
                Text("yt-dlp 和 ffmpeg 版本信息已移动到“在线资源”右侧。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct StorageSettingsView: View {
    @StateObject private var storage = StorageUsageModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: "存储") {
                storageRow(
                    title: "媒体缓存",
                    path: AppPaths.mediaDir.path,
                    size: storage.mediaBytes.byteCountString,
                    openAction: storage.openMediaFolder
                )

                storageRow(
                    title: "导入暂存",
                    path: AppPaths.importStagingDir.path,
                    size: storage.importStagingBytes.byteCountString,
                    openAction: storage.openImportStagingFolder
                )

                storageRow(
                    title: "字幕缓存",
                    path: AppPaths.transcriptsDir.path,
                    size: storage.transcriptBytes.byteCountString,
                    openAction: storage.openTranscriptsFolder
                )

                storageRow(
                    title: "媒体库索引",
                    path: AppPaths.libraryFile.path,
                    size: storage.libraryBytes.byteCountString,
                    openAction: storage.openLibraryFile
                )

                storageRow(
                    title: "生词本",
                    path: AppPaths.vocabularyFile.path,
                    size: storage.vocabularyBytes.byteCountString,
                    openAction: storage.openVocabularyFile
                )

                storageRow(
                    title: "释义缓存",
                    path: AppPaths.translationCacheFile.path,
                    size: storage.translationCacheBytes.byteCountString,
                    openAction: storage.openTranslationCacheFile
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("内置浏览器 Cookies")
                            .font(.headline)
                        Spacer()
                        Text(storage.cookiesBytes.byteCountString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("打开") {
                            storage.openCookiesFile()
                        }
                        Button("清除") {
                            storage.clearCookiesFile()
                        }
                    }
                    Text(AppPaths.ytDlpCookiesFile.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)

                HStack {
                    if let last = storage.lastUpdated {
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
                        storage.refresh()
                    }
                }
            }

        }
        .onAppear {
            storage.refresh()
        }
    }

    private func storageRow(title: String, path: String, size: String, openAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(size)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("打开") {
                    openAction()
                }
            }
            Text(path)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(12)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(10)
    }
}
