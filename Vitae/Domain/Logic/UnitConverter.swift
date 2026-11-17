import Foundation

/// Конвертация единиц измерения. Переводы между массовой и молярной концентрацией
/// выполняются только для показателей с известной молярной массой. Для остальных
/// (например, липопротеин (а): мг/дл ↔ нмоль/л) пересчёт невозможен и значения считаются несопоставимыми.
enum UnitConverter {
    enum Dimension: Equatable {
        case mass, molar, equivalents, cellCount, enzyme, internationalUnits, percent, other
    }

    struct CanonicalUnit: Equatable {
        let id: String
        let dimension: Dimension
        /// Множитель к базовой единице измерения своей размерности.
        let factor: Double
    }

    private static let known: [String: CanonicalUnit] = {
        var map: [String: CanonicalUnit] = [:]
        func add(_ keys: [String], _ id: String, _ dimension: Dimension, _ factor: Double) {
            for key in keys { map[key] = CanonicalUnit(id: id, dimension: dimension, factor: factor) }
        }
        // Массовая концентрация, база — г/л.
        add(["g/l"], "g/L", .mass, 1)
        add(["g/dl"], "g/dL", .mass, 10)
        add(["g/ml"], "g/mL", .mass, 1000)
        add(["mg/ml"], "mg/mL", .mass, 1)
        add(["mg/dl"], "mg/dL", .mass, 0.01)
        add(["mg/l"], "mg/L", .mass, 0.001)
        add(["µg/ml"], "µg/mL", .mass, 0.001)
        add(["µg/dl"], "µg/dL", .mass, 1e-5)
        add(["µg/l", "ng/ml"], "µg/L", .mass, 1e-6)
        add(["ng/dl"], "ng/dL", .mass, 1e-8)
        add(["ng/l", "pg/ml"], "ng/L", .mass, 1e-9)
        // Молярная концентрация, база — моль/л.
        add(["mol/l"], "mol/L", .molar, 1)
        add(["mmol/l"], "mmol/L", .molar, 1e-3)
        add(["µmol/l"], "µmol/L", .molar, 1e-6)
        add(["nmol/l"], "nmol/L", .molar, 1e-9)
        add(["pmol/l"], "pmol/L", .molar, 1e-12)
        add(["meq/l"], "mEq/L", .equivalents, 1e-3)
        // Клетки в объёме, база — 1/л.
        add(["10^12/l", "10^6/µl"], "10^12/L", .cellCount, 1e12)
        add(["10^9/l", "10^3/µl"], "10^9/L", .cellCount, 1e9)
        add(["/µl", "1/µl"], "1/µL", .cellCount, 1e6)
        // Ферментативная активность, база — Ед/л.
        add(["u/l", "iu/l", "mu/ml"], "U/L", .enzyme, 1)
        add(["µkat/l"], "µkat/L", .enzyme, 60)
        add(["nkat/l"], "nkat/L", .enzyme, 0.06)
        // Международные единицы гормонов, база — мкМЕ/мл.
        add(["µiu/ml", "miu/l", "µu/ml", "mu/l"], "µIU/mL", .internationalUnits, 1)
        add(["miu/ml"], "mIU/mL", .internationalUnits, 1000)
        add(["iu/ml"], "IU/mL", .internationalUnits, 1_000_000)
        // Проценты и прочее.
        add(["%"], "%", .percent, 1)
        add(["mmol/mol"], "mmol/mol", .other, 1)
        add(["fl"], "fL", .other, 1)
        add(["pg"], "pg", .other, 1)
        add(["mm/h"], "mm/h", .other, 1)
        return map
    }()

    /// Молярные массы (г/моль) для пересчёта масса ↔ моль.
    static let molarMass: [String: Double] = [
        "glucose": 180.16,
        "lipid.chol": 386.65, "lipid.ldl": 386.65, "lipid.hdl": 386.65,
        "lipid.tg": 885.7,
        "creatinine": 113.12,
        "urea": 60.06,
        "uric_acid": 168.11,
        "bili.total": 584.66, "bili.direct": 584.66,
        "calcium": 40.08,
        "magnesium": 24.305,
        "iron": 55.845,
        "vitd": 400.64,
        "b12": 1355.37,
        "folate": 441.4,
        "testosterone": 288.42,
        "homocysteine": 135.18,
        "electrolytes.na": 22.99, "electrolytes.k": 39.098, "electrolytes.cl": 35.45,
        "cbc.hgb": 16114.5, "cbc.mchc": 16114.5
    ]

    /// Валентность для пересчёта мЭкв/л ↔ ммоль/л.
    static let valence: [String: Double] = [
        "electrolytes.na": 1, "electrolytes.k": 1, "electrolytes.cl": 1, "calcium": 2, "magnesium": 2
    ]

    /// Типичные альтернативные единицы для выбора в динамике.
    static let suggestedUnits: [String: [String]] = [
        "glucose": ["ммоль/л", "мг/дл"],
        "hba1c": ["%", "ммоль/моль"],
        "insulin": ["мкЕд/мл", "пмоль/л"],
        "lipid.chol": ["ммоль/л", "мг/дл"], "lipid.ldl": ["ммоль/л", "мг/дл"],
        "lipid.hdl": ["ммоль/л", "мг/дл"], "lipid.tg": ["ммоль/л", "мг/дл"],
        "apob": ["г/л", "мг/дл"],
        "homocysteine": ["мкмоль/л"],
        "creatinine": ["мкмоль/л", "мг/дл"], "urea": ["ммоль/л", "мг/дл"], "uric_acid": ["мкмоль/л", "мг/дл"],
        "bili.total": ["мкмоль/л", "мг/дл"], "bili.direct": ["мкмоль/л", "мг/дл"],
        "cbc.hgb": ["г/л", "г/дл", "ммоль/л"], "cbc.mchc": ["г/л", "г/дл"],
        "vitd": ["нг/мл", "нмоль/л"], "b12": ["пг/мл", "пмоль/л"], "folate": ["нг/мл", "нмоль/л"],
        "ferritin": ["нг/мл", "мкг/л"], "iron": ["мкмоль/л", "мкг/дл"],
        "testosterone": ["нмоль/л", "нг/дл", "нг/мл"],
        "calcium": ["ммоль/л", "мг/дл"], "magnesium": ["ммоль/л", "мг/дл"],
        "crp": ["мг/л", "мг/дл"], "protein": ["г/л", "г/дл"], "albumin": ["г/л", "г/дл"],
        "tsh": ["мкМЕ/мл", "мМЕ/л"]
    ]

    /// Нормализованная форма единицы: латиница, нижний регистр, без пробелов.
    static func normalizedKey(_ unit: String) -> String {
        var s = unit.lowercased().trimmed
        s = s.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "μ", with: "µ")
            .replacingOccurrences(of: "×", with: "")
            .replacingOccurrences(of: "x10", with: "10")
            .replacingOccurrences(of: "х10", with: "10")
            .replacingOccurrences(of: "*", with: "^")
            .replacingOccurrences(of: "¹²", with: "^12")
            .replacingOccurrences(of: "⁹", with: "^9")
            .replacingOccurrences(of: "⁶", with: "^6")
            .replacingOccurrences(of: "³", with: "^3")
            .replacingOccurrences(of: "10e", with: "10^")
            .replacingOccurrences(of: "^^", with: "^")

        let replacements: [(String, String)] = [
            ("мм/час", "mm/h"), ("мм/ч", "mm/h"),
            ("тыс/мкл", "10^3/µl"), ("млн/мкл", "10^6/µl"), ("тыс/µl", "10^3/µl"), ("млн/µl", "10^6/µl"),
            ("ммоль/моль", "mmol/mol"),
            ("мкмоль", "µmol"), ("ммоль", "mmol"), ("нмоль", "nmol"), ("пмоль", "pmol"), ("моль", "mol"),
            ("мкме", "µiu"), ("мме", "miu"), ("мкед", "µu"), ("мед", "mu"),
            ("мккат", "µkat"), ("нкат", "nkat"), ("кат", "kat"),
            ("мэкв", "meq"), ("мекв", "meq"),
            ("мкг", "µg"), ("мкл", "µl"), ("мг", "mg"), ("нг", "ng"), ("пг", "pg"), ("фл", "fl"),
            ("дл", "dl"), ("мл", "ml"), ("ме", "iu"), ("ед", "u"), ("г", "g"), ("л", "l"), ("ч", "h")
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }
        s = s.replacingOccurrences(of: "umol", with: "µmol")
            .replacingOccurrences(of: "mkmol", with: "µmol")
            .replacingOccurrences(of: "mcmol", with: "µmol")
            .replacingOccurrences(of: "mcg", with: "µg")
            .replacingOccurrences(of: "ug/", with: "µg/")
            .replacingOccurrences(of: "uiu", with: "µiu")
            .replacingOccurrences(of: "uu/", with: "µu/")
            .replacingOccurrences(of: "ukat", with: "µkat")
            .replacingOccurrences(of: "/ul", with: "/µl")
            .replacingOccurrences(of: "units/l", with: "u/l")
        return s
    }

    static func canonical(_ unit: String) -> CanonicalUnit {
        let key = normalizedKey(unit)
        return known[key] ?? CanonicalUnit(id: key, dimension: .other, factor: 1)
    }

    /// Единицы обозначают одно и то же (например, «г/л» и «g/L»).
    static func areEquivalent(_ a: String, _ b: String) -> Bool {
        let ca = canonical(a), cb = canonical(b)
        if ca.id == cb.id { return true }
        return ca.dimension == cb.dimension && ca.dimension != .other && ca.factor == cb.factor
    }

    static func canConvert(from: String, to: String, testCode: String?) -> Bool {
        convert(1, from: from, to: to, testCode: testCode) != nil
    }

    /// Пересчёт значения. Возвращает nil, если корректный пересчёт невозможен.
    static func convert(_ value: Double, from: String, to: String, testCode: String?) -> Double? {
        let a = canonical(from), b = canonical(to)
        if a.id == b.id { return value }
        if a.dimension == b.dimension && a.dimension != .other {
            return value * a.factor / b.factor
        }
        guard let code = testCode else { return nil }

        if code == "hba1c" {
            if a.id == "%" && b.id == "mmol/mol" { return (value - 2.15) * 10.929 }
            if a.id == "mmol/mol" && b.id == "%" { return value / 10.929 + 2.15 }
        }

        if code == "insulin" {
            // 1 мкМЕ/мл = 6,0 пмоль/л.
            if a.dimension == .internationalUnits && b.dimension == .molar {
                let pmol = value * a.factor * 6.0
                return pmol * 1e-12 / b.factor
            }
            if a.dimension == .molar && b.dimension == .internationalUnits {
                let pmol = value * a.factor / 1e-12
                return (pmol / 6.0) / b.factor
            }
        }

        if let mass = molarMass[code] {
            if a.dimension == .mass && b.dimension == .molar {
                return (value * a.factor / mass) / b.factor
            }
            if a.dimension == .molar && b.dimension == .mass {
                return (value * a.factor * mass) / b.factor
            }
        }

        if let valence = valence[code] {
            if a.dimension == .equivalents && b.dimension == .molar {
                return (value * a.factor / valence) / b.factor
            }
            if a.dimension == .molar && b.dimension == .equivalents {
                return (value * a.factor * valence) / b.factor
            }
        }
        return nil
    }

    /// Пересчёт референса (границы пересчитываются по той же формуле).
    static func convert(_ range: ReferenceRange, from: String, to: String, testCode: String?) -> ReferenceRange? {
        if canonical(from).id == canonical(to).id { return range }
        guard canConvert(from: from, to: to, testCode: testCode) else { return nil }
        return ReferenceRange(
            lower: range.lower.flatMap { convert($0, from: from, to: to, testCode: testCode) },
            upper: range.upper.flatMap { convert($0, from: from, to: to, testCode: testCode) },
            text: range.text
        )
    }

    /// Единицы, в которые можно перевести значения показателя (без дублей).
    static func availableUnits(testCode: String, observedUnits: [String], baseUnit: String) -> [String] {
        let candidates = [baseUnit] + observedUnits + (suggestedUnits[testCode] ?? [])
        var seen = Set<String>()
        var result: [String] = []
        for unit in candidates where !unit.trimmed.isEmpty {
            let id = canonical(unit).id
            guard !seen.contains(id), canConvert(from: baseUnit, to: unit, testCode: testCode) else { continue }
            seen.insert(id)
            result.append(unit)
        }
        return result
    }
}
