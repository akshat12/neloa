import AVFoundation
import AVKit
import SwiftUI

enum ReviewTimelineSelection {
    nonisolated static func stepID(at time: TimeInterval, in steps: [WorkflowStep]) -> UUID? {
        let ordered = steps.enumerated().sorted { lhs, rhs in
            if lhs.element.time == rhs.element.time { return lhs.offset < rhs.offset }
            return lhs.element.time < rhs.element.time
        }.map(\.element)
        return ordered.last(where: { $0.time <= time + 0.05 })?.id ?? ordered.first?.id
    }

    nonisolated static func duration(videoDuration: TimeInterval, steps: [WorkflowStep]) -> TimeInterval {
        if videoDuration > 0 { return max(videoDuration, 1) }
        return max((steps.map(\.time).max() ?? 0) + 0.5, 1)
    }

    nonisolated static func stepID(
        at time: TimeInterval,
        in steps: [WorkflowStep],
        preserving selectedStepID: UUID?,
        at selectedTime: TimeInterval?
    ) -> UUID? {
        if let selectedStepID,
           steps.contains(where: { $0.id == selectedStepID }),
           let selectedTime,
           abs(selectedTime - time) <= 0.1 {
            return selectedStepID
        }
        return stepID(at: time, in: steps)
    }
}

@MainActor
final class ReviewPlaybackModel: ObservableObject {
    let player: AVPlayer?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false

    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?

    init(recordingPath: String?) {
        guard let recordingPath,
              FileManager.default.fileExists(atPath: recordingPath),
              let fileSize = try? FileManager.default.attributesOfItem(atPath: recordingPath)[.size] as? NSNumber,
              fileSize.int64Value > 0 else {
            player = nil
            return
        }

        let player = AVPlayer(url: URL(fileURLWithPath: recordingPath))
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.updatePlaybackState(time: time)
            }
        }
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playbackDidEnd()
            }
        }
    }

    deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.rate == 0 {
            if duration > 0, currentTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func seek(to time: TimeInterval) {
        let clampedTime = clampedTime(time)
        guard let player else {
            currentTime = clampedTime
            return
        }
        let target = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clampedTime
    }

    func clampedTime(_ time: TimeInterval) -> TimeInterval {
        let nonnegative = max(0, time)
        guard duration > 0 else { return nonnegative }
        return min(nonnegative, duration)
    }

    private func updatePlaybackState(time: CMTime) {
        let seconds = time.seconds
        if seconds.isFinite {
            currentTime = max(0, seconds)
        }
        if let itemDuration = player?.currentItem?.duration.seconds,
           itemDuration.isFinite,
           itemDuration > 0 {
            duration = itemDuration
        }
        isPlaying = (player?.rate ?? 0) != 0
    }

    private func playbackDidEnd() {
        isPlaying = false
        if duration > 0 {
            currentTime = duration
        }
    }
}

struct WorkflowReviewView: View {
    @Binding var workflow: Workflow
    @StateObject private var playback: ReviewPlaybackModel
    @State private var selectedStepID: UUID?
    @State private var pinnedStepID: UUID?
    @State private var pinnedTime: TimeInterval?

    init(workflow: Binding<Workflow>) {
        _workflow = workflow
        _playback = StateObject(wrappedValue: ReviewPlaybackModel(recordingPath: workflow.wrappedValue.recordingPath))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("Automation name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Automation name", text: $workflow.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                Spacer()
                Label("\(workflow.steps.count) salient actions", systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    videoSurface

                    ReviewTimeline(
                        currentTime: playback.currentTime,
                        videoDuration: playback.duration,
                        steps: workflow.steps,
                        selectedStepID: selectedStepID,
                        isPlaying: playback.isPlaying,
                        hasVideo: playback.player != nil,
                        togglePlayback: playback.togglePlayback,
                        seek: seek,
                        selectStep: selectStep
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text("What you said")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(workflow.transcript.isEmpty ? "No narration was captured." : workflow.transcript)
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 82)
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.trailing, 14)
                .frame(minWidth: 500, idealWidth: 620)

                ReviewActionsSidebar(
                    steps: $workflow.steps,
                    selectedStepID: $selectedStepID,
                    select: selectStep
                )
                .padding(.leading, 14)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)
            }
        }
        .onAppear {
            selectedStepID = ReviewTimelineSelection.stepID(at: playback.currentTime, in: workflow.steps)
        }
        .onChange(of: playback.currentTime) { _, newTime in
            selectedStepID = ReviewTimelineSelection.stepID(
                at: newTime,
                in: workflow.steps,
                preserving: pinnedStepID,
                at: pinnedTime
            )
            if let pinnedTime, abs(pinnedTime - newTime) > 0.1 {
                pinnedStepID = nil
                self.pinnedTime = nil
            }
        }
        .onChange(of: workflow.steps.map(\.id)) { _, stepIDs in
            if let selectedStepID, !stepIDs.contains(selectedStepID) {
                self.selectedStepID = ReviewTimelineSelection.stepID(at: playback.currentTime, in: workflow.steps)
            }
            if let pinnedStepID, !stepIDs.contains(pinnedStepID) {
                self.pinnedStepID = nil
                pinnedTime = nil
            }
        }
    }

    @ViewBuilder
    private var videoSurface: some View {
        if let player = playback.player {
            ReviewVideoSurface(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.18)))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.09))
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    VStack(spacing: 9) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No screen recording was captured")
                            .font(.system(size: 15, weight: .semibold))
                        Text("The learned actions and narration are still available for review.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private func seek(to time: TimeInterval) {
        pinnedStepID = nil
        pinnedTime = nil
        selectedStepID = ReviewTimelineSelection.stepID(at: time, in: workflow.steps)
        playback.seek(to: time)
    }

    private func selectStep(_ step: WorkflowStep) {
        let targetTime = playback.clampedTime(step.time)
        selectedStepID = step.id
        pinnedStepID = step.id
        pinnedTime = targetTime
        playback.seek(to: targetTime)
    }
}

private struct ReviewVideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private struct ReviewTimeline: View {
    let currentTime: TimeInterval
    let videoDuration: TimeInterval
    let steps: [WorkflowStep]
    let selectedStepID: UUID?
    let isPlaying: Bool
    let hasVideo: Bool
    let togglePlayback: () -> Void
    let seek: (TimeInterval) -> Void
    let selectStep: (WorkflowStep) -> Void

    private var effectiveDuration: TimeInterval {
        ReviewTimelineSelection.duration(videoDuration: videoDuration, steps: steps)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Label("Recording timeline", systemImage: "timeline.selection")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(currentTime.compactClockString) / \(effectiveDuration.compactClockString)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let trackWidth = max(1, geometry.size.width - 12)
                let progress = min(max(currentTime / effectiveDuration, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 6)
                        .padding(.horizontal, 6)

                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: max(6, trackWidth * progress), height: 6)
                        .padding(.leading, 6)

                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        let position = min(max(step.time / effectiveDuration, 0), 1)
                        Button {
                            selectStep(step)
                        } label: {
                            Circle()
                                .fill(step.id == selectedStepID ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                                .frame(width: step.id == selectedStepID ? 14 : 11, height: step.id == selectedStepID ? 14 : 11)
                        }
                        .buttonStyle(.plain)
                        .help("\(step.time.compactClockString) · \(step.title)")
                        .position(
                            x: 6 + trackWidth * position,
                            y: geometry.size.height / 2 + (index.isMultiple(of: 2) ? -5 : 5)
                        )
                    }

                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2, height: 21)
                        .position(x: 6 + trackWidth * progress, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(max((value.location.x - 6) / trackWidth, 0), 1)
                            seek(effectiveDuration * fraction)
                        }
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Recording timeline")
                .accessibilityValue("\(currentTime.compactClockString) of \(effectiveDuration.compactClockString)")
                .accessibilityHint("Adjust to seek through the recording")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        seek(min(effectiveDuration, currentTime + 5))
                    case .decrement:
                        seek(max(0, currentTime - 5))
                    @unknown default:
                        break
                    }
                }
            }
            .frame(height: 38)

            HStack(spacing: 10) {
                Button(action: togglePlayback) {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasVideo)

                if let selected = steps.first(where: { $0.id == selectedStepID }) {
                    Text("Selected: \(selected.title)")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                } else {
                    Text("Select a marker or action")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ReviewActionsSidebar: View {
    @Binding var steps: [WorkflowStep]
    @Binding var selectedStepID: UUID?
    let select: (WorkflowStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Salient actions")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(steps.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            Button {
                                select(step)
                            } label: {
                                ReviewActionCard(
                                    number: index + 1,
                                    step: step,
                                    isSelected: step.id == selectedStepID
                                )
                            }
                            .buttonStyle(.plain)
                            .id(step.id)
                            .contextMenu {
                                Button("Remove action", role: .destructive) {
                                    steps.removeAll { $0.id == step.id }
                                }
                            }
                        }
                    }
                }
                .onChange(of: selectedStepID) { _, selectedID in
                    guard let selectedID else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }

            Label("Select an action to jump to it. Right-click to remove it.", systemImage: "cursorarrow.click")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ReviewActionCard: View {
    let number: Int
    let step: WorkflowStep
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isSelected ? .white : .primary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(step.time.compactClockString)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(step.kind.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(step.kind == .approval ? .orange : Color.accentColor)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.14), lineWidth: isSelected ? 2 : 1)
        )
    }
}

private extension TimeInterval {
    var compactClockString: String {
        let clamped = max(0, self)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
