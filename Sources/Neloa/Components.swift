import AppKit
import SwiftUI

struct NeloaAppIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = Self.bundledIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let bundledIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.08, green: 0.09, blue: 0.34), Color(red: 0.20, green: 0.29, blue: 0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Circle()
                .trim(from: 0.11, to: 0.94)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                .frame(width: size * 0.53, height: size * 0.53)
                .rotationEffect(.degrees(-12))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: size * 0.11, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-8))
                .offset(x: size * 0.27, y: -size * 0.04)
            Circle()
                .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.13, height: size * 0.13)
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 35, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 18)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FeatureToggle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StepRow: View {
    let number: Int
    let step: WorkflowStep
    var isCurrent = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(width: 30, height: 30)
                .background(isCurrent ? Color.accentColor : Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(isCurrent ? .white : .primary)
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                if !step.detail.isEmpty { Text(step.detail).font(.system(size: 14)).foregroundStyle(.secondary) }
                Text(step.kind.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(step.kind == .approval ? .orange : Color.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((step.kind == .approval ? Color.orange : Color.accentColor).opacity(0.11), in: Capsule())
            }
            Spacer()
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.16)))
    }
}

extension TimeInterval {
    var clockString: String {
        String(format: "%02d:%02d", Int(self) / 60, Int(self) % 60)
    }
}
