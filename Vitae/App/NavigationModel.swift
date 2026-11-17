import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, examinations, dynamics, expenses, catalog, importExport, reminders, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Главная"
        case .examinations: "Обследования"
        case .dynamics: "Динамика"
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
        case .expenses: "rublesign.circle"
        case .catalog: "books.vertical"
        case .importExport: "arrow.up.arrow.down.square"
        case .reminders: "bell"
        case .settings: "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        let index = (Self.allCases.firstIndex(of: self) ?? 0) + 1
        return KeyEquivalent(Character(String(index)))
    }
}

enum AppRoute: Hashable {
    case examination(UUID)
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
        let section: SidebarItem = selection == .dashboard || selection == .expenses ? selection! : .examinations
        selection = section
        paths[section] = [.examination(id)]
    }

    func openDynamics(code: String) {
        selection = .dynamics
        dynamics.mode = .indicator
        dynamics.selectedCode = code
    }

    func compare(_ a: UUID, _ b: UUID) {
        selection = .dynamics
        dynamics.mode = .comparison
        dynamics.comparisonA = a
        dynamics.comparisonB = b
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
