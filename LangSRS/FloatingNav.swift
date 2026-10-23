import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case importVideos = "Import"
    case review = "Review"
    case words = "Words"
    case library = "Library"

    var id: String { rawValue }

    /// Position in the nav, used to slide screens in the direction you moved.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var symbol: String {
        switch self {
        case .importVideos: "square.and.arrow.down.fill"
        case .review: "rectangle.stack.fill"
        case .words: "text.book.closed.fill"
        case .library: "film.stack.fill"
        }
    }
}

/// The navigation, as a rounded card floating over the window.
struct FloatingNav: View {
    @Binding var selection: SidebarItem
    var dueCount: Int
    var languages: [(code: String, name: String)]
    @Binding var language: String
    var showAcknowledgements: () -> Void
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Theme.pink))
                    .background(RoundedRectangle(cornerRadius: 11).fill(Theme.pinkEdge).offset(y: 3))
                Text("LangSRS").font(Theme.title(20)).foregroundStyle(Theme.pinkText)
            }
            .padding(.bottom, 14)
            .padding(.horizontal, 4)

            ForEach(SidebarItem.allCases) { item in
                navRow(item)
            }

            Spacer(minLength: 16)

            Menu {
                ForEach(languages, id: \.code) { entry in
                    Button(entry.name) { language = entry.code }
                }
            } label: {
                HStack {
                    Image(systemName: "globe")
                    Text(languages.first { $0.code == language }?.name ?? language)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.pinkText)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 2))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Button("Acknowledgements", action: showAcknowledgements)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.top, 4)
        }
        .padding(14)
        .frame(width: 214)
        .frame(maxHeight: .infinity)
        // The shadow belongs to the card's shape only; on the whole view it would smear the icons and text.
        .background(RoundedRectangle(cornerRadius: 28).fill(Theme.card)
            .shadow(color: Theme.pinkEdge.opacity(0.16), radius: 20, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.line, lineWidth: 2))
    }

    private func navRow(_ item: SidebarItem) -> some View {
        let selected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 24)
                Text(item.rawValue.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                Spacer()
                if item == .review, dueCount > 0 {
                    Text("\(dueCount)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.red))
                }
            }
            .foregroundStyle(selected ? Theme.pinkText : Color.secondary)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background {
                // One shared shape: it glides between rows when the selection changes.
                if selected {
                    RoundedRectangle(cornerRadius: 15).fill(Theme.pinkSoft)
                        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.pink, lineWidth: 2))
                        .matchedGeometryEffect(id: "selectionPill", in: pill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}
