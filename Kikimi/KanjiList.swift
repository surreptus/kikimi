import LangCore
import SwiftUI

/// Each kanji of a word with its meaning and readings. On'yomi (from Chinese) are in katakana and kun'yomi (native) in
/// hiragana, and each is labelled too, so the difference never depends on telling scripts apart.
/// The word's page shows the full list. A card shows the compact one: no title, no exam level.
struct KanjiList: View {
    let kanji: [KanjiInfo]
    var showsTitle = false
    var compact = false

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 12) {
            if showsTitle { Text("Kanji").font(Theme.title(17)) }
            ForEach(kanji) { info in
                HStack(alignment: .top, spacing: 14) {
                    Text(info.literal).font(Theme.sized(size: compact ? 30 : 34, design: .rounded))
                    VStack(alignment: .leading, spacing: 4) {
                        if !info.meanings.isEmpty {
                            Text(info.meanings.joined(separator: "; ")).font(Theme.styled(.callout))
                        }
                        if !compact, let level = levelLine(info) {
                            Text(level).font(Theme.small).foregroundStyle(Theme.muted)
                                .help("The JLPT level is KANJIDIC2's, from the exam's older four levels, shown as the matching N levels (N3 and N2 share one). The school year is when Japanese schools teach it.")
                        }
                        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 2) {
                            if !info.onReadings.isEmpty {
                                GridRow {
                                    Text("On'yomi").font(Theme.sized(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
                                    Text(info.onReadings.joined(separator: "、"))
                                }
                            }
                            if !info.kunReadings.isEmpty {
                                GridRow {
                                    Text("Kun'yomi").font(Theme.sized(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
                                    Text(info.kunReadings.joined(separator: "、"))
                                }
                            }
                        }
                        .font(Theme.styled(.callout))
                    }
                    if !compact { Spacer(minLength: 0) }
                }
                .textSelection(.enabled)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(info))
            }
        }
        .help("On'yomi: reading from Chinese. Kun'yomi: native reading; the dot marks where the ending begins.")
    }

    /// "JLPT N5 · School year 1", or whichever of the two the kanji has.
    private func levelLine(_ info: KanjiInfo) -> String? {
        var parts: [String] = []
        if let levels = info.jlptLevels { parts.append(String(localized: "JLPT \(levels)")) }
        switch info.schoolGrade {
        case .year(let year): parts.append(String(localized: "School year \(year)"))
        case .secondary: parts.append(String(localized: "Secondary school"))
        case .names: parts.append(String(localized: "Used in names"))
        case nil: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func label(_ info: KanjiInfo) -> String {
        var parts = [info.literal]
        if !info.meanings.isEmpty { parts.append(String(localized: "Meaning: \(listed(info.meanings))")) }
        if !compact, let level = levelLine(info) { parts.append(level) }
        if !info.onReadings.isEmpty { parts.append(String(localized: "On reading: \(listed(info.onReadings))")) }
        if !info.kunReadings.isEmpty { parts.append(String(localized: "Kun reading: \(listed(info.kunReadings))")) }
        return parts.joined(separator: ". ")
    }
}

/// The kanji of a word, looked up when it shows. Nothing for a word with none, or a language with no kanji file.
struct WordKanji: View {
    let env: LangEnvironment
    let lemma: String
    let language: String
    @State private var kanji: [KanjiInfo] = []

    var body: some View {
        Group {
            if !kanji.isEmpty { KanjiList(kanji: kanji, compact: true).padding(.top, 8) }
        }
        .task(id: lemma) { kanji = await env.kanjiInfo(in: lemma, language: language) }
    }
}
