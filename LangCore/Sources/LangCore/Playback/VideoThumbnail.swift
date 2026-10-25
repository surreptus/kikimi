import AVFoundation
import CoreGraphics

/// A still from a video, for the library list.
public enum VideoThumbnail {
    /// A frame about a tenth of the way in (the opening is often a title card or black), no larger than `maxSize`
    /// on a side. nil if the file can't be read.
    public static func image(for url: URL, duration: Double, maxSize: Double = 360) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        let time = CMTime(seconds: max(0, duration * 0.1), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}
