import SwiftData
import SwiftUI

struct DocumentImportView: View {
    let request: DocumentImportRequest
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.navigationModel) private var navigation
    @State private var model: DocumentImportModel?

    var body: some View {
        Group {
            if let model {
                DocumentImportContent(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(request.targetExaminationID == nil ? "Импорт документа" : "Распознавание документа")
        .task(id: request.token) {
            // Экран пересоздаётся при возврате в раздел: модель берётся из навигации окна, чтобы не
            // распознавать файл заново — иначе пропали бы правки проверки, а сохранённый документ
            // снова предлагался бы к сохранению.
            let make = { DocumentImportModel(request: request, environment: environment) }
            let session = navigation?.importSession(for: request, make: make) ?? (model: make(), isNew: true)
            self.model = session.model
            if session.isNew, let url = request.url { await session.model.load(url) }
        }
    }
}

private struct DocumentImportContent: View {
    @Bindable var model: DocumentImportModel
    @Environment(\.navigationModel) private var navigation
    @Query(sort: \Laboratory.name) private var laboratories: [Laboratory]
    @State private var isDropTargeted = false
    @State private var showText = false

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                dropZone
            case .recognizing:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Распознавание текста…").font(.title3)
                    Text("Выполняется локально на этом Mac.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyStateView(title: "Не удалось распознать документ", systemImage: "exclamationmark.triangle",
                               message: message, actionTitle: "Выбрать другой файл") {
                    Task { await pick() }
                }
            case .review:
                review
            case .saved(let id):
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
                    Text("Данные сохранены").font(.title2.weight(.semibold))
                    HStack {
                        Button("Открыть обследование") { navigation?.openExamination(id) }
                            .buttonStyle(.borderedProminent)
                        Button("Импортировать ещё") { model.reset() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await model.load(url) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .alert("Не удалось сохранить", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var dropZone: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
            Text("Перетащите PDF или изображение бланка").font(.title2.weight(.semibold))
            Text("Поддерживаются PDF, PNG, JPG и HEIC. Текст распознаётся средствами macOS (Vision) прямо на этом Mac; документы никуда не отправляются. Перед сохранением вы проверите каждое значение.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button {
                Task { await pick() }
            } label: {
                Label("Выбрать файл…", systemImage: "folder")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isDropTargeted ? Color.accentColor : Theme.separator, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                .padding(24)
        }
    }

    private var review: some View {
        HSplitView {
            preview
                .frame(minWidth: 240, idealWidth: 340, maxWidth: 560)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Проверьте распознанные данные", systemImage: "checkmark.shield")
                            .font(.headline)
                        Spacer()
                        Toggle("Исходный текст", isOn: $showText).toggleStyle(.switch).controlSize(.small)
                    }
                    Text(reviewHint).font(.callout).foregroundStyle(.secondary)
                    if model.targetExaminationID == nil {
                        EditorHeaderForm(draft: $model.draft, laboratories: laboratories.map(\.name), compact: true)
                    } else if let target = model.targetExamination {
                        Text("Результаты будут добавлены в обследование «\(target.title)» от \(Fmt.date(target.date)).")
                            .font(.callout)
                    }
                }
                .padding(16)
                Divider()
                if showText {
                    ScrollView {
                        Text(model.recognizedLines.joined(separator: "\n"))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(height: 160)
                    Divider()
                }
                if model.draft.rows.isEmpty {
                    EmptyStateView(title: "Показатели не найдены", systemImage: "text.magnifyingglass",
                                   message: "Не удалось выделить строки результатов. Добавьте их вручную или посмотрите исходный текст.",
                                   actionTitle: "Добавить строку") { model.addEmptyRow() }
                } else {
                    ResultEntryGrid(rows: $model.draft.rows, issues: DraftValidator.issues(in: model.draft))
                }
                Divider()
                footer
            }
            .frame(minWidth: 560)
            .layoutPriority(1)
        }
    }

    private var reviewHint: String {
        var parts = ["Найдено показателей: \(model.draft.rows.count)."]
        if model.unmatchedCount > 0 {
            parts.append("Не сопоставлено со справочником: \(model.unmatchedCount) — будут созданы пользовательские показатели.")
        }
        parts.append(model.source == .textLayer ? "Текст взят из текстового слоя PDF." : "Текст распознан OCR — сверьте значения с документом.")
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var preview: some View {
        if let url = model.fileURL {
            if FileStorageService.contentType(of: url)?.conforms(to: .pdf) == true {
                PDFKitView(url: url)
            } else if let image = NSImage(contentsOf: url) {
                ScrollView(.vertical) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.draft.rows.contains(where: \.isMarked) {
                Button("Удалить отмеченные", role: .destructive) { model.removeMarked() }
            }
            Button("Добавить строку") { model.addEmptyRow() }
            if model.targetExaminationID == nil {
                Toggle("Прикрепить документ к обследованию", isOn: $model.attachDocument)
            }
            Spacer()
            Button("Отмена") { model.reset() }
            Button(model.targetExaminationID == nil ? "Сохранить обследование" : "Добавить в обследование") {
                model.confirm()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.draft.rows.isEmpty || !DraftValidator.errors(in: model.draft).isEmpty)
        }
        .padding(12)
    }

    private func pick() async {
        guard let url = await FilePanels.open(title: "Выберите документ с результатами",
                                              contentTypes: FileStorageService.supportedTypes).first else { return }
        await model.load(url)
    }
}
