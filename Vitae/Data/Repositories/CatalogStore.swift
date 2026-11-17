import Foundation
import SwiftData

/// Значения формы пользовательского показателя.
struct LabTestForm: Equatable {
    struct Component: Identifiable, Equatable {
        var id = UUID()
        var code: String?
        var name: String = ""
        var unit: String = ""
        var isQualitative = false
    }

    var name: String = ""
    var shortName: String = ""
    var category: TestCategory = .other
    var unit: String = ""
    var aliasesText: String = ""
    var details: String = ""
    var isQualitative = false
    var isPanel = false
    var components: [Component] = []

    var isValid: Bool {
        !name.trimmed.isEmpty && (!isPanel || components.contains { !$0.name.trimmed.isEmpty })
    }

    var aliases: [String] {
        aliasesText.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

@MainActor
struct CatalogStore {
    let context: ModelContext

    func test(code: String) -> LabTest? {
        var descriptor = FetchDescriptor<LabTest>(predicate: #Predicate { $0.code == code })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func components(of panelCode: String) -> [LabTest] {
        let all = (try? context.fetch(FetchDescriptor<LabTest>())) ?? []
        return all.filter { $0.panelCode == panelCode }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func form(for test: LabTest) -> LabTestForm {
        LabTestForm(name: test.name, shortName: test.shortName, category: test.category, unit: test.defaultUnit,
                    aliasesText: test.aliases.joined(separator: ", "), details: test.details,
                    isQualitative: test.isQualitative, isPanel: test.isPanel,
                    components: components(of: test.code).map {
                        LabTestForm.Component(code: $0.code, name: $0.name, unit: $0.defaultUnit, isQualitative: $0.isQualitative)
                    })
    }

    private func nextSortOrder() -> Int {
        ((try? context.fetch(FetchDescriptor<LabTest>()))?.map(\.sortOrder).max() ?? 0) + 10
    }

    /// Создаёт или обновляет пользовательский показатель (и компоненты комплекса).
    @discardableResult
    func saveCustom(_ form: LabTestForm, editing existing: LabTest?) throws -> LabTest {
        var order = nextSortOrder()
        let test: LabTest
        if let existing {
            test = existing
        } else {
            test = LabTest(code: "custom." + UUID().uuidString.lowercased(), name: form.name.trimmed,
                           category: form.category, isCustom: true, sortOrder: order)
            context.insert(test)
            order += 10
        }
        test.name = form.name.trimmed
        test.shortName = form.shortName.trimmed
        test.category = form.category
        test.defaultUnit = form.isPanel ? "" : form.unit.trimmed
        test.aliases = form.aliases
        test.details = form.details.trimmed
        test.isQualitative = form.isPanel ? false : form.isQualitative
        test.isPanel = form.isPanel

        if form.isPanel {
            let current = components(of: test.code)
            let keptCodes = Set(form.components.compactMap(\.code))
            for component in current where !keptCodes.contains(component.code) {
                component.panelCode = nil
            }
            for item in form.components where !item.name.trimmed.isEmpty {
                if let code = item.code, let component = self.test(code: code) {
                    component.name = item.name.trimmed
                    component.defaultUnit = item.unit.trimmed
                    component.isQualitative = item.isQualitative
                    component.category = form.category
                } else {
                    context.insert(LabTest(code: "custom." + UUID().uuidString.lowercased(), name: item.name.trimmed,
                                           category: form.category, defaultUnit: item.unit.trimmed,
                                           isQualitative: item.isQualitative, panelCode: test.code,
                                           isCustom: true, sortOrder: order))
                    order += 10
                }
            }
        }
        try context.save()
        return test
    }

    /// Количество сохранённых результатов по коду (история при удалении сохраняется).
    func resultCount(code: String) -> Int {
        let descriptor = FetchDescriptor<TestResult>(predicate: #Predicate { $0.testCode == code })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Удаляет пользовательский показатель. Результаты остаются в истории как снимки.
    func deleteCustom(_ test: LabTest) throws {
        guard test.isCustom else { return }
        if test.isPanel {
            for component in components(of: test.code) where component.isCustom {
                context.delete(component)
            }
        }
        context.delete(test)
        try context.save()
    }

    /// Создаёт пользовательскую копию встроенного показателя.
    @discardableResult
    func duplicateAsCustom(_ test: LabTest) throws -> LabTest {
        var form = form(for: test)
        form.name += " (моя версия)"
        form.components = form.components.map { var c = $0; c.code = nil; return c }
        return try saveCustom(form, editing: nil)
    }
}
