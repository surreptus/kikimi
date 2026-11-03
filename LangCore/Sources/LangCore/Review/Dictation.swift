import Foundation

/// How a typed copy of a sentence compares with what was said: the sentence with what was missed marked, and what
/// was typed that isn't in it. A plain comparison of spelling, so it is only as right as the transcript line.
public struct DictationCheck: Equatable, Sendable {
    public enum Kind: Sendable { case same, missed, extra }

    public struct Piece: Equatable, Sendable {
        public let text: String
        public let kind: Kind
    }

    /// The line in order, a missed piece marked as such and each stray piece you typed shown where it fell.
    public let pieces: [Piece]
    /// How many of the line's pieces you got, out of how many it has.
    public let correct: Int
    public let total: Int
    public var isExact: Bool { correct == total && !pieces.contains { $0.kind == .extra } }

    public static func compare(typed: String, line: String, profile: any LanguageProfile) -> DictationCheck {
        let target = profile.dictationUnits(in: line), written = profile.dictationUnits(in: typed)
        let targetKeys = target.map(key), writtenKeys = written.map(key)

        // Longest common subsequence: the pieces you got in the right order.
        var table = Array(repeating: Array(repeating: 0, count: writtenKeys.count + 1), count: targetKeys.count + 1)
        for i in stride(from: targetKeys.count - 1, through: 0, by: -1) {
            for j in stride(from: writtenKeys.count - 1, through: 0, by: -1) {
                table[i][j] = targetKeys[i] == writtenKeys[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pieces: [Piece] = []
        var i = 0, j = 0
        while i < target.count || j < written.count {
            if i < target.count, j < written.count, targetKeys[i] == writtenKeys[j] {
                pieces.append(Piece(text: target[i], kind: .same)); i += 1; j += 1
            } else if j < written.count, i == target.count || table[i][j + 1] >= table[i + 1][j] {
                pieces.append(Piece(text: written[j], kind: .extra)); j += 1
            } else {
                pieces.append(Piece(text: target[i], kind: .missed)); i += 1
            }
        }
        return DictationCheck(pieces: pieces, correct: pieces.filter { $0.kind == .same }.count, total: target.count)
    }

    /// What two pieces are compared by: the same letters whatever the case, width or punctuation. Accents count.
    static func key(_ unit: String) -> String {
        String(String.UnicodeScalarView(
            unit.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars.filter { scalar in
                switch scalar.properties.generalCategory {
                case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
                     .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
                     .spaceSeparator, .lineSeparator, .paragraphSeparator: false
                default: true
                }
            }))
    }
}

extension LanguageProfile {
    /// The pieces a typed copy is compared in: the words of the line, or its characters for a language written
    /// without spaces. Punctuation alone is not a piece.
    public func dictationUnits(in text: String) -> [String] {
        text.split { $0.isWhitespace }.map(String.init).filter { !DictationCheck.key($0).isEmpty }
    }

    /// The most pieces a line can have to be offered for typing: longer ones are too much to hold in your head.
    public var dictationLimit: Int { 10 }
    public var dictationSeparator: String { " " }

    /// Short enough to type from hearing it once or twice: not long on the clock and not many pieces.
    public func suitsDictation(_ line: ExampleLine) -> Bool {
        let count = dictationUnits(in: line.text).count
        return line.endTime - line.startTime <= DictationLimits.maxSeconds && (1...dictationLimit).contains(count)
    }
}

public enum DictationLimits {
    public static let maxSeconds = 6.5
}
