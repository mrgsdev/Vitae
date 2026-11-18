import XCTest

/// UI-тесты основных сценариев. Приложение запускается с хранилищем в памяти (`-uiTesting`),
/// поэтому реальные данные пользователя не затрагиваются.
final class VitaeUITests: XCTestCase {
    private var app: XCUIApplication!

    private let sections = ["Главная", "Обследования", "Динамика", "Сравнение", "Расходы", "Справочник анализов",
                            "Импорт и экспорт", "Напоминания", "Настройки"]

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
    }

    @discardableResult
    private func launch(fixture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-ApplePersistenceIgnoreState", "YES"]
        if fixture { app.launchArguments.append("-uiTestingFixture") }
        app.launch()
        self.app = app
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    private func snapshot(_ name: String, element: XCUIElement? = nil) {
        let target = element ?? app.windows.firstMatch
        let shot = target.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["HT_SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func waitForWindowTitle(_ title: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "title == %@", title)
        return app.windows.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    // MARK: - Навигация

    func testSidebarNavigationWithShortcutsAndClicks() {
        launch(fixture: true)
        for (index, title) in sections.enumerated() {
            app.typeKey("\(index + 1)", modifierFlags: .command)
            XCTAssertTrue(waitForWindowTitle(title), "Раздел «\(title)» не открылся по ⌘\(index + 1)")
            snapshot(String(format: "%02d-%@", index + 1, title))
        }
        // Переход кликом по боковой панели.
        app.outlines.firstMatch.staticTexts["Обследования"].click()
        XCTAssertTrue(waitForWindowTitle("Обследования"))
        app.outlines.firstMatch.staticTexts["Главная"].click()
        XCTAssertTrue(waitForWindowTitle("Главная"))
    }

    func testDashboardShowsRealData() {
        launch(fixture: true)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Контроль витамина D"].waitForExistence(timeout: 5), "Карточка последнего обследования")
        XCTAssertTrue(app.staticTexts["Последние изменения".uppercased()].exists)
        XCTAssertTrue(app.staticTexts["Вне референса".uppercased()].exists)
    }

    // MARK: - Обследования

    func testExaminationDetailTabs() {
        launch(fixture: true)
        app.typeKey("2", modifierFlags: .command)
        let table = app.tables["examinations.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let cell = table.staticTexts["Ежегодный чек-ап"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.doubleClick()
        XCTAssertTrue(app.tables["examination.results"].waitForExistence(timeout: 5))
        snapshot("20-Карточка-Результаты")
        for tab in ["Динамика", "Расходы", "Документы"] {
            app.radioButtons[tab].click()
            snapshot("21-Карточка-\(tab)")
        }
    }

    func testCreateExaminationWithTableInput() {
        launch(fixture: false)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(waitForWindowTitle("Новое обследование", timeout: 8))
        let editor = app.windows["Новое обследование"]

        let title = editor.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("UI-тест: ферритин")

        let search = editor.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Поиск анализа")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("Ферритин")
        let checkbox = editor.checkBoxes["catalog.ferritin"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.click()

        let value = editor.textFields["cell.value.Ферритин"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.click()
        value.typeText("42")
        let lower = editor.textFields["cell.lower.Ферритин"]
        lower.click()
        lower.typeText("30")
        let upper = editor.textFields["cell.upper.Ферритин"]
        upper.click()
        upper.typeText("400")
        let price = editor.textFields["cell.price.Ферритин"]
        price.click()
        price.typeText("850")
        snapshot("30-Редактор", element: editor)

        editor.buttons["editor.save"].click()
        XCTAssertTrue(waitForWindowTitle("UI-тест: ферритин", timeout: 8), "После сохранения открывается карточка")
        XCTAssertTrue(app.staticTexts["42"].firstMatch.waitForExistence(timeout: 5))
        snapshot("31-Сохранённое-обследование")

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.tables["examinations.table"].staticTexts["UI-тест: ферритин"].waitForExistence(timeout: 5))
    }

    func testDraftSavedWithCommandS() {
        launch(fixture: false)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(waitForWindowTitle("Новое обследование", timeout: 8))
        let editor = app.windows["Новое обследование"]
        let title = editor.textFields["editor.title"]
        title.click()
        title.typeText("Черновик UI")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(editor.staticTexts.containing(NSPredicate(format: "value BEGINSWITH %@", "Черновик сохранён")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.tables["examinations.table"].staticTexts["Черновик UI"].waitForExistence(timeout: 5))
    }

    // MARK: - Динамика и сравнение

    func testDynamicsAndComparison() {
        launch(fixture: true)
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(waitForWindowTitle("Динамика"))
        XCTAssertTrue(app.staticTexts["Все показатели"].waitForExistence(timeout: 5), "Обзор всех показателей")
        snapshot("40-Динамика-обзор")
        let ferritin = app.descendants(matching: .any)["dynamics.indicator.ferritin"]
        XCTAssertTrue(ferritin.waitForExistence(timeout: 5))
        ferritin.click()
        XCTAssertTrue(waitForWindowTitle("Ферритин"), "Карточка открывает график показателя")
        snapshot("41-Динамика-ферритин")
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(waitForWindowTitle("Сравнение"))
        XCTAssertTrue(app.tables["comparison.table"].waitForExistence(timeout: 5))
        snapshot("42-Сравнение")
    }

    // MARK: - Меню и горячие клавиши

    func testMenusContainCommands() {
        launch(fixture: false)
        let menuBar = app.menuBars.firstMatch
        for item in ["О программе Vitae", "Новое обследование", "Новое окно", "Импортировать документ…", "Экспорт…",
                     "Сохранить черновик", "Сохранить обследование", "Найти…", "Главная", "Обследования", "Динамика",
                     "Сравнение", "Расходы", "Справка Vitae"] {
            XCTAssertTrue(menuBar.menuItems[item].exists, "Нет пункта меню «\(item)»")
        }
        XCTAssertFalse(menuBar.menuItems["Сохранить черновик"].isEnabled, "⌘S недоступно вне редактора")
    }

    func testSettingsWindowOpensWithCommandComma() {
        launch(fixture: true)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.matching(NSPredicate(format: "title CONTAINS %@", "Профиль")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5) || app.windows.count >= 2)
        snapshot("50-Настройки", element: app.windows.firstMatch)
    }

    // MARK: - Размеры окна

    func testLayoutAtMinimumAndLargeWindowSizes() {
        launch(fixture: true)
        let window = app.windows.firstMatch
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.999))
        corner.press(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)))
        for (index, key) in ["1", "2", "3", "4", "5"].enumerated() {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(waitForWindowTitle(sections[index]))
            snapshot("60-Мин-\(sections[index])")
        }
        XCTAssertGreaterThanOrEqual(window.frame.width, 980, "Минимальная ширина окна соблюдается")
        XCTAssertGreaterThanOrEqual(window.frame.height, 620)
    }
}
