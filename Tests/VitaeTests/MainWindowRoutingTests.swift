import Foundation
import Testing
@testable import Vitae

@MainActor
private final class FakeWindow: MainWindowHandle {
    private(set) var broughtToFront = 0

    func bringToFront() { broughtToFront += 1 }
}

@MainActor
@Suite("Команды меню и главные окна")
struct MainWindowRoutingTests {
    /// Сценарий из QA: фокус в редакторе или окне обследования, главное окно открыто,
    /// ⌘1…⌘9 подряд не открывают новые главные окна.
    @Test func shortcutsWithoutFocusReuseOpenMainWindow() {
        let registry = MainWindowRegistry()
        let navigation = NavigationModel()
        let window = FakeWindow()
        registry.register(navigation, window: window)
        var opened: [PendingRoute] = []

        for item in SidebarItem.allCases {
            registry.route(.section(item), focused: nil) { opened.append($0) }
        }

        #expect(opened.isEmpty)
        #expect(navigation.selection == SidebarItem.allCases.last)
        #expect(window.broughtToFront == SidebarItem.allCases.count)
    }

    @Test func focusedMainWindowGetsRouteAndOthersStayUnchanged() {
        let registry = MainWindowRegistry()
        let first = NavigationModel(), second = NavigationModel()
        let firstWindow = FakeWindow(), secondWindow = FakeWindow()
        registry.register(first, window: firstWindow)
        registry.register(second, window: secondWindow)
        registry.didActivate(first)
        var opened: [PendingRoute] = []

        registry.route(.section(.expenses), focused: second) { opened.append($0) }

        #expect(second.selection == .expenses)
        #expect(first.selection == .dashboard)
        #expect(opened.isEmpty)
        #expect(firstWindow.broughtToFront == 0)
        #expect(secondWindow.broughtToFront == 0)
    }

    @Test func routeGoesOnlyToMostRecentlyActiveMainWindow() {
        let registry = MainWindowRegistry()
        let first = NavigationModel(), second = NavigationModel()
        let firstWindow = FakeWindow(), secondWindow = FakeWindow()
        registry.register(first, window: firstWindow)
        registry.register(second, window: secondWindow)
        registry.didActivate(first)
        var opened: [PendingRoute] = []

        registry.route(.importExportAction(.importCSV), focused: nil) { opened.append($0) }

        #expect(opened.isEmpty)
        #expect(first.selection == .importExport)
        #expect(first.importExportAction == .importCSV)
        #expect(firstWindow.broughtToFront == 1)
        #expect(second.selection == .dashboard)
        #expect(second.importExportAction == nil)
        #expect(secondWindow.broughtToFront == 0)
    }

    @Test func newMainWindowOpensOnlyWhenNoneIsOpen() {
        let registry = MainWindowRegistry()
        let navigation = NavigationModel()
        let window = FakeWindow()
        let route = PendingRoute.importDocument(DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/бланк.pdf")))
        var opened: [PendingRoute] = []

        registry.route(route, focused: nil) { opened.append($0) }
        #expect(opened == [route])

        registry.register(navigation, window: window)
        registry.route(route, focused: nil) { opened.append($0) }
        #expect(opened == [route])
        #expect(window.broughtToFront == 1)

        registry.unregister(navigation)
        registry.route(.section(.reminders), focused: nil) { opened.append($0) }
        #expect(opened == [route, .section(.reminders)])
        #expect(navigation.selection == .importExport)
    }

    @Test func releasedWindowIsSkipped() {
        let registry = MainWindowRegistry()
        let first = NavigationModel(), second = NavigationModel()
        let firstWindow = FakeWindow()
        var secondWindow: FakeWindow? = FakeWindow()
        registry.register(first, window: firstWindow)
        registry.register(second, window: secondWindow!)
        secondWindow = nil
        var opened: [PendingRoute] = []

        registry.route(.section(.catalog), focused: nil) { opened.append($0) }

        #expect(opened.isEmpty)
        #expect(first.selection == .catalog)
        #expect(firstWindow.broughtToFront == 1)
        #expect(second.selection == .dashboard)
    }
}
