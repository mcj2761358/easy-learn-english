import SwiftUI
import AppKit

enum SidebarSelection: Hashable {
    case media(UUID)
    case vocabulary
    case settings
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case provider = "转写提供商"
    case tools = "外部工具"
    case storage = "存储"

    var id: String { rawValue }
}

struct ContentView: View {
    @ObservedObject var appModel: AppViewModel
    @State private var selection: SidebarSelection?
    @State private var settingsSection: SettingsSection = .provider
    @State private var vocabularySelection: UUID?

    var body: some View {
        NavigationSplitView {
            MediaLibraryView(appModel: appModel, selection: $selection)
                .frame(minWidth: 240)
        } content: {
            if case .settings = selection {
                SettingsMenuView(selection: $settingsSection)
                    .frame(minWidth: 520)
            } else if case .vocabulary = selection {
                VocabularyLibraryView(appModel: appModel, selection: $vocabularySelection)
                    .frame(minWidth: 520)
            } else {
                PlayerAndSubtitlesView(appModel: appModel)
                    .frame(minWidth: 520)
            }
        } detail: {
            if case .settings = selection {
                SettingsDetailView(section: settingsSection, settings: appModel.settings)
                    .frame(minWidth: 360)
            } else if case .vocabulary = selection {
                VocabularyDetailView(appModel: appModel, entryID: vocabularySelection)
                    .frame(minWidth: 360)
            } else {
                TranslationAndVocabView(appModel: appModel)
                    .frame(minWidth: 280)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appModel.handleAppBecameActive()
        }
    }
}

private struct SettingsMenuView: View {
    @Binding var selection: SettingsSection

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsSection.allCases) { section in
                HStack {
                    Image(systemName: iconName(for: section))
                        .foregroundColor(.secondary)
                    Text(section.rawValue)
                }
                .tag(section)
            }
        }
        .listStyle(.sidebar)
    }

    private func iconName(for section: SettingsSection) -> String {
        switch section {
        case .provider: return "waveform"
        case .tools: return "wrench.and.screwdriver"
        case .storage: return "externaldrive"
        }
    }
}
