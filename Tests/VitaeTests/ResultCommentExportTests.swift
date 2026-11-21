import Foundation
import PDFKit
import SwiftData
import Testing
@testable import Vitae

/// Комментарий лаборатории к результату («см. комм.» и текст рекомендаций) попадает
/// в выгрузку CSV отдельной колонкой и в PDF-отчёт обследования сноской под таблицей.
@MainActor
@Suite("Комментарий лаборатории в экспорте")
struct ResultCommentExportTests {
    /// Комментарий Инвитро к витамину D: по нему статус подписан «Недостаточность».
    private let vitaminNote = "< 10 нг/мл - выраженный дефицит; 10-20 нг/мл - дефицит; 20-30 нг/мл - недостаточность; "
        + "30-100 нг/мл - адекватный уровень; > 100 нг/мл - избыток."
    /// Комментарий с кавычками и переносом строки: в CSV такое поле берётся в кавычки.
    private let lipidNote = "Желательный уровень \"для взрослых\": < 3,8 ммоль/л.\nПовторить через 3 месяца."

    private let date = AppLocale.calendar.date(from: DateComponents(year: 2025, month: 10, day: 5))!

    private func snapshot(_ code: String, _ name: String, value: String, unit: String, reference: ReferenceRange,
                          note: String = "", sortIndex: Int) -> ResultSnapshot {
        var snapshot = ResultSnapshot(examinationTitle: "Осень", date: date, laboratoryName: "Инвитро", testCode: code,
                                      testName: name, sortIndex: sortIndex, rawValue: value, unit: unit, reference: reference)
        snapshot.note = note
        return snapshot
    }

    private var results: [ResultSnapshot] {
        [
            snapshot("cbc.hgb", "Гемоглобин", value: "128", unit: "г/л", reference: ReferenceRange(lower: 130, upper: 160), sortIndex: 0),
            snapshot("vitd", "Витамин D (25-OH)", value: "25", unit: "нг/мл",
                     reference: ReferenceRange(lower: 30, upper: 100, text: LabReportParser.commentReferenceText),
                     note: vitaminNote, sortIndex: 1),
            snapshot("lipid.nonhdl", "Холестерин не-ЛПВП", value: "3,2", unit: "ммоль/л",
                     reference: ReferenceRange(upper: 3.8), note: lipidNote, sortIndex: 2),
        ]
    }

    /// Текст PDF без переносов строк: длинный комментарий в отчёте переносится по словам.
    private func pdfText(_ data: Data) throws -> String {
        let document = try #require(PDFDocument(data: data))
        let text = try #require(document.string)
        return flattened(text)
    }

    private func flattened(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: CSV

    @Test func csvHasCommentColumn() throws {
        let text = try #require(CSV.decodeText(CSVExporter.results(results)))
        let table = CSV.parse(text)

        let commentColumn = try #require(table.headers.firstIndex(of: "Комментарий"))
        #expect(commentColumn == table.headers.count - 1, "новая колонка последняя: прежние колонки не сдвигаются")
        #expect(Array(table.headers.prefix(12)) == ["Дата", "Обследование", "Лаборатория", "Код", "Показатель", "Комплекс",
                                                     "Результат", "Единица", "Нижняя граница", "Верхняя граница",
                                                     "Референс", "Статус"])
        #expect(table.rows.allSatisfy { $0.count == table.headers.count })

        let vitamin = try #require(table.rows.first { $0[4] == "Витамин D (25-OH)" })
        #expect(vitamin[10] == "см. комментарий")
        #expect(vitamin[11] == "Недостаточность")
        #expect(vitamin[commentColumn] == vitaminNote)

        let lipid = try #require(table.rows.first { $0[4] == "Холестерин не-ЛПВП" })
        #expect(lipid[commentColumn] == lipidNote, "кавычки и перенос строки переживают выгрузку")

        let hemoglobin = try #require(table.rows.first { $0[4] == "Гемоглобин" })
        #expect(hemoglobin[commentColumn].isEmpty)
    }

    /// Выгрузка открывается импортом CSV: автосопоставление прежних колонок не меняется,
    /// а комментарий возвращается в результат вместе с подписью статуса.
    @Test func exportedCSVImportsBackWithComment() throws {
        let env = try TestEnvironment()
        let table = CSV.parse(try #require(CSV.decodeText(CSVExporter.results(results))))
        let mapping = CSVMapping.autoDetect(headers: table.headers)
        #expect(mapping.columns[.date] == 0)
        #expect(mapping.columns[.examination] == 1)
        #expect(mapping.columns[.laboratory] == 2)
        #expect(mapping.columns[.testName] == 4)
        #expect(mapping.columns[.value] == 6)
        #expect(mapping.columns[.unit] == 7)
        #expect(mapping.columns[.lower] == 8)
        #expect(mapping.columns[.upper] == 9)
        #expect(mapping.columns[.reference] == 10)
        #expect(mapping.columns[.note] == 12)
        #expect(mapping.columns[.price] == nil)
        #expect(mapping.missingRequired.isEmpty)

        let result = CSVImporter.makeDrafts(table: table, mapping: mapping, catalog: env.store.catalogIndex(), defaultCurrency: "RUB")
        #expect(result.skippedRows.isEmpty)
        #expect(result.unmatchedNames.isEmpty)
        let draft = try #require(result.drafts.first)
        #expect(result.drafts.count == 1)
        #expect(draft.rows.map(\.testCode) == ["cbc.hgb", "vitd", "lipid.nonhdl"])
        let vitamin = try #require(draft.rows.first { $0.testCode == "vitd" })
        #expect(vitamin.value == "25")
        #expect(vitamin.lower == "30")
        #expect(vitamin.upper == "100")
        #expect(vitamin.referenceText == "см. комментарий")
        #expect(vitamin.note == vitaminNote)
        #expect(draft.rows.first { $0.testCode == "lipid.nonhdl" }?.note == lipidNote)
        #expect(draft.rows.first { $0.testCode == "cbc.hgb" }?.note == "")

        let exam = try env.store.save(draft, finalize: true)
        let saved = try #require(exam.sortedResults.first { $0.testCode == "vitd" })
        #expect(saved.note == vitaminNote)
        #expect(ResultSnapshot(saved).statusLabel == "Недостаточность", "подпись статуса снова выводится из комментария")
    }

    /// Чужой CSV: колонку комментария, которую автосопоставление не узнало, выбирают вручную,
    /// как в листе сопоставления; без неё импорт работает как раньше.
    @Test func manualMappingOfCommentColumn() throws {
        let env = try TestEnvironment()
        let table = CSV.parse("""
        Пояснение;Дата;Анализ;Значение
        "20-30 нг/мл - недостаточность; 30-100 нг/мл - адекватный уровень";05.10.2025;Витамин D (25-OH);25
        ;05.10.2025;Гемоглобин;128
        """)
        var mapping = CSVMapping.autoDetect(headers: table.headers)
        #expect(mapping.columns[.note] == nil)
        #expect(mapping.columns[.date] == 1)
        #expect(mapping.columns[.testName] == 2)
        #expect(mapping.columns[.value] == 3)
        #expect(!CSVField.note.isRequired)
        #expect(mapping.missingRequired.isEmpty)

        let catalog = env.store.catalogIndex()
        let withoutComment = CSVImporter.makeDrafts(table: table, mapping: mapping, catalog: catalog, defaultCurrency: "RUB")
        #expect(withoutComment.drafts.first?.rows.map(\.note) == ["", ""])

        mapping.columns[.note] = 0
        let result = CSVImporter.makeDrafts(table: table, mapping: mapping, catalog: catalog, defaultCurrency: "RUB")
        #expect(result.skippedRows.isEmpty)
        let rows = try #require(result.drafts.first?.rows)
        #expect(rows.map(\.testCode) == ["vitd", "cbc.hgb"])
        #expect(rows[0].note == "20-30 нг/мл - недостаточность; 30-100 нг/мл - адекватный уровень")
        #expect(rows[1].note == "")
    }

    // MARK: PDF

    @Test func pdfReportHasCommentFootnotes() throws {
        let expenses = [ExpenseSnapshot(date: date, title: "Витамин D", amount: 1800, currencyCode: "RUB", category: .test)]
        let text = try pdfText(PDFReportService.examinationReport(title: "Осень", date: date, laboratory: "Инвитро",
                                                                  status: .completed, comment: "", results: results,
                                                                  expenses: expenses, profile: nil))
        #expect(text.contains("Недостаточность"), "подпись статуса словами лаборатории остаётся в таблице")
        #expect(text.contains("Комментарии лаборатории"))
        #expect(text.contains("¹ Витамин D (25-OH): " + vitaminNote))
        #expect(text.contains("² Холестерин не-ЛПВП: " + flattened(lipidNote)))
        #expect(!text.contains("³"), "у гемоглобина нет комментария — нет и сноски")

        // Сноски — под таблицей результатов, до раздела расходов.
        let table = try #require(text.range(of: "Холестерин не-ЛПВП"))
        let notes = try #require(text.range(of: "Комментарии лаборатории"))
        let expensesHeading = try #require(text.range(of: "Расходы"))
        #expect(table.upperBound <= notes.lowerBound)
        #expect(notes.upperBound <= expensesHeading.lowerBound)
    }

    @Test func pdfReportWithoutCommentsHasNoFootnotes() throws {
        let plain = results.map { result -> ResultSnapshot in
            var copy = result
            copy.note = ""
            return copy
        }
        let text = try pdfText(PDFReportService.examinationReport(title: "Осень", date: date, laboratory: nil, status: .completed,
                                                                  comment: "", results: plain, expenses: [], profile: nil))
        #expect(text.contains("Витамин D (25-OH)"))
        #expect(!text.contains("Комментарии лаборатории"))
        #expect(!text.contains("¹"))
    }
}
