import SwiftUI

struct TranslationAndVocabView: View {
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let manualText = appModel.manualLookupText.trimmingCharacters(in: .whitespacesAndNewlines)
                let selectedText = appModel.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
                let activeText = manualText.isEmpty ? selectedText : manualText

                HStack(spacing: 8) {
                    TextField("输入单词或短语进行查询", text: $appModel.manualLookupText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let trimmed = appModel.manualLookupText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            appModel.fetchTranslation(for: trimmed, forceRefresh: true)
                        }
                    Button("查询") {
                        let trimmed = appModel.manualLookupText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        appModel.fetchTranslation(for: trimmed, forceRefresh: true)
                    }
                    Button("清空") {
                        appModel.manualLookupText = ""
                        if let selectedText, !selectedText.isEmpty {
                            appModel.fetchTranslation(for: selectedText, forceRefresh: false)
                        }
                    }
                }

                if let activeText, !activeText.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(activeText)
                                .font(.headline)

                            HStack(spacing: 8) {
                                Button("刷新释义") {
                                    appModel.refreshTranslation(for: activeText)
                                }
                                if appModel.isWordSaved(activeText) {
                                    Button("从生词本移除") {
                                        appModel.removeWord(activeText)
                                    }
                                } else {
                                    Button("加入生词本") {
                                        appModel.saveWord(activeText)
                                    }
                                }
                                Spacer()
                                if let translation = activeTranslation(for: activeText) {
                                    Text("更新于 \(translation.fetchedAt.formatted(date: .numeric, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            ProviderResultsSection(
                                title: "英文",
                                results: activeTranslation(for: activeText)?.english ?? [],
                                isLoading: appModel.isFetchingTranslation,
                                emptyText: "暂无英文释义。"
                            )

                            Divider()

                            ProviderResultsSection(
                                title: "中文",
                                results: activeTranslation(for: activeText)?.chinese ?? [],
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
        .onChange(of: appModel.manualLookupText) { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, let selected = appModel.selectedText, !selected.isEmpty {
                let key = appModel.normalizedTranslationKey(for: selected)
                if key != appModel.translationKey {
                    appModel.fetchTranslation(for: selected, forceRefresh: false)
                }
            }
        }
    }

    private func activeTranslation(for text: String) -> TranslationSnapshot? {
        guard let key = appModel.normalizedTranslationKey(for: text) else { return nil }
        guard key == appModel.translationKey else { return nil }
        return appModel.translation
    }
}
