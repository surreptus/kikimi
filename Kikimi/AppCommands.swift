import AppKit
import SwiftUI

/// The menu bar: adding videos, going to a page, finding words, and the help pages. Everything else is the standard
/// Mac menus. Items are disabled until the library has opened.
struct AppCommands: Commands {
    let app: AppState

    var body: some Commands {
        // The standard About window, with a few lines under the version: what the app is, where to find it, and the credits.
        CommandGroup(replacing: .appInfo) {
            Button("About Kikimi") { Self.showAboutPanel() }
            Button("Check for Updates…") { Task { await UpdateChecker.run() } }
        }

        // One window, so there is no "New Window". Adding a video is what "New" means here.
        CommandGroup(replacing: .newItem) {
            Button("Add Videos…") { app.requestAddVideos() }
                .keyboardShortcut("o")
                .disabled(!app.isReady)
            Button("Storage…") { app.showStorage = true }
                .disabled(!app.isReady)
            Divider()
            Button("Export Progress…") { app.backup.request = .export; app.openSettings(.data) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!app.isReady)
            Button("Import Progress…") { app.backup.request = .chooseFile; app.openSettings(.data) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!app.isReady)
            Divider()
            Button("Export Words to Anki…") { app.ankiExportRequested = true }
                .disabled(!app.isReady)
        }

        CommandMenu("Go") {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { app.select(item) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(!app.isReady)
            }
            Divider()
            Button("Find Words") { app.requestFindWords() }
                .keyboardShortcut("f")
                .disabled(!app.isReady)
        }

        #if DEBUG
        CommandMenu("Debug") {
            Button("Show Welcome Page") { app.previewingWelcome = true }
                .disabled(!app.isReady)
            Divider()
            Button("Reset Library…") { app.confirmingReset = .library }
            Button("Reset Library and Settings…") { app.confirmingReset = .everything }
        }
        #endif

        CommandGroup(replacing: .help) {
            Button("How Kikimi Works") { app.showAbout = true }
                .disabled(!app.isReady)
            Button("Keyboard Shortcuts") { app.aboutAtKeyboard = true; app.showAbout = true }
                .disabled(!app.isReady)
            Button("Report a Problem…") { app.reportProblem() }
            Divider()
            Button("Privacy Policy") { app.showPrivacy = true }
                .disabled(!app.isReady)
            Button("Terms of Use") { app.showTerms = true }
                .disabled(!app.isReady)
            Button("Acknowledgements") { app.showAcknowledgements = true }
                .disabled(!app.isReady)
        }
    }

    /// What the About window says under the name and version. Each paragraph is one whole sentence for a translator,
    /// with its links written in it.
    private static func showAboutPanel() {
        let paragraphs = [
            String(localized: "Learn a language from videos on your Mac. Nothing leaves it."),
            String(localized: "Free and open source under the [MIT licence](https://github.com/surreptus/kikimi/blob/main/LICENSE). [Website](https://surreptus.github.io/kikimi/), [source code](https://github.com/surreptus/kikimi) and [problem reports](https://github.com/surreptus/kikimi/issues)."),
            String(localized: "Dictionary data from JMdict, KANJIDIC2 and Wiktionary (CC BY-SA 4.0), and speech recognition by OpenAI Whisper. All credits are under Help > Acknowledgements."),
        ]
        let credits = NSMutableAttributedString()
        for (index, text) in paragraphs.enumerated() {
            let styled = (try? AttributedString(markdown: text)) ?? AttributedString(text)
            let line = NSMutableAttributedString(styled)
            line.addAttributes(
                [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor],
                range: NSRange(location: 0, length: line.length))
            if index > 0 { credits.append(NSAttributedString(string: "\n\n")) }
            credits.append(line)
        }
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 0, length: credits.length))
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
