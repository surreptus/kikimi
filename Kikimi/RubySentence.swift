import LangCore
import SwiftUI

/// A card's sentence with furigana over its words. The space for the furigana is always kept, so showing it never moves the
/// text. It shows while the pointer is over the sentence, or while the F key has it on.
struct RubySentence: View {
    let example: ExampleLine
    let profile: any LanguageProfile
    /// Set by the F key.
    let pinned: Bool
    var size: CGFloat = 20

    @State private var segments: [LineSegment] = []
    @State private var hovering = false

    private var rubySize: CGFloat { max(10, (size * 0.55).rounded()) }
    private var hasRuby: Bool { segments.contains { $0.token?.reading != nil } }

    var body: some View {
        Group {
            if segments.isEmpty || !hasRuby {
                Text(example.highlighted).font(Theme.sized(size: size, design: .rounded)).multilineTextAlignment(.center)
            } else {
                FlowLayout(centered: true) {
                    ForEach(segments) { segment in
                        VStack(spacing: 0) {
                            Text(segment.token?.reading ?? " ")
                                .font(.system(size: rubySize, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.ink)
                                .opacity((hovering || pinned) && segment.token?.reading != nil ? 1 : 0)
                                .accessibilityHidden(true)
                            Text(segment.text)
                                .font(Theme.sized(size: size, design: .rounded))
                                .foregroundStyle(isTheWord(segment) ? Color(Theme.highlight) : Theme.muted)
                                .fontWeight(isTheWord(segment) ? .semibold : .regular)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[.lastTextBaseline] }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(example.text)
            }
        }
        .foregroundStyle(Theme.muted)
        .onHover { hovering = $0 }
        .task(id: example.text) {
            let text = example.text
            let profile = profile
            segments = profile.display.showsReadings ? await Task.detached { profile.lineSegments(in: text) }.value : []
        }
    }

    private func isTheWord(_ segment: LineSegment) -> Bool {
        segment.token != nil && segment.text.localizedCaseInsensitiveCompare(example.surface) == .orderedSame
    }
}
