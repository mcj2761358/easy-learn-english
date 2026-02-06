import Foundation
import AppKit

struct TranscriptionErrorInfo: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let actions: [TranscriptionErrorAction]
}

enum TranscriptionErrorAction: Identifiable, Equatable {
    case openSpeechPrivacy
    case openSiriSettings

    var id: String { title }

    var title: String {
        switch self {
        case .openSpeechPrivacy:
            return "打开语音识别设置"
        case .openSiriSettings:
            return "打开 Siri 与听写设置"
        }
    }
}

enum TranscriptionErrorMapper {
    static func describe(_ error: Error) -> TranscriptionErrorInfo {
        if let te = error as? TranscriptionError {
            switch te {
            case .authorizationDenied:
                return TranscriptionErrorInfo(
                    title: "语音识别权限未授权",
                    message: "请到「系统设置 → 隐私与安全 → 语音识别」中允许 EasyLearnEnglish。",
                    actions: [.openSpeechPrivacy]
                )
            case .siriDictationDisabled:
                return TranscriptionErrorInfo(
                    title: "Siri 与听写已关闭",
                    message: "请在系统设置中启用 Siri 和听写功能，然后重试。",
                    actions: [.openSiriSettings]
                )
            case .speechNotAvailable:
                return TranscriptionErrorInfo(
                    title: "语音识别不可用",
                    message: "系统语音识别当前不可用，请检查系统语言或稍后重试。",
                    actions: []
                )
            case .noSpeechDetected:
                return TranscriptionErrorInfo(
                    title: "未检测到语音",
                    message: "已尝试识别但未检测到人声。建议：确认音量正常、音轨未损坏，或切换为联网识别后重试。",
                    actions: []
                )
            case .unsupported:
                return TranscriptionErrorInfo(
                    title: "媒体不受支持",
                    message: "请尝试更换音频格式，或先转换为常见格式再导入。",
                    actions: []
                )
            case .onlineFallbackRequired(let reason):
                return TranscriptionErrorInfo(
                    title: "需要确认联网识别",
                    message: reason,
                    actions: []
                )
            case .failed(let message):
                return TranscriptionErrorInfo(
                    title: "转写失败",
                    message: message,
                    actions: []
                )
            }
        }

        let nsError = error as NSError
        if nsError.domain == "kLSRErrorDomain", nsError.code == 301 {
            return TranscriptionErrorInfo(
                title: "Siri 与听写已关闭",
                message: "请在系统设置中启用 Siri 和听写功能，然后重试。",
                actions: [.openSiriSettings]
            )
        }

        return TranscriptionErrorInfo(
            title: "转写失败",
            message: nsError.localizedDescription,
            actions: []
        )
    }
}

enum SettingsOpener {
    static func open(_ action: TranscriptionErrorAction) {
        let urlString: String
        switch action {
        case .openSpeechPrivacy:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .openSiriSettings:
            urlString = "x-apple.systempreferences:com.apple.preference.siri"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
