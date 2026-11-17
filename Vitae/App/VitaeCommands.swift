import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Меню приложения и горячие клавиши.
/// ⌘N — новое обследование, ⌘F — поиск, ⌘I — импорт документа, ⌘E — экспорт,
/// ⌘S — сохранить черновик, ⌘, — настройки (стандартно), ⌘W — закрыть окно (стандартно),
/// ⌘1…⌘8 — разделы. Сочетания ⌘I и ⌘E в текстовых редакторах обычно заняты «Курсивом» и
/// «Использовать выделенное для поиска», но в приложении нет меню форматирования и подменю «Найти»,
/// поэтому конфликтов нет.
struct VitaeCommands: Commands {
    let environment: AppEnvironment

    @FocusedValue(\.navigation) private var navigation
    @FocusedValue(\.editorActions) private var editorActions
    @FocusedValue(\.printAction) private var printAction
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("О программе Vitae") { AboutPanel.show() }
        }

        CommandGroup(replacing: .newItem) {
            Button("Новое обследование") {
                openWindow(id: WindowID.editor, value: EditorRequest.new())
            }
            .keyboardShortcut("n")
            .disabled(environment.lock.isLocked)

            Button("Новое окно") {
                openWindow(id: WindowID.main)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Divider()
            Group {
                Button("Импортировать документ…") {
                    Task { await importDocument() }
                }
                .keyboardShortcut("i")

                Menu("Импорт данных") {
                    Button("Восстановить из резервной копии…") { route(.importExportAction(.restoreBackup)) }
                    Button("Импорт результатов из CSV…") { route(.importExportAction(.importCSV)) }
                }

                Divider()
                Button("Экспорт…") { route(.section(.importExport)) }
                    .keyboardShortcut("e")

                Menu("Экспорт данных") {
                    Button("Резервная копия (JSON)…") { Task { await ExportActions.exportBackup(environment: environment) } }
                    Button("Результаты (CSV)…") { Task { await ExportActions.exportResultsCSV(environment: environment) } }
                    Button("Расходы (CSV)…") { Task { await ExportActions.exportExpensesCSV(environment: environment) } }
                }
            }
            // Пока приложение заблокировано, данные нельзя импортировать или выгрузить через меню.
            .disabled(environment.lock.isLocked)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Сохранить черновик") { editorActions?.saveDraft() }
                .keyboardShortcut("s")
                .disabled(editorActions == nil)
            Button("Сохранить обследование") { editorActions?.save() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(editorActions == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button(printAction.map { "Печать: \($0.title)…" } ?? "Печать…") { printAction?.run() }
                .keyboardShortcut("p")
                .disabled(printAction == nil || environment.lock.isLocked)
        }

        CommandGroup(after: .textEditing) {
            Button("Найти…") { SearchFieldFocuser.focus() }
                .keyboardShortcut("f")
        }

        SidebarCommands()
        ToolbarCommands()

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(SidebarItem.allCases) { item in
                Button(item.title) { route(.section(item)) }
                    .keyboardShortcut(item.shortcut)
            }
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Справка Vitae") { openWindow(id: "help") }
                .keyboardShortcut("?")
        }
    }

    private func route(_ route: PendingRoute) {
        if let navigation {
            navigation.apply(route)
        } else {
            environment.pendingRoute = route
            openWindow(id: WindowID.main)
        }
    }

    @MainActor
    private func importDocument() async {
        guard let url = await FilePanels.open(title: "Импорт документа с результатами",
                                              contentTypes: FileStorageService.supportedTypes).first else { return }
        route(.importDocument(DocumentImportRequest(url: url)))
    }
}

/// Экспорт, доступный из меню без открытия раздела.
@MainActor
enum ExportActions {
    static func exportBackup(environment: AppEnvironment, includeAttachments: Bool = true) async {
        guard !environment.lock.isLocked else { return }
        do {
            let data = try BackupService(context: environment.context, fileStorage: environment.fileStorage)
                .exportData(includeAttachments: includeAttachments)
            try await FilePanels.export(data, title: "Резервная копия Vitae",
                                        suggestedName: AutoBackupService.fileName(for: .now), contentType: .json)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось создать резервную копию")
        }
    }

    static func exportResultsCSV(environment: AppEnvironment) async {
        guard !environment.lock.isLocked else { return }
        let data = CSVExporter.results(environment.examinationStore.resultSnapshots())
        do {
            try await FilePanels.export(data, title: "Экспорт результатов", suggestedName: "Vitae — результаты.csv",
                                        contentType: .commaSeparatedText)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось сохранить файл")
        }
    }

    static func exportExpensesCSV(environment: AppEnvironment) async {
        guard !environment.lock.isLocked else { return }
        let data = CSVExporter.expenses(environment.examinationStore.expenseSnapshots())
        do {
            try await FilePanels.export(data, title: "Экспорт расходов", suggestedName: "Vitae — расходы.csv",
                                        contentType: .commaSeparatedText)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось сохранить файл")
        }
    }
}
