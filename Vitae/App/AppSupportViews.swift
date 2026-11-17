import AppKit
import SwiftUI

/// Стандартная панель «О программе» с пояснением о медицинских ограничениях.
@MainActor
enum AboutPanel {
    static func show() {
        let credits = NSAttributedString(
            string: "Личный архив лабораторных анализов.\nДанные хранятся только на этом Mac и никуда не передаются.\n\n" +
                "Vitae не является медицинским изделием, не ставит диагнозов и не назначает лечение.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Vitae"])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Показ ошибок вне контекста конкретного представления.
@MainActor
enum AlertPresenter {
    static func show(error: Error, title: String) {
        show(title: title, message: error.localizedDescription, style: .warning)
    }

    static func show(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

/// Экран блокировки поверх содержимого окна.
struct LockScreenView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Vitae заблокирован")
                    .font(.title2.weight(.semibold))
                Text("Медицинские данные скрыты. Разблокируйте с помощью Touch ID или пароля Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Разблокировать") {
                    Task { await environment.lock.unlock() }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                if let error = environment.lock.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(40)
        }
        .ignoresSafeArea()
        .task { await environment.lock.unlock() }
    }
}

/// Краткая справка: возможности, сочетания клавиш, ограничения.
struct HelpView: View {
    private let shortcuts: [(String, String)] = [
        ("⌘N", "Новое обследование"), ("⇧⌘N", "Новое окно"), ("⌘F", "Поиск в текущем разделе"),
        ("⌘I", "Импорт документа (PDF, изображение)"), ("⌘E", "Экспорт и отчёты"), ("⌘S", "Сохранить черновик в редакторе"),
        ("⌘↩", "Сохранить обследование"), ("⌘P", "Печать отчёта"), ("⌘1…⌘8", "Переход по разделам"),
        ("⌃⌘S", "Показать или скрыть боковую панель"), ("⌘,", "Настройки"), ("⌘W", "Закрыть окно"),
        ("⌫", "Удалить выбранное (с подтверждением)"), ("↑ ↓ ↩ ⇥", "Перемещение по ячейкам таблицы ввода")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Vitae").font(.largeTitle.weight(.bold))
                Text("Личный архив лабораторных анализов: обследования, результаты, динамика показателей и расходы. Все данные хранятся локально.")
                    .foregroundStyle(.secondary)

                GroupBox("Сочетания клавиш") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(shortcuts, id: \.0) { item in
                            GridRow {
                                Text(item.0).font(.body.monospaced()).foregroundStyle(.secondary)
                                Text(item.1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Табличный ввод") {
                    Text("В редакторе обследования можно вставить целый столбец значений из Excel или Numbers: поставьте курсор в первую ячейку и нажмите ⌘V. Диапазон «3,5–5,5», вставленный в колонку нижней границы, заполнит обе границы. Для повторяющихся значений используйте «Массовое заполнение».")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                GroupBox("Медицинские ограничения") {
                    Text("Приложение не является медицинским изделием. Оно не ставит диагнозов, не назначает лечение и не оценивает изменения как улучшение или ухудшение. Статусы рассчитываются только по референсам лаборатории, указанным в бланке; если референса нет, показывается «Нет данных для оценки». Обсуждайте результаты с врачом.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
            }
            .padding(28)
        }
    }
}
