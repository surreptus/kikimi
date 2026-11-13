# Architecture

This file shows where things live. The [README](README.md) says what the app does and how to build it.

## The one rule

All logic is in `LangCore/`, a Swift package with no UI. `Kikimi/` holds SwiftUI views only, and calls `LangCore` through one object,
`LangEnvironment`. New behaviour belongs in `LangCore`, with a test. Shared code never checks a language code such as `"ja"`. It
asks the `LanguageProfile`.

## Where to start reading

1. `Environment/LangEnvironment.swift`: the front door. It owns the database, the dictionaries, the model manager and the import
   queue. The views hold it.
2. `Profiles/LanguageProfile.swift`: everything that differs between languages.
3. `Import/ImportPipeline.swift`: the main flow. `importVideo` is a list of steps.
4. `Kikimi/RootView.swift`, then the view for the screen you need.

## LangCore, by folder

Paths are under `LangCore/Sources/LangCore/`.

| Folder | What it holds |
|---|---|
| `Profiles/` | `LanguageProfile`, the four profiles, and the registry `LanguageProfiles.all`. |
| `Tokenizing/` | Lines to content words (lemma, part of speech). Apple `NaturalLanguage` for Spanish, French and German. The vendored MeCab (`Sources/CMeCab`) for Japanese. A profile gives `TokenRules` (articles, interjections, cut-off words, names, verbs after "he" or "yo", a short list of conjunctions to learn) to correct the tagger. |
| `Dictionary/` | `DictionaryStore` and `KanjiStore` read the bundled files in place, read-only. `ReopeningReader` opens a file again, once, after a SQLite disk I/O error (the file changed while the app ran). `VerbForms` reads the `forms` table (verb spellings built from Wiktionary). The tokenizer uses it to correct verb lemmas (Spanish `puede` read as `podar`). |
| `Database/` | GRDB records, migrations (`LangMigrations`) and queries. A schema change is always a new migration. |
| `Import/` | The pipeline, queue, transcription and video compaction. `SubtitleParser` reads `.srt` and `.vtt`. `MediaCheck` refuses a file that macOS cannot open or that has no video. `SegmentSplitter` cuts a line longer than `maxSegmentSeconds` at its longest pause, using Whisper word times. |
| `Models/` | Speech-model download, check, listing and removal (`ModelManager`, `ModelCatalog`, `ModelManifest`). `ModelManifest.json` fixes the model version and holds a SHA-256 value for each LFS file. |
| `SRS/`, `Review/` | The eight stages, Finished, and their intervals. Review sessions. The cloze, typing and calibration logic. `ReviewShortcut` lists the keys a card offers. |
| `Playback/` | The player controller, subtitle timeline and word hints. |
| `Export/` | Audio and video clips. `AnkiExport` writes the Anki import file. |
| `Translation/` | On-device translation (macOS Translation framework, behind a protocol so tests use a stand-in). Results are in the `translations` table. |
| `Coverage/` | How much of a video you know (`VideoCoverage`, `LevelFit`), and `wordsToReach`. |
| `Backup/` | `ProgressBackup` (the `.kikimi` JSON file; a restore never overwrites progress) and `LibraryBackup` (the full-backup folder). |
| `Environment/` | `LangEnvironment`, the video locations, `TextScale`, and `LibraryReset` (moves the database, videos and staging into `Set Aside/`). |
| `Resources/` | Strings for this package, the built dictionaries, the IPADIC data and the licence texts. |

## The import pipeline

`ImportPipeline.importVideo` calls one method for each step:

`stage` (copy the original) → `confirmLanguage` → `transcribe` → `makeLibraryFiles` (compact, verify) → `moveIntoLibrary` →
`save` (one database transaction) → delete the staged copy.

The original is only read. A failure removes only what this import made. Tests inject a failure at each step and check that the
original is unchanged. `ImportQueue` runs imports one at a time for the UI.

Transcription asks Whisper for word times. `SegmentSplitter` then cuts long lines, and `TranscriptCleaner` removes sound tags and
empty segments.

The library copy is HEVC with the short side at most 480 px (a small video is kept as is). Sound is AAC. Sentence audio and clips
play from this copy. Settings > General > Video quality can keep the original file. The hardest files are
`AVFoundationTranscoder.swift` (it starts with a reading guide) and `ImportPipeline.swift`.

## The app

`KikimiApp` → `RootView` (nav strip and current section). `AppState` holds the current section and the Words screen state.

| View | Screen |
|---|---|
| `WordsView`, `WordTable`, `WordDetailView` | Search and bulk actions, the word table, the word panel |
| `ReviewView`, `ReviewOverviewView` | The Learn overview, then the cards |
| `VideosView`, `ImportSection` | Add videos, then the video list |
| `PlayerView`, `SubtitleRow` | Playback with clickable subtitles |
| `StorageView` | Models and videos, with removal |
| `SettingsView`, `BackupModel`, `StartOver` | The ⌘, window. The Data tab has backup, restore and the Danger zone (`StartOver` sets the library aside at the next launch). |
| `OnboardingView` | First launch |
| `AppCommands` | The menu bar |
| `VoiceRecorder` | Records the Shadow card to a temporary file. It deletes the file when the card ends or at the next launch. |
| `KeyboardSwitch` | Switches the typing card to a keyboard for the language, then restores the Mac keyboard |
| `Toast`, `AppState.showToast` | A short message over the window (4 s; 8 s for an error). Use it instead of a status line. |

`Theme.swift` is the design system: one colour field, a monotone ink accent, pill buttons, flat panels. `Theme.sized` and
`Theme.styled` make every font at the chosen text size. Use `Theme`, `SideNav` and `Modal.swift`. Do not style views one by one.

## The website

`site/` is an [Astro](https://astro.build) and [Starlight](https://starlight.astro.build) project: home, guide, FAQ, download and
changelog. The privacy, terms, acknowledgements and changelog pages import files from the repo, so there is one copy of each. Search
(Pagefind) is the only client script. The site loads nothing from other hosts. `.github/workflows/site.yml` builds it, and deploys
it to GitHub Pages when `main` changes.

## Data on disk

All data is in the app container, never in the repo. `Application Support/Kikimi/` holds `Library/` (videos and audio), `Staging/`
(temporary), `Models/` (speech models), `Set Aside/` (after Start over) and the SQLite database.

## Tests

Run `cd LangCore && swift test`. A test that needs a real model or file is opt-in through an environment variable, and skipped by
default. There are no UI tests. Check views by building and by rendering.

| Variable | Runs |
|---|---|
| `LANGCORE_INTEGRATION=1` | Real WhisperKit transcription and language detection (tiny model, about 73 MB download) |
| `LANGCORE_BENCHMARK=1` | Accuracy and speed on synthesized speech. Set `LANGCORE_MODEL` and `LANGCORE_MODELS_DIR`. |
| `LANGCORE_FILE=<media>` | With the benchmark: one file (read-only) |
| `LANGCORE_COMPACT_FILE=<video>` | What video compaction does to one file (read-only) |
| `LANGCORE_AUDIT=1` | The full dictionary audits (`DictionaryAuditTests`) |
| `KIKIMI_TOKEN_AUDIT=<folder>` | The tokenizer audit (`TokenAuditRunTests`) on the .srt and .vtt files in the folder. It reads the files only. The language is the file name prefix (`es-`), or `KIKIMI_AUDIT_LANG`. `KIKIMI_AUDIT_SAVE=<file>` writes a baseline. `KIKIMI_AUDIT_BASELINE=<file>` shows new and gone suspects. `KIKIMI_AUDIT_TOP=<n>` sets the list length. |

If `xcode-select` points at the Command Line Tools, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Other tests:
`python3 Scripts/dictionaries/test_builders.py`, `python3 -I Scripts/test_release_tools.py`, and `Scripts/check_leaks.sh` (the
`LangCore` tests under `leaks`; it does not cover the SwiftUI app).

## Adding a language

1. Write a profile and add it to `LanguageProfiles.all`.
2. Add a script that builds its dictionary.

The `words` and `dictionary` tables are keyed by language, so there is no schema change. Check the tokenizer first. Apple
`NaturalLanguage` gives good lemmas for Spanish, French and German, but not for Japanese. This is why Japanese uses MeCab.
