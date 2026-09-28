import SwiftUI

/// Apple Music–style synced text. The sentence at `displayIndex` sits at a fixed anchor near the
/// top; lines glide into place with a slight top-to-bottom stagger. Every sentence is a button,
/// so the remote can move through them and click to jump.
struct LyricsView: View {
    static let fontSize: CGFloat = 64

    let sentences: [Sentence]
    /// The sentence being read (drawn at full brightness).
    let activeIndex: Int?
    /// The sentence to position at the anchor: the one being read, browsed to, or scrubbed to.
    let displayIndex: Int
    let isBrowsing: Bool
    var focus: FocusState<PlayerFocus?>.Binding
    let onSelect: (Int) -> Void

    @State private var heights: [CGFloat]
    @State private var containerHeight: CGFloat = 1080
    @State private var previousDisplayIndex = 0

    init(
        sentences: [Sentence], activeIndex: Int?, displayIndex: Int, isBrowsing: Bool,
        focus: FocusState<PlayerFocus?>.Binding, onSelect: @escaping (Int) -> Void
    ) {
        self.sentences = sentences
        self.activeIndex = activeIndex
        self.displayIndex = displayIndex
        self.isBrowsing = isBrowsing
        self.focus = focus
        self.onSelect = onSelect
        _heights = State(initialValue: Array(repeating: Self.fontSize * 1.2, count: sentences.count))
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
            ForEach(sentences.indices, id: \.self) { i in
                Button(sentences[i].text) { onSelect(i) }
                    .buttonStyle(LyricLineStyle(isActive: i == activeIndex, showsFocus: isBrowsing))
                    .focused(focus, equals: .sentence(i))
                    .accessibilityIdentifier("sentence-\(i)")
                    .padding(.bottom, gap(after: i))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[i] = $0 }
                    // Every line shares the same shift; only the timing differs per line.
                    .offset(y: shift)
                    .animation(animation(for: i), value: displayIndex)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Dimmed lines pick up the background colour, like Apple Music's vibrant text.
        .blendMode(.plusLighter)
    }

    private func gap(after i: Int) -> CGFloat {
        guard i + 1 < sentences.count else { return 0 }
        return sentences[i + 1].para == sentences[i].para ? sentenceGap : paragraphGap
    }

    private func top(of i: Int) -> CGFloat {
        heights[..<i].reduce(0, +)
    }

    /// Where the anchored sentence's top edge sits. Long sentences are pulled up so they stay on screen.
    private func anchor(for i: Int) -> CGFloat {
        let textHeight = heights[i] - gap(after: i)
        return max(containerHeight * 0.08, min(containerHeight * 0.3, containerHeight * 0.92 - textHeight))
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

private struct LyricLineStyle: ButtonStyle {
    let isActive: Bool
    let showsFocus: Bool

    func makeBody(configuration: Configuration) -> some View {
        LyricLine(configuration: configuration, isActive: isActive, showsFocus: showsFocus)
    }
}

private struct LyricLine: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool
    let showsFocus: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        // Following playback, focus rides along on the active line and isn't drawn.
        let highlighted = showsFocus && isFocused
        configuration.label
            .font(.system(size: LyricsView.fontSize, weight: .bold))
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
            .opacity(isActive || highlighted ? 1 : 0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(highlighted ? 0.12 : 0))
                    .padding(.horizontal, -28)
                    .padding(.vertical, -14)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.2), value: highlighted)
            .animation(.easeOut(duration: 0.3), value: isActive)
    }
}
