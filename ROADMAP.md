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
- [x] **Name: keeping Kikimi, with the trademark risk known** (decision of 30 Oct 2026). KIKIMI is a live registered US mark (reg.
      7139558, registered 15 Aug 2023, standard characters; owner KKLT Enterprises, LLC of San Francisco, which has a law
      firm; Class 9 downloadable software to share photos, exchange information securely, store data and reach social
      networks). The goods differ from a language-learning app, but an identical mark in the same class can draw a
      demand letter, and the worst case is a forced rename once there are users. The app is free, so the risk is a
      request to stop, not damages. To keep it small: position the app as education (not social or photo sharing), keep
      it out of the App Store for now, and register no mark of our own. **Fallback:** the alternative name chosen in the earlier rename was checked in full (no App
      Store app in the US or Japan, no USPTO result, `.app`, `.io`, `.dev` free by DNS). The whole rename is the commit
      `71c93ff` (see its message); reverting this revert re-applies it in one step.
- [ ] Ask the lawyer who reads the terms for a view on the KIKIMI registration, before any wider release.
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
- [x] **Readings and kanji for Japanese** (30 Oct 2026): a word with several readings (月: つき, がつ, げつ) lists them in the word bar
      and on review cards, and a word's page lists each kanji with its meaning and its on'yomi and kun'yomi (KANJIDIC2,
      EDRDG, CC BY-SA 4.0, 12,633 kanji, 0.7 MB). Not done: showing which reading a given sentence used on the review card,
      and naming the on'yomi or kun'yomi of the kanji as it is read in the word.
- [x] **First-launch welcome** (30 Oct 2026): languages you are learning, the language you read, a speech model download per
      language (or later). Not seen on screen yet (the sandbox here could not capture it). Not done: asking macOS to download
      the translation language during setup (needs the system's own sheet), and a link to run the welcome again.
- [x] **Release the speech model when idle.** It is let go after 2 minutes unused (never mid-import); the next
      import reloads it.
- [ ] **Transcript performance.** It felt slow in Debug. A 20-second sample of the Debug build showed the main
      thread about 74% idle and nothing in our code standing out. Confirm in the Release build; if it still lags,
      likely suspects are every row re-evaluating on hover and rows never being released. Test on a 25-minute video.
- [x] Accessibility pass on the newer features (code review and fixes, 26 Oct 2026): buttons name their video or
      sentence, the resume offer and status messages are announced, auto-scroll honours Reduce Motion, previews are
      hidden from VoiceOver. **Still to do by hand:** listen to it with VoiceOver on, and tab through with Full Keyboard
      Access, in Light and Dark.
- [x] A full backup (Settings > Data > Include my videos and transcripts) saves a folder with the compressed videos, their
      transcripts and where you stopped. The small progress-only file still leaves out where you stopped; decide if it should.
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
- [x] **Translations in your native language** (30 Oct 2026): macOS's on-device Translation framework, one line at a time, kept in a
      `translations` table (derived data, not backed up). Settings > General: Off, When I ask (default: hidden until you press
      a line's translate button or T, so you listen first) or Always, and the language to translate into (default: the
      Mac's). Needs the language pair installed; if not, the status line says where to add it. Not done: an in-app
      download prompt for a missing language (it needs the system's own sheet), and context-aware translation (a language
      model such as TranslateGemma was researched: it needs a ~2.5 GB download, a new dependency and Gemma's licence terms,
      so it waits until per-line translation has been used and found wanting). Findings behind the design (27 Oct 2026):
      Apple's framework translates each line of a batch separately and returns no alignment; its default and high-fidelity
      strategies gave identical results on 18 real lines, so the default is used.
- [x] **Explain this sentence**: tested on 27 Oct 2026 and **dropped for now**. The on-device language model in macOS 26
      is available on this Mac, but on real transcript lines it gave a wrong translation of a Spanish line, called
      "qué tipo de" an "adjective phrase", and for a Japanese line explained a different line's ending as a "polite
      negative suggestion". A wrong grammar note is worse than none for a learner. Revisit when the model improves, or
      with a checked, fixed set of grammar notes instead of generated ones.
- [x] **Grammar link-out for Japanese** (27 Oct 2026): the word bar names a verb's or adjective's form (from MeCab's inflection) and
      links to its Tsumiki page. Next, if wanted: map the auxiliary morphemes (させ, られ, た) to Tsumiki's suffix pages
      and show the whole derivation in the app from Tsumiki's data (CC BY-SA, so credited in the Acknowledgements).
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
- [x] **Cloze cards** (Settings > Languages > Review cards > Fill in the word): the example sentence with the word blanked and a short
      hint of its meaning (and, for Japanese, its reading); you recall the word, then see it filled in with the
      sentence audio. Production in context, which avoids the ambiguity of meaning-to-word cards. **Listening
      cards** (done, Settings > Languages > Review cards > Listen to the sentence): hear the sentence, answer before reading.
- [ ] **Reverse (meaning to word) cards**, only as an optional extra: off by default, only for words that have reached
      about stage 4 so early reviews don't double, and counted in the overview so the workload shows. Prefer cloze.
      Evidence: reviews are recognition only today, and receptive practice doesn't reliably carry over to producing a
      word, so generating it (cloze, meaning-to-word) is the main upgrade to the review loop.
- [x] **Learning stats over time** (built; Review page > Your progress; carried in the full backup): a small history table, so the Review page can show words learned
      per week, hours of listening (the measure that matters for comprehensible input), and how often you look
      each word up, so the words you keep checking stand out as your weakest. A new table, so a deliberate step;
      the log stays on the Mac and is left out of nothing the privacy policy promises.
- [x] **Anki export** (Words page > Export to Anki…): a local text file Anki imports (word, meaning, example sentence), with
      optional sentence audio in a media folder. Checked against Anki 25.09's own importer: notes land in a
      "Kikimi Spanish" deck, and exporting again updates them instead of duplicating.

### Keeping the numbers honest
- [x] **Check what you marked known** (Review page > Check my known words): a quiz of up to 10 random known words; any you
      miss go back to learning, so coverage stops counting them. Self-marked words and imported lists can inflate it otherwise.
- [x] **Encounters per word**: the Words table's Seen column, and the word panel's "Seen in N lines across M videos".
- [x] **Measured the 95% claim** (26 Oct 2026, one Spanish and one Japanese transcript, 918 and 2,459 words): content words
      were 58% (es) and 40% (ja) of all words, so knowing 90% of them is about 94% (es) and 96% (ja) of everything,
      assuming the small words are known. The text now says that. A small sample; recount with more videos.
- [ ] **Resurface finished words** now and then (a sparse, rare review, or a nudge when one appears in a video), since
      stopping at the last interval can let words fade.
- [ ] **Smarter review timing** (FSRS-style scheduling): low priority; the evidence is benchmark data, not trials.

### More languages
- [x] **French and German** (30 Oct 2026): each is a profile plus a Wiktionary dictionary (about 9 MB each), with the
      `medium` Whisper model and Apple's tokenizer. Checked on spoken-style sentences: German lemmas and word types
      were good (one fix: the tagger answered `koennen`, `muessen`, `duerfen` for "kann", "musst", "darf"); French has more
      mistakes (`restaurant` as a verb, `faut` as `faillir`, `commence` as a noun). Known gaps: a German separable verb
      ("ruf ... an") is learned as `rufen` and the particle is lost, and compound nouns missing from Wiktionary have no
      meaning. Not yet tried on a real French or German video, and `medium` is not benchmarked for either.
- [ ] **More languages**: Italian next (Apple's tagger handles it), then Portuguese and Dutch, whose lemmas macOS
      does not give (tested 30 Oct 2026: no lemma or part of speech), so each needs a lemma source, a dependency to
      ask about first.

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
3. **More languages after Spanish and Japanese**: French and German are done; Italian, Portuguese and Dutch are next (see After 1.0).

Open:
1. How people get updates (see Release readiness).
2. Whether an always-visible translation should exist at all (see After 1.0).

## Not doing
- Downloading from YouTube or any video site. Ever.
- Accounts, sync servers, analytics, or anything that sends your data off the Mac.
- Modifying or deleting your original files.
