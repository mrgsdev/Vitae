import SwiftData
import SwiftUI

@main
struct VitaeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup("Vitae", id: WindowID.main) {
            MainWindowView()
                .appEnvironment(environment)
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            VitaeCommands(environment: environment)
        }

        WindowGroup("Обследование", id: WindowID.examination, for: UUID.self) { $examinationID in
            ExaminationWindowView(examinationID: examinationID)
                .appEnvironment(environment)
        }
        .defaultSize(width: 1080, height: 780)

        WindowGroup("Редактор обследования", id: WindowID.editor, for: EditorRequest.self) { $request in
            ExaminationEditorWindow(request: request ?? .new())
                .appEnvironment(environment)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unifiedCompact)

        Window("Справка Vitae", id: "help") {
            HelpView()
                .environment(\.locale, AppLocale.locale)
        }
        .defaultSize(width: 640, height: 640)

        Settings {
            SettingsView()
                .appEnvironment(environment)
                .frame(minWidth: 680, minHeight: 520)
        }
    }
}

private struct AppEnvironmentModifier: ViewModifier {
    let environment: AppEnvironment

    func body(content: Content) -> some View {
        content
            .environment(environment)
            .environment(\.locale, AppLocale.locale)
            .modelContainer(environment.container)
            .overlay {
                if environment.lock.isLocked {
                    LockScreenView()
                        .environment(environment)
                }
            }
    }
}

extension View {
    func appEnvironment(_ environment: AppEnvironment) -> some View {
        modifier(AppEnvironmentModifier(environment: environment))
    }
}
