import AppKit
import PDFKit
import SwiftUI

/// Фокусировка поля поиска текущего окна (⌘F) — поиск NSSearchField в панели инструментов.
@MainActor
enum SearchFieldFocuser {
    static func focus() {
        guard let window = NSApp.keyWindow else { return }
        if let toolbar = window.toolbar,
           let item = toolbar.items.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return
        }
        let root = window.contentView?.superview ?? window.contentView
        if let root, let field = findSearchField(in: root) {
            window.makeFirstResponder(field)
        }
    }

    private static func findSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = findSearchField(in: subview) { return field }
        }
        return nil
    }
}

/// Локальный монитор нажатий клавиш, активный только для окна этого представления.
struct KeyEventMonitor: NSViewRepresentable {
    /// Возвращает true, если событие обработано и не должно идти дальше.
    var handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.handler = handler
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.stop()
    }

    final class MonitorView: NSView {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, let handler = self.handler else { return event }
                return handler(event) ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Просмотр PDF средствами PDFKit.
struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .underPageBackgroundColor
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}

/// Миниатюра файла через Quick Look.
struct FileThumbnailView: View {
    let url: URL
    var size = CGSize(width: 120, height: 150)
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: url) {
            image = await ThumbnailService.thumbnail(for: url, size: size)
        }
    }
}
