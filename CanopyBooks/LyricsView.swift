import SwiftUI

/// Apple Music–style synced text: the active sentence sits at a fixed anchor near the top,
/// everything else is dimmed, and lines glide into place with a slight top-to-bottom stagger.
struct LyricsView: View {
    let sentences: [Sentence]
    let activeIndex: Int?
    let fontSize: CGFloat

    @State private var heights: [CGFloat]
    @State private var previousFocus = 0

    init(sentences: [Sentence], activeIndex: Int?, fontSize: CGFloat) {
        self.sentences = sentences
        self.activeIndex = activeIndex
        self.fontSize = fontSize
        _heights = State(initialValue: Array(repeating: fontSize * 1.2, count: sentences.count))
    }

    private var sentenceGap: CGFloat { fontSize * 1.1 }
    private var paragraphGap: CGFloat { fontSize * 2 }

    var body: some View {
        GeometryReader { geo in
            let focus = activeIndex ?? 0
            let shift = anchor(for: focus, height: geo.size.height) - top(of: focus)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sentences.indices, id: \.self) { i in
                    LyricLine(text: sentences[i].text, isActive: i == activeIndex, fontSize: fontSize)
                        .padding(.bottom, gap(after: i))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[i] = $0 }
                        // Every line shares the same shift; only the timing differs per line.
                        .offset(y: shift)
                        .animation(animation(for: i, focus: focus), value: activeIndex)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            // Dimmed lines pick up the background colour, like Apple Music's vibrant text.
            .blendMode(.plusLighter)
        }
        .onChange(of: activeIndex) { previousFocus = activeIndex ?? 0 }
    }

    private func gap(after i: Int) -> CGFloat {
        guard i + 1 < sentences.count else { return 0 }
        return sentences[i + 1].para == sentences[i].para ? sentenceGap : paragraphGap
    }

    private func top(of i: Int) -> CGFloat {
        heights[..<i].reduce(0, +)
    }

    /// Where the active sentence's top edge sits. Long sentences are pulled up so they stay on screen.
    private func anchor(for i: Int, height: CGFloat) -> CGFloat {
        let textHeight = heights[i] - gap(after: i)
        return max(height * 0.08, min(height * 0.3, height * 0.92 - textHeight))
    }

    private func animation(for i: Int, focus: Int) -> Animation? {
        let step = focus - previousFocus
        let glide = Animation.spring(duration: 0.7, bounce: 0.1)
        // Seeks snap; small backward skips move as one block (a stagger would overlap lines).
        if abs(step) > 3 { return nil }
        guard step > 0 else { return glide }
        // Lines above the new sentence move first; each line below trails its neighbour.
        let order = min(max(0, i - focus + 1), 12)
        return glide.delay(Double(order) * 0.04)
    }
}

private struct LyricLine: View {
    let text: String
    let isActive: Bool
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .opacity(isActive ? 1 : 0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
