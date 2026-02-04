import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("transcriptionProvider") private var providerRaw: String = TranscriptionProviderKind.appleSpeech.rawValue
    @AppStorage("openaiApiKey") var openaiApiKey: String = ""
    @AppStorage("geminiApiKey") var geminiApiKey: String = ""
    @AppStorage("glmApiKey") var glmApiKey: String = ""
    @AppStorage("kimiApiKey") var kimiApiKey: String = ""
    @AppStorage("minmaxApiKey") var minmaxApiKey: String = ""

    @Published var provider: TranscriptionProviderKind = .appleSpeech {
        didSet {
            providerRaw = provider.rawValue
        }
    }

    init() {
        provider = TranscriptionProviderKind(rawValue: providerRaw) ?? .appleSpeech
    }
}
