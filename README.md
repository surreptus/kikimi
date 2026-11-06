<p align="center">
  <a href="https://github.com/surreptus/kikimi/security/code-scanning"><img src="https://github.com/surreptus/kikimi/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
</p>

<h1 align="center">
  <img src="Kikimi/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="The Kikimi icon: a white asanoha star on dark green" width="64" height="64" align="absmiddle">
  Kikimi
</h1>

<p align="center">
  A native macOS app for learning a language from videos already on your Mac.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#what-it-does">What it does</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="ROADMAP.md">Roadmap</a>
</p>

---

Drop in a video. Kikimi transcribes it on your Mac and finds the words you'll meet. Then it helps you learn them with
spaced repetition, using real sentences from your own videos.

The aim is to understand more of what you watch. Spanish, French, German and Japanese work today.

- **Local files only.** Nothing is downloaded from video sites, ever.
- **On-device.** Transcription runs on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit).
- **Almost no network use.** It downloads a speech model the first time you need one, and checks for a new version
  when you ask.
- **Your originals are never modified or deleted.**

## What it does

### Videos

Each video is transcribed with timestamps, or imported with its own `.srt` or `.vtt` subtitles, which needs no speech
model. Each one shows how much of it you already know, and one button starts learning the words that would take it to
about 90%. A **Next up** card suggests the one that fits you best, heard before or not.

### Player

- Clickable, synced subtitles with meanings and furigana.
- Line looping and clips.
- Translations when you ask for them, made on your Mac.

### Words

- A searchable table with dictionary entries and example lines. Select words to learn, mark known, ignore or reset them, and undo it.
- **Japanese:** every reading of a word, and each kanji with its on'yomi and kun'yomi, JLPT level and school year.
- **Spanish, French and German:** a noun shows its article (el/la, le/la, der/die/das).

### Learn

- **Lessons.** Each day, the new words you hear most in your videos are offered as short lessons, 15 by default or none.
  You are taught a few at a time and quizzed on them at once.
- **Reviews.** Nine-stage spaced repetition. Choose the kind of card: word and meaning, fill in the word, listen to the
  sentence, type a short sentence you hear, or say it aloud and play yourself beside the original (the Shadow
  card, which uses the microphone).
- **Practice.** Review words before they are due, practise finished ones, or test the words you marked known, without
  moving the schedule.

### Your progress

It saves to a `.kikimi` file you can restore later. Restoring never overwrites what you already have.

## Install

Download the latest `Kikimi-….zip` from the [Releases page](https://github.com/surreptus/kikimi/releases/latest), unzip
it and drag **Kikimi** into Applications.

The first time you open it, macOS says it can't verify the app. That is expected: Kikimi is free and open source, and
isn't notarized yet (Apple charges a yearly fee for that). To open it:

1. Click **Done** on the warning.
2. Open **System Settings > Privacy & Security**, scroll to the message about Kikimi, click **Open Anyway** and confirm.

Each release lists a SHA-256 to check the download against. Building from source (below) avoids the warning.

<details>
<summary>Advanced: skip the warning from Terminal</summary>

<br>

Remove the download flag once, then open the app normally:

```bash
xattr -dr com.apple.quarantine /Applications/Kikimi.app
```

Do this only for a copy you trust, since it skips macOS's check.

</details>

## Finding videos to learn from

Kikimi never finds or downloads videos. It works on files you give it. If you have none, some places publish video you
may download and study, each under its own licence:

- [Internet Archive, Moving Image Archive](https://archive.org/details/movies): many films and clips can be downloaded,
  and some come with subtitle files. Drop the `.srt` with its video and Kikimi uses it instead of transcribing.
- [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Videos): free and public-domain clips, mostly short.
  Each file's page states its licence.
- [TED Talks](https://www.ted.com/about/our-organization/our-policies-terms/ted-talks-usage-policy): personal,
  non-commercial use under a Creative Commons licence. Read TED's policy for what it allows.

"Creative Commons" is not one licence. NonCommercial and NoDerivatives terms limit what you may do, and a subtitle file
can have a different licence from its video, so check each one you use. This is not legal advice. Kikimi's
[terms](Kikimi/Terms.md) say to use only videos you own or may copy and study.

## Build from source

You need macOS 15 or later (Apple silicon recommended; translations need macOS 26), Xcode 27, Python 3 and network
access.

The dictionaries are large generated files, so they aren't in the repository. Build them once:

```bash
Scripts/build_ipadic.sh         # Japanese tokenizer dictionary (~50 MB)
Scripts/build_dictionaries.sh   # JMdict, KANJIDIC2, Spanish, French and German (~2.5 GB download)
```

Then open `Kikimi.xcodeproj`, pick the **Kikimi** scheme and **My Mac**, and press ⌘R.

On the Videos page, download a speech model (about 1.5 GB for Spanish, French and German, 1.6 GB for Japanese), then
drop in a video.

Run the tests with `cd LangCore && swift test`.

## Security

The Python scripts, the website and the Swift in `LangCore` are scanned with CodeQL, and Dependabot watches the
dependencies. That looks for common mistakes. It doesn't show the code is free of problems, and the code is public so
anyone can read it. See [SECURITY.md](SECURITY.md), which also says how to report a vulnerability privately.

## Licences

The app's code is under the [MIT licence](LICENSE).

- **Dictionaries:** JMdict and KANJIDIC2 (EDRDG) and English Wiktionary via kaikki.org, all CC BY-SA 4.0. The built
  files stay under that licence, so they are built from scripts rather than committed.
- **Speech models:** OpenAI Whisper, converted by Argmax.
- **Japanese tokenizing:** [MeCab](https://taku910.github.io/mecab/) with IPADIC.

[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists every component, and the licence texts are in the app under
Acknowledgements.

## Known limits

- Accuracy depends on the model and the audio. `medium` scored about 23% word error rate on a long synthesized
  Spanish passage and hasn't been benchmarked for French or German.
- Whisper's timestamps are coarse in fast, overlapping speech, so sentence clips there can start or end slightly off.
- French lemmas are noisier than German ones, and a German separable verb ("ruf ... an") is learned as `rufen`.
- IPADIC dates from 2007, so modern Japanese slang is sometimes split or missed.
- Audio-only files aren't supported. The UI has had limited hands-on testing.

## More

- [`ARCHITECTURE.md`](ARCHITECTURE.md): where things live, the import pipeline, tests, adding a language.
- [`ROADMAP.md`](ROADMAP.md) and [`AGENTS.md`](AGENTS.md): what comes next, and how we work.
- [`Release/CHECKLIST.md`](Release/CHECKLIST.md): shipping. The bundle identifier is `com.surreptus.Kikimi`.
- [Privacy policy](Kikimi/Privacy.md) and [terms of use](Kikimi/Terms.md), shown in the app and on the website.
