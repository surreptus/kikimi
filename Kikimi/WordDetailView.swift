import AppKit
import LangCore
import SwiftUI

struct WordDetail: View {
    let env: LangEnvironment
    let row: WordRow
    @Environment(AppState.self) private var app
    @State private var entries: [DictionaryEntry] = []
    @State private var kanji: [KanjiInfo] = []
    @State private var examples: [ExampleLine] = []
    @State private var audio: SentenceAudioPlayer?
    @State private var showsAllExamples = false
    @State private var seen = WordSeen()
    /// The word the details on show belong to. The panel is kept as you move from word to word and its details are
    /// swapped in together, so nothing empties out and refills (and "No entry found" never shows while one loads).
    @State private var loadedFor: Int64?
    @State private var position = ScrollPosition(edge: .top)
    private let examplesShownFirst = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !kanji.isEmpty { kanjiSection }

                Text("Dictionary").font(Theme.title(17))
                if entries.isEmpty {
                    if loadedFor == row.id { Text("No entry found.").foregroundStyle(Theme.muted) }
                } else {
                    ForEach(entries) { EntryView(entry: $0, showsReading: app.profile.display.showsReadings, partOfSpeech: row.word.pos) }
                }

                Text("From your videos").font(Theme.title(17))
                ForEach(showsAllExamples ? examples : Array(examples.prefix(examplesShownFirst))) { line in exampleRow(line) }
                if examples.count > examplesShownFirst {
                    Button(showsAllExamples ? String(localized: "Show fewer") : String(localized: "Show \(examples.count - examplesShownFirst) more")) {
                        showsAllExamples.toggle()
                    }
                    .buttonStyle(.plain).font(Theme.small).foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($position)
        // Back to the top as soon as the word changes, before its details arrive: waiting until they are in place
        // asks for the top while the old, longer layout is still showing, and the offset then ends at the bottom.
        .onChange(of: row.id) { position.scrollTo(edge: .top) }
        // Opened for a moment longer than it takes to arrow past: that is a lookup.
        .task(id: row.id) {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { try? await env.database.record(.lookup, subject: row.id) }
        }
        .task { audio = SentenceAudioPlayer(libraryRoot: env.libraryURL) }
        .task(id: row.id) {
            let word = row.word, id = row.id
            let newEntries = (try? await env.database.lookup(language: word.language, term: word.lemma, limit: 5)) ?? []
            let newKanji = await env.kanjiInfo(in: word.lemma, language: word.language)
            let newExamples = (try? await env.database.examples(wordID: id)) ?? []
            let newSeen = (try? await env.database.seen(wordID: id)) ?? WordSeen()
            guard !Task.isCancelled else { return }   // you moved on before this one finished
            audio?.stop()
            showsAllExamples = false
            (entries, kanji, examples, seen, loadedFor) = (newEntries, newKanji, newExamples, newSeen, id)
        }
        .onDisappear { audio?.stop() }
    }

    /// Each kanji in the word with its meaning and readings. On'yomi (from Chinese) are in katakana and kun'yomi
    /// (native) in hiragana, and each is labelled too, so the difference never depends on telling scripts apart.
    private var kanjiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kanji").font(Theme.title(17))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(kanji) { info in
                    HStack(alignment: .top, spacing: 14) {
                        Text(info.literal).font(.system(size: 34, design: .rounded))
                        VStack(alignment: .leading, spacing: 4) {
                            if !info.meanings.isEmpty {
                                Text(info.meanings.joined(separator: "; ")).font(.callout)
                            }
                            if let level = levelLine(info) {
                                Text(level).font(Theme.small).foregroundStyle(Theme.muted)
                                    .help("The JLPT level is KANJIDIC2's, from the exam's older four levels, shown as the matching N levels (N3 and N2 share one). The school year is when Japanese schools teach it.")
                            }
                            Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 2) {
                                if !info.onReadings.isEmpty {
                                    GridRow {
                                        Text("On'yomi").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
                                        Text(info.onReadings.joined(separator: "、"))
                                    }
                                }
                                if !info.kunReadings.isEmpty {
                                    GridRow {
                                        Text("Kun'yomi").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
                                        Text(info.kunReadings.joined(separator: "、"))
                                    }
                                }
                            }
                            .font(.callout)
                        }
                        Spacer(minLength: 0)
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(kanjiLabel(info))
                }
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

    private func kanjiLabel(_ info: KanjiInfo) -> String {
        var parts = [info.literal]
        if !info.meanings.isEmpty { parts.append(String(localized: "Meaning: \(listed(info.meanings))")) }
        if let level = levelLine(info) { parts.append(level) }
        if !info.onReadings.isEmpty { parts.append(String(localized: "On reading: \(listed(info.onReadings))")) }
        if !info.kunReadings.isEmpty { parts.append(String(localized: "Kun reading: \(listed(info.kunReadings))")) }
        return parts.joined(separator: ". ")
    }

    /// The word, with its audio and clip menu beside it; its status and actions share the line below.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(row.word.lemma).font(Theme.title(32)).lineLimit(2).minimumScaleFactor(0.7).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SpeakButton(
                    text: (app.profile.display.showsReadings ? entries.first?.reading : nil) ?? row.word.lemma,
                    languageCode: LanguageProfiles.profile(for: row.word.language)?.whisperCode ?? row.word.language)
                if !examples.isEmpty {
                    Menu {
                        Button("Export audio clips…") { exportExamples(.audio) }
                        Button("Export video clips…") { exportExamples(.video) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: PillIconStyle.width)
                    }
                    .menuStyle(.button).buttonStyle(.pill(.secondary, compact: true)).menuIndicator(.hidden).fixedSize()
                    .help("Export this word's example sentences as clips")
                }
            }
            if seen.lines > 0 {
                Text("Seen in ^[\(seen.lines) line](inflect: true) across ^[\(seen.videos) video](inflect: true)")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                StatusBadge(status: row.word.status, stage: row.word.stage)
                Spacer(minLength: 8)
                if row.word.status == .new {
                    Button("Learn") { setStatus(.learning) }.buttonStyle(.pill(compact: true))
                        .help("Start learning this word")
                }
                if row.word.status != .known, row.word.status != .ignored {
                    Button("Known") { setStatus(.known) }.buttonStyle(.pill(.secondary, compact: true))
                        .help("Mark this word as known")
                }
                if row.word.status == .ignored {
                    Button("Restore") { setStatus(.new) }.buttonStyle(.pill(.secondary, compact: true))
                        .help("Bring this word back as a new word")
                } else {
                    Button("Ignore") { setStatus(.ignored) }.buttonStyle(.pill(.quiet, compact: true))
                        .help("Set this word aside: it is not worth learning, such as a name or a mistake")
                }
            }
        }
    }

    private func setStatus(_ status: WordStatus) {
        Task {
            switch status {
            case .learning: try? await env.database.startLearning(wordID: row.id)
            case .ignored: try? await env.database.markIgnored(wordIDs: [row.id])
            case .new: try? await env.database.markNew(wordIDs: [row.id])
            default: try? await env.database.markKnown(wordID: row.id)
            }
            app.dataChanged()
        }
    }

    private func exampleRow(_ line: ExampleLine) -> some View {
        let isPlaying = audio?.playingLineID == line.id
        return VStack(alignment: .leading, spacing: 4) {
            Text(line.text).font(.system(.body, design: .rounded)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text("\(line.videoTitle) · \(timestamp(line.startTime))").font(Theme.small).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button(isPlaying ? String(localized: "Stop") : String(localized: "Hear"), systemImage: isPlaying ? "stop.fill" : "speaker.wave.2") {
                    togglePlayback(line)
                }
                .help("Play this sentence's audio from your video, right here")
                .accessibilityLabel(isPlaying ? "Stop the sentence" : "Hear the sentence")
                Button("Open video", systemImage: "play.rectangle") {
                    audio?.stop()
                    app.openVideo(id: line.videoID, at: line.startTime)
                }
                .help("Open the video at this moment")
                .accessibilityLabel("Open the video at this sentence")
            }
            .labelStyle(.iconOnly).foregroundStyle(Theme.muted).font(.system(size: 13))
            // Speaker and stop are different widths; a fixed box keeps the icons, and the text beside them, still.
            .buttonStyle(IconSlotStyle())
        }
        .padding(.vertical, 6)
        // One group per sentence, named by the sentence, so the buttons inside say which one they are for.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(line.text)
    }

    private func togglePlayback(_ line: ExampleLine) {
        guard let audio else { return }
        if audio.playingLineID == line.id {
            audio.stop()
            return
        }
        Task {
            if await !audio.play(line), !FileManager.default.fileExists(atPath: env.libraryURL.appending(path: line.mediaPath).path) {
                app.showToast(String(localized: "That audio file is missing from the library."), isError: true)
            }
        }
    }

    private func exportExamples(_ kind: ClipKind) {
        guard let folder = ExportPanels.chooseFolder(message: String(localized: "Choose a folder for the \(row.word.lemma) clips")) else { return }
        app.showToast(String(localized: "Exporting…"))
        Task {
            do {
                let files = try await env.exportClips(forWord: row.id, kind: kind, into: folder)
                app.showToast(inflected("Saved ^[\(files.count) clip](inflect: true) to \(folder.lastPathComponent)"))
                NSWorkspace.shared.activateFileViewerSelecting(files)
            } catch {
                app.showToast(String(localized: "Export failed: \(error.localizedDescription)"), isError: true)
            }
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct EntryView: View {
    let entry: DictionaryEntry
    let showsReading: Bool
    /// The part of speech of the word being shown, when a page knows it; otherwise the entry's first meaning decides.
    var partOfSpeech: PartOfSpeech?

    /// "das Buch" for a noun with a gender, else just the word. A verb that also has a noun sense (aller) gets none.
    private var title: String {
        let isNoun = partOfSpeech.map { $0 == .noun } ?? entry.startsAsNoun
        guard isNoun else { return entry.headword }
        return LanguageProfiles.profile(for: entry.language)?.nounPhrase(headword: entry.headword, gender: entry.gender) ?? entry.headword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                if showsReading, let reading = entry.reading, reading != entry.headword {
                    Text(reading).foregroundStyle(Theme.muted)
                }
            }
            Text(entry.gloss).font(.callout).textSelection(.enabled)
        }
    }
}

/// A plain icon button in a fixed 28 x 24 box, so swapping its symbol never changes the layout around it.
private struct IconSlotStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
