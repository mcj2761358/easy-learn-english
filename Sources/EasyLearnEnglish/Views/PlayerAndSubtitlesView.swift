import SwiftUI
import AVKit

struct PlayerAndSubtitlesView: View {
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if appModel.selectedMedia != nil {
                    VideoPlayer(player: appModel.player)
                        .frame(minHeight: 240)
                } else {
                    Text("请选择媒体开始")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if appModel.isTranscribing {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("正在转写…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .background(Color.black.opacity(0.05))

            if let error = appModel.transcriptionError,
               (appModel.transcript?.segments.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.title)
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error.message)
                        .font(.caption)
                        .foregroundColor(.red)
                    if !error.actions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(error.actions) { action in
                                Button(action.title) {
                                    SettingsOpener.open(action)
                                }
                            }
                        }
                    }
                    Button("诊断") {
                        appModel.runDiagnostics()
                    }
                }
                .padding(8)
            }

            if !appModel.isTranscribing, appModel.selectedMedia != nil, appModel.transcript == nil {
                HStack {
                    Button("重新转写") {
                        appModel.retranscribe()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()
            SubtitleListView(appModel: appModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $appModel.showDiagnostics) {
            VStack(alignment: .leading, spacing: 12) {
                Text("转写诊断")
                    .font(.headline)
                ScrollView {
                    Text(appModel.diagnosticsText ?? "暂无诊断信息")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("关闭") {
                        appModel.showDiagnostics = false
                    }
                }
            }
            .padding(16)
            .frame(width: 520, height: 320)
        }
    }
}
