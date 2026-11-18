import SwiftData
import SwiftUI

/// Главное окно: боковая панель + рабочая область с NavigationStack для каждого раздела.
struct MainWindowView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.openWindow) private var openWindow

    @State private var navigation = NavigationModel()
    @SceneStorage("main.sidebarSelection") private var storedSelection = SidebarItem.dashboard.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $navigation.selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            SectionContainerView(navigation: navigation)
        }
        .frame(minWidth: 980, minHeight: 620)
        .environment(\.navigationModel, navigation)
        .focusedSceneValue(\.navigation, navigation)
        .onAppear {
            navigation.selection = SidebarItem(rawValue: storedSelection) ?? .dashboard
            consumePendingRoute()
            modelContext.undoManager = undoManager
            #if DEBUG
            UITestingHooks.configure(navigation, context: modelContext, openWindow: openWindow)
            #endif
        }
        .onChange(of: navigation.selection) { _, newValue in
            if let newValue { storedSelection = newValue.rawValue }
        }
        .onChange(of: environment.pendingRoute) { _, _ in consumePendingRoute() }
        .task {
            await offerUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await offerUpdate() }
        }
        .onChange(of: controlActiveState) { _, state in
            if state == .key { modelContext.undoManager = undoManager }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = environment.startupError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.15))
            } else if let notice = environment.migrationNotice {
                HStack {
                    Label(notice, systemImage: "arrow.right.doc.on.clipboard")
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Скрыть") { environment.migrationNotice = nil }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1))
            }
        }
    }

    /// Проверка при запуске и не чаще двух раз в сутки; окно открывается, только если есть новая версия.
    private func offerUpdate() async {
        if await Updater.shared.checkInBackground() {
            openWindow(id: "update")
        }
    }

    private func consumePendingRoute() {
        guard let route = environment.pendingRoute else { return }
        environment.pendingRoute = nil
        navigation.apply(route)
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query(filter: #Predicate<Examination> { $0.statusRaw == "draft" }) private var drafts: [Examination]
    @Query(filter: #Predicate<Reminder> { !$0.isCompleted }) private var activeReminders: [Reminder]

    var body: some View {
        List(selection: $selection) {
            Section("Обзор") {
                row(.dashboard)
            }
            Section("Мои анализы") {
                row(.examinations, badge: drafts.count)
                row(.dynamics)
                row(.comparison)
                row(.expenses)
            }
            Section("Справочники") {
                row(.catalog)
            }
            Section("Сервис") {
                row(.importExport)
                row(.reminders, badge: activeReminders.filter { $0.dueDate <= .now }.count)
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("sidebar")
    }

    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label(item.title, systemImage: item.symbolName)
            .badge(badge)
            .tag(item)
            .help(item.hint)
            .accessibilityIdentifier("sidebar.\(item.rawValue)")
    }
}

struct SectionContainerView: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        let section = navigation.selection ?? .dashboard
        NavigationStack(path: navigation.path(for: section)) {
            root(for: section)
                .navigationDestination(for: AppRoute.self) { route in
                    RouteDestinationView(route: route, navigation: navigation)
                }
        }
        .id(section)
    }

    @ViewBuilder
    private func root(for section: SidebarItem) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .examinations: ExaminationsView(navigation: navigation)
        case .dynamics: DynamicsView(navigation: navigation)
        case .comparison: ComparisonView(navigation: navigation)
        case .expenses: ExpensesView(navigation: navigation)
        case .catalog: LabTestsView(navigation: navigation)
        case .importExport: ImportExportView(navigation: navigation)
        case .reminders: RemindersView()
        case .settings: SettingsView(isInline: true)
        }
    }
}

struct RouteDestinationView: View {
    let route: AppRoute
    let navigation: NavigationModel

    var body: some View {
        switch route {
        case .examination(let id):
            ExaminationDetailContainer(examinationID: id)
        case .indicator(let code):
            IndicatorDetailContainer(code: code, navigation: navigation)
        case .documentImport(let request):
            DocumentImportView(request: request)
        }
    }
}
