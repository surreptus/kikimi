import Foundation
@testable import LangCore

extension ModelManifest {
    /// Variants that Kikimi may download, with no large files to check. For tests that use a fake downloader.
    static func unchecked(_ variants: String...) -> ModelManifest {
        ModelManifest(repo: "test/repo", commit: String(repeating: "0", count: 40),
                      variants: Dictionary(uniqueKeysWithValues: variants.map { ($0, []) }))
    }
}
