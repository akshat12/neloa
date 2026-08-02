import SwiftUI

enum AppTourTarget: Hashable {
    case teachNavigation
    case teachingSetup
    case startTeaching
    case automationsNavigation
    case activityNavigation
    case settingsNavigation
}

struct AppTourAnchorKey: PreferenceKey {
    static var defaultValue: [AppTourTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [AppTourTarget: Anchor<CGRect>], nextValue: () -> [AppTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func appTourTarget(_ target: AppTourTarget) -> some View {
        anchorPreference(key: AppTourAnchorKey.self, value: .bounds) { anchor in
            [target: anchor]
        }
    }
}

struct AppTourStep: Identifiable, Equatable {
    let target: AppTourTarget
    let title: String
    let detail: String

    var id: AppTourTarget { target }

    static let all = [
        AppTourStep(
            target: .teachNavigation,
            title: "Teach Neloa a task",
            detail: "Start here whenever you want to turn a task you already know into a reusable automation."
        ),
        AppTourStep(
            target: .teachingSetup,
            title: "Choose what Neloa can learn",
            detail: "Decide whether Neloa can watch the screen, follow clicks and typing, and listen to your explanation."
        ),
        AppTourStep(
            target: .startTeaching,
            title: "Show the task once",
            detail: "Start teaching, complete the task naturally, and explain the decisions that may change next time."
        ),
        AppTourStep(
            target: .automationsNavigation,
            title: "Run it again—with changes",
            detail: "Your saved automations live here. Ask Neloa to use a different date, amount, person, or file on each run."
        ),
        AppTourStep(
            target: .activityNavigation,
            title: "See what happened",
            detail: "Activity keeps a clear record of teaching sessions and automation runs."
        ),
        AppTourStep(
            target: .settingsNavigation,
            title: "You control access",
            detail: "Review permissions, privacy controls, local processing, and model options at any time."
        )
    ]
}

struct AppTourOverlay: View {
    let step: AppTourStep
    let stepIndex: Int
    let totalSteps: Int
    let spotlight: CGRect
    let back: () -> Void
    let next: () -> Void
    let skip: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let highlightedRect = spotlight.insetBy(dx: -9, dy: -7)
            let calloutWidth = min(350, geometry.size.width - 40)
            let calloutPosition = position(
                for: highlightedRect,
                calloutWidth: calloutWidth,
                container: geometry.size
            )

            ZStack(alignment: .topLeading) {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.66))
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .frame(width: highlightedRect.width, height: highlightedRect.height)
                        .position(x: highlightedRect.midX, y: highlightedRect.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .shadow(color: Color.accentColor.opacity(0.55), radius: 9)
                    .frame(width: highlightedRect.width, height: highlightedRect.height)
                    .position(x: highlightedRect.midX, y: highlightedRect.midY)

                tourCallout
                    .frame(width: calloutWidth)
                    .position(calloutPosition)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: spotlight)
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Neloa guided tour")
    }

    private var tourCallout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("QUICK TOUR")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("\(stepIndex + 1) of \(totalSteps)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(step.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index == stepIndex ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: index == stepIndex ? 18 : 6, height: 6)
                }
            }

            HStack {
                Button("Skip tour", action: skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                if stepIndex > 0 {
                    Button("Back", action: back)
                        .buttonStyle(.bordered)
                }

                Button(stepIndex == totalSteps - 1 ? "Finish" : "Next", action: next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.28)))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private func position(for rect: CGRect, calloutWidth: CGFloat, container: CGSize) -> CGPoint {
        let estimatedHeight: CGFloat = 220
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 18

        if rect.maxX < container.width * 0.32 {
            let x = min(rect.maxX + horizontalPadding + calloutWidth / 2, container.width - calloutWidth / 2 - horizontalPadding)
            let y = min(max(rect.midY, estimatedHeight / 2 + verticalPadding), container.height - estimatedHeight / 2 - verticalPadding)
            return CGPoint(x: x, y: y)
        }

        let x = min(max(rect.midX, calloutWidth / 2 + horizontalPadding), container.width - calloutWidth / 2 - horizontalPadding)
        let hasRoomBelow = rect.maxY + verticalPadding + estimatedHeight < container.height
        let y = hasRoomBelow
            ? rect.maxY + verticalPadding + estimatedHeight / 2
            : rect.minY - verticalPadding - estimatedHeight / 2
        return CGPoint(x: x, y: min(max(y, estimatedHeight / 2 + verticalPadding), container.height - estimatedHeight / 2 - verticalPadding))
    }
}
