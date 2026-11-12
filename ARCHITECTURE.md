# Architecture

This file shows where things live. The [README](README.md) says what the app does and how to build it.

## The one rule

All logic is in `LangCore/`, a Swift package with no UI. `Kikimi/` holds SwiftUI views only. The views call `LangCore` through
one object, `LangEnvironment`. New behavior belongs in `LangCore`, with a test.

Shared code never checks a language code such as `"ja"`. It asks the `LanguageProfile`.

## Where to start reading

1. `Environment/LangEnvironment.swift`: the front door. It owns the database, the dictionaries, the model manager and the import
   queue. The views hold it.
2. `Profiles/LanguageProfile.swift`: everything that differs between languages.
3. `Import/ImportPipeline.swift`: the main flow. `importVideo` is a list of steps.
4. `Kikimi/RootView.swift`, then the view for the screen you need.

## LangCore, by folder

Paths are under `LangCore/Sources/LangCore/`.

| Folder or file | What it holds |
|---|---|
| `Profiles/` | `LanguageProfile` and the four language profiles. `LanguageProfiles.all` is the registry. `LearningLanguages` is the set the person chose. |
| `Tokenizing/` | Turns a line into content words (lemma and part of speech). Spanish, French and German use Apple `NaturalLanguage`. Japanese uses the vendored MeCab (`Sources/CMeCab`). |
| `Dictionary/` | `DictionaryStore` and `KanjiStore` read the bundled files in place, read-only. Nothing is copied into the database. `ReopeningReader` opens a file again, once, if SQLite reports a disk I/O error (the file was replaced while the app ran). `VerbForms` reads the `forms` table (common verb spellings, built from Wiktionary). `NLTaggerTokenizer` uses it to correct wrong verb lemmas (Spanish `puede` read as `podar`) and to read spellings that are only verb forms (German `richtest`). |
| `Database/` | GRDB records, migrations (`LangMigrations`) and queries. A schema change is always a new migration. `LangDatabase+EditLine.swift` edits a subtitle line and finds its words again. `LangDatabase+Activity.swift` keeps the daily tally and the stats. |
| `Import/` | The pipeline, queue, transcription and video compaction. `SubtitleParser` reads `.srt` and `.vtt` and pairs them with videos by name. `MediaCheck` refuses a file that macOS cannot open or that has no video. `SegmentSplitter` cuts a transcript line longer than the profile's `maxSegmentSeconds` at its longest pause, using Whisper word times. |
| `Models/` | Speech-model download, listing and removal (`ModelManager`). `ModelCatalog` has sizes and notes. |
| `SRS/`, `Review/` | The nine stages and their intervals. Review sessions and sentence audio. `ClozeCard` and `Dictation` build the fill-in and typing cards. `Calibration` runs "Mark the words I know". `KnownCheck` samples known words. `ReviewShortcut` lists the keys a card offers, by state. |
| `Playback/` | The player controller, subtitle timeline and word hints. |
| `Export/` | Audio and video clip export. `AnkiExport` writes the Anki import file (tab-separated text). |
| `Translation/` | On-device translation with the macOS Translation framework. The translator is behind a protocol, so tests use a stand-in. Results are kept in the `translations` table. |
| `Coverage/` | How much of a video you know (`VideoCoverage`, `LevelFit`), the shortest word list that reaches a target (`wordsToReach`), and marking a list of known words. |
| `Backup/` | `ProgressBackup`: the `.kikimi` file (readable JSON), export, preview, and a restore that never overwrites progress. `LibraryBackup`: the full-backup folder (progress, transcripts, compressed videos). |
| `Environment/` | `LangEnvironment` and the video locations on disk. `TextScale` has the four text sizes and how they are saved. `LibraryReset` moves the database, videos and staging into `Set Aside/`. |
| `Resources/` | `Localizable.xcstrings` (strings from this package), the built dictionaries, the IPADIC data and the licence texts. |

## The import pipeline

`ImportPipeline.importVideo` calls one small method per step, in this order:

`stage` (copy the original) → `confirmLanguage` → `transcribe` → `makeLibraryFiles` (compact the video, verify) →
`moveIntoLibrary` → `save` (one database transaction) → delete the staged copy.

The original is only read. A failure removes only what this import made. Tests inject a failure at each step and check that the
original is unchanged. `ImportQueue` runs imports one at a time for the UI and reports status.

Transcription asks Whisper for word times. `SegmentSplitter` then cuts long lines. `TranscriptCleaner` removes sound tags and
empty segments.

The library copy: a small HEVC video is kept. Otherwise it becomes low-bitrate HEVC with the short side at most 480 px, unless
re-encoding is not smaller. Sound is AAC, copied if already small, otherwise about 64 kbps (48 for mono). Sentence audio and
clips play from this copy. There is no separate audio file. Settings > General > Video quality can keep the original file.

The two hardest files are `AVFoundationTranscoder.swift` (it starts with a reading guide) and `ImportPipeline.swift`.

## The app

`KikimiApp` → `RootView` (the nav strip and the current section). `AppState` holds the current section and the Words screen
state (search, filter, selection), so they survive a change of screen.

| View | Screen |
|---|---|
| `WordsView`, `WordTable`, `WordDetailView` | Search and bulk actions; the word table (square rows, keyboard selection); the word panel |
| `ReviewView`, `ReviewOverviewView` | The Learn overview, then the cards |
| `VideosView`, `ImportSection` | Add videos (drop zone, model download, progress), then the video list |
| `PlayerView`, `SubtitleRow` | Playback with clickable subtitles |
| `StorageView` | Downloaded models and videos, with removal |
| `SettingsView`, `BackupModel`, `StartOver` | The ⌘, window with tabs General, Languages, Data, About. The Data tab has backup and restore, and the Danger zone (`StartOver` sets the library aside at the next launch). |
| `OnboardingView` | First launch: languages, reading language, model download |
| `AppCommands` | The menu bar |
| `VoiceRecorder` | Records the Shadow card into a temporary file and deletes it when the card ends or at the next launch. It needs the microphone entitlement. |
| `KeyboardSwitch` | Switches the typing card to an installed keyboard for the language, then restores the Mac keyboard |
| `IconSegmentedPicker` | A row of choices with icons and names (VoiceOver reads full names) |
| `Toast`, `AppState.showToast` | A short message over the window. It goes after 4 s (8 s for an error). Use it instead of a status line. |

`Theme.swift` is the design system: one colour field for the window, a monotone ink accent, pill buttons and flat panels.
`Theme.sized` and `Theme.styled` make every font at the chosen text size. `SideNav` is the left strip. `Modal.swift` shows
panels that close on an outside click. Use these. Do not style views one by one.

## The website

`site/` is an [Astro](https://astro.build) and [Starlight](https://starlight.astro.build) project. It has the home page, the guide,
the FAQ, the download page and the changelog. The privacy, terms, acknowledgements and changelog pages import files from the repo
(`Kikimi/Privacy.md`, `Kikimi/Terms.md`, the licence texts, `CHANGELOG.md`), so there is one copy of each. Search (Pagefind) is the
only client script. The site loads nothing from other hosts. `.github/workflows/site.yml` builds it, and deploys it to GitHub
Pages when `main` changes.

## Data on disk

All data is in the app container, never in the repo. `Application Support/Kikimi/` holds `Library/` (videos and audio, one folder
per content hash), `Staging/` (temporary), `Models/` (speech models), `Set Aside/` (after Start over) and the SQLite database.

## Tests

Run `cd LangCore && swift test`. The tests are the best examples of how each part works. A test that needs a real model or file is
opt-in through environment variables, and is skipped by default. There are no UI tests. Check views by building and by rendering.

| Variable | Runs |
|---|---|
| `LANGCORE_INTEGRATION=1` | Real WhisperKit transcription and language detection with the tiny model (downloads about 73 MB) |
| `LANGCORE_BENCHMARK=1` | Accuracy and speed on synthesized speech. Set `LANGCORE_MODEL` and `LANGCORE_MODELS_DIR` to choose the model. |
| `LANGCORE_FILE=<media>` | With the benchmark: transcribe or detect the language of one file (read-only) |
| `LANGCORE_COMPACT_FILE=<video>` | Report what video compaction does to one file (read-only) |
| `LANGCORE_AUDIT=1` | The full dictionary audits (`DictionaryAuditTests`) |

If `xcode-select` points at the Command Line Tools, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. XCTest needs
the Xcode toolchain. The dictionary builders have their own tests: `python3 Scripts/dictionaries/test_builders.py`. The release
tools have tests too: `python3 -I Scripts/test_release_tools.py`. `Scripts/check_leaks.sh` runs the `LangCore` tests under the
macOS `leaks` tool. It does not cover the SwiftUI app.

## Adding a language

1. Write a profile and add it to `LanguageProfiles.all`.
2. Add a script that builds its dictionary.

The `words` and `dictionary` tables are keyed by language, so there is no schema change. Check the tokenizer first. Apple
`NaturalLanguage` gives good lemmas for Spanish, French and German, but not for Japanese. This is why Japanese uses MeCab.
