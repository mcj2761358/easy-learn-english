import SwiftUI

struct ContentView: View {
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            MediaLibraryView(appModel: appModel)
                .frame(minWidth: 240)
        } content: {
            PlayerAndSubtitlesView(appModel: appModel)
                .frame(minWidth: 520)
        } detail: {
            TranslationAndVocabView(appModel: appModel)
                .frame(minWidth: 280)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
