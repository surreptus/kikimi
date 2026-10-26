# Architecture

A map for finding your way around. The [README](README.md) says what the app does and how to build it.

## The one rule

All logic lives in `LangCore/` (a Swift package with no UI). `Kikimi/` holds SwiftUI views only and calls into
`LangCore` through one object, `LangEnvironment`. If you are adding behaviour, it almost certainly belongs in
`LangCore`, with a test.

Shared code never checks a language code such as `"ja"`. It asks the `LanguageProfile`.

## Where to start reading

1. `LangCore/Sources/LangCore/Environment/LangEnvironment.swift`: the front door. It owns the database, the
   dictionaries, the model manager and the import queue, and is what the views hold.
2. `Profiles/LanguageProfile.swift`: everything that differs between languages.
3. `Import/ImportPipeline.swift`: the most important flow. `importVideo` reads as a list of steps.
4. `Kikimi/RootView.swift`, then the view for the screen you care about.

## LangCore, by folder

| Folder | What it holds |
|---|---|
| `Profiles/` | `LanguageProfile` and the Spanish and Japanese profiles; `LanguageProfiles.all` is the registry. |
| `Tokenizing/` | Turns a line of text into content words (lemma and part of speech). Spanish uses Apple's `NaturalLanguage`; Japanese uses the vendored MeCab (`Sources/CMeCab`). |
| `Dictionary/` | `DictionaryStore` reads the bundled dictionary files in place, read-only. They are never copied into the database. |
| `Database/` | GRDB records, migrations (`LangMigrations`) and queries. Schema changes are new migrations only. |
| `Import/` | The import pipeline, queue, transcription, video compaction and the language check. |
| `Models/` | Speech-model download, listing and removal (`ModelManager`), plus `ModelCatalog` (sizes and notes). |
| `SRS/`, `Review/` | The nine review stages and their intervals; review sessions and sentence audio; the overview (ready, coming up, words per stage). |
| `Playback/` | The player controller, subtitle timeline and word hints. |
| `Export/` | Audio and video clip export. |
| `Resources/Localizable.xcstrings` | Strings shown to the user from this package (errors, titles). The app's own are in `Kikimi/Localizable.xcstrings`. |
| `Coverage/` | How much of a video you know (`VideoCoverage`, `LevelFit`), the shortest word list that reaches a target (`wordsToReach`), and marking a list of known words. |
| `Backup/` | `ProgressBackup`: the `.kikimi` file (readable JSON), export, preview and merge-on-restore that never overwrites existing progress. |
| `Environment/` | `LangEnvironment` and where videos live on disk. |

## The import pipeline

`ImportPipeline.importVideo` calls one small method per step, in this order:

`stage` (copy the original) → `confirmLanguage` → `transcribe` → `makeLibraryFiles` (compact video, verify) → `moveIntoLibrary` → `save` (one database transaction) → delete the staged copy.

The original is only read. Any failure removes only what this import created. Tests inject a failure at each step
and check the original is unchanged. `ImportQueue` runs imports one at a time for the UI and reports status.

The two hardest files are `AVFoundationTranscoder.swift` (it starts with a reading guide) and `ImportPipeline.swift`.

## The website

`site/` is an [Astro](https://astro.build) project of static pages (home, privacy, terms) in the app's colours, with no client
script. The privacy and terms pages import `Kikimi/Privacy.md` and `Kikimi/Terms.md` directly, so there is one copy
of each. `.github/workflows/site.yml` builds it and deploys to GitHub Pages.

## The app

`KikimiApp` → `RootView` (floating nav plus the current section). `AppState` holds which section is showing and
the Words screen's search, filter and selection, so they survive switching screens.

| View | Screen |
|---|---|
| `WordsView`, `WordTable`, `WordDetailView` | Search and bulk actions; the hand-built word table (square rows, keyboard selection); the inspector |
| `ReviewView`, `ReviewOverviewView` | The review overview, then spaced-repetition cards |
| `VideosView`, `ImportSection` | Add videos (drop zone, model choice and download, import progress), then your videos: details, delete |
| `PlayerView`, `SubtitleRow` | Playback with clickable subtitles; one subtitle line |
| `StorageView` | Downloaded models and videos, with removal |
| `SettingsView`, `BackupModel` | The ⌘, window: a standard Mac settings window with icon tabs General, Languages, Data (save and restore progress, via LangCore's `ProgressBackup`), About |
| `AppCommands` | The menu bar: Add Videos, Storage, the Go menu (pages and Find Words), Help pages; Export and Import Progress open Settings on the Data tab |

`Theme.swift` is the design system: one colour field for the whole window, a monotone ink accent, pill buttons and flat panels. `SideNav` is the left strip, and `Modal.swift` shows panels that close on an outside click. Use these rather than styling views ad hoc.

## Data on disk

Everything is in the app container, never the repo: `Application Support/Kikimi/` holds `Library/` (videos and
audio, one folder per content hash), `Staging/` (temporary), `models/` (speech models) and the SQLite database.

## Tests

`cd LangCore && swift test`. The tests are the best examples of how each part is used. Anything needing a real
model or file is opt-in through environment variables listed in the README. There are no UI tests; the views are
checked by building and by rendered previews.

## Adding a language

Write a profile, add it to `LanguageProfiles.all`, add a dictionary build script. See the README.
