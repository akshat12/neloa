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

    func pause() {
        player?.pause()
        isPlaying = false
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
    @State private var instructionDraft: ReviewInstructionDraft?

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
                Label(reviewCountLabel, systemImage: "sparkles.rectangle.stack")
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
                        selectStep: selectStep,
                        addInstruction: beginAddingInstruction
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
                    select: selectStep,
                    editInstruction: beginEditingInstruction
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
        .sheet(item: $instructionDraft) { draft in
            ReviewInstructionEditor(
                draft: draft,
                save: saveInstruction,
                cancel: { instructionDraft = nil }
            )
        }
    }

    private var reviewCountLabel: String {
        let instructionCount = workflow.steps.filter(\.isUserInstruction).count
        let actionCount = workflow.steps.count - instructionCount
        guard instructionCount > 0 else { return "\(actionCount) salient actions" }
        return "\(actionCount) actions · \(instructionCount) instruction\(instructionCount == 1 ? "" : "s")"
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

    private func beginAddingInstruction(at time: TimeInterval) {
        playback.pause()
        let clampedTime = playback.clampedTime(time)
        instructionDraft = ReviewInstructionDraft(time: clampedTime)
    }

    private func beginEditingInstruction(_ step: WorkflowStep) {
        guard step.isUserInstruction else { return }
        playback.pause()
        instructionDraft = ReviewInstructionDraft(
            stepID: step.id,
            time: playback.clampedTime(step.time),
            text: step.text ?? step.title,
            scope: step.instructionScope ?? .thisAction
        )
    }

    private func saveInstruction(_ draft: ReviewInstructionDraft, text: String, scope: WorkflowInstructionScope) {
        let otherSteps = workflow.steps.filter { $0.id != draft.stepID }
        guard let instruction = WorkflowInstructionSupport.makeStep(
            text: text,
            time: draft.time,
            scope: scope,
            existingSteps: otherSteps,
            id: draft.stepID ?? draft.id
        ) else { return }
        workflow.steps = WorkflowInstructionSupport.inserting(instruction, into: workflow.steps)
        selectedStepID = instruction.id
        pinnedStepID = instruction.id
        pinnedTime = instruction.time
        playback.seek(to: instruction.time)
        instructionDraft = nil
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
    let addInstruction: (TimeInterval) -> Void

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
                            TimelineMarker(step: step, isSelected: step.id == selectedStepID)
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
                    Text(selected.isUserInstruction ? "Your instruction: \(selected.title)" : "Selected: \(selected.title)")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                } else {
                    Text("Select a marker or action")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    addInstruction(currentTime)
                } label: {
                    Label("Add instruction at \(currentTime.compactClockString)", systemImage: "text.bubble.fill")
                }
                .buttonStyle(.bordered)
                .help("Add something Neloa should understand at this point in the recording")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TimelineMarker: View {
    let step: WorkflowStep
    let isSelected: Bool

    var body: some View {
        if step.isUserInstruction {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: isSelected ? 14 : 11, weight: .bold))
                .foregroundStyle(isSelected ? .white : Color.orange)
                .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
                .background(isSelected ? Color.orange : Color(nsColor: .windowBackgroundColor), in: Circle())
                .overlay(Circle().stroke(Color.orange, lineWidth: 2))
        } else {
            Circle()
                .fill(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                .frame(width: isSelected ? 14 : 11, height: isSelected ? 14 : 11)
        }
    }
}

private struct ReviewActionsSidebar: View {
    @Binding var steps: [WorkflowStep]
    @Binding var selectedStepID: UUID?
    let select: (WorkflowStep) -> Void
    let editInstruction: (WorkflowStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workflow moments")
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
                                    number: inferredActionNumber(at: index),
                                    step: step,
                                    isSelected: step.id == selectedStepID
                                )
                            }
                            .buttonStyle(.plain)
                            .id(step.id)
                            .contextMenu {
                                if step.isUserInstruction {
                                    Button("Edit instruction") {
                                        editInstruction(step)
                                    }
                                }
                                Button(step.isUserInstruction ? "Remove instruction" : "Remove action", role: .destructive) {
                                    steps = WorkflowInstructionSupport.removing(stepID: step.id, from: steps)
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

            Label("Select a moment to jump to it. Right-click your instructions to edit or remove them.", systemImage: "cursorarrow.click")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inferredActionNumber(at index: Int) -> Int {
        steps.prefix(index + 1).filter { !$0.isUserInstruction }.count
    }
}

private struct ReviewActionCard: View {
    let number: Int
    let step: WorkflowStep
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Group {
                if step.isUserInstruction {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
            .frame(width: 28, height: 28)
            .background(markerColor.opacity(isSelected ? 1 : 0.12), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isSelected ? .white : markerColor)

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
                Text(step.displayKindLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(markerColor)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? markerColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(isSelected ? markerColor : Color.secondary.opacity(0.14), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var markerColor: Color {
        step.isUserInstruction || step.kind == .approval ? .orange : Color.accentColor
    }
}

private struct ReviewInstructionDraft: Identifiable {
    let id: UUID
    let stepID: UUID?
    let time: TimeInterval
    let text: String
    let scope: WorkflowInstructionScope

    init(
        id: UUID = UUID(),
        stepID: UUID? = nil,
        time: TimeInterval,
        text: String = "",
        scope: WorkflowInstructionScope = .thisAction
    ) {
        self.id = id
        self.stepID = stepID
        self.time = time
        self.text = text
        self.scope = scope
    }
}

private struct ReviewInstructionEditor: View {
    let draft: ReviewInstructionDraft
    let save: (ReviewInstructionDraft, String, WorkflowInstructionScope) -> Void
    let cancel: () -> Void

    @StateObject private var voice = VoiceService()
    @State private var text: String
    @State private var scope: WorkflowInstructionScope
    @State private var voiceBusy = false
    @State private var voiceTask: Task<Void, Never>?
    @FocusState private var textIsFocused: Bool

    init(
        draft: ReviewInstructionDraft,
        save: @escaping (ReviewInstructionDraft, String, WorkflowInstructionScope) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.save = save
        self.cancel = cancel
        _text = State(initialValue: draft.text)
        _scope = State(initialValue: draft.scope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.stepID == nil ? "Add your instruction" : "Edit your instruction")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("At \(draft.time.compactClockString) in the recording · Kept separate from inferred actions.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What should Neloa understand here?")
                    .font(.system(size: 14, weight: .semibold))

                TextEditor(text: $text)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 112)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.secondary.opacity(0.22)))
                    .focused($textIsFocused)
                    .accessibilityLabel("Instruction")

                HStack(spacing: 10) {
                    Button {
                        toggleVoice()
                    } label: {
                        Label(
                            voice.isListening ? "Finish speaking" : "Say it instead",
                            systemImage: voice.isListening ? "stop.circle.fill" : "mic.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(voice.isListening ? .red : Color.accentColor)
                    .disabled(voiceBusy)

                    if voice.isListening {
                        Label("Listening on this Mac", systemImage: "waveform")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    } else {
                        Text("Type or speak in your own words.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = voice.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Where should it apply?")
                    .font(.system(size: 14, weight: .semibold))
                Picker("Instruction scope", selection: $scope) {
                    ForEach(WorkflowInstructionScope.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(scope.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Approval wording creates a hard gate; other instructions create a review checkpoint.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) {
                    stopVoice()
                    cancel()
                }
                    .keyboardShortcut(.cancelAction)
                Button(draft.stepID == nil ? "Add to workflow" : "Save changes") {
                    stopVoice()
                    save(draft, text, scope)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { textIsFocused = true }
        .onChange(of: voice.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            text = transcript
        }
        .onDisappear {
            stopVoice()
        }
    }

    private func toggleVoice() {
        if voice.isListening {
            _ = voice.stop()
            return
        }
        voiceTask = Task {
            voiceBusy = true
            defer {
                voiceBusy = false
                voiceTask = nil
            }
            do {
                _ = try await voice.start()
                if Task.isCancelled { _ = voice.stop() }
            } catch {
                if !Task.isCancelled { voice.errorMessage = error.localizedDescription }
            }
        }
    }

    private func stopVoice() {
        voiceTask?.cancel()
        voiceTask = nil
        if voice.isListening { _ = voice.stop() }
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
