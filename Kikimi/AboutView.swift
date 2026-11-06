import LangCore
import SwiftUI

/// How Kikimi works: the first-time steps, what each import step does and how long it takes, how reviews are
/// scheduled, and the keyboard shortcuts. The review intervals are read from `SRS`, so this page can't drift from it.
struct AboutView: View {
    @Environment(\.dismissModal) private var dismiss
    @Environment(AppState.self) private var app

    private static let stageNames = [
        String(localized: "Stage 1"), String(localized: "Stage 2"), String(localized: "Stage 3"), String(localized: "Stage 4"),
        String(localized: "Stage 5"), String(localized: "Stage 6"), String(localized: "Stage 7"), String(localized: "Stage 8"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How Kikimi works").font(Theme.title(22))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
            }
            .padding(20)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    gettingStarted
                    level
                    importSteps
                    reviews
                    backups
                    shortcuts.id("keyboard")
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if app.aboutAtKeyboard { proxy.scrollTo("keyboard", anchor: .top) }
                app.aboutAtKeyboard = false
            }
            }
        }
        .frame(width: 640, height: 600)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .fontDesign(.rounded)
    }

    // MARK: Sections

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.title(17))
            content()
        }
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
    }

    private var gettingStarted: some View {
        section("The first time") {
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Add a video", "Drop a video you own on Videos, then press Start import. Got an .srt or .vtt subtitle file? Press Add subtitles and nothing is transcribed. Otherwise, the first time, download a speech model once.")
                step(2, "Let it transcribe", "Kikimi listens on this Mac and writes out what is said, with times. This is the long step: about 3 minutes for a 10 minute video in our tests.")
                step(3, "Choose your words", "On Words, the words from your videos are listed by how often they appear. Press Learn on the ones you want, or Known on the ones you already know. Or let Learn offer the words you hear most each day, 15 by default (Settings > Languages).")
                step(4, "Practise", "On Learn, the words you are learning come back at set times, each in a sentence from your videos. Choose the kind of card above Start, and come back whenever the number beside Learn is above zero.")
            }
        }
    }

    private func step(_ number: Int, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 26, height: 26).background(Circle().fill(Theme.softStrong))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.body, design: .rounded, weight: .semibold))
                paragraph(text)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var importSteps: some View {
        section("What happens when you add a video") {
            paragraph("Your original file is only read, never changed or deleted. Its row shows the step it is on, such as 4 of 7 · Transcribing.")
            VStack(alignment: .leading, spacing: 8) {
                row("Reading file", "Checks you haven't added this video already.")
                row("Copying", "Makes a working copy.")
                row("Checking language", "Listens to a short sample, so a Japanese video isn't added as Spanish.")
                row("Transcribing", "The long step. Longer with larger models.")
                row("Compressing video", "Saves a small copy for playback (161 MB became 29 MB in our tests). Choose Original quality in Settings to skip this.")
                row("Verifying", "Checks the copy plays and is the right length.")
                row("Saving", "Stores everything at once: all of it or none of it.")
            }
            paragraph("Cancel at any point before saving and nothing is left behind.")
        }
    }

    private func row(_ name: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name).font(.system(.body, design: .rounded, weight: .medium)).frame(width: 150, alignment: .leading)
            paragraph(text)
        }
        .accessibilityElement(children: .combine)
    }

    private var reviews: some View {
        section("How reviews are scheduled") {
            paragraph("A word you get right comes back after a longer wait each time. One you miss comes back sooner.")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("").frame(width: 18)
                    Text("Stage").foregroundStyle(Theme.muted)
                    Text("Next review comes after").foregroundStyle(Theme.muted)
                }
                .font(Theme.small)
                ForEach(Array(SRS.intervals.enumerated()), id: \.offset) { index, interval in
                    GridRow {
                        StageRing(stage: index + 1, size: 18)
                        Text(Self.stageNames[index])
                        Text(Self.describe(interval))
                    }
                }
                GridRow {
                    StageRing(stage: 9, size: 18)
                    Text("Finished")
                    Text("Finished: it never comes back")
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel(padding: 0)
            VStack(alignment: .leading, spacing: 6) {
                bullet("Got it moves a word up a stage. Missed it moves it down one, never below Stage 1.")
                bullet("A word moves only on its first answer in a sitting. A missed word comes back later in the sitting without moving again.")
                bullet("The ring beside a word fills as it moves up. An empty ring is new, and a green tick is known.")
                bullet("Words marked Known are not reviewed. Reset on Words puts one back to new.")
                bullet("Under Practice, Review ahead and Practice finished ask words without moving them; Review known tests a few words you marked known, and any you miss go back to your reviews.")
            }
        }
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").accessibilityHidden(true)
            paragraph(text)
        }
    }

    private var level: some View {
        section("Finding videos at your level") {
            paragraph("Each video shows how much of it you know, such as 91% known · Comfortable. Only nouns, verbs, adjectives and adverbs are counted. Small words are nearly always known, so you understand more than the figure says.")
            VStack(alignment: .leading, spacing: 6) {
                bullet("Hard is under 80%, A stretch is 80 to 88%, Comfortable is 88 to 98%, and Easy is 98% or more.")
                bullet("Around 90% of the counted words is where following along gets comfortable.")
                bullet("A word counts as known if you marked it known, it is finished, or it is at Stage 5 or above.")
                bullet("Sort by Closest to my level to see what to watch next.")
                bullet("Open a video's Info to start learning its commonest new words at once.")
                bullet("In Settings, under Data, you can mark a list of words you already know.")
            }
        }
    }

    private var backups: some View {
        section("Keeping your progress safe") {
            paragraph("In Settings, under Data, Save backup writes your words, stages and review dates to a .kikimi file. Turn on Include my videos and transcripts to save a folder instead, so a new Mac needs no re-transcribing. Speech models are never included.")
            paragraph("To restore, choose the file or folder, or double-click it. You see what would change first, and nothing you already have is overwritten.")
        }
    }

    private var shortcuts: some View {
        section("Keyboard") {
            VStack(alignment: .leading, spacing: 14) {
                shortcutGroup("Anywhere", [
                    ("⌘O", String(localized: "Add videos")), ("⌘1 ⌘2 ⌘3", String(localized: "Videos, Words, Review")),
                    ("⌘F", String(localized: "Find words")), ("⌘,", String(localized: "Settings"))])
                shortcutGroup("Review", [
                    ("Space", String(localized: "Show answer")), ("→", String(localized: "Got it")), ("←", String(localized: "Missed it")),
                    ("W", String(localized: "Say word")), ("R", String(localized: "Play sentence")), ("T", String(localized: "Translate (macOS 26)")),
                    ("E", String(localized: "Fix the line")), ("I", String(localized: "Open the word"))])
                shortcutGroup("Video", [
                    ("Space", String(localized: "Play or pause")), ("⌘← ⌘→", String(localized: "Line")), ("← →", String(localized: "Word")),
                    ("Return", String(localized: "Keep the meaning")), ("L", String(localized: "Learn")), ("K", String(localized: "Known")),
                    ("P", String(localized: "Pause after each line")), ("R", String(localized: "Repeat")), ("T", String(localized: "Translation (macOS 26)")),
                    ("H", String(localized: "Hide subtitles")), ("S", String(localized: "Show one line")),
                    ("E", String(localized: "Edit the line")), ("Esc", String(localized: "Let go"))])
                shortcutGroup("Words", [
                    ("↑ ↓", String(localized: "Move")), ("Shift", String(localized: "Extend")), ("⌘A", String(localized: "Select all")), ("Esc", String(localized: "Clear"))])
            }
        }
    }

    private func shortcutGroup(_ place: LocalizedStringKey, _ items: [(key: String, action: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(place).font(.system(.body, design: .rounded, weight: .medium))
            ShortcutHints(items: items)
        }
    }

    /// 4 hours, 47 hours, 7 days: hours until two days, then days.
    private static func describe(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        if hours <= 48 { return inflected("^[\(hours) hour](inflect: true)") }
        return inflected("^[\(hours / 24) day](inflect: true)")
    }
}
