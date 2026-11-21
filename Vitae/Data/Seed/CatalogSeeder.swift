import Foundation
import SwiftData

/// Досоздаёт встроенные показатели, которых нет в базе, и дописывает в существующие
/// новые синонимы из обновлённого справочника. Пользовательские изменения
/// (избранное, собственные показатели, свои синонимы) не затрагиваются.
enum CatalogSeeder {
    @MainActor
    @discardableResult
    static func seedIfNeeded(context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<LabTest>())
        let codes = Set(existing.map(\.code))
        let seedByCode = Dictionary(CatalogSeedData.entries.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for test in existing where !test.isCustom {
            guard let entry = seedByCode[test.code] else { continue }
            let known = Set(test.aliases.map(\.searchNormalized))
            let missing = entry.aliases.filter { !known.contains($0.searchNormalized) }
            if !missing.isEmpty {
                test.aliases += missing
                changed = true
            }
        }
        var inserted = 0
        for entry in CatalogSeedData.entries where !codes.contains(entry.code) {
            context.insert(LabTest(code: entry.code, name: entry.name, shortName: entry.shortName, category: entry.category,
                                   defaultUnit: entry.unit, aliases: entry.aliases, details: entry.details,
                                   isQualitative: entry.isQualitative, isPanel: entry.isPanel, panelCode: entry.panelCode,
                                   isCustom: false, isFavorite: false, sortOrder: entry.sortOrder))
            inserted += 1
        }
        if inserted > 0 || changed { try context.save() }
        return inserted
    }
}
