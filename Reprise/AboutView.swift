import LangCore
import SwiftUI

/// How Reprise works: the first-time steps, what each import step does and how long it takes, how reviews are
/// scheduled, and the keyboard shortcuts. The review intervals are read from `SRS`, so this page can't drift from it.
struct AboutView: View {
    @Environment(\.dismissModal) private var dismiss

    private static let stageNames = [
        String(localized: "Stage 1"), String(localized: "Stage 2"), String(localized: "Stage 3"), String(localized: "Stage 4"),
        String(localized: "Stage 5"), String(localized: "Stage 6"), String(localized: "Stage 7"), String(localized: "Stage 8"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How Reprise works").font(Theme.title(22))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.pill(compact: true)).keyboardShortcut(.defaultAction)
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    gettingStarted
                    level
                    importSteps
                    reviews
                    backups
                    shortcuts
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                step(1, "Add a video", "On Videos, drop a video file you own. The first time, pick a speech model and let it download once; the sizes are shown next to each choice.")
                step(2, "Let it transcribe", "Reprise listens to the video on this Mac and writes out what is said, with times. This is the long step. In our tests the medium model took about 3 minutes for a 10 minute video on an Apple silicon Mac; larger models are slower.")
                step(3, "Choose your words", "On Words, the words from your videos are listed by how often they appear. Select the ones you want to learn and press Start learning, or mark the ones you already know.")
                step(4, "Practise", "On Review, words you are learning come back at set times. Each card shows a sentence from one of your videos. Come back whenever the number beside Review is above zero.")
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
        .accessibilityLabel("Step \(number): \(title). \(text)")
    }

    private var importSteps: some View {
        section("What happens when you add a video") {
            paragraph("Your original file is only ever read, never changed or deleted. Reprise works on a copy and keeps a smaller one for playback. While a video is being added, its row says which step it is on, such as 4 of 8 · Transcribing. If you chose to go ahead despite a language warning, the language check is skipped and there are 7 steps.")
            VStack(alignment: .leading, spacing: 8) {
                row("Reading file", "Checks whether you've already added this video, by its contents rather than its name.")
                row("Copying", "Makes a working copy. Seconds.")
                row("Checking language", "Listens to a short sample so a Japanese video can't be added as Spanish by mistake.")
                row("Transcribing", "The long step: about a quarter of the video's length with the medium model in our tests, longer with larger models.")
                row("Compressing video", "Saves a small copy for playback; in our tests a 161 MB video became 29 MB. A video that is already small is kept as it is.")
                row("Verifying", "Checks the copy plays and is the right length before anything is kept.")
                row("Extracting audio", "Saves the sound on its own, for the sentence audio in reviews.")
                row("Saving", "Stores the lines and words in one step. Either everything is saved or nothing is.")
            }
            paragraph("You can cancel at any point before saving, and nothing is left behind. The other steps are usually much shorter than transcribing; we haven't timed each one.")
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
            paragraph("Reprise uses spaced repetition: a word you get right comes back after a longer wait each time, and one you miss comes back sooner. A word you are learning moves through these stages:")
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
            paragraph("You'll see the same circle beside a word on the Words page, in its panel and in the video. It fills as the word moves up, from red through yellow to green, and becomes a white disc once it is finished. An empty ring is a new word, and a green tick is a word you marked known.")
            VStack(alignment: .leading, spacing: 6) {
                bullet("Got it moves a word up one stage. Missed it moves it down one, never below Stage 1.")
                bullet("A word's stage changes only on its first answer in a sitting. A missed word returns later in the same sitting for another try, without moving again.")
                bullet("The sentence on a card is picked at random from your videos each time, so you meet the word in different places.")
                bullet("Words marked Known are never reviewed. Reset on the Words page puts a word back to new.")
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
            paragraph("On Videos, each video shows how much of it you already know, such as 91% known · Comfortable. It counts the nouns, verbs, adjectives and adverbs you know. Small words like articles and particles aren't kept; they make up about half of what is said and are nearly always known, so the share you really understand is higher than the figure. About 90% of the words that are kept is roughly 95% of everything, which is around where following along gets comfortable.")
            VStack(alignment: .leading, spacing: 6) {
                bullet("Hard is under 80%, A stretch is 80 to 88%, Comfortable is 88 to 98%, and Easy is 98% or more.")
                bullet("A word counts as known if you marked it known, it is finished, or you are learning it and its reviews are a week or more apart (Stage 5 and above).")
                bullet("Sort by Best fit to put the videos worth watching next at the top: mostly understood, with a little new.")
                bullet("Open a video's Info to see the commonest words you don't know yet, and start learning them all at once.")
                bullet("In Settings, under Data, you can mark a list of words you already know (one per line, or the first column of a CSV), so these numbers start out honest.")
            }
        }
    }

    private var backups: some View {
        section("Keeping your progress safe") {
            paragraph("In Settings, under Data, Save backup writes the words you are learning and the ones you know, with their stages and review dates, to a file ending in .reprise. It doesn't include videos or speech models.")
            paragraph("To restore, choose the file in the same place, drop it there, or double-click it. You'll see what would change first, and progress you already have is never overwritten. Words from a backup join their sentences when you add the videos again.")
        }
    }

    private var shortcuts: some View {
        section("Keyboard") {
            VStack(alignment: .leading, spacing: 8) {
                shortcut("Anywhere", "⌘O adds videos. ⌘1, ⌘2 and ⌘3 go to Videos, Words and Review. ⌘F finds words. ⌘, opens Settings.")
                shortcut("Review", "Space shows the answer. → is Got it, ← is Missed it. W says the word, R plays the sentence.")
                shortcut("Video", "Space plays and pauses. Click a word to keep its meaning; arrow keys move between words and Return keeps one. L starts learning it and K marks it known. Click anywhere outside the transcript, or press Esc, to let go.")
                shortcut("Words", "↑ ↓ move, Shift extends, ⌘A selects all, Esc clears.")
            }
        }
    }

    private func shortcut(_ place: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(place).font(.system(.body, design: .rounded, weight: .medium)).frame(width: 70, alignment: .leading)
            paragraph(text)
        }
        .accessibilityElement(children: .combine)
    }

    /// 4 hours, 47 hours, 7 days: hours until two days, then days.
    private static func describe(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        if hours <= 48 { return inflected("^[\(hours) hour](inflect: true)") }
        return inflected("^[\(hours / 24) day](inflect: true)")
    }
}
