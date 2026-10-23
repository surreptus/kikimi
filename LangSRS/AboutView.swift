import LangCore
import SwiftUI

/// How Reprise works: the first-time steps, what each import step does and how long it takes, how reviews are
/// scheduled, and the keyboard shortcuts. The review intervals are read from `SRS`, so this page can't drift from it.
struct AboutView: View {
    @Environment(\.dismissModal) private var dismiss

    private static let stageNames = [
        "Apprentice 1", "Apprentice 2", "Apprentice 3", "Apprentice 4", "Guru 1", "Guru 2", "Master", "Enlightened",
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
                    importSteps
                    reviews
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

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.title(17))
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
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

    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
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
            paragraph("Your original file is only ever read, never changed or deleted. Reprise works on a copy and keeps a smaller one for playback.")
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

    private func row(_ name: String, _ text: String) -> some View {
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
                    Text("Stage").foregroundStyle(Theme.muted)
                    Text("Next review comes after").foregroundStyle(Theme.muted)
                }
                .font(Theme.small)
                ForEach(Array(SRS.intervals.enumerated()), id: \.offset) { index, interval in
                    GridRow {
                        Text("\(index + 1). \(Self.stageNames[index])")
                        Text(Self.describe(interval))
                    }
                }
                GridRow {
                    Text("9. Burned")
                    Text("Finished: it never comes back")
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel(padding: 0)
            VStack(alignment: .leading, spacing: 6) {
                bullet("Got it moves a word up one stage. Missed it moves it down one, never below Apprentice 1.")
                bullet("A word's stage changes only on its first answer in a sitting. A missed word returns later in the same sitting for another try, without moving again.")
                bullet("The sentence on a card is picked at random from your videos each time, so you meet the word in different places.")
                bullet("Words marked Known are never reviewed. Reset on the Words page puts a word back to new.")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").accessibilityHidden(true)
            paragraph(text)
        }
    }

    private var shortcuts: some View {
        section("Keyboard") {
            VStack(alignment: .leading, spacing: 8) {
                shortcut("Anywhere", "⌘O adds videos. ⌘1, ⌘2 and ⌘3 go to Videos, Words and Review. ⌘F finds words. ⌘, opens Settings.")
                shortcut("Review", "Space shows the answer. → is Got it, ← is Missed it. W says the word, R plays the sentence.")
                shortcut("Video", "Space plays and pauses. Click a word to keep its meaning; arrow keys move between words and Return keeps one. S says it, L starts learning it, K marks it known, Esc lets go.")
                shortcut("Words", "↑ ↓ move, Shift extends, ⌘A selects all, Esc clears.")
            }
        }
    }

    private func shortcut(_ place: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(place).font(.system(.body, design: .rounded, weight: .medium)).frame(width: 70, alignment: .leading)
            paragraph(text)
        }
        .accessibilityElement(children: .combine)
    }

    /// 4 hours, 47 hours, 7 days: hours until two days, then days.
    private static func describe(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        if hours <= 48 { return "\(hours) hours" }
        return "\(hours / 24) days"
    }
}
