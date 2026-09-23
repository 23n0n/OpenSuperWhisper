# OpenSuperWhisper

OpenSuperWhisper is a macOS application that provides real-time audio transcription using the Whisper model. It offers a seamless way to record and transcribe audio with customizable settings and keyboard shortcuts.

<p align="center">
<img src="docs/image.png" width="400" /> <img src="docs/image_indicator.png" width="400" />
</p>

## Features

- 🎙️ Real-time audio recording and transcription
- 🧠 Two transcription engines: [Whisper](https://github.com/ggerganov/whisper.cpp) and [Parakeet](https://github.com/AntinomyCollective/FluidAudio) — download models directly from the app
- ⌨️ Global keyboard shortcuts — key combination or single modifier key (e.g. Left ⌘, Right ⌥, Fn)
- 🖱️ Mouse button trigger — bind the middle or an extra (thumb) mouse button to start/stop recording
- ✊ Hold-to-record mode — hold the shortcut, modifier key or mouse button to record, release to stop
- 📁 Drag & drop audio files for transcription with queue processing
- 🎤 Microphone selection — switch between built-in, external, Bluetooth and iPhone (Apple Continuity) mics from the menu bar
- 🌍 Support for multiple languages with auto-detection
- 🇯🇵🇨🇳🇰🇷 Asian language autocorrect ([autocorrect](https://github.com/huacnlee/autocorrect))

## Installation

```shell
brew update # Optional
brew install opensuperwhisper
```

Or from [GitHub releases page](https://github.com/Starmel/OpenSuperWhisper/releases).

## Requirements

- macOS (Apple Silicon/ARM64)

## Support

If you encounter any issues or have questions, please:
1. Check the existing issues in the repository
2. Create a new issue with detailed information about your problem
3. Include system information and logs when reporting bugs

## Building locally

To build locally, you'll need:

    git clone git@github.com:Starmel/OpenSuperWhisper.git
    cd OpenSuperWhisper
    git submodule update --init --recursive
    brew install cmake libomp rust ruby
    gem install xcpretty
    ./run.sh build

In case of problems, consult `.github/workflows/build.yml` which is our CI workflow
where the app gets built automatically on GitHub's CI.

## Local translation backend (Polish → English + tone)

Two independent switches in Settings drive the transform, and both are off by default: **Translate
Polish to English** and **Apply tone**. When either is on, the app sends the transcript to an
OpenAI-compatible endpoint on this machine; no cloud service is involved. Serve that endpoint with a
small instruction-tuned model:

```shell
brew install llama.cpp                  # provides llama-server
Scripts/transform-server.sh --fetch     # downloads ~986 MB of weights once, then serves
```

Later runs only need `Scripts/transform-server.sh`; the weights stay in `$HOME/models` (override with
`TRANSFORM_MODEL_DIR`). The script serves `http://127.0.0.1:1919/v1/chat/completions` reporting the
model `qwen2.5-1.5b-instruct-q4_k_m` — the endpoint and model the app's defaults point at.

The language of each utterance decides what happens to it. The app takes the language the speech
engine reports for that same transcription — whisper's own detection when the language setting is
**Auto-detect** and a multilingual model is loaded, or your fixed language setting exactly as chosen —
and falls back to a small text heuristic (Polish diacritics, function words, bigrams) for engines that
cannot report one, such as Parakeet. When it cannot tell, the raw transcript is pasted:

| Translation | Tone | Spoken language | Pasted text |
|---|---|---|---|
| off | off | any | raw transcript, nothing is even detected |
| on | off | Polish | translated English, with no tone sentence in the prompt |
| on | off | English or any other | raw transcript — English never reaches the Polish→English transform |
| off | on | English | rewritten in the selected tone |
| off | on | Polish | raw transcript — a tone-only rewrite translates Polish anyway |
| on | on | Polish | translated and toned |
| any | any | unknown | raw transcript |

Dictation history always keeps the raw transcript, and recordings transcribed from the list (queued or
re-run files) are never transformed. To get language awareness on the dictation hotkey, set the
language picker to **Auto-detect** with a multilingual model (e.g. Turbo V3); a fixed setting is
trusted as-is.

To check that the running backend still matches the app's request/response contract (and that
translation, tone control and latency behave), run:

```shell
Scripts/verify-transform.sh
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests or create issues for bugs and feature requests.

### Contribution TODO list

- [ ] Streaming transcription
- [ ] Custom dictionary / keyword boosting ([#19](https://github.com/Starmel/OpenSuperWhisper/issues/19))
- [ ] Intel macOS compatibility ([#15](https://github.com/Starmel/OpenSuperWhisper/issues/15))
- [ ] Agent mode ([#14](https://github.com/Starmel/OpenSuperWhisper/issues/14))
- [x] Background app ([#8](https://github.com/Starmel/OpenSuperWhisper/issues/8))
- [x] Support long-press single key audio recording ([#18](https://github.com/Starmel/OpenSuperWhisper/issues/18))

## License

OpenSuperWhisper is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Whisper Models

You can download Whisper model files (`.bin`) from the [Whisper.cpp Hugging Face repository](https://huggingface.co/ggerganov/whisper.cpp/tree/main). Place the downloaded `.bin` files in the app's models directory. On first launch, the app will attempt to copy a default model automatically, but you can add more models manually.

### Hebrew (ivrit.ai)

For Hebrew transcription, download the **"Turbo V3 Hebrew"** model from Settings → Model. It is [ivrit.ai](https://www.ivrit.ai/)'s Hebrew fine-tune of `whisper-large-v3-turbo` ([whisper-large-v3-turbo-ggml](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml)) — the same base model as the other "Turbo V3" entries, but tuned for Hebrew. Selecting it automatically sets the input language to Hebrew, which these models require to be set explicitly.
