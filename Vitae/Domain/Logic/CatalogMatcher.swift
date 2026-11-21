import Foundation

/// Сопоставление произвольного названия (из OCR или CSV) с показателем справочника.
struct CatalogMatcher: Sendable {
    struct Alias: Sendable {
        let text: String
        let code: String
    }

    struct Match: Sendable {
        let entry: CatalogEntry
        /// Диапазон совпадения в символах нормализованной строки.
        let start: Int
        let end: Int
    }

    let catalog: CatalogIndex
    private let aliases: [Alias]

    init(catalog: CatalogIndex) {
        self.catalog = catalog
        var list: [Alias] = []
        for entry in catalog.entries where !entry.isPanel {
            let names = Set(([entry.name, entry.shortName] + entry.aliases).map { Self.matchKey($0) })
            for name in names where name.count >= 2 {
                list.append(Alias(text: name, code: entry.code))
            }
        }
        aliases = list.sorted { $0.text.count > $1.text.count }
    }

    static func normalize(_ text: String) -> String {
        matchKey(text.searchNormalized.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;*-–—•·")))
    }

    /// Ключ для сравнения названий: дефис равен пробелу, а кириллические буквы, похожие
    /// на латинские, приравнены к ним. Так «Холестерин-ЛПВП» находит «холестерин лпвп»,
    /// а «Витамин 25(ОН) D» с русскими «О» и «Н» — синоним с латинским «25(OH)».
    static func matchKey(_ text: String) -> String {
        searchCharacters(text.searchNormalized).searchNormalized
    }

    /// Замена символов для сравнения без изменения длины строки: позиции совпадения
    /// остаются верными для исходной строки.
    static func searchCharacters(_ text: String) -> String {
        String(text.map { lookalikes[$0] ?? $0 })
    }

    private static let lookalikes: [Character: Character] = [
        "-": " ", "‐": " ", "а": "a", "в": "b", "е": "e", "к": "k", "м": "m", "н": "h",
        "о": "o", "р": "p", "с": "c", "т": "t", "у": "y", "х": "x"
    ]

    /// Точное совпадение названия с названием, кратким названием или синонимом.
    func exactMatch(_ name: String) -> CatalogEntry? {
        let normalized = Self.normalize(name)
        guard !normalized.isEmpty else { return nil }
        if let alias = aliases.first(where: { $0.text == normalized }) { return catalog.byCode[alias.code] }
        // Название с уточнением в скобках: «Гемоглобин (HGB)».
        let withoutParens = normalized.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression).trimmed
        if withoutParens != normalized, let alias = aliases.first(where: { $0.text == withoutParens }) {
            return catalog.byCode[alias.code]
        }
        return nil
    }

    /// Самый длинный синоним, встречающийся в строке целым словом.
    func find(inNormalized line: String) -> Match? {
        let chars = Array(Self.searchCharacters(line))
        for alias in aliases {
            let target = Array(alias.text)
            guard target.count <= chars.count else { continue }
            var index = 0
            while index + target.count <= chars.count {
                if chars[index] == target[0], Array(chars[index..<(index + target.count)]) == target {
                    let before = index == 0 ? nil : chars[index - 1]
                    let afterIndex = index + target.count
                    let after = afterIndex < chars.count ? chars[afterIndex] : nil
                    if !Self.isWordCharacter(before) && !Self.isWordCharacter(after),
                       let entry = catalog.byCode[alias.code] {
                        return Match(entry: entry, start: index, end: afterIndex)
                    }
                }
                index += 1
            }
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber
    }
}
