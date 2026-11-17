import Foundation

struct ParsedLabItem: Identifiable, Equatable, Sendable {
    var id = UUID()
    var sourceLine: String
    var name: String
    var testCode: String?
    var rawValue: String
    var unit: String
    var reference: ReferenceRange
    var isQualitative: Bool
}

struct ParsedLabReport: Equatable, Sendable {
    var date: Date?
    var laboratoryName: String?
    var items: [ParsedLabItem]
}

/// Разбор текста лабораторного бланка (после OCR или из текстового слоя PDF).
/// Результат всегда проходит ручную проверку пользователем перед сохранением.
struct LabReportParser: Sendable {
    let matcher: CatalogMatcher
    let knownLaboratories: [String]

    static let builtInLaboratories = [
        "Инвитро", "Invitro", "Гемотест", "Gemotest", "KDL", "КДЛ", "Хеликс", "Helix", "CMD", "ЦМД",
        "Ситилаб", "Citilab", "ДНКОМ", "DNKOM", "ЛабКвест", "LabQuest", "Синэво", "Synevo", "Медси",
        "СМ-Клиника", "Lab4U", "Лабстори", "Quest Diagnostics", "Labcorp"
    ]

    /// Единицы в «красивой» записи; сопоставление без учёта регистра, длинные — первыми.
    static let unitTokens: [String] = [
        "×10^12/л", "×10^9/л", "×10¹²/л", "×10⁹/л", "x10^12/л", "x10^9/л", "10^12/л", "10^9/л", "10*12/л", "10*9/л",
        "x10^12/L", "x10^9/L", "10^12/L", "10^9/L", "тыс/мкл", "млн/мкл", "ммоль/моль", "mmol/mol",
        "мкмоль/л", "ммоль/л", "нмоль/л", "пмоль/л", "мкМЕ/мл", "мкЕд/мл", "мМЕ/л", "мЕд/л", "МЕ/л", "Ед/л",
        "мкг/дл", "мкг/л", "мг/дл", "мг/л", "нг/мл", "нг/дл", "пг/мл", "г/дл", "г/л", "мм/час", "мм/ч", "в п/зр",
        "µmol/L", "umol/L", "mmol/L", "nmol/L", "pmol/L", "µIU/mL", "uIU/mL", "mIU/L", "IU/L", "U/L",
        "ng/mL", "ng/dL", "pg/mL", "mg/dL", "mg/L", "µg/L", "g/dL", "g/L", "mm/h", "фл", "fL", "пг", "pg", "%"
    ].sorted { $0.count > $1.count }

    private static let qualitativeWords = [
        "не обнаружено", "не обнаружены", "не выявлено", "отрицательно", "отрицательный", "положительно",
        "положительный", "обнаружено", "следы", "negative", "positive", "not detected", "detected",
        "соломенно-желтый", "соломенно-жёлтый", "светло-желтый", "желтый", "жёлтый", "прозрачная", "мутная"
    ]

    private static let numberRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9.,])((?:<=|>=|<|>|≤|≥)\s*)?([0-9]+(?:[.,][0-9]+)?)(?![0-9])"#)
    private static let rangeRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9.,])([0-9]+(?:[.,][0-9]+)?)\s*(?:-|–|—|\.\.\.|…)\s*([0-9]+(?:[.,][0-9]+)?)(?![0-9])"#)
    private static let boundRegex = try! NSRegularExpression(
        pattern: #"(?:^|\s)(до|менее|<|≤|<=|от|более|>|≥|>=)\s*([0-9]+(?:[.,][0-9]+)?)\s*$"#, options: [.caseInsensitive])
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])([0-3]?[0-9])[./]([01]?[0-9])[./]((?:19|20)?[0-9]{2})(?![0-9])|(?<![0-9])((?:19|20)[0-9]{2})-([01][0-9])-([0-3][0-9])(?![0-9])"#)

    init(catalog: CatalogIndex, knownLaboratories: [String] = []) {
        self.matcher = CatalogMatcher(catalog: catalog)
        self.knownLaboratories = knownLaboratories
    }

    func parse(lines rawLines: [String]) -> ParsedLabReport {
        let lines = rawLines.map(\.trimmed).filter { !$0.isEmpty }
        var items: [ParsedLabItem] = []
        var seenCodes = Set<String>()
        for line in lines {
            guard let item = parseLine(line) else { continue }
            if let code = item.testCode {
                guard !seenCodes.contains(code) else { continue }
                seenCodes.insert(code)
            }
            items.append(item)
        }
        return ParsedLabReport(date: detectDate(in: lines), laboratoryName: detectLaboratory(in: lines), items: items)
    }

    // MARK: Строки результатов

    func parseLine(_ rawLine: String) -> ParsedLabItem? {
        let line = rawLine.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
        let lowerString = line.lowercased().replacingOccurrences(of: "ё", with: "е")
        if Self.isNoiseLine(lowerString) { return nil }

        if let match = matcher.find(inNormalized: lowerString) {
            let original = Array(line)
            let lower = Array(lowerString)
            let source = original.count == lower.count ? original : lower
            let rest = String(source[min(match.end, source.count)...])
            guard var item = parseValues(in: rest, isQualitative: match.entry.isQualitative) else { return nil }
            item.name = match.entry.name
            item.testCode = match.entry.code
            item.sourceLine = rawLine
            if item.unit.isEmpty || UnitConverter.areEquivalent(item.unit, match.entry.unit) {
                item.unit = match.entry.unit
            }
            return item
        }

        // Строка не из справочника: «Название  значение  ед.  референс».
        // Нужен корректный диапазон референса; строки с датами (шапка бланка) пропускаются.
        guard Self.firstDate(in: line) == nil,
              let range = Self.rangeRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let l = Range(range.range(at: 1), in: line), let u = Range(range.range(at: 2), in: line),
              let lowerBound = NumberParsing.double(String(line[l])), let upperBound = NumberParsing.double(String(line[u])),
              lowerBound <= upperBound,
              let firstDigit = line.firstIndex(where: { $0.isNumber }) else { return nil }
        let namePart = String(line[..<firstDigit]).trimmingCharacters(in: CharacterSet(charactersIn: " .,:;*-–—•·\t"))
        guard namePart.filter(\.isLetter).count >= 3 else { return nil }
        guard var item = parseValues(in: String(line[firstDigit...]), isQualitative: false) else { return nil }
        item.name = namePart
        item.testCode = nil
        item.sourceLine = rawLine
        return item
    }

    private static func isNoiseLine(_ lower: String) -> Bool {
        let noise = ["дата рождения", "пациент", "ф.и.о", "фио", "возраст", "пол:", "врач", "страница", "page ", "исследование выполнено"]
        return noise.contains { lower.contains($0) }
    }

    private func parseValues(in text: String, isQualitative: Bool) -> ParsedLabItem? {
        var remaining = text
        var reference = ReferenceRange()

        let nsRange = NSRange(remaining.startIndex..., in: remaining)
        if let range = Self.rangeRegex.firstMatch(in: remaining, range: nsRange),
           let r = Range(range.range, in: remaining),
           let l = Range(range.range(at: 1), in: remaining), let u = Range(range.range(at: 2), in: remaining) {
            let lower = NumberParsing.double(String(remaining[l]))
            let upper = NumberParsing.double(String(remaining[u]))
            if let lower, let upper, lower <= upper {
                reference = ReferenceRange(lower: lower, upper: upper)
                remaining.replaceSubrange(r, with: String(repeating: " ", count: remaining[r].count))
            }
        }

        // Единица измерения.
        var unit = ""
        var unitStart: String.Index?
        let lowerRemaining = remaining.lowercased()
        for token in Self.unitTokens {
            guard let found = Self.findToken(token.lowercased(), in: lowerRemaining) else { continue }
            unit = token
            unitStart = remaining.index(remaining.startIndex, offsetBy: lowerRemaining.distance(from: lowerRemaining.startIndex, to: found.lowerBound))
            let end = remaining.index(unitStart!, offsetBy: token.count, limitedBy: remaining.endIndex) ?? remaining.endIndex
            remaining.replaceSubrange(unitStart!..<end, with: String(repeating: " ", count: remaining[unitStart!..<end].count))
            break
        }

        // Односторонний референс в конце строки: «до 5», «< 5».
        if !reference.hasNumericBounds {
            let trimmed = remaining.trimmed
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            let numbers = Self.numberRegex.matches(in: trimmed, range: range)
            if numbers.count >= 2, let bound = Self.boundRegex.firstMatch(in: trimmed, range: range),
               let opRange = Range(bound.range(at: 1), in: trimmed), let valueRange = Range(bound.range(at: 2), in: trimmed),
               let full = Range(bound.range, in: trimmed) {
                let op = trimmed[opRange].lowercased()
                let value = NumberParsing.double(String(trimmed[valueRange]))
                if ["до", "менее", "<", "≤", "<="].contains(op) { reference = ReferenceRange(upper: value) }
                else { reference = ReferenceRange(lower: value) }
                remaining = String(trimmed[..<full.lowerBound])
                unitStart = nil
            }
        }

        // Качественное значение.
        if isQualitative {
            let lowered = remaining.lowercased()
            for word in Self.qualitativeWords where lowered.contains(word) {
                return ParsedLabItem(sourceLine: text, name: "", rawValue: word.prefix(1).uppercased() + word.dropFirst(),
                                     unit: unit, reference: reference, isQualitative: true)
            }
        }

        // Числовое значение: ближайшее перед единицей, иначе первое.
        let range = NSRange(remaining.startIndex..., in: remaining)
        let candidates = Self.numberRegex.matches(in: remaining, range: range).compactMap { match -> (String, String.Index)? in
            guard let full = Range(match.range, in: remaining) else { return nil }
            return (String(remaining[full]).replacingOccurrences(of: " ", with: ""), full.lowerBound)
        }
        guard !candidates.isEmpty else { return nil }
        var chosen = candidates[0]
        if let unitStart {
            if let before = candidates.last(where: { $0.1 < unitStart }) { chosen = before }
        }
        return ParsedLabItem(sourceLine: text, name: "", rawValue: chosen.0, unit: unit, reference: reference, isQualitative: false)
    }

    private static func findToken(_ token: String, in text: String) -> Range<String.Index>? {
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: token, range: searchRange) {
            let before = found.lowerBound > text.startIndex ? text[text.index(before: found.lowerBound)] : nil
            let after = found.upperBound < text.endIndex ? text[found.upperBound] : nil
            let beforeOK = before.map { !$0.isLetter } ?? true
            let afterOK = after.map { !($0.isLetter || $0.isNumber || $0 == "/") } ?? true
            if beforeOK && afterOK { return found }
            searchRange = found.upperBound..<text.endIndex
        }
        return nil
    }

    // MARK: Дата и лаборатория

    func detectDate(in lines: [String]) -> Date? {
        let keywords = ["взят", "забор", "дата выполнения", "дата исследования", "дата анализа", "дата регистрации",
                        "дата поступления", "collected", "date"]
        var fallback: Date?
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("рожд") || lower.contains("birth") || lower.contains("dob") { continue }
            guard let date = Self.firstDate(in: line) else { continue }
            if keywords.contains(where: { lower.contains($0) }) { return date }
            if fallback == nil { fallback = date }
        }
        return fallback
    }

    static func firstDate(in line: String) -> Date? {
        let range = NSRange(line.startIndex..., in: line)
        for match in dateRegex.matches(in: line, range: range) {
            var day = 0, month = 0, year = 0
            if let d = Range(match.range(at: 1), in: line), let m = Range(match.range(at: 2), in: line),
               let y = Range(match.range(at: 3), in: line) {
                day = Int(line[d]) ?? 0; month = Int(line[m]) ?? 0; year = Int(line[y]) ?? 0
                if year < 100 { year += 2000 }
            } else if let y = Range(match.range(at: 4), in: line), let m = Range(match.range(at: 5), in: line),
                      let d = Range(match.range(at: 6), in: line) {
                day = Int(line[d]) ?? 0; month = Int(line[m]) ?? 0; year = Int(line[y]) ?? 0
            }
            guard (1...31).contains(day), (1...12).contains(month), (1990...2100).contains(year),
                  let date = AppLocale.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9)) else { continue }
            return date
        }
        return nil
    }

    func detectLaboratory(in lines: [String]) -> String? {
        let candidates = knownLaboratories + Self.builtInLaboratories
        for line in lines.prefix(40) {
            let lower = line.lowercased()
            if let lab = candidates.first(where: { lower.contains($0.lowercased()) }) { return lab }
        }
        for line in lines.prefix(25) where line.lowercased().contains("лаборатор") {
            let cleaned = line.trimmed
            if cleaned.count <= 80 { return cleaned }
        }
        return nil
    }
}
