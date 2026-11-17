import AppKit
import Foundation
import SwiftData
import Testing
@testable import Vitae

@MainActor
@Suite("Распознавание бланков (OCR)")
struct OCRTests {
    private func parser() throws -> LabReportParser {
        let env = try TestEnvironment()
        return LabReportParser(catalog: env.store.catalogIndex(), knownLaboratories: ["Моя лаборатория"])
    }

    @Test func parsesTypicalRussianReport() throws {
        let lines = [
            "ИНВИТРО  Медицинская компания",
            "Пациент: Иванов И. И.   Дата рождения: 01.02.1985",
            "Дата взятия образца: 25.06.2025 08:15",
            "Исследование  Результат  Единицы  Референсные значения",
            "Гемоглобин (HGB)  160  г/л  130 - 180",
            "Лейкоциты (WBC)  6,4  ×10^9/л  4,0 - 9,0",
            "Средняя концентрация гемоглобина в эритроците (MCHC)  335  г/л  300-380",
            "25-OH витамин D  32,5  нг/мл  30 – 100",
            "С-реактивный белок  < 0,6  мг/л  0 - 5",
            "Холестерин ЛПНП  3,1  ммоль/л  < 3,0",
            "Цинк  14,2  мкмоль/л  11 - 18",
            "Белок в моче  отрицательно  г/л"
        ]
        let report = try parser().parse(lines: lines)
        let date = try #require(report.date)
        #expect(AppLocale.calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2025, month: 6, day: 25))
        #expect(report.laboratoryName == "Инвитро")

        func item(_ code: String) -> ParsedLabItem? { report.items.first { $0.testCode == code } }
        let hgb = try #require(item("cbc.hgb"))
        #expect(hgb.rawValue == "160")
        #expect(hgb.unit == "г/л")
        #expect(hgb.reference == ReferenceRange(lower: 130, upper: 180))

        let wbc = try #require(item("cbc.wbc"))
        #expect(wbc.rawValue == "6,4")
        #expect(wbc.reference.upper == 9)

        #expect(item("cbc.mchc")?.rawValue == "335", "длинное название не путается с гемоглобином")
        #expect(item("vitd")?.rawValue == "32,5")
        #expect(item("crp")?.rawValue == "<0,6")
        #expect(item("lipid.ldl")?.reference == ReferenceRange(upper: 3))
        #expect(item("urine.protein")?.rawValue.lowercased() == "отрицательно")

        let zinc = try #require(report.items.first { $0.testCode == nil })
        #expect(zinc.name == "Цинк")
        #expect(zinc.rawValue == "14,2")
        #expect(zinc.reference == ReferenceRange(lower: 11, upper: 18))
        #expect(!report.items.contains { $0.sourceLine.contains("Дата рождения") })
    }

    @Test func detectsKnownLaboratoryAndIsoDate() throws {
        let report = try parser().parse(lines: ["Моя лаборатория, г. Москва", "Collected: 2024-03-15", "Ферритин 42 нг/мл 30-400"])
        #expect(report.laboratoryName == "Моя лаборатория")
        #expect(report.date.map { AppLocale.calendar.component(.month, from: $0) } == 3)
        #expect(report.items.first?.testCode == "ferritin")
    }

    @Test func rowReconstructionGroupsByLine() {
        let lines = [
            OCRLine(text: "160", box: CGRect(x: 0.5, y: 0.80, width: 0.05, height: 0.02)),
            OCRLine(text: "Гемоглобин", box: CGRect(x: 0.1, y: 0.805, width: 0.2, height: 0.02)),
            OCRLine(text: "Ферритин", box: CGRect(x: 0.1, y: 0.70, width: 0.2, height: 0.02)),
            OCRLine(text: "42", box: CGRect(x: 0.5, y: 0.70, width: 0.05, height: 0.02))
        ]
        #expect(OCRService.reconstructRows(lines) == ["Гемоглобин  160", "Ферритин  42"])
    }

    /// Полный цикл: рисуем бланк, распознаём Vision, разбираем.
    @Test func visionRecognizesRenderedReport() async throws {
        let width = 1600, height = 700
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let lines = ["Дата взятия: 12.03.2024", "Гемоглобин   145   г/л   130 - 160", "Ферритин   42   нг/мл   30 - 400"]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 54), .foregroundColor: NSColor.black])
                .draw(at: CGPoint(x: 60, y: height - 140 - index * 160))
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = try #require(context.makeImage())

        let observations = try await OCRService().recognize(cgImage: image)
        let rows = OCRService.reconstructRows(observations)
        let text = rows.joined(separator: "\n").lowercased()
        #expect(text.contains("гемоглобин"))
        #expect(text.contains("145"))

        let report = try parser().parse(lines: rows)
        #expect(report.items.first { $0.testCode == "cbc.hgb" }?.rawValue == "145")
        #expect(report.items.first { $0.testCode == "ferritin" }?.rawValue == "42")
    }
}

@MainActor
@Suite("Схема данных и миграции")
struct MigrationTests {
    @Test func schemaVersionAndModels() {
        #expect(VitaeSchema.versionString == "1.0.0")
        #expect(VitaeMigrationPlan.schemas.count == 1)
        let schema = Schema(versionedSchema: VitaeSchemaV1.self)
        let names = Set(schema.entities.map(\.name))
        #expect(names == ["UserProfile", "Laboratory", "LabTest", "Examination", "TestResult", "Expense", "Attachment", "Reminder"])
    }

    @Test func onDiskStoreReopensThroughMigrationPlan() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HTStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Vitae.store")
        let examID: UUID
        do {
            let container = try PersistenceController.makeContainer(inMemory: false, url: url)
            try CatalogSeeder.seedIfNeeded(context: container.mainContext)
            let store = ExaminationStore(context: container.mainContext)
            var draft = ExaminationDraft(title: "Сохранённое", laboratoryName: "Инвитро")
            draft.rows = store.rowFactory().rows(for: store.catalogIndex().entry("ferritin")!, laboratory: "", currency: "RUB")
            draft.rows[0].value = "42"
            draft.rows[0].price = "650"
            examID = try store.save(draft, finalize: true).id
        }
        let reopened = try PersistenceController.makeContainer(inMemory: false, url: url)
        let exam = try #require(ExaminationStore(context: reopened.mainContext).examination(id: examID))
        #expect(exam.title == "Сохранённое")
        #expect(exam.results.first?.rawValue == "42")
        #expect(exam.expenses.first?.amount == Decimal(650))
        #expect(exam.laboratory?.name == "Инвитро")
        #expect(try CatalogSeeder.seedIfNeeded(context: reopened.mainContext) == 0)
    }
}
