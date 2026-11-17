import SwiftData
import SwiftUI

/// Настройки: окно Settings (⌘,) и раздел боковой панели используют одно содержимое.
struct SettingsView: View {
    var isInline = false

    var body: some View {
        TabView {
            ProfileSettingsView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
            LaboratoriesSettingsView()
                .tabItem { Label("Лаборатории", systemImage: "building.2") }
            CurrencySettingsView()
                .tabItem { Label("Валюты", systemImage: "dollarsign.circle") }
            SecuritySettingsView()
                .tabItem { Label("Безопасность", systemImage: "lock.shield") }
            BackupSettingsView()
                .tabItem { Label("Резервные копии", systemImage: "externaldrive") }
            DataSettingsView()
                .tabItem { Label("Данные", systemImage: "internaldrive") }
            UpdatesSettingsView()
                .tabItem { Label("Обновления", systemImage: "arrow.down.app") }
        }
        .padding(isInline ? 20 : 0)
        .navigationTitle("Настройки")
    }
}

struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        let profile = profiles.first
        Form {
            Section {
                TextField("Имя", text: Binding(get: { profile?.name ?? "" }, set: { value in edit { $0.name = value } }), prompt: Text("Не указано"))
                Toggle("Указать дату рождения", isOn: Binding(
                    get: { profile?.birthDate != nil },
                    set: { enabled in
                        edit { $0.birthDate = enabled ? ($0.birthDate ?? Calendar.current.date(byAdding: .year, value: -30, to: .now)) : nil }
                    }
                ))
                if let birth = profile?.birthDate {
                    DatePicker("Дата рождения", selection: Binding(get: { birth }, set: { value in edit { $0.birthDate = value } }),
                               displayedComponents: .date)
                }
                Picker("Пол", selection: Binding(get: { profile?.sex ?? .unspecified }, set: { value in edit { $0.sex = value } })) {
                    ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
                }
                TextField("Заметки", text: Binding(get: { profile?.notes ?? "" }, set: { value in edit { $0.notes = value } }), prompt: Text("Хронические состояния, аллергии, постоянные препараты"), axis: .vertical)
                    .lineLimit(2...5)
            } footer: {
                Text("Имя и дата рождения выводятся в PDF-отчётах. Пол и возраст не используются для оценки результатов — статусы рассчитываются только по референсам лаборатории.")
            }
        }
        .formStyle(.grouped)
    }

    private func edit(_ change: (UserProfile) -> Void) {
        let profile: UserProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = UserProfile()
            context.insert(profile)
        }
        change(profile)
        try? context.save()
    }
}

struct LaboratoriesSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Laboratory.name) private var laboratories: [Laboratory]
    @State private var selection: Laboratory.ID?
    @State private var pendingDelete: Laboratory?
    @State private var newName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                List(laboratories, selection: $selection) { lab in
                    VStack(alignment: .leading) {
                        Text(lab.name)
                        Text(Fmt.count(lab.examinations.count, one: "обследование", few: "обследования", many: "обследований"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(lab.id)
                    .contextMenu {
                        Button("Удалить…", role: .destructive) { pendingDelete = lab }
                    }
                }
                .listStyle(.bordered)
                HStack {
                    TextField("Новая лаборатория", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Добавить", action: add).disabled(newName.trimmed.isEmpty)
                }
                .padding(.top, 8)
            }
            .frame(width: 260)
            .padding()

            if let lab = laboratories.first(where: { $0.id == selection }) {
                LaboratoryDetailForm(laboratory: lab) { pendingDelete = lab }
            } else {
                ContentUnavailableView("Выберите лабораторию", systemImage: "building.2",
                                       description: Text("Лаборатории добавляются автоматически при сохранении обследований."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("Удалить лабораторию?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { lab in
            Button("Удалить", role: .destructive) {
                context.delete(lab)
                try? context.save()
                selection = nil
                pendingDelete = nil
            }
        } message: { lab in
            Text("«\(lab.name)» будет удалена из списка. Обследования (\(lab.examinations.count)) сохранятся, но останутся без указания лаборатории.")
        }
    }

    private func add() {
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        let lab = ExaminationStore(context: context).laboratory(named: name)
        try? context.save()
        selection = lab?.id
        newName = ""
    }
}

private struct LaboratoryDetailForm: View {
    @Bindable var laboratory: Laboratory
    let onDelete: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            TextField("Название", text: $laboratory.name)
            TextField("Адрес", text: $laboratory.address)
            TextField("Телефон", text: $laboratory.phone)
            TextField("Сайт", text: $laboratory.website)
            TextField("Заметки", text: $laboratory.notes, axis: .vertical).lineLimit(2...4)
            Section {
                Button("Удалить лабораторию…", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
        .onDisappear { try? context.save() }
        .onChange(of: laboratory.name) { _, _ in try? context.save() }
    }
}

struct CurrencySettingsView: View {
    @AppStorage(SettingsKey.defaultCurrency) private var defaultCurrency = "RUB"
    @Query private var expenses: [Expense]
    @State private var rates: [String: String] = [:]

    var body: some View {
        let used = Array(Set(expenses.map(\.currencyCode))).filter { $0 != defaultCurrency }
            .sorted { CurrencyCatalog.order($0) < CurrencyCatalog.order($1) }
        Form {
            Section {
                Picker("Основная валюта", selection: $defaultCurrency) {
                    ForEach(CurrencyCatalog.codes, id: \.self) { Text(CurrencyCatalog.title($0)).tag($0) }
                }
            } footer: {
                Text("Подставляется в новые обследования и расходы.")
            }
            Section {
                if used.isEmpty {
                    Text("Все расходы в основной валюте — курсы не нужны.").foregroundStyle(.secondary)
                }
                ForEach(used, id: \.self) { code in
                    LabeledContent("1 \(code) =") {
                        HStack {
                            TextField("курс", text: Binding(
                                get: { rates[code] ?? AppSettings.exchangeRates[code]?.editingString ?? "" },
                                set: { rates[code] = $0; saveRate(code, $0) }
                            ))
                            .frame(width: 120)
                            Text(defaultCurrency)
                        }
                    }
                }
            } header: {
                Text("Курсы для сводных итогов")
            } footer: {
                Text("Суммы в разных валютах не складываются автоматически. Если задать курсы вручную, в разделе «Расходы» появится приблизительный общий итог в основной валюте. Курсы не загружаются из интернета.")
            }
        }
        .formStyle(.grouped)
    }

    private func saveRate(_ code: String, _ text: String) {
        var all = AppSettings.exchangeRates
        if let value = NumberParsing.decimal(text), value > 0 { all[code] = value } else { all.removeValue(forKey: code) }
        AppSettings.exchangeRates = all
    }
}

struct SecuritySettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(SettingsKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingsKey.lockTimeoutMinutes) private var lockTimeout = 5

    var body: some View {
        Form {
            Section {
                Toggle("Блокировать Vitae", isOn: $lockEnabled)
                    .disabled(!AppLockManager.isAvailable)
                Picker("Блокировать после бездействия", selection: $lockTimeout) {
                    Text("1 минуты").tag(1)
                    Text("5 минут").tag(5)
                    Text("15 минут").tag(15)
                    Text("1 часа").tag(60)
                }
                .disabled(!lockEnabled)
                Button("Заблокировать сейчас") { environment.lock.lockNow() }
                    .disabled(!lockEnabled)
            } header: {
                Text("Блокировка")
            } footer: {
                Text(AppLockManager.isAvailable
                     ? "При запуске и после ухода из приложения содержимое окон скрывается до подтверждения Touch ID или паролем учётной записи Mac."
                     : "На этом Mac не настроены Touch ID или пароль учётной записи — блокировка недоступна.")
            }
            Section("Хранение данных") {
                Label("Все данные хранятся локально: ~/Library/Application Support/Vitae.", systemImage: "internaldrive")
                Label("Регистрация и сервер не требуются. Сеть нужна только для проверки обновлений на GitHub, медицинские данные никуда не отправляются.", systemImage: "wifi.slash")
                Label("Медицинские значения не записываются в системный журнал.", systemImage: "doc.text.magnifyingglass")
                Label("Файлы документов сохраняются с правами доступа только для владельца и с классом защиты файлов macOS. Для шифрования диска включите FileVault.",
                      systemImage: "lock.doc")
            }
        }
        .formStyle(.grouped)
    }
}

struct BackupSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(SettingsKey.autoBackupEnabled) private var autoBackupEnabled = true
    @AppStorage(SettingsKey.autoBackupIntervalDays) private var interval = 7
    @AppStorage(SettingsKey.autoBackupKeepCount) private var keepCount = 10
    @State private var lastBackup = AppSettings.lastAutoBackup
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Автоматическое резервное копирование", isOn: $autoBackupEnabled)
                Picker("Периодичность", selection: $interval) {
                    Text("Ежедневно").tag(1)
                    Text("Раз в неделю").tag(7)
                    Text("Раз в месяц").tag(30)
                }
                .disabled(!autoBackupEnabled)
                Stepper("Хранить копий: \(keepCount)", value: $keepCount, in: 1...50)
                LabeledContent("Последняя копия", value: lastBackup.map(Fmt.dateTime) ?? "ещё не создавалась")
            } footer: {
                Text("Копия создаётся при запуске приложения, если с прошлой прошло больше выбранного интервала. Копии включают документы.")
            }
            Section {
                Button("Создать копию сейчас") {
                    do {
                        try AutoBackupService.createBackup(context: environment.context, fileStorage: environment.fileStorage)
                        lastBackup = AppSettings.lastAutoBackup
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                Button("Показать папку с копиями") {
                    NSWorkspace.shared.activateFileViewerSelecting([AutoBackupService.backupFiles().first ?? AppDirectories.backups])
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }
}

struct DataSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @Query private var examinations: [Examination]
    @Query private var results: [TestResult]
    @Query private var expenses: [Expense]
    @Query private var attachments: [Attachment]

    @State private var confirmErase = false
    @State private var confirmEraseFinal = false
    @State private var info: String?
    @State private var storageSize: Int64 = 0

    var body: some View {
        Form {
            Section("Статистика") {
                LabeledContent("Обследований", value: "\(examinations.count)")
                LabeledContent("Результатов", value: "\(results.count)")
                LabeledContent("Записей расходов", value: "\(expenses.count)")
                LabeledContent("Документов", value: "\(attachments.count) · \(Fmt.fileSize(storageSize))")
                LabeledContent("Версия схемы данных", value: VitaeSchema.versionString)
            }
            Section {
                Button("Удалить неиспользуемые файлы") {
                    let referenced = Set(attachments.map(\.storedFileName))
                    let removed = environment.fileStorage.removeOrphans(keeping: referenced)
                    storageSize = environment.fileStorage.totalSize()
                    info = removed == 0 ? "Неиспользуемых файлов нет." : "Удалено файлов: \(removed)."
                }
                Button("Показать папку данных в Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppDirectories.root])
                }
                if let info { Text(info).foregroundStyle(.secondary) }
            } header: {
                Text("Обслуживание")
            }
            Section {
                Button("Удалить все данные…", role: .destructive) { confirmErase = true }
            } footer: {
                Text("Перед удалением автоматически создаётся резервная копия. Встроенный справочник сохраняется.")
            }
        }
        .formStyle(.grouped)
        .onAppear { storageSize = environment.fileStorage.totalSize() }
        .confirmationDialog("Удалить все данные?", isPresented: $confirmErase) {
            Button("Продолжить", role: .destructive) { confirmEraseFinal = true }
        } message: {
            Text("Будут удалены все обследования, результаты, расходы, документы, лаборатории и напоминания.")
        }
        .alert("Это действие нельзя отменить", isPresented: $confirmEraseFinal) {
            Button("Удалить всё", role: .destructive) { eraseAll() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Резервная копия будет сохранена в папку автоматических копий.")
        }
    }

    private func eraseAll() {
        do {
            try AutoBackupService.createBackup(context: context, fileStorage: environment.fileStorage)
            let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
            reminders.forEach { environment.notifications.cancel(id: $0.id) }
            try BackupService(context: context, fileStorage: environment.fileStorage).eraseAllData()
            storageSize = environment.fileStorage.totalSize()
            info = "Все данные удалены. Резервная копия сохранена."
        } catch {
            info = "Не удалось удалить данные: \(error.localizedDescription)"
        }
    }
}

struct UpdatesSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Updater.automaticChecksKey) private var automaticChecks = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Установлена версия", value: Updater.currentVersion)
                Toggle("Проверять обновления автоматически", isOn: $automaticChecks)
                HStack {
                    Button("Проверить обновления…") {
                        openWindow(id: "update")
                        Task { await Updater.shared.checkNow() }
                    }
                    Button("Другие версии…") { openWindow(id: "versions") }
                }
            } footer: {
                Text("Vitae проверяет релизы на GitHub при запуске и не чаще двух раз в сутки. Обновление ставится одной кнопкой, " +
                     "перед установкой создаётся резервная копия базы. В «Других версиях» можно вернуться к любой прошлой версии.")
            }
            Section("Что отправляется в сеть") {
                Label("Только запрос списка релизов и загрузка архива приложения с github.com. Обследования, результаты и документы не передаются.",
                      systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
    }
}
