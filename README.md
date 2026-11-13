<p align="center">
  <a href="https://github.com/surreptus/kikimi/security/code-scanning"><img src="https://github.com/surreptus/kikimi/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
</p>

<h1 align="center">
  <img src="Kikimi/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="The Kikimi icon: a white asanoha star on dark green" width="64" height="64" align="absmiddle">
  Kikimi
</h1>

<p align="center">
  A native macOS app for learning a language from videos already on your Mac.
</p>

<p align="center">
  <a href="https://surreptus.github.io/kikimi/">Website</a> ·
  <a href="#install">Install</a> ·
  <a href="#what-it-does">What it does</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="ROADMAP.md">Roadmap</a>
</p>

---

Drop in a video. Kikimi transcribes it on your Mac and finds the words you will meet. Then it teaches you those words with
spaced repetition, using real sentences from your own videos. Spanish, French, German and Japanese work today.

- **Local files only.** Kikimi never downloads video.
- **On-device.** Transcription runs on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit).
- **Almost no network use.** It downloads a speech model when you first need one, and checks for a new version when you ask.
- **Your original files are never changed or deleted.**

## What it does

- **Videos.** Each video is transcribed, or imported with its own `.srt` or `.vtt` file (no speech model needed). Each one
  shows how much of it you already know. One button starts the words that bring a video to about 90%.
- **Player.** Clickable, synced subtitles with meanings and furigana. Loop a line, export clips, translate on request.
- **Words.** A searchable table with dictionary entries and example lines. Mark words known, learn, ignore or reset them, with
  undo. Japanese shows every reading and each kanji's readings, JLPT level and school year. Spanish, French and German
  nouns show their article. File > Export Words to Anki… makes a file Anki can import.
- **Learn.** Daily lessons, eight-stage spaced repetition and practice. Card types: meaning, fill in the word, listen, type what
  you hear, and Shadow (say the sentence aloud, then hear yourself beside the original).
- **Your progress** saves to a `.kikimi` file. A restore never overwrites what you already have.

## Install

1. Download the latest `Kikimi-….zip` from the [Releases page](https://github.com/surreptus/kikimi/releases/latest).
2. Unzip it and drag **Kikimi** into Applications.
3. The first time, macOS says it cannot verify the app, because Kikimi is not notarized yet. Click **Done**. Then open
   **System Settings > Privacy & Security**, find the message about Kikimi, click **Open Anyway** and confirm.

Each release lists a SHA-256 checksum for the download. Building from source avoids the warning.

<details>
<summary>Advanced: skip the warning from Terminal</summary>

<br>

```bash
xattr -dr com.apple.quarantine /Applications/Kikimi.app
```

This removes the download flag. Run it only for a copy you trust, because it skips the macOS check.

</details>

## Finding videos

Kikimi works on files you give it. For where to find videos you may use, see
[Finding material](https://surreptus.github.io/kikimi/guide/finding-material/). Use only videos you own or may copy and study
(see the [terms](Kikimi/Terms.md)).

## Build from source

Requirements: macOS 15 or later (Apple silicon recommended; translations need macOS 26), Xcode 27, Python 3, and network access.

The dictionaries are large generated files. They are not in the repository. Build them once:

```bash
Scripts/build_ipadic.sh         # Japanese tokenizer dictionary (~50 MB)
Scripts/build_dictionaries.sh   # JMdict, KANJIDIC2, Spanish, French and German (~2.5 GB download)
```

Then open `Kikimi.xcodeproj`, choose the **Kikimi** scheme and **My Mac**, and press ⌘R. On the Videos page, download a speech
model (about 1.5 GB; 1.6 GB for Japanese), then drop in a video.

Run the tests with `cd LangCore && swift test`.

## Security

CodeQL scans the Python scripts, the website and the Swift in `LangCore`. Dependabot watches the dependencies. These tools find
common mistakes. They do not prove the code is safe. See [SECURITY.md](SECURITY.md) to report a vulnerability in private.

## Licences

The app code uses the [MIT licence](LICENSE).

- **Dictionaries:** JMdict and KANJIDIC2 (EDRDG) and English Wiktionary via kaikki.org. All are CC BY-SA 4.0. The scripts
  build the dictionary files, so the files are not committed.
- **Speech models:** OpenAI Whisper, converted by Argmax.
- **Japanese word splitting:** [MeCab](https://taku910.github.io/mecab/) with IPADIC.

[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists every component. The licence texts are in the app, under
Acknowledgements.

## Known limits

- Transcription accuracy depends on the model and the audio. The `medium` model made about 23% word errors on one long
  synthesized Spanish passage. Japanese, French and German are not measured. Real speech is probably harder than synthesized
  speech, so expect more errors.
- Whisper timestamps are coarse in fast, overlapping speech. A sentence clip there can start or end slightly off.
- French lemmas are less accurate than German ones. A German separable verb ("ruf … an") is learned as `rufen`.
- IPADIC is from 2007. It can split or miss modern Japanese slang.
- Audio-only files, and subtitle tracks inside a video file, are not supported. WebM and MKV files do not open.
- The UI has had limited testing.

## More

- [`ARCHITECTURE.md`](ARCHITECTURE.md): where things live, the import pipeline, tests, how to add a language.
- [`ROADMAP.md`](ROADMAP.md) and [`AGENTS.md`](AGENTS.md): what comes next, and how we work.
- [`Release/CHECKLIST.md`](Release/CHECKLIST.md): how to ship. The bundle identifier is `com.surreptus.Kikimi`.
- [Privacy policy](Kikimi/Privacy.md) and [terms of use](Kikimi/Terms.md): shown in the app and on the website.
