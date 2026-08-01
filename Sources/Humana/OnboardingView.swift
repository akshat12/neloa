import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionCenter
    let finish: () -> Void
    @State private var page = 0
    @State private var appeared = false
    @State private var orbiting = false

    var body: some View {
        ZStack {
            if page == 0 {
                welcome.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
            } else {
                permissionSetup.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(width: 760, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.spring(response: 0.52, dampingFraction: 0.86), value: page)
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.76).delay(0.08)) { appeared = true }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { orbiting = true }
        }
    }

    private var welcome: some View {
        ZStack {
            Circle()
                .fill(Color.indigo.opacity(0.07))
                .frame(width: 460, height: 460)
                .blur(radius: 22)
                .offset(x: -310, y: -260)
            Circle()
                .fill(Color.blue.opacity(0.055))
                .frame(width: 390, height: 390)
                .blur(radius: 28)
                .offset(x: 340, y: 290)

            VStack(spacing: 25) {
                Spacer(minLength: 20)
                animatedBrand
                    .scaleEffect(appeared ? 1 : 0.78)
                    .opacity(appeared ? 1 : 0)
                Text("Human automation,\ntaught naturally.")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: appeared ? 0 : 18)
                    .opacity(appeared ? 1 : 0)
                Text("Show Humana a task once and explain the choices that matter. Run it again with a different date, amount, or instruction—just by typing or speaking.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 590)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: appeared ? 0 : 14)
                    .opacity(appeared ? 1 : 0)
                HStack(spacing: 16) {
                    onboardingFeature("record.circle", "Teach", "Do the task once", index: 0)
                    onboardingFeature("sparkles", "Adapt", "Ask for a variation", index: 1)
                    onboardingFeature("hand.raised", "Approve", "Stay in control", index: 2)
                }
                .padding(.vertical, 8)
                Spacer(minLength: 8)
                Button("Continue") { page = 1 }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .padding(.bottom, 26)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .padding(34)
    }

    private var animatedBrand: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Color(red: 0.12, green: 0.17, blue: 0.55)).frame(width: 58, height: 58)
                Circle()
                    .trim(from: 0.08, to: 0.91)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(orbiting ? 360 : 0))
                Circle().fill(Color(red: 1.0, green: 0.32, blue: 0.28)).frame(width: 9, height: 9)
            }
            .shadow(color: Color.indigo.opacity(0.25), radius: 12, y: 5)
            Text("humana")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .fixedSize()
        }
    }

    private var permissionSetup: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Allow only what you want to teach", subtitle: "These permissions let Humana observe and replay your demonstration. Recordings stay on this Mac.")
            permissionRow(icon: "rectangle.on.rectangle", title: "Screen recording", detail: "Records the apps you demonstrate", status: permissions.screen) {
                permissions.requestScreen()
            }
            permissionRow(icon: "cursorarrow.click", title: "Input monitoring", detail: "Learns clicks and keystrokes; macOS may require reopening Humana", status: permissions.inputMonitoring) {
                permissions.requestInputMonitoring()
            }
            permissionRow(icon: "mic", title: "Microphone & speech", detail: "Understands explanations and spoken run instructions", status: combinedVoiceStatus) {
                Task { await permissions.requestMicrophoneAndSpeech() }
            }
            HStack {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
                }
                Spacer()
                Button("Back") { withAnimation { page = 0 } }
                Button("Start using Humana") { finish() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(34)
    }

    private var combinedVoiceStatus: PermissionCenter.Status {
        if permissions.microphone == .denied || permissions.speech == .denied { return .denied }
        if permissions.microphone == .granted && permissions.speech == .granted { return .granted }
        return .unknown
    }

    private func onboardingFeature(_ icon: String, _ title: String, _ detail: String, index: Int) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 27, weight: .medium)).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 16, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(width: 168, height: 96)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .offset(y: appeared ? 0 : 20)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.22 + Double(index) * 0.09), value: appeared)
    }

    private func permissionRow(icon: String, title: String, detail: String, status: PermissionCenter.Status, action: @escaping () -> Void) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            if status == .granted {
                Label(status.label, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(status == .denied ? "Open Settings" : "Allow") {
                    if status == .denied,
                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    } else { action() }
                }
            }
        }
        .padding(16).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}
