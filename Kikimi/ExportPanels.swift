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

    /// Choose one file with this extension (a `.kikimi` backup).
    static func openFile(fileExtension: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = UTType(filenameExtension: fileExtension).map { [$0] } ?? []
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Choose a `.kikimi` file, or a full backup folder.
    static func openBackup() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = UTType(filenameExtension: "kikimi").map { [$0] } ?? []
        panel.message = String(localized: "Choose a backup file, or a backup folder")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Choose a plain-text or CSV/TSV file (a list of words).
    static func openTextFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .tabSeparatedText]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export Here")
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
