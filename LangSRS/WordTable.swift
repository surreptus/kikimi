import AppKit
import LangCore
import SwiftUI

/// How the word table is sorted: one column, one direction.
struct WordSort: Equatable {
    enum Column: CaseIterable { case word, type, seen, status }

    var column: Column
    var ascending: Bool

    var comparators: [KeyPathComparator<WordRow>] {
        let order: SortOrder = ascending ? .forward : .reverse
        switch column {
        case .word: return [KeyPathComparator(\WordRow.word.lemma, order: order)]
        case .type: return [KeyPathComparator(\WordRow.word.pos.rawValue, order: order)]
        case .seen: return [KeyPathComparator(\WordRow.occurrenceCount, order: order)]
        case .status: return [KeyPathComparator(\WordRow.statusOrder, order: order)]
        }
    }

    /// Clicking the sorted column flips it; clicking another sorts by it (counts start high, names start A to Z).
    mutating func choose(_ new: Column) {
        if column == new { ascending.toggle() } else { column = new; ascending = new != .seen }
    }
}

/// The word list: square rows with faint stripes, the selected rows in the accent colour. It is built by hand
/// (not `Table`) because the system table draws its own rounded selection; the keyboard and VoiceOver behaviour
/// it replaces is rebuilt here: arrows move, shift extends, ⌘A selects all, Escape clears.
struct WordTable: View {
    let rows: [WordRow]            // already sorted
    @Binding var selection: Set<Int64>
    @Binding var sort: WordSort

    @State private var anchor: Int64?
    @FocusState private var focused: Bool

    private static let word: CGFloat = 0     // flexible
    private static let typeWidth: CGFloat = 80, seenWidth: CGFloat = 60, statusWidth: CGFloat = 96, nextWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            WordTableRow(row: row, selected: selection.contains(row.id), striped: index % 2 == 1)
                                .onTapGesture { click(row) }
                                .id(row.id)
                        }
                    }
                }
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, extend: NSEvent.modifierFlags.contains(.shift), proxy); return .handled }
                .onKeyPress(.upArrow) { move(-1, extend: NSEvent.modifierFlags.contains(.shift), proxy); return .handled }
                .onKeyPress(.escape) { selection = []; return .handled }
                .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    selection = Set(rows.map(\.id)); return .handled
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Words")
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell("Word", .word).frame(maxWidth: .infinity, alignment: .leading)
            headerCell("Type", .type).frame(width: Self.typeWidth, alignment: .leading)
            headerCell("Seen", .seen).frame(width: Self.seenWidth, alignment: .leading)
            headerCell("Status", .status).frame(width: Self.statusWidth, alignment: .leading)
            Text("Next review").frame(width: Self.nextWidth, alignment: .leading)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, Theme.screenPadding).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func headerCell(_ title: String, _ column: WordSort.Column) -> some View {
        Button {
            sort.choose(column)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sort.column == column {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(sort.column == column ? Theme.ink : Theme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title)")
        .accessibilityAddTraits(sort.column == column ? .isSelected : [])
    }

    // MARK: Selection

    /// Click selects one row; ⌘-click toggles it; shift-click extends from the last clicked row.
    private func click(_ row: WordRow) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor, let from = rows.firstIndex(where: { $0.id == anchor }),
           let to = rows.firstIndex(where: { $0.id == row.id }) {
            selection = Set(rows[min(from, to)...max(from, to)].map(\.id))
        } else if flags.contains(.command) {
            if selection.contains(row.id) { selection.remove(row.id) } else { selection.insert(row.id) }
            anchor = row.id
        } else {
            selection = selection == [row.id] ? [] : [row.id]
            anchor = row.id
        }
    }

    private func move(_ step: Int, extend: Bool, _ proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        let current = rows.lastIndex { selection.contains($0.id) }
        let next = min(rows.count - 1, max(0, (current ?? (step > 0 ? -1 : rows.count)) + step))
        let target = rows[next].id
        if extend, let anchor, let from = rows.firstIndex(where: { $0.id == anchor }) {
            selection = Set(rows[min(from, next)...max(from, next)].map(\.id))
        } else {
            selection = [target]
            anchor = target
        }
        proxy.scrollTo(target)
    }
}

private struct WordTableRow: View {
    let row: WordRow
    let selected: Bool
    let striped: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(row.word.lemma).font(.system(.body, design: .rounded, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.word.pos.rawValue).foregroundStyle(secondary).frame(width: 80, alignment: .leading)
            Text("\(row.occurrenceCount)×").foregroundStyle(secondary).monospacedDigit().frame(width: 60, alignment: .leading)
            status.frame(width: 96, alignment: .leading)
            // A container, so the column keeps its width on rows with no date.
            ZStack(alignment: .leading) {
                if let due = row.word.nextReview {
                    Text(due, format: .relative(presentation: .named)).foregroundStyle(secondary)
                }
            }
            .frame(width: 120, alignment: .leading)
        }
        .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
        .padding(.horizontal, Theme.screenPadding).padding(.vertical, 9)
        .background(selected ? Theme.accent : (striped ? Theme.stripe : .clear))
        // A bar as well as the colour, so the selection doesn't depend on telling gold from the field.
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.ink).frame(width: 4) } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var secondary: Color { selected ? Theme.onAccent.opacity(0.85) : Theme.muted }

    /// On the accent colour a tinted pill would be unreadable, so the word stands alone.
    @ViewBuilder private var status: some View {
        if selected {
            Text(row.word.status.rawValue.capitalized).font(.system(size: 12, weight: .medium, design: .rounded))
        } else {
            StatusBadge(status: row.word.status)
        }
    }
}
