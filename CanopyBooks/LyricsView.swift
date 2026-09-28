import SwiftUI

/// Apple Music–style synced text. The sentence at `displayIndex` sits at a fixed anchor near the
/// top; lines glide into place with a slight top-to-bottom stagger. Every sentence is a button,
/// so the remote can move through them and click to jump; the focused one gets a highlight.
/// Press and hold a sentence to bookmark it.
struct LyricsView: View {
    static let fontSize: CGFloat = 64

    let sentences: [Sentence]
    /// The sentences shown (one chapter); indices below are into `sentences`.
    let range: Range<Int>
    /// The sentence being read (drawn at full brightness).
    let activeIndex: Int?
    /// The sentence to position at the anchor: the one being read, browsed to, or scrubbed to.
    let displayIndex: Int
    let bookmarked: Set<Int>
    var focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (Int) -> Void
    let onToggleBookmark: (Int) -> Void
    /// Playback position (whole seconds) and speed. Only read while a sentence taller than the
    /// screen is being read, and only by `ReadingScroll`, so the lines don't redraw every tick.
    let playback: () -> (time: Double, rate: Float)

    @State private var heights: [CGFloat]
    @State private var containerHeight: CGFloat = 1080
    @State private var previousDisplayIndex = 0

    init(
        sentences: [Sentence], range: Range<Int>, activeIndex: Int?, displayIndex: Int, bookmarked: Set<Int>,
        focus: FocusState<PlayerFocus?>.Binding, onSelect: @escaping (Int) -> Void,
        onToggleBookmark: @escaping (Int) -> Void,
        playback: @escaping () -> (time: Double, rate: Float)
    ) {
        self.sentences = sentences
        self.range = range
        self.activeIndex = activeIndex
        self.displayIndex = displayIndex
        self.bookmarked = bookmarked
        self.focus = focus
        self.onSelect = onSelect
        self.onToggleBookmark = onToggleBookmark
        self.playback = playback
        _heights = State(initialValue: Array(repeating: Self.fontSize * 1.2, count: range.count))
        _previousDisplayIndex = State(initialValue: displayIndex)
    }

    private var sentenceGap: CGFloat { Self.fontSize * 1.1 }
    private var paragraphGap: CGFloat { Self.fontSize * 2 }

    var body: some View {
        let shift = anchor(for: displayIndex) - top(of: displayIndex)
        // The column's own size comes from the parent; the (very tall) text hangs off its top.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
            .overlay(alignment: .top) { lines(shift: shift) }
            .onChange(of: displayIndex) { previousDisplayIndex = displayIndex }
    }

    private func lines(shift: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(range, id: \.self) { i in
                Button(sentences[i].text) { onSelect(i) }
                    .buttonStyle(LyricLineStyle(isActive: i == activeIndex, isBookmarked: bookmarked.contains(i)))
                    .contextMenu {
                        if bookmarked.contains(i) {
                            Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) { onToggleBookmark(i) }
                        } else {
                            Button("Add Bookmark", systemImage: "bookmark") { onToggleBookmark(i) }
                        }
                    }
                    .focused(focus, equals: .sentence(i))
                    .accessibilityIdentifier("sentence-\(i)")
                    .accessibilityValue(bookmarked.contains(i) ? "Bookmarked" : "")
                    .padding(.bottom, gap(after: i))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[i - range.lowerBound] = $0 }
                    // Every line shares the same shift; only the timing differs per line.
                    .offset(y: shift)
                    .animation(animation(for: i), value: displayIndex)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(ReadingScroll(
            sentence: displayIndex,
            timing: displayIndex == activeIndex ? sentences[displayIndex] : nil,
            overflow: overflow(of: displayIndex),
            playback: playback
        ))
        // Dimmed lines pick up the background colour, like Apple Music's vibrant text.
        .blendMode(.plusLighter)
    }

    private func gap(after i: Int) -> CGFloat {
        guard i + 1 < range.upperBound else { return 0 }
        return sentences[i + 1].para == sentences[i].para ? sentenceGap : paragraphGap
    }

    private func top(of i: Int) -> CGFloat {
        heights[..<(i - range.lowerBound)].reduce(0, +)
    }

    private func textHeight(of i: Int) -> CGFloat {
        heights[i - range.lowerBound] - gap(after: i)
    }

    /// Where the anchored sentence's top edge sits. Long sentences are pulled up so more fits.
    private func anchor(for i: Int) -> CGFloat {
        max(containerHeight * 0.08, min(containerHeight * 0.3, containerHeight * 0.92 - textHeight(of: i)))
    }

    /// How much of a sentence hangs below the screen when its top is at the anchor.
    private func overflow(of i: Int) -> CGFloat {
        max(0, anchor(for: i) + textHeight(of: i) - containerHeight * 0.92)
    }

    private func animation(for i: Int) -> Animation? {
        let step = displayIndex - previousDisplayIndex
        let glide = Animation.spring(duration: 0.7, bounce: 0.1)
        // Seeks snap; moving back glides as one block (a stagger would overlap lines).
        if abs(step) > 3 { return nil }
        guard step > 0 else { return glide }
        // Lines above the new sentence move first; each line below trails its neighbour.
        let order = min(max(0, i - displayIndex + 1), 12)
        return glide.delay(Double(order) * 0.04)
    }
}

/// Scrolls a sentence that's taller than the screen while it's read: its top starts at the
/// anchor and its last line reaches the bottom as the sentence ends. There are no word timings,
/// so this assumes an even pace through the sentence.
private struct ReadingScroll: ViewModifier {
    let sentence: Int
    /// The sentence's timing when it's the one being read; nil while browsing to another.
    let timing: Sentence?
    let overflow: CGFloat
    let playback: () -> (time: Double, rate: Float)

    func body(content: Content) -> some View {
        var progress = 0.0
        var tick = 0.0
        var rate: Float = 1
        if overflow > 0, let timing {
            (tick, rate) = playback()
            // The time is whole seconds; aim for where playback will be at the next tick.
            progress = min(1, max(0, (tick + 1 - timing.start) / (timing.end - timing.start)))
        }
        return content
            .offset(y: -overflow * progress)
            .animation(.spring(duration: 0.7, bounce: 0.1), value: sentence)
            .animation(.linear(duration: 1 / Double(max(rate, 0.25))), value: tick)
    }
}

private struct LyricLineStyle: ButtonStyle {
    let isActive: Bool
    let isBookmarked: Bool

    func makeBody(configuration: Configuration) -> some View {
        LyricLine(configuration: configuration, isActive: isActive, isBookmarked: isBookmarked)
    }
}

private struct LyricLine: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool
    let isBookmarked: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.system(size: LyricsView.fontSize, weight: .bold))
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
            .opacity(isActive || isFocused ? 1 : 0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                // In the margin, level with the first line.
                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white.opacity(isActive || isFocused ? 0.9 : 0.4))
                        .offset(x: -64, y: 22)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(isFocused ? 0.12 : 0))
                    .padding(.horizontal, -28)
                    .padding(.vertical, -14)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.2), value: isFocused)
            .animation(.easeOut(duration: 0.3), value: isActive)
    }
}
