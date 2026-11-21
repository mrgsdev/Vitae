import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Документы обследования: добавление (кнопка или перетаскивание), Quick Look, распознавание, удаление.
struct ExaminationDocumentsTab: View {
    let examination: Examination
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @Environment(\.navigationModel) private var navigation
    @Environment(\.openWindow) private var openWindow

    @State private var selectedID: UUID?
    @State private var previewURL: URL?
    @State private var pendingDelete: Attachment?
    @State private var isDropTargeted = false
    @State private var errorMessage: String?

    private var attachments: [Attachment] {
        examination.attachments.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let urls = attachments.map { environment.fileStorage.url(for: $0.storedFileName) }
        VStack(spacing: 0) {
            HStack {
                Text("PDF, PNG, JPG и HEIC. Файлы хранятся в папке приложения и не передаются в интернет.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await pickFiles() }
                } label: {
                    Label("Добавить файл…", systemImage: "plus")
                }
            }
            .padding(16)
            Divider()

            if attachments.isEmpty {
                dropZone
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(attachments) { attachment in
                            tile(attachment)
                        }
                    }
                    .padding(20)
                }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    guard let attachment = attachments.first(where: { $0.id == selectedID }) else { return .ignored }
                    previewURL = environment.fileStorage.url(for: attachment.storedFileName)
                    return .handled
                }
                .onDeleteCommand {
                    pendingDelete = attachments.first { $0.id == selectedID }
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { items, _ in
            add(items)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .quickLookPreview($previewURL, in: urls)
        .confirmationDialog("Удалить документ?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { attachment in
            Button("Удалить", role: .destructive) { delete(attachment) }
        } message: { attachment in
            Text("Файл «\(attachment.originalFileName)» будет удалён из архива приложения. Это действие нельзя отменить.")
        }
        .alert("Не удалось добавить файл", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Перетащите сюда PDF или изображение бланка")
                .font(.title3)
            Text("или нажмите «Добавить файл…»").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ attachment: Attachment) -> some View {
        let url = environment.fileStorage.url(for: attachment.storedFileName)
        let isSelected = selectedID == attachment.id
        return VStack(spacing: 8) {
            FileThumbnailView(url: url, size: CGSize(width: 130, height: 160))
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            Text(attachment.originalFileName).font(.callout).lineLimit(2).multilineTextAlignment(.center)
            Text(Fmt.fileSize(attachment.fileSize)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color.accentColor : Theme.separator))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { previewURL = url }
        .onTapGesture { selectedID = attachment.id }
        .contextMenu {
            Button("Просмотр (Quick Look)") { previewURL = url }
            Button("Открыть в программе по умолчанию") { NSWorkspace.shared.open(url) }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Распознать результаты…") { recognize(url) }
            Button("Сохранить копию…") { Task { await saveCopy(attachment) } }
            Divider()
            Button("Удалить…", role: .destructive) { pendingDelete = attachment }
        }
        .help(attachment.originalFileName)
    }

    private func pickFiles() async {
        let urls = await FilePanels.open(title: "Добавить документы", contentTypes: FileStorageService.supportedTypes, allowsMultiple: true)
        add(urls)
    }

    private func add(_ urls: [URL]) {
        var errors: [String] = []
        for url in urls {
            do {
                let stored = try environment.fileStorage.importFile(at: url)
                let attachment = Attachment(originalFileName: stored.originalFileName, storedFileName: stored.storedFileName,
                                            contentTypeIdentifier: stored.contentType.identifier, fileSize: stored.size)
                context.insert(attachment)
                attachment.examination = examination
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        try? context.save()
        if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
    }

    private func delete(_ attachment: Attachment) {
        environment.fileStorage.deleteFile(named: attachment.storedFileName)
        context.delete(attachment)
        try? context.save()
        context.undoManager?.removeAllActions()
        pendingDelete = nil
        selectedID = nil
    }

    private func recognize(_ url: URL) {
        environment.showInMainWindow(.importDocument(DocumentImportRequest(url: url, targetExaminationID: examination.id)),
                                     focused: navigation, openWindow: openWindow)
    }

    private func saveCopy(_ attachment: Attachment) async {
        do {
            let data = try environment.fileStorage.data(for: attachment.storedFileName)
            let type = UTType(attachment.contentTypeIdentifier) ?? .data
            try await FilePanels.export(data, title: "Сохранить копию", suggestedName: attachment.originalFileName, contentType: type)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Панель сведений о выбранном обследовании в списке.
struct ExaminationInspector: View {
    let examinationID: UUID?
    @Query private var examinations: [Examination]
    @Environment(\.navigationModel) private var navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let id = examinationID, let exam = examinations.first(where: { $0.id == id }) {
            let results = exam.sortedResults.map(ResultSnapshot.init)
            let deviations = results.filter { $0.status.isDeviation }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exam.title).font(.title3.weight(.semibold))
                        Text(Fmt.date(exam.date)).foregroundStyle(.secondary)
                    }
                    ExaminationStatusBadge(status: exam.status)
                    VStack(spacing: 6) {
                        InfoRow(title: "Лаборатория", value: exam.laboratory?.name ?? "—")
                        InfoRow(title: "Показателей", value: "\(results.count)")
                        InfoRow(title: "Вне референса", value: "\(deviations.count)")
                        InfoRow(title: "Стоимость", value: Fmt.moneyTotals(exam.costTotals))
                        InfoRow(title: "Документов", value: "\(exam.attachments.count)")
                    }
                    if !deviations.isEmpty {
                        Divider()
                        CardHeader(title: "Вне референса", systemImage: "exclamationmark.circle")
                        ForEach(deviations) { item in
                            HStack {
                                Text(item.testName).lineLimit(1)
                                Spacer()
                                Text("\(item.displayValue) \(item.unit)").monospacedDigit()
                                Image(systemName: item.status.symbolName).foregroundStyle(item.status.color)
                            }
                            .font(.callout)
                        }
                    }
                    if !exam.comment.isEmpty {
                        Divider()
                        CardHeader(title: "Комментарий", systemImage: "text.bubble")
                        Text(exam.comment).font(.callout)
                    }
                    Divider()
                    HStack {
                        Button("Открыть") { navigation?.openExamination(exam.id) }
                            .buttonStyle(.borderedProminent)
                        Button("Редактировать") { openWindow(id: WindowID.editor, value: EditorRequest.edit(exam.id)) }
                    }
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("Выберите обследование", systemImage: "list.clipboard",
                                   description: Text("Здесь появится краткая сводка."))
        }
    }
}
