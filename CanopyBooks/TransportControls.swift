import SwiftUI

/// Progress bar plus skip, play/pause and speed buttons, sized to sit under the artwork.
struct TransportControls: View {
    let model: AudiobookPlayer
    var focus: FocusState<PlayerFocus?>.Binding
    @Binding var scrubTime: Double?

    var body: some View {
        VStack(spacing: 30) {
            ScrubBar(elapsed: model.elapsed, duration: model.duration, scrubTime: $scrubTime, onCommit: model.seek)
                .focused(focus, equals: .scrubber)
                .accessibilityIdentifier("scrubber")

            HStack(spacing: 20) {
                Button("Back \(Int(AudiobookPlayer.skipInterval)) Seconds", systemImage: "gobackward.15") {
                    model.skip(by: -AudiobookPlayer.skipInterval)
                }
                .focused(focus, equals: .skipBack)
                .accessibilityIdentifier("skipBack")

                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.togglePlayPause()
                }
                .focused(focus, equals: .playPause)
                .accessibilityIdentifier("playPause")

                Button("Forward \(Int(AudiobookPlayer.skipInterval)) Seconds", systemImage: "goforward.15") {
                    model.skip(by: AudiobookPlayer.skipInterval)
                }
                .focused(focus, equals: .skipForward)
                .accessibilityIdentifier("skipForward")

                SpeedMenu(model: model)
                    .focused(focus, equals: .speed)
                    .accessibilityIdentifier("speed")
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .disabled(scrubTime != nil)
        }
    }
}

private struct SpeedMenu: View {
    let model: AudiobookPlayer

    var body: some View {
        Menu {
            Picker("Playback Speed", selection: Binding(get: { model.rate }, set: model.setRate)) {
                ForEach(model.speeds, id: \.self) { speed in
                    Text(Self.label(for: speed)).tag(speed)
                }
            }
        } label: {
            Text(Self.label(for: model.rate))
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
        }
        .buttonBorderShape(.capsule)
    }

    /// "0.5×", "1×", "1.25×"
    private static func label(for rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

/// Click to start scrubbing, left/right to move 10 seconds, click again to jump there.
/// Back cancels (handled by `PlayerScreen`).
struct ScrubBar: View {
    let elapsed: Double
    let duration: Double
    @Binding var scrubTime: Double?
    let onCommit: (Double) -> Void

    private static let step = 10.0

    var body: some View {
        Button {
            if let scrubTime {
                onCommit(scrubTime)
                self.scrubTime = nil
            } else {
                scrubTime = elapsed
            }
        } label: {
            Text("Playback Position")
        }
        .buttonStyle(ScrubBarStyle(time: scrubTime ?? elapsed, duration: duration, isScrubbing: scrubTime != nil))
        .onMoveCommand { direction in
            guard let current = scrubTime else { return }
            switch direction {
            case .left: scrubTime = max(0, current - Self.step)
            case .right: scrubTime = min(duration, current + Self.step)
            default: break
            }
        }
    }
}

private struct ScrubBarStyle: ButtonStyle {
    let time: Double
    let duration: Double
    let isScrubbing: Bool

    func makeBody(configuration: Configuration) -> some View {
        ScrubBarBody(time: time, duration: duration, isScrubbing: isScrubbing)
    }
}

private struct ScrubBarBody: View {
    let time: Double
    let duration: Double
    let isScrubbing: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let progress = duration > 0 ? min(1, max(0, time / duration)) : 0
        VStack(spacing: 12) {
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.25))
                Rectangle()
                    .fill(.white.opacity(isFocused ? 1 : 0.75))
                    .scaleEffect(x: progress, anchor: .leading)
            }
            .frame(height: isFocused ? 14 : 6)
            .clipShape(.capsule)

            HStack {
                Text(Self.format(time))
                Spacer()
                Text("-" + Self.format(max(0, duration - time)))
            }
            .font(.system(size: 22, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(isScrubbing ? 1 : 0.55))
        }
        .frame(height: 54, alignment: .top)
        .blendMode(.plusLighter)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .accessibilityLabel("Playback Position")
        .accessibilityValue(Self.format(time))
    }

    private static func format(_ seconds: Double) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: pattern))
    }
}
