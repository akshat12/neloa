import AppKit
import SwiftUI

private let sidebarIconColumnWidth: CGFloat = 36

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

    var tourTarget: AppTourTarget {
        switch self {
        case .teach: .teachNavigation
        case .automations: .automationsNavigation
        case .activity: .activityNavigation
        case .settings: .settingsNavigation
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var agent: LocalAgentService
    @State private var selection: NavigationItem? = .teach
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var choseInitialDestination = false
    @State private var showTour = false
    @State private var tourStepIndex = 0
    @State private var scheduledInitialTour = false
    @State private var showStoreIssueDetails = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                BrandMark()
                    .padding(.vertical, 24)
                List {
                    ForEach(NavigationItem.allCases) { item in
                        SidebarNavigationRow(item: item, isSelected: selection == item) {
                            selection = item
                        }
                        .appTourTarget(item.tourTarget)
                    }
                }
                .listStyle(.sidebar)
                .contentMargins(.horizontal, 0, for: .scrollContent)

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
        .overlayPreferenceValue(AppTourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if showTour,
                   AppTourStep.all.indices.contains(tourStepIndex),
                   let anchor = anchors[AppTourStep.all[tourStepIndex].target] {
                    AppTourOverlay(
                        step: AppTourStep.all[tourStepIndex],
                        stepIndex: tourStepIndex,
                        totalSteps: AppTourStep.all.count,
                        spotlight: proxy[anchor],
                        back: previousTourStep,
                        next: nextTourStep,
                        skip: finishTour
                    )
                    .zIndex(100)
                }
            }
        }
        .overlay(alignment: .top) {
            if let issue = store.issue {
                StoreIssueBanner(
                    issue: issue,
                    retry: store.retryLastOperation,
                    showDetails: { showStoreIssueDetails = true },
                    dismiss: store.dismissIssue
                )
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(120)
            }
        }
        .alert(store.issue?.title ?? "Neloa needs attention", isPresented: $showStoreIssueDetails) {
            if store.issue?.canRetry == true {
                Button("Try again") { store.retryLastOperation() }
            }
            Button("Dismiss", role: .cancel) { store.dismissIssue() }
        } message: {
            if let issue = store.issue {
                Text("\(issue.message)\n\nDetails: \(issue.details)")
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(permissions: permissions, agent: agent) { shouldStartTour in
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showOnboarding = false
                if shouldStartTour {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        startTour()
                    }
                } else {
                    markTourComplete()
                }
            }
            .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNeloaWelcome)) { _ in
            permissions.refresh()
            showTour = false
            showOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNeloaTour)) { _ in
            startTour()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNeloaAutomations)) { _ in
            selection = .automations
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNeloaTeach)) { _ in
            selection = .teach
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
        .onAppear {
            permissions.refresh()
            guard !choseInitialDestination else { return }
            choseInitialDestination = true
            selection = store.workflows.isEmpty ? .teach : .automations
            scheduleInitialTourIfNeeded()
        }
    }

    private func scheduleInitialTourIfNeeded() {
        guard !showOnboarding,
              !UserDefaults.standard.bool(forKey: "hasCompletedAppTour"),
              !scheduledInitialTour else { return }
        scheduledInitialTour = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            startTour()
        }
    }

    private func startTour() {
        selection = .teach
        tourStepIndex = 0
        withAnimation(.easeInOut(duration: 0.22)) {
            showTour = true
        }
    }

    private func previousTourStep() {
        guard tourStepIndex > 0 else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            tourStepIndex -= 1
        }
    }

    private func nextTourStep() {
        if tourStepIndex == AppTourStep.all.count - 1 {
            finishTour()
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                tourStepIndex += 1
            }
        }
    }

    private func finishTour() {
        withAnimation(.easeOut(duration: 0.18)) {
            showTour = false
        }
        markTourComplete()
    }

    private func markTourComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedAppTour")
    }
}

private struct StoreIssueBanner: View {
    let issue: WorkflowStoreIssue
    let retry: () -> Void
    let showDetails: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(issue.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            if issue.canRetry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
            Button("Details", action: showDetails)
                .buttonStyle(.bordered)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .accessibilityLabel("Dismiss error")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.32)))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 5)
        .accessibilityElement(children: .contain)
    }
}

private struct SidebarNavigationRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: NavigationItem
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .frame(width: sidebarIconColumnWidth)
                Text(item.rawValue)
                    .fixedSize(horizontal: true, vertical: false)
            }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? selectedForeground : Color.primary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 2, trailing: 18))
        .listRowBackground(Color.clear)
        .onHover { isHovering = $0 }
        .accessibilityLabel(item.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var rowBackground: Color {
        if isSelected { return NeloaPalette.accent }
        if isHovering { return Color.secondary.opacity(0.10) }
        return .clear
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? NeloaPalette.lagoonDeep : .white
    }
}

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 10) {
            NeloaAppIcon(size: sidebarIconColumnWidth)
            Text("Neloa").font(.system(size: 22, weight: .bold, design: .rounded)).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
    }
}

extension Notification.Name {
    static let showNeloaWelcome = Notification.Name("showNeloaWelcome")
    static let showNeloaTour = Notification.Name("showNeloaTour")
    static let showNeloaAutomations = Notification.Name("showNeloaAutomations")
    static let showNeloaTeach = Notification.Name("showNeloaTeach")
}
