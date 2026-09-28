import CoreImage
import SwiftUI

/// A slowly drifting mesh gradient coloured from a 4×4 sampling of the artwork,
/// standing in for Apple Music's animated backdrop.
struct ArtworkBackground: View {
    let image: UIImage
    @State private var colors: [Color] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            if colors.count == 16 {
                MeshGradient(
                    width: 4, height: 4,
                    points: Self.points(at: context.date.timeIntervalSinceReferenceDate),
                    colors: colors
                )
            } else {
                Color.black
            }
        }
        .overlay(Color.black.opacity(0.2))
        .ignoresSafeArea()
        .task { colors = image.meshPalette() }
    }

    /// A 4×4 grid whose inner points wander; edge points only slide along their edge.
    private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        (0..<4).flatMap { row in
            (0..<4).map { column in
                let phase = Double(row * 4 + column)
                var x = Float(column) / 3
                var y = Float(row) / 3
                if column != 0, column != 3 { x += Float(0.08 * sin(time * 0.31 + phase * 1.7)) }
                if row != 0, row != 3 { y += Float(0.08 * cos(time * 0.27 + phase * 2.3)) }
                return SIMD2(x, y)
            }
        }
    }
}

extension UIImage {
    /// Sixteen colours, row by row from the top left, sampled from a blurred and saturated copy.
    func meshPalette() -> [Color] {
        guard let cgImage else { return [] }
        let side = 64
        let input = CIImage(cgImage: cgImage)
        let small = input.transformed(by: CGAffineTransform(
            scaleX: CGFloat(side) / input.extent.width, y: CGFloat(side) / input.extent.height
        ))
        let soft = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 8)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5])
            .cropped(to: small.extent)
        guard let blurred = CIContext().createCGImage(soft, from: soft.extent),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(blurred, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        // Bitmap row 0 is the top of the image; sample the centre of each grid cell.
        let cell = side / 4
        return (0..<4).flatMap { row in
            (0..<4).map { column in
                let offset = ((row * cell + cell / 2) * side + column * cell + cell / 2) * 4
                return Color(
                    .sRGB,
                    red: Double(pixels[offset]) / 255,
                    green: Double(pixels[offset + 1]) / 255,
                    blue: Double(pixels[offset + 2]) / 255
                )
            }
        }
    }
}
