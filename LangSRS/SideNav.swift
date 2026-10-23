import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case videos = "Videos"
    case words = "Words"
    case review = "Review"

    var id: String { rawValue }

    /// Position in the nav, used to slide screens in the direction you moved.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

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
    var showPrivacy: () -> Void
    var showStorage: () -> Void
    var showAcknowledgements: () -> Void
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reprise").font(Theme.title(20)).foregroundStyle(Theme.ink)
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
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Capsule().fill(Theme.ink.opacity(0.07)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button("How it works", action: showAbout)
                    Button("Privacy", action: showPrivacy)
                }
                HStack(spacing: 12) {
                    Button("Storage", action: showStorage)
                    Button("Acknowledgements", action: showAcknowledgements)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 6).padding(.top, 4)
        }
        .padding(14)
        .frame(width: 214)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Theme.rail)
    }

    private func navRow(_ item: SidebarItem) -> some View {
        let selected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol).font(.system(size: 15, weight: .medium)).frame(width: 22)
                Text(item.rawValue)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                Spacer()
                if item == .review, dueCount > 0 {
                    Text("\(dueCount)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background {
                // One shared shape: it glides between rows when the selection changes.
                if selected {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.softStrong)
                        .matchedGeometryEffect(id: "selectionPill", in: pill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
