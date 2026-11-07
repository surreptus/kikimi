import Foundation
import GRDB

/// The spellings of common verbs and the verbs they belong to, read in place from a dictionary file's `forms` table
/// (built from Wiktionary, and only for verbs with several meanings). A tagger that reads `puede` as `podar` is checked
/// against it: `puede` is a form of `poder`, and no common verb called `podar` has that spelling.
/// Opened on first use. A file without the table, or one that will not open, simply knows no forms.
public final class VerbForms: @unchecked Sendable {
    private let open: @Sendable () -> (queue: DatabaseQueue, hasSole: Bool)?
    private let lock = NSLock()
    private var opened: (queue: DatabaseQueue, hasSole: Bool)??   // nil until tried; .some(nil) when there is nothing to read
    private var cache: [String: (lemmas: [String], sole: Bool)] = [:]

    /// The file named `resource` in the package's dictionaries folder.
    public convenience init(resource: String, bundle: Bundle? = nil) {
        self.init { (bundle ?? .module).url(forResource: resource, withExtension: "sqlite", subdirectory: "dictionaries") }
    }

    /// A dictionary file at `url`.
    public convenience init(url: URL) { self.init { url } }

    private init(locate: @escaping @Sendable () -> URL?) {
        open = {
            guard let url = locate() else { return nil }
            var configuration = Configuration()
            configuration.readonly = true
            guard let queue = try? DatabaseQueue(path: url.path, configuration: configuration),
                  let columns = try? queue.read({ try $0.tableExists("forms") ? try $0.columns(in: "forms").map(\.name) : [] }),
                  !columns.isEmpty else { return nil }
            return (queue, columns.contains("sole"))
        }
    }

    /// The common verbs `form` can be a form of, the one with the most meanings first. Empty when it is no common verb's.
    public func lemmas(for form: String) -> [String] { entry(for: form).lemmas }

    /// Whether `form` is a verb form and nothing else: no word of its own is spelt that way, so a tagger that calls it an
    /// adverb or a noun is wrong. False for a file built before the table said so.
    public func isOnlyAVerbForm(_ form: String) -> Bool { entry(for: form).sole }

    private func entry(for form: String) -> (lemmas: [String], sole: Bool) {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[form] { return cached }
        if opened == nil { opened = .some(open()) }
        var found: (lemmas: [String], sole: Bool) = ([], false)
        if let (queue, hasSole) = opened ?? nil,
           let row = try? queue.read({ try Row.fetchOne($0, sql: "SELECT lemmas, \(hasSole ? "sole" : "0 AS sole") FROM forms WHERE form = ?", arguments: [form]) }) {
            let lemmas: String = row["lemmas"]
            found = (lemmas.split(separator: ",").map { String($0.split(separator: ":").first ?? "") }, (row["sole"] as Int) == 1)
        }
        cache[form] = found
        return found
    }
}
