import Foundation

/// The forms a Japanese verb or adjective takes before a suffix, as explained in Tsumiki
/// (https://surreptus.github.io/tsumiki/), a guide that models Japanese grammar as function composition.
/// A word in a transcript is shown in one of these forms; this says which, so the app can point to the page that
/// explains how it is built and what attaches to it.
public enum TsumikiStem: String, CaseIterable, Sendable {
    case gokan, mizenkei, renyokei, ishikei, kateikei, meireikei
    case taStem = "ta_stem", teStem = "te_stem"

    public static let site = URL(string: "https://surreptus.github.io/tsumiki/")!

    /// The page for this form on the site.
    public var url: URL { Self.site.appending(path: "reference/stems/\(rawValue)/") }

    /// The form's name as Japanese grammar books write it.
    public var name: String {
        switch self {
        case .gokan: "語幹"
        case .mizenkei: "未然形"
        case .renyokei: "連用形"
        case .ishikei: "意志形"
        case .kateikei: "仮定形"
        case .meireikei: "命令形"
        case .taStem: "た形"
        case .teStem: "て形"
        }
    }

    /// What learners call it, as Tsumiki does.
    public var label: String {
        switch self {
        case .gokan: String(localized: "the adjective stem", bundle: .module)
        case .mizenkei: String(localized: "the ない-stem", bundle: .module)
        case .renyokei: String(localized: "the ます-stem", bundle: .module)
        case .ishikei: String(localized: "the う-stem", bundle: .module)
        case .kateikei: String(localized: "the ば-stem", bundle: .module)
        case .meireikei: String(localized: "the command form", bundle: .module)
        case .taStem: String(localized: "the た-form", bundle: .module)
        case .teStem: String(localized: "the て-form", bundle: .module)
        }
    }

    /// Which form a word is in, from the inflection IPADIC reports (活用形). nil for the dictionary form and for words
    /// that don't inflect, since there is nothing to explain. Every inflected い-adjective form hangs off the adjective
    /// stem in Tsumiki, so those all point to 語幹.
    public static func stem(forInflection inflection: String?, pos: PartOfSpeech) -> TsumikiStem? {
        guard let inflection, !inflection.isEmpty else { return nil }
        if inflection.hasSuffix("基本形") || inflection == "体言接続" { return nil }
        if pos == .adjective { return .gokan }
        guard pos == .verb else { return nil }
        switch inflection {
        case "未然形", "未然ヌ接続", "未然レル接続": return .mizenkei
        case "未然ウ接続": return .ishikei
        case "連用形", "連用ニ接続", "連用ゴザイ接続": return .renyokei
        case "連用タ接続": return .taStem       // 行っ, 食べ before た or て; the た-form page covers the shared sound change
        case "連用テ接続": return .teStem
        case "仮定形", "仮定縮約１", "仮定縮約２": return .kateikei
        case "命令ｅ", "命令ｙｏ", "命令ｒｏ", "命令ｉ": return .meireikei
        default: return nil
        }
    }

    public static func stem(for token: Token) -> TsumikiStem? { stem(forInflection: token.inflection, pos: token.pos) }
}
