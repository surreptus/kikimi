import AppKit
import UniformTypeIdentifiers

/// Where exported clips go. The sandbox only allows writing to places the user picks here.
@MainActor
enum ExportPanels {
    static func saveFile(suggestedName: String, fileExtension: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = UTType(filenameExtension: fileExtension).map { [$0] } ?? []
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Choose one file with this extension (a `.reprise` backup).
    static func openFile(fileExtension: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = UTType(filenameExtension: fileExtension).map { [$0] } ?? []
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
