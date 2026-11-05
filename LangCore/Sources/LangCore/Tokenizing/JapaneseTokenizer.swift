import Foundation

/// MeCab with the few corrections that spoken, unpunctuated text needs, found by running common lines through it:
/// - A transcript has no commas, and IPADIC reads the very common "Xはね" ("それはね…", "私はね…": the particles は and ね)
///   as a form of the verb はねる (to bounce).
/// - 行っ (行った, 行って) is taken as 行う (to carry out) when it is nearly always 行く (to go), unless it follows を.
/// - A hiragana verb stem right before だ or です ("あしたはやすみだよ") is a noun (a day off), not the verb.
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

    /// What follows a noun used as the thing being said: "やすみだ", "やすみです".
    private static let copulas: Set<String> = ["だ", "です", "でし", "だっ"]

    private static func isHiragana(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) } }

    static func fixed(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        for (index, token) in tokens.enumerated() {
            if token.surface == "行っ", token.lemma == "行う", result.last?.surface != "を" {
                result.append(Token(surface: token.surface, lemma: "行く", pos: token.pos, reading: token.reading, inflection: token.inflection))
                continue
            }
            if token.pos == .verb, token.inflection == "連用形", token.surface.allSatisfy(Self.isHiragana),
               index + 1 < tokens.count, copulas.contains(tokens[index + 1].surface) {
                result.append(Token(surface: token.surface, lemma: token.surface, pos: .noun))
                continue
            }
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
