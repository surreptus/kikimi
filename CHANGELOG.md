# Changelog

What changed in each version of Kikimi, newest first. Every release's page on GitHub has these notes with its download and checksum.

## 0.15.1

*6 November 2026.* Spanish verbs are read correctly, a quieter Learn page, and fixes to hidden subtitles and the first-video card.

### New

- **Spanish verbs are read correctly.** Apple's word-splitting read every present-tense form of *poder* as *podar* (puedo, puede, pueden), *sale* as *salar*, *venga* as *vengar* and *creo* as *crear*. The Spanish dictionary now carries a table of common verbs' spellings that corrects these. It applies to videos you import from now on, not to words already imported.
- **A quieter Learn page.** Coming up, the stage rings and the weekly chart appear only once there is something in them, and the stage explanation is shorter.
- **The Words page with no words** shows only the way to Videos. In the word panel, an example sentence's video title and time open the video.

### Fixed

- A translation now waits with its line when subtitles are hidden.
- The first-video card is kept for each language, not once for the whole app.
- Clearer wording: coverage reads "of words known", the Shadow card says "Listen, then repeat the sentence aloud", and the first-video card says "to about 90% of its words known".

## 0.15.0

*6 November 2026.* Say a sentence aloud and compare yourself with the original, hide the subtitles to listen, and a clearer Learn page and first run.

### New

- **The Shadow card.** Hear a short sentence from your videos, say it aloud, and play yourself beside the original. It uses the microphone only while you press Record, keeps the recording only while the card is open, and never uploads, transcribes or analyses it. The privacy policy says so.
- **Card types are Meaning, Fill in and Sentence.** For Sentence, a menu chooses how you answer: listen and check, type it, or say it aloud.
- **The Learn page leads with one action:** reviews while any are due, then lessons.
- **Hide subtitles** in the player (H) to listen without reading. S shows one line.
- **A Next up card** on Videos suggests the video that fits you best.
- **The first video gets a card** of next steps: watch it, or learn the words that would make it followable. The speech-model card now says it is only for videos without subtitles.
- **Coverage says "of words known"**, since knowing the words is not the same as understanding a video.

### Fixed

- **Spanish "muy"** and about 680 other short forms were missing from the dictionary. The Spanish dictionary is rebuilt; French and German are unchanged.
- The subtitle file chooser now lets you pick `.srt` files.
- The Learn, Known and Ignore buttons in the word strip no longer squash into the word in a narrow panel.

## 0.14.1

*6 November 2026.* A much faster speech model for Japanese, a way to check for new versions, and a round of fixes found by using the app.

### New

- **Faster Japanese transcription.** Japanese now uses Whisper large-v3 turbo (1.6 GB, down from 3 GB). On a 5-minute Japanese video it transcribed 8 times faster than large-v3 (the whole import took about 1 minute instead of 5) and made fewer of the mistakes we checked. If you already have large-v3 installed and have not chosen a model, you keep it; choose turbo in Settings > Languages. This is from one video, and Spanish, French and German still use medium.
- **Check for Updates** in the Kikimi menu. It reads one small file from the website, only when you choose it, and sends nothing else. The privacy policy now says so.
- **Ignore.** In the word panel and the player, as well as on lessons and the Words page: set aside a name or a mistake. Restore brings it back.
- **The word is picked out** in orange and bold in its sentence on review and lesson cards.
- **The typing exercise switches your keyboard** to the language's (for example Japanese) when you have one installed, and switches back after.

### Fixed

- **Japanese words.** 「それはね」 and 「私はね」 are no longer read as the verb はねる, 行った is 行く and not 行う, and a hiragana word like やすみ before だ is a noun.
- **Fill-in cards for Japanese** show the meaning only, not the reading, which gave the answer away.
- **Editing a sentence** so it no longer contains the card's word now skips the card instead of leaving it broken.
- **Plainer wording:** error screens say what to do, the Settings notes are shorter, the stage rings are explained, and the import button says Start import. The welcome page sits on the window colour.

## 0.14.0

*5 November 2026.* Lessons that teach and then quiz, a Learn page, and a way to set aside entries that are not words.

### New

- **Lessons.** Each day Kikimi offers the new words you hear most in your videos, 15 by default (Settings > Languages > New words a day; Off hides them). A lesson teaches five at a time, each with its meaning and a sentence from your video, then quizzes those five straight away in word-and-meaning form. A missed word is asked again until it is right. The words join your reviews only when the quiz is finished, with their first review hours later; leaving half way starts none of them.
- **A Learn page.** The Review page is now Learn: a Lessons card, then Reviews with the card type, and Practice inside the same panel (Review ahead, Review known and Practice finished). Practice moves nothing, except that a known word you miss goes back to learning.
- **Ignore.** Set aside a name, a mistake or punctuation from a lesson (X) or the Words page. An ignored word is kept, hidden from the Words list, never offered as a lesson and left out of how much of a video you know. Show it with the Ignored filter and press Reset to bring it back.
- **Punctuation in subtitle files** (`!`, `?`) is no longer read as a word in Japanese, and the ones already stored are removed the first time you open this version. Words you chose to learn or know are kept.
- **Keys on the buttons**, and **Help > Keyboard Shortcuts**. Captions are a little larger (14 pt), and every animation uses one ease-out curve.

## 0.13.0

*5 November 2026.* Import with subtitle files, a clearer first run, and the keys shown on the buttons.

### New

- **Import with subtitles.** Add a video, then **Add subtitles** for an `.srt` or `.vtt` file and press **Start**. Nothing is transcribed, so no speech model is needed.
- **A clearer first import.** The Videos page states the goal and four steps, explains the speech model as a one-time download (its size, and that nothing is uploaded), and says you can use other pages while it runs.
- **Keys on the buttons.** Show answer, Got it, Missed it, Play sentence, Learn and Known show their key. **Help > Keyboard Shortcuts** opens the full list.
- **Kanji levels.** A kanji shows its JLPT level and school year in the word panel.
- **A welcome page with language tiles** and flags.
- **Easier to follow.** The percentage on each video is explained, the empty Words and Review pages have a button to the next step, and How it works is shorter.
- **Accessibility.** VoiceOver hears the selected page and the number of reviews due. Known words in the player get a dotted underline, so colour is not the only sign.
- **Smoother.** Every animation uses one ease-out curve, and the Settings window no longer jumps between tabs.

## 0.12.0

*4 November 2026.* Kikimi now supports macOS 15 and later, and the Review page is easier to use.

### New

- **macOS 15 and later.** It used to need macOS 26. Translations still need macOS 26: on macOS 15 to 25 every translation control is hidden and nothing else changes.
- **A clearer Review page.** The top panel reads *Reviews* with the number due and **Start** beside it. Under it, the kind of card is four icon buttons (Meaning, Fill in, Listen, Type), and the line below changes with your choice. The quiz of known words is now a row, *104 known* with a **Review known** button, in place of "Check my known words".
- **The word panel no longer flashes** when you move from word to word on the Words page, and it starts at the top each time.
- **A fuller About Kikimi window** (in the Kikimi menu): what the app is, links to the licence, website, source code and problem reports, and the credits.
- **A contact for the privacy policy and terms:** the GitHub issues page. Issues there are public, so don't put personal details in one. No email address is published.

## 0.11.0

*3 November 2026.* Noun genders for Spanish, French and German, and a new way to practise listening.

### New

- **Noun gender, with the article.** A Spanish, French or German noun now shows with its article, such as *das Buch* or *la casa*, in a word's dictionary entry, in the player's word bar, and on a review card once the answer is showing. A word with two genders shows both (*le / la livre*). Where a plain article would be wrong, the gender is shown instead: *l'eau (f)* in French, and *agua (f)* in Spanish, where a stressed *a* takes *el*. The genders come from Wiktionary, and senses meant for one region or for slang are ignored.
- **Type what you hear.** A new kind of card, chosen in the menu above Start reviewing. A short sentence from your videos plays and you type it. You then see the sentence with what you missed underlined and anything you typed in error struck through, and it is described for VoiceOver. Capitals, punctuation and width are ignored; accents count. Only short lines are offered (up to 6.5 seconds and 10 words, or 25 characters in Japanese), and a word with a short line gets that one. A word with none is asked as word and meaning.

- **The card type moved to the top of the Review page**, above every panel, because it decides the cards of your reviews and of Check my known words alike.
- **No more flashing in the word panel.** Moving from one word to the next on the Words page used to rebuild the panel empty each time; it now stays in place and fills in with the next word's details.

## 0.10.0

*3 November 2026.* Fixing a transcript from anywhere you notice the mistake, a word's page inside Review, and messages that go away by themselves.

### New

- **Review:** once the answer is showing, click the word (or press I) to open its page beside the card. A ⋯ button next to Play sentence translates the sentence (T) or fixes it (E) when the transcript got it wrong; the translation follows your Settings.
- **Choosing the kind of card:** Word and meaning, Fill in the word or Listen to the sentence is now picked at the top of the Review page, just above Start reviewing, instead of in Settings. In a listening card the answer now shows the sentence's translation by default (unless translations are off); T hides it.
- **Player:** each line has a ⋯ button, shown when you point at it or tab to it, with Translate, Edit line and the clip exports. It has the same list as the right-click menu, and E edits the line you are on.
- **Messages that go away:** "Started learning 25 words", "Marked as known", export results and similar now appear as a short message over the window instead of a line in the page. It disappears after a few seconds (eight for an error), stays while you point at it, can be closed, and is read out by VoiceOver.
- **Fixing a wrong word:** resetting a word that is in none of your lines now removes it, so a word made by a transcript mistake can be cleaned up: edit the line, then reset the word.
- Each kanji on a word's page is top-aligned with its description.

## 0.9.2

*30 October 2026.* A pass on how the app feels to use, and the interface in four more languages.

### New

- **The app in Spanish, French, German and Japanese**, following your Mac's language. These are machine-made drafts that no native speaker has reviewed yet, so expect some awkward wording. The privacy policy, terms and "How it works" stay in English.
- **Videos:** one drop area that shrinks to an "Add videos…" row once your library has videos, "Download model" shows its size, and "Best fit first" is now "Closest to my level".
- **Player:** clicking a word now only shows its meaning and no longer moves the video. ⌘← and ⌘→ jump between lines, ⌘↓ moves the keyboard into the transcript, and a strip under the video lists the shortcuts.
- **Review:** the card front shows the word inside the sentence from your video.
- **Words:** a "Start with the 25 words you hear most" button on a fresh list, kanji at the top of a word's page, and Learn shown only for new words.
- **First launch:** the welcome page is down to choosing your languages and Start. The language you read is the Mac's, changeable in Settings > General, and the speech model download is on the Videos page, where it says what it costs.
- Review stage labels say "1mo" and "4mo" instead of "1m" and "4m", and one small label is now 12 pt.

## 0.9.1

*30 October 2026.* French and German, a first-launch welcome page, translations on request, and more for Japanese readers.

### New

- **French and German**, joining Spanish and Japanese. Each has a Wiktionary dictionary and uses the `medium` speech model. French lemmas are noisier than German ones, and a German separable verb ("ruf ... an") is learned as `rufen`.
- **A welcome page on first launch**: choose the languages you are learning, the language you read (the Mac's by default), and download each speech model now or later. Each model is shown once, with the languages that use it. Settings > Languages changes the choice later; a language you drop is only hidden, and its words and videos are kept.
- **Translations when you ask**: a line's translation is made on your Mac by macOS's own Translation and shown when you press its translate button or T. Settings > General can turn it off or show it always. If the language isn't installed, the status line says where to add it.
- **Every reading of a Japanese word**: 月 is つき, がつ and げつ. The player's word bar and the review cards list them, with the reading the sentence used first.
- **Kanji on a word's page**: each kanji in a Japanese word with its meaning and its on'yomi (katakana) and kun'yomi (hiragana), from KANJIDIC2.

### Data

KANJIDIC2 (EDRDG, CC BY-SA 4.0) is new and is listed in the Acknowledgements. Translations use macOS, and nothing of ours is sent anywhere.

## 0.9.0

*28 October 2026.* Learn Spanish or Japanese from videos you already own. Drop in a video, Kikimi transcribes it on your Mac, finds the words you'll meet, and helps you learn them with spaced repetition, using real sentences from your own videos. Nothing leaves your Mac, and nothing is downloaded from video sites.

### Import and library

- Add a video file you own; it's transcribed on-device with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (speech models download once, when you ask). The spoken language is checked first, so a Japanese video can't be imported as Spanish by mistake. Imports show progress and time left, can be cancelled, and never change your original file.
- The library keeps a small compressed copy of each video by default, or your file exactly as it is (Settings > General > Video quality). The speech model is released after two idle minutes.
- Each video shows how much of it you already know ("91% known · Comfortable"), with a preview still, and you can sort by best fit and start learning the commonest words that would take a video to about 90%. Rename videos, see their size and location, and pick up where you stopped.

### Player

- Synced, clickable subtitles: hover or pin a word for its meaning, start learning it or mark it known, with furigana for Japanese. Everything works by keyboard and VoiceOver.
- Pause after each line (P), loop a line (R) at 1x, 0.75x or 0.5x, fix a line's text or timing, and save audio or video clips. The transcript text size is a setting.
- For Japanese verbs and adjectives, the word bar names the form (未然形, 連用形...) and links to the matching page of [Tsumiki](https://surreptus.github.io/tsumiki/).

### Words

- A sortable, searchable table with status and type filters and bulk actions. Each word has its dictionary entry (JMdict for Japanese, Wiktionary for Spanish), how often you've seen it, and example sentences with audio you can play in place.
- Export to Anki (checked against Anki 25.09's own importer), and mark a list of words you already know from a text or CSV file.

### Review

- An overview first: reviews ready, the next seven days, words at each stage, and your progress (listening time, accuracy, words started per week, words looked up most).
- Nine-stage spaced repetition. Cards can ask word and meaning, fill in the word, or listen to the sentence, and "Check my known words" quizzes a sample of what you marked known so coverage stays honest.

### Your data

- Save your progress to a small `.kikimi` file, or a full backup folder with the compressed videos, transcripts and history. Restoring never overwrites what you already have and is safe to run twice.

### Look and feel

- A green window around a warm off-white (or very dark green) card, Light and Dark, an asanoha star icon whose Dock version follows the app's appearance, an accessibility pass, and all text ready for translation (English only for now).

### Privacy, legal and the website

- Privacy policy, terms of use (California law), Acknowledgements and third-party notices, all shown in the app and on the [website](https://surreptus.github.io/kikimi/). Kikimi is MIT licensed; its dictionaries are CC BY-SA 4.0 adaptations of JMdict and English Wiktionary.
