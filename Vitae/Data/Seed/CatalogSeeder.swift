import Foundation
import SwiftData

/// Досоздаёт встроенные показатели, которых нет в базе. Пользовательские изменения
/// (избранное, собственные показатели) не затрагиваются.
enum CatalogSeeder {
    @MainActor
    @discardableResult
    static func seedIfNeeded(context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<LabTest>())
        let codes = Set(existing.map(\.code))
        var inserted = 0
        for entry in CatalogSeedData.entries where !codes.contains(entry.code) {
            context.insert(LabTest(code: entry.code, name: entry.name, shortName: entry.shortName, category: entry.category,
                                   defaultUnit: entry.unit, aliases: entry.aliases, details: entry.details,
                                   isQualitative: entry.isQualitative, isPanel: entry.isPanel, panelCode: entry.panelCode,
                                   isCustom: false, isFavorite: false, sortOrder: entry.sortOrder))
            inserted += 1
        }
        if inserted > 0 { try context.save() }
        return inserted
    }
}
