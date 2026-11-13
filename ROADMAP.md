# Roadmap

This file lists what 1.0 needs and what comes after. The principles are in [AGENTS.md](AGENTS.md). Last updated 2026-11-13.

## Where we are

The core loop works. You import a video. Kikimi transcribes it on the Mac and finds its words. You play it with clickable
subtitles, learn the words with spaced repetition, see how much of each video you know, and back up your progress. Spanish,
French, German and Japanese work. Spanish and Japanese were used on real videos. French and German were checked on sentences only.

The features for 1.0 are built. The app is not ready to release. What remains is proof (a clean-machine test, observed learner
sessions), release work (signing, notarization) and a legal review. New features wait for these.

## Needed for 1.0

### Promises and paperwork
- [x] **Terms of use** (`Kikimi/Terms.md`). The app shows them beside the privacy policy.
- [ ] **Finish the terms.** The governing law is California. The contact is the GitHub issues page. A lawyer must review them,
      because a lawyer did not write them and what they can limit depends on where users live.
- [x] **Contact line** (4 Nov 2026). The privacy policy and the terms point to the GitHub issues page and say that issues there
      are public. We publish no email address.
- [x] **Licences confirmed** (25 Oct and 12 Nov 2026, against the upstream licence texts; details in the
      [release checklist](Release/CHECKLIST.md)). One gap found and closed: the EDRDG licence requires regular updates of the
      JMdict and KANJIDIC2 data. Each release now refreshes it, and `check_release_sync.py` fails if the data is more than 31 days
      old. This is not a lawyer's review.
- [ ] Privacy report (Xcode: Product > Archive > Generate Privacy Report). `PrivacyInfo.xcprivacy` must cover it, including the
      third-party packages.

### Release readiness
- [ ] Apple Developer membership, team ID, signing, notarization profile. Set the version and build number.
- [ ] **Clean-machine test** with a Release build: first launch, model download, import, play, review, export a clip, quit and
      open again. Release already showed a crash that Debug hid (AVKit was not linked; fixed), so this is not a formality.
- [ ] Walk through every screen in the final build: Videos, Words, Review, Player, Storage, Settings, About.
- [ ] **Watch first sessions** (outside feedback, 11 Nov 2026). Three to five learners each import a short video (best with
      subtitles), learn a few words and watch the video again. Someone watches, notes where they get stuck, and asks how it went.
      This is observation, not measurement. We have no analytics, so we cannot track whether they return. It comes before more
      features.
- [ ] **Check the "how much you know" bands with learners.** The figure is vocabulary coverage only: nouns, verbs, adjectives and
      adverbs (and a few Spanish conjunctions), with Stage 5 counted as known and ignored words left out. The "Mostly familiar" band (88 to 98%) rests on two
      transcripts. Ask learners if it matches what they can follow, by language and level. For Japanese near N4, look at what
      grammar and speed do to it.
- [ ] Rebuild the shareable zip from the final build.
- [ ] The website (`site/`) is live on GitHub Pages. When a notarized release exists, link Download to it. Today it links to the
      Releases page.
- [x] **Updates** (6 Nov 2026). Kikimi > Check for Updates reads one small file from the website, only when the user chooses it.
      There is no Sparkle and no automatic check. A release raises `site/public/latest.json` after it is published.

### Quality
- [x] **Japanese readings and kanji** (30 Oct 2026). A word shows all its readings. Its page lists each kanji with meaning,
      on'yomi and kun'yomi (KANJIDIC2, 12,633 kanji, 0.7 MB). Not done: show which reading a sentence used.
- [x] **First-launch welcome** (30 Oct 2026): languages, reading language, speech model download. Not seen on screen. Not done: ask
      macOS to download the translation language during setup (it needs the system sheet), and a link to run the welcome again.
- [x] **Release the speech model when idle** (after 2 minutes, never during an import).
- [ ] **Transcript performance.** It felt slow in Debug. A 20-second sample showed the main thread about 74% idle and nothing in
      our code that stood out. Confirm in a Release build with a 25-minute video. If it lags, suspects are rows that evaluate on
      hover and rows that are never released.
- [x] **Accessibility pass** (code review and fixes, 26 Oct 2026). **Still to do by hand:** use it with VoiceOver, and tab through it
      with Full Keyboard Access, in Light and Dark.
- [x] **Full backup** (Settings > Data) saves a folder with the compressed videos, transcripts and where you stopped. The small
      progress-only file does not save where you stopped. Decide if it should.
- [x] **Help > Report a Problem…** (6 Nov 2026) opens a new GitHub issue in the browser with the Kikimi and macOS versions filled
      in. Nothing is sent until the person submits it. We have no mailto link, because we publish no email address.
- [x] **App-wide text size** (8 Nov 2026, **not seen in the running app**). Four steps (1, 1.15, 1.3, 1.5 times) in Settings >
      General, and ⌘+, ⌘- and ⌘0. macOS ignores the SwiftUI text size (measured), so `Theme` makes every font and `TextScale`
      scales it. The transcript, menus, system controls and tooltips are not scaled. Check by eye at Largest: the player controls,
      the Learn cards, the Settings window and the Words table columns.

### From the review of 13 Nov 2026

A review read the source for platform practice, security, text, the website, accessibility and the learning loop. "Confirmed"
means a second read of the code agreed. All other items are reported and need a check. Nothing was run in the app.

Learning loop:
- [x] **Bug: `startLearning(wordID:)` reset a finished or learning word to stage 1** (13 Nov 2026, pull request #45). It now
      skips those words, as the bulk version does. A test covers it.
- [x] **Bug: a review session ended if a word changed status during it** (13 Nov 2026, pull request #46). The session now skips
      the card. A test covers it.
- [ ] **Limit the review load (confirmed: `dueWords` has no limit, and the intervals have no variation).** A bulk Learn of many
      words comes back as one pile at each stage. Add a limit for each session, a small random variation on each interval, and
      the daily allowance for bulk Learn. Reason: review time must not replace watching time.
- [ ] **Undo.** Add undo for a review answer, for L, K and X in the player, and for "Already know it" in a lesson. K on a
      learning word discards its stage without a message.
- [x] Build *Known and learning on each video's bar* (below) before 1.0, because Next up uses that figure.

Engineering:
- [ ] **CI (confirmed: no workflow runs the tests or builds the app).** Add a pull request workflow with `swift test` and a
      Debug build.
- [x] **`Info.plist` had `NSHumanReadableCopyright` twice** (13 Nov 2026). The empty second one is deleted.
- [ ] Show an error when a write fails. The app target has about 50 `try?` calls, and a failed status change looks successful.
- [ ] Open With and the Dock icon accept only `.kikimi` backups. Accept videos and subtitle files too.
- [ ] `VideosView.reload` measures the library folder and calls `wordsToReach` for each video. Check the cost with a large library.

Security and privacy (no high-severity finding):
- [x] **Speech model download** (13 Nov 2026): the app downloads one fixed commit of `argmaxinc/whisperkit-coreml`. It checks the
      size and SHA-256 value of every LFS file against `ModelManifest.json` before it records the model. The privacy policy names
      Hugging Face. Not done on purpose: files that are not in LFS have no SHA-256 value, and earlier installs are not checked.
- [x] **Shadow recording** (13 Nov 2026). The policy says the recording is deleted on quit. The app now deletes it at quit. The
      cleanup at launch still covers a crash. Checked with a probe file and a normal quit; a force-quit is not tested.
- [x] Restore leaves out a video whose backup folder holds a symbolic link (13 Nov 2026). A test covers it.
- [x] Workflows (13 Nov 2026): the `pages` and `id-token` permissions are on the deploy job only. Actions are pinned by commit,
      and Dependabot keeps the pins current.
- [x] Update check (13 Nov 2026): it accepts only this repository's path on `github.com`, or this project's website.

Text in the app:
- [ ] **Error messages.** Import and storage errors show raw system text and the words "re-encode", "verification" and
      "database". Each message must say what happened and what to do next. Put the raw detail behind "Show details".
- [ ] **One name for one thing.** Learn, Review, Lessons, Practice and Session overlap. "Set aside" means an ignored word and a
      reset library. "Danger zone" is above text that says nothing is deleted.
- [x] "Practice" in `AboutView.swift`, and one count of stages everywhere: eight, then Finished (13 Nov 2026). The stale catalog
      entries are removed.
- [ ] Use title case for all menu items and buttons.

Website:
- [ ] **Landing page.** Say "free Mac app" in the first line. Explain comprehensible input in one sentence. Show the beta status.
      Add a screenshot in a language other than Japanese, and one of a card.
- [ ] **Download page.** Notarization removes most of it. Until then, explain the warning in plain words, and move the Terminal
      command out of the main steps.
- [ ] **Guide.** Move the `ffmpeg` commands to a separate page. Rewrite the Lessons and Words pages in the warm style. Say that
      the first reviews come four hours after the first lesson.
- [ ] **Terms and contact.** Offer a private way to make a privacy request. Consider the plain summary as the full terms.

Accessibility (no high-severity finding):
- [ ] Pill buttons, status pills and key hints do not follow the text size setting (`Theme.swift` uses fixed sizes).
- [x] Add Playback and Review menus. Today the single-key shortcuts are on hidden buttons, so nobody can find them in the menu bar.
- [ ] Announce a review result, the next card, and a line reached with ⌘← or ⌘→ to VoiceOver.
- [ ] Contrast (reported): the stage ring is below 3:1 in Light. Muted text on the sidebar and header was 4.39:1; it is 4.83:1
      since 13 Nov 2026.
- [ ] With Increase Contrast or Differentiate Without Colour on, make the word underlines thicker.

## After 1.0

The order follows how much each item helps comprehensible input for the effort.

### Understanding the material
- [x] **Translations** (30 Oct 2026). The macOS on-device Translation framework translates one line at a time. Settings > General:
      Off, When I ask (default, so you listen first) or Always. Not done: an in-app prompt to download a missing language (it
      needs the system sheet), and context-aware translation. A language model such as TranslateGemma needs a download of about
      2.5 GB, a new dependency and the Gemma licence terms, so it waits until per-line translation proves too weak. The Apple
      framework translates each line separately and gives no alignment. Its default and high-fidelity strategies gave the same
      result on 18 real lines, so we use the default.
- [x] **Explain this sentence** (tested 27 Oct 2026, **dropped**). The on-device model in macOS 26 translated a Spanish line
      wrongly, called "qué tipo de" an "adjective phrase", and explained a Japanese line ending with the wrong line's grammar. A
      wrong grammar note is worse than none. Revisit when the model improves, or use a fixed set of checked notes.
- [x] **Japanese grammar link-out** (27 Oct 2026). The word bar names a verb's or adjective's form (from the MeCab inflection) and
      links to its Tsumiki page. Next, if wanted: map the auxiliary morphemes (させ, られ, た) to Tsumiki suffix pages (CC BY-SA,
      credited in Acknowledgements).
- [x] **Subtitle modes** (0.15.0): H hides subtitles for listening, S shows one line. **Pause after each line** (P). **Loop this
      line** (R) at 1×, 0.75× or 0.5× speed.
- [x] **Import subtitles** (.srt and .vtt, 4 Nov 2026). Kikimi uses the cues and skips transcription and the speech model. Files
      pair by name. Kikimi checks the language from the text and refuses other languages (English subtitles, for example). Not
      done: choose a subtitle file for a video already in the library, and the formats .ass and .ttml.
- [ ] **Subtitles inside a video file, with a way to choose the track** (scoped 11 Nov 2026, **not started**). An MP4 or MOV can
      hold several subtitle tracks, often one per language. Kikimi reads only a separate `.srt` or `.vtt`.
      - Choosing is the main point, because a wrong track is refused or, worse, used. With more than one text track, ask which to
        use. List each by language and name, with the track in the video's language ticked. With one track in the right language,
        use it without asking. Check it like a subtitle file.
      - Offer the same choice for a video already in the library, in the Info sheet's "Add subtitles": one menu with a file from
        disk or a track inside the video. This also covers the "choose a subtitle file for a video already in the library" item.
        Every row works by keyboard and VoiceOver.
      - AVFoundation reads subtitle tracks in MP4, MOV and M4V. A `mov_text` sample is a length-prefixed string with style boxes
        after it, so the text needs unwrapping. **AVFoundation cannot read MKV**, and most embedded tracks are in MKV. Those files
        still need the ffmpeg step in the guide. Support for them needs a demuxer, which is a dependency (ask first). Picture-based
        tracks (DVD, Blu-ray) are not text. Do not offer them.
      - Test with real files: one `mov_text` track, two, none, and a missing or wrong language tag. Add a test for a cue time
        offset (a track often starts after the video).
- [x] **Edit a transcript line** (right-click a line > Edit line…). It fixes the text and the timing, and finds the words again.
- [ ] **Word-level timestamps**, so that one word can play and clips are tighter. **Partly done (12 Nov 2026).** Transcription asks
      Whisper for word times (same speed, same text). A line longer than 6.5 s (`maxSegmentSeconds` in the language profile) is cut
      at its longest pause between words, again while still too long (`SegmentSplitter`). Test: one 5-minute Japanese video with
      human subtitles. Lines over 6.5 s went from 12 to 0. The share of human cue breaks that a cut also hits (within 0.6 s) went
      from 42% to 57%. Text and time did not change. Lines under 1.2 s went from 0 to 6. One video is too few to tune the limit or
      compare languages, so next we need a set of videos with same-language human subtitles for each language. **Tried and not
      taken:** a punctuation prompt (every line ends with a mark, but Whisper then writes lines of 14 s and the cuts match worse),
      and the on-device language model that rewrites text (it changes words). The model that only groups Whisper's own pieces
      writes no text and works, but it merges too much and needs macOS 26. Still to do: play one word, and tighten clips to words.

### Finding the right material
- [x] **Known and learning on each video's bar** (suggested 12 Nov 2026, agreed 13 Nov 2026, built 13 Nov 2026, **not seen in the running app**). Today the bar counts only
      known words: known, finished, or learning at Stage 5 and up (`knownCondition` in `Coverage.swift`). A word you are
      learning at Stages 1 to 4 counts as unknown, so a video made of words you are working on reads as hard. Proposal: a
      second, lighter segment for learning words. The text keeps the known figure and the fit word, and adds the learning
      share ("82% known, 6% learning"). The segments differ in length and fill, never in colour alone, and VoiceOver reads
      both figures. The fit word stays on known words: a Stage 1 to 4 word is recognised only with effort, so counting it
      would call a video easy before it is. Built as proposed: `VideoCoverage.learningWords`, a lighter bar segment, and the learning share in the text and
      the VoiceOver label. No new table, no migration.
- [ ] **Long tail on the bar.** A learning word seen once in a video could count as known sooner than a common one. We have no data
      for this, so the fit rule stays on known words until it is measured on real videos.
- [x] **Next up** (5 Nov 2026). A card on Videos suggests the video that fits best, by fit alone. A video you heard is as good a
      choice as a new one, because listening again is how a nearly understood video becomes understood.
- [ ] **Frequency-list bootstrap.** Mark the most common words as known for a beginner. It needs a data source and a licence
      decision first.
- [x] **Calibrate on the first video** (6 Nov 2026, **not seen in the running app**). "Mark the words I know" shows a video's
      most-seen new content words, 20 at a time, up to 120. The learner ticks the words they know. It stops when half a
      batch is unknown. A last screen says how many words become known, and Undo is offered. Reason: a new learner has nothing
      marked known, so every video reads as mostly unknown and the first lessons teach words that the learner knows. It needs no
      frequency list and no new data, so it has no licence question. **It does not give a level label** ("B1"): the app has no
      validated map from words known to a level. Risks: people over-claim, and one short video gives a noisy ranking.
- [ ] **Audio files** (podcasts that you downloaded; scoped 11 Nov 2026, **not started**). Import an MP3, M4A or similar like a
      video, with or without a transcript. After import, everything already works from the text and its times, so the work is at
      the two ends. Estimate: a few days, one pull request.
      - Import: today the pipeline re-encodes to HEVC and rejects a file with no video track. Audio needs its own path: AAC (or keep
        the file), no video checks, and the same order, atomic move and clean-up after a failure.
      - Player: `PlayerView` assumes a picture. Make an audio layout with a large transcript. Check loop, pause after each line,
        hide subtitles and clip export.
      - Small items: a thumbnail for an episode (cover art, else a plain tile), the Info sheet, and backup and restore.
      - A transcript without times (plain text, HTML, Podcasting 2.0 JSON) is not supported. Such an episode is transcribed. Aligning
        a supplied text to the audio is a later job.
      - **Not included, on purpose: feeds and episode downloads.** AGENTS.md principle 7 limits the network to speech models and
        update checks. A downloader changes the privacy policy and needs a feed parser and probably a dependency. A file that the
        user downloads and drops in gives most of the benefit.
      - To settle: the app says "videos" everywhere, and audio needs a word for both ("media"). Keep it out of the UI until the
        feature exists.

### Practising
- [x] **Learn page with three paths** (built 5 Nov 2026, seen on screen 6 Nov 2026). **Lessons** (the day's new words), **Reviews**
      (the count due) and **Practice** (extra study that moves no stage: *Review ahead*, *Review known*, *Practice finished*).
      "Known" is what you marked. "Finished" is what you earned by passing every review. A miss in *Practice finished* changes
      nothing. The sidebar count stays "reviews due".
- [x] **Daily lessons** (5 Nov 2026, seen on screen 6 Nov 2026). Each day Kikimi queues the most important words that you have not
      started: 15 for each language by default (Settings > Languages; 0 turns it off). Unused lessons lapse. No lessons are offered
      while more than 100 reviews are due. Words come from your own videos, ranked by how many lines they appear in. A lesson
      teaches five words one by one (sentence, audio, meaning), then quizzes them at once and asks a missed word again until it is
      right. The words then start at stage 1, with the first review 4 hours later. "Already know it" marks a word known. Reason:
      without lessons, a person with videos but no habit meets an empty Review page.
- [ ] **Grammar from your own videos** (researched 5 Nov 2026, direction **agreed 12 Nov 2026**, not started). Noticing, not a
      course. Decision: show the **forms of the words you meet, on demand, with a link out**. No lesson path. No rules taught ahead of the material. Grammar
      belongs to the word you look at, so it belongs in the player and the word panel, not on Learn.
      - **Detection.** Japanese: good. MeCab and IPADIC give the inflection form and the auxiliaries, and a fixed table in the
        profile names a chain. Spanish, French, German: `NLTagger` gives only lemma and part of speech. A form can be named by
        looking up the *surface* in the dictionary's inflected forms (kaikki has each `form_of` sense with tags, and
        `build_kaikki.py` drops them today). Ambiguity is real (Spanish *hable*, German *die*): show every reading or none, never
        one guess. We cannot detect syntax, use, or the German case of a noun phrase. Not measured: how often the lookup is
        unambiguous on real lines. Measure before building.
      - **Sources.** Wiktionary forms through kaikki.org (CC BY-SA 4.0, already credited). Tsumiki (CC BY-SA, already credited).
        Tatoeba (mostly CC BY 2.0 FR; not needed if our own video lines serve as examples). Wikibooks (CC BY-SA 4.0, uneven, so
        only a link out). Not usable: Tae Kim's guide (non-commercial), Bunpro (proprietary), JLPT grammar lists (no official one).
        Check each licence text before use. Our own notes would be short and checked by hand, never generated.
      - **First slice.** Japanese form chains named in full in the word bar (no new data). Then Spanish, French and German forms
        from a `forms` table that the dictionary script builds, shown as one line in the word panel. The mapping and lookup go in
        `LangCore` with tests. The data is derived (a new file, no migration, out of backups). Cost: about +20 to +40 MB on disk for
        each language, read in place. Measure from the real build.
      - **Left out:** lessons, a grammar index, pattern cloze cards, conjugation drills, generated explanations.
      - **To settle:** the form line on by default or in Settings; a conjugated cloze blank showing its form as the hint; the size
        for each language.
- [ ] **Deleting a video that taught you words** (checked in code 12 Nov 2026, not run). Progress is kept: words you started,
      review or marked known keep their stage and dates. Their example sentences go, so their cards become word and meaning
      only, and the word panel shows no line from your videos. Importing the file again brings the sentences back. Decision:
      keep this behaviour. The delete dialog says that those words lose their example lines (13 Nov 2026). Not
      checked: a lesson already queued for a word that the deletion removes.
- [x] **Ignore** (5 Nov 2026). A fifth word status for names and tokenizer mistakes. An ignored word is kept, hidden from the Words
      list (the Ignored filter shows it), never offered as a lesson, and left out of coverage. A backup that contains it does not
      restore in an older Kikimi.
- [x] **Cloze cards** and **listening cards** (Review page). Cloze: the sentence has the word blanked, with a short hint. This is
      production in context and avoids the ambiguity of meaning-to-word cards.
- [ ] **Reverse (meaning to word) cards**, only as an optional extra: off by default, only for words at about stage 4 or higher,
      and counted in the overview. Prefer cloze. Reason: reviews are recognition only, and receptive practice does not reliably
      carry over to producing a word.
- [x] **Learning stats over time** (Review page > Your progress, in the full backup): words learned each week, hours of listening
      and how often you look up each word. The log stays on the Mac.
- [x] **Anki export** (File > Export Words to Anki…, since 6 Nov 2026). A local text file that Anki imports (word, meaning, example
      sentence), with optional sentence audio. Checked with the Anki 25.09 importer: notes go to a "Kikimi Spanish" deck, and
      exporting again updates them.
- [ ] **Conversation practice** (researched 31 Oct 2026, **waiting**). A partner that talks with you in your learning language,
      mostly in words you know. The Apple on-device model (macOS 27, M3) holds a short beginner dialogue in all four languages,
      about 0.7 s a reply. Checked against your word list with the profile tokenizer (retry up to twice), replies mostly stayed
      inside it: 14 of 15 Spanish, 12 of 15 French, 15 of 15 German with a 130-word list (Japanese not measured). **It cannot be
      trusted to correct you.** Given 12 sentences with one error each, it fixed 6, passed 5 as "Correct" and changed 1 wrongly.
      This is the failure that ended "Explain this sentence". Smallest useful version: typing only, about five exchanges, no
      correction, hidden without Apple Intelligence. Not measured: voice, a vocabulary of thousands, Japanese word-keeping,
      battery and VoiceOver. A larger downloaded model (Gemma class, 2.5 GB or more) might correct better, but it is untested and
      it changes the "only a speech model downloads" promise, so it needs the policy first. Revisit when the built-in model
      improves.
- [x] **Shadowing** (5 Nov 2026, the Shadow card type; the privacy policy changed first). Hear a line, record yourself, play both.
      There is no AI. The recording stays on the Mac. **The recording, the permission prompt and the playback were not tried in the
      running app.**
- [x] **Type what you hear** (3 Nov 2026). Hear a sentence and type it. The result marks what you missed and what you added. It is a
      plain spelling comparison (case and punctuation ignored, accents count), with no AI. It offers only short lines (at most 6.5
      seconds and 10 words; 25 characters for Japanese). Not done: slow audio, and judging kana against kanji.
- [x] **Review ahead** (5 Nov 2026), a row in Practice.
- [x] **Kanji level and school year** (4 Nov 2026). KANJIDIC2 has the older four-level exam. The app shows N5, N4, N3–N2 and N1 (the
      counts match: 103, 181, 739 and 1,207 kanji), with a tooltip that says so. Not wanted (from the JIVX comparison): AI grading
      of what you write or say (the on-device model passed 5 of 12 mistakes; a cloud model breaks "local and private"), gamification,
      pasted video links, a sentence bank.
- [x] **Noun gender and articles** (3 Nov 2026). A noun shows its article (el/la, le/la, der/die/das), from Wiktionary data. A word
      with two genders shows both. Where an article would be wrong, the gender shows instead (French l'eau (f); Spanish agua (f)).
      Not done: a gender drill, and German plural forms.
- [ ] **Hands-free listening** (Clozemaster has "Radio"). The sentences of your learning words play on their own with a pause, and
      a translation only if you ask. Not wanted from that comparison: AI explanations, graded texts, blanks chosen by rarity,
      custom review intervals.

### Keeping the numbers honest
- [x] **Check what you marked known** (Review page > Review known). A quiz of up to 10 known words. A word you miss goes back to
      learning. Without it, self-marked words and imported lists can inflate coverage.
- [x] **Encounters per word:** the Words table's Seen column, and "Seen in N lines across M videos".
- [x] **Measured the 95% claim** (26 Oct 2026; one Spanish and one Japanese transcript, 918 and 2,459 words). Content words were 58%
      (Spanish) and 40% (Japanese) of all words. So 90% of content words is about 94% (Spanish) and 96% (Japanese) of everything,
      if the small words are known. The text says so. This is a small sample. Count again with more videos.
- [ ] **Resurface finished words** now and then (a rare review, or a nudge when one appears in a video), because stopping at the
      last interval can let words fade. Practice finished lets a person choose to do this. An automatic nudge would be on top.
- [ ] **Benchmark NVIDIA Nemotron 3.5 ASR (0.6B) against Whisper turbo** (looked at 5 Nov 2026, **not started**). The model
      (OpenMDW-1.1 licence, not read in full) lists our four languages, adds punctuation and is small. Against it: it is a NeMo
      model for live streaming and the app runs WhisperKit on Core ML, so it needs another runtime and a dependency (ask first).
      Community Core ML and MLX conversions are untested here. We need accurate start and end times for each line, and we have not
      confirmed that it gives them. The measure is the opt-in `ImportTimingTests` on a video with a human `.srt` (large-v3 took
      312 s and turbo 62 s on a 334 s Japanese video). Turbo is the default for Japanese since 5 Nov 2026. Spanish, French and
      German still use `medium`, and nobody compared them with turbo (it needs a video and `.srt` for each).
- [ ] **Smarter review timing** (FSRS-style). Low priority. The evidence is benchmark data, not trials. The review limit and
      interval variation (review of 13 Nov 2026) come first and cost less.
- [ ] **The meaning used in the line, and phrases** (review of 13 Nov 2026). A card shows the first dictionary meaning, not the
      one the line uses. Phrases ("por favor") are not kept. German nouns are stored in lower case (`Tokenizer.swift`); check
      how they show.
- [ ] **Playback speed and a subtitle time offset** (review of 13 Nov 2026). Speed exists only for a looped line.
- [ ] **Swift 6 language mode** (review of 13 Nov 2026). Both targets use Swift 5 mode, with 12 `@unchecked Sendable` types.
      Turn on the strict concurrency warnings first.

### More languages
- [x] **French and German** (30 Oct 2026): a profile, a Wiktionary dictionary (about 9 MB each), the `medium` Whisper model and the
      Apple tokenizer. French has more lemma mistakes. A German separable verb ("ruf … an") is learned as `rufen` and the
      particle is lost. Compound nouns that Wiktionary lacks have no meaning. Not yet tried on a real French or German video, and
      `medium` is not benchmarked for either.
- [x] **Verb forms for Spanish, French and German** (6 Nov 2026). The Apple tagger read *puedo* as a form of *podar*, *sale* as
      *salar*, *venga* as *vengar* and *creo* as *crear*. Each dictionary now has a `forms` table (220,000 forms for Spanish, 88,000
      French, 37,000 German). The tokenizer overrules a verb that the spelling cannot be a form of, and reads a spelling that is no
      word of its own as the verb it is. An audit test checks sampled spellings: 99.97% of Spanish, 99.8% of French and 99.2% of
      German lemmas are right, and none is another verb. This applies to videos imported from now on. Words already imported keep
      their old lemmas, because there is no way yet to read a video again.
- [ ] **More languages:** Italian, Portuguese and Dutch. **Correction, 5 Nov 2026:** `NLTagger` on macOS 27 gives no lexical class
      and no lemma for these three (checked with `availableTagSchemes`; ten Italian lines all returned "other"). All three need a
      lemma source. The likeliest source needs no dependency: the Wiktionary data that we use lists every inflected form with
      tags, so the dictionary script can build a table of surface form to lemma and part of speech, with `NLTokenizer` to split
      words. The *Grammar from your own videos* item needs the same table, so the two are one project. Open: how to choose among
      lemmas when a form is ambiguous (Italian *sono* is *essere* or *suono*). Mandarin has no inflection but needs a word splitter
      and a pinyin dictionary (CC-CEDICT, CC BY-SA). Korean is not planned.

### Housekeeping
- [x] **Find words again** (13 Nov 2026). Settings > Data re-reads the saved lines of every video (edited lines too) with the current
      tokenizer, so fixes reach videos imported earlier. It needs no video file, model or network. It only changes occurrences
      and adds new words; status, stage, review dates and activity stay, and words you have worked with that are found in no video any more are kept. A `new` word with no activity and no occurrence is
      removed, as editing a line does. Each video
      is one transaction, and a second run changes nothing. No migration and no version stamp on videos. Not done: running it
      automatically, and undo (nothing of yours changes, so there is a confirmation instead). Not seen in the running app.
- [ ] Cache video thumbnails on disk if scrolling a large library feels slow.
- [ ] **Translate the app's own interface.** The groundwork is done (strings are localisable, in two string catalogs). To add a
      language: add it to each catalog in Xcode, translate (Product > Export Localizations), add localised copies of `Privacy.md`
      and `Terms.md` and `InfoPlist.xcstrings`, and run the app with the double-length pseudolanguage to find text that no longer
      fits. Several windows have fixed widths.

## Decisions

Made:
1. **Direct download** for 1.0, not the Mac App Store. It needs a Developer ID, notarization and a download page. The App Store
   can come later.
2. **Free.** The terms say so plainly (no payment, provided as is). A donation link is optional.
3. **More languages after Spanish and Japanese.** French and German are done. Italian, Portuguese and Dutch are next.

Open:
1. Whether an always-visible translation should exist at all.

## Not doing
- Downloading from YouTube or any video site. Ever.
- Accounts, sync servers, analytics, or anything that sends your data off the Mac.
- Changing or deleting your original files.
