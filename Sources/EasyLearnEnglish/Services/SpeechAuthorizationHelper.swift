import Foundation
import Speech

enum SpeechAuthorizationHelper {
    static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
    }

    static func status() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static func statusText(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限制"
        case .notDetermined:
            return "未请求"
        @unknown default:
            return "未知"
        }
    }

    static func request() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
