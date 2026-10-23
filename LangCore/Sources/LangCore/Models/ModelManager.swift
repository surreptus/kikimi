import Foundation
import WhisperKit

public enum ModelError: Error, LocalizedError {
    case notInstalled(String)
    /// The download finished but files are missing (usually a dropped connection). Trying again resumes it.
    case incomplete(String, missing: [String])

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let model): "The speech model \(model) isn't downloaded yet."
        case .incomplete(let model, let missing):
            "The \(model) download didn't finish (missing \(missing.joined(separator: ", "))). Check your connection and download again."
        }
    }
}

/// Downloads Whisper models into `directory` (inside the app's container) and remembers where each landed.
public actor ModelManager {
    /// Fetches a model variant into `base` and returns its folder. Replaceable so retries can be tested offline.
    public typealias Downloader = @Sendable (_ variant: String, _ base: URL, _ progress: @escaping @Sendable (Double) -> Void) async throws -> URL

    /// Every file a usable model needs. WhisperKit can return from a dropped connection with some missing.
    static let requiredFiles = [
        "config.json",
        "AudioEncoder.mlmodelc/weights/weight.bin",
        "TextDecoder.mlmodelc/weights/weight.bin",
        "MelSpectrogram.mlmodelc/weights/weight.bin",
    ]

    public let directory: URL
    private let downloader: Downloader
    private var indexURL: URL { directory.appending(path: "installed.json") }

    public init(
        directory: URL,
        downloader: @escaping Downloader = { variant, base, progress in
            try await WhisperKit.download(variant: variant, downloadBase: base,
                                          progressCallback: { progress($0.fractionCompleted) })
        }
    ) {
        self.directory = directory
        self.downloader = downloader
    }

    static func missingFiles(in folder: URL) -> [String] {
        requiredFiles.filter { !FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
    }

    /// Folder of an installed model variant, or nil if it is missing or incomplete.
    public func installedFolder(for variant: String) -> URL? {
        guard let relative = loadIndex()[variant] else { return nil }
        let folder = directory.appending(path: relative)
        return Self.missingFiles(in: folder).isEmpty ? folder : nil
    }

    public func isInstalled(_ variant: String) -> Bool { installedFolder(for: variant) != nil }

    /// Downloads a model, retrying while files are missing (each retry resumes rather than starting over).
    @discardableResult
    public func download(
        variant: String, attempts: Int = 3, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var missing: [String] = []
        for _ in 0..<max(1, attempts) {
            let folder = try await downloader(variant, directory, progress)
            missing = Self.missingFiles(in: folder)
            if missing.isEmpty {
                var index = loadIndex()
                index[variant] = relativePath(of: folder)
                try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
                return folder
            }
        }
        // Don't leave a stale "installed" entry pointing at a broken folder.
        var index = loadIndex()
        index[variant] = nil
        try? JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
        throw ModelError.incomplete(variant, missing: missing)
    }

    private func loadIndex() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: indexURL))) ?? [:]
    }

    private func relativePath(of folder: URL) -> String {
        let base = directory.standardizedFileURL.path + "/"
        let path = folder.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }
}

/// Which Whisper model each language uses: the profile's default unless the user picked another.
public struct ModelPreferences: @unchecked Sendable {
    /// Variants offered in the UI, smallest to largest.
    public static let choices = [
        "openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small",
        "openai_whisper-medium", "openai_whisper-large-v3",
    ]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func model(for profile: any LanguageProfile) -> String {
        defaults.string(forKey: key(profile)) ?? profile.defaultModel
    }

    /// Pass nil to go back to the profile's default.
    public func setModel(_ variant: String?, for profile: any LanguageProfile) {
        defaults.set(variant, forKey: key(profile))
    }

    private func key(_ profile: any LanguageProfile) -> String { "whisperModel.\(profile.code)" }
}
