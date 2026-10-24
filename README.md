# Reprise

A native macOS app for learning a language from videos you already own.

Drop in a video file and the app transcribes it on your Mac, pulls out the words you'll meet, and lets you
look them up, mark the ones you know, and review the rest with spaced repetition, using real sentences from
your own videos. Spanish and Japanese work today; the design makes adding another language a small, contained job.

- **Local files only.** Nothing is downloaded from video sites, ever.
- **On-device.** Transcription runs on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit).
  The only network use is downloading a speech model the first time you need it.
- **Your originals are never modified or deleted.** See [Import pipeline](#import-pipeline).

## What it does

| | |
|---|---|
| **Videos** | Drag and drop videos. Each is transcribed with timestamps, and words (nouns, verbs, adjectives, adverbs) are extracted into a shared SQLite database. The spoken language is checked first, so a Japanese video can't silently be imported as Spanish. Your videos are listed below it with size, location and date added, and the way to delete the app's copy. Play a video with clickable, synced subtitles; hover a line for furigana and a word for its meaning. Export audio or video clips of any line, or of every example of a word. Each video shows how much of it you already know (and whether that is Hard, A stretch, Comfortable or Easy); sort by best fit, and one button starts learning the commonest words that would take it to about 90%. |
| **Words** | A sortable, searchable table with multi-select. Start learning, mark known, or reset many words at once. Each word shows its dictionary entry and example lines from your videos, with audio you can hear in place. |
| **Review** | Nine-stage spaced repetition (intervals 4h, 8h, 23h, 47h, 7d, 14d, 30d, 120d, then retired). A card shows a sentence from one of your videos, can speak it, and picks a different example each visit. |
| **Settings** | A standard Mac settings window (⌘,) with icon tabs: appearance; the speech model and sentence audio for each language; and Data, which saves your progress to a `.reprise` file and restores it (never overwriting progress you already have, with a preview first). |

## Requirements

- macOS 26 or later, Apple silicon recommended (Core ML runs the speech model)
- Xcode 27 (Swift 6.2 toolchain)
- Python 3 (standard library only), to build the dictionary files once
- Network access for the builds below and for the first speech-model download

## Build and run

The built dictionaries are large generated files, so they are not in the repository. Build them once:

```bash
Scripts/build_ipadic.sh         # Japanese tokenizer dictionary (clones MeCab at a pinned commit, ~50 MB)
Scripts/build_dictionaries.sh   # JMdict (~10 MB download) and the Spanish extract (~1 GB download)
```

Then open `Reprise.xcodeproj` in Xcode, pick the **Reprise** scheme and **My Mac**, and press ⌘R. The app reads the
bundled dictionaries in place (they are never copied into its database); on the **Import** tab, download a speech
model, then drop in a video.
Defaults are `medium` for Spanish and `large-v3` for Japanese (about 3 GB), and you can pick another per language.

The app is sandboxed. Its database, models and library live in its container,
`~/Library/Containers/<bundle id>/Data/Library/Application Support/Reprise/`.

## Tests

```bash
cd LangCore && swift test
```

If `xcode-select` points at the Command Line Tools, prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (XCTest needs Xcode's toolchain). The dictionary builders have
their own tests: `cd Scripts/dictionaries && python3 test_builders.py`.

`Scripts/check_leaks.sh` runs the same tests under macOS's `leaks` tool and fails if anything leaked. It covers `LangCore`, not the
SwiftUI app.

Some tests need real models or files, so they are opt-in and skipped by default:

| Variable | Runs |
|---|---|
| `LANGCORE_INTEGRATION=1` | Real WhisperKit transcription and language detection with the tiny model (downloads ~73 MB) |
| `LANGCORE_BENCHMARK=1` | Accuracy and speed on synthesized speech; with `LANGCORE_MODEL` and `LANGCORE_MODELS_DIR` to choose the model |
| `LANGCORE_FILE=<media>` | With the benchmark: transcribe or detect the language of one file (read-only) |
| `LANGCORE_COMPACT_FILE=<video>` | Report what the video compaction does to one file (read-only) |

## How it is organised

Two parts in one repository:

- **`LangCore/`**, a Swift package with no UI, and all the logic: language profiles, SRS, database (GRDB with
  migrations), tokenizing, the import pipeline, playback, clip export, and review sessions.
- **`Reprise.xcodeproj`** with **`Reprise/`**: the SwiftUI interface, app lifecycle, assets, entitlements and
  `Info.plist`. It contains no logic of its own; views call into `LangCore`.

### Language profiles

Everything language-specific sits behind the `LanguageProfile` protocol: language code, the code and default model
WhisperKit uses, a tokenizer (lemma and part of speech), which parts of speech count as content words, the dictionary
source, and display options. Shared code never checks a language code; it asks the profile.

To add a language: write a new profile type, add it to `LanguageProfiles.all`, and add a script that builds its
dictionary file. The `words` and `dictionary` tables are already keyed by language, so there is no schema change.
Check the tokenizer first: Apple's `NaturalLanguage` was fine for Spanish but returned no part of speech or lemma for
Japanese, which is why Japanese uses MeCab.

### Import pipeline

The original file is only ever read. Steps, in order:

1. Hash the file (duplicates are detected by content, not name) and copy it to a staging folder.
2. Check the spoken language against the chosen one. Failing here changes nothing.
3. Transcribe with WhisperKit (Whisper sound tags are removed).
4. Make the library copy: small HEVC is kept as is; otherwise low-bitrate HEVC with the short side at most 480 px.
   If re-encoding isn't smaller than the source, the original streams are copied instead.
5. Verify the output (opens, has a video track, duration matches), and save a compact AAC audio track.
6. Atomically move both into the library, then write all database rows in one transaction.
7. Only then delete the staged copy.

Any failure removes only the staging and temporary files. This is covered by tests that inject a failure at each step
and check the original is byte-identical.

## Data and licences

Transcription uses OpenAI Whisper models converted for Core ML by Argmax, downloaded at runtime.
Dictionary data is built from JMdict (EDRDG) and the English Wiktionary via kaikki.org, both **CC BY-SA 4.0**. The
built dictionary files are adaptations of that data and must stay under that licence with attribution, so they are
not committed; only the scripts that build them are. Japanese tokenizing uses a vendored copy of
[MeCab](https://taku910.github.io/mecab/) (BSD licence) with the IPADIC dictionary.

The licence texts are in `LangCore/Sources/LangCore/Resources/Licenses/` and are shown in the app under
**Acknowledgements**. The app's own code is under the [MIT licence](LICENSE); the dictionary data and the other components keep the licences above.

The privacy policy is [`Reprise/Privacy.md`](Reprise/Privacy.md); the app shows the same file (Privacy, in the nav footer), and
it is the text to publish where the App Store asks for a policy URL.

## Release

`Release/CHECKLIST.md` lists what to do before shipping, and `Scripts/release.sh` builds, exports and (optionally)
notarizes a release; use `--dry-run` to see the commands. Nothing in the repository is signed. The bundle identifier
is `com.surreptus.Reprise`.

## Status and known limits

- Accuracy depends on the model. On synthesized Spanish, `medium` scored about 23% word error rate on a long passage
  and 2% on a short one; the `tiny` model is poor. Real-world results vary with audio quality.
- Whisper's timestamps are coarse in some stretches (for example fast overlapping dialogue), so sentence clips there
  can start or end slightly off.
- IPADIC dates from 2007: modern loanwords and slang are sometimes split or missed. Japanese lemmas are good
  for everyday text.
- Spanish dictionary entries are for dictionary forms; typing an inflected form into search won't find it directly.
- Audio-only files aren't supported; the pipeline needs a video track.
- The UI has had limited hands-on testing; much of it was verified through builds, tests and rendered previews.
