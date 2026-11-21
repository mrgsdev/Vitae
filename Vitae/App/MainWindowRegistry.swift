import AppKit
import SwiftUI

/// Окно, которое можно вывести на передний план. Абстракция отделяет выбор окна от AppKit.
@MainActor
protocol MainWindowHandle: AnyObject {
    func bringToFront()
}

/// Открытые главные окна в порядке активации.
@MainActor
final class MainWindowRegistry {
    private struct Entry {
        weak var navigation: NavigationModel?
        weak var window: (any MainWindowHandle)?
    }

    /// Последний элемент — главное окно, которое было активным последним.
    private var entries: [Entry] = []

    /// Окно появилось или снова показано.
    func register(_ navigation: NavigationModel, window: any MainWindowHandle) {
        entries.removeAll { $0.navigation == nil || $0.navigation === navigation }
        entries.append(Entry(navigation: navigation, window: window))
    }

    /// Окно стало ключевым.
    func didActivate(_ navigation: NavigationModel) {
        guard let index = entries.firstIndex(where: { $0.navigation === navigation }) else { return }
        entries.append(entries.remove(at: index))
    }

    /// Окно закрыто.
    func unregister(_ navigation: NavigationModel) {
        entries.removeAll { $0.navigation == nil || $0.navigation === navigation }
    }

    /// Выполняет маршрут команды меню. `focused` — модель главного окна с фокусом (nil, если в фокусе
    /// редактор, окно обследования или настройки). Без фокуса маршрут получает главное окно, активное
    /// последним, и оно выходит вперёд; `openNewWindow` вызывается, только когда главных окон нет.
    func route(_ route: PendingRoute, focused: NavigationModel?, openNewWindow: (PendingRoute) -> Void) {
        if let focused {
            focused.apply(route)
            return
        }
        entries.removeAll { $0.navigation == nil || $0.window == nil }
        if let entry = entries.last, let navigation = entry.navigation, let window = entry.window {
            window.bringToFront()
            navigation.apply(route)
        } else {
            openNewWindow(route)
        }
    }
}

extension NSWindow: MainWindowHandle {
    func bringToFront() {
        if isMiniaturized { deminiaturize(nil) }
        makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

extension AppEnvironment {
    /// Показывает маршрут в главном окне; новое главное окно открывается, только если ни одного нет.
    func showInMainWindow(_ route: PendingRoute, focused: NavigationModel?, openWindow: OpenWindowAction) {
        mainWindows.route(route, focused: focused) { route in
            pendingRoute = route
            openWindow(id: WindowID.main)
        }
    }
}
