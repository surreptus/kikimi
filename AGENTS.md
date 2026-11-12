# Working agreements

This file says how we build Kikimi. Read it before you change anything. Update it when we agree on a new way to work.
[ARCHITECTURE.md](ARCHITECTURE.md) says where things live. [ROADMAP.md](ROADMAP.md) says what comes next.

## What every change is measured against

1. **Mac app practice.** Follow the Apple Human Interface Guidelines: a standard Settings window (⌘,), menu-bar commands with
   shortcuts, system colours and controls, Light and Dark, full screen, window restoration, drag and drop, Open With. Target
   macOS 15 and later. Hide a feature that needs a newer system (translations need macOS 26) on older systems. Never emulate it or
   work around a missing API. Keep the sandbox and the hardened runtime on.
2. **Dieter Rams: less, but better.** Good design is useful, unobtrusive, honest, thorough and long-lasting. Remove decoration and
   any control that is not needed. This applies to the UI, the code and our reports.
3. **Our promises.** The app must match its [privacy policy](Kikimi/Privacy.md) and its terms. If a feature changes what data
   leaves the Mac, or what we say about it, change the policy first.
4. **Comprehensible input.** A feature must make this loop faster or clearer: much understandable material, a little above the
   learner's level, so that the words they meet become words they know. If a feature works against the loop (a translation that
   is always visible, for example), hide it until the learner asks.
5. **Small and fast.** Keep memory, disk use and launch time low. Load lazily. Release what is not in use. Read dictionaries in
   place. Measure before you optimise, and say what you measured. Check Release builds, not only Debug.
6. **Accessible and easy.** Everything works with the keyboard and VoiceOver. Text is at least 12 pt (furigana excepted). Contrast
   is at least 4.5:1. Colour is never the only signal. Increase Contrast and Reduce Motion are honoured. The first use needs no
   explanation.
7. **Local and private.** Use local files only. Never download video from video sites. No accounts, analytics or tracking. The
   microphone records a Shadow card only, and only while the card is open. The only network use is the speech-model download
   and, when asked, a check for a new version. (macOS can download a translation language. That is the system, and we send nothing.)
8. **Never harm the user's data.** Never change or delete an original. Imports are idempotent and clean up after a failure. A
   restore never overwrites existing progress. We never permanently delete user data. We show the user where it is, and they
   decide.
9. **Licences and credit.** Every dependency and data source is in Acknowledgements with its licence. Ask before you add a
   dependency.

## How we work

- **Say what you will change, then what you checked.** Write one line before each step. After it, write what you checked and what
  you did not check ("builds, tests pass; not seen in the running app"). Keep reports short.
- **Write for the reader.** Documents for users are warm and plain: the README install part, the guide, the FAQ, the changelog,
  the privacy policy and the terms. All other documents use **simplified technical English**: AGENTS, ARCHITECTURE, ROADMAP, the
  release checklist, pull request text and code comments. Rules: 20 words or fewer in a sentence, one idea in each, active voice,
  common words, one name for one thing, no idioms, no jokes. Keep documents short. Say a thing once. Cut what the reader does not
  need.
- **Push back** when a step is overbuilt or a request works against these principles. Give one recommendation, not a list.
- **Ask before** you add a dependency, change what leaves the Mac, do anything hard to undo, or push to GitHub. Approval for one
  push is not approval for the next.
- **Commits** follow Conventional Commits (`feat(scope):`, `fix(scope):`, `docs:`, `refactor:`). Keep them small, with one idea each.
  Commit when asked. Do not push until told.
- **Everything goes through a pull request.** `main` is protected. Work on a branch (`feat/…`, `fix/…`, `chore/…`). Push when told.
  The pull request says what changed, what was checked and what was not (the template asks). The owner merges. Never commit or
  push to `main`. A release is also a pull request (see [Release/CHECKLIST.md](Release/CHECKLIST.md)).
- **Shared code asks the profile.** Language-specific behaviour lives in a `LanguageProfile`. Shared code never checks a language
  code.
- **Change the schema only with a GRDB migration.** Never edit an existing one. Derived data (dictionaries, coverage, thumbnails)
  can be rebuilt, and stays out of backups.
- **Logic goes in `LangCore`, with a test. Views stay thin.** When you fix a bug, add the test that would have caught it.
- **Look at the real thing.** A passing build is not a working screen. Run the app. Look at anything visual. Measure anything about
  performance. Debug does not show Release performance. Open a video in a Release build before you call a release ready.
- **Make every user-facing string translatable.** In a view, a plain literal works (`Text("Done")`). Elsewhere use
  `String(localized: "…")`, and in `LangCore` add `bundle: .module`. Never build a sentence from pieces. Plurals use
  `^[\(n) word](inflect: true)` (`inflected(...)` for a `String`). Lists use `listed(...)`. An enum value shown to the user gets a
  `title` property. Dates, numbers and sizes use system formatters. Do not fix the width of text. Strings are in
  `Kikimi/Localizable.xcstrings` and `LangCore/Sources/LangCore/Resources/Localizable.xcstrings`. Xcode adds new keys when it
  builds in the IDE.
- **Buttons in a row match.** Pill buttons of one size have the same height with text or with an icon (`PillButtonStyle`). Icon-only
  pills use `.labelStyle(.pillIcon)`. When you add a button, put it next to its neighbours and check that they line up.
- **Code reads like the code around it:** the same comments, names and style. A comment says why, not what.

## Commands

The shell needs the Xcode toolchain. Builds that use the network or the sandbox need it relaxed.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Kikimi.xcodeproj -scheme Kikimi -destination 'platform=macOS' build
(cd LangCore && swift test)                                  # about 430 tests, 12 opt-in ones skipped
python3 Scripts/dictionaries/test_builders.py                # dictionary builder tests
python3 -I Scripts/test_release_tools.py                     # release tool tests
Scripts/check_leaks.sh                                       # LangCore tests under `leaks`
```

Website: `cd site && npm install && npm run build` (Node 22 or later). Keep Astro at an exact version. Ask before you add another
npm package. The site stays static, with no analytics and no third-party scripts.

The Release build is `xcodebuild … -configuration Release`. [Release/CHECKLIST.md](Release/CHECKLIST.md) has the shipping steps.
Generated dictionaries are in `.gitignore`. A new clone needs `Scripts/build_ipadic.sh` and `Scripts/build_dictionaries.sh`
before it builds.

## Before you call something done

- It builds (Debug, and Release if it links or loads differently), and `swift test` passes.
- New behaviour has a test, or you say why it has none.
- The keyboard and VoiceOver path exists, in Light and in Dark.
- README, ARCHITECTURE, the How it works page, the privacy policy and the terms are still true.
- New text is translatable.
- You said what you did not check.
