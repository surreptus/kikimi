# Release checklist (Aomame)

Work top to bottom. `Scripts/release.sh --help` shows how to run the build.

## One-time setup
- [ ] Apple Developer Program membership (paid). Note your **team ID** (developer.apple.com > Membership).
- [x] **Bundle ID** is `com.surreptus.Aomame` (set in the Aomame target). Changing it later moves the app's data
      container, so do that before anyone has data.
- [ ] Choose your team in the target (Signing & Capabilities). Keep "Automatically manage signing" on.
- [x] **App icon**: an asanoha (hemp leaf) star in white line on dark green, drawn for Aomame (the Dock shows a light version in Light appearance) (`Scripts/icon/make_icon.swift` regenerates it) (PNGs in `Aomame/Assets.xcassets/AppIcon.appiconset`). Replace it if you commission a different one.
- [ ] Open a video in the **Release** build, not only the Debug one: Release links differently (the AVKit link is set in the target's `OTHER_LDFLAGS` because SwiftUI's `VideoPlayer` never names it).
- [x] Version: `MARKETING_VERSION` is `0.9.0` (a public beta; the first release is 0.9.0, and 1.0.0 follows once the 1.0 list in the roadmap is done), build `1`.
      Raise `CURRENT_PROJECT_VERSION` (a plain integer) for every release handed to anyone. After that: `0.9.x` fixes, `0.10.0` or `1.0.0` features. Tag the release commit `v0.9.0` and attach the notarized zip to a GitHub Release.
- [ ] Direct download only: create a notarization profile once:
      `xcrun notarytool store-credentials aomame --apple-id <you> --team-id <TEAM_ID>`
      (uses an app-specific password from appleid.apple.com).

## Every release
- [ ] `Scripts/build_ipadic.sh` and `Scripts/build_dictionaries.sh` have been run (the build refuses otherwise).
- [ ] `cd LangCore && swift test` passes (the script runs it unless `--skip-tests`).
- [ ] **Run the model-based tests**, which the normal run skips because they need real models (coverage of
      `WhisperKitTranscriber` is only 6% without them). With a network connection:
      `cd LangCore && LANGCORE_INTEGRATION=1 swift test` (real transcription and language detection, tiny model, ~73 MB),
      then once with a speech model you ship: `LANGCORE_BENCHMARK=1 LANGCORE_MODEL=<variant> LANGCORE_MODELS_DIR=<folder> swift test`.
      Note the word error rate and speed in the release notes; a result far worse than the README's figures (about 23% on a
      long Spanish passage with `medium`) is a reason to stop and look.
- [ ] Open the project in Xcode once and check **Product > Archive > Generate Privacy Report**. Every API listed
      must be covered by `Aomame/PrivacyInfo.xcprivacy` (it currently declares UserDefaults only; this was not
      checked against third-party packages).
- [ ] Build: `TEAM_ID=... Scripts/release.sh developer-id --notarize` (direct) or `... app-store`.

## Test the result (on a Mac or user account that has never run a dev build)
- [ ] The app opens without a Gatekeeper warning (direct download).
- [ ] First launch is quick (the dictionaries are read in place); the Videos page can download a speech model.
- [ ] Import a short video end to end; play it; review a word; export a clip.
- [ ] Quit and relaunch: data is still there.
- [ ] The Acknowledgements screen lists all licences.

## Mac App Store extras
- [ ] App record in App Store Connect with the same bundle ID.
- [ ] Privacy policy URL: publish `Aomame/Privacy.md` (the app shows the same file) and add a contact line to it first.
- [ ] Terms of use: fill in the `[Contact email]` placeholder in `Aomame/Terms.md` (governing law is California), and
      have a lawyer read it, before publishing or shipping.
      Privacy "nutrition label": data not collected.
- [ ] Export compliance: only standard HTTPS (model downloads) is used.
- [ ] Screenshots, description, age rating, category (Education).
- [ ] Review notes: the app downloads Whisper speech models (about 1.5 GB, data not code) from Hugging Face on
      first use, and works only on files the user provides.

## Licences to confirm before publishing
- [x] Whisper model card on Hugging Face (`argmaxinc/whisperkit-coreml`) says MIT (checked 25 Oct 2026; check again when the model changes).
- [x] JMdict and Wiktionary data stay under CC BY-SA 4.0 with attribution; the Acknowledgements say they were adapted and are shared under the same licence, and point to the build scripts. Do not commit the built dictionaries.
- [x] The SRS stages are plain "Stage 1" to "Stage 8" and "Finished" (the WaniKani names are gone from the app, code and docs). Still do not use the name "WaniKani" in marketing.
- [ ] When a package is added or updated, check `Package.resolved` against Acknowledgements (today: GRDB, WhisperKit and the swift-transformers code inside it; swift-argument-parser is resolved but not linked).
