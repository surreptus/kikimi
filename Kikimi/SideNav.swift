import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case videos = "Videos"
    case words = "Words"
    case review = "Review"

    var id: String { rawValue }

    /// Position in the nav, used to slide screens in the direction you moved.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var title: String {
        switch self {
        case .videos: String(localized: "Videos")
        case .words: String(localized: "Words")
        case .review: String(localized: "Learn")
        }
    }

    var symbol: String {
        switch self {
        case .videos: "film.stack.fill"
        case .words: "text.book.closed.fill"
        case .review: "rectangle.stack.fill"
        }
    }
}

/// The navigation: a strip fixed to the left edge, a shade darker than the section colour beside it.
struct SideNav: View {
    @Binding var selection: SidebarItem
    var dueCount: Int
    var languages: [(code: String, name: String)]
    @Binding var language: String
    var showAbout: () -> Void
    var showSettings: () -> Void
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kikimi").font(Theme.title(20)).foregroundStyle(Theme.ink)
                .padding(.bottom, 14)
                .padding(.horizontal, 12)
                .padding(.top, 30)   // clears the window's traffic-light buttons

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
                    Image(systemName: "chevron.up.chevron.down").font(Theme.styled(.caption2))
                }
                .font(Theme.sized(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Capsule().fill(Theme.ink.opacity(0.07)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            HStack(spacing: 12) {
                Button("Settings", action: showSettings)
                Button("How it works", action: showAbout)
            }
            .buttonStyle(.plain)
            .font(Theme.sized(size: 12, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6).padding(.top, 4)
        }
        .padding(14)
        .frame(width: 214)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func navRow(_ item: SidebarItem) -> some View {
        let selected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol).font(Theme.sized(size: 15, weight: .medium)).frame(width: 22)
                Text(item.title)
                    .font(Theme.sized(size: 15, weight: .medium, design: .rounded))
                Spacer()
                if item == .review, dueCount > 0 {
                    Text("\(dueCount)")
                        .font(Theme.sized(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent))
                        .help(inflected("^[\(dueCount) review](inflect: true) due now"))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background {
                // One shared shape: it glides between rows when the selection changes.
                if selected {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.navSelection)
                        .matchedGeometryEffect(id: "selectionPill", in: pill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item == .review && dueCount > 0 ? String(localized: "Learn, \(dueCount) due") : item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
