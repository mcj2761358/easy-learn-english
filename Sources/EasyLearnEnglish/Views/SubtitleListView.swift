import SwiftUI
import AppKit

struct SubtitleListView: View {
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        Group {
            if let transcript = appModel.transcript {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(transcript.segments.enumerated()), id: \..element.id) { index, segment in
                                SubtitleSegmentRow(
                                    appModel: appModel,
                                    segment: segment,
                                    segmentIndex: index,
                                    isActive: index == appModel.currentSegmentIndex
                                )
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: appModel.currentSegmentIndex) { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("暂无字幕")
                        .foregroundColor(.secondary)
                    Text("可点击下方“重新转写”按钮重试。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

private struct SubtitleSegmentRow: View {
    @ObservedObject var appModel: AppViewModel
    let segment: TranscriptSegment
    let segmentIndex: Int
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(Array(segment.tokens.enumerated()), id: \..offset) { tokenIndex, token in
                    WordTokenView(
                        token: token,
                        isSelected: appModel.isTokenSelected(segmentIndex: segmentIndex, tokenIndex: tokenIndex)
                    )
                    .onTapGesture {
                        let extend = NSEvent.modifierFlags.contains(.shift)
                        appModel.selectToken(segmentIndex: segmentIndex, tokenIndex: tokenIndex, extend: extend)
                    }
                }
            }
            Text(timeRangeText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(8)
    }

    private var timeRangeText: String {
        String(format: "%.2f - %.2f", segment.start, segment.end)
    }
}

private struct WordTokenView: View {
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
