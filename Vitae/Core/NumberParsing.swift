import Foundation

/// Разбор чисел, введённых пользователем или распознанных OCR.
/// Поддерживает десятичную запятую и точку, неразрывные пробелы, «−».
enum NumberParsing {
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmed
        guard !s.isEmpty else { return nil }
        for separator in ["\u{00A0}", "\u{202F}", "\u{2009}", " ", "'"] {
            s = s.replacingOccurrences(of: separator, with: "")
        }
        s = s.replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")

        let hasComma = s.contains(",")
        let hasDot = s.contains(".")
        if hasComma && hasDot {
            if let lastComma = s.lastIndex(of: ","), let lastDot = s.lastIndex(of: "."), lastComma > lastDot {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            s = s.replacingOccurrences(of: ",", with: ".")
        }

        guard s.filter({ $0 == "." }).count <= 1 else { return nil }
        var body = Substring(s)
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }
        guard !body.isEmpty, body != ".",
              body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        if s.hasPrefix(".") { s = "0" + s }
        if s.hasPrefix("-.") { s = "-0" + s.dropFirst() }
        return s
    }

    static func double(_ raw: String) -> Double? {
        guard let normalized = normalize(raw), let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    static func decimal(_ raw: String) -> Decimal? {
        guard let normalized = normalize(raw) else { return nil }
        return Decimal(string: normalized, locale: AppLocale.posix)
    }
}
