<img src="Kikimi/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="The Kikimi icon: a white asanoha star on dark green" width="96" height="96">

# Kikimi

A native macOS app for learning a language from videos you already own.

Drop in a video. Kikimi transcribes it on your Mac, finds the words you'll meet, and helps you learn them with
spaced repetition, using real sentences from your own videos. The aim is to understand more of what you watch.
Spanish, French, German and Japanese work today.

- **Local files only.** Nothing is downloaded from video sites, ever.
- **On-device.** Transcription runs on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit). The
  only network use is downloading a speech model the first time you need it, and checking for a new version when you ask.
- **Your originals are never modified or deleted.**

[![CodeQL](https://github.com/surreptus/kikimi/actions/workflows/codeql.yml/badge.svg)](https://github.com/surreptus/kikimi/security/code-scanning)
Scanned with CodeQL and watched by Dependabot; see [SECURITY.md](SECURITY.md) for what that does and doesn't show.

## What it does

- **Videos.** Transcribed with timestamps, or imported with their own `.srt` or `.vtt` subtitles, which needs no speech
  model; each shows how much of it you already know, and one button starts
  learning the words that would take it to about 90%.
- **Player.** Clickable, synced subtitles with meanings, furigana, line looping, clips, and translations when you
  ask for them (made on your Mac).
- **Words.** A searchable table with dictionary entries, example lines and Anki export. For Japanese, every reading
  of a word and each kanji with its on'yomi and kun'yomi, JLPT level and school year. For Spanish, French and German, a noun shows its article
  (el/la, le/la, der/die/das).
- **Learn.** Each day, the new words you hear most in your videos are offered as short lessons (15 by default, or
  none). Then nine-stage spaced repetition. Choose the kind of card on the Learn page: word and meaning, fill in the
  word, listen to the sentence, or type a short sentence you hear. Under Practice, review words before they are due or
  practise finished ones without moving the schedule, or test the words you marked known.
- **Your progress** saves to a `.kikimi` file you can restore later; it never overwrites what you already have.

## Finding videos to learn from

Kikimi never finds or downloads videos; it works on files you give it. If you have none, some places publish video you
may download and study, each under its own licence:

- [Internet Archive, Moving Image Archive](https://archive.org/details/movies): many films and clips can be downloaded, and some
  come with subtitle files (drop the `.srt` with its video and Kikimi uses it instead of transcribing). Each collection has
  its own terms.
- [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Videos): free and public-domain clips, mostly short. Each
  file's page states its licence.
- [TED Talks](https://www.ted.com/about/our-organization/our-policies-terms/ted-talks-usage-policy): personal, non-commercial
  use under a Creative Commons licence. Read TED's policy for what it allows.

"Creative Commons" is not one licence. NonCommercial and NoDerivatives terms limit what you may do, and a subtitle file can
have a different licence from its video, so check each one you use. This is not legal advice. Kikimi's
[terms](Kikimi/Terms.md) say to use only videos you own or may copy and study.

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

Remove the download flag once, then open the app normally:

```bash
xattr -dr com.apple.quarantine /Applications/Kikimi.app
```

Do this only for a copy you trust, since it skips macOS's check.
</details>

## Build from source

Needs macOS 15 or later (Apple silicon recommended; translations need macOS 26), Xcode 27, Python 3, and network access. The dictionaries are
large generated files, so they aren't in the repository. Build them once:

```bash
Scripts/build_ipadic.sh         # Japanese tokenizer dictionary (~50 MB)
Scripts/build_dictionaries.sh   # JMdict, KANJIDIC2, Spanish, French and German (~2.5 GB download)
```

Then open `Kikimi.xcodeproj`, pick the **Kikimi** scheme and **My Mac**, and press ⌘R. On the Videos page, download
a speech model (about 1.5 GB for Spanish, French and German, 1.6 GB for Japanese), then drop in a video.

Tests: `cd LangCore && swift test`.

## More

- [`ARCHITECTURE.md`](ARCHITECTURE.md): where things live, the import pipeline, tests, adding a language.
- [`ROADMAP.md`](ROADMAP.md) and [`AGENTS.md`](AGENTS.md): what comes next, and how we work.
- [`Release/CHECKLIST.md`](Release/CHECKLIST.md): shipping. The bundle identifier is `com.surreptus.Kikimi`.
- [Privacy policy](Kikimi/Privacy.md) and [terms of use](Kikimi/Terms.md), shown in the app and on the website.

## Licences

The app's code is under the [MIT licence](LICENSE). Dictionary data comes from JMdict and KANJIDIC2 (EDRDG) and
English Wiktionary via kaikki.org, all CC BY-SA 4.0, and the built files stay under that licence, so they are built
from scripts rather than committed. Speech models are OpenAI Whisper converted by Argmax; Japanese tokenizing uses
[MeCab](https://taku910.github.io/mecab/) with IPADIC. [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists every
component, and the licence texts are in the app under Acknowledgements.

## Known limits

- Accuracy depends on the model and the audio. `medium` scored about 23% word error rate on a long synthesized
  Spanish passage and hasn't been benchmarked for French or German.
- Whisper's timestamps are coarse in fast, overlapping speech, so sentence clips there can start or end slightly off.
- French lemmas are noisier than German ones, and a German separable verb ("ruf ... an") is learned as `rufen`.
- IPADIC dates from 2007, so modern Japanese slang is sometimes split or missed.
- Audio-only files aren't supported. The UI has had limited hands-on testing.
