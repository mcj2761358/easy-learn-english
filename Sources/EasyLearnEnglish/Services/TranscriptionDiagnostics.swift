import Foundation
import AVFoundation

struct TranscriptionDiagnostics {
    static func run(mediaURL: URL) async -> String {
        var lines: [String] = []

        lines.append("媒体路径: \(mediaURL.path)")
        lines.append("存在: \(FileManager.default.fileExists(atPath: mediaURL.path) ? "是" : "否")")
        lines.append("可读: \(FileManager.default.isReadableFile(atPath: mediaURL.path) ? "是" : "否")")

        if let attrs = try? FileManager.default.attributesOfItem(atPath: mediaURL.path),
           let size = attrs[.size] as? NSNumber {
            lines.append("文件大小: \(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))")
        }

        let asset = AVAsset(url: mediaURL)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        let isExportable = (try? await asset.load(.isExportable)) ?? false
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        lines.append("可播放: \(isPlayable ? "是" : "否")")
        lines.append("可导出: \(isExportable ? "是" : "否")")
        lines.append(String(format: "时长: %.2fs", duration))

        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        lines.append("音轨数量: \(audioTracks.count)")
        lines.append("视频轨数量: \(videoTracks.count)")

        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let hasM4A = presets.contains(AVAssetExportPresetAppleM4A)
        lines.append("支持导出 M4A: \(hasM4A ? "是" : "否")")

        return lines.joined(separator: "\n")
    }
}
