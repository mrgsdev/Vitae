import SwiftData
import SwiftUI
import UserNotifications

struct RemindersView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]

    @State private var showNew = false
    @State private var editing: Reminder?
    @State private var pendingDelete: Reminder?
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        let active = reminders.filter { !$0.isCompleted }
        let completed = reminders.filter(\.isCompleted).sorted { ($0.completedAt ?? $0.dueDate) > ($1.completedAt ?? $1.dueDate) }
        Group {
            if reminders.isEmpty {
                EmptyStateView(title: "Напоминаний нет", systemImage: "bell",
                               message: "Запланируйте повторную сдачу анализов — Vitae пришлёт уведомление.",
                               actionTitle: "Новое напоминание") { showNew = true }
            } else {
                List {
                    if authorization == .denied {
                        Section {
                            Label("Уведомления для Vitae выключены в Системных настройках. Напоминания видны только в приложении.",
                                  systemImage: "bell.slash")
                            Button("Открыть настройки уведомлений") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                    Section("Предстоящие") {
                        if active.isEmpty { Text("Нет активных напоминаний").foregroundStyle(.secondary) }
                        ForEach(active) { row($0) }
                    }
                    if !completed.isEmpty {
                        Section("Выполненные") {
                            ForEach(completed) { row($0) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Напоминания")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNew = true
                } label: {
                    Label("Новое напоминание", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNew) { ReminderEditorSheet(reminder: nil) }
        .sheet(item: $editing) { ReminderEditorSheet(reminder: $0) }
        .confirmationDialog("Удалить напоминание?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { reminder in
            Button("Удалить", role: .destructive) {
                environment.notifications.cancel(id: reminder.id)
                context.delete(reminder)
                try? context.save()
                pendingDelete = nil
            }
        } message: { reminder in
            Text("«\(reminder.title)» будет удалено.")
        }
        .task { authorization = await environment.notifications.authorizationStatus() }
    }

    private func row(_ reminder: Reminder) -> some View {
        let overdue = !reminder.isCompleted && reminder.dueDate < .now
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggleCompleted(reminder)
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(reminder.isCompleted ? "Вернуть в активные" : (reminder.repeatRule == .none ? "Отметить выполненным" : "Выполнено — перенести на следующий срок"))

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title).strikethrough(reminder.isCompleted)
                HStack(spacing: 8) {
                    Label(Fmt.dateTime(reminder.dueDate), systemImage: "calendar")
                        .foregroundStyle(overdue ? .orange : .secondary)
                    if reminder.repeatRule != .none {
                        Label(reminder.repeatRule.title, systemImage: "repeat").foregroundStyle(.secondary)
                    }
                    if !reminder.notificationsEnabled {
                        Label("без уведомления", systemImage: "bell.slash").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                if !reminder.notes.isEmpty {
                    Text(reminder.notes).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = reminder }
        .contextMenu {
            Button("Редактировать…") { editing = reminder }
            Button(reminder.isCompleted ? "Вернуть в активные" : "Отметить выполненным") { toggleCompleted(reminder) }
            Divider()
            Button("Удалить…", role: .destructive) { pendingDelete = reminder }
        }
    }

    private func toggleCompleted(_ reminder: Reminder) {
        if reminder.isCompleted {
            reminder.isCompleted = false
            reminder.completedAt = nil
        } else if let next = reminder.repeatRule.nextDate(after: reminder.dueDate) {
            reminder.dueDate = next
        } else {
            reminder.isCompleted = true
            reminder.completedAt = .now
        }
        try? context.save()
        Task {
            await environment.notifications.schedule(id: reminder.id, title: reminder.title, date: reminder.dueDate,
                                                     enabled: reminder.notificationsEnabled && !reminder.isCompleted)
        }
    }
}

struct ReminderEditorSheet: View {
    let reminder: Reminder?
    var preset: Preset?

    struct Preset {
        var title: String
        var dueDate: Date
        var testCodes: [String]
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LabTest.sortOrder) private var tests: [LabTest]

    @State private var title = ""
    @State private var dueDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var repeatRule: ReminderRepeat = .none
    @State private var notes = ""
    @State private var notificationsEnabled = true
    @State private var testCodes: Set<String> = []
    @State private var testSearch = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(reminder == nil ? "Новое напоминание" : "Редактирование напоминания")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20)
            Form {
                TextField("Название", text: $title, prompt: Text("Например, «Сдать ферритин и витамин D»"))
                DatePicker("Дата и время", selection: $dueDate)
                Picker("Повтор", selection: $repeatRule) {
                    ForEach(ReminderRepeat.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Показывать уведомление", isOn: $notificationsEnabled)
                TextField("Заметка", text: $notes, axis: .vertical).lineLimit(1...3)
                Section("Связанные анализы") {
                    InlineSearchField(text: $testSearch, prompt: "Найти анализ")
                    let roots = tests.filter { $0.panelCode == nil && (testSearch.isEmpty || $0.name.matchesSearch(testSearch)) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(roots.prefix(60), id: \.code) { test in
                                Toggle(test.name, isOn: Binding(
                                    get: { testCodes.contains(test.code) },
                                    set: { if $0 { testCodes.insert(test.code) } else { testCodes.remove(test.code) } }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 130)
                }
                Text("В уведомлении показывается только название напоминания — результаты анализов не отображаются.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmed.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520, height: 620)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let reminder {
            title = reminder.title
            dueDate = reminder.dueDate
            repeatRule = reminder.repeatRule
            notes = reminder.notes
            notificationsEnabled = reminder.notificationsEnabled
            testCodes = Set(reminder.testCodes)
        } else if let preset {
            title = preset.title
            dueDate = preset.dueDate
            testCodes = Set(preset.testCodes)
        }
    }

    private func save() {
        let target = reminder ?? Reminder(title: title, dueDate: dueDate)
        if reminder == nil { context.insert(target) }
        target.title = title.trimmed
        target.dueDate = dueDate
        target.repeatRule = repeatRule
        target.notes = notes
        target.notificationsEnabled = notificationsEnabled
        target.testCodes = Array(testCodes).sorted()
        if target.isCompleted && dueDate > .now { target.isCompleted = false; target.completedAt = nil }
        try? context.save()
        let id = target.id, name = target.title, date = target.dueDate, enabled = notificationsEnabled && !target.isCompleted
        Task { await environment.notifications.schedule(id: id, title: name, date: date, enabled: enabled) }
        dismiss()
    }
}
