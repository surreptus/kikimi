// Draws the Kikimi app icon: a single asanoha (hemp leaf) star, a traditional Japanese pattern of growth, in white
// line on dark green, and a light version (dark line on pale green) the app shows in the Dock in Light appearance.
//
// Run from the repository root (needs Xcode):
//   swiftc -O -swift-version 5 Scripts/icon/make_icon.swift -o /tmp/make_icon && mkdir -p /tmp/icon-out && /tmp/make_icon /tmp/icon-out
// It writes final.png (dark) and light.png (1024 px). Then make the sizes for the asset catalog:
//   for n in 16 32 64 128 256 512 1024; do sips -z $n $n /tmp/icon-out/final.png --out Kikimi/Assets.xcassets/AppIcon.appiconset/icon_$n.png; done
//   cp /tmp/icon-out/light.png Kikimi/Assets.xcassets/IconLight.imageset/icon_light.png
//
// The look is set by `radius` (how large the star is) and `lineWidth`. The line is heavier than a drawing would
// have, so it still reads at 16 and 32 px.

import AppKit
import SwiftUI

let green = Color(red: 0x0B / 255, green: 0x2E / 255, blue: 0x1C / 255)
let pale = Color(red: 0xEE / 255, green: 0xF4 / 255, blue: 0xE7 / 255)
let radius: CGFloat = 340          // centre to corner of the hexagon, on a 1024 canvas
let lineWidth: CGFloat = 24
let shape = CGRect(x: 100, y: 100, width: 824, height: 824)   // the icon shape's size and place
let cornerSize: CGFloat = 185

/// Six triangles round the centre, each divided into thirds from its own centre: the asanoha star.
func star(in size: CGSize) -> Path {
    let c = CGPoint(x: size.width / 2, y: size.height / 2)
    let corners = (0..<6).map { i -> CGPoint in
        let a = CGFloat(i) * .pi / 3 - .pi / 2
        return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
    }
    var p = Path()
    for i in 0..<6 {
        let a = corners[i], b = corners[(i + 1) % 6]
        let m = CGPoint(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3)
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: a)
        for v in [a, b, c] { p.move(to: m); p.addLine(to: v) }
    }
    return p
}

struct Icon: View {
    var isLight = false
    var body: some View {
        ZStack {
            Path(roundedRect: shape, cornerRadius: cornerSize, style: .continuous)
                .fill(isLight ? pale : green)
                .shadow(color: .black.opacity(0.28), radius: 16, y: 12)
            Canvas { ctx, size in
                ctx.stroke(star(in: size), with: .color(isLight ? green : .white),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    for (name, light) in [("final", false), ("light", true)] {
        let r = ImageRenderer(content: Icon(isLight: light)); r.scale = 1
        if let i = r.nsImage, let t = i.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/\(name).png"))
        }
    }
}

MainActor.assumeIsolated { run() }
