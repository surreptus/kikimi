import Foundation

/// MeCab with the few corrections that spoken, unpunctuated text needs. A transcript has no commas, and IPADIC reads
/// the very common "Xはね" ("それはね…", "私はね…": the particles は and ね) as a form of the verb はねる (to bounce).
public struct JapaneseTokenizer: WordTokenizer {
    let base: any WordTokenizer

    public init(_ base: any WordTokenizer) { self.base = base }

    public func tokens(in text: String) -> [Token] {
        Self.fixed(base.tokens(in: text))
    }

    /// Particles that come before a verb, so a はね after one of them really is the verb ("水をはねる").
    private static let particles: Set<String> = ["が", "を", "に", "で", "と", "も", "の", "へ", "や", "か", "から", "まで", "より"]
    /// What follows a verb stem, so a はね before one of them really is the verb ("はねて", "はねた").
    private static let verbEndings: Set<String> = ["て", "で", "た", "だ", "ない", "ず", "ます", "ませ", "ば", "そう", "なかっ", "たい", "れ", "られ", "さ", "せ"]

    static func fixed(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        for (index, token) in tokens.enumerated() {
            guard token.surface == "はね", token.pos == .verb, let before = result.last, !particles.contains(before.surface) else {
                result.append(token); continue
            }
            if index + 1 < tokens.count, verbEndings.contains(tokens[index + 1].surface) { result.append(token); continue }
            result.append(Token(surface: "は", lemma: "は", pos: .other))
            result.append(Token(surface: "ね", lemma: "ね", pos: .other))
        }
        return result
    }
}
