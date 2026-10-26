# Third-party notices

Kikimi is released under the [MIT licence](LICENSE). It uses the software, models and data below, each under its own
licence. The full texts are in [`LangCore/Sources/LangCore/Resources/Licenses/`](LangCore/Sources/LangCore/Resources/Licenses/),
are shown in the app under Help > Acknowledgements, and are on the website at `/acknowledgements/`.

| Component | What it is used for | Licence |
|---|---|---|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Argmax) | Runs speech recognition on the Mac | MIT |
| [swift-transformers](https://github.com/huggingface/swift-transformers) (Hugging Face), inside WhisperKit | Tokenizer code used by WhisperKit | Apache 2.0 |
| [OpenAI Whisper](https://github.com/openai/whisper) models, converted for Core ML by Argmax | The speech models you download | MIT |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | The app's database | MIT |
| [MeCab](https://taku910.github.io/mecab/) (vendored) | Splits Japanese into words | BSD (one of its licence options) |
| IPADIC (NAIST, ICOT) | Japanese word and reading data for MeCab | IPADIC licence (permissive, notice must be kept) |
| [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html) (EDRDG) | Japanese dictionary data, adapted into the app's dictionary | CC BY-SA 4.0 |
| English Wiktionary via [kaikki.org](https://kaikki.org) (wiktextract) | Spanish dictionary data, adapted into the app's dictionary | CC BY-SA 4.0 and GFDL |

The dictionary files in the app are adaptations of JMdict and Wiktionary and are shared under the same licence
(CC BY-SA 4.0). The scripts that build them are in `Scripts/dictionaries/`, so they can be rebuilt from the original data.

The website (`site/`) is built with [Astro](https://astro.build) (MIT). The built pages do not include Astro's code.

Names such as Apple, macOS, Anki, OpenAI, Whisper, Hugging Face and WaniKani belong to their owners. Kikimi is not
affiliated with or endorsed by them, and its review stages use no name from WaniKani.

When a package is added or updated, check `Package.resolved` against this file and the Acknowledgements.
