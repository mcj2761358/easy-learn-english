import Foundation
import CryptoKit

struct TranslationServiceConfig {
    let youdaoAppKey: String
    let youdaoAppSecret: String
    let baiduAppId: String
    let baiduAppSecret: String
    let azureTranslatorKey: String
    let azureTranslatorRegion: String
}

final class TranslationService {
    private let cacheStore = TranslationCacheStore()
    private let session = URLSession.shared

    static func normalizedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func cachedSnapshot(for text: String) -> TranslationSnapshot? {
        let key = Self.normalizedKey(text)
        return cacheStore.snapshot(for: key)
    }

    func fetch(wordOrPhrase: String, forceRefresh: Bool, config: TranslationServiceConfig) async -> TranslationSnapshot {
        let trimmed = wordOrPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.normalizedKey(trimmed)
        if !forceRefresh, let cached = cacheStore.snapshot(for: key) {
            return cached
        }

        async let english = fetchEnglishDefinitions(for: trimmed)
        async let chinese = fetchChineseDefinitions(for: trimmed, config: config)
        let snapshot = TranslationSnapshot(
            query: trimmed,
            fetchedAt: Date(),
            english: await english,
            chinese: await chinese
        )
        cacheStore.save(cacheableSnapshot(snapshot), for: key)
        return snapshot
    }

    private func fetchEnglishDefinitions(for text: String) async -> [DefinitionProviderResult] {
        let order = ["dictionaryapi", "wiktionary", "datamuse"]
        let providers: [(String, () async -> DefinitionProviderResult?)] = [
            ("dictionaryapi", { await self.fetchFreeDictionary(text: text) }),
            ("wiktionary", { await self.fetchWiktionary(text: text) }),
            ("datamuse", { await self.fetchDatamuse(text: text) })
        ]
        return await withTaskGroup(of: DefinitionProviderResult?.self) { group in
            for provider in providers {
                group.addTask { await provider.1() }
            }

            var results: [String: DefinitionProviderResult] = [:]
            for await result in group {
                if let result, !result.isError, !result.text.isEmpty {
                    results[result.id] = result
                }
            }
            return order.compactMap { results[$0] }
        }
    }

    private func fetchChineseDefinitions(for text: String, config: TranslationServiceConfig) async -> [DefinitionProviderResult] {
        var order = ["google", "libretranslate", "mymemory"]
        var providers: [(String, () async -> DefinitionProviderResult?)] = [
            ("google", { await self.fetchGoogleTranslate(text: text) }),
            ("libretranslate", { await self.fetchLibreTranslate(text: text) }),
            ("mymemory", { await self.fetchMyMemory(text: text) })
        ]

        if configHasYoudao(config) {
            order.append("youdao")
            providers.append(("youdao", { await self.fetchYoudaoTranslate(text: text, config: config) }))
        }
        if configHasBaidu(config) {
            order.append("baidu")
            providers.append(("baidu", { await self.fetchBaiduTranslate(text: text, config: config) }))
        }
        if configHasMicrosoft(config) {
            order.append("microsoft")
            providers.append(("microsoft", { await self.fetchMicrosoftTranslate(text: text, config: config) }))
        }

        return await withTaskGroup(of: DefinitionProviderResult?.self) { group in
            for provider in providers {
                group.addTask { await provider.1() }
            }

            var results: [String: DefinitionProviderResult] = [:]
            for await result in group {
                if let result, !result.isError, !result.text.isEmpty {
                    results[result.id] = result
                }
            }
            return order.compactMap { results[$0] }
        }
    }

    private func fetchFreeDictionary(text: String) async -> DefinitionProviderResult? {
        let providerID = "dictionaryapi"
        let providerName = "Free Dictionary API"
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded(text))") else {
            return nil
        }
        guard let data = await requestData(from: url) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            let entries = try decoder.decode([FreeDictionaryEntry].self, from: data)
            guard !entries.isEmpty else {
                return nil
            }
            var lines: [String] = []
            for entry in entries {
                for meaning in entry.meanings {
                    if !lines.isEmpty { lines.append("") }
                    lines.append(meaning.partOfSpeech)
                    for definition in meaning.definitions {
                        lines.append("- \(definition.definition)")
                        if let example = definition.example, !example.isEmpty {
                            lines.append("例：\(example)")
                        }
                        if let synonyms = definition.synonyms, !synonyms.isEmpty {
                            lines.append("同义：\(synonyms.joined(separator: ", "))")
                        }
                        if let antonyms = definition.antonyms, !antonyms.isEmpty {
                            lines.append("反义：\(antonyms.joined(separator: ", "))")
                        }
                    }
                }
            }
            guard !lines.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: lines.joined(separator: "\n"), isError: false)
        } catch {
            return nil
        }
    }

    private func fetchWiktionary(text: String) async -> DefinitionProviderResult? {
        let providerID = "wiktionary"
        let providerName = "Wiktionary"
        let query = "https://en.wiktionary.org/w/api.php?action=parse&format=json&page=\(encoded(text))&prop=wikitext&redirects=1"
        guard let url = URL(string: query) else {
            return nil
        }
        guard let data = await requestData(from: url) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(WiktionaryParseResponse.self, from: data)
            guard let wikitext = response.parse?.wikitext.value else {
                return nil
            }
            let definitions = parseWiktionaryDefinitions(wikitext)
            guard !definitions.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: definitions.joined(separator: "\n"), isError: false)
        } catch {
            return nil
        }
    }

    private func fetchDatamuse(text: String) async -> DefinitionProviderResult? {
        let providerID = "datamuse"
        let providerName = "Datamuse/WordNet"
        guard let url = URL(string: "https://api.datamuse.com/words?sp=\(encoded(text))&md=d&max=3") else {
            return nil
        }
        guard let data = await requestData(from: url) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            let results = try decoder.decode([DatamuseResult].self, from: data)
            let defs = results.flatMap { $0.defs ?? [] }
            guard !defs.isEmpty else {
                return nil
            }
            let lines = defs.map { def -> String in
                let parts = def.split(separator: "\t", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    return "\(parts[0]): \(parts[1])"
                }
                return def
            }
            return .init(id: providerID, name: providerName, text: lines.joined(separator: "\n"), isError: false)
        } catch {
            return nil
        }
    }

    private func fetchYoudaoTranslate(text: String, config: TranslationServiceConfig) async -> DefinitionProviderResult? {
        let providerID = "youdao"
        let providerName = "有道翻译"
        guard configHasYoudao(config) else { return nil }
        guard let url = URL(string: "https://openapi.youdao.com/api") else {
            return nil
        }

        let salt = UUID().uuidString
        let curtime = String(Int(Date().timeIntervalSince1970))
        let signType = "v3"
        let signStr = config.youdaoAppKey + youdaoTruncate(text) + salt + curtime + config.youdaoAppSecret
        let sign = sha256Hex(signStr)
        let body: [String: String] = [
            "q": text,
            "from": "en",
            "to": "zh-CHS",
            "appKey": config.youdaoAppKey,
            "salt": salt,
            "sign": sign,
            "signType": signType,
            "curtime": curtime
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(body)

        guard let data = await requestData(for: request) else { return nil }
        do {
            let response = try JSONDecoder().decode(YoudaoResponse.self, from: data)
            guard response.errorCode == "0" else { return nil }
            var lines: [String] = []
            if let translation = response.translation, !translation.isEmpty {
                lines.append(contentsOf: translation)
            }
            if let basic = response.basic {
                if let phonetic = basic.phonetic, !phonetic.isEmpty {
                    lines.append("音标：\(phonetic)")
                }
                if let us = basic.usPhonetic, !us.isEmpty {
                    lines.append("美式：\(us)")
                }
                if let uk = basic.ukPhonetic, !uk.isEmpty {
                    lines.append("英式：\(uk)")
                }
                if let explains = basic.explains, !explains.isEmpty {
                    lines.append(contentsOf: explains)
                }
            }
            if let webs = response.web, !webs.isEmpty {
                lines.append("网络释义：")
                for web in webs {
                    let values = web.value.joined(separator: "，")
                    lines.append("- \(web.key)：\(values)")
                }
            }
            guard !lines.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: lines.joined(separator: "\n"), isError: false)
        } catch {
            return nil
        }
    }

    private func fetchBaiduTranslate(text: String, config: TranslationServiceConfig) async -> DefinitionProviderResult? {
        let providerID = "baidu"
        let providerName = "百度翻译"
        guard configHasBaidu(config) else { return nil }
        guard let url = URL(string: "https://fanyi-api.baidu.com/api/trans/vip/translate") else {
            return nil
        }

        let salt = UUID().uuidString
        let signStr = config.baiduAppId + text + salt + config.baiduAppSecret
        let sign = md5Hex(signStr)
        let body: [String: String] = [
            "q": text,
            "from": "en",
            "to": "zh",
            "appid": config.baiduAppId,
            "salt": salt,
            "sign": sign
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(body)

        guard let data = await requestData(for: request) else { return nil }
        do {
            let response = try JSONDecoder().decode(BaiduTranslateResponse.self, from: data)
            if response.errorCode != nil { return nil }
            let translations = response.transResult?.map { $0.dst } ?? []
            guard !translations.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: translations.joined(separator: "\n"), isError: false)
        } catch {
            return nil
        }
    }

    private func fetchMicrosoftTranslate(text: String, config: TranslationServiceConfig) async -> DefinitionProviderResult? {
        let providerID = "microsoft"
        let providerName = "微软翻译"
        guard configHasMicrosoft(config) else { return nil }
        let query = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=en&to=zh-Hans"
        guard let url = URL(string: query) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.azureTranslatorKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        if !config.azureTranslatorRegion.isEmpty {
            request.setValue(config.azureTranslatorRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        let payload = [[ "Text": text ]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let data = await requestData(for: request) else { return nil }
        do {
            let response = try JSONDecoder().decode([MicrosoftTranslateResponse].self, from: data)
            let translations = response.first?.translations.map { $0.text } ?? []
            guard !translations.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: translations.joined(separator: "\n"), isError: false)
        } catch {
            return nil
        }
    }

    private func fetchGoogleTranslate(text: String) async -> DefinitionProviderResult? {
        let providerID = "google"
        let providerName = "Google Translate"
        let query = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&dt=bd&dt=md&dt=ex&dt=ss&q=\(encoded(text))"
        guard let url = URL(string: query) else {
            return nil
        }
        guard let data = await requestData(from: url) else {
            return nil
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            guard let root = json as? [Any] else {
                return nil
            }
            let translated = googleTranslationText(from: root)
            let dictionary = googleDictionaryText(from: root)
            var lines: [String] = []
            if !translated.isEmpty {
                lines.append(translated)
            }
            if !dictionary.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append(dictionary)
            }
            guard !lines.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: lines.joined(separator: "\n"), isError: false)
        } catch {
            return nil
        }
    }

    private func fetchLibreTranslate(text: String) async -> DefinitionProviderResult? {
        let providerID = "libretranslate"
        let providerName = "LibreTranslate"
        guard let url = URL(string: "https://translate.cutie.dating/translate") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "q": text,
            "source": "en",
            "target": "zh",
            "format": "text"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let data = await requestData(for: request) else { return nil }
        do {
            let response = try JSONDecoder().decode(LibreTranslateResponse.self, from: data)
            let translated = response.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: translated, isError: false)
        } catch {
            return nil
        }
    }

    private func fetchMyMemory(text: String) async -> DefinitionProviderResult? {
        let providerID = "mymemory"
        let providerName = "MyMemory"
        let query = "https://api.mymemory.translated.net/get?q=\(encoded(text))&langpair=en|zh-CN"
        guard let url = URL(string: query) else { return nil }
        guard let data = await requestData(from: url) else { return nil }
        do {
            let response = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            let translated = response.responseData.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else { return nil }
            return .init(id: providerID, name: providerName, text: translated, isError: false)
        } catch {
            return nil
        }
    }

    private func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    private func requestData(from url: URL) async -> Data? {
        let request = URLRequest(url: url)
        return await requestData(for: request)
    }

    private func requestData(for request: URLRequest) async -> Data? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func youdaoTruncate(_ text: String) -> String {
        let count = text.count
        if count <= 20 { return text }
        let start = text.prefix(10)
        let end = text.suffix(10)
        return "\(start)\(count)\(end)"
    }

    private func cacheableSnapshot(_ snapshot: TranslationSnapshot) -> TranslationSnapshot {
        let filteredChinese = snapshot.chinese.filter { $0.id != "baidu" }
        return TranslationSnapshot(
            query: snapshot.query,
            fetchedAt: snapshot.fetchedAt,
            english: snapshot.english,
            chinese: filteredChinese
        )
    }

    private func configHasYoudao(_ config: TranslationServiceConfig) -> Bool {
        !config.youdaoAppKey.isEmpty && !config.youdaoAppSecret.isEmpty
    }

    private func configHasBaidu(_ config: TranslationServiceConfig) -> Bool {
        !config.baiduAppId.isEmpty && !config.baiduAppSecret.isEmpty
    }

    private func configHasMicrosoft(_ config: TranslationServiceConfig) -> Bool {
        !config.azureTranslatorKey.isEmpty
    }

    private func sha256Hex(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func md5Hex(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func formURLEncoded(_ params: [String: String]) -> Data? {
        let pairs = params.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8)
    }

    private func parseWiktionaryDefinitions(_ wikitext: String) -> [String] {
        guard let englishSection = extractSection(wikitext, title: "English") else {
            return []
        }

        var definitions: [String] = []
        let lines = englishSection.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") {
                let cleaned = cleanWiktionaryMarkup(stripLeading(trimmed, drop: ["#", " "]))
                if !cleaned.isEmpty {
                    definitions.append(cleaned)
                }
            } else if trimmed.hasPrefix("#: ") || trimmed.hasPrefix("#* ") {
                guard let lastIndex = definitions.indices.last else { continue }
                let cleaned = cleanWiktionaryMarkup(stripLeading(trimmed, drop: ["#", ":", "*", " "]))
                if !cleaned.isEmpty {
                    definitions[lastIndex].append("\n例：\(cleaned)")
                }
            }
        }
        return definitions
    }

    private func extractSection(_ text: String, title: String) -> String? {
        let marker = "==\(title)=="
        guard let range = text.range(of: marker) else { return nil }
        let after = text[range.upperBound...]
        if let nextRange = after.range(of: "\n==") {
            return String(after[..<nextRange.lowerBound])
        }
        return String(after)
    }

    private func cleanWiktionaryMarkup(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: "'''", with: "")
        output = output.replacingOccurrences(of: "''", with: "")
        output = regexReplace(output, pattern: "<ref[^>]*>.*?</ref>", replacement: "")
        output = regexReplace(output, pattern: "<[^>]+>", replacement: "")
        output = regexReplace(output, pattern: "\\{\\{[^}]+\\}\\}", replacement: "")
        output = regexReplace(output, pattern: "\\[\\[([^\\]|]+)\\|([^\\]]+)\\]\\]", replacement: "$2")
        output = regexReplace(output, pattern: "\\[\\[([^\\]]+)\\]\\]", replacement: "$1")
        output = output.replacingOccurrences(of: "&nbsp;", with: " ")
        output = output.replacingOccurrences(of: "&amp;", with: "&")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripLeading(_ text: String, drop: Set<Character>) -> String {
        var result = text
        while let first = result.first, drop.contains(first) {
            result.removeFirst()
        }
        return result
    }

    private func regexReplace(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private func googleTranslationText(from root: [Any]) -> String {
        guard let segments = root.first as? [[Any]] else { return "" }
        return segments.compactMap { $0.first as? String }.joined()
    }

    private func googleDictionaryText(from root: [Any]) -> String {
        guard root.count > 1 else { return "" }
        if let dictEntries = root[1] as? [[String: Any]] {
            return googleDictionaryTextFromDict(dictEntries)
        }
        if let dictEntries = root[1] as? [[Any]] {
            return googleDictionaryTextFromArray(dictEntries)
        }
        return ""
    }

    private func googleDictionaryTextFromDict(_ dictEntries: [[String: Any]]) -> String {
        var lines: [String] = []
        for entry in dictEntries {
            if let pos = entry["pos"] as? String, !pos.isEmpty {
                lines.append(pos)
            }
            if let terms = entry["terms"] as? [String], !terms.isEmpty {
                lines.append("释义：\(terms.joined(separator: "，"))")
            }
            if let entryDetails = entry["entry"] as? [[String: Any]] {
                for detail in entryDetails {
                    guard let word = detail["word"] as? String, !word.isEmpty else { continue }
                    if let reverse = detail["reverse_translation"] as? [String], !reverse.isEmpty {
                        lines.append("- \(word)：\(reverse.joined(separator: "，"))")
                    } else {
                        lines.append("- \(word)")
                    }
                }
            }
            lines.append("")
        }
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private func googleDictionaryTextFromArray(_ dictEntries: [[Any]]) -> String {
        var lines: [String] = []
        for entry in dictEntries {
            if let pos = entry[safe: 0] as? String, !pos.isEmpty {
                lines.append(pos)
            }
            if let terms = entry[safe: 1] as? [String], !terms.isEmpty {
                lines.append("释义：\(terms.joined(separator: "，"))")
            }
            if let entryDetails = entry[safe: 2] as? [[Any]] {
                for detail in entryDetails {
                    guard let word = detail[safe: 0] as? String, !word.isEmpty else { continue }
                    if let reverse = detail[safe: 1] as? [String], !reverse.isEmpty {
                        lines.append("- \(word)：\(reverse.joined(separator: "，"))")
                    } else {
                        lines.append("- \(word)")
                    }
                }
            }
            lines.append("")
        }
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct FreeDictionaryEntry: Decodable {
    let word: String
    let meanings: [FreeDictionaryMeaning]
}

private struct FreeDictionaryMeaning: Decodable {
    let partOfSpeech: String
    let definitions: [FreeDictionaryDefinition]
}

private struct FreeDictionaryDefinition: Decodable {
    let definition: String
    let example: String?
    let synonyms: [String]?
    let antonyms: [String]?
}

private struct WiktionaryParseResponse: Decodable {
    struct Parse: Decodable {
        struct Wikitext: Decodable {
            let value: String

            private enum CodingKeys: String, CodingKey {
                case value = "*"
            }
        }

        let wikitext: Wikitext
    }

    let parse: Parse?
}

private struct DatamuseResult: Decodable {
    let defs: [String]?
}

private struct LibreTranslateResponse: Decodable {
    let translatedText: String
}

private struct MyMemoryResponse: Decodable {
    struct ResponseData: Decodable {
        let translatedText: String
    }

    let responseData: ResponseData
}

private struct YoudaoResponse: Decodable {
    let errorCode: String?
    let translation: [String]?
    let basic: YoudaoBasic?
    let web: [YoudaoWeb]?

    struct YoudaoBasic: Decodable {
        let phonetic: String?
        let usPhonetic: String?
        let ukPhonetic: String?
        let explains: [String]?

        private enum CodingKeys: String, CodingKey {
            case phonetic
            case usPhonetic = "us-phonetic"
            case ukPhonetic = "uk-phonetic"
            case explains
        }
    }

    struct YoudaoWeb: Decodable {
        let key: String
        let value: [String]
    }
}

private struct BaiduTranslateResponse: Decodable {
    let errorCode: String?
    let errorMsg: String?
    let transResult: [BaiduTransResult]?

    private enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMsg = "error_msg"
        case transResult = "trans_result"
    }
}

private struct BaiduTransResult: Decodable {
    let dst: String
}

private struct MicrosoftTranslateResponse: Decodable {
    struct Translation: Decodable {
        let text: String
    }

    let translations: [Translation]
}
