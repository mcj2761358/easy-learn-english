import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        Form {
            Section("转写提供商") {
                Picker("提供商", selection: $settings.provider) {
                    ForEach(TranscriptionProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("语音识别权限") {
                if !SpeechAuthorizationHelper.hasUsageDescription {
                    Text("未检测到权限说明（NSSpeechRecognitionUsageDescription）。需要在 Xcode 的 Target → Info 中添加后才能授权。")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                HStack {
                    Text("当前状态")
                    Spacer()
                    Text(SpeechAuthorizationHelper.statusText(SpeechAuthorizationHelper.status()))
                        .foregroundColor(.secondary)
                }
                Button("请求授权") {
                    Task {
                        _ = await SpeechAuthorizationHelper.request()
                    }
                }
                .disabled(!SpeechAuthorizationHelper.hasUsageDescription)
            }

            Section("API Key") {
                TextField("OpenAI", text: $settings.openaiApiKey)
                TextField("Gemini", text: $settings.geminiApiKey)
                TextField("GLM", text: $settings.glmApiKey)
                TextField("Kimi", text: $settings.kimiApiKey)
                TextField("MinMax", text: $settings.minmaxApiKey)
            }

            Section {
                Text("Apple Speech 为默认选项，支持时优先使用本地识别以降低成本。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            StorageManagementView()
        }
        .padding(12)
        .frame(width: 420)
    }
}
