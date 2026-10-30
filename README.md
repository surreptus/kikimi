# Kikimi

A native macOS app for learning a language from videos you already own.

Drop in a video. Kikimi transcribes it on your Mac, finds the words you'll meet, and helps you learn them with
spaced repetition, using real sentences from your own videos. Spanish, French, German and Japanese work today.

- **Local files only.** Nothing is downloaded from video sites, ever.
- **On-device.** Transcription runs on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). The
  only network use is downloading a speech model the first time you need it.
- **Your originals are never modified or deleted.**

## What it does

- **Videos.** Transcribed with timestamps; each shows how much of it you already know, and one button starts
  learning the words that would take it to about 90%.
- **Player.** Clickable, synced subtitles with meanings, furigana, line looping, clips, and translations when you
  ask for them (made on your Mac).
- **Words.** A searchable table with dictionary entries, example lines and Anki export. For Japanese, every reading
  of a word and each kanji with its on'yomi and kun'yomi.
- **Review.** Nine-stage spaced repetition with fill-in-the-blank and listening cards.
- **Your progress** saves to a `.kikimi` file you can restore later; it never overwrites what you already have.

## Install

Releases aren't signed with an Apple Developer ID or notarized yet, so macOS blocks a downloaded copy the first
time. This is Gatekeeper, not a damaged file. With a `Kikimi.zip`:

1. Unzip it and drag **Kikimi** into Applications.
2. Open it. macOS says it can't verify the app. Click **Done**.
3. Open **System Settings > Privacy & Security**, scroll to the message about Kikimi, click **Open Anyway** and
   confirm.

Or remove the download flag once in Terminal, then open it normally:

```bash
xattr -dr com.apple.quarantine /Applications/Kikimi.app
```

Do this only for a copy you trust. Each release lists a SHA-256 to check the download against. Building from
source avoids all of this.

## Build from source

Needs macOS 26 or later (Apple silicon recommended), Xcode 27, Python 3, and network access. The dictionaries are
large generated files, so they aren't in the repository. Build them once:

```bash
Scripts/build_ipadic.sh         # Japanese tokenizer dictionary (~50 MB)
Scripts/build_dictionaries.sh   # JMdict, KANJIDIC2, Spanish, French and German (~2.5 GB download)
```

Then open `Kikimi.xcodeproj`, pick the **Kikimi** scheme and **My Mac**, and press ⌘R. On the Videos page, download
a speech model (about 1.5 GB for Spanish, French and German, 3 GB for Japanese), then drop in a video.

Tests: `cd LangCore && swift test`.

## More

- [`ARCHITECTURE.md`](ARCHITECTURE.md): where things live, the import pipeline, tests, adding a language.
- [`ROADMAP.md`](ROADMAP.md) and [`AGENTS.md`](AGENTS.md): what comes next, and how we work.
- [`Release/CHECKLIST.md`](Release/CHECKLIST.md): shipping. The bundle identifier is `com.surreptus.Kikimi`.
- [Privacy policy](Kikimi/Privacy.md) and [terms of use](Kikimi/Terms.md), shown in the app and on the website.

## Licences

The app's code is under the [MIT licence](LICENSE). Dictionary data comes from JMdict and KANJIDIC2 (EDRDG) and
English Wiktionary via kaikki.org, all CC BY-SA 4.0, and the built files stay under that licence, so they are built
from scripts rather than committed. Speech models are OpenAI Whisper converted by Argmax; Japanese tokenizing uses
[MeCab](https://taku910.github.io/mecab/) with IPADIC. [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists every
component, and the licence texts are in the app under Acknowledgements.

## Known limits

- Accuracy depends on the model and the audio. `medium` scored about 23% word error rate on a long synthesized
  Spanish passage and hasn't been benchmarked for French or German.
- Whisper's timestamps are coarse in fast, overlapping speech, so sentence clips there can start or end slightly off.
- French lemmas are noisier than German ones, and a German separable verb ("ruf ... an") is learned as `rufen`.
- IPADIC dates from 2007, so modern Japanese slang is sometimes split or missed.
- Audio-only files aren't supported. The UI has had limited hands-on testing.
