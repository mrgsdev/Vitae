import SwiftData
import SwiftUI

/// Распознавание бланка и подготовка черновика. В базу ничего не пишется до подтверждения.
@MainActor
@Observable
final class DocumentImportModel {
    enum Phase: Equatable {
        case idle
        case recognizing
        case review
        case failed(String)
        case saved(UUID)
    }

    var phase: Phase = .idle
    var fileURL: URL?
    var recognizedLines: [String] = []
    var source: RecognizedDocument.Source?
    var draft = ExaminationDraft(currencyCode: AppSettings.defaultCurrency)
    var attachDocument = true
    var errorMessage: String?

    let targetExaminationID: UUID?
    private let environment: AppEnvironment

    init(request: DocumentImportRequest, environment: AppEnvironment) {
        self.targetExaminationID = request.targetExaminationID
        self.environment = environment
        // Документ уже прикреплён к обследованию — повторно не прикрепляем.
        if request.targetExaminationID != nil { attachDocument = false }
    }

    private var store: ExaminationStore { environment.examinationStore }

    var targetExamination: Examination? {
        targetExaminationID.flatMap { store.examination(id: $0) }
    }

    var unmatchedCount: Int { draft.rows.filter { $0.testCode == nil }.count }

    func load(_ url: URL) async {
        guard FileStorageService.isSupported(url) else {
            phase = .failed(FileStorageError.unsupportedType(url.pathExtension).localizedDescription)
            return
        }
        fileURL = url
        phase = .recognizing
        do {
            let document = try await environment.ocr.recognize(url: url)
            recognizedLines = document.lines
            source = document.source
            buildDraft(from: document.lines, fileName: url.deletingPathExtension().lastPathComponent)
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func buildDraft(from lines: [String], fileName: String) {
        let catalog = store.catalogIndex()
        let labs = ((try? environment.context.fetch(FetchDescriptor<Laboratory>())) ?? []).map(\.name)
        let report = LabReportParser(catalog: catalog, knownLaboratories: labs).parse(lines: lines)
        var draft = ExaminationDraft(currencyCode: AppSettings.defaultCurrency)
        if let target = targetExamination {
            draft.title = target.title
            draft.date = target.date
            draft.laboratoryName = target.laboratory?.name ?? ""
        } else {
            draft.title = "Импорт: \(fileName)"
            draft.date = report.date ?? .now
            draft.laboratoryName = report.laboratoryName ?? ""
            draft.comment = "Распознано из документа «\(fileName)»"
        }
        draft.rows = report.items.map { item in
            let entry = catalog.entry(item.testCode)
            return EntryRow(groupID: UUID(), kind: .single, testCode: item.testCode, name: item.name,
                            category: entry?.category ?? .other, isQualitative: item.isQualitative,
                            value: item.rawValue, unit: item.unit,
                            lower: Fmt.optionalNumber(item.reference.lower), upper: Fmt.optionalNumber(item.reference.upper),
                            referenceText: item.reference.text ?? "", note: item.comment)
        }
        self.draft = draft
    }

    func addEmptyRow() {
        draft.rows.append(EntryRow(groupID: UUID(), kind: .single, testCode: nil, name: ""))
    }

    func removeMarked() {
        EntryTableOperations.removeRows(ids: Set(draft.rows.filter(\.isMarked).map(\.id)), from: &draft.rows)
    }

    /// Сохраняет подтверждённые пользователем данные.
    @discardableResult
    func confirm() -> UUID? {
        do {
            if let target = targetExamination {
                var existing = store.draft(from: target)
                let existingCodes = Set(existing.rows.compactMap(\.testCode))
                existing.rows += draft.rows.filter { row in row.testCode.map { !existingCodes.contains($0) } ?? true }
                let exam = try store.save(existing, finalize: target.status != .draft)
                phase = .saved(exam.id)
                return exam.id
            }
            let exam = try store.save(draft, finalize: true)
            if attachDocument, let fileURL {
                let stored = try environment.fileStorage.importFile(at: fileURL)
                let attachment = Attachment(originalFileName: stored.originalFileName, storedFileName: stored.storedFileName,
                                            contentTypeIdentifier: stored.contentType.identifier, fileSize: stored.size)
                environment.context.insert(attachment)
                attachment.examination = exam
                try environment.context.save()
            }
            phase = .saved(exam.id)
            return exam.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func reset() {
        phase = .idle
        fileURL = nil
        recognizedLines = []
        draft = ExaminationDraft(currencyCode: AppSettings.defaultCurrency)
    }
}
