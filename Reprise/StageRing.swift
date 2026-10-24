import LangCore
import SwiftUI

/// Where a word is in its nine review stages: a ring of nine segments that fills as the word moves up. The colour
/// goes from red through yellow to green, and a word that has finished (stage 9) is a white disc. Stage 0 is an
/// empty ring: not started. The number of segments filled says the stage, so colour is never the only signal.
struct StageRing: View {
    let stage: Int
    var size: CGFloat = 16

    /// Red at stage 1, yellow around 5, green at 8.
    static func color(for stage: Int) -> Color {
        let ramp: [UInt32] = [0xE5484D, 0xEF6C2F, 0xF28C1E, 0xF2AE1C, 0xE3C41A, 0xA8C61F, 0x5DB542, 0x1E8A55]
        return Color(hex: ramp[max(0, min(ramp.count - 1, stage - 1))])
    }

    var body: some View {
        Group {
            if stage >= 9 {
                Circle().fill(Color.white)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: max(1.5, size * 0.1)))
            } else {
                ZStack {
                    ForEach(0..<9, id: \.self) { index in
                        Segment(index: index)
                            .stroke(index < stage ? Self.color(for: stage) : Theme.ink.opacity(0.2),
                                    style: StrokeStyle(lineWidth: size * 0.2, lineCap: .butt))
                    }
                }
                .padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(stage >= 9 ? "Stage 9 of 9, finished" : stage == 0 ? "Not started" : "Stage \(stage) of 9")
    }

    /// One ninth of the ring, with a small gap either side, starting at the top and going clockwise.
    private struct Segment: Shape {
        let index: Int
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let start = -90.0 + Double(index) * 40 + 4
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(start), endAngle: .degrees(start + 32), clockwise: false)
            return path
        }
    }
}

/// A word's status as one small mark: an empty ring (new), a ring filled to its stage (learning), a green tick
/// (known) or a white disc (finished).
struct StatusIndicator: View {
    let status: WordStatus
    let stage: Int?
    var size: CGFloat = 16

    var body: some View {
        switch status {
        case .new: StageRing(stage: 0, size: size)
        case .learning: StageRing(stage: max(1, stage ?? 1), size: size)
        case .burned: StageRing(stage: 9, size: size)
        case .known:
            ZStack {
                Circle().fill(Theme.green)
                Image(systemName: "checkmark").font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(Color(light: .white, dark: Color(hex: 0x0F2A1C)))
            }
            .frame(width: size, height: size)
            .accessibilityLabel("Known")
        }
    }
}

/// The word's status: its mark, then the word for it (except for a word being learned, which is just its ring).
struct StatusBadge: View {
    let status: WordStatus
    var stage: SRSStage?

    /// A word being learned shows only its ring: the filled segments and colour are the stage, and hovering or
    /// VoiceOver says it in words. Every other status keeps its word beside the mark.
    private var ringOnly: Bool { status == .learning }

    var body: some View {
        HStack(spacing: 6) {
            StatusIndicator(status: status, stage: stage?.rawValue, size: 18)
            if !ringOnly { Text(status.rawValue.capitalized) }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.leading, 6).padding(.trailing, ringOnly ? 6 : 10).padding(.vertical, 3)
        .background(Capsule().fill(Theme.softStrong))
        .foregroundStyle(Theme.ink)
        .help(stage.map { "Stage \($0.rawValue) of 9" } ?? status.rawValue.capitalized)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.map { "\(status.rawValue.capitalized), stage \($0.rawValue) of 9" } ?? status.rawValue.capitalized)
    }
}
