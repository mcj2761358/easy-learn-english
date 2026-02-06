import SwiftUI
import AppKit

struct ShadowingView: View {
    @ObservedObject var appModel: AppViewModel
    @State private var draftStart: Double = 0
    @State private var draftEnd: Double = 5
    @State private var expandedSegmentIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                creationCard
                segmentList
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            if draftEnd <= draftStart {
                draftEnd = draftStart + 5
            }
        }
    }

    private var creationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("跟读片段")
                .font(.headline)
            HStack(spacing: 10) {
                TimecodeField(title: "开始", seconds: $draftStart)
                Button("用当前时间") {
                    draftStart = appModel.currentPlaybackSeconds
                    if draftEnd <= draftStart {
                        draftEnd = min(draftStart + 5, appModel.selectedMedia?.duration ?? draftStart + 5)
                    }
                }
                TimecodeField(title: "结束", seconds: $draftEnd)
                Button("用当前时间") {
                    draftEnd = appModel.currentPlaybackSeconds
                }
                Spacer()
                Button("创建片段") {
                    appModel.addShadowingSegment(start: draftStart, end: draftEnd, title: "")
                    if let media = appModel.selectedMedia {
                        draftStart = min(appModel.currentPlaybackSeconds, media.duration)
                        draftEnd = min(draftStart + 5, media.duration)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(10)
    }

    private var segmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("片段列表")
                    .font(.subheadline)
                Spacer()
                if appModel.shadowingSegments.isEmpty {
                    Text("暂无片段")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(appModel.shadowingSegments) { segment in
                ShadowingSegmentRow(
                    appModel: appModel,
                    segment: segment,
                    isExpanded: expandedSegmentIDs.contains(segment.id),
                    onToggleExpanded: { toggleExpanded(segment.id) }
                )
                if expandedSegmentIDs.contains(segment.id) {
                    ShadowingTranscriptBlock(
                        appModel: appModel,
                        segment: segment
                    )
                }
            }
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedSegmentIDs.contains(id) {
            expandedSegmentIDs.remove(id)
        } else {
            expandedSegmentIDs.insert(id)
        }
    }

    private func transcriptSegments(in transcript: Transcript, start: Double, end: Double) -> [(index: Int, segment: TranscriptSegment)] {
        transcript.segments.enumerated().compactMap { index, segment in
            if segment.end >= start && segment.start <= end {
                return (index: index, segment: segment)
            }
            return nil
        }
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

private struct ShadowingSegmentRow: View {
    @ObservedObject var appModel: AppViewModel
    let segment: ShadowingSegment
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    @State private var isEditingTitle: Bool = false
    @State private var draftTitle: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(timeRangeText)
                .font(.caption)
                .foregroundColor(.secondary)
            if isEditingTitle {
                TextField("备注", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160, maxWidth: 260)
                    .onSubmit {
                        saveTitle()
                    }
                Button {
                    saveTitle()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("保存备注")
            } else {
                Text(segment.title.isEmpty ? "备注" : segment.title)
                    .font(.caption)
                    .foregroundColor(segment.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    draftTitle = segment.title
                    isEditingTitle = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("编辑备注")
            }
            Spacer()
            Button("播放") {
                appModel.playSegment(segment)
            }
            Button(appModel.loopSegmentID == segment.id ? "停止循环" : "循环") {
                appModel.toggleLoop(for: segment)
            }
            Button(isExpanded ? "隐藏字幕" : "显示字幕") {
                onToggleExpanded()
            }
            Button("删除", role: .destructive) {
                appModel.deleteShadowingSegment(id: segment.id)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(8)
        .onAppear {
            if draftTitle.isEmpty {
                draftTitle = segment.title
            }
        }
        .onChange(of: segment.title) { newValue in
            if !isEditingTitle {
                draftTitle = newValue
            }
        }
    }

    private var timeRangeText: String {
        "\(formatTimestamp(segment.start)) - \(formatTimestamp(segment.end))"
    }

    private func saveTitle() {
        var updated = segment
        updated.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        appModel.updateShadowingSegment(updated)
        isEditingTitle = false
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

private struct ShadowingTranscriptBlock: View {
    @ObservedObject var appModel: AppViewModel
    let segment: ShadowingSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("跟读内容")
                .font(.caption)
                .foregroundColor(.secondary)
            if let transcript = appModel.activeTranscript {
                let filtered = transcriptSegments(in: transcript, start: segment.start, end: segment.end)
                if filtered.isEmpty {
                    Text("该片段范围内暂无字幕。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filtered, id: \.index) { item in
                            ShadowingTranscriptRow(
                                appModel: appModel,
                                segment: item.segment,
                                segmentIndex: item.index
                            )
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂无字幕，无法生成跟读文本。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("请先完成整段转写，或稍后再试。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private func transcriptSegments(in transcript: Transcript, start: Double, end: Double) -> [(index: Int, segment: TranscriptSegment)] {
        transcript.segments.enumerated().compactMap { index, segment in
            if segment.end >= start && segment.start <= end {
                return (index: index, segment: segment)
            }
            return nil
        }
    }
}

private struct ShadowingTranscriptRow: View {
    @ObservedObject var appModel: AppViewModel
    let segment: TranscriptSegment
    let segmentIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(Array(segment.tokens.enumerated()), id: \.offset) { tokenIndex, token in
                    ShadowingTokenView(
                        token: token,
                        isSelected: appModel.isTokenSelected(segmentIndex: segmentIndex, tokenIndex: tokenIndex)
                    )
                    .onTapGesture {
                        let extend = NSEvent.modifierFlags.contains(.shift)
                        appModel.selectToken(segmentIndex: segmentIndex, tokenIndex: tokenIndex, extend: extend)
                    }
                }
            }
            HStack(spacing: 8) {
                Text(timeRangeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    appModel.seek(to: segment.start)
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private var timeRangeText: String {
        "\(formatTimestamp(segment.start)) - \(formatTimestamp(segment.end))"
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

private struct ShadowingTokenView: View {
    let token: String
    let isSelected: Bool

    var body: some View {
        Text(token)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.12))
            .cornerRadius(6)
    }
}

private struct TimecodeField: View {
    let title: String
    @Binding var seconds: Double
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .frame(width: 32, alignment: .leading)
            TextField("00:00:00", text: $text, onCommit: applyText)
                .frame(width: 90)
                .textFieldStyle(.roundedBorder)
        }
        .onAppear {
            text = format(seconds)
        }
        .onChange(of: seconds) { newValue in
            text = format(newValue)
        }
    }

    private func applyText() {
        if let value = parse(text) {
            seconds = value
        } else {
            text = format(seconds)
        }
    }

    private func format(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private func parse(_ value: String) -> Double? {
        let parts = value.split(separator: ":").map(String.init)
        if parts.count == 1, let secs = Double(parts[0]) {
            return secs
        }
        if parts.count == 2, let minutes = Double(parts[0]), let secs = Double(parts[1]) {
            return minutes * 60 + secs
        }
        if parts.count == 3,
           let hours = Double(parts[0]),
           let minutes = Double(parts[1]),
           let secs = Double(parts[2]) {
            return hours * 3600 + minutes * 60 + secs
        }
        return nil
    }
}
