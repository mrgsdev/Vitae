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
            navigation.dynamics.mode = .comparison
        }
        if let code = defaults.string(forKey: "uiTestingIndicator") {
            navigation.dynamics.selectedCode = code
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
        switch defaults.string(forKey: "uiTestingEditor") {
        case "new": openWindow(id: WindowID.editor, value: EditorRequest.new())
        case "repeat": if let latest { openWindow(id: WindowID.editor, value: EditorRequest.repeatFrom(latest.id)) }
        case "edit":
            let target = ExaminationStore(context: context).allExaminations().first { $0.results.count > 8 }
            if let target { openWindow(id: WindowID.editor, value: EditorRequest.edit(target.id)) }
        default: break
        }
    }

    static var selectsFirstResult: Bool { isActive && defaults.bool(forKey: "uiTestingSelectResult") }

    static var initialDetailTab: ExaminationDetailTab? {
        guard isActive, let value = defaults.string(forKey: "uiTestingTab") else { return nil }
        return ExaminationDetailTab(rawValue: value)
    }
}
#endif
