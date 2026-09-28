import SwiftUI

/// Everything on screen that can hold focus. Sentences are focusable so the Siri Remote can
/// move through the text and jump to a line.
enum PlayerFocus: Hashable {
    case scrubber, chapters, skipBack, playPause, skipForward, speed
    case sentence(Int)

    var isSentence: Bool {
        if case .sentence = self { true } else { false }
    }
}

/// Apple Music–style lyrics screen: artwork and transport on the left, synced text on the right.
/// Column positions are measured from Apple Music on a 1920×1080 screen.
struct PlayerScreen: View {
    let model: AudiobookPlayer

    @FocusState private var focus: PlayerFocus?
    /// True while the user is moving through sentences instead of following playback.
    @State private var isBrowsing = false
    /// Bumped by remote input in the text column; restarts the idle timer.
    @State private var textActivity = 0
    /// Non-nil while the remote is scrubbing the progress bar.
    @State private var scrubTime: Double?

    private var focusedSentence: Int? {
        if case .sentence(let index) = focus { index } else { nil }
    }

    /// The sentence the text column is positioned on, kept within the chapter on screen.
    private var displayIndex: Int {
        let index = if let scrubTime {
            model.sentences.index(at: scrubTime) ?? 0
        } else if isBrowsing, let focusedSentence {
            focusedSentence
        } else {
            model.activeIndex ?? 0
        }
        let chapter = model.chapter.sentences
        return min(max(index, chapter.lowerBound), chapter.upperBound - 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            ArtworkColumn(model: model, focus: $focus, scrubTime: $scrubTime)
                .frame(width: 839)
                .focusSection()
            // One chapter at a time keeps the text column to a few hundred lines.
            LyricsView(
                sentences: model.sentences,
                range: model.chapter.sentences,
                activeIndex: model.activeIndex,
                displayIndex: displayIndex,
                focus: $focus,
                onSelect: select,
                playback: { (model.elapsed, model.rate) }
            )
            .id(model.chapterIndex)
            .transition(.opacity)
            .frame(width: 973)
            .focusSection()
            .disabled(scrubTime != nil)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: model.chapterIndex)
        .background { ArtworkBackground(image: model.cover) }
        .ignoresSafeArea()
        .defaultFocus($focus, .playPause)
        .onPlayPauseCommand(perform: model.togglePlayPause)
        .onExitCommand(perform: exitAction)
        .onChange(of: focus, focusChanged)
        .onChange(of: model.activeIndex) {
            // Following playback: keep focus on the sentence being read.
            if !isBrowsing, focus?.isSentence == true {
                focus = .sentence(model.activeIndex ?? 0)
            }
        }
        .task(id: textActivity) {
            // Idle in the text: focus goes back to play/pause so the highlight never lingers.
            // Browsing gets longer, to leave time to read.
            guard focus?.isSentence == true else { return }
            try? await Task.sleep(for: .seconds(isBrowsing ? 12 : 6))
            if !Task.isCancelled, focus?.isSentence == true { leaveText() }
        }
    }

    private func focusChanged(from old: PlayerFocus?, to new: PlayerFocus?) {
        let fromText = old?.isSentence == true
        guard case .sentence(let index) = new else {
            isBrowsing = false
            if fromText, new == .scrubber {
                // Left from the text: the bar is marginally nearer, but focus should reach the
                // end of the button row first.
                focus = .speed
            } else if fromText, new == nil {
                // The focused line went away (a new chapter started).
                focus = .playPause
            }
            return
        }
        let active = model.activeIndex ?? 0
        if !fromText {
            // Arriving from the controls lands on the sentence being read, not the nearest one.
            if index != active { focus = .sentence(active) }
            textActivity += 1
        } else if isBrowsing || index != active {
            // Moving up or down. (Focus following playback from line to line isn't user input.)
            isBrowsing = true
            textActivity += 1
        }
    }

    private func select(_ index: Int) {
        isBrowsing = false
        textActivity += 1
        model.play(sentence: index)
    }

    private func leaveText() {
        isBrowsing = false
        focus = .playPause
    }

    /// Back on the remote cancels scrubbing, then returns from the text to play/pause; from the
    /// controls it falls through to the system and leaves the app.
    private var exitAction: (() -> Void)? {
        if scrubTime != nil { return { scrubTime = nil } }
        if focus?.isSentence == true { return leaveText }
        return nil
    }
}

private struct ArtworkColumn: View {
    let model: AudiobookPlayer
    var focus: FocusState<PlayerFocus?>.Binding
    @Binding var scrubTime: Double?

    private let artworkHeight: CGFloat = 540

    private var artworkWidth: CGFloat {
        let size = model.cover.size
        return size.height > 0 ? artworkHeight * size.width / size.height : artworkHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: model.cover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .frame(width: artworkWidth, height: artworkHeight)

            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    PlayingIndicator(isPlaying: model.isPlaying)
                    Text(model.chapter.title)
                        .contentTransition(.opacity)
                }
                .foregroundStyle(.white)
                .font(.system(size: 28, weight: .semibold))

                Text("\(model.book.title) · \(model.book.author)")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .blendMode(.plusLighter)
            }
            .lineLimit(1)
            .padding(.top, 30)

            TransportControls(model: model, focus: focus, scrubTime: $scrubTime)
                .frame(width: artworkWidth)
                .padding(.top, 36)
        }
    }
}

/// The little animated bars Apple Music shows next to the playing track.
private struct PlayingIndicator: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { bar in
                    let level = isPlaying ? 0.3 + 0.7 * abs(sin(t * (3.1 + Double(bar) * 1.3) + Double(bar))) : 0.3
                    Capsule().frame(width: 3.5, height: 18 * level)
                }
            }
            .frame(height: 18, alignment: .bottom)
        }
    }
}
