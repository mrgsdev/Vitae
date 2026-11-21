#if DEBUG
import AppKit
import SwiftData
import SwiftUI

/// Отладочные параметры запуска для UI-тестов и проверки вёрстки.
/// Работают только в Debug-сборке и только с `-uiTesting` (хранилище в памяти).
@MainActor
enum UITestingHooks {
    private static var defaults: UserDefaults { .standard }
    private static var isActive: Bool { RunMode.current == .uiTesting }

    static func applyAppearance() {
        guard isActive else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard let value = defaults.string(forKey: "uiTestingAppearance") else { return }
        NSApp.appearance = NSAppearance(named: value == "light" ? .aqua : .darkAqua)
    }

    static func configure(_ navigation: NavigationModel, context: ModelContext, openWindow: OpenWindowAction) {
        guard isActive else { return }
        applyAppearance()
        if let value = defaults.string(forKey: "uiTestingSection"), let section = SidebarItem(rawValue: value) {
            navigation.selection = section
        }
        if defaults.string(forKey: "uiTestingDynamicsMode") == "comparison" {
            navigation.selection = .comparison
        }
        if let value = defaults.string(forKey: "uiTestingComparisonFilter"), let filter = ComparisonFilter(rawValue: value) {
            navigation.comparison.filter = filter
        }
        if let code = defaults.string(forKey: "uiTestingIndicator") {
            navigation.paths[.dynamics] = [.indicator(code)]
            navigation.catalog.selection = code
        }
        if let path = defaults.string(forKey: "uiTestingImport") {
            navigation.importDocument(URL(fileURLWithPath: path))
        }
        let latest = ExaminationStore(context: context).allExaminations().first { $0.status != .draft }
        if defaults.bool(forKey: "uiTestingOpenLatest"), let latest {
            navigation.openExamination(latest.id)
        }
        if defaults.bool(forKey: "uiTestingOpenRichest"),
           let richest = ExaminationStore(context: context).allExaminations()
            .filter({ $0.status != .draft }).max(by: { $0.results.count < $1.results.count }) {
            navigation.openExamination(richest.id)
        }
        if defaults.bool(forKey: "uiTestingInspector") {
            navigation.examinations.showInspector = true
            if let latest { navigation.examinations.selection = [latest.id] }
        }
        scheduleSnapshot()
        switch defaults.string(forKey: "uiTestingEditor") {
        case "new": openWindow(id: WindowID.editor, value: EditorRequest.new())
        case "repeat": if let latest { openWindow(id: WindowID.editor, value: EditorRequest.repeatFrom(latest.id)) }
        case "edit":
            let target = ExaminationStore(context: context).allExaminations().first { $0.results.count > 8 }
            if let target { openWindow(id: WindowID.editor, value: EditorRequest.edit(target.id)) }
        default: break
        }
    }

    /// `-uiTestingSnapshot /путь.png`: через несколько секунд сохраняет снимок главного окна
    /// средствами самого приложения (без права на запись экрана) и закрывает приложение.
    static func scheduleSnapshot() {
        guard isActive, let path = defaults.string(forKey: "uiTestingSnapshot") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(defaults.double(forKey: "uiTestingSnapshotDelay").nonZero ?? 3))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let image = captureOwnWindow(window) else { return }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
            if !defaults.bool(forKey: "uiTestingSnapshotKeepOpen") { NSApp.terminate(nil) }
        }
    }

    /// Снимок собственного окна через CGWindowListCreateImage: для окон своего процесса
    /// разрешение на запись экрана не нужно. В Swift функция помечена устаревшей, поэтому через dlsym.
    private static func captureOwnWindow(_ window: NSWindow) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // kCGWindowListOptionIncludingWindow; kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution.
        return create(.null, 1 << 3, UInt32(window.windowNumber), 1 | 1 << 3)?.takeRetainedValue()
    }

    static var selectsFirstResult: Bool { isActive && defaults.bool(forKey: "uiTestingSelectResult") }

    static var initialDetailTab: ExaminationDetailTab? {
        guard isActive, let value = defaults.string(forKey: "uiTestingTab") else { return nil }
        return ExaminationDetailTab(rawValue: value)
    }
}
private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
#endif
