import Foundation
import GRDB

/// The spellings of common verbs and the verbs they belong to, read in place from a dictionary file's `forms` table
/// (built from Wiktionary, and only for verbs with several meanings). A tagger that reads `puede` as `podar` is checked
/// against it: `puede` is a form of `poder`, and no common verb called `podar` has that spelling.
/// Opened on first use. A file without the table, or one that will not open, simply knows no forms.
public final class VerbForms: @unchecked Sendable {
    private let open: @Sendable () -> DatabaseQueue?
    private let lock = NSLock()
    private var queue: DatabaseQueue??   // nil until tried; .some(nil) when there is nothing to read
    private var cache: [String: [String]] = [:]

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
                  (try? queue.read { try $0.tableExists("forms") }) == true else { return nil }
            return queue
        }
    }

    /// The common verbs `form` can be a form of, the one with the most meanings first. Empty when it is no common verb's.
    public func lemmas(for form: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[form] { return cached }
        if queue == nil { queue = .some(open()) }
        let found: [String] = (try? queue??.read { db in
            try String.fetchOne(db, sql: "SELECT lemmas FROM forms WHERE form = ?", arguments: [form])
        })?.flatMap { $0 }
            .map { $0.split(separator: ",").map { String($0.split(separator: ":").first ?? "") } } ?? []
        cache[form] = found
        return found
    }
}
