import Foundation

/// A version such as "0.14.0", compared number by number. Anything after a "-" (a pre-release tag) is ignored.
public struct AppVersion: Comparable, Equatable, Sendable {
    let parts: [Int]

    public init?(_ text: String) {
        let core = text.trimmingCharacters(in: .whitespaces).split(separator: "-").first.map(String.init) ?? ""
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    /// "1.0" and "1.0.0" are the same version.
    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        for i in 0..<count {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

/// What the small file on Kikimi's website says, and what to tell the learner about it. The file is
/// `{"version": "0.15.0", "url": "https://github.com/surreptus/kikimi/releases/latest"}`.
public enum UpdateCheck {
    public static let address = URL(string: "https://surreptus.github.io/kikimi/latest.json")!

    public enum Outcome: Equatable, Sendable {
        case upToDate
        case available(version: String, page: URL)
        case failed
    }

    private struct Latest: Decodable { let version: String; let url: URL }

    /// Only a page on GitHub is offered, so a damaged or tampered file can't send anyone elsewhere.
    private static let trustedHosts: Set<String> = ["github.com", "surreptus.github.io"]

    public static func outcome(current: String, latest data: Data) -> Outcome {
        guard let latest = try? JSONDecoder().decode(Latest.self, from: data),
              let newest = AppVersion(latest.version), let now = AppVersion(current),
              latest.url.scheme == "https", let host = latest.url.host, trustedHosts.contains(host) else { return .failed }
        return newest > now ? .available(version: latest.version, page: latest.url) : .upToDate
    }
}
