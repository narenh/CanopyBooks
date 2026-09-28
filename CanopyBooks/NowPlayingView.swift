import CoreImage
import SwiftUI

/// Full-screen overlay laid out like Apple Music's tvOS lyrics screen
/// (proportions measured from a 1920×1080 reference).
struct NowPlayingView: View {
    let model: AudiobookPlayer

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ArtworkBackground(backdrop: model.backdrop)

                ArtworkColumn(model: model, artworkBox: CGSize(width: size.width * 0.273, height: size.height * 0.52))
                    .position(x: size.width * 0.213, y: size.height * 0.47)

                LyricsView(sentences: model.sentences, activeIndex: model.activeIndex, fontSize: 64)
                    .frame(width: size.width * 0.507, height: size.height)
                    .offset(x: size.width * 0.437)
            }
        }
        .ignoresSafeArea()
    }
}

private struct ArtworkColumn: View {
    let model: AudiobookPlayer
    let artworkBox: CGSize

    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: model.cover)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .frame(width: artworkBox.width, height: artworkBox.height)
                .padding(.bottom, 30)

            HStack(spacing: 10) {
                PlayingIndicator(isPlaying: model.isPlaying)
                Text(model.chapter.title)
            }
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white)

            Text("\(model.chapter.bookTitle) · \(model.chapter.author)")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .blendMode(.plusLighter)
        }
        .lineLimit(1)
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

/// Slowly swirling, pre-blurred artwork, standing in for Apple Music's animated colour field.
private struct ArtworkBackground: View {
    let backdrop: UIImage
    @State private var rotating = false

    var body: some View {
        GeometryReader { geo in
            let side = hypot(geo.size.width, geo.size.height)
            ZStack {
                Color.black
                layer(side: side * 1.2, degrees: rotating ? 360 : 0)
                layer(side: side * 0.9, degrees: rotating ? -360 : 0)
                    .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 0, endRadius: side * 0.45))
                    .opacity(0.7)
                Color.black.opacity(0.15)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) { rotating = true }
        }
    }

    private func layer(side: CGFloat, degrees: Double) -> some View {
        Image(uiImage: backdrop)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .rotationEffect(.degrees(degrees))
    }
}

extension UIImage {
    /// A tiny, blurred, saturated copy of the image. Scaled up it reads as a soft colour field,
    /// so the background never needs a live full-screen blur.
    func blurredBackdrop() -> UIImage? {
        guard let cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let scale = 96 / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let output = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 10)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6])
            .cropped(to: small.extent)
        return CIContext().createCGImage(output, from: output.extent).map(UIImage.init(cgImage:))
    }
}
