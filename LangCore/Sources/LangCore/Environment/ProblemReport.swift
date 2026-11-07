import Foundation

/// The page Help > Report a Problem opens: a new issue on Kikimi's GitHub page, with the version numbers already typed into
/// the form. Nothing is attached and nothing is sent: the person reads and changes the text in their browser, and submits it
/// there or not. (The privacy policy says the same.)
public enum ProblemReport {
    public static let issuesURL = "https://github.com/surreptus/kikimi/issues/new"

    /// `app` is such as "0.15.2 (12)" and `system` such as "macOS 27.2".
    public static func url(app: String, system: String) -> URL? {
        // GitHub fills the form from `body`. The questions come first so the person can answer straight under them; the
        // versions go last, under a line, where they are easy to leave alone or delete.
        let body = """
            **What happened?**


            **What did you expect instead?**


            **Public page: leave out personal details.**

            ---
            Kikimi \(app) · \(system)
            """
        var components = URLComponents(string: issuesURL)
        components?.queryItems = [URLQueryItem(name: "body", value: body)]
        return components?.url
    }
}
