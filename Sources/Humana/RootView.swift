import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case teach = "Teach"
    case automations = "Automations"
    case skills = "Skills"
    case agents = "Agents"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .teach: "record.circle"
        case .automations: "square.grid.2x2"
        case .skills: "sparkles"
        case .agents: "person.2"
        }
    }
}

struct RootView: View {
    @State private var selection: NavigationItem? = .teach
    @StateObject private var permissions = PermissionCenter()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

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

                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 9, height: 9)
                    Text("Local processing").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(20)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            Group {
                switch selection ?? .teach {
                case .teach: TeachView()
                case .automations: AutomationsView()
                case .skills: CapabilityView(title: "Skills", subtitle: "Reusable knowledge Humana can apply inside an automation.", icon: "sparkles")
                case .agents: CapabilityView(title: "Agents", subtitle: "Decision-makers that handle safe variations in your workflows.", icon: "person.2")
                }
            }
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
}

struct CapabilityView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(subtitle))
    }
}
