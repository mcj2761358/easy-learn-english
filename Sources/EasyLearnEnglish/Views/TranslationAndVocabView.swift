import SwiftUI

struct TranslationAndVocabView: View {
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appModel.selectedText ?? "选择单词")
                        .font(.headline)

                    if let translation = appModel.translation {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("英文")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(translation.definitionEn)
                                .font(.body)

                            Divider()

                            Text("中文")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(translation.translationZh)
                                .font(.body)
                        }
                    } else {
                        Text("点击单词查看释义。")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        if appModel.isSelectionSaved {
                            Button("从生词本移除") {
                                appModel.removeSelectionFromVocabulary()
                            }
                        } else {
                            Button("加入生词本") {
                                appModel.saveSelectionToVocabulary()
                            }
                            .disabled(appModel.selectedText == nil)
                        }
                        Spacer()
                    }
                }
                .padding(6)
            } label: {
                Text("单词详情")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    if appModel.vocabularyStore.entries.isEmpty {
                        Text("暂无生词。")
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(appModel.vocabularyStore.entries) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.word).font(.headline)
                                        Text(entry.definitionEn).font(.caption)
                                        Text(entry.translationZh).font(.caption)
                                    }
                                    .padding(6)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(6)
            } label: {
                Text("生词本")
            }

            Spacer()
        }
        .padding(8)
    }
}
