import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 30, weight: .bold))
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
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
                .font(.title2)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(16)
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
                Text(step.title).fontWeight(.semibold).lineLimit(2)
                if !step.detail.isEmpty { Text(step.detail).font(.caption).foregroundStyle(.secondary) }
                Text(step.kind.label)
                    .font(.caption2.weight(.semibold))
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
