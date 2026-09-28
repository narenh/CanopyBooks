import SwiftUI

/// Everything on screen that can hold focus. Sentences are focusable so the Siri Remote can
/// move through the text and jump to a line.
enum PlayerFocus: Hashable {
    case scrubber, skipBack, playPause, skipForward, speed
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
    @State private var browseActivity = 0
    /// Non-nil while the remote is scrubbing the progress bar.
    @State private var scrubTime: Double?

    private var focusedSentence: Int? {
        if case .sentence(let index) = focus { index } else { nil }
    }

    private var controlsFocused: Bool {
        focus.map { !$0.isSentence } ?? false
    }

    /// The sentence the text column is positioned on.
    private var displayIndex: Int {
        if let scrubTime { return model.sentences.index(at: scrubTime) ?? 0 }
        if isBrowsing, let focusedSentence { return focusedSentence }
        return model.activeIndex ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ArtworkColumn(model: model, focus: $focus, scrubTime: $scrubTime)
                .frame(width: 839)
                .focusSection()
            LyricsView(
                sentences: model.sentences,
                activeIndex: model.activeIndex,
                displayIndex: displayIndex,
                isBrowsing: isBrowsing,
                focus: $focus,
                onSelect: select
            )
            .frame(width: 973)
            .focusSection()
            .disabled(scrubTime != nil)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ArtworkBackground(image: model.cover) }
        .ignoresSafeArea()
        .defaultFocus($focus, .sentence(0))
        .onPlayPauseCommand(perform: model.togglePlayPause)
        .onExitCommand(perform: exitAction)
        .onChange(of: focus, focusChanged)
        .onChange(of: model.activeIndex) {
            // Following playback: keep focus on the sentence being read.
            if !isBrowsing, focus?.isSentence == true {
                focus = .sentence(model.activeIndex ?? 0)
            }
        }
        .task(id: browseActivity) {
            // Drift back to following playback once the remote has been idle for a while.
            guard isBrowsing else { return }
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { stopBrowsing() }
        }
    }

    private func focusChanged(from old: PlayerFocus?, to new: PlayerFocus?) {
        guard case .sentence(let index) = new else {
            isBrowsing = false
            return
        }
        let active = model.activeIndex ?? 0
        if old?.isSentence == true {
            if index != active { isBrowsing = true }
            if isBrowsing { browseActivity += 1 }
        } else if index != active {
            // Arriving from the controls lands on the sentence being read, not the nearest one.
            focus = .sentence(active)
        }
    }

    /// Clicking a sentence you've moved to jumps there; clicking while following playback
    /// plays/pauses, like the system player.
    private func select(_ index: Int) {
        if isBrowsing {
            isBrowsing = false
            model.play(sentence: index)
        } else {
            model.togglePlayPause()
        }
    }

    private func stopBrowsing() {
        isBrowsing = false
        if focus?.isSentence == true {
            focus = .sentence(model.activeIndex ?? 0)
        }
    }

    /// Back on the remote unwinds scrubbing, then browsing, then the controls; after that it
    /// falls through to the system and leaves the app.
    private var exitAction: (() -> Void)? {
        if scrubTime != nil { return { scrubTime = nil } }
        if isBrowsing { return stopBrowsing }
        if controlsFocused { return { focus = .sentence(model.activeIndex ?? 0) } }
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
                }
                .foregroundStyle(.white)
                .font(.system(size: 28, weight: .semibold))

                Text("\(model.chapter.bookTitle) · \(model.chapter.author)")
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
