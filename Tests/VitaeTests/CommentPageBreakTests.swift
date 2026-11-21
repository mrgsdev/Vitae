import Foundation
import Testing
@testable import Vitae

/// Комментарий лаборатории, перенесённый на следующую страницу бланка: подвал первой страницы
/// («Продолжение на следующей странице», «стр. 1 из 2») и шапка второй в него не входят,
/// а продолжение приклеивается к тому же результату.
@MainActor
@Suite("Комментарий через границу страниц")
struct CommentPageBreakTests {
    private func parse(_ lines: [String]) throws -> ParsedLabReport {
        let env = try TestEnvironment()
        return LabReportParser(catalog: env.store.catalogIndex()).parse(lines: lines)
    }

    private func status(_ item: ParsedLabItem) -> ResultStatus {
        ReferenceEvaluator.status(for: ParsedValue.parse(item.rawValue), reference: item.reference)
    }

    /// Строки двухстраничного бланка в том виде, в каком их собирает `OCRService` из текстового слоя:
    /// подвал страницы — одна строка, у второй страницы шапки нет.
    @Test func commentContinuesAfterPageFooter() throws {
        let report = try parse([
            "ИНВИТРО",
            "Пациент: Тестов Тест Тестович",
            "Дата рождения: 01.01.1990",
            "Дата взятия образца: 14.11.2026 08:30",
            "Заказ № 123456789",
            "Исследование  Результат  Единицы  Референсные значения  Комментарий",
            "Ферритин  28  нг/мл  30 - 400",
            "Витамин 25(ОН) D  34  нг/мл  см.комм.  < 10 нг/мл - выраженный дефицит;",
            "10-30 нг/мл - недостаточность;",
            "Продолжение на следующей странице  Стр. 1 из 2",
            "30-100 нг/мл - адекватный уровень;",
            "> 100 нг/мл - избыток.",
            "Витамин B12  250  пг/мл  191 - 663",
            "Фолиевая кислота  7.2  нг/мл  > 3.89",
            "Стр. 2 из 2"
        ])
        let vitD = try #require(report.items.first { $0.testCode == "vitd" })
        #expect(vitD.comment == "< 10 нг/мл - выраженный дефицит; 10-30 нг/мл - недостаточность; "
                + "30-100 нг/мл - адекватный уровень; > 100 нг/мл - избыток.")
        #expect(vitD.reference.lower == 30 && vitD.reference.upper == 100, "адекватный уровень со второй страницы")
        #expect(status(vitD) == .inRange)

        #expect(report.items.map(\.testCode) == ["ferritin", "vitd", "b12", "folate"])
        let b12 = try #require(report.items.first { $0.testCode == "b12" })
        #expect(b12.rawValue == "250")
        #expect(b12.comment.isEmpty)
    }

    /// Бланк, где подвал занимает несколько строк, а вторая страница повторяет шапку:
    /// лабораторию, данные пациента и заказа, заголовок таблицы на двух строках.
    @Test func footerAndNextPageHeaderStayOutOfComment() throws {
        let report = try parse([
            "Исследование Результат Единицы Референсные  Комментарий",
            "значения",
            "Витамин 25(ОН) D  26.4*  нг/мл см.комм.  < 10 нг/мл - выраженный дефицит;",
            "< 20 - дефицит;",
            "20-30 - недостаточность;",
            "Результаты исследований не являются диагнозом, необходима консультация",
            "специалиста.",
            "Продолжение на следующей странице",
            "стр.1 из 2",
            "ИНВИТРО",
            "Пациент: Иванов И. И.   Дата рождения: 01.02.1985",
            "Пол: М  Возраст: 40",
            "Заказ № 123456789",
            "Дата взятия образца: 25.06.2025 08:15",
            "Исследование Результат Единицы Референсные  Комментарий",
            "значения",
            "30-100 - адекватный уровень (целевые",
            "значения при коррекции дефицита",
            "вит.D - 30-60);",
            "> 150 - возможен токсический эффект.",
            "Тиреотропный гормон (ТТГ) 2.1 мкМЕ/мл 0.4 - 4.0",
            "Результаты исследований не являются диагнозом, необходима консультация",
            "специалиста.",
            "стр.2 из 2"
        ])
        let vitD = try #require(report.items.first { $0.testCode == "vitd" })
        #expect(vitD.comment == "< 10 нг/мл - выраженный дефицит; < 20 - дефицит; 20-30 - недостаточность; "
                + "30-100 - адекватный уровень (целевые значения при коррекции дефицита вит.D - 30-60); "
                + "> 150 - возможен токсический эффект.")
        #expect(vitD.reference.lower == 30 && vitD.reference.upper == 100)
        #expect(status(vitD) == .below, "26.4* отмечено лабораторией")

        #expect(report.items.map(\.testCode) == ["vitd", "tsh"])
        #expect(report.items.first { $0.testCode == "tsh" }?.reference == ReferenceRange(lower: 0.4, upper: 4))
    }

    /// Если после подвала и шапки сразу идут результаты, комментарий заканчивается на подвале;
    /// номер страницы может быть записан и словом «Страница».
    @Test func commentEndsAtFooterWhenResultsFollow() throws {
        let report = try parse([
            "Холестерин 3.83 ммоль/л см.комм Рекомендации по интерпретации:",
            "желательный уровень <5,0 ммоль/л.",
            "Страница 1 из 2",
            "Пациент: Иванов И. И.",
            "Триглицериды 1.21 ммоль/л < 1.7",
            "Страница 2 из 2"
        ])
        let chol = try #require(report.items.first { $0.testCode == "lipid.chol" })
        #expect(chol.comment == "Рекомендации по интерпретации: желательный уровень <5,0 ммоль/л.")
        #expect(chol.reference.upper == 5)

        let tg = try #require(report.items.first { $0.testCode == "lipid.tg" })
        #expect(tg.reference == ReferenceRange(upper: 1.7))
        #expect(tg.comment.isEmpty)
    }
}
