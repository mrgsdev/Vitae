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
    /// Комментарий лаборатории к результату («см. комм.» и текст рекомендаций).
    var comment: String = ""
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
    /// Отсылка к комментарию вместо референса: «см.комм», «см. комм.», «см. комментарий».
    private static let commentMarkerRegex = try! NSRegularExpression(
        pattern: #"(?<![а-яa-z])см\.?\s*комм?[а-я]*\.?"#, options: [.caseInsensitive])
    static let commentReferenceText = "см. комментарий"
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])([0-3]?[0-9])[./]([01]?[0-9])[./]((?:19|20)?[0-9]{2})(?![0-9])|(?<![0-9])((?:19|20)[0-9]{2})-([01][0-9])-([0-3][0-9])(?![0-9])"#)

    init(catalog: CatalogIndex, knownLaboratories: [String] = []) {
        self.matcher = CatalogMatcher(catalog: catalog)
        self.knownLaboratories = knownLaboratories
    }

    func parse(lines rawLines: [String]) -> ParsedLabReport {
        let lines = rawLines.map(\.trimmed).filter { !$0.isEmpty }
        var items: [ParsedLabItem] = []
        var seenNames: [String: String] = [:]
        // Строка, к которой относятся следующие строки без значений: продолжение названия
        // («Холестерин-ЛПНП (по» + «Фридвальду)») и текст комментария лаборатории.
        var continuationTarget: Int?
        // Строка, прерванная подвалом страницы. Её комментарий продолжается на следующей странице,
        // если подвал её перелистнул («Продолжение на следующей странице», «стр. 1 из 2»).
        var interrupted: (target: Int, pageTurned: Bool)?
        for line in withoutSectionHeaders(lines) {
            if var item = parseLine(line) {
                if let code = item.testCode {
                    let name = item.name.searchNormalized
                    if let previous = seenNames[code] {
                        // Тот же показатель повторно (дубль строки) пропускается. Другое название,
                        // совпавшее с тем же синонимом, не теряется: оно идёт на проверку без привязки.
                        guard previous != name,
                              let unmatched = parseUnmatched(line) ?? parseUnmatchedQualitative(line) else { continue }
                        item = unmatched
                    } else {
                        seenNames[code] = name
                    }
                }
                items.append(item)
                continuationTarget = items.count - 1
                interrupted = nil
                continue
            }
            let text = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
            let lower = text.lowercased()
            if Self.isFooterLine(lower) {
                if let target = continuationTarget ?? interrupted?.target {
                    interrupted = (target, (interrupted?.pageTurned ?? false) || Self.isPageTurn(lower))
                }
                continuationTarget = nil
                continue
            }
            if let paused = interrupted {
                // Хвост подвала до номера страницы и шапка следующей страницы в комментарий не входят.
                guard paused.pageTurned, !isPageHeaderLine(text) else { continue }
                continuationTarget = paused.target
                interrupted = nil
            }
            guard let target = continuationTarget else { continue }
            Self.appendContinuation(text, to: &items[target])
        }
        // Комментарий собран целиком только теперь: из него берётся уровень, который лаборатория
        // назвала адекватным или желательным («30-100 - адекватный уровень», «желательный уровень <5,0»).
        for index in items.indices where items[index].reference.text == Self.commentReferenceText
            && !items[index].reference.hasNumericBounds {
            if let target = LabCommentInterpreter.targetReference(in: items[index].comment) {
                items[index].reference.lower = target.lower
                items[index].reference.upper = target.upper
            }
        }
        return ParsedLabReport(date: detectDate(in: lines), laboratoryName: detectLaboratory(in: lines), items: items)
    }

    /// Строки без заголовков разделов бланка («Гормоны», «Гормоны щитовидной железы»). Заголовок
    /// стоит между комментарием одного результата и следующим результатом, и без этого он
    /// дописывался бы в комментарий: «…> 100 нг/мл - избыток. Гормоны».
    /// Заголовком считается строка вида `looksLikeSectionHeader`, за которой сразу или через
    /// такие же строки идёт результат. Продолжение комментария с заглавной буквы
    /// («Индивидуальные целевые значения ХС ЛПНП для») остаётся: за ним идёт текст, а не результат.
    private func withoutSectionHeaders(_ lines: [String]) -> [String] {
        var kept: [String] = []
        var index = lines.startIndex
        while index < lines.endIndex {
            var end = index
            while end < lines.endIndex, looksLikeSectionHeader(lines[end]) { end += 1 }
            if end == index {
                kept.append(lines[index])
                index += 1
                continue
            }
            let isBeforeResult = end < lines.endIndex && parseLine(lines[end]) != nil
            if !isBeforeResult { kept += lines[index..<end] }
            index = end
        }
        return kept
    }

    /// Строка с заглавной буквы без цифр и знаков препинания в конце, не результат.
    /// Скобки сбалансированы: «Фридвальду)» — окончание названия, а не заголовок.
    private func looksLikeSectionHeader(_ line: String) -> Bool {
        guard let first = line.first, first.isLetter, first.isUppercase,
              let last = line.last, last.isLetter || last == ")",
              !line.contains(where: \.isNumber),
              line.filter({ $0 == "(" }).count == line.filter({ $0 == ")" }).count else { return false }
        return parseLine(line) == nil
    }

    // MARK: Строки результатов

    func parseLine(_ rawLine: String) -> ParsedLabItem? {
        let line = rawLine.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
        let lowerString = line.lowercased().replacingOccurrences(of: "ё", with: "е")
        if Self.isNoiseLine(lowerString) { return nil }

        if let match = matcher.find(inNormalized: lowerString), !Self.hasNarrowingModifier(after: match, in: lowerString),
           !nameContinuesWithNumber(after: match, in: lowerString) {
            let original = Array(line)
            let lower = Array(lowerString)
            let source = original.count == lower.count ? original : lower
            let rest = String(source[min(match.end, source.count)...])
            let (values, comment) = Self.splitComment(rest)
            // «Билирубин в моче  отрицательно»: синоним другого показателя внутри названия, а значение
            // текстом. Строка не теряется, а идёт на проверку без привязки.
            guard var item = parseValues(in: values, isQualitative: match.entry.isQualitative) else {
                return parseUnmatchedQualitative(rawLine)
            }
            let documentName = Self.documentName(source, match: match)
            item.name = documentName.isEmpty ? match.entry.name : documentName
            item.testCode = match.entry.code
            item.sourceLine = rawLine
            Self.applyComment(comment, to: &item)
            if item.unit.isEmpty || UnitConverter.areEquivalent(item.unit, match.entry.unit) {
                item.unit = match.entry.unit
            }
            return item
        }

        return parseUnmatched(rawLine) ?? parseUnmatchedQualitative(rawLine)
    }

    /// Строка не из справочника: «Название  значение  ед.  референс». Нужны название и значение,
    /// а также единица измерения или референс; строки с датами (шапка бланка) пропускаются.
    private func parseUnmatched(_ rawLine: String) -> ParsedLabItem? {
        let line = rawLine.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
        guard Self.firstDate(in: line) == nil, let firstNumber = Self.numberStarts(in: line).first else { return nil }
        let start = valueStart(in: line, firstNumber: firstNumber)
        let namePart = Self.namePart(of: line, before: start)
        // Название результата начинается с заглавной буквы и не заканчивается знаком сравнения:
        // так строки комментариев («желательный уровень <5,0 ммоль/л») не принимаются за результаты.
        // Короче трёх букв название бывает только с цифрой: «Т3», «CA 125».
        let letters = namePart.filter(\.isLetter).count
        guard letters >= 3 || (letters > 0 && namePart.contains(where: \.isNumber)),
              namePart.first(where: \.isLetter)?.isUppercase == true,
              !Self.endsWithComparator(line[..<firstNumber]) else { return nil }
        let (values, comment) = Self.splitComment(String(line[start...]))
        guard var item = parseValues(in: values, isQualitative: false),
              !item.unit.isEmpty || item.reference.hasNumericBounds || comment != nil else { return nil }
        item.name = namePart
        item.testCode = nil
        item.sourceLine = rawLine
        Self.applyComment(comment, to: &item)
        return item
    }

    /// Название так, как оно написано в документе: от начала строки до значения.
    /// Уточнение в скобках сразу после названия сохраняется: «Гемоглобин (HGB)».
    private static func documentName(_ source: [Character], match: CatalogMatcher.Match) -> String {
        let end = min(match.end, source.count)
        let prefix = source[..<min(match.start, end)]
        let start = prefix.contains(where: \.isLetter) ? 0 : min(match.start, end)
        var nameEnd = end
        let tail = source[end...]
        if let open = tail.firstIndex(where: { !$0.isWhitespace }), source[open] == "(" {
            let firstDigit = tail.firstIndex(where: \.isNumber) ?? source.count
            if let close = source[open..<firstDigit].firstIndex(of: ")") {
                nameEnd = close + 1
            } else if firstDigit > open {
                nameEnd = firstDigit
            }
        }
        let valuesEnd = min(source.count, end + splitComment(String(tail)).values.count)
        if let close = closingParenthesisEnd(source, name: start..<nameEnd, valuesEnd: valuesEnd) {
            nameEnd = close
        }
        return String(source[start..<nameEnd]).trimmingCharacters(in: CharacterSet(charactersIn: " .,:;*-–—•·\t<>≤≥="))
    }

    /// Уточнение с цифрами внутри скобки: «Тромбоциты (PLT, 10^9/л) 250». Иначе название обрывалось
    /// на первой цифре, а незакрытую скобку потом «закрывала» чужая строка бланка. Скобка входит
    /// в название, если начинается с буквы, закрывается до комментария и после неё ещё есть значение.
    private static func closingParenthesisEnd(_ source: [Character], name: Range<Int>, valuesEnd: Int) -> Int? {
        let text = source[name]
        guard text.filter({ $0 == "(" }).count > text.filter({ $0 == ")" }).count,
              let open = text.lastIndex(of: "("), name.upperBound < valuesEnd,
              let close = source[name.upperBound..<valuesEnd].firstIndex(of: ")") else { return nil }
        let inside = source[(open + 1)..<close]
        guard inside.first(where: { !$0.isWhitespace })?.isLetter == true, !inside.contains("("),
              source[(close + 1)..<valuesEnd].contains(where: \.isNumber) else { return nil }
        return close + 1
    }

    /// Делит текст после названия на значения и комментарий по отсылке «см. комм.».
    private static func splitComment(_ text: String) -> (values: String, comment: String?) {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = commentMarkerRegex.firstMatch(in: text, range: range),
              let marker = Range(match.range, in: text) else { return (text, nil) }
        return (String(text[..<marker.lowerBound]), String(text[marker.upperBound...]).trimmed)
    }

    private static func applyComment(_ comment: String?, to item: inout ParsedLabItem) {
        guard let comment else { return }
        if item.reference.isEmpty { item.reference.text = commentReferenceText }
        item.comment = comment
    }

    /// Строка без значений после результата: продолжение названия или комментария.
    private static func appendContinuation(_ text: String, to item: inout ParsedLabItem) {
        var text = Substring(text)
        let opened = item.name.filter { $0 == "(" }.count
        let closed = item.name.filter { $0 == ")" }.count
        // Скобку названия закрывает только «)» без своей «(» перед ней: «Фридвальду)» — продолжение
        // «Холестерин-ЛПНП (по», а «Примечание (см. ниже)» — отдельный текст со своей скобкой.
        if opened > closed, let close = text.firstIndex(of: ")"), !text[..<close].contains("(") {
            item.name += " " + text[...close].trimmingCharacters(in: .whitespaces)
            text = text[text.index(after: close)...]
        }
        let rest = text.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty, item.reference.text == commentReferenceText else { return }
        item.comment = item.comment.isEmpty ? rest : item.comment + " " + rest
    }

    /// Подвал страницы и служебные строки: на них комментарий к результату прерывается.
    /// Продолжиться он может только на следующей странице, после её шапки.
    private static func isFooterLine(_ lower: String) -> Bool {
        let markers = ["продолжение на следующей", "перейти на исходный", "документ результатов", "оборудование",
                       "исполнитель", "результаты исследований не являются", "внимание!", "* результат",
                       "исследование результат", "дата печати", "дата взятия", "page "]
        return lower.hasPrefix("стр.") || markers.contains { lower.contains($0) } || isPageTurn(lower)
    }

    private static let pageNumberRegex = try! NSRegularExpression(
        pattern: #"(?<![а-яёa-z])(?:стр\.?|страница|page)\s*[0-9]+\s*(?:из|of|/)\s*[0-9]+"#, options: [.caseInsensitive])

    /// Подвал, после которого начинается следующая страница: «Продолжение на следующей странице»,
    /// номер страницы «стр. 1 из 2», «Страница 1 из 2», «Page 1 of 2».
    private static func isPageTurn(_ lower: String) -> Bool {
        lower.contains("продолжение на следующей")
            || pageNumberRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
    }

    /// Слова заголовка таблицы результатов, в том числе его перенесённой части («значения»).
    private static let tableHeaderWords: Set<String> = [
        "исследование", "исследования", "наименование", "показатель", "тест", "анализ", "результат", "результаты",
        "значение", "значения", "единицы", "ед", "изм", "измерения", "референсные", "референсный", "референсное",
        "интервал", "норма", "нормы", "комментарий", "комментарии", "примечание", "метод"
    ]

    /// Шапка страницы: лаборатория, данные пациента и заказа, даты, заголовок таблицы.
    /// Проверяется только между подвалом и продолжением комментария на следующей странице.
    private func isPageHeaderLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        if Self.isNoiseLine(lower) || lower.hasPrefix("заказ") || Self.firstDate(in: text) != nil { return true }
        if (knownLaboratories + Self.builtInLaboratories).contains(where: { lower.hasPrefix($0.lowercased()) }) { return true }
        let words = lower.split(whereSeparator: { !$0.isLetter })
        return !words.isEmpty && words.allSatisfy { Self.tableHeaderWords.contains(String($0)) }
    }

    /// Название в начале строки: всё до значения, по умолчанию — до первого отдельного числа.
    /// Цифры, приклеенные к названию, остаются в нём: «Т3 свободный», «Витамин B6», «ИФР-1».
    static func namePart(of line: String, before valueStart: String.Index? = nil) -> String {
        let end = valueStart ?? numberStarts(in: line).first ?? line.endIndex
        return String(line[..<end]).trimmingCharacters(in: CharacterSet(charactersIn: " .,:;*-–—•·\t"))
    }

    /// Начала чисел, которые могут быть значением: после хотя бы одной буквы названия
    /// («17-ОН прогестерон» начинается с цифр) и не приклеенные к нему. Целое число сразу
    /// после буквы или после дефиса за буквой или цифрой — часть названия: «Т3», «B6», «ИФР-1», «CA 19-9».
    static func numberStarts(in line: String) -> [String.Index] {
        let range = NSRange(line.startIndex..., in: line)
        return numberRegex.matches(in: line, range: range).compactMap { match in
            guard let digits = Range(match.range(at: 2), in: line) else { return nil }
            let prefix = line[..<digits.lowerBound]
            guard prefix.contains(where: \.isLetter) else { return nil }
            let isInteger = !line[digits].contains { $0 == "." || $0 == "," }
            let previous = prefix.last
            let beforeHyphen = prefix.dropLast().last
            let glued = previous?.isLetter == true
                || (previous.map { "-–‐".contains($0) } == true && (beforeHyphen?.isLetter == true || beforeHyphen?.isNumber == true))
            return isInteger && glued ? nil : digits.lowerBound
        }
    }

    /// Где начинается значение, если первое отдельное число строки — `firstNumber`.
    /// Целое число сразу после названия бывает его частью: «CA 125 12 Ед/мл», «Cyfra 21-1 2.1 нг/мл»,
    /// «Интерлейкин 6 (ИЛ-6) 3.2 пг/мл». Тогда значение — следующее число, с которого строка читается
    /// однозначно. Дробное число, единица или знак сравнения перед ним значат, что значение уже было.
    private func valueStart(in line: String, firstNumber: String.Index) -> String.Index {
        guard !Self.endsWithComparator(line[..<firstNumber]), !isUnambiguousValue(line[firstNumber...]) else { return firstNumber }
        for start in Self.numberStarts(in: line) where start > firstNumber {
            let gap = line[firstNumber..<start].lowercased()
            if gap.contains(where: { "<>≤≥=".contains($0) }) || gap.range(of: "[0-9][.,][0-9]", options: .regularExpression) != nil
                || Self.unitTokens.contains(where: { Self.findToken($0.lowercased(), in: gap) != nil }) { break }
            // Название заканчивается словом, числом или скобкой, а не «-» диапазона: «30 - 100 нг/мл».
            guard let last = gap.trimmingCharacters(in: .whitespaces).last, last.isLetter || last.isNumber || last == ")" else { continue }
            if isUnambiguousValue(line[start...]) { return start }
        }
        return firstNumber
    }

    /// С этого места значение читается однозначно: есть единица или референс, а кроме них
    /// в тексте одно число, и оно стоит первым.
    private func isUnambiguousValue(_ text: Substring) -> Bool {
        let (values, comment) = Self.splitComment(String(text))
        guard let item = parseValues(in: values, isQualitative: false),
              !item.unit.isEmpty || item.reference.hasNumericBounds || comment != nil else { return false }
        let numbers = Self.numbers(in: values)
        let bounds = [item.reference.lower, item.reference.upper].compactMap { $0 }.count
        return numbers.count - bounds - Self.numbers(in: item.unit).count == 1 && numbers.first == item.rawValue
    }

    /// Числа в тексте так, как их записывает разбор значения: «< 35» → «<35».
    private static func numbers(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return numberRegex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { text[$0].replacingOccurrences(of: " ", with: "") }
        }
    }

    private static func endsWithComparator(_ text: Substring) -> Bool {
        text.trimmingCharacters(in: .whitespaces).last.map { "<>≤≥=".contains($0) } ?? false
    }

    /// Короткий синоним с числом после него — начало другого названия, если значение идёт дальше:
    /// «CA 125 12 Ед/мл < 35» — онкомаркер, а не кальций («Ca»). После длинного синонима такое число —
    /// уточнение того же показателя («Витамин D 25-OH 30 нг/мл»), и привязка сохраняется.
    private func nameContinuesWithNumber(after match: CatalogMatcher.Match, in lower: String) -> Bool {
        let chars = Array(lower)
        guard match.end < chars.count, chars[match.start..<match.end].filter(\.isLetter).count < 3,
              let digit = chars[match.end...].firstIndex(where: \.isNumber) else { return false }
        let end = lower.index(lower.startIndex, offsetBy: match.end)
        guard let firstNumber = Self.numberStarts(in: lower).first(where: { $0 >= end }) else { return false }
        return valueStart(in: lower, firstNumber: firstNumber) != lower.index(lower.startIndex, offsetBy: digit)
    }

    /// Слово сразу после найденного синонима сужает смысл: «Холестерин не-ЛПВП»,
    /// «Билирубин непрямой», «Тестостерон свободный» — это другие показатели, а не общий.
    private static func hasNarrowingModifier(after match: CatalogMatcher.Match, in lower: String) -> Bool {
        let chars = Array(CatalogMatcher.searchCharacters(lower))
        guard match.end < chars.count else { return false }
        let tail = String(chars[match.end...]).trimmingCharacters(in: .whitespaces)
        // «Белок в моче не обнаружено»: после названия идёт результат, а не уточнение.
        guard tail.first?.isLetter == true, !qualitativeKeys.contains(where: { tail.hasPrefix($0) }),
              let word = tail.split(whereSeparator: { !$0.isLetter }).first else { return false }
        return narrowingModifiers.contains { word == $0 || ($0.count > 2 && word.hasPrefix($0)) }
    }

    /// Слова сравниваются с хвостом строки в том же виде, в каком в ней искался синоним:
    /// кириллица, похожая на латиницу, заменена (с → c, н → h). Без этого «свободный»
    /// превращается в «cboбoдhый» и не совпадает с «свободн» никогда.
    private static let narrowingModifiers = ["не", "непрям", "неконъюг", "свободн", "биодоступн"]
        .map(CatalogMatcher.searchCharacters)
    private static let qualitativeKeys = qualitativeWords.map(CatalogMatcher.searchCharacters)

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

    /// Качественная строка не из справочника: «HBsAg  не обнаружено  не обнаружено». Значение — первое
    /// известное качественное слово после названия. За ним допустимы только единица, референс из того же
    /// словаря и отсылка к комментарию, и хоть что-то из этого обязательно, как у числовых строк. Так фразы
    /// комментариев («Антитела не обнаружены, что не исключает…», «Результат отрицательный») не становятся результатами.
    private func parseUnmatchedQualitative(_ rawLine: String) -> ParsedLabItem? {
        let line = rawLine.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
        guard Self.firstDate(in: line) == nil else { return nil }
        let (head, comment) = Self.splitComment(line)
        let words = head.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        // Значение из двух слов («не обнаружено») проверяется раньше одного («не»).
        var valueRange: Range<Int>?
        search: for start in 1..<words.count {
            for length in [2, 1] where start + length <= words.count
                && Self.qualitativeToken(words[start..<start + length].joined(separator: " ")) != nil {
                valueRange = start..<start + length
                break search
            }
        }
        guard let valueRange else { return nil }
        let name = words[..<valueRange.lowerBound].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;*-–—•·\t"))
        guard name.filter(\.isLetter).count >= 3, name.first(where: \.isLetter)?.isUppercase == true else { return nil }

        var rest = words[valueRange.upperBound...].joined(separator: " ")
        var unit = ""
        let lowerRest = rest.lowercased()
        if let token = Self.unitTokens.first(where: { lowerRest == $0.lowercased() || lowerRest.hasPrefix($0.lowercased() + " ") }) {
            unit = token
            rest = String(rest.dropFirst(token.count)).trimmed
        }
        var reference = ReferenceRange()
        if !rest.isEmpty {
            guard let text = Self.qualitativeToken(rest) else { return nil }
            reference.text = text
        }
        guard !unit.isEmpty || !reference.isEmpty || comment != nil else { return nil }

        let value = words[valueRange].joined(separator: " ")
        var item = ParsedLabItem(sourceLine: rawLine, name: name, rawValue: value.prefix(1).uppercased() + value.dropFirst(),
                                 unit: unit, reference: reference, isQualitative: true)
        Self.applyComment(comment, to: &item)
        return item
    }

    /// Качественное значение так, как оно написано: слово из `qualitativeWords` или синоним, который
    /// узнаёт `QualitativeMatcher` («отр.», «neg»). Запятая после слова или точка после полного слова —
    /// конец фразы комментария, а не ячейка таблицы; точка допустима только у сокращения.
    private static func qualitativeToken(_ text: String) -> String? {
        guard let last = text.last, !",;:!?".contains(last) else { return nil }
        if last == "." {
            let core = text.dropLast()
            guard !core.contains(" "), core.count <= 5 else { return nil }
        } else if qualitativeSet.contains(text.searchNormalized) {
            return text
        }
        guard text.filter(\.isLetter).count >= 2 else { return nil }
        return ["negative", "positive"].contains(QualitativeMatcher.canonical(text)) ? text : nil
    }

    private static let qualitativeSet = Set(qualitativeWords.map(\.searchNormalized))

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
