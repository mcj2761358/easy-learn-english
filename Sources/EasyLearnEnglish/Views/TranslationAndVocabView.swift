import SwiftUI

struct TranslationAndVocabView: View {
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let selectedText = appModel.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let selectedText, !selectedText.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedText)
                                .font(.headline)

                            HStack(spacing: 8) {
                                Button("刷新释义") {
                                    appModel.refreshTranslation(for: selectedText)
                                }
                                if appModel.isSelectionSaved {
                                    Button("从生词本移除") {
                                        appModel.removeSelectionFromVocabulary()
                                    }
                                } else {
                                    Button("加入生词本") {
                                        appModel.saveSelectionToVocabulary()
                                    }
                                }
                                Spacer()
                                if let translation = activeTranslation(for: selectedText) {
                                    Text("更新于 \(translation.fetchedAt.formatted(date: .numeric, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            ProviderResultsSection(
                                title: "英文",
                                results: activeTranslation(for: selectedText)?.english ?? [],
                                isLoading: appModel.isFetchingTranslation,
                                emptyText: "暂无英文释义。"
                            )

                            Divider()

                            ProviderResultsSection(
                                title: "中文",
                                results: activeTranslation(for: selectedText)?.chinese ?? [],
                                isLoading: appModel.isFetchingTranslation,
                                emptyText: "暂无中文释义。"
                            )
                        }
                        .padding(6)
                    } label: {
                        Text("单词详情")
                    }
                } else {
                    Text("暂未选中词汇")
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    private func activeTranslation(for text: String) -> TranslationSnapshot? {
        guard let key = appModel.normalizedTranslationKey(for: text) else { return nil }
        guard key == appModel.translationKey else { return nil }
        return appModel.translation
    }
}
