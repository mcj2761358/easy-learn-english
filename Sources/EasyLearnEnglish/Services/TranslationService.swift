import Foundation

struct TranslationService {
    func translate(wordOrPhrase: String) -> TranslationResult {
        let definition = englishDefinition(for: wordOrPhrase)
        let zh = chineseTranslation(for: wordOrPhrase)
        return TranslationResult(definitionEn: definition, translationZh: zh)
    }

    private func englishDefinition(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "（未配置英文释义查询）"
    }

    private func chineseTranslation(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "（需要配置翻译API）"
    }
}
