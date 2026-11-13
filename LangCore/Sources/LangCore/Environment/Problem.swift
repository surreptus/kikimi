import Foundation

/// An error with two texts: `errorDescription` says in plain words what happened and what to do next, and `detail` keeps
/// the technical text for the learner to copy into a bug report.
public protocol DetailedError: LocalizedError {
    var detail: String { get }
}

/// What the learner sees when something fails: a plain message, and the raw detail behind "Show details".
public struct Problem: Equatable, Sendable {
    public let message: String
    public let detail: String

    public init(message: String, detail: String) {
        self.message = message
        self.detail = detail
    }

    /// An error of ours supplies its own message. Anything else (a system or database error) gets `fallback`, which the
    /// caller writes for the step that failed, and its raw text goes to `detail`.
    public init(_ error: Error, fallback: String) {
        if let own = error as? any DetailedError, let message = own.errorDescription {
            self.init(message: message, detail: own.detail)
        } else {
            self.init(message: fallback, detail: Self.rawDetail(of: error))
        }
    }

    /// The type, then the text the system gives, and its domain and code when it has them.
    public static func rawDetail(of error: Error) -> String {
        let ns = error as NSError
        var text = "\(type(of: error)): \(error.localizedDescription)"
        if ns.domain != "" { text += " (\(ns.domain) \(ns.code))" }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { text += "\n\(rawDetail(of: underlying))" }
        return text
    }
}
