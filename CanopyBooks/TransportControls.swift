import SwiftUI

/// Progress bar (as wide as the artwork) plus bookmark, chapter, skip, play/pause and speed
/// buttons (centred under it, and allowed to run a little wider).
struct TransportControls: View {
    let model: AudiobookPlayer
    var focus: FocusState<PlayerFocus?>.Binding
    @Binding var scrubTime: Double?
    let barWidth: CGFloat
    let onShowBookmarks: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            ScrubBar(elapsed: model.elapsed, range: model.chapter.timeRange, scrubTime: $scrubTime, onCommit: model.seek)
                .frame(width: barWidth)
                .focused(focus, equals: .scrubber)
                .accessibilityIdentifier("scrubber")

            HStack(spacing: 14) {
                Button("Bookmarks", systemImage: "bookmark", action: onShowBookmarks)
                    .focused(focus, equals: .bookmarks)
                    .accessibilityIdentifier("bookmarks")

                ChapterMenu(model: model)
                    .focused(focus, equals: .chapters)
                    .accessibilityIdentifier("chapters")

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
            .fixedSize()
            .disabled(scrubTime != nil)
        }
    }
}

private struct ChapterMenu: View {
    let model: AudiobookPlayer

    var body: some View {
        Menu {
            Picker("Chapter", selection: Binding(get: { model.chapterIndex }, set: model.play(chapter:))) {
                ForEach(model.chapters.indices, id: \.self) { index in
                    Text(model.chapters[index].title).tag(index)
                }
            }
        } label: {
            Label("Chapters", systemImage: "list.bullet")
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
                .lineLimit(1)
        }
        .buttonBorderShape(.capsule)
    }

    /// "0.5×", "1×", "1.25×"
    private static func label(for rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

/// Progress through the current chapter. Click to start scrubbing, left/right to move 10 seconds,
/// click again to jump there. Back cancels (handled by `PlayerScreen`).
struct ScrubBar: View {
    /// Position in the book.
    let elapsed: Double
    /// The part of the book the bar spans.
    let range: ClosedRange<Double>
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
        .buttonStyle(ScrubBarStyle(
            time: max(0, (scrubTime ?? elapsed) - range.lowerBound),
            duration: range.upperBound - range.lowerBound,
            isScrubbing: scrubTime != nil
        ))
        .onMoveCommand { direction in
            guard let current = scrubTime else { return }
            switch direction {
            case .left: scrubTime = max(range.lowerBound, current - Self.step)
            case .right: scrubTime = min(range.upperBound, current + Self.step)
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
