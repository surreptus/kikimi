# Release checklist (Kikimi)

Work top to bottom. `Scripts/release.sh --help` shows how to run the build.

## One-time setup
- [ ] Apple Developer Program membership (paid). Note your **team ID** (developer.apple.com > Membership).
- [x] **Bundle ID** is `com.surreptus.Kikimi` (set in the Kikimi target). Changing it later moves the app's data
      container, so do that before anyone has data.
- [ ] Choose your team in the target (Signing & Capabilities). Keep "Automatically manage signing" on.
- [x] **App icon**: an asanoha (hemp leaf) star in white line on dark green, drawn for Kikimi (the Dock shows a light version in Light appearance) (`Scripts/icon/make_icon.swift` regenerates it) (PNGs in `Kikimi/Assets.xcassets/AppIcon.appiconset`). Replace it if you commission a different one.
- [ ] Open a video in the **Release** build, not only the Debug one: Release links differently (the AVKit link is set in the target's `OTHER_LDFLAGS` because SwiftUI's `VideoPlayer` never names it).
- [x] Version: `MARKETING_VERSION` is `0.16.0` (a public beta; the first release was 0.9.0, and 1.0.0 follows once the 1.0 list in the roadmap is done), build `13`.
      Raise `CURRENT_PROJECT_VERSION` (a plain integer) for every release handed to anyone. After that: `0.16.x` fixes, `0.17.0` or `1.0.0` features. Tag the release commit `v0.16.0` and attach the notarized zip to a GitHub Release.
- [ ] Direct download only: create a notarization profile once:
      `xcrun notarytool store-credentials kikimi --apple-id <you> --team-id <TEAM_ID>`
      (uses an app-specific password from appleid.apple.com).

## Every release
- [ ] **Releases go through pull requests, since `main` is protected.** The version bump, the changelog entry and the guide
      changes are one release PR. After it is merged, build from the merge commit (not the branch), tag that commit, and
      publish. `site/public/latest.json` is raised in a second small PR after the release is published, since it must not
      move before then.
- [ ] `Scripts/build_ipadic.sh` and `Scripts/build_dictionaries.sh` have been run (the build refuses otherwise).
- [ ] **Refresh the dictionary data for this release**: rerun `Scripts/build_dictionaries.sh` so JMdict and KANJIDIC2 are the
      current EDRDG files, not the ones from the last release. The EDRDG licence requires "a procedure for regular updating" and
      calls failing to keep the data up to date a violation of it; this is that procedure, and `check_release_sync.py` (below)
      fails when the data is over 31 days old. The same run takes the newest Wiktionary extracts, which can change meanings and
      verb forms, so then run `python3 Scripts/dictionaries/test_builders.py`, `swift test` and the opt-in dictionary audits
      (`LANGCORE_AUDIT=1 swift test --filter DictionaryAuditTests`) before building.
- [ ] `cd LangCore && swift test` passes (the script runs it unless `--skip-tests`).
- [ ] **Run the model-based tests**, which the normal run skips because they need real models (coverage of
      `WhisperKitTranscriber` is only 6% without them). With a network connection:
      `cd LangCore && LANGCORE_INTEGRATION=1 swift test` (real transcription and language detection, tiny model, ~73 MB),
      then once with a speech model you ship: `LANGCORE_BENCHMARK=1 LANGCORE_MODEL=<variant> LANGCORE_MODELS_DIR=<folder> swift test`.
      Note the word error rate and speed in the release notes; a result far worse than the README's figures (about 23% on a
      long Spanish passage with `medium`) is a reason to stop and look.
- [ ] Open the project in Xcode once and check **Product > Archive > Generate Privacy Report**. Every API listed
      must be covered by `Kikimi/PrivacyInfo.xcprivacy` (it currently declares UserDefaults only; this was not
      checked against third-party packages).
- [ ] Build: `TEAM_ID=... Scripts/release.sh developer-id --notarize` (direct) or `... app-store`.
- [ ] **Update `site/public/latest.json`** to the new version (`{"version": "x.y.z", "url": "https://github.com/surreptus/kikimi/releases/latest"}`)
      and push, so Check for Updates in older copies finds it. Do it only once the release is published, not before.
- [ ] **Write the version's section in `CHANGELOG.md`** (a summary line, then New and Fixed), and run
      `python3 -I Scripts/check_release_sync.py`: it fails if the changelog's newest section isn't the Xcode project's version,
      if `site/public/latest.json` is ahead of it, or if the built JMdict or KANJIDIC2 data is over 31 days old. The changelog is the one source: the website's changelog page imports it,
      and the release notes are made from it.
- [ ] **Publish a checksum with every download.** Make the notes with
      `python3 -I Scripts/release_notes.py X.Y.Z --zip <the zip> --commit <the tagged commit> --out build/notes-X.Y.Z.md --tests "N automated tests pass."`
      and pass them to `gh release create --notes-file`. It computes the SHA-256 of the exact file you attach and adds the beta notice,
      the download block and the standing limits in `Release/known-limits.md` (edit that file when they change). The tag is annotated,
      and the notes say which commit it is. A checksum only shows the file is the one published, not that it is safe; say nothing stronger than that.

## Test the result (on a Mac or user account that has never run a dev build)
- [ ] The app opens without a Gatekeeper warning (direct download).
- [ ] First launch is quick (the dictionaries are read in place); the Videos page can download a speech model.
- [ ] Import a short video end to end; play it; review a word; export a clip.
- [ ] Quit and relaunch: data is still there.
- [ ] The Acknowledgements screen lists all licences.

## Mac App Store extras
- [ ] App record in App Store Connect with the same bundle ID.
- [ ] Privacy policy URL: publish `Kikimi/Privacy.md` (the app shows the same file); its contact is the GitHub issues page.
- [ ] Terms of use: the contact in `Kikimi/Terms.md` is the GitHub issues page (governing law is California); have a
      lawyer read it before publishing or shipping.
      Privacy "nutrition label": data not collected.
- [ ] Export compliance: only standard HTTPS (model downloads) is used.
- [ ] Screenshots, description, age rating, category (Education).
- [ ] Review notes: the microphone is used only for the Shadow card type, and recordings are deleted when the card ends.
- [ ] Review notes: the app downloads Whisper speech models (about 1.5 GB, data not code) from Hugging Face on
      first use, and works only on files the user provides.

## Licences to confirm before publishing
- [x] Whisper model card on Hugging Face (`argmaxinc/whisperkit-coreml`) says MIT (checked 25 Oct and again 12 Nov 2026; check again when the model changes). OpenAI's own cards differ: `openai/whisper-large-v3-turbo` says MIT, `openai/whisper-medium` says Apache 2.0 (the Whisper repository says MIT); all are permissive, and the models are downloaded by the person, not bundled.
- [x] JMdict and Wiktionary data stay under CC BY-SA 4.0 with attribution; the Acknowledgements say they were adapted and are shared under the same licence, and point to the build scripts. Do not commit the built dictionaries.
- [x] The SRS stages are plain "Stage 1" to "Stage 8" and "Finished" (the WaniKani names are gone from the app, code and docs). Still do not use the name "WaniKani" in marketing.
- [x] Audited 12 Nov 2026 (read against the upstream licence texts): GRDB, WhisperKit, MeCab (BSD), IPADIC and swift-transformers licence files are the upstream texts, with only our explanatory headers added; the EDRDG licence's acknowledgement terms are met (an "About"-reachable Acknowledgements screen with the licence link, the website page, and the data credited as adapted under the same licence); `THIRD_PARTY_NOTICES.md` matches. Not a lawyer's review.
- [ ] When a package is added or updated, check `Package.resolved` against Acknowledgements (today: GRDB, WhisperKit and the swift-transformers code inside it; swift-argument-parser is resolved but not linked).
