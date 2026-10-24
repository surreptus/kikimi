import AppKit
import SwiftUI

/// A very faint grain laid over the window colour behind the sidebar and around the card, like paper. The tile is drawn once in code (a fixed pattern, so it
/// never changes between launches), then repeated. It only nudges the colour a little, so text keeps its contrast,
/// and it goes away when the Mac's Increase Contrast setting is on.
struct NoiseOverlay: View {
    /// How strong the grain is. At 0.18 the background varies by about 8 of 255 brightness levels: a visible, soft grain.
    var strength: Double = 0.18
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast == .standard {
            Image(nsImage: NoiseTile.image)
                .resizable(resizingMode: .tile)
                .blendMode(.softLight)
                .opacity(strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The repeating tile: grey pixels of random brightness, 256 pixels square, drawn at half size so each grain is a
/// single pixel on a Retina display.
enum NoiseTile {
    static let pixels = 256

    static let image: NSImage = {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15   // fixed seed
        for y in 0..<pixels {
            for x in 0..<pixels {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let value = UInt8(truncatingIfNeeded: state >> 33)
                rep.setColor(
                    NSColor(deviceRed: CGFloat(value) / 255, green: CGFloat(value) / 255, blue: CGFloat(value) / 255, alpha: 1),
                    atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: pixels / 2, height: pixels / 2))
        image.addRepresentation(rep)
        return image
    }()
}
