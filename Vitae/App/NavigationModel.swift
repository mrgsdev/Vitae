import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, examinations, dynamics, comparison, expenses, catalog, importExport, reminders, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Главная"
        case .examinations: "Обследования"
        case .dynamics: "Динамика"
        case .comparison: "Сравнение"
        case .expenses: "Расходы"
        case .catalog: "Справочник анализов"
        case .importExport: "Импорт и экспорт"
        case .reminders: "Напоминания"
        case .settings: "Настройки"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "heart.text.square"
        case .examinations: "list.clipboard"
        case .dynamics: "chart.xyaxis.line"
        case .comparison: "rectangle.split.2x1"
        case .expenses: "rublesign.circle"
        case .catalog: "books.vertical"
        case .importExport: "arrow.up.arrow.down.square"
        case .reminders: "bell"
        case .settings: "gearshape"
        }
    }

    /// Подсказка при наведении на пункт боковой панели: что находится в разделе.
    var hint: String {
        switch self {
        case .dashboard: "Сводка: последнее обследование, отклонения, изменения и расходы"
        case .examinations: "Все сдачи анализов списком: открыть, изменить, повторить"
        case .dynamics: "Графики всех показателей: как менялось каждое значение со временем"
        case .comparison: "Два обследования рядом: что изменилось между ними"
        case .expenses: "Сколько потрачено на анализы и как менялись цены"
        case .catalog: "Список анализов, которые можно вносить, и ваши собственные"
        case .importExport: "Распознать бланк, резервная копия, CSV и PDF-отчёты"
        case .reminders: "Когда сдать анализы повторно"
        case .settings: "Профиль, лаборатории, валюты, блокировка"
        }
    }

    var shortcut: KeyEquivalent {
        let index = (Self.allCases.firstIndex(of: self) ?? 0) + 1
        return KeyEquivalent(Character(String(index)))
    }
}

enum AppRoute: Hashable {
    case examination(UUID)
    case indicator(String)
    case documentImport(DocumentImportRequest)
}

/// Запрос на распознавание документа. Если указан `targetExaminationID`, распознанные
/// результаты добавляются в существующее обследование, иначе создаётся новое.
struct DocumentImportRequest: Hashable {
    var url: URL?
    var targetExaminationID: UUID?
    var token = UUID()
}

/// Состояние навигации одного главного окна. Хранит пути и состояние всех разделов,
/// поэтому при переключении разделов ничего не теряется.
@MainActor
@Observable
final class NavigationModel {
    var selection: SidebarItem? = .dashboard
    var paths: [SidebarItem: [AppRoute]] = [:]

    var examinations = ExaminationsListState()
    var dynamics = DynamicsState()
    var comparison = ComparisonState()
    var expenses = ExpensesState()
    var catalog = CatalogState()
    var importExportAction: ImportExportAction?

    func path(for section: SidebarItem) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[section] ?? [] }, set: { self.paths[section] = $0 })
    }

    func show(_ section: SidebarItem) {
        selection = section
    }

    func openExamination(_ id: UUID) {
        let current = selection ?? .dashboard
        switch current {
        case .dashboard, .expenses:
            paths[current] = [.examination(id)]
        case .dynamics, .comparison:
            // Обследование открывается поверх графика или сравнения, «Назад» возвращает к ним.
            paths[current, default: []].append(.examination(id))
        default:
            selection = .examinations
            paths[.examinations] = [.examination(id)]
        }
    }

    /// Открывает подробный график показателя в разделе «Динамика».
    func openDynamics(code: String) {
        selection = .dynamics
        paths[.dynamics] = [.indicator(code)]
    }

    /// Открывает обзор всех показателей с фильтром по статусу последнего значения.
    func openDynamicsOverview(filter: IndicatorFilter = .all) {
        selection = .dynamics
        paths[.dynamics] = []
        dynamics.filter = filter
        dynamics.searchText = ""
    }

    func compare(_ a: UUID, _ b: UUID) {
        selection = .comparison
        paths[.comparison] = []
        comparison.examinationA = a
        comparison.examinationB = b
    }

    func importDocument(_ url: URL?, into examinationID: UUID? = nil) {
        selection = .importExport
        paths[.importExport] = [.documentImport(DocumentImportRequest(url: url, targetExaminationID: examinationID))]
    }

    func apply(_ route: PendingRoute) {
        switch route {
        case .importDocument(let request): importDocument(request.url, into: request.targetExaminationID)
        case .section(let section): show(section)
        case .examination(let id):
            selection = .examinations
            paths[.examinations] = [.examination(id)]
            examinations.selection = [id]
        case .importExportAction(let action):
            selection = .importExport
            paths[.importExport] = []
            importExportAction = action
        }
    }
}

// MARK: - Focused values & environment

struct EditorActions {
    var saveDraft: () -> Void
    var save: () -> Void
}

struct PrintAction {
    var title: String
    var run: () -> Void
}

private struct NavigationFocusKey: FocusedValueKey { typealias Value = NavigationModel }
private struct EditorActionsKey: FocusedValueKey { typealias Value = EditorActions }
private struct PrintActionKey: FocusedValueKey { typealias Value = PrintAction }

extension FocusedValues {
    var navigation: NavigationModel? {
        get { self[NavigationFocusKey.self] }
        set { self[NavigationFocusKey.self] = newValue }
    }

    var editorActions: EditorActions? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }

    var printAction: PrintAction? {
        get { self[PrintActionKey.self] }
        set { self[PrintActionKey.self] = newValue }
    }
}

private struct NavigationModelKey: EnvironmentKey {
    static let defaultValue: NavigationModel? = nil
}

extension EnvironmentValues {
    /// Модель навигации главного окна (в отдельных окнах обследований — nil).
    var navigationModel: NavigationModel? {
        get { self[NavigationModelKey.self] }
        set { self[NavigationModelKey.self] = newValue }
    }
}

/// Запрос на открытие окна редактора обследования.
struct EditorRequest: Codable, Hashable {
    enum Mode: Codable, Hashable {
        case new
        case edit(UUID)
        case repeatFrom(UUID)
    }

    var token: UUID
    var mode: Mode

    static func new() -> EditorRequest { EditorRequest(token: UUID(), mode: .new) }
    /// Одинаковый токен — повторный запрос активирует уже открытое окно.
    static func edit(_ id: UUID) -> EditorRequest { EditorRequest(token: id, mode: .edit(id)) }
    static func repeatFrom(_ id: UUID) -> EditorRequest { EditorRequest(token: UUID(), mode: .repeatFrom(id)) }
}
