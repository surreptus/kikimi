# Kikimi

A native macOS app for learning a language from videos you already own.

Drop in a video. Kikimi transcribes it on your Mac, finds the words you'll meet, and helps you learn them with
spaced repetition, using real sentences from your own videos. Spanish, French, German and Japanese work today.

- **Local files only.** Nothing is downloaded from video sites, ever.
- **On-device.** Transcription runs on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). The
  only network use is downloading a speech model the first time you need it.
- **Your originals are never modified or deleted.** See [Import pipeline](#import-pipeline).

## What it does

- **Videos.** Drag in videos; each is transcribed with timestamps and its nouns, verbs, adjectives and adverbs are
  extracted. The spoken language is checked first, so a Japanese video can't be imported as Spanish. Each video shows
  how much of it you already know (Hard, A stretch, Comfortable or Easy); sort by best fit, and one button starts
  learning the commonest words that would take it to about 90%.
- **Player.** Clickable, synced subtitles: hover a word for its meaning, a line for furigana. Pause after each line
  or loop it (slower if you like), show its translation when you ask (made on your Mac by macOS), fix a line's text
  or timing, and export audio or video clips. For Japanese verbs and adjectives the word bar names the form and links
  to the matching page of [Tsumiki](https://surreptus.github.io/tsumiki/), a grammar guide.
- **Words.** A sortable, searchable table: start learning, mark known or reset many at once, and export to an Anki
  import file. Each word has its dictionary entry and example lines with audio. For Japanese it also lists every
  reading of the word (月: つき, がつ, げつ) and each kanji with its meaning and on'yomi/kun'yomi readings.
- **Review.** An overview (reviews ready, the next seven days, words at each stage, your progress), then nine-stage
  spaced repetition (4h, 8h, 23h, 47h, 7d, 14d, 30d, 120d, then retired). Cards ask for the word from its meaning,
  as a fill-in-the-blank sentence, or by ear; choose in Settings > Languages. "Check my known words" quizzes a
  sample of what you marked known and sends back any you miss.
- **First launch.** A welcome page asks which languages you are learning and which language you read, and offers to
  download each speech model now or later. Settings > Languages changes the choice; a dropped language is only
  hidden, and its words and videos are kept.
- **Settings (⌘,).** Appearance, the speech model and review options per language, and Data: save your progress to
  a `.kikimi` file (or a folder that includes videos and transcripts) and restore it. Restoring previews first and
  never overwrites progress you already have.

## Requirements

- macOS 26 or later, Apple silicon recommended (Core ML runs the speech model)
- Xcode 27 (Swift 6.2 toolchain)
- Python 3 (standard library only), to build the dictionary files once
- Network access for the builds below and for the first speech-model download

## Installing a build that isn't notarized

Releases are not signed with an Apple Developer ID or notarized yet, so macOS blocks a downloaded copy the first
time. This is Gatekeeper, not a damaged file. With a `Kikimi.zip`:

1. Unzip it and drag **Kikimi** into Applications.
2. Open it. macOS says it can't verify the app. Click **Done**.
3. Open **System Settings > Privacy & Security**, scroll to the message about Kikimi, click **Open Anyway** and
   confirm.

Or remove the download flag once in Terminal, then open it normally:

```bash
xattr -dr com.apple.quarantine /Applications/Kikimi.app
```

Do this only for a copy you trust, since it skips macOS's check. Building from source avoids it, and the code is
here to read. A notarized download will come when there is enough use to justify Apple's yearly fee.

## Build and run

The dictionaries are large generated files, so they are not in the repository. Build them once:

```bash
Scripts/build_ipadic.sh         # Japanese tokenizer dictionary (clones MeCab at a pinned commit, ~50 MB)
Scripts/build_dictionaries.sh   # JMdict, KANJIDIC2, and the Spanish, French and German extracts (~2.5 GB download)
```

Then open `Kikimi.xcodeproj` in Xcode, pick the **Kikimi** scheme and **My Mac**, and press ⌘R. On the Videos
page, download a speech model, then drop in a video. The default is `medium` for Spanish, French and German and
`large-v3` (about 3 GB) for Japanese; you can pick another per language.

The app is sandboxed. Its database, models and library live in
`~/Library/Containers/<bundle id>/Data/Library/Application Support/Kikimi/`.

## Tests

```bash
cd LangCore && swift test
```

If `xcode-select` points at the Command Line Tools, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
(XCTest needs Xcode's toolchain). The dictionary builders have their own tests:
`python3 Scripts/dictionaries/test_builders.py`. `Scripts/check_leaks.sh` runs the `LangCore` tests under macOS's
`leaks` tool and fails if anything leaked; it doesn't cover the SwiftUI app.

Tests that need real models or files are opt-in and skipped by default:

| Variable | Runs |
|---|---|
| `LANGCORE_INTEGRATION=1` | Real WhisperKit transcription and language detection with the tiny model (downloads ~73 MB) |
| `LANGCORE_BENCHMARK=1` | Accuracy and speed on synthesized speech; set `LANGCORE_MODEL` and `LANGCORE_MODELS_DIR` to choose the model |
| `LANGCORE_FILE=<media>` | With the benchmark: transcribe or detect the language of one file (read-only) |
| `LANGCORE_COMPACT_FILE=<video>` | Report what video compaction does to one file (read-only) |

## How it is organised

Three parts in one repository:

- **`LangCore/`**: a Swift package with no UI and all the logic: language profiles, SRS, the database (GRDB with
  migrations), tokenizing, the import pipeline, playback, clip export and review sessions.
- **`Kikimi.xcodeproj`** with **`Kikimi/`**: the SwiftUI interface, app lifecycle, assets and entitlements. It has
  no logic of its own; views call into `LangCore`.
- **`site/`**: the website, static pages built with [Astro](https://astro.build). Its privacy and terms pages are
  the app's own `Kikimi/Privacy.md` and `Terms.md`, so they can't differ. Run it with
  `cd site && npm install && npm run dev`. A workflow (`.github/workflows/site.yml`) publishes it to GitHub Pages
  once Pages is switched on (Settings > Pages > Source: GitHub Actions).

[`ARCHITECTURE.md`](ARCHITECTURE.md) says where things live in more detail.

### Language profiles

Everything language-specific sits behind the `LanguageProfile` protocol: language code, the WhisperKit code and
default model, a tokenizer (lemma and part of speech), which parts of speech count as content words, the dictionary
source and display options. Shared code never checks a language code; it asks the profile.

To add a language: write a profile, add it to `LanguageProfiles.all`, and add a script that builds its dictionary.
The `words` and `dictionary` tables are keyed by language, so there is no schema change. Check the tokenizer first:
Apple's `NaturalLanguage` gives good lemmas for Spanish, French and German, but none for Japanese, which is why
Japanese uses MeCab.

### Import pipeline

The original file is only ever read. In order:

1. Hash the file (duplicates are found by content, not name) and copy it to a staging folder.
2. Check the spoken language against the chosen one. Failing here changes nothing.
3. Transcribe with WhisperKit (Whisper's sound tags are removed).
4. Make the library copy: small HEVC is kept as is; otherwise low-bitrate HEVC with the short side at most 480 px.
   If re-encoding isn't smaller than the source, the original streams are copied.
5. Verify the output (it opens, has a video track, duration matches). Its sound is AAC: copied when already small,
   otherwise about 64 kbps (48 for mono), plenty for speech. Sentence audio and audio clips play from this copy.
6. Atomically move it into the library, then write all database rows in one transaction.
7. Only then delete the staged copy.

Any failure removes only staging and temporary files. Tests inject a failure at each step and check the original is
byte-identical. Settings > General > Video quality can keep your file as it is instead of compressing it.

## Data and licences

Transcription uses OpenAI Whisper models converted for Core ML by Argmax, downloaded at runtime. Dictionary data is
built from JMdict and KANJIDIC2 (EDRDG) and from English Wiktionary via kaikki.org, all **CC BY-SA 4.0**. The built
dictionary files are adaptations of that data and stay under that licence with attribution, so they are not
committed; only the scripts that build them are. Japanese tokenizing uses a vendored copy of
[MeCab](https://taku910.github.io/mecab/) (BSD) with the IPADIC dictionary.

[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists every component and its licence; the texts are in
`LangCore/Sources/LangCore/Resources/Licenses/` and shown in the app under Acknowledgements. The app's own code is
under the [MIT licence](LICENSE).

The privacy policy is [`Kikimi/Privacy.md`](Kikimi/Privacy.md) and the terms of use are
[`Kikimi/Terms.md`](Kikimi/Terms.md). The app shows both (Help menu, and Settings > About), and the website
publishes them at `/privacy/` and `/terms/`.

## Release

[`Release/CHECKLIST.md`](Release/CHECKLIST.md) lists what to do before shipping. `Scripts/release.sh` builds,
exports and optionally notarizes a release (`--dry-run` prints the commands). Nothing in the repository is signed.
The bundle identifier is `com.surreptus.Kikimi`.

## Status and known limits

- Accuracy depends on the model. On synthesized Spanish, `medium` scored about 23% word error rate on a long passage
  and 2% on a short one; `tiny` is poor. Real audio varies. `medium` hasn't been benchmarked for French or German.
- Whisper's timestamps are coarse in some stretches (fast, overlapping speech), so sentence clips there can start
  or end slightly off.
- IPADIC dates from 2007, so modern loanwords and slang are sometimes split or missed.
- French lemmas are noisier than German ones, and a German separable verb ("ruf ... an") is learned as `rufen`.
- Dictionary entries are for dictionary forms; typing an inflected form into search won't find it directly.
- Audio-only files aren't supported; the pipeline needs a video track.
- The UI has had limited hands-on testing; much of it was checked through builds, tests and rendered previews.
