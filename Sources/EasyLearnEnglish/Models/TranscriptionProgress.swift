import Foundation

enum TranscriptionStage: Int, CaseIterable {
    case preparing = 0
    case requestingPermission
    case loadingMedia
    case extractingAudio
    case recognizingOnDevice
    case recognizingServer
    case parsingSegments
    case savingTranscript
    case completed

    var title: String {
        switch self {
        case .preparing:
            return "准备转写"
        case .requestingPermission:
            return "请求语音识别权限"
        case .loadingMedia:
            return "读取媒体信息"
        case .extractingAudio:
            return "提取音频"
        case .recognizingOnDevice:
            return "识别中（本地）"
        case .recognizingServer:
            return "识别中（联网）"
        case .parsingSegments:
            return "解析字幕"
        case .savingTranscript:
            return "保存字幕"
        case .completed:
            return "完成"
        }
    }

    var detail: String {
        switch self {
        case .preparing:
            return "初始化转写流程"
        case .requestingPermission:
            return "等待系统语音识别权限"
        case .loadingMedia:
            return "检查文件与音轨"
        case .extractingAudio:
            return "从媒体中导出音频"
        case .recognizingOnDevice:
            return "使用本地模型识别"
        case .recognizingServer:
            return "使用联网模型识别"
        case .parsingSegments:
            return "生成字幕与分词"
        case .savingTranscript:
            return "写入字幕缓存"
        case .completed:
            return "已完成"
        }
    }
}

struct TranscriptionProgress: Equatable {
    let stage: TranscriptionStage
    let detail: String?

    init(stage: TranscriptionStage, detail: String? = nil) {
        self.stage = stage
        self.detail = detail
    }

    var resolvedDetail: String {
        detail ?? stage.detail
    }
}
