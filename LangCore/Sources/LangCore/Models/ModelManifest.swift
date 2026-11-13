import CryptoKit
import Foundation

/// The one fixed version of the speech models Kikimi downloads, and a SHA-256 value for each large file in it.
/// `Scripts/update_model_manifest.py` writes `ModelManifest.json`. Only files stored with Git LFS have a SHA-256 value,
/// so only those are listed.
public struct ModelManifest: Decodable, Sendable, Equatable {
    public struct File: Decodable, Sendable, Equatable {
        /// Relative to the variant folder.
        public let path: String
        public let size: Int64
        public let sha256: String
    }

    /// The Hugging Face repository, for example `argmaxinc/whisperkit-coreml`.
    public let repo: String
    /// The full commit name that every download uses, never a branch.
    public let commit: String
    public let variants: [String: [File]]

    public static let bundled: ModelManifest = {
        guard let url = Bundle.module.url(forResource: "ModelManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ModelManifest.self, from: data)
        else { fatalError("ModelManifest.json is missing or broken. Run Scripts/update_model_manifest.py.") }
        return manifest
    }()

    /// The large files of a variant, or nil when Kikimi has no checked version of it.
    public func files(for variant: String) -> [File]? { variants[variant] }
}

/// Checks downloaded model files against a manifest.
enum ModelVerifier {
    /// Files that are present and wrong. Each one is deleted, so it can never be used and the next download fetches it again.
    /// A file that is absent is not reported here: the caller finds missing files.
    static func deleteMismatches(of files: [ModelManifest.File], in folder: URL) -> [String] {
        var bad: [String] = []
        for file in files {
            let url = folder.appending(path: file.path)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else { continue }
            // The size is cheap to read, so it goes first. Only a file of the right size is read in full.
            if size != file.size || sha256(of: url) != file.sha256 {
                try? FileManager.default.removeItem(at: url)
                bad.append(file.path)
            }
        }
        return bad
    }

    /// Reads the file in blocks, so a 1 GB weight file never sits in memory.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            // Nil data means the end of the file. A thrown error means a failed read.
            let more: Bool? = autoreleasepool {
                do {
                    guard let block = try handle.read(upToCount: 4 << 20), !block.isEmpty else { return false }
                    hasher.update(data: block)
                    return true
                } catch { return nil }
            }
            guard let more else { return nil }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
