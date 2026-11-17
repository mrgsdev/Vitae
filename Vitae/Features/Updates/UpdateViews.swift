import AppKit
import SwiftUI

private let panelBackground = Color.primary.opacity(0.05)

/// Окно обновления: предлагает новую версию с описанием «Что нового»
/// или сообщает, что установлена последняя, если проверку запустили из меню.
struct UpdateView: View {
    @State private var updater = Updater.shared
    @State private var showsNotes = false
    @State private var showsGoodToKnow = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if updater.state == .idle {
                Task { await updater.checkNow() }
            }
        }
        .onDisappear {
            updater.windowClosed()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking:
            Text("Проверка обновлений").font(.headline)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Ищем новую версию на GitHub…").foregroundStyle(.secondary)
            }
            buttons {
                Button("Отмена", role: .cancel) { dismiss() }
            }

        case .upToDate:
            Text("У вас последняя версия").font(.headline)
            Text("Установлена самая новая версия: Vitae \(Updater.currentVersion).")
                .foregroundStyle(.secondary)
            buttons {
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

        case let .available(release):
            Text("Доступна новая версия Vitae").font(.headline)
            Text("Вышла версия \(release.version), у вас \(Updater.currentVersion). Обновить приложение?")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if release.version == updater.skippedVersion {
                Label("Вы пропустили эту версию: сама она больше не предлагается. Установить её можно сейчас.",
                      systemImage: "forward")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            disclosure("Что нового", isOpen: $showsNotes)
            if showsNotes {
                ScrollView {
                    ReleaseNotes(text: release.body ?? "")
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
            }
            disclosure("Что важно знать заранее", isOpen: $showsGoodToKnow)
            if showsGoodToKnow {
                UpdateNotesBox(notes: UpdateNote.forUpdate)
            }
            HStack {
                if release.version != updater.skippedVersion {
                    Button("Пропустить эту версию") {
                        updater.skip(release)
                        dismiss()
                    }
                    .help("Не предлагать версию \(release.version). О следующей версии Vitae сообщит как обычно.")
                }
                Spacer()
                Button("Позже", role: .cancel) { dismiss() }
                Button("Обновить") { updater.install(release) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.top, 4)

        case let .downloading(release):
            Text("Обновление до версии \(release.version)").font(.headline)
            ProgressView().progressViewStyle(.linear)
            Text("Сохраняем резервную копию, загружаем и устанавливаем. Vitae перезапустится сама.")
                .foregroundStyle(.secondary)
            buttons {
                Button("Отмена", role: .cancel) { dismiss() }
            }

        case let .failed(message, release):
            Text("Не получилось").font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Открыть страницу релиза") {
                    NSWorkspace.shared.open(release?.htmlURL ?? Updater.releasesPage)
                }
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func disclosure(_ title: String, isOpen: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOpen.wrappedValue.toggle() }
        } label: {
            Label(title, systemImage: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
        }
        .buttonStyle(.link)
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
        .controlSize(.large)
        .padding(.top, 4)
    }
}

/// Описание релиза с GitHub: заголовки, списки и абзацы со встроенным Markdown.
struct ReleaseNotes: View {
    let text: String

    private var lines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lines.isEmpty {
                Text("Описание изменений не указано.").foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        if line.hasPrefix("#") {
            Text(Self.inline(String(line.drop { $0 == "#" }).trimmed))
                .font(.headline)
                .padding(.top, 4)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(Self.inline(String(line.dropFirst(2))))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(Self.inline(line))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}

/// «Другие версии…»: все релизы с GitHub и установка любой из них, в том числе возврат к прошлой.
struct VersionsView: View {
    @State private var updater = Updater.shared
    @State private var releases: [AppRelease] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var expanded: Set<String> = []
    /// Версия, выбранная для установки и ждущая подтверждения.
    @State private var pending: AppRelease?
    @Environment(\.dismiss) private var dismiss

    private var newest: AppRelease? { releases.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task { await load() }
        .onDisappear {
            if case .downloading = updater.state { updater.cancelInstall() }
            if case .failed = updater.state { updater.cancelInstall() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Версии Vitae").font(.headline)
                Text("Установлена версия \(Updater.currentVersion). Здесь можно вернуться к прошлой версии или поставить другую.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case let .downloading(release):
            Text("Устанавливаем версию \(release.version)").font(.headline)
            ProgressView().progressViewStyle(.linear)
            Text("Сохраняем резервную копию, загружаем и устанавливаем. Vitae перезапустится сама.")
                .foregroundStyle(.secondary)
            buttons {
                Button("Отмена", role: .cancel) { updater.cancelInstall() }
            }
        case let .failed(message, release) where pending != nil:
            Text("Не получилось").font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Открыть страницу релиза") {
                    NSWorkspace.shared.open(release?.htmlURL ?? Updater.releasesPage)
                }
                Button("К списку версий") {
                    updater.cancelInstall()
                    pending = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        default:
            if let pending {
                confirmation(pending)
            } else {
                list
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if isLoading, releases.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Загружаем список версий с GitHub…").foregroundStyle(.secondary)
            }
        } else if let loadError, releases.isEmpty {
            Text(loadError)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Открыть страницу релизов") { NSWorkspace.shared.open(Updater.releasesPage) }
                Button("Повторить") { Task { await load() } }
                    .keyboardShortcut(.defaultAction)
            }
        } else if releases.isEmpty {
            Text("На GitHub пока нет опубликованных версий.").foregroundStyle(.secondary)
            buttons {
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(releases) { row($0) }
                }
            }
            .frame(maxHeight: 380)
            buttons {
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func row(_ release: AppRelease) -> some View {
        let isCurrent = release.version == Updater.currentVersion
        let isOpen = expanded.contains(release.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Vitae \(release.version)").font(.body.weight(.semibold))
                if let date = release.publishedDate {
                    Text(Fmt.date(date)).foregroundStyle(.secondary)
                }
                if isCurrent {
                    badge("Установлена", color: .green)
                } else if release.id == newest?.id {
                    badge("Последняя", color: .accentColor)
                }
                if release.version == updater.skippedVersion {
                    badge("Пропущена", color: .secondary)
                }
                Spacer()
                if !isCurrent {
                    Button(Self.isOlder(release) ? "Вернуться" : "Установить") {
                        pending = release
                    }
                }
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { expanded.remove(release.id) } else { expanded.insert(release.id) }
                }
            } label: {
                Label("Что нового", systemImage: isOpen ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.link)
            if isOpen {
                ReleaseNotes(text: release.body ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func confirmation(_ release: AppRelease) -> some View {
        let older = Self.isOlder(release)
        return VStack(alignment: .leading, spacing: 12) {
            Text(older ? "Вернуться к версии \(release.version)?" : "Установить версию \(release.version)?")
                .font(.headline)
            Text("Что важно знать заранее")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            UpdateNotesBox(notes: UpdateNote.forVersion(release, newest: newest))
            buttons {
                Button("Отмена", role: .cancel) { pending = nil }
                Button(older ? "Вернуться к \(release.version)" : "Установить \(release.version)") {
                    updater.install(release, allowingOlder: true, newest: newest)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    static func isOlder(_ release: AppRelease) -> Bool {
        UpdatePackage.isVersion(Updater.currentVersion, newerThan: release.version)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            releases = try await updater.releases()
        } catch {
            if !(error is CancellationError) {
                loadError = "Не удалось загрузить список версий: \(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
        .controlSize(.large)
        .padding(.top, 4)
    }
}

/// Строка блока «Что важно знать заранее».
struct UpdateNote {
    let symbol: String
    let text: String
    var isWarning = false

    private static let dataKept = UpdateNote(
        symbol: "checkmark.circle",
        text: "Обследования, результаты, документы и настройки сохранятся: приложение то же и с той же подписью."
    )
    private static let backup = UpdateNote(
        symbol: "externaldrive",
        text: "Перед установкой Vitae сама сделает резервную копию базы в папку автоматических копий."
    )

    /// Обычное обновление до новой версии.
    static var forUpdate: [UpdateNote] {
        [
            dataKept,
            backup,
            UpdateNote(symbol: "arrow.clockwise", text: "После установки Vitae перезапустится сама."),
            UpdateNote(symbol: "arrow.uturn.backward",
                       text: "Если новая версия не понравится, вернуться к прошлой можно в Настройках: «Обновления» → «Другие версии…»."),
        ]
    }

    /// Установка выбранной версии из «Другие версии…».
    static func forVersion(_ release: AppRelease, newest: AppRelease?) -> [UpdateNote] {
        var notes = [dataKept, backup]
        guard VersionsView.isOlder(release) else {
            if let newest, newest.id != release.id {
                notes.append(UpdateNote(symbol: "info.circle",
                                        text: "Это не последняя версия. О версии \(newest.version) Vitae сообщит как обычно."))
            }
            notes.append(UpdateNote(symbol: "arrow.clockwise", text: "После установки Vitae перезапустится сама."))
            return notes
        }
        notes.append(UpdateNote(
            symbol: "exclamationmark.triangle",
            text: "Версия \(release.version) не знает о том, что появилось позже. Если в новой версии менялась структура базы, прежняя может не открыть её и покажет предупреждение: файл базы при этом не изменяется, а после обновления всё вернётся.",
            isWarning: true
        ))
        let skipped = newest?.version ?? Updater.currentVersion
        notes.append(UpdateNote(symbol: "forward",
                                text: "Версия \(skipped) будет пропущена: сама она предлагаться не будет. О более новой версии Vitae сообщит как обычно."))
        notes.append(UpdateNote(symbol: "arrow.uturn.forward",
                                text: "Вернуться на новую версию можно в любой момент: «Проверить обновления…» в меню Vitae или в Настройках."))
        return notes
    }
}

/// Блок примечаний; предупреждения выделены оранжевым.
struct UpdateNotesBox: View {
    let notes: [UpdateNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: note.symbol)
                        .foregroundStyle(note.isWarning ? Color.orange : Color.secondary)
                        .frame(width: 16)
                    Text(note.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}
