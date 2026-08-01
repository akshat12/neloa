import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case teach = "Teach"
    case automations = "My automations"
    case activity = "Activity"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .teach: "sparkles.rectangle.stack"
        case .automations: "repeat"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: WorkflowStore
    @State private var selection: NavigationItem? = .teach
    @StateObject private var permissions = PermissionCenter()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var choseInitialDestination = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                BrandMark()
                    .padding(.vertical, 24)
                List(NavigationItem.allCases, selection: $selection) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.vertical, 7)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Button {
                    selection = .settings
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Private by design").font(.system(size: 13, weight: .semibold))
                            Text("View privacy controls").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(20)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            Group {
                switch selection ?? .teach {
                case .teach: TeachView()
                case .automations: AutomationsView()
                case .activity: ActivityView()
                case .settings: SettingsPage()
                }
            }
            .environmentObject(permissions)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(Color(red: 0.20, green: 0.31, blue: 0.82))
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(permissions: permissions) {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHumanaWelcome)) { _ in
            permissions.refresh()
            showOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHumanaAutomations)) { _ in
            selection = .automations
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHumanaTeach)) { _ in
            selection = .teach
        }
        .onAppear {
            guard !choseInitialDestination else { return }
            choseInitialDestination = true
            selection = store.workflows.isEmpty ? .teach : .automations
        }
    }
}

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(red: 0.12, green: 0.17, blue: 0.55)).frame(width: 34, height: 34)
                Circle().stroke(.white, lineWidth: 5).frame(width: 19, height: 19)
                Circle().fill(.white).frame(width: 5, height: 5)
            }
            Text("humana").font(.system(size: 22, weight: .bold, design: .rounded)).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }
}

extension Notification.Name {
    static let showHumanaWelcome = Notification.Name("showHumanaWelcome")
    static let showHumanaAutomations = Notification.Name("showHumanaAutomations")
    static let showHumanaTeach = Notification.Name("showHumanaTeach")
}
