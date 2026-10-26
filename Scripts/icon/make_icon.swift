// Draws the Kikimi app icon: the musical repeat sign (𝄆), drawn larger than the icon shape so it fills it edge to
// edge (the shape clips it), and zig-zagged sideways, in dark green on the app's lime.
//
// Run from the repository root (needs Xcode):
//   swiftc -O -swift-version 5 Scripts/icon/make_icon.swift -o /tmp/make_icon && /tmp/make_icon /tmp/icon-out
// It writes final.png (1024 px). Then make the other sizes into the asset catalog:
//   for n in 16 32 64 128 256 512 1024; do sips -z $n $n /tmp/icon-out/final.png --out Kikimi/Assets.xcassets/AppIcon.appiconset/icon_$n.png; done
//
// The look is set at the bottom: `glyphWidth` (how wide the sign is before warping), `amplitude` (how far rows slide
// sideways) and `stretch` (how much they widen and narrow). The zig-zag's period is in `zigzag`.

import AppKit
import SwiftUI

// --- tunables
let ss = 2                                  // supersample: draw and warp at 2x, then reduce
let W = 1024 * ss
let squircle = 824.0 * Double(ss)           // the icon shape's size, in supersampled pixels
let ink = (r: UInt8(0x15), g: UInt8(0x3A), b: UInt8(0x0B))
let lime = Color(.sRGB, red: 0x66/255, green: 0xCC/255, blue: 0x0A/255)

/// The repeat sign, drawn flat: a thick bar, a thin bar and two dots, spanning `width` and centred.
func drawGlyph(width: Double) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: W * W * 4)
    let unit = width / 100                  // the glyph is laid out in a 100-wide box
    let cx = Double(W) / 2, cy = Double(W) / 2
    func fill(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, ellipse: Bool = false) {
        let xs = Int(max(0, cx + x0 * unit)), xe = Int(min(Double(W - 1), cx + x1 * unit))
        let ys = Int(max(0, cy + y0 * unit)), ye = Int(min(Double(W - 1), cy + y1 * unit))
        let ex = (cx + (x0 + x1) / 2 * unit), ey = (cy + (y0 + y1) / 2 * unit)
        let rx = (x1 - x0) / 2 * unit, ry = (y1 - y0) / 2 * unit
        for y in ys...ye { for x in xs...xe {
            if ellipse { let dx = (Double(x) - ex) / rx, dy = (Double(y) - ey) / ry; if dx * dx + dy * dy > 1 { continue } }
            let i = (y * W + x) * 4; px[i] = ink.r; px[i + 1] = ink.g; px[i + 2] = ink.b; px[i + 3] = 255
        } }
    }
    // Layout across the whole 100-wide box (x from -50 to 50): a thick bar, a thin bar, a gap, then the two dots.
    // The bars run past the top and bottom of the icon shape, which clips them.
    let barTop = -60.0, barBottom = 60.0
    fill(-50, -20, barTop, barBottom)       // thick bar, 30 wide
    fill(-10, 3, barTop, barBottom)         // thin bar, 13 wide
    fill(21, 50, -27 - 17, -27 + 17, ellipse: true)    // upper dot, 29 across
    fill(21, 50, 27 - 17, 27 + 17, ellipse: true)      // lower dot
    return px
}

/// A triangle wave: -1...1, with straight runs and sharp turns, `period` long.
func zigzag(_ y: Double, period: Double) -> Double { asin(sin(y / period * 2 * Double.pi)) * 2 / Double.pi }

/// Zig-zag: each row slides sideways by a big and a small triangle wave, and stretches a little, so edges run
/// diagonally and turn sharply.
func melt(_ src: [UInt8], amplitude: Double, stretch: Double) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: W * W * 4)
    let cx = Double(W) / 2
    let h = Double(W)
    for y in 0..<W {
        let t = Double(y) / h * 2 * Double.pi
        let yy = Double(y) + 40 * Double(ss)
        let shift = amplitude * (0.75 * zigzag(yy, period: 230 * Double(ss)) + 0.25 * zigzag(yy, period: 86 * Double(ss)))
        let scale = 1 + stretch * (0.7 * sin(t * 2.1 + 1.3) + 0.3 * sin(t * 5.3))
        for x in 0..<W {
            let sx = cx + (Double(x) - cx - shift) / scale
            if sx < 0 || sx >= Double(W - 1) { continue }
            let x0 = Int(sx), f = sx - Double(x0)
            let a = (y * W + x0) * 4, b = a + 4
            let o = (y * W + x) * 4
            for c in 0..<4 { out[o + c] = UInt8(Double(src[a + c]) * (1 - f) + Double(src[b + c]) * f) }
        }
    }
    return out
}

func bounds(_ px: [UInt8]) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
    var minX = W, maxX = 0, minY = W, maxY = 0
    for y in 0..<W { for x in 0..<W where px[(y * W + x) * 4 + 3] > 128 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
    return (minX, maxX, minY, maxY)
}

/// Slides the whole picture sideways so its ink is centred (the warp pulls it to one side).
func recentred(_ px: [UInt8]) -> [UInt8] {
    let b = bounds(px)
    let dx = W / 2 - (b.minX + b.maxX) / 2
    if dx == 0 { return px }
    var out = [UInt8](repeating: 0, count: px.count)
    for y in 0..<W { for x in 0..<W {
        let nx = x + dx
        if nx < 0 || nx >= W { continue }
        let a = (y * W + x) * 4, o = (y * W + nx) * 4
        for c in 0..<4 { out[o + c] = px[a + c] }
    } }
    return out
}

func image(from px: [UInt8]) -> NSImage {
    var data = px
    let ctx = data.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: W, height: W, bitsPerComponent: 8, bytesPerRow: W * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! }
    // The bytes above are straight (not premultiplied) colour with alpha; fully opaque or fully clear except at the
    // warp's soft edges, which is close enough once reduced.
    return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 1024, height: 1024))
}

struct Icon: View {
    let glyph: NSImage
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous).fill(lime).frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 16, y: 12)
            Image(nsImage: glyph).resizable().frame(width: 1024, height: 1024)
                .mask(RoundedRectangle(cornerRadius: 185, style: .continuous).frame(width: 824, height: 824))
        }.frame(width: 1024, height: 1024)
    }
}

@MainActor func run(name: String, glyphWidth: Double, amplitude: Double, stretch: Double, out: String) {
    let flat = drawGlyph(width: glyphWidth)
    let warped = recentred(melt(flat, amplitude: amplitude, stretch: stretch))
    let b = bounds(warped)
    let span = Double(b.maxX - b.minX) / Double(ss), shapeEdge = (1024 - 824) / 2.0
    print(String(format: "%@: glyph spans x %.0f...%.0f of 1024 (%.0f wide; the icon shape is 100...924)", name, Double(b.minX) / Double(ss), Double(b.maxX) / Double(ss), span))
    _ = shapeEdge
    let r = ImageRenderer(content: Icon(glyph: image(from: warped))); r.scale = 1
    if let i = r.nsImage, let t = i.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: out + "/\(name).png"))
    }
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let out = CommandLine.arguments[1]
    run(name: "final", glyphWidth: 820.0 * Double(ss), amplitude: 52 * Double(ss), stretch: 0.06, out: out)
}
