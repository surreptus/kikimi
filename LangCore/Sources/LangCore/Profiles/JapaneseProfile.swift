import Foundation

public struct JapaneseProfile: LanguageProfile {
    public init() {}

    public let code = "ja"
    public var displayName: String { Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "Japanese" }
    public let whisperCode = "ja"
    public let defaultModel = "openai_whisper-large-v3"
    public let tokenizer: any WordTokenizer = JapaneseProfile.sharedTokenizer
    public let dictionarySource = DictionarySource(
        resourceName: "dictionary-ja",
        attribution: "JMdict, EDRDG (CC BY-SA 4.0)")
    public let display = DisplaySettings(showsReadings: true)

    /// Loaded once; the model is large and immutable. A missing dictionary is a packaging error, so fail loudly.
    private static let sharedTokenizer: MeCabTokenizer = {
        guard let dictionary = Bundle.module.url(forResource: "ipadic", withExtension: nil) else {
            preconditionFailure("IPADIC dictionary is not in the bundle; run Scripts/build_ipadic.sh")
        }
        do { return try MeCabTokenizer(dictionaryDirectory: dictionary, interpret: interpretIPADIC) }
        catch { preconditionFailure("Cannot load IPADIC: \(error)") }
    }()

    /// IPADIC features: 品詞, 細分類1-3, 活用型, 活用形, 原形, 読み, 発音. Unknown words have 7 fields.
    @Sendable static func interpretIPADIC(surface: String, features f: [String]) -> Token? {
        guard f.count >= 7 else { return nil }
        let lemma = f[6] == "*" ? surface : f[6]
        let pos: PartOfSpeech
        switch (f[0], f[1]) {
        case ("名詞", "一般"), ("名詞", "固有名詞"), ("名詞", "サ変接続"), ("名詞", "副詞可能"): pos = .noun
        case ("名詞", "形容動詞語幹"), ("名詞", "ナイ形容詞語幹"): pos = .adjective   // 静か, きれい
        case ("動詞", "自立"): pos = .verb
        case ("形容詞", "自立"): pos = .adjective
        case ("副詞", _): pos = .adverb
        default: pos = .other   // particles, auxiliaries, pronouns, numbers, suffixes, dependent verbs/nouns
        }
        // f[7] is the katakana reading of this exact surface form (so inflected 行き is いき, not いく).
        let reading = f.count > 7 && f[7] != "*" && Self.containsKanji(surface) ? Self.hiragana(fromKatakana: f[7]) : nil
        return Token(surface: surface, lemma: lemma, pos: pos, reading: reading, inflection: f[5] == "*" ? nil : f[5])
    }

    static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) || $0.value == 0x3005 }
    }

    /// カタカナ to ひらがな; the long-vowel mark ー and anything else is left alone.
    static func hiragana(fromKatakana text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60)! : scalar
        }))
    }
}
