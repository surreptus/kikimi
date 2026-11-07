import AppKit
import LangCore
import SwiftUI

/// File > Export Words to Anki…: asks whether to include sentence audio, then for a folder, and writes the file Anki imports.
/// It exports the words selected on the Words page, or, with none selected, the words you are learning.
struct AnkiExportFlow: ViewModifier {
    let env: LangEnvironment
    @Environment(AppState.self) private var app
    @State private var result: AnkiExportResult?

    private var selected: Int { app.wordsSelection.count }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Export to Anki", isPresented: Binding(get: { app.ankiExportRequested }, set: { app.ankiExportRequested = $0 })) {
                Button("Export with sentence audio") { export(includeAudio: true) }
                Button("Export text only") { export(includeAudio: false) }
            } message: {
                Text(selected == 0
                     ? "Exports the words you are learning, each with its meaning and a sentence from your videos. Sentence audio makes a media folder you copy into Anki once."
                     : "Exports the \(selected) selected words, each with its meaning and a sentence from your videos. Sentence audio makes a media folder you copy into Anki once.")
            }
            .alert("Anki file saved", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                if let result {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.file]) }
                }
                Button("OK", role: .cancel) {}
            } message: {
                if let result { Text(message(for: result)) }
            }
    }

    private func export(includeAudio: Bool) {
        guard let folder = ExportPanels.chooseFolder(message: String(localized: "Choose a folder for the Anki file")) else { return }
        app.showToast(String(localized: "Exporting…"))
        Task {
            do {
                let ids = app.wordsSelection.isEmpty
                    ? try await env.database.learningWordIDs(language: app.languageCode)
                    : Array(app.wordsSelection)
                guard !ids.isEmpty else { app.showToast(String(localized: "No words to export.")); return }
                result = try await env.exportAnki(wordIDs: ids, language: app.languageCode, includeAudio: includeAudio, into: folder)
                app.dismissToast()   // the saved-file alert takes over
            } catch {
                app.showToast(String(localized: "Export failed: \(error.localizedDescription)"), isError: true)
            }
        }
    }

    private func message(for result: AnkiExportResult) -> String {
        var text = String(localized: "Saved \(inflected("^[\(result.cards) card](inflect: true)")) to \(result.file.deletingLastPathComponent().lastPathComponent). In Anki, choose File > Import and pick \(result.file.lastPathComponent).")
        if result.audioFiles > 0 {
            text += " " + String(localized: "Copy the files in the media folder into Anki's collection.media folder first, so the sentence audio plays.")
        }
        return text
    }
}
