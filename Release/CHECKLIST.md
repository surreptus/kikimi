# Release checklist

Work top to bottom. `Scripts/release.sh --help` shows how to run the build.

## One-time setup
- [ ] Apple Developer Program membership (paid). Note your **team ID** (developer.apple.com > Membership).
- [ ] Pick the real **bundle ID** and set it in the LangSRS target (Signing & Capabilities).
      **This changes the app's data container.** Before switching, copy
      `~/Library/Containers/dev.langsrs.LangSRS/Data/Library/Application Support/LangSRS` into the new container
      (`~/Library/Containers/<new id>/Data/Library/Application Support/LangSRS`) while the app is closed.
- [ ] Choose your team in the target (Signing & Capabilities). Keep "Automatically manage signing" on.
- [ ] Add the **app icon** (PNGs in `LangSRS/Assets.xcassets/AppIcon.appiconset`, 1024 px source).
- [ ] Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (raise the build number for every upload).
- [ ] Direct download only: create a notarization profile once:
      `xcrun notarytool store-credentials langsrs --apple-id <you> --team-id <TEAM_ID>`
      (uses an app-specific password from appleid.apple.com).

## Every release
- [ ] `Scripts/build_ipadic.sh` and `Scripts/build_dictionaries.sh` have been run (the build refuses otherwise).
- [ ] `cd LangCore && swift test` passes (the script runs it unless `--skip-tests`).
- [ ] Open the project in Xcode once and check **Product > Archive > Generate Privacy Report**. Every API listed
      must be covered by `LangSRS/PrivacyInfo.xcprivacy` (it currently declares UserDefaults only; this was not
      checked against third-party packages).
- [ ] Build: `TEAM_ID=... Scripts/release.sh developer-id --notarize` (direct) or `... app-store`.

## Test the result (on a Mac or user account that has never run a dev build)
- [ ] The app opens without a Gatekeeper warning (direct download).
- [ ] First launch is quick (the dictionaries are read in place); the Import tab can download a speech model.
- [ ] Import a short video end to end; play it; review a word; export a clip.
- [ ] Quit and relaunch: data is still there.
- [ ] The Acknowledgements screen lists all licences.

## Mac App Store extras
- [ ] App record in App Store Connect with the same bundle ID.
- [ ] Privacy policy URL; privacy "nutrition label": data not collected.
- [ ] Export compliance: only standard HTTPS (model downloads) is used.
- [ ] Screenshots, description, age rating, category (Education).
- [ ] Review notes: the app downloads Whisper speech models (about 1.5 GB, data not code) from Hugging Face on
      first use, and works only on files the user provides.

## Licences to confirm before publishing
- [ ] Whisper model card on Hugging Face (`argmaxinc/whisperkit-coreml`) states the licence you assumed (MIT).
- [ ] JMdict and Wiktionary data stay under CC BY-SA 4.0 with attribution; do not commit the built dictionaries.
- [ ] Do not use the name "WaniKani" in the app name or marketing; consider renaming the SRS stage names.
