import AppKit
import Foundation
import PDFKit
import Vision

struct OCRLine: Sendable {
    let text: String
    /// Нормализованный прямоугольник Vision (начало координат — внизу слева).
    let box: CGRect
}

struct RecognizedDocument: Sendable {
    enum Source: Sendable { case textLayer, vision }
    let lines: [String]
    let source: Source
    let pageCount: Int

    var fullText: String { lines.joined(separator: "\n") }
}

enum OCRError: LocalizedError {
    case unreadableFile
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "Не удалось открыть документ."
        case .recognitionFailed: "Не удалось распознать текст в документе."
        }
    }
}

/// Распознавание текста локально, средствами Vision. Документы никуда не отправляются.
struct OCRService: Sendable {
    var languages: [String] = ["ru-RU", "en-US"]
    /// Максимальное число страниц PDF для распознавания.
    var pageLimit = 10

    func recognize(url: URL) async throws -> RecognizedDocument {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let type = FileStorageService.contentType(of: url)
        if type?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(url: url) else { throw OCRError.unreadableFile }
            return try await recognize(pdf: document)
        }
        guard let image = NSImage(contentsOf: url), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.unreadableFile
        }
        let lines = try await recognize(cgImage: cgImage)
        return RecognizedDocument(lines: Self.reconstructRows(lines), source: .vision, pageCount: 1)
    }

    func recognize(pdf document: PDFDocument) async throws -> RecognizedDocument {
        let pageCount = min(document.pageCount, pageLimit)
        // Текстовый слой точнее OCR, если он есть. Порядок текста в PDF часто не совпадает
        // с таблицей (название в одной ячейке, значение в другой), поэтому строки собираются
        // по положению на странице, как при распознавании изображения.
        var textLines: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            textLines += Self.textLayerRows(page)
        }
        let meaningful = textLines.joined().filter { $0.isLetter || $0.isNumber }.count
        if meaningful > 40 {
            return RecognizedDocument(lines: textLines.map(\.trimmed).filter { !$0.isEmpty }, source: .textLayer, pageCount: pageCount)
        }

        var rows: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index), let image = Self.render(page: page) else { continue }
            rows += Self.reconstructRows(try await recognize(cgImage: image))
        }
        return RecognizedDocument(lines: rows, source: .vision, pageCount: pageCount)
    }

    func recognize(cgImage: CGImage) async throws -> [OCRLine] {
        let languages = self.languages
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = languages.filter { supported.isEmpty || supported.contains($0) }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                AppLog.ocr.error("Ошибка распознавания текста")
                throw OCRError.recognitionFailed
            }
            return (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLine(text: candidate.string, box: observation.boundingBox)
            }
        }.value
    }

    static func render(page: PDFPage, targetWidth: CGFloat = 2200) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let scale = targetWidth / bounds.width
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// Строки текстового слоя страницы, собранные в строки таблицы по координатам.
    static func textLayerRows(_ page: PDFPage) -> [String] {
        let bounds = page.bounds(for: .mediaBox)
        let lines = (page.selection(for: bounds)?.selectionsByLine() ?? []).compactMap { selection -> OCRLine? in
            let text = (selection.string ?? "").trimmed
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, box: selection.bounds(for: page))
        }
        guard !lines.isEmpty else {
            return (page.string ?? "").components(separatedBy: .newlines)
        }
        return reconstructRows(lines)
    }

    /// Собирает наблюдения Vision в строки таблицы: группировка по вертикали, сортировка по горизонтали.
    static func reconstructRows(_ lines: [OCRLine]) -> [String] {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var rows: [[OCRLine]] = []
        for line in sorted {
            if var last = rows.last, let anchor = last.first {
                let tolerance = max(anchor.box.height, line.box.height) * 0.6
                if abs(anchor.box.midY - line.box.midY) <= tolerance {
                    last.append(line)
                    rows[rows.count - 1] = last
                    continue
                }
            }
            rows.append([line])
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ")
        }
    }
}
