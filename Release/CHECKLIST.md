# Release checklist (Kikimi)

Work from top to bottom. `Scripts/release.sh --help` shows how to run the build.

## One-time setup
- [ ] Join the Apple Developer Program (paid). Note your **team ID** (developer.apple.com > Membership).
- [x] The **bundle ID** is `com.surreptus.Kikimi`. A change later moves the app's data container, so change it before anyone has
      data.
- [ ] Choose your team in the Kikimi target (Signing & Capabilities). Keep "Automatically manage signing" on.
- [x] **App icon**: an asanoha star in white line on dark green. `Scripts/icon/make_icon.swift` regenerates the PNGs in
      `Kikimi/Assets.xcassets/AppIcon.appiconset`.
- [ ] Open a video in the **Release** build, not only Debug. Release links differently: the AVKit link is set in the target's
      `OTHER_LDFLAGS`, because SwiftUI's `VideoPlayer` never names it.
- [x] Version: `MARKETING_VERSION` is `0.17.0` (a public beta), build `15`. Raise `CURRENT_PROJECT_VERSION` (an integer) for every
      release you give to anyone. Use `0.16.x` for fixes, and `0.17.0` or `1.0.0` for features. 1.0.0 follows the 1.0 list in the
      roadmap. Tag the release commit `v0.17.0`. Attach the notarized zip to a GitHub Release.
- [ ] Direct download only: create a notarization profile once, with an app-specific password from appleid.apple.com:
      `xcrun notarytool store-credentials kikimi --apple-id <you> --team-id <TEAM_ID>`

## Every release
- [ ] **A release is a pull request, because `main` is protected.** The version bump, the changelog entry and the guide changes go
      in one release PR. After the merge, build from the merge commit (not the branch), tag that commit and publish. Raise
      `site/public/latest.json` in a second small PR after the release is published, not before.
- [ ] Run `Scripts/build_ipadic.sh` and `Scripts/build_dictionaries.sh` (the build refuses to run without them).
- [ ] **Refresh the dictionary data.** Run `Scripts/build_dictionaries.sh` again, so JMdict and KANJIDIC2 are the current EDRDG
      files. The EDRDG licence requires regular updates and calls old data a violation. `check_release_sync.py` fails if the data is
      more than 31 days old. New Wiktionary extracts can change meanings and verb forms, so then run
      `python3 Scripts/dictionaries/test_builders.py`, `swift test` and `LANGCORE_AUDIT=1 swift test --filter DictionaryAuditTests`.
- [ ] `cd LangCore && swift test` passes. (The release script runs it unless you pass `--skip-tests`.)
- [ ] **Run the model-based tests.** The normal run skips them, and without them `WhisperKitTranscriber` coverage is 6%. With a
      network connection, run `cd LangCore && LANGCORE_INTEGRATION=1 swift test` (tiny model, about 73 MB). Then run once with a
      model that you ship:
      `LANGCORE_BENCHMARK=1 LANGCORE_MODEL=<variant> LANGCORE_MODELS_DIR=<folder> swift test`.
      Put the word error rate and the speed in the release notes. If it is much worse than the README figure (about 23% on a long
      Spanish passage with `medium`), stop and find the cause.
- [ ] In Xcode, run **Product > Archive > Generate Privacy Report**. `Kikimi/PrivacyInfo.xcprivacy` must cover every API in it. It
      declares UserDefaults only. We have not checked it against the third-party packages.
- [ ] Build: `TEAM_ID=... Scripts/release.sh developer-id --notarize` (direct download) or `... app-store`.
- [ ] **Write the version's section in `CHANGELOG.md`** (a summary line, then New and Fixed). Then run
      `python3 -I Scripts/check_release_sync.py`. It fails if the newest changelog section is not the Xcode project's version, if
      `site/public/latest.json` is ahead of it, or if the built JMdict or KANJIDIC2 data is more than 31 days old. The changelog is
      the one source: the website imports it, and the release notes come from it.
- [ ] **Publish a checksum with every download.** Make the notes:
      `python3 -I Scripts/release_notes.py X.Y.Z --zip <the zip> --commit <the tagged commit> --out build/notes-X.Y.Z.md --tests "N automated tests pass."`
      Give them to `gh release create --notes-file`. The script computes the SHA-256 of the exact file you attach, and adds the beta
      notice, the download block and the limits from `Release/known-limits.md`. The tag is annotated. A checksum shows only that the
      file is the published file. It does not show that the file is safe. Do not claim more.
- [ ] **Update `site/public/latest.json`** to the new version
      (`{"version": "x.y.z", "url": "https://github.com/surreptus/kikimi/releases/latest"}`) after the release is published. Then
      Check for Updates in older copies finds it.

## Test the result
Use a Mac or user account that has never run a dev build.
- [ ] The app opens without a Gatekeeper warning (direct download).
- [ ] The first launch is quick. The Videos page can download a speech model.
- [ ] Import a short video. Play it. Review a word. Export a clip.
- [ ] Quit and open again. The data is still there.
- [ ] The Acknowledgements screen lists all licences.

## Mac App Store extras
- [ ] Make an app record in App Store Connect with the same bundle ID.
- [ ] Privacy policy URL: publish `Kikimi/Privacy.md`. Its contact is the GitHub issues page.
- [ ] Terms: the contact in `Kikimi/Terms.md` is the GitHub issues page, and the governing law is California. A lawyer must read the
      terms before you publish or ship. The privacy "nutrition label" says: data not collected.
- [ ] Export compliance: the app uses only standard HTTPS (model downloads).
- [ ] Screenshots, description, age rating, category (Education).
- [ ] Review notes: the microphone is used only for the Shadow card, and recordings are deleted when the card ends. On first use
      the app downloads Whisper models (about 1.5 GB, data not code) from Hugging Face, and it works only on files that the user
      provides.

## Licences to confirm before publishing
- [x] The Whisper model card (`argmaxinc/whisperkit-coreml`) says MIT (checked 25 Oct and 12 Nov 2026; check again when the model
      changes). OpenAI's own cards say MIT (`openai/whisper-large-v3-turbo`) or Apache 2.0 (`openai/whisper-medium`; the Whisper
      repository says MIT). All are permissive. The user downloads the models. We do not bundle them.
- [x] JMdict and Wiktionary data stay under CC BY-SA 4.0 with attribution. Acknowledgements say that the data is adapted and shared
      under the same licence, and point to the build scripts. Do not commit the built dictionaries.
- [x] The SRS stages are "Stage 1" to "Stage 8" and "Finished". Do not use the name "WaniKani" in the app, the docs or marketing.
- [x] Audit of 12 Nov 2026, against the upstream licence texts. The GRDB, WhisperKit, MeCab (BSD), IPADIC and swift-transformers
      files are the upstream texts with only our headers added. The credits meet the EDRDG acknowledgement terms. The website page
      and `THIRD_PARTY_NOTICES.md` match. This is not a lawyer's review.
- [ ] When you add or update a package, check `Package.resolved` against Acknowledgements. Today: GRDB, WhisperKit and the
      swift-transformers code inside it. `swift-argument-parser` is resolved but not linked.
