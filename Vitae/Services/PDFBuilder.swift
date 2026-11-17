import AppKit
import CoreText
import Foundation

/// Простой многостраничный генератор PDF (CoreGraphics + CoreText): заголовки, абзацы,
/// таблицы с переносом строк и повтором шапки, изображения графиков.
final class PDFBuilder {
    struct Column {
        let title: String
        /// Доля ширины таблицы.
        let width: CGFloat
        var alignment: NSTextAlignment = .left
    }

    let pageSize: CGSize
    let margin: CGFloat
    let documentTitle: String

    private let data = NSMutableData()
    private var context: CGContext?
    private var cursorY: CGFloat = 0
    private var pageNumber = 0

    private var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private var bottomLimit: CGFloat { pageSize.height - margin - 24 }

    init(title: String, pageSize: CGSize = CGSize(width: 595.2, height: 841.8), margin: CGFloat = 48) {
        self.documentTitle = title
        self.pageSize = pageSize
        self.margin = margin
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return }
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Vitae"]
        context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        beginPage()
    }

    // MARK: Pages

    private func beginPage() {
        guard let context else { return }
        context.beginPDFPage(nil)
        pageNumber += 1
        cursorY = margin
        drawFooter()
    }

    private func endPage() {
        context?.endPDFPage()
    }

    private func ensureSpace(_ height: CGFloat) {
        if cursorY + height > bottomLimit {
            endPage()
            beginPage()
        }
    }

    private func drawFooter() {
        let text = "Vitae · \(documentTitle) · стр. \(pageNumber)"
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.gray
        ])
        draw(attributed, in: CGRect(x: margin, y: pageSize.height - margin + 8, width: contentWidth, height: 14))
    }

    // MARK: Text

    private func attributes(size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black,
                            alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private func measure(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: text.length), nil,
                                                                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(size.height)
    }

    /// Рисует текст в прямоугольнике, заданном в координатах «сверху вниз».
    private func draw(_ text: NSAttributedString, in rect: CGRect) {
        guard let context else { return }
        let flipped = CGRect(x: rect.minX, y: pageSize.height - rect.maxY, width: rect.width, height: rect.height)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: flipped, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: text.length), path, nil)
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func fill(_ rect: CGRect, color: NSColor) {
        guard let context else { return }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: rect.minX, y: pageSize.height - rect.maxY, width: rect.width, height: rect.height))
    }

    private func line(y: CGFloat, color: NSColor = NSColor(white: 0.85, alpha: 1)) {
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5), color: color)
    }

    func title(_ text: String, subtitle: String? = nil) {
        let attributed = NSAttributedString(string: text, attributes: attributes(size: 20, weight: .bold))
        let height = measure(attributed, width: contentWidth)
        ensureSpace(height + 30)
        draw(attributed, in: CGRect(x: margin, y: cursorY, width: contentWidth, height: height))
        cursorY += height + 4
        if let subtitle {
            let sub = NSAttributedString(string: subtitle, attributes: attributes(size: 10, color: .darkGray))
            let h = measure(sub, width: contentWidth)
            draw(sub, in: CGRect(x: margin, y: cursorY, width: contentWidth, height: h))
            cursorY += h
        }
        cursorY += 10
        line(y: cursorY)
        cursorY += 12
    }

    func heading(_ text: String) {
        let attributed = NSAttributedString(string: text, attributes: attributes(size: 13, weight: .semibold))
        let height = measure(attributed, width: contentWidth)
        ensureSpace(height + 40)
        cursorY += 6
        draw(attributed, in: CGRect(x: margin, y: cursorY, width: contentWidth, height: height))
        cursorY += height + 6
    }

    func paragraph(_ text: String, size: CGFloat = 10, color: NSColor = .black) {
        let attributed = NSAttributedString(string: text, attributes: attributes(size: size, color: color))
        let height = measure(attributed, width: contentWidth)
        ensureSpace(height)
        draw(attributed, in: CGRect(x: margin, y: cursorY, width: contentWidth, height: height))
        cursorY += height + 6
    }

    func keyValues(_ pairs: [(String, String)]) {
        let keyWidth = contentWidth * 0.32
        for (key, value) in pairs {
            let k = NSAttributedString(string: key, attributes: attributes(size: 10, color: .darkGray))
            let v = NSAttributedString(string: value, attributes: attributes(size: 10, weight: .medium))
            let height = max(measure(k, width: keyWidth - 8), measure(v, width: contentWidth - keyWidth))
            ensureSpace(height + 4)
            draw(k, in: CGRect(x: margin, y: cursorY, width: keyWidth - 8, height: height))
            draw(v, in: CGRect(x: margin + keyWidth, y: cursorY, width: contentWidth - keyWidth, height: height))
            cursorY += height + 4
        }
        cursorY += 6
    }

    func table(columns: [Column], rows: [[String]], highlights: Set<Int> = []) {
        let totalFraction = columns.reduce(0) { $0 + $1.width }
        let widths = columns.map { $0.width / totalFraction * contentWidth }
        let padding: CGFloat = 4

        func rowHeight(_ cells: [NSAttributedString]) -> CGFloat {
            zip(cells, widths).map { measure($0, width: $1 - padding * 2) }.max() ?? 12
        }

        func drawRow(_ cells: [NSAttributedString], background: NSColor?) {
            let height = rowHeight(cells) + padding * 2
            ensureSpace(height)
            if let background { fill(CGRect(x: margin, y: cursorY, width: contentWidth, height: height), color: background) }
            var x = margin
            for (cell, width) in zip(cells, widths) {
                draw(cell, in: CGRect(x: x + padding, y: cursorY + padding, width: width - padding * 2, height: height - padding * 2))
                x += width
            }
            cursorY += height
            line(y: cursorY)
        }

        let header = columns.map { NSAttributedString(string: $0.title, attributes: attributes(size: 8.5, weight: .semibold, color: .darkGray, alignment: $0.alignment)) }
        let headerHeight = rowHeight(header) + padding * 2
        ensureSpace(headerHeight + 20)
        drawRow(header, background: NSColor(white: 0.95, alpha: 1))

        for (index, row) in rows.enumerated() {
            let cells = row.enumerated().map { i, text in
                NSAttributedString(string: text, attributes: attributes(size: 9, weight: highlights.contains(index) && i == 1 ? .semibold : .regular,
                                                                        alignment: columns[safe: i]?.alignment ?? .left))
            }
            let height = rowHeight(cells) + padding * 2
            if cursorY + height > bottomLimit {
                endPage()
                beginPage()
                drawRow(header, background: NSColor(white: 0.95, alpha: 1))
            }
            drawRow(cells, background: highlights.contains(index) ? NSColor(red: 1, green: 0.95, blue: 0.9, alpha: 1) : nil)
        }
        cursorY += 10
    }

    func image(_ image: CGImage, maxHeight: CGFloat = 260) {
        guard let context else { return }
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        let width = contentWidth
        let height = min(maxHeight, width * aspect)
        let drawWidth = height / aspect
        ensureSpace(height + 8)
        let rect = CGRect(x: margin, y: pageSize.height - cursorY - height, width: drawWidth, height: height)
        context.draw(image, in: rect)
        cursorY += height + 10
    }

    func spacer(_ height: CGFloat = 10) { cursorY += height }

    func finish() -> Data {
        endPage()
        context?.closePDF()
        context = nil
        return data as Data
    }
}
