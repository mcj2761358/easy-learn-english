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
            }
            .background(Color.black.opacity(0.05))

            if appModel.isTranscribing || appModel.transcriptionProgress != nil {
                TranscriptionProgressView(
                    providerName: appModel.settings.provider.displayName,
                    progress: appModel.transcriptionProgress
                )
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            if let error = appModel.transcriptionError,
               (appModel.activeTranscript?.segments.isEmpty ?? true) {
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

            if !appModel.isTranscribing, appModel.selectedMedia != nil, appModel.activeTranscript == nil {
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
                .id(appModel.selectedMedia?.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "是否改用联网识别？",
            isPresented: Binding(
                get: { appModel.onlineFallbackPrompt != nil },
                set: { if !$0 { appModel.cancelOnlineFallback() } }
            )
        ) {
            if let prompt = appModel.onlineFallbackPrompt {
                Button("改用联网识别") {
                    appModel.confirmOnlineFallback(for: prompt.mediaID)
                }
                Button("取消", role: .cancel) {
                    appModel.cancelOnlineFallback()
                }
            } else {
                Button("关闭", role: .cancel) {}
            }
        } message: {
            if let prompt = appModel.onlineFallbackPrompt {
                Text("\(prompt.reason)\n联网识别可能产生费用。")
            } else {
                Text("联网识别可能产生费用。")
            }
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

private struct TranscriptionProgressView: View {
    let providerName: String
    let progress: TranscriptionProgress?

    var body: some View {
        let stage = progress?.stage ?? .preparing
        let title = stage.title
        let detail = progress?.resolvedDetail ?? stage.detail
        let fraction = progress?.fraction

        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            VStack(alignment: .leading, spacing: 4) {
                AnimatedDotsText(text: title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    StepChip(title: "提取音频", state: stepState(for: .extractingAudio, stage: stage))
                    StepChip(title: "识别中", state: stepState(for: .recognizingOnDevice, stage: stage))
                    StepChip(title: "解析字幕", state: stepState(for: .parsingSegments, stage: stage))
                }
                VStack(alignment: .leading, spacing: 4) {
                    progressRow(title: "提取音频", value: stepProgress(for: .extractingAudio, stage: stage, fraction: fraction))
                    progressRow(title: "识别中", value: stepProgress(for: .recognizingOnDevice, stage: stage, fraction: fraction))
                    progressRow(title: "解析字幕", value: stepProgress(for: .parsingSegments, stage: stage, fraction: fraction))
                }
                Text("使用 \(providerName)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(10)
    }

    private func stepState(for step: TranscriptionStage, stage: TranscriptionStage) -> StepState {
        switch step {
        case .extractingAudio:
            if stage.rawValue >= TranscriptionStage.recognizingOnDevice.rawValue {
                return .done
            }
            if stage.rawValue >= TranscriptionStage.loadingMedia.rawValue {
                return .active
            }
            return .pending
        case .recognizingOnDevice:
            if stage.rawValue >= TranscriptionStage.parsingSegments.rawValue {
                return .done
            }
            if stage == .recognizingOnDevice || stage == .recognizingServer {
                return .active
            }
            return .pending
        case .parsingSegments:
            if stage.rawValue >= TranscriptionStage.savingTranscript.rawValue {
                return .done
            }
            if stage == .parsingSegments || stage == .savingTranscript {
                return .active
            }
            return .pending
        default:
            return .pending
        }
    }

    private func stepProgress(for step: TranscriptionStage, stage: TranscriptionStage, fraction: Double?) -> Double? {
        switch step {
        case .extractingAudio:
            if stage.rawValue < TranscriptionStage.extractingAudio.rawValue {
                return 0
            }
            if stage == .extractingAudio {
                guard let fraction else { return nil }
                return min(max(fraction, 0), 1)
            }
            return 1
        case .recognizingOnDevice:
            if stage == .recognizingOnDevice || stage == .recognizingServer {
                guard let fraction else { return nil }
                return min(max(fraction, 0), 1)
            }
            if stage.rawValue > TranscriptionStage.recognizingServer.rawValue {
                return 1
            }
            return 0
        case .parsingSegments:
            if stage == .parsingSegments {
                guard let fraction else { return nil }
                return min(max(fraction, 0), 1)
            }
            if stage.rawValue > TranscriptionStage.parsingSegments.rawValue {
                return 1
            }
            return 0
        default:
            return 0
        }
    }

    @ViewBuilder
    private func progressRow(title: String, value: Double?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .frame(width: 56, alignment: .leading)
            if let value {
                ProgressView(value: value)
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            } else {
                ProgressView()
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

private struct AnimatedDotsText: View {
    let text: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 2) % 3
            let dots = String(repeating: "·", count: tick + 1)
            Text("\(text)\(dots)")
        }
    }
}

private enum StepState {
    case pending
    case active
    case done
}

private struct StepChip: View {
    let title: String
    let state: StepState

    var body: some View {
        HStack(spacing: 4) {
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.caption2)
            } else if state == .active {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Circle()
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(backgroundColor)
        .cornerRadius(6)
    }

    private var backgroundColor: Color {
        switch state {
        case .pending:
            return Color.gray.opacity(0.15)
        case .active:
            return Color.accentColor.opacity(0.2)
        case .done:
            return Color.green.opacity(0.2)
        }
    }
}
