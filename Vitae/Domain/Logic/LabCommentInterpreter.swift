import Foundation

/// Разбор комментария лаборатории, который стоит на бланке вместо референса.
///
/// Лаборатории пишут его двумя способами:
/// - список зон: «< 10 нг/мл - выраженный дефицит; 20-30 - недостаточность; 30-100 - адекватный уровень»;
/// - фраза о желательном уровне: «желательный уровень <5,0 ммоль/л», «уровень >1,0 ммоль/л указывает на низкий риск».
///
/// Референсом считается только зона или уровень, который сама лаборатория назвала адекватным,
/// желательным, оптимальным или нормальным. Если такой зоны нет или их несколько с разными
/// границами — в разных предложениях или в одном, — референс не выводится и статус остаётся
/// «Нет данных для оценки».
enum LabCommentInterpreter {
    struct Zone: Equatable, Sendable {
        var lower: Double?
        var upper: Double?
        var label: String
        /// Зона так, как она записана в комментарии: «< 10 нг/мл - выраженный дефицит».
        var text: String = ""
        /// Граница записана строгим знаком («> 100», «менее 10»): значение на ней в зону не входит.
        var lowerIsStrict = false
        var upperIsStrict = false

        var range: ReferenceRange { ReferenceRange(lower: lower, upper: upper) }

        func contains(_ value: Double) -> Bool {
            let aboveLower = lower.map { lowerIsStrict ? value > $0 : value >= $0 } ?? true
            let belowUpper = upper.map { upperIsStrict ? value < $0 : value <= $0 } ?? true
            return aboveLower && belowUpper
        }
    }

    private static let number = #"([0-9]+(?:[.,][0-9]+)?)"#
    private static let comparator = #"(<=|>=|<|>|≤|≥|не более|не менее|менее|более|до|от)"#

    /// Зона в начале фрагмента: «20-30 - недостаточность», «< 10 нг/мл - выраженный дефицит», «> 150 - …».
    private static let zoneRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:"# + comparator + #"\s*)?"# + number + #"(?:\s*(?:-|–|—)\s*"# + number + #")?"#
            + #"(?:\s*[^\s\d;:,–—-][^\s;:,–—-]*)?\s*(?:-|–|—|:)\s*(.+)$"#,
        options: [.caseInsensitive])
    private static let boundRegex = try! NSRegularExpression(
        pattern: #"(?<![a-zа-я])"# + comparator + #"\s*"# + number, options: [.caseInsensitive])
    private static let rangeRegex = try! NSRegularExpression(
        pattern: number + #"\s*(?:-|–|—)\s*"# + number)

    /// Слова, которыми лаборатория отмечает целевой уровень.
    private static let targetWords = ["адекватн", "желательн", "оптимальн", "норм", "достаточн", "низкий риск", "референс"]

    // MARK: Зоны

    /// Зоны из комментария-списка. Список признаётся, только если в нём минимум две зоны.
    static func zones(in comment: String) -> [Zone] {
        let parts = comment.split(whereSeparator: { $0 == ";" || $0 == "\n" }).map { String($0).trimmed }
        let zones = parts.compactMap(zone(in:))
        return zones.count >= 2 ? zones : []
    }

    private static func zone(in part: String) -> Zone? {
        let range = NSRange(part.startIndex..., in: part)
        guard let match = zoneRegex.firstMatch(in: part, range: range),
              let first = capture(match, 2, in: part).flatMap(NumberParsing.double),
              let label = capture(match, 4, in: part)?.trimmed, label.contains(where: \.isLetter) else { return nil }
        let second = capture(match, 3, in: part).flatMap(NumberParsing.double)
        let op = capture(match, 1, in: part)?.lowercased()
        if let second {
            guard op == nil, first <= second else { return nil }
            return Zone(lower: first, upper: second, label: label, text: part)
        }
        guard let op else { return nil }
        let strict = isStrict(op)
        return isUpperBound(op) ? Zone(lower: nil, upper: first, label: label, text: part, upperIsStrict: strict)
            : Zone(lower: first, upper: nil, label: label, text: part, lowerIsStrict: strict)
    }

    /// Зона, в которую попадает значение. «< 10» и «> 100» — строгие: 10 и 100 в них не входят.
    /// Если подходят несколько зон, берётся целевая: у референса границы нестрогие, поэтому
    /// 100 при «30-100 - адекватный уровень; 100-150 - избыток» — «Адекватный уровень», как и статус.
    /// Среди остальных значение на верхней границе («20» для «10-20» и «20-30») относится
    /// к следующей зоне, а из вложенных («< 10» и «< 20») берётся самая узкая.
    static func zone(for value: Double, in comment: String) -> Zone? {
        zones(in: comment).filter { $0.contains(value) }.min { priority($0, value) < priority($1, value) }
    }

    /// Зона для показа рядом со статусом результата (значок, «Зона по комментарию»): та, куда
    /// попало точное значение, если она не противоречит статусу по референсу.
    static func zone(for value: ParsedValue, in comment: String, status: ResultStatus?) -> Zone? {
        guard value.isExactNumber, let number = value.numeric,
              let zone = zone(for: number, in: comment), agrees(target: isTarget(zone.label), with: status) else { return nil }
        return zone
    }

    private static func priority(_ zone: Zone, _ value: Double) -> (Int, Int, Double) {
        (isTarget(zone.label) ? 0 : 1, zone.upper == value ? 1 : 0, width(zone))
    }

    private static func width(_ zone: Zone) -> Double {
        (zone.upper ?? 1e12) - (zone.lower ?? 0)
    }

    /// Подпись словами лаборатории не спорит со статусом по референсу: целевой уровень —
    /// только «В пределах», остальные зоны — только «Ниже» или «Выше». Без референса спорить не с чем.
    private static func agrees(target: Bool, with status: ResultStatus?) -> Bool {
        switch status {
        case .inRange?: target
        case .below?, .above?: !target
        default: true
        }
    }

    // MARK: Подпись статуса

    /// Подпись статуса словами лаборатории: зона, в которую попало значение («Выраженный дефицит»,
    /// «Недостаточность», «Адекватный уровень»), или целевой уровень из фразы («Желательный уровень»,
    /// «Низкий риск»), если значение в нём. Без такой подписи показывается обычный статус.
    /// С переданным статусом по референсу подпись, которая ему противоречит, не выводится.
    static func label(for value: ParsedValue, comment: String, status: ResultStatus? = nil) -> String? {
        guard !comment.trimmed.isEmpty, value.isExactNumber, value.numeric != nil else { return nil }
        if !zones(in: comment).isEmpty {
            return zone(for: value, in: comment, status: status).map { displayLabel($0.label) }
        }
        guard agrees(target: true, with: status),
              let reference = sentenceReference(in: comment),
              ReferenceEvaluator.status(for: value, reference: reference) == .inRange,
              let phrase = sentences(in: comment).filter(isTarget).lazy.compactMap(targetPhrase(in:)).first
        else { return nil }
        return displayLabel(phrase)
    }

    private static let targetPhraseRegex = try! NSRegularExpression(
        pattern: #"(?<![а-я])(?:(?:желательн|оптимальн|адекватн|нормальн|достаточн)[а-я]*\s+уровень|низк[а-я]*\s+риск)"#,
        options: [.caseInsensitive])

    private static func targetPhrase(in sentence: String) -> String? {
        let lower = sentence.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = targetPhraseRegex.firstMatch(in: lower, range: range),
              let found = Range(match.range, in: lower) else { return nil }
        return String(lower[found])
    }

    /// «адекватный уровень (целевые значения … 30-60)» → «Адекватный уровень».
    static func displayLabel(_ label: String) -> String {
        var text = label
        if let open = text.firstIndex(of: "(") { text = String(text[..<open]) }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:–—-"))
        guard let first = text.first else { return label.trimmed }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Целевой уровень

    /// Референс, который лаборатория указала в комментарии: целевая зона списка
    /// или единственная граница во фразе о желательном уровне.
    static func targetReference(in comment: String) -> ReferenceRange? {
        let zones = zones(in: comment)
        if !zones.isEmpty {
            return unique(zones.filter { isTarget($0.label) }.map(\.range))
        }
        return sentenceReference(in: comment)
    }

    /// Уровень из фраз о желательном уровне. Целевая фраза без чисел выбор не меняет,
    /// а фраза с несколькими уровнями («<3,0 ммоль/л; для лиц с высоким риском <1,8 ммоль/л»)
    /// или разные уровни в разных фразах делают его невозможным.
    private static func sentenceReference(in comment: String) -> ReferenceRange? {
        let targets = sentences(in: comment).filter { isTarget($0) && mentionsLevel($0) }
        let levels = targets.compactMap(bounds(in:))
        guard levels.count == targets.count else { return nil }
        return unique(levels)
    }

    /// В предложении есть граница («<3,0», «не менее 1,0») или интервал («4,1-5,9»).
    private static func mentionsLevel(_ sentence: String) -> Bool {
        let range = NSRange(sentence.startIndex..., in: sentence)
        return rangeRegex.firstMatch(in: sentence, range: range) != nil
            || boundRegex.firstMatch(in: sentence, range: range) != nil
    }

    /// Единственная граница или интервал в предложении; nil, если уровней несколько.
    private static func bounds(in sentence: String) -> ReferenceRange? {
        let range = NSRange(sentence.startIndex..., in: sentence)
        let ranges = rangeRegex.matches(in: sentence, range: range)
        let bounds = boundRegex.matches(in: sentence, range: range)
        if ranges.count == 1, bounds.isEmpty, let match = ranges.first,
           let lower = capture(match, 1, in: sentence).flatMap(NumberParsing.double),
           let upper = capture(match, 2, in: sentence).flatMap(NumberParsing.double), lower <= upper {
            return ReferenceRange(lower: lower, upper: upper)
        }
        guard ranges.isEmpty, bounds.count == 1, let match = bounds.first,
              let op = capture(match, 1, in: sentence)?.lowercased(),
              let value = capture(match, 2, in: sentence).flatMap(NumberParsing.double) else { return nil }
        return isUpperBound(op) ? ReferenceRange(upper: value) : ReferenceRange(lower: value)
    }

    /// Предложения комментария: граница — точка или точка с запятой перед заглавной буквой
    /// либо конец текста. Десятичные запятые и сокращения вроде «вит.D» предложение не рвут.
    private static func sentences(in comment: String) -> [String] {
        comment.replacingOccurrences(of: #"([.;])\s+(?=[А-ЯЁA-Z])"#, with: "$1\n", options: .regularExpression)
            .split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    private static func isTarget(_ text: String) -> Bool {
        let lower = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        // «Недостаточность» содержит «достаточн», но целевой зоной не является.
        let cleaned = lower.replacingOccurrences(of: "недостаточн", with: "")
            .replacingOccurrences(of: "ненормальн", with: "")
        return targetWords.contains { cleaned.contains($0) }
    }

    private static func unique(_ ranges: [ReferenceRange]) -> ReferenceRange? {
        guard let first = ranges.first, ranges.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func isUpperBound(_ op: String) -> Bool {
        ["<", "<=", "≤", "до", "менее", "не более"].contains(op)
    }

    /// «<», «>», «менее», «более» — строго; «≤», «≥», «не более», «до», «от» включают границу.
    private static func isStrict(_ op: String) -> Bool {
        ["<", ">", "менее", "более"].contains(op)
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
