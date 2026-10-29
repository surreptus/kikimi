import SwiftUI

/// The menu bar: adding videos, going to a page, finding words, and the help pages. Everything else is the standard
/// Mac menus. Items are disabled until the library has opened.
struct AppCommands: Commands {
    let app: AppState

    var body: some Commands {
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

        CommandGroup(replacing: .help) {
            Button("How Aomame Works") { app.showAbout = true }
                .disabled(!app.isReady)
            Button("Privacy Policy") { app.showPrivacy = true }
                .disabled(!app.isReady)
            Button("Terms of Use") { app.showTerms = true }
                .disabled(!app.isReady)
            Button("Acknowledgements") { app.showAcknowledgements = true }
                .disabled(!app.isReady)
        }
    }
}
