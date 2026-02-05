import SwiftUI
import AppKit

@main
struct EasyLearnEnglishApp: App {
    @StateObject private var mediaLibrary = MediaLibrary()
    @StateObject private var vocabularyStore = VocabularyStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var appModel: AppViewModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let mediaLibrary = MediaLibrary()
        let vocabularyStore = VocabularyStore()
        let settings = SettingsStore()
        _mediaLibrary = StateObject(wrappedValue: mediaLibrary)
        _vocabularyStore = StateObject(wrappedValue: vocabularyStore)
        _settings = StateObject(wrappedValue: settings)
        _appModel = StateObject(wrappedValue: AppViewModel(mediaLibrary: mediaLibrary, vocabularyStore: vocabularyStore, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
                .task {
                    if SpeechAuthorizationHelper.hasUsageDescription,
                       SpeechAuthorizationHelper.status() == .notDetermined {
                        _ = await SpeechAuthorizationHelper.request()
                    }
                }
        }
        Settings {
            SettingsDetailView(section: .provider, settings: settings)
                .frame(minWidth: 420, minHeight: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
