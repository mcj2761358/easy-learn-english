import SwiftUI

struct VocabularyLibraryView: View {
    @ObservedObject var appModel: AppViewModel
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "book")
                    .foregroundColor(.secondary)
                Text("生词本")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VocabularyReportView(report: appModel.vocabularyStore.report)
                .padding(.horizontal, 8)

            List(selection: $selection) {
                if appModel.vocabularyStore.entries.isEmpty {
                    Text("暂无生词。")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appModel.vocabularyStore.entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.word)
                                    .font(.headline)
                                if !entry.sourceTitle.isEmpty {
                                    Text(entry.sourceTitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            FamiliarityBadge(title: entry.familiarity.label)
                        }
                        .tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)
        }
    }
}

struct VocabularyDetailView: View {
    @ObservedObject var appModel: AppViewModel
    let entryID: UUID?

    @State private var showChinese = false

    private var entry: VocabularyEntry? {
        guard let entryID else { return nil }
        return appModel.vocabularyStore.entry(id: entryID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let entry {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.word)
                                .font(.title2)

                            HStack(spacing: 12) {
                                Text("熟悉度")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("熟悉度", selection: familiarityBinding(for: entry)) {
                                    ForEach(VocabularyFamiliarity.allCases) { familiarity in
                                        Text(familiarity.label).tag(familiarity)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            HStack(spacing: 8) {
                                Button("刷新释义") {
                                    appModel.refreshTranslation(for: entry.word)
                                }
                                Button("移除") {
                                    appModel.vocabularyStore.remove(word: entry.word)
                                }
                                Spacer()
                                if let translation = currentTranslation(for: entry.word) {
                                    Text("更新于 \(translation.fetchedAt.formatted(date: .numeric, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !entry.sourceTitle.isEmpty {
                                Text("来源：\(entry.sourceTitle)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("加入时间：\(entry.addedAt.formatted(date: .numeric, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ProviderResultsSection(
                                title: "英文",
                                results: englishResults(for: entry),
                                isLoading: appModel.isFetchingTranslation,
                                emptyText: "暂无英文释义。"
                            )

                            Divider()

                            if showChinese {
                                ProviderResultsSection(
                                    title: "中文",
                                    results: chineseResults(for: entry),
                                    isLoading: appModel.isFetchingTranslation,
                                    emptyText: "暂无中文释义。"
                                )
                            } else {
                                Button("显示中文释义") {
                                    showChinese = true
                                }
                            }
                        }
                        .padding(6)
                    } label: {
                        Text("生词详情")
                    }
                } else {
                    Text("请选择一个生词。")
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
        .onAppear {
            guard let entry else { return }
            showChinese = false
            appModel.fetchTranslation(for: entry.word, forceRefresh: false)
        }
        .onChange(of: entryID) { _ in
            guard let entry else { return }
            showChinese = false
            appModel.fetchTranslation(for: entry.word, forceRefresh: false)
        }
    }

    private func familiarityBinding(for entry: VocabularyEntry) -> Binding<VocabularyFamiliarity> {
        Binding(
            get: { entry.familiarity },
            set: { newValue in
                appModel.vocabularyStore.updateFamiliarity(id: entry.id, familiarity: newValue)
            }
        )
    }

    private func activeTranslation(for text: String) -> TranslationSnapshot? {
        guard let key = appModel.normalizedTranslationKey(for: text) else { return nil }
        guard key == appModel.translationKey else { return nil }
        return appModel.translation
    }

    private func cachedTranslation(for text: String) -> TranslationSnapshot? {
        appModel.cachedTranslation(for: text)
    }

    private func currentTranslation(for text: String) -> TranslationSnapshot? {
        activeTranslation(for: text) ?? cachedTranslation(for: text)
    }

    private func fallbackEnglish(entry: VocabularyEntry) -> [DefinitionProviderResult] {
        guard !entry.definitionEn.isEmpty else { return [] }
        return [
            DefinitionProviderResult(id: "stored-en", name: "已保存", text: entry.definitionEn, isError: false)
        ]
    }

    private func fallbackChinese(entry: VocabularyEntry) -> [DefinitionProviderResult] {
        guard !entry.translationZh.isEmpty else { return [] }
        return [
            DefinitionProviderResult(id: "stored-zh", name: "已保存", text: entry.translationZh, isError: false)
        ]
    }

    private func englishResults(for entry: VocabularyEntry) -> [DefinitionProviderResult] {
        if let translation = currentTranslation(for: entry.word), !translation.english.isEmpty {
            return translation.english
        }
        return fallbackEnglish(entry: entry)
    }

    private func chineseResults(for entry: VocabularyEntry) -> [DefinitionProviderResult] {
        if let translation = currentTranslation(for: entry.word), !translation.chinese.isEmpty {
            return translation.chinese
        }
        return fallbackChinese(entry: entry)
    }
}

private struct VocabularyReportView: View {
    let report: VocabularyReport

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatBadge(title: "总量", value: "\(report.total)")
                    StatBadge(title: "7天新增", value: "\(report.addedLast7Days)")
                    StatBadge(title: "30天新增", value: "\(report.addedLast30Days)")
                }

                HStack(spacing: 8) {
                    ForEach(VocabularyFamiliarity.allCases) { familiarity in
                        let count = report.familiarityCounts[familiarity, default: 0]
                        StatBadge(title: familiarity.label, value: "\(count)")
                    }
                }

                if !report.topSources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("高频来源")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(report.topSources, id: \.0) { source, count in
                            Text("\(source) (\(count))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(6)
        } label: {
            Text("生词报表")
        }
    }
}

private struct FamiliarityBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15))
            .cornerRadius(6)
    }
}

private struct StatBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .padding(6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}
