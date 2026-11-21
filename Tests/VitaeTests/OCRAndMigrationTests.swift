import AppKit
import Foundation
import PDFKit
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

    /// Бланк «Инвитро» из текстового слоя PDF после сборки строк по координатам: названия через дефис,
    /// «Витамин 25(ОН) D» с кириллическими «О» и «Н», «см.комм.» вместо референса,
    /// комментарий на нескольких строках и название, перенесённое на вторую строку.
    @Test func parsesInvitroReportWithComments() throws {
        let lines = [
            "Исследование Результат Единицы Референсные  Комментарий",
            "значения",
            "АлАТ 39 Ед/л < 41",
            "Билирубин общий 10.5 мкмоль/л 3.4 - 20.5",
            "Билирубин прямой 3.9 мкмоль/л <8.6",
            "Билирубин непрямой 6.6 мкмоль/л <19.0",
            "Триглицериды 1.21 ммоль/л см.комм Рекомендации по интерпретации",
            "кардиориска: уровень <1,7 ммоль/л",
            "указывает на низкий риск.",
            "Холестерин 3.83 ммоль/л см.комм Рекомендации по интерпретации:",
            "желательный уровень <5,0 ммоль/л. В",
            "Холестерин-ЛПВП  0.87*  ммоль/л см.комм Рекомендации по интерпретации",
            "кардиориска: уровень >1,0 ммоль/л",
            "указывает на низкий риск.",
            "Холестерин-ЛПНП (по  2.41 ммоль/л см.комм Рекомендации по интерпретации: при",
            "Фридвальду)  отсутствии дополнительных факторов",
            "кардиориска желательный уровень",
            "<3,0 ммоль/л. Индивидуальные",
            "целевые значения ХС ЛПНП для",
            "пациентов высокого и очень высокого",
            "риска определяет врач.",
            "Холестерин не-ЛПВП 2.96 ммоль/л см.комм. Рекомендации по интерпретации: при",
            "отсутствии дополнительных факторов",
            "кардиориска желательный уровень",
            "<3,8 ммоль/л. Индивидуальные",
            "целевые значения для пациентов",
            "групп высокого и очень высокого",
            "риска определяет врач.",
            "Фосфатаза щелочная 96 Ед/л 40 - 150",
            "Витамин 25(ОН) D  26.4*  нг/мл см.комм.  < 10 нг/мл - выраженный дефицит;",
            "< 20 - дефицит;",
            "20-30 - недостаточность;",
            "30-100 - адекватный уровень (целевые",
            "значения при коррекции дефицита",
            "вит.D - 30-60);",
            "Продолжение на следующей странице",
            "стр.1 из 2"
        ]
        let report = try parser().parse(lines: lines)
        func item(_ code: String) -> ParsedLabItem? { report.items.first { $0.testCode == code } }

        #expect(report.items.allSatisfy { $0.testCode != nil }, "все строки бланка привязаны к справочнику")
        #expect(report.items.count == 11, "строки комментариев не принимаются за результаты")

        let alt = try #require(item("alt"))
        #expect(alt.name == "АлАТ", "название как в документе")
        #expect(item("bili.indirect")?.rawValue == "6.6")
        #expect(item("alp")?.name == "Фосфатаза щелочная")

        let tg = try #require(item("lipid.tg"))
        #expect(tg.rawValue == "1.21")
        #expect(tg.reference.text == LabReportParser.commentReferenceText)
        #expect(tg.comment == "Рекомендации по интерпретации кардиориска: уровень <1,7 ммоль/л указывает на низкий риск.")

        #expect(item("lipid.chol")?.rawValue == "3.83")
        #expect(item("lipid.hdl")?.rawValue == "0.87")
        #expect(item("lipid.hdl")?.name == "Холестерин-ЛПВП")

        let ldl = try #require(item("lipid.ldl"))
        #expect(ldl.rawValue == "2.41")
        #expect(ldl.name == "Холестерин-ЛПНП (по Фридвальду)")
        #expect(ldl.comment.hasPrefix("Рекомендации по интерпретации: при отсутствии дополнительных факторов"))
        #expect(ldl.comment.hasSuffix("риска определяет врач."))

        #expect(item("lipid.nonhdl")?.rawValue == "2.96")

        let vitD = try #require(item("vitd"))
        #expect(vitD.rawValue == "26.4")
        #expect(vitD.unit == "нг/мл")
        #expect(vitD.name == "Витамин 25(ОН) D")
        #expect(vitD.comment == "< 10 нг/мл - выраженный дефицит; < 20 - дефицит; 20-30 - недостаточность; "
                + "30-100 - адекватный уровень (целевые значения при коррекции дефицита вит.D - 30-60);",
                "комментарий заканчивается на подвале страницы")

        // Референс из комментария: только уровень, который лаборатория назвала желательным,
        // низким риском или адекватным. Статусы совпадают с отметками «*» на бланке.
        func status(_ code: String) -> ResultStatus? {
            item(code).map { ReferenceEvaluator.status(for: ParsedValue.parse($0.rawValue), reference: $0.reference) }
        }
        #expect(item("lipid.tg")?.reference.upper == 1.7)
        #expect(item("lipid.chol")?.reference.upper == 5.0)
        #expect(item("lipid.hdl")?.reference.lower == 1.0)
        #expect(item("lipid.ldl")?.reference.upper == 3.0)
        #expect(item("lipid.nonhdl")?.reference.upper == 3.8)
        #expect(status("lipid.chol") == .inRange)
        #expect(status("lipid.hdl") == .below, "0.87* отмечено лабораторией")
        #expect(vitD.reference.lower == 30 && vitD.reference.upper == 100, "адекватный уровень 30-100")
        #expect(status("vitd") == .below, "26.4* отмечено лабораторией")
        #expect(LabCommentInterpreter.zone(for: 26.4, in: vitD.comment)?.label == "недостаточность")
    }

    @Test func commentZonesGiveReferenceAndZone() {
        let comment = "< 10 нг/мл - выраженный дефицит; < 20 - дефицит; 20-30 - недостаточность; "
            + "30-100 - адекватный уровень (целевые значения при коррекции дефицита вит.D - 30-60); > 150 - возможен токсический эффект."
        #expect(LabCommentInterpreter.zones(in: comment).count == 5)
        #expect(LabCommentInterpreter.targetReference(in: comment) == ReferenceRange(lower: 30, upper: 100))
        #expect(LabCommentInterpreter.zone(for: 26.4, in: comment)?.label == "недостаточность")
        #expect(LabCommentInterpreter.zone(for: 5, in: comment)?.label == "выраженный дефицит", "из вложенных — самая узкая")
        #expect(LabCommentInterpreter.zone(for: 15, in: comment)?.label == "дефицит")
        #expect(LabCommentInterpreter.zone(for: 10, in: comment)?.label == "дефицит", "«< 10» — строго меньше")
        #expect(LabCommentInterpreter.zone(for: 30, in: comment)?.label.hasPrefix("адекватный") == true, "стык относится к следующей зоне")
        #expect(LabCommentInterpreter.zone(for: 120, in: comment) == nil)
        #expect(LabCommentInterpreter.zone(for: 200, in: comment)?.label == "возможен токсический эффект.")
    }

    @Test func commentSentencesGiveDesirableLevel() {
        #expect(LabCommentInterpreter.targetReference(in: "Рекомендации по интерпретации: желательный уровень <5,0 ммоль/л. "
            + "В индивидуальной оценке кардиориска холестерин следует использовать в комплексе с другими факторами (см. таблицы SCORE).")
            == ReferenceRange(upper: 5))
        #expect(LabCommentInterpreter.targetReference(in: "Рекомендации по интерпретации кардиориска: уровень >1,0 ммоль/л указывает на низкий риск.")
            == ReferenceRange(lower: 1))
        #expect(LabCommentInterpreter.targetReference(in: "Оптимальный уровень 4,1-5,9 ммоль/л.") == ReferenceRange(lower: 4.1, upper: 5.9))
    }

    @Test func statusLabelUsesLabWording() {
        let vitD = "< 10 нг/мл - выраженный дефицит; < 20 - дефицит; 20-30 - недостаточность; "
            + "30-100 - адекватный уровень (целевые значения при коррекции дефицита вит.D - 30-60); > 150 - возможен токсический эффект."
        func label(_ value: String, _ comment: String) -> String? {
            LabCommentInterpreter.label(for: ParsedValue.parse(value), comment: comment)
        }
        #expect(label("8", vitD) == "Выраженный дефицит")
        #expect(label("15", vitD) == "Дефицит")
        #expect(label("26,4", vitD) == "Недостаточность")
        #expect(label("45", vitD) == "Адекватный уровень")
        #expect(label("200", vitD) == "Возможен токсический эффект")
        #expect(label("120", vitD) == nil, "между зонами — обычный статус")
        #expect(label("<8", vitD) == nil, "значение со знаком сравнения не относится к зоне")

        let chol = "Рекомендации по интерпретации: желательный уровень <5,0 ммоль/л. В индивидуальной оценке кардиориска "
            + "холестерин следует использовать в комплексе с другими факторами (см. таблицы SCORE)."
        #expect(label("3,83", chol) == "Желательный уровень")
        #expect(label("6,1", chol) == nil, "вне желательного уровня — обычный статус «Выше»")
        let hdl = "Рекомендации по интерпретации кардиориска: уровень >1,0 ммоль/л указывает на низкий риск."
        #expect(label("1,4", hdl) == "Низкий риск")
        #expect(label("0,87", hdl) == nil)
        #expect(label("5", "") == nil)

        let snapshot = ResultSnapshot(date: .now, testCode: "vitd", testName: "Витамин D", rawValue: "26.4", unit: "нг/мл",
                                      reference: ReferenceRange(lower: 30, upper: 100))
        var withNote = snapshot
        withNote.note = vitD
        #expect(snapshot.statusShortTitle == ResultStatus.below.shortTitle)
        #expect(withNote.statusShortTitle == "Недостаточность")
        #expect(withNote.status == .below, "цвет и счётчики — по референсу")
    }

    @Test func ambiguousCommentsGiveNoReference() {
        // Нет слова о желательном уровне — референс не угадывается.
        #expect(LabCommentInterpreter.targetReference(in: "Высокий риск: уровень >4,9 ммоль/л.") == nil)
        // Два разных желательных уровня — выбрать нельзя.
        #expect(LabCommentInterpreter.targetReference(in: "Желательный уровень <3,0 ммоль/л. Для группы риска желательный уровень <1,8 ммоль/л.") == nil)
        // «Недостаточность» не путается с «достаточным уровнем».
        #expect(LabCommentInterpreter.targetReference(in: "< 20 - дефицит; 20-30 - недостаточность") == nil)
        #expect(LabCommentInterpreter.targetReference(in: "") == nil)
    }

    @Test func pdfTextLayerRowsFollowPageLayout() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let font = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12)]
        // Значение рисуется раньше названия: в текстовом слое порядок будет «0.87», «Холестерин-ЛПВП».
        ("0.87" as NSString).draw(at: CGPoint(x: 160, y: 120), withAttributes: font)
        ("Холестерин-ЛПВП" as NSString).draw(at: CGPoint(x: 20, y: 120), withAttributes: font)
        ("Ферритин" as NSString).draw(at: CGPoint(x: 20, y: 80), withAttributes: font)
        ("42" as NSString).draw(at: CGPoint(x: 160, y: 80), withAttributes: font)
        NSGraphicsContext.current = nil
        context.endPDFPage()
        context.closePDF()
        let page = try #require(PDFDocument(data: data as Data)?.page(at: 0))
        let rows = OCRService.textLayerRows(page).map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
        #expect(rows == ["Холестерин-ЛПВП 0.87", "Ферритин 42"])
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
