import XCTest
@testable import LangCore

final class JapaneseTokenizerTests: XCTestCase {
    let ja = JapaneseProfile()

    private func content(_ text: String) -> [String: PartOfSpeech] {
        var result: [String: PartOfSpeech] = [:]
        for t in ja.contentWords(in: text) { result[t.lemma] = t.pos }
        return result
    }

    func testPrintSample() {
        for line in sampleLines {
            print(line, "→", ja.contentWords(in: line).map { "\($0.surface)=\($0.lemma)/\($0.pos)" })
        }
    }

    func testVerbsReturnDictionaryForm() {
        XCTAssertEqual(content("昨日は友達と一緒に新しいレストランへ行きました。")["行く"], .verb)
        XCTAssertEqual(content("もう食べられないよ。")["食べる"], .verb)
        XCTAssertEqual(content("新聞を読んでいます。")["読む"], .verb)
        XCTAssertEqual(content("傘を持って行ったほうがいいよ。")["持つ"], .verb)
        XCTAssertEqual(content("彼が来なかったら、中止になるだろう。")["来る"], .verb)
        XCTAssertEqual(content("宿題を忘れてしまった。")["忘れる"], .verb)
    }

    func testAdjectivesReturnDictionaryForm() {
        XCTAssertEqual(content("その映画はとても面白かったけど")["面白い"], .adjective)
        XCTAssertEqual(content("昨日は新しいレストランへ行きました。")["新しい"], .adjective)
        XCTAssertEqual(content("どうしてそんなに静かなの？")["静か"], .adjective)
        XCTAssertEqual(content("カメラがきれいです。")["きれい"], .adjective)
    }

    func testAdverbsAndNouns() {
        XCTAssertEqual(content("ゆっくり歩いて、駅まで行きましょう。")["ゆっくり"], .adverb)
        XCTAssertEqual(content("とても面白かった。")["とても"], .adverb)
        let nouns = content("先生に宿題を出すのを忘れてしまった。")
        XCTAssertEqual(nouns["先生"], .noun)
        XCTAssertEqual(nouns["宿題"], .noun)
        XCTAssertEqual(content("このスマートフォンは高いけど、カメラがきれいです。")["カメラ"], .noun)
    }

    func testFunctionWordsAreExcluded() {
        let words = Set(ja.contentWords(in: "私は日本語を勉強していますが、まだ上手に話せません。").map(\.surface))
        for particle in ["は", "を", "が", "に", "ます", "ませ", "ん", "て"] {
            XCTAssertFalse(words.contains(particle), particle)
        }
        XCTAssertFalse(words.contains("い"), "auxiliary いる is not a content verb")
    }

    func testEveryLineYieldsContentWords() {
        for line in sampleLines {
            XCTAssertFalse(ja.contentWords(in: line).isEmpty, line)
        }
    }

    func testNaturalLanguageBaselineWasUnusable() {
        // Documents why MeCab replaced NLTagger: it tags every Japanese word OtherWord, so nothing survives filtering.
        let nl = NLTaggerTokenizer(language: .japanese)
        XCTAssertTrue(nl.contentTokens(in: sampleLines[0], matching: ja.contentPOS).isEmpty)
    }

    func testConcurrentUseIsSafe() async {
        await withTaskGroup(of: Int.self) { group in
            for line in sampleLines {
                group.addTask { JapaneseProfile().contentWords(in: line).count }
            }
            for await count in group { XCTAssertGreaterThan(count, 0) }
        }
    }

    let sampleLines = [
        "昨日は友達と一緒に新しいレストランへ行きました。",
        "その映画はとても面白かったけど、少し長すぎた。",
        "彼女は毎朝六時に起きて、コーヒーを飲みながら新聞を読んでいます。",
        "もう食べられないよ。お腹がいっぱいだ。",
        "どうしてそんなに静かなの？何かあったの？",
        "明日の会議には出席できないかもしれません。",
        "このスマートフォンは高いけど、カメラがきれいです。",
        "私は日本語を勉強していますが、まだ上手に話せません。",
        "雨が降っているから、傘を持って行ったほうがいいよ。",
        "先生に宿題を出すのを忘れてしまった。",
        "ゆっくり歩いて、駅まで行きましょう。",
        "彼が来なかったら、パーティーは中止になるだろう。",
    ]
}

import NaturalLanguage
