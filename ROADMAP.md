# Roadmap

What exists, what is left for 1.0, and what comes after. Measured against the principles in
[AGENTS.md](AGENTS.md). Last updated 2026-10-26.

## Where we are

The core loop works end to end: import a video you own, transcribe it on the Mac, find and look up its words,
play it with synced and clickable subtitles, review words with spaced repetition, see how much of each video you
already know, and back your progress up. Spanish and Japanese are supported.

**Verdict: feature-complete for 1.0, not yet release-ready.** What remains is mostly proving the app on a clean
machine, release plumbing, and a few promises we have made but not kept (below). New features can wait.

## Needed for 1.0

### Promises and paperwork
- [x] **Terms of use** drafted (`Kikimi/Terms.md`, shown in the app beside the privacy policy).
- [ ] **Finish the terms**: governing law is set to California; fill in the contact placeholder (the same contact
      the privacy policy needs), and have a lawyer review them. They were not written by one, and what they can
      limit depends on where your users live.
- [ ] **Privacy policy contact line.** Needs an email or page before the policy can be published.
- [ ] **Check the name "Kikimi"** is free to use (App Store, trademark search) before anything is public.
- [ ] Confirm licences listed in the [release checklist](Release/CHECKLIST.md) (Whisper model card, JMdict and
      Wiktionary attribution, no use of the name "WaniKani"). Audited 25 Oct 2026: notices are complete, the
      model card says MIT, the stage names are renamed, and the dictionaries are credited as adaptations.
- [ ] Privacy report (Xcode: Product > Archive > Generate Privacy Report) covered by `PrivacyInfo.xcprivacy`,
      including third-party packages.

### Release readiness
- [ ] Apple Developer membership, team ID, signing, notarization profile; set the version and build number.
- [ ] **Clean-machine test** with a Release build: first launch, model download, import, play, review, export a
      clip, quit and relaunch. The Release build has already shown a crash that Debug hid (AVKit not linked;
      fixed), so this is not a formality.
- [ ] Walk through every screen in the final build: Videos, Words, Review, Player, Storage, Settings, About.
- [ ] Rebuild the shareable zip from the final build.
- [ ] The website (`site/`, Astro, GitHub Pages): scaffolded with the home, privacy and terms pages. To do: switch on
      Pages (Settings > Pages > Source: GitHub Actions), a screenshot, and the Download link once there is a notarized
      release. The terms page shows `[Contact email]` until you fill it in, so don't publish before then.
- [ ] **How people get updates.** Direct download has no App Store to do it. Options: tell people to download again
      (nothing to build), a manual "Check for updates" that reads a small file from the download page (no new
      dependency; a network request to our own page, which the privacy policy must then mention), or Sparkle
      (a dependency, so ask first). Recommendation: the manual check.

### Quality
- [x] **Release the speech model when idle.** It is let go after 2 minutes unused (never mid-import); the next
      import reloads it.
- [ ] **Transcript performance.** It felt slow in Debug. A 20-second sample of the Debug build showed the main
      thread about 74% idle and nothing in our code standing out. Confirm in the Release build; if it still lags,
      likely suspects are every row re-evaluating on hover and rows never being released. Test on a 25-minute video.
- [x] Accessibility pass on the newer features (code review and fixes, 26 Oct 2026): buttons name their video or
      sentence, the resume offer and status messages are announced, auto-scroll honours Reduce Motion, previews are
      hidden from VoiceOver. **Still to do by hand:** listen to it with VoiceOver on, and tab through with Full Keyboard
      Access, in Light and Dark.
- [ ] Decide whether the progress backup should include where you stopped in each video (it does not now).
- [ ] Help and feedback: a "Report a problem" route (a mailto link with the app version, no data attached).
- [ ] App-wide text size. Today the setting covers only the transcript; macOS has no system text-size setting for
      apps to follow.

### Already done for 1.0
Import with progress and cancel; language check before transcribing; idempotent, non-destructive pipeline; word
extraction; dictionary lookup (JMdict, Wiktionary); word table with filters and bulk actions; review with
sentence audio; synced player with furigana, hints, clip export; coverage per video and level fit; known-words list;
backup and restore; Storage view for models; Settings window; menu commands; About, Privacy and Acknowledgements;
review overview (ready now, next 7 days, words per stage); transcript text size; resume where you stopped; video thumbnails; app icon; keyboard and VoiceOver for word hints.

## After 1.0

Ordered by how much each helps comprehensible input per unit of effort.

### Understanding the material
- [ ] **Translations in your native language**, per sentence, with Apple's on-device Translation framework. Stored
      in a new table (derived data, not backed up). Hidden by default, shown on request for a line, with "always
      show" as an option, because an always-visible translation encourages reading over listening. Needs the
      language pair installed once (Settings guides this). Quality varies, especially for Japanese; check the pair
      is supported before offering it.
- [ ] **Explain this sentence** (on request, on-device only): a short grammar and meaning note for a line. First
      check that the on-device model in macOS 26 handles Spanish and Japanese well enough; if it doesn't, drop it
      rather than send text off the Mac.
- [ ] **Subtitle modes**: target language only, target plus translation, none (listening practice), and a
      reveal-on-click mode.
- [x] **Pause after each line** (P) and **loop this line** (R), with a 1×, 0.75× or 0.5× speed for loops.
- [ ] **Import subtitles** (.srt / .vtt) when a video already has good ones, instead of transcribing.
- [x] **Edit a transcript line** (right-click a line > Edit line…): fixes the text and its timing (with a preview), and
      finds its words again.
- [ ] **Word-level timestamps**, so a single word can be played and clips are tighter.

### Finding the right material
- [ ] **Next up**: suggest the next video to watch by fit (we sort by fit now; this surfaces it on launch).
- [ ] **Frequency-list bootstrap**: mark the most common words as known for a beginner who has nothing yet. Needs
      a data source and a licence decision first.
- [ ] **Audio-only import** (podcasts) for material with no picture.

### Practising
- [ ] **Listening cards**: hear the sentence, answer before reading. **Cloze cards**: the word blanked in its sentence.
      Evidence: reviews are recognition only today, and receptive practice doesn't reliably carry over to producing a
      word, so generating it (cloze, meaning-to-word) is the main upgrade to the review loop.
- [ ] **Learning stats over time** (prioritised): a small history table, so the Review page can show words learned
      per week, hours of listening (the measure that matters for comprehensible input), and how often you look
      each word up, so the words you keep checking stand out as your weakest. A new table, so a deliberate step;
      the log stays on the Mac and is left out of nothing the privacy policy promises.
- [x] **Anki export** (Words page > Export to Anki…): a local text file Anki imports (word, meaning, example sentence), with
      optional sentence audio in a media folder. Checked against Anki 25.09's own importer: notes land in a
      "Kikimi Spanish" deck, and exporting again updates them instead of duplicating.

### Keeping the numbers honest
- [ ] **Check what you marked known.** Self-marked words (and imported lists) can inflate a video's coverage, so
      "Comfortable" overstates how easy it is. An occasional quick check on a sample of known words would catch that.
- [x] **Encounters per word**: the Words table's Seen column, and the word panel's "Seen in N lines across M videos".
- [ ] **Measure the 95% claim**: the README and About page say about 90% of content words is roughly 95% of all words.
      That is an estimate; count real transcripts and state the real figure, or soften the text.
- [ ] **Resurface finished words** now and then (a sparse, rare review, or a nudge when one appears in a video), since
      stopping at the last interval can let words fade.
- [ ] **Smarter review timing** (FSRS-style scheduling): low priority; the evidence is benchmark data, not trials.

### More languages
- [ ] **Romance languages next** (decided): French, Italian and Portuguese, one at a time. The `medium` Whisper
      model covers them, and Spanish already shows the way: the system tokenizer, a Wiktionary extract per
      language (`Scripts/dictionaries`, a large one-off download each), and a profile. Suggested order: French
      (most learners), then Portuguese, then Italian. Check each tokenizer's lemmas and parts of speech on real
      transcripts before committing, as we did for Japanese.

### Housekeeping
- [ ] Cache video thumbnails on disk if scrolling a large library feels slow (they are now made once per launch).
- [ ] **Translate the app's own interface** (no other language yet). The groundwork is done: strings are localisable and
      kept in two string catalogs. To add a language: add it in each catalog in Xcode, translate (Product >
      Export Localizations for a translator), add localised copies of `Privacy.md` and `Terms.md`, a localised
      `InfoPlist.xcstrings` (document type name), and run the app with the double-length pseudolanguage to find text that
      no longer fits. Several windows have fixed widths and will need checking.

## Decisions
Made:
1. **Direct download** for 1.0, not the Mac App Store. Needs a Developer ID, notarization and a download page; no
   review, screenshots or App Store listing. The App Store can come later.
2. **Free.** The terms of use can say so plainly (no payment, provided as is). A donation link is optional.
3. **Third language: Romance languages**, starting with French (see After 1.0).

Open:
1. How people get updates (see Release readiness).
2. Whether an always-visible translation should exist at all (see After 1.0).

## Not doing
- Downloading from YouTube or any video site. Ever.
- Accounts, sync servers, analytics, or anything that sends your data off the Mac.
- Modifying or deleting your original files.
