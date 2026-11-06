# Roadmap

What exists, what is left for 1.0, and what comes after. Measured against the principles in
[AGENTS.md](AGENTS.md). Last updated 2026-11-06.

## Where we are

The core loop works end to end: import a video you own, transcribe it on the Mac, find and look up its words,
play it with synced and clickable subtitles, review words with spaced repetition, see how much of each video you
already know, and back your progress up. Spanish, French, German and Japanese are supported. Spanish and Japanese have
been used on real videos; French and German have been checked on sentences only (see More languages).

**Verdict: feature-complete for 1.0, not yet release-ready.** What remains is mostly proving the app on a clean
machine, release plumbing, and a few promises we have made but not kept (below). New features can wait.

## Needed for 1.0

### Promises and paperwork
- [x] **Terms of use** drafted (`Kikimi/Terms.md`, shown in the app beside the privacy policy).
- [ ] **Finish the terms**: governing law is set to California and the contact is the GitHub issues page; have a lawyer
      review them. They were not written by one, and what they can limit depends on where your users live.
- [x] **Contact line** (4 Nov 2026): the privacy policy and the terms point to the GitHub issues page
      (https://github.com/surreptus/kikimi/issues), and say issues there are public. No email address is published.
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
      release. The privacy and terms pages give the GitHub issues page as the contact.
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
- [x] **Import subtitles** (.srt / .vtt, 4 Nov 2026): drop a subtitle file with its video (or choose both together) and its cues
      are used instead of transcribing, so the import needs no speech model and is quick. Files are paired by name (`film.mp4`
      with `film.srt` or `film.es.srt`; the one tagged with the chosen language wins; a lone video with a lone subtitle file
      pair whatever they are called). Reads UTF-8, UTF-16 and older Western or Japanese encodings, SubRip and WebVTT, with
      markup, style codes, notes and sound descriptions removed. The language is checked from the text (a supported
      other language offers the same switch as for audio; any other, such as English subtitles, is refused), and a file
      whose cues all start after the video ends is refused before anything is copied. Not done: choosing a subtitle file for
      a video already in the library, subtitles inside a video file (embedded tracks), and other formats (.ass, .ttml).
- [x] **Edit a transcript line** (right-click a line > Edit line…): fixes the text and its timing (with a preview), and
      finds its words again.
- [ ] **Word-level timestamps**, so a single word can be played and clips are tighter.

### Finding the right material
- [x] **Next up** (5 Nov 2026): a card at the top of Videos suggests the video that fits best, by fit alone. A video you have heard is as
      good a choice as a new one, since listening again is how an almost-understood video becomes understood, so nothing is
      marked finished and replays are not marked down. It is hidden with one video, or when every video is still hard.
- [ ] **Frequency-list bootstrap**: mark the most common words as known for a beginner who has nothing yet. Needs
      a data source and a licence decision first.
- [ ] **Audio-only import** (podcasts) for material with no picture.

### Practising
- [x] **A Learn page with three paths** (suggested 4 Nov 2026, in the style of WaniKani's dashboard; built 5 Nov 2026 with Lessons, Reviews and Practice, not yet seen on screen): the Review page becomes
      **Learn**, a page of cards, one for each thing you can do now:
      - **Lessons**, with the count of the day's new words (see Daily lessons below). Start opens the lesson.
      - **Reviews**, with the count due now. This is today's panel, with the card type and Start.
      - **Practice**, extra study that does not move any stage: *Review ahead* (words not yet due), *Review known* (the quiz of
        words you marked known, which exists today) and *Practice finished* (words that have been through every stage and
        retired, WaniKani's "burned"), each a row with its count and a button, as WaniKani's Extra Study has.
      "Known" and "finished" differ: known is what you marked yourself, finished is what you earned by passing every review.
      The card type applies to all three paths. Settled 5 Nov 2026: a miss in *Practice finished* changes nothing (extra study; only *Review known*
      is a real check), and the sidebar count stays reviews due. It absorbs the *Review ahead* and *Resurface finished words* items.
- [x] **Daily lessons** (5 Nov 2026; built as below, 15 a day by default, Settings > Languages > New words a day, 0 turns them off; unused lessons lapse, and none are offered while more than 100 reviews are due; not yet seen on screen) (like WaniKani's): each day Kikimi queues up the most important words you haven't started, 15 for each
      language by default, and you learn them from a short lesson instead of picking every word yourself. The number is a
      setting (Settings > Languages > New words per day, one for each language you learn; 0 turns it off). Today nothing is
      learned until you select words, so someone with videos but no habit meets an empty Review page; a steady supply of the
      words that matter most keeps the loop going. Points to settle before building:
      - **Which words.** From your own videos, never a generic list. New content words (nouns, verbs, adjectives, adverbs),
        ranked by how much of your material they cover, either by the lines they appear in (as "Start with the 25 words you
        hear most" does) or, better, by how much each raises the coverage of the videos you are working through (as the
        per-video goal does). Skip known, learning and finished words, and any word with no example line from a video. With
        no videos yet there is nothing to queue (see the frequency-list item).
      - **No pile-up.** The day's lessons don't accumulate: unused ones lapse at midnight (our choice, to settle), and no new ones
        are offered while the reviews due are over a limit, as WaniKani does for overload. The limit (say 100) needs measuring.
      - **The lesson** (changed 5 Nov 2026, from the user's feedback: a lesson teaches a batch and quizzes it at once, as
        WaniKani's does). Five words at a time, one by one: the word in a sentence from one of your videos with its audio and
        its meaning. "Next" teaches it, "Already know it" marks it known. When the batch is done the words start at stage 1
        with their first review one stage-1 interval (4 hours) away, and the page quizzes them straight away in the chosen
        card type, asking a missed word again until it is right; the quiz moves no stage. Then the next five. Not a silent
        bulk add. Reviews and Practice (including the known and finished rechecks) use the chosen card type; lessons do not.
      - **Where it shows.** The Lessons card on the Learn page (above), with its count, for the language you are in.
      - **Counting the day.** The activity log already records each word started (`learn`), by day, so no new table is needed.
        It counts every start, including words you pick on Words or take from a video's goal; I'd let those use up the day's
        allowance too, since it is the cap on new words per day however they begin.
      - It sits beside picking words yourself and the per-video goal, not in place of them. Nothing leaves the Mac.
- [ ] **Grammar from your own videos** (researched 5 Nov 2026, **not started**): noticing, not a course. Recommendation: **forms
      of words you meet, shown on demand, with a link out**; no lesson path, no rules taught ahead of the material.
      - **Fits the loop:** the word panel and word bar say what a form is ("hablaría: conditional, 1st/3rd singular"; "食べさせられた:
        causative-passive, past") with a few other forms of the same word, and a line's pattern is found by looking, as
        Japanese already is (see the link-out item). Works against it: a fourth path of explained rules, tables to memorise,
        pattern drills ahead of use, anything generated (see *Explain this sentence*, dropped; and *Conversation practice*).
        Grammar is a property of the word you are looking at, so it belongs in the player and the word panel, not on Learn.
      - **What can be detected.** Japanese: well. MeCab/IPADIC already gives the 活用形 and the auxiliaries (させ, られ, た, ない, たい,
        ている), and particles are their own part of speech; chaining them names a form with a fixed table in the profile.
        Spanish, French, German: only lemma and part of speech, since `NLTagger` returns no tense, mood, case or person, and
        French lemmas are noisy. A form can still be named by looking the *surface* up in the dictionary's inflected forms:
        `build_kaikki.py` drops the `form_of` senses today, but kaikki carries each one with tags (`first-person singular
        conditional`). Ambiguity is real (Spanish *hable* is subjunctive 1st or 3rd; German *die* is a case in four ways),
        so show every reading or none, never one guess. Not detectable: syntax (relative clauses, word order), use
        (why subjunctive here), German case of a noun phrase. Not measured: how often the form lookup is unambiguous on
        real lines; measure on the library's transcripts before building.
      - **Sources and licences** (none verified against the licence texts today; check each before use):
        Wiktionary forms through kaikki.org (CC BY-SA 4.0, already credited, so no new entry; only a bigger derived file);
        Tsumiki for Japanese (CC BY-SA per its repository, already credited); Tatoeba example sentences (mostly CC BY 2.0 FR,
        some CC0; credit the project and not needed if our own video lines serve as examples, which they should);
        Wikibooks grammars (CC BY-SA 4.0, uneven quality, so only as a link-out). Not usable: Tae Kim's guide (non-commercial
        licence, we should not mix it in), Bunpro and similar (proprietary), JLPT grammar lists (no official one; unofficial
        lists are others' work). Notes of our own would be short, written and checked by hand, not generated.
      - **First slice** (small): Japanese form chains named in full in the word bar (extends the link-out item, no new data),
        then Spanish/French/German forms from a `forms` table built by the dictionary script (surface to lemma, tags), shown
        as one line in the word panel. A `LanguageProfile` property for the language's form names; the tag mapping and the
        lookup in `LangCore` with tests; new strings localisable. The `forms` data is derived, so a new file, no GRDB
        migration, out of backups. Cost: Spanish verbs alone have about 50 forms each, so roughly +20–40 MB on disk per
        language read in place, no memory or launch cost unless opened; measure from the real build before committing.
      - **Left out:** lessons and a grammar index (revisit once forms are named and used), pattern cloze cards (the sentence's
        form is reachable from the existing cloze with the form as the blank, a later and cheap option), conjugation drills,
        generated explanations, Italian, Portuguese and Dutch.
      - **To settle:** whether the form line is on by default or in Settings (a learner sees it all day); whether a cloze
        blank on a conjugated form should show the form as its hint; whether the size is acceptable per language.
- [x] **Ignore** (5 Nov 2026): a fifth word status for entries that are not worth learning (names, tokenizer mistakes). An ignored
      word is kept, hidden from the Words list (the Ignored status filter shows it, Reset brings it back), never offered as a
      lesson, and left out of coverage. Ignore is on the lesson card (X) and on the Words page. The status is stored as
      "ignored", so a backup made with it does not restore in an older Kikimi.
- [x] **Cloze cards** (Review page > Fill in the word): the example sentence with the word blanked and a short
      hint of its meaning ; you recall the word, then see it filled in with the
      sentence audio. Production in context, which avoids the ambiguity of meaning-to-word cards. **Listening
      cards** (done, Review page > Listen to the sentence): hear the sentence, answer before reading.
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

- [ ] **Conversation practice** (researched 31 Oct 2026, **waiting**): a partner that talks with you in the language you
      are learning, mostly in your own words. Apple's on-device model (macOS 27, M3) holds a short beginner dialogue in
      Spanish, French, German and Japanese in about 0.7 s a reply. A check of each reply against your word list with the
      profile's tokenizer, retrying up to twice, kept replies mostly inside it (14/15 Spanish, 12/15 French, 15/15 German
      on a 130-word list; Japanese not measured). **It cannot be trusted to correct you**: given 12 sentences with one
      error each, it fixed 6, passed 5 as "Correct" and wrongly changed 1, the same failure that ended "Explain this
      sentence". Smallest useful version: typing only, about five exchanges, no correction, 100 to 200 sampled lemmas, new
      words from your own videos, hidden without Apple Intelligence (`LangCore/Conversation/`, one view). Not measured:
      voice in and out (the on-device recognisers aren't installed here), a real vocabulary of thousands, Japanese
      word-keeping, battery, VoiceOver. A larger downloaded model (Gemma class, 2.5 GB or more, custom terms, a new
      runtime) might correct better but is untested and changes the "only a speech model downloads" promise, so it needs the
      policy first. Revisit when the built-in model improves or when correction can be checked.

- [x] **Shadowing** (5 Nov 2026; built as the Shadow card type, with the privacy policy changed first; **the recording, the permission prompt and the
      playback were not tried in the running app**): hear a line from your own video, record yourself saying it, and play both to compare. No AI, and the
      recording stays on the Mac. Needs the microphone (a sandbox entitlement and a usage string), so the privacy policy
      says so first. (From a look at JIVX's features, 3 Nov 2026.)
- [x] **Type what you hear** (3 Nov 2026): a card type on the Review page. Hear a sentence and type it; the sentence then
      shows with what you missed underlined and what you typed in error struck through, and says so for VoiceOver. A plain
      comparison of spelling (case, width and punctuation ignored, accents count), no AI and no new permission; it is only as
      right as the transcript, which Edit sentence can fix. Only short lines are offered: at most 6.5 seconds and 10 words
      (25 characters for Japanese; in the library it was written for, 91% of Japanese lines and about 75% of Spanish ones
      qualify). A word with no short line is asked as word and meaning, and a session prefers a short line when a word has
      one. Not done: slowing the audio on this card, and judging kana against kanji (a correct reading in kana counts as
      different from the kanji line).
- [x] **Review ahead** (5 Nov 2026, as a row in Practice on the Learn page): practise words that are not due yet without changing their stages ("cram"). A row in the Learn page's
      Practice area (see above).
- [x] **Kanji level and school year** (4 Nov 2026): the word panel's Kanji section shows each kanji's JLPT level and the school
      year that teaches it. KANJIDIC2's level is the exam's older four levels; they are shown as N5, N4, N3–N2 and N1 (the
      counts match: 103, 181, 739 and 1,207 kanji), with a tooltip saying so. A kanji no exam asked for shows only its year.
      A file built before this still opens, without them. Not wanted from the JIVX comparison: AI grading of what you write or say (the on-device model passed 5 of
      12 mistakes; a cloud one breaks "local and private"), gardens and other gamification, pasting video links, a
      sentence bank. Maybe later: a hands-free listening playlist of your learning words' sentences (see below).

- [x] **Noun gender and articles** (3 Nov 2026, from a look at Clozemaster): a noun shows with its article (el/la, le/la,
      der/die/das) in the word panel, the player's word bar and, once the answer is showing, on review cards. The Spanish,
      French and German dictionaries now carry each noun's gender from Wiktionary (new `gender` column; a file built before
      it still opens, with none). A word with two genders shows both ("le / la"). Where an article would be wrong the gender
      is shown instead: French before a vowel or silent h (l'eau (f)) and Spanish feminine nouns starting with a or ha (agua
      (f), because the data does not say which take el). Not done: a gender drill, German plural forms (the data has them),
      and German nouns still keep a lower-case lemma in the word list (the tokenizer lower-cases every lemma), which is why the
      phrase uses the dictionary's spelling.
- [ ] **Hands-free listening** (Clozemaster has "Radio"): the sentences of your learning words play on their own with a pause,
      and a translation only if you ask. Not wanted from that comparison: AI explanations, graded texts, rarity-chosen
      blanks, custom review intervals.

### Keeping the numbers honest
- [x] **Check what you marked known** (Review page > Review known): a quiz of up to 10 random known words; any you
      miss go back to learning, so coverage stops counting them. Self-marked words and imported lists can inflate it otherwise.
- [x] **Encounters per word**: the Words table's Seen column, and the word panel's "Seen in N lines across M videos".
- [x] **Measured the 95% claim** (26 Oct 2026, one Spanish and one Japanese transcript, 918 and 2,459 words): content words
      were 58% (es) and 40% (ja) of all words, so knowing 90% of them is about 94% (es) and 96% (ja) of everything,
      assuming the small words are known. The text now says that. A small sample; recount with more videos.
- [ ] **Resurface finished words** now and then (a sparse, rare review, or a nudge when one appears in a video), since
      stopping at the last interval can let words fade. Practice finished on the Learn page (see Practising) is the way to
      choose to do this; a sparse automatic nudge would be on top of it.
- [ ] **Benchmark NVIDIA Nemotron 3.5 ASR (0.6B) against Whisper turbo** (looked at 5 Nov 2026, **not started**). The model
      (`nvidia/nemotron-3.5-asr-streaming-0.6b`, OpenMDW-1.1 licence, which we haven't read in full) lists Japanese,
      Spanish, French, German, Italian, Portuguese and Dutch as transcription-ready and Mandarin as broad-coverage, adds
      punctuation, and is small. Against it: it is a NeMo model built for live streaming, and the app runs WhisperKit on Core ML,
      so using it means another runtime and a dependency (ask first); community Core ML and MLX conversions exist but are
      untested here; and we need accurate start and end times for each line, which we haven't confirmed. The yardstick is
      the opt-in `ImportTimingTests` on a video with a human `.srt` (large-v3 took 312 s and turbo 62 s on a 334 s Japanese
      video). The 30B Nemotron is too large to ship. Whisper large-v3 turbo is the default for Japanese as of 5 Nov 2026;
      Spanish, French and German still use `medium` and haven't been compared with turbo (needs a video and `.srt` in each).
- [ ] **Smarter review timing** (FSRS-style scheduling): low priority; the evidence is benchmark data, not trials.

### More languages
- [x] **French and German** (30 Oct 2026): each is a profile plus a Wiktionary dictionary (about 9 MB each), with the
      `medium` Whisper model and Apple's tokenizer. Checked on spoken-style sentences: German lemmas and word types
      were good (one fix: the tagger answered `koennen`, `muessen`, `duerfen` for "kann", "musst", "darf"); French has more
      mistakes (`restaurant` as a verb, `faut` as `faillir`, `commence` as a noun). Known gaps: a German separable verb
      ("ruf ... an") is learned as `rufen` and the particle is lost, and compound nouns missing from Wiktionary have no
      meaning. Not yet tried on a real French or German video, and `medium` is not benchmarked for either.
- [ ] **More languages**: Italian, Portuguese and Dutch. **Correction, 5 Nov 2026:** this item used to say Italian is next because
      Apple's tagger handles it. It does not: on macOS 27 `NLTagger` offers no lexical class and no lemma for Italian,
      Portuguese or Dutch (only language, script and token type; checked with `availableTagSchemes`, and a probe of ten
      Italian lines gave every word as "other"). So all three need a lemma source, and Italian is no cheaper than the
      others. The likeliest source needs no dependency: the Wiktionary data we already use lists every inflected form of a
      word with its tags, so a table of surface form to lemma and part of speech, built by the dictionary script, can lemmatize
      them, with an `NLTokenizer` splitting the words. The same table is what *Grammar from your own videos* needs for Spanish,
      French and German, so the two are one project. Open: how to choose among lemmas when a form is ambiguous (Italian
      *sono* is both *essere* and *suono*), measured on real lines before any language ships. Mandarin has no inflection, so
      it avoids the problem but needs a word splitter and a pinyin dictionary (CC-CEDICT, CC BY-SA); Korean is not planned.
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
