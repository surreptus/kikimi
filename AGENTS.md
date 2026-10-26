# Working agreements

How we build Kikimi. Read this before changing anything; update it when we agree on a new way of working.
[ARCHITECTURE.md](ARCHITECTURE.md) says where things live, [ROADMAP.md](ROADMAP.md) says what comes next.

## What every change is measured against

1. **Mac app best practices.** Follow Apple's Human Interface Guidelines and platform conventions: a standard
   Settings window (⌘,), menu-bar commands with shortcuts, system colours and controls where they fit, Light and
   Dark, full-screen and window restoration, drag and drop, Open With. Target modern macOS only; no backwards
   compatibility shims. Sandbox and hardened runtime stay on.
2. **Dieter Rams.** Less, but better. Good design is useful, unobtrusive, honest, thorough and long-lasting. Remove
   embellishment; if a control isn't needed, it goes. This applies to the UI, to the code, and to how we report.
3. **Our promises.** The app must always match its [privacy policy](Kikimi/Privacy.md) and its terms of use. A
   feature that would change what data leaves the Mac, or what we say about it, changes the policy first.
4. **Comprehensible input.** Kikimi exists to help a learner apply comprehensible-input methodology as effectively
   as possible: lots of understandable material, slightly above their level, with the words they meet turning
   into words they know. A feature should make that loop faster or clearer. If it works against it (for example,
   a translation that is always showing), it is hidden until asked for.
5. **Small and fast.** Keep memory, disk and launch time low. Load things lazily, release what is not in use,
   read dictionaries in place, never copy data we can read where it lives. Measure before optimising and say what
   was measured. Check Release builds, not only Debug.
6. **Accessible and easy.** Everything works with the keyboard and VoiceOver, text is at least 12 pt (furigana
   excepted), contrast stays at 4.5:1 or better, colour is never the only signal, and Increase Contrast and
   Reduce Motion are honoured. The first-time experience should need no explanation.
7. **Local and private.** Local files only; nothing is downloaded from video sites. No accounts, analytics or
   tracking. The only network use is downloading a speech model.
8. **Never harm the user's data.** Originals are never modified or deleted. Imports are idempotent and clean up
   after failure. Restores never overwrite existing progress. We never permanently delete the user's data
   ourselves; we show them where it is and let them.
9. **Licences and credit.** Every dependency and data source is listed in Acknowledgements with its licence. Add no
   dependency without asking first.

## How we work

- **Say what you will change, then what you verified.** Before each step, one line on what is about to change.
  After it, what was verified and, just as plainly, what was not (for example "builds, tests pass; not seen in the
  running app"). Keep responses short.
- **Push back** when a step is overbuilt, or a request works against the principles above. Give a recommendation,
  not a survey of options.
- **Ask before** adding a dependency, changing what leaves the Mac, anything hard to reverse, or pushing to GitHub.
  Approval for one push is not approval for the next.
- **Commits** are conventional (`feat(scope):`, `fix(scope):`, `docs:`, `refactor:`), small, and one idea each.
  Commit when asked; do not push until told.
- **Shared code asks the profile.** Language-specific behaviour lives in a `LanguageProfile`; shared code never
  checks a language code. Adding a language is a contained job.
- **Schema changes only through GRDB migrations**, never edits to an existing one. Derived data (dictionaries,
  coverage, thumbnails) is rebuildable and stays out of backups.
- **Logic in `LangCore`, tested; views stay thin.** Anything that can be tested without a window goes in the
  package with a test. When fixing a bug, add the test that would have caught it.
- **Look at the real thing.** A build that passes is not a screen that works. Run the app, and for anything
  visual or about performance, look at it or measure it. Debug builds are not a guide to performance; Release
  builds link differently, so open a video in a Release build before calling a release ready.
- **Write every user-facing string so it can be translated**, even though English is the only language today.
  In a view, a plain literal is already localisable (`Text("Done")`, `.help("…")`, `Button("…")`). Anywhere else
  (helpers, error descriptions, messages stored in state) use `String(localized: "…")`, and in `LangCore`
  `String(localized: "…", bundle: .module)`. Never build a sentence by joining pieces; give the translator the
  whole sentence with its values interpolated. Plurals use `^[\(n) word](inflect: true)` (`inflected(...)` where a
  `String` is needed), lists use `listed(...)`, and the names of enum values shown to the user get a `title`
  property instead of showing a raw value (a stored value is a save format, not text). Dates, numbers and sizes use
  the system formatters. Layouts must survive text that is longer, so avoid fixed widths for text. Strings are kept in
  `Kikimi/Localizable.xcstrings` and `LangCore/Sources/LangCore/Resources/Localizable.xcstrings`; Xcode adds new
  keys when it builds in the IDE.
- **Code reads like the code around it**: same comment density, naming and idiom. Comments say why, not what.

## Commands

The shell needs Xcode's toolchain, and builds that touch the network or the sandbox need it relaxed.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Kikimi.xcodeproj -scheme Kikimi -destination 'platform=macOS' build
(cd LangCore && swift test)                                  # about 230 tests, 9 opt-in ones skipped
python3 Scripts/dictionaries/test_builders.py                # dictionary builder tests
Scripts/check_leaks.sh                                       # LangCore tests under `leaks`
```

The Release build is `xcodebuild … -configuration Release`; the shipping procedure is
[Release/CHECKLIST.md](Release/CHECKLIST.md). Generated dictionaries are gitignored; a fresh clone needs
`Scripts/build_ipadic.sh` and `Scripts/build_dictionaries.sh` before it will build.

## Before calling something done

- It builds (Debug and, for anything that links or loads differently, Release) and `swift test` passes.
- New behaviour has a test, or a stated reason it cannot.
- The keyboard and VoiceOver path exists, in both Light and Dark.
- README, ARCHITECTURE, the How it works page, the privacy policy and the terms still tell the truth.
- New text is localisable (see above).
- Anything not verified is said so.
