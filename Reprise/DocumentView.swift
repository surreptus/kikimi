import SwiftUI

/// The privacy policy, shown from the nav footer. The text is `Privacy.md`, which is also the file to publish at a
/// URL (the App Store asks for one), so there is one source and the two can't disagree.
struct PrivacyView: View {
    @Environment(\.dismissModal) private var dismiss

    private enum Block: Identifiable {
        case heading(String), bullet(String), paragraph(String)
        var id: String {
            switch self {
            case .heading(let t): "h:" + t
            case .bullet(let t): "b:" + t
            case .paragraph(let t): "p:" + t
            }
        }
    }

    /// Headings, bullets and paragraphs: all the file uses. The page title is dropped; the panel has its own.
    private var blocks: [Block] {
        guard let url = Bundle.main.url(forResource: "Privacy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [.paragraph("The privacy policy could not be loaded.")]
        }
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() { if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] } }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("# ") { flush() }
            else if line.hasPrefix("## ") { flush(); result.append(.heading(String(line.dropFirst(3)))) }
            else if line.hasPrefix("- ") { flush(); result.append(.bullet(String(line.dropFirst(2)))) }
            else if line.trimmingCharacters(in: .whitespaces).isEmpty { flush() }
            else { paragraph.append(line) }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Privacy policy").font(Theme.title(22))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { block in
                        switch block {
                        case .heading(let text):
                            Text(text).font(Theme.title(17)).padding(.top, 10)
                        case .bullet(let text):
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").accessibilityHidden(true)
                                inline(text)
                            }
                        case .paragraph(let text):
                            inline(text)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 560)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .fontDesign(.rounded)
    }

    /// Plain text with the inline markdown (italics) the file uses.
    private func inline(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
