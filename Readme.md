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

Download `OpenSuperWhisper-<version>.pkg` from the
[GitHub releases page](https://github.com/Starmel/OpenSuperWhisper/releases) and run it, or:

```shell
brew update # Optional
brew install opensuperwhisper
```

Everything the app needs is inside the package: the speech engine (whisper.cpp
plus llama.cpp for translation and tone) is linked into the app, its Metal
shaders are embedded in it, and neither needs Homebrew, a background server or a
listening port. Speech models (and the ~1 GB transform model, if you use
translation or tone) are downloaded by the app into its own folder on first use.

On first launch macOS asks for the two permissions the app needs:

| Permission | Why | Where it lives |
|---|---|---|
| **Microphone** | recording | Privacy & Security → Microphone |
| **Accessibility** | typing the transcript into the focused app | Privacy & Security → Accessibility |

Both grant the *app binary*. If you rebuild it locally with a different
signature, macOS treats it as a different app and the grant must be given again.

## Uninstalling

One operation removes the app, your dictation history, the downloaded models and
the installer receipt:

- **Settings → Advanced → Uninstall OpenSuperWhisper…**, or the same item in the menu-bar menu; or
- `/Applications/Uninstall OpenSuperWhisper.command`, if the app is already gone.

It leaves `~/models`, `/opt/homebrew` and every other application's data alone,
and running it twice is harmless.

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
    brew install cmake rust ruby
    gem install xcpretty
    ./run.sh build

The vendored engines are built by `Scripts/build-native.sh`: llama.cpp is
configured first and installs its ggml package, then whisper.cpp is configured
against that same ggml (`WHISPER_USE_SYSTEM_GGML=ON`). There is exactly one ggml
in the app image — linking a second copy fails with duplicate symbols.

In case of problems, consult `.github/workflows/build.yml` which is our CI workflow
where the app gets built automatically on GitHub's CI.

### Keeping permission grants across rebuilds

A Debug build from `run.sh` carries no identity — it is at best linker-signed with an
ad-hoc signature, and Xcode writes the target's code into `OpenSuperWhisper.debug.dylib`
behind a stub binary (`ENABLE_DEBUG_DYLIB` defaults to `YES` in Debug). An ad-hoc
signature's designated requirement is a hash of the exact binary
(`# designated => cdhash H"…"`), and macOS stores Accessibility, Microphone and
Automation grants against that requirement. Every rebuild therefore produces a binary
that no longer matches the grant: System Settings still shows Accessibility as granted
while the app is refused. tccd logs exactly that, seconds after the grant was recorded:

```
tccd: Update Access Record: kTCCServiceAccessibility for ru.starmel.OpenSuperWhisper to Allowed (System Set)
tccd: -[TCCDAccessIdentity matchesCodeRequirement:]: SecStaticCodeCheckValidity() static code
      (0x7b9f1bc300) from ru.starmel.OpenSuperWhisper : identifier
      "ru.starmel.OpenSuperWhisper" and certificate leaf = H"32266bcc…"; status: -67050
```

`-67050` is `errSecCSReqFailed`: the copy that is running does not satisfy the
requirement the grant was stored with. The same trap has a second half — because the
real code lives in the debug dylib, the binary TCC attributes is the ~40 KB stub, not
the app. `Scripts/dev-run.sh` (and therefore `./run.sh`) removes a product left in that
split layout before building it and refuses to launch one that survives.

The recorded grant can be tested against any build without launching it, with the same
check tccd performs:

```shell
codesign --verify -R '=identifier "ru.starmel.OpenSuperWhisper" and certificate leaf = H"32266bcc…"' <app>
```

Sign local builds with a real (self-signed) identity instead. It is created without
sudo, without an Apple account, and lives in its own keychain. `./run.sh` is now a thin
alias for `Scripts/dev-run.sh`, so the command above already takes this path:

```shell
Scripts/dev-signing-identity.sh   # once per machine: creates "OpenSuperWhisper Local Dev"
Scripts/dev-run.sh                # build (debug dylib off), sign, run
Scripts/dev-run.sh build          # build and sign only
Scripts/dev-run.sh test           # build, run the unit suite, then sign again
```

Run the suite through `Scripts/dev-run.sh test` rather than a bare `xcodebuild test`.
The test action rebuilds the app target with signing off, so it leaves the copy on
disk linker-signed ("`# designated => cdhash H"…"`"), and the next launch of that copy
has the same "grant does not stick" problem described above. The script signs the
bundle again after the suite — whether it passed or not — and asserts the identity
requirement is what is actually on disk. It also offers the language-report cases a
multilingual model when this machine happens to have one (`OSW_TEST_MULTILINGUAL_MODEL`);
with none, they skip, exactly as in CI.

Any other copy can be signed the same way, by pointing the signing script at it:

```shell
Scripts/dev-sign.sh build/Build/Products/Debug/OpenSuperWhisper.app
```

Every signed bundle then reports the same requirement, whatever changed in the code:

```
designated => identifier "ru.starmel.OpenSuperWhisper" and certificate leaf = H"…"
```

Because that requirement is derived from the signing identity, not from the binary, the
grant is made once per identity and survives rebuilds. If a valid `Developer ID
Application` identity exists in your keychains, both scripts prefer it and never create
the self-signed one. Remove the self-signed identity in one line:

```shell
Scripts/dev-signing-identity.sh --remove
```

Granting is the one step no script can do for you: the app has to be running and asking
for it, and you have to turn the switch on in System Settings → Privacy & Security →
Accessibility. The app never blocks on this — it shows an inline "Keystrokes are off —
grant Accessibility" notice with a button that opens that pane, and the notice clears
itself as soon as the switch is on. When you move from an ad-hoc-signed build to an
identity-signed one, the recorded grant matches the old requirement, so drop it once and
grant again:

```shell
tccutil reset Accessibility ru.starmel.OpenSuperWhisper
Scripts/dev-run.sh
```

From then on ordinary rebuilds keep the grant; `Scripts/dev-run.sh --reset-tcc` does that
reset for you if you ever need it again.

## Translation and tone (Polish → English + tone)

Two independent switches in Settings drive the transform, and both are off by default: **Translate
Polish to English** and **Apply tone**. When either is on, the app runs a small instruction-tuned
model **inside itself** — llama.cpp is linked into the app exactly like whisper.cpp, no server, no
port, no cloud service. Turn on a switch and press **Download model** next to it in
Settings → Transcription: the app fetches `Qwen2.5-1.5B-Instruct-Q4_K_M` (~986 MB, Apache-2.0) into
its own Application Support folder, verifies the published checksum and keeps it there. Until it is
downloaded, dictation is pasted unchanged.

**Advanced override:** if you would rather run your own endpoint, Settings → Advanced turns on
*Use an external endpoint* and takes an OpenAI-compatible URL, model id and timeout. The weights it
needs are not required then, and `Scripts/transform-server.sh` can fetch and serve them as before
(`Scripts/transform-server.sh --fetch`); that script is an optional external backend, not a
requirement.

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
| on | on | English or any other | rewritten in the selected tone (nothing is translated) |
| any | any | unknown | raw transcript |

The translation switch never vetoes a tone rewrite: for English it has nothing to do. Turn tone off to
keep your English untouched.

Dictation history always keeps the raw transcript, and recordings transcribed from the list (queued or
re-run files) are never transformed. To get language awareness on the dictation hotkey, set the
language picker to **Auto-detect** with a multilingual model (e.g. Turbo V3); a fixed setting is
trusted as-is.

To check that an external endpoint still matches the app's request/response contract (and that
translation, tone control and latency behave), start one and run:

```shell
Scripts/transform-server.sh &            # or any OpenAI-compatible endpoint
Scripts/verify-transform.sh
```

The packaging contract — the uninstaller's path list, its idempotence and a built package's payload —
is checked with:

```shell
Scripts/verify-packaging.sh --app build/Build/Products/Release/OpenSuperWhisper.app
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
