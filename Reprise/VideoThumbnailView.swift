import AppKit
import LangCore
import SwiftUI

/// A small still from a video, made on first sight and remembered while the app runs.
struct VideoThumbnailView: View {
    let url: URL
    let duration: Double
    @State private var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        ZStack {
            Theme.soft
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "film").font(.system(size: 18)).foregroundStyle(Theme.faint)
            }
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityHidden(true)   // decorative; the title says what the video is
        .task(id: url) {
            if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
            guard let cg = await VideoThumbnail.image(for: url, duration: duration) else { return }
            let made = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            Self.cache.setObject(made, forKey: url as NSURL)
            image = made
        }
    }
}
