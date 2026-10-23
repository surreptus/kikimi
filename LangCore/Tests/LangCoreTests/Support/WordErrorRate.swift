import Foundation

/// Word error rate of a transcript against known text: (substitutions + deletions + insertions) / reference words.
enum WordErrorRate {
    /// Lowercased words with punctuation removed. Accents are kept unless `foldingAccents`.
    static func words(_ text: String, foldingAccents: Bool = false) -> [String] {
        var t = text.lowercased()
        if foldingAccents { t = t.folding(options: .diacriticInsensitive, locale: nil) }
        let junk = CharacterSet.punctuationCharacters.union(.symbols)
        return t.components(separatedBy: junk).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func rate(reference: String, hypothesis: String, foldingAccents: Bool = false) -> Double {
        let r = words(reference, foldingAccents: foldingAccents)
        let h = words(hypothesis, foldingAccents: foldingAccents)
        guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
        var previous = Array(0...h.count)
        for i in 1...r.count {
            var current = [i] + Array(repeating: 0, count: h.count)
            for j in 1...max(h.count, 1) where j <= h.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[h.count]) / Double(r.count)
    }
}
