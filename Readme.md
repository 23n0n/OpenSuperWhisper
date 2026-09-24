# OpenSuperWhisper

OpenSuperWhisper is a macOS application that provides real-time audio transcription using the Whisper model. It offers a seamless way to record and transcribe audio with customizable settings and keyboard shortcuts.

> **This tree is a fork of [Starmel/OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) (MIT).**
> Everything the original does is still here; on top of it this fork adds local translation and tone, language-aware
> gating, a dictation clean-up pass, keystroke delivery that never touches the clipboard, and a repaired long-form
> decode path. Section [What this fork changes](#what-this-fork-changes) describes every difference in detail, and
> [What is unchanged](#what-is-unchanged) lists what is inherited verbatim.
>
> **The `brew install` line and the release links below install the *original* app, not this build.** This fork
> publishes no downloads: it is built from source ([Building locally](#building-locally)), and its work lives at
> `main` in this fork's own repository ([23n0n/OpenSuperWhisper](https://github.com/23n0n/OpenSuperWhisper)) —
> nothing has been sent upstream, and no pull request is open against it.

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

### Added by this fork

- 🌐 **Local translation and tone** — an instruction-tuned model runs inside the app (llama.cpp linked in, no
  server, no port); two independent switches plus a target-language picker, off by default
- 🧭 **Language-aware gating** — speech already in the target language is never sent to the model; English is
  never translated while the target is English; an unknown language passes through raw
- 🛡️ **English-only model guard** — an English-only model with a non-English language is refused with a notice
  instead of silently hallucinating
- 🧹 **Dictation clean-up** — filler words, `hmm`, `aaa` and stutters are scrubbed, the sentence language repaired,
  through the same single transform call
- 📚 **Reference / glossary field** — names and terms fed into the transform prompt
- ⌨️ **Keystroke delivery** — the transcript is typed into the focused app; the clipboard is never written to
- 🔒 **Accessibility only** — Input Monitoring is no longer used or required anywhere, and no permission screen
  blocks the app
- 📊 **Last-dictation card** — the detected language and the raw, cleaned and final text of the last dictation
- 🗂️ **Model storage controls** — installed models listed with the one in use, SHA-256 verification against the
  digest each publisher reports, removal with the space it frees
- 🧯 **Long-form audio fix** — dictation longer than 30 s no longer skips audio
- 🧾 **Readable settings, reachable settings** — the Settings sheet lays out correctly, and the status-bar menu
  reaches it even with the main window closed
- 📦 **One-package install, one-operation uninstall** — from inside the app
- 🛠️ **Developer tooling** — identity-signed builds whose permission grants survive rebuilds, one build script for
  the vendored engines, contract checks for the transform endpoint and the installer

## What this fork changes

Written against the delivery branch `feat/local-translate-tone`, merge tip `319f3a3` (2026-09-24; this section
is its own commit). Every claim below was
checked against that tree, and the numbers were produced by running the code, not by reading it. To see the whole
delta yourself:

```shell
git fetch upstream        # upstream = https://github.com/Starmel/OpenSuperWhisper.git, already a remote here
git diff upstream/develop...feat/local-translate-tone
```

**Scale.** 54 commits of its own on top of `upstream/develop` (69 including merges), touching 78 files:
**+12,995 / −715** lines. 42 files are new, 35 are upstream files with changes, and one file moved
(`ggml-tiny.en.bin` into the app bundle directory). Those 42 new files — app sources, tests, build scripts,
packaging and the vendored `libllama/` — are the fork's own; everything else in the tree — the two engines, the
shortcuts, the queue, the model catalogue, the onboarding — is upstream's, edited where a feature required it.

Paths below are relative to `OpenSuperWhisper/` unless they start with `Scripts/`, `packaging/` or `libllama/`.

### 1. Translation and tone, inside the app

Upstream transcribes; it does not translate, and it has no notion of tone. This fork adds both, driven by two
independent switches in **Settings → Transcription** ("Translate into …" and "Apply tone"), each carrying a
**Target language** picker (English by default, Polish as the reverse direction). Both default to off.

The transform is performed by `Qwen2.5-1.5B-Instruct-Q4_K_M` (~986 MB), which the app downloads into its own
Application Support folder and verifies against the published checksum. It runs **in-process**: llama.cpp is
vendored as `libllama/` and linked into the app exactly like whisper.cpp, so there is no background server and no
listening port. The runtime lives in `OpenSuperWhisper/Llama/{Llama,TransformRuntime}.swift`, the model's
lifecycle and verification in `TransformModelManager.swift`, and the prompt/request layer in
`TranslationService.swift`. A user who prefers their own backend can set an OpenAI-compatible endpoint in
**Settings → Advanced**; `Scripts/transform-server.sh` can serve one and `Scripts/verify-transform.sh` checks any
endpoint against the app's request/response contract.

### 2. Language awareness: what gets translated, and when

The decision is a table (`TransformPolicy` in `TranslationService.swift`), not a per-call guess, and it is fed by
the language the speech engine reports *for that same utterance* — whisper's own detection under **Auto-detect**
with a multilingual model, a fixed language setting when set, or the text heuristic in
`Utils/LanguageDetector.swift` (Polish diacritics, function words, bigrams) for engines that cannot report one,
such as Parakeet. The rules that matter:

- Speech already in the **target** language is pasted unchanged — **no model call at all**, even with tone on.
- With the default target (English), **English dictation is never translated**, so the original's behaviour is
  preserved for English users and the transform only ever engages on foreign speech.
- Tone rides on a translation: it describes the output of a direction change, so it does nothing without one.
- When the language cannot be determined, the raw transcript is pasted and nothing is sent to a model.

The full switch table is in [Translation and tone](#translation-and-tone-towards-a-target-language) below.

### 3. English-only model guard

A `.en` whisper model cannot detect a language; pairing one with a Polish utterance made whisper *translate into
English* and hallucinate before the transform ever ran. `Utils/SpeechModelLanguageGate.swift` now refuses that
combination with an inline notice (and a remedy button) instead of producing confident nonsense.

### 4. Dictation clean-up and the reference field

Two more controls in **Settings → Transcription**. **Clean up dictation** removes filler sounds, drawn-out
vowel runs, stutters and false starts, and repairs the sentence language (Polish affixes, casing, diacritics) —
deterministically in `Utils/DictationScrubber.swift`, and where grammar is at stake through the *same* single
transform call the translation already uses: measured on the captain's own recordings with the bundled model,
clean-up **adds no model call** where a translation or tone rewrite is already happening (the clean-up wording
travels inside that prompt), and it adds exactly **one** call — median 0.17–0.38 s — where the app previously made
none, which is target-language speech with clean-up on. The deterministic scrub itself costs ~0.13 ms. **Reference** takes free text — names, product
terms, jargon — and passes it into that prompt so the model stops mangling them.

The last dictation is inspectable in the app: `DictationReport.swift` records the detected language plus the raw,
cleaned and final text, and the main window shows them side by side. History always keeps the raw transcript.

### 5. Delivery by synthetic keystrokes — the clipboard is never used

Upstream types the transcript by putting it on the system pasteboard and sending ⌘V
(`ClipboardUtil.insertText` / `sendCmdV`), which overwrites whatever the user had copied. This fork delivers by
synthesising the keystrokes instead (`Utils/KeyboardSimulator.swift`; it is the only delivery path —
`Indicator/IndicatorWindow.swift:65-66`, and no `ClipboardUtil` paste call site remains in the app). The clipboard
is not read or written by the delivery path at all, and the layout-dependent keycode translation is covered by
`KeyboardSimulatorTests`. Keystrokes that the system refuses to
deliver are reported instead of being dropped silently. This also means Accessibility — not Input Monitoring — is
the grant that matters; see the next point.

### 6. Permissions: Accessibility only, and nothing blocks on it

Upstream's modifier monitor installs a `.listenOnly` event tap (`ModifierKeyMonitor.swift:142` in upstream's
tree), which is what made macOS demand **Input Monitoring**. This fork's tree contains no `IOHID` reference and no
listen-only tap: the event-related grant is Accessibility alone, and recording and typing work without a
permission screen. The app never
gates on permissions: missing ones surface as inline notices with a button that opens the right System Settings
pane, onboarding can be skipped, and **Settings → Shortcuts → Permissions** shows the state of both grants at any
time. A build left in Xcode's split debug-dylib layout — the state that makes a recorded grant stop matching — is
now detected and refused rather than launched.

### 7. Long-form dictation no longer loses audio

The most consequential bug fixed here, because it silently destroyed text in the path the app is used for. The
decoder was configured with `noTimestamps = !showTimestamps`, which is `true` by default, and without timestamps
whisper.cpp advanced its seek a full 30 s per window — discarding whatever it had not transcribed. A dictation
longer than a window therefore arrived with holes. The fork keeps the decoder's timestamps unconditionally
(`params.noTimestamps = false`, `Engines/WhisperEngine.swift:415`, with the rationale in place), so the seek
follows the audio the decoder actually covered.

Measured on the delivery tip against `large-v3-turbo`, in `LongFormTranscriptionTests`: **unique-word recall
0.9932 English** and **0.9873 Russian**, tail recall **1.0** in both languages, **0 replayed four-word runs**.
The transcripts are captured verbatim next to the measurement, and four independent derivations of the numbers
agree to the last printed digit.

### 8. Settings, models and diagnostics made visible

Several of these are the difference between a feature existing and a feature being *findable*:

- **Settings is reachable from the status-bar menu**, so it works with the main window closed — previously the
  only entries were inside a window that could be closed, and features appeared not to exist.
- **The Settings sheet lays out correctly.** macOS lays a `TabView`'s strip out 0×0 inside a sheet, which made
  the tabs unclickable; the strip is a segmented picker now, and a snapshot test asserts the sheet is not clipped.
- **Model management.** Every whisper model file on disk — downloaded or placed by hand — is listed with the one
  in use, can be verified against the publisher's published SHA-256 (the bundled model included) or removed with
  the space it frees reported, and a missing selection is reported instead of silently switching models.
- **Debug Mode** is wired through to whisper.cpp's verbose decode trace, and **Show the welcome screen again**
  re-runs the first-run flow without disturbing the existing choices.
- **The indicator is honest.** With no microphone it says so, instead of showing "Processing…" forever, and a
  dictation whose transcript was lost says why.

### 9. Packaging and uninstall

Upstream ships a package built from its own release process and has no uninstaller. This fork adds
`packaging/{build-pkg.sh,distribution.xml,scripts/preinstall,uninstall.sh}` plus `UninstallService.swift`: one
package installs the app with everything it needs inside it, and one operation — **Settings → Advanced → Uninstall
OpenSuperWhisper…**, the same item in the menu-bar menu, or `/Applications/Uninstall OpenSuperWhisper.command` if
the app is already gone — removes the app, the dictation history, the downloaded models and the installer receipt,
leaving other applications' data alone. Running it twice is harmless, and `Scripts/verify-packaging.sh` checks the
path list, the idempotence and a built package's payload rather than trusting them.

### 10. Developer tooling

Local Debug builds are signed with a stable self-signed identity (`Scripts/dev-signing-identity.sh`,
`dev-sign.sh`) so the Accessibility grant survives rebuilds, and `Scripts/dev-run.sh` is the single entry point
that builds with the debug dylib disabled, signs, and can run the unit suite *and re-sign afterwards* — a bare
`xcodebuild test` leaves an ad-hoc signed bundle and is exactly the failure the script exists to prevent.
`Scripts/build-native.sh` builds the two vendored engines in the one order that works (llama.cpp installs the
single ggml package that whisper.cpp then links against). Crew worktrees build under a different bundle id, and
each test process gets its own preference store, so parallel development cannot poison the app someone is using.
The suite on the merged tip is **420 tests: 367 passing, 0 failing, 53 skipped**, where the skips are all
environmental: 50 gated on this machine's input sources or on Accessibility automation, 2 behind
`OSW_TEST_TURBO_MODEL` and 1 behind a microphone opt-in. That 50 is why the daily delivery path is the least
covered part of the suite.

### What is unchanged

Inherited from upstream, unmodified in behaviour: the whisper.cpp and Parakeet (FluidAudio) transcription
engines and their model downloads, key-combination and single-modifier triggers, the mouse-button trigger,
hold-to-record, drag & drop with the transcription queue, microphone selection (including iPhone/Continuity),
auto language detection, Asian-language autocorrect, the Hebrew (ivrit.ai) model entry, onboarding, and the MIT
licence. Upstream's own README sections — Installation, Requirements, Support, Building locally, Contributing,
Whisper Models — are kept as they are, apart from the notes this fork needed.

### Known limits and what is not built yet

- **Polish *output* from the bundled 1.5B model is best-effort.** It was measured on English→Polish dictation and
  it drops content, invents details and is unstable between identical runs. English output is the reliable
  direction; see the honest note in [Translation and tone](#translation-and-tone-towards-a-target-language).
- **A larger model for Polish output is decided but not implemented.** `Qwen3-8B-Q4_K_M` is the chosen backend
  for that direction (it was measured at 11/15 clean, never inventing) and is not wired into the app yet.
- **In-process transform determinism is an open question.** The sampling chain is fully seed-pinned already
  (`Llama.swift:270-278`, `dist(seed = 0)`, a fresh chain per request), so identical inputs *should* give
  identical outputs; observed differences on this machine point at backend reduction nondeterminism rather than
  seeding. Unresolved, and not a claim this fork makes.
- **The delivery path is the least covered by tests** (see the skip breakdown above), which is the next test work
  queued.
- This fork has **no releases**: it is built from source, and its permission grants are tied to a locally created
  signing identity. The code itself is at `main` in this fork's own repository; upstream has received nothing.

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

The same two grants are visible inside the app — **Settings → Shortcuts →
Permissions** — with their current state and a button that opens the pane which
restores a missing one. With the Whisper engine, **Settings → Model** lists every
model file that is on disk, downloaded or put there by hand, marks the one in use,
and each row can be verified against the sha256 its publisher reports or removed
outright, reporting the space that frees; the Parakeet rows report whether every
file the engine needs is present, which is all FluidAudio publishes. **Settings →
Advanced** carries the **Debug Mode** switch
that makes whisper.cpp print its verbose decode trace, and **Show the welcome
screen again**, which re-runs the first-run flow (dictation language, shortcut,
speech model) without changing any of the three until you choose.

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
requirement is what is actually on disk. xcodebuild flags are forwarded, so a single
class still goes through that path:

```shell
Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/TransformBackendTests
```

It also offers the language-report cases a multilingual model when this machine happens
to have one (`OSW_TEST_MULTILINGUAL_MODEL`); with none, they skip, exactly as in CI.
Tests read and write a scratch preference store of their own rather than the app's
domain, so a suite cannot change — or be changed by — the app someone is running or
another suite running in parallel.

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

## Translation and tone (towards a target language)

Two independent switches in Settings drive the transform, and both are off by default: **Translate
into …** and **Apply tone**. The switch carries a **Target language** picker (English by default,
Polish for the demanded reverse direction). When either switch is on, the app runs a small
instruction-tuned model **inside itself** — llama.cpp is linked into the app exactly like whisper.cpp,
no server, no port, no cloud service. Turn on a switch and press **Download model** next to it in
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
cannot report one, such as Parakeet. When it cannot tell, the raw transcript is pasted. The action is
then decided against the **target language**; with the default target (English) the table reads:

| Translation | Tone | Spoken language | Pasted text |
|---|---|---|---|
| off | off | any | raw transcript, nothing is even detected |
| on | off | Polish (English target) | translated English, with no tone sentence in the prompt |
| on | off | English (English target) | raw transcript — speech already in the target is never translated |
| off | on | any | raw transcript — a tone rides on a translation, and none is asked for |
| on | on | Polish (English target) | translated into English and toned |
| on | on | English (English target) | raw transcript — nothing to translate, so nothing to tone |
| any | any | unknown | raw transcript |

With **Polish** as the target the two directions swap: spoken **English** is translated into Polish
(tone riding along when the tone switch is on), and spoken **Polish** is pasted unchanged — it is
already in the target, so no model call is made at all.

Speech already in the target language is never sent to the model, tone switch or not. The tone belongs
to a translation: it describes the output of a direction change, so it needs the translation switch on
to have anything to rewrite.

**Honest note on Polish output.** The bundled 1.5B model was measured on English→Polish dictation
before this control was wired (task `fm-20260923-13`, full outputs in its report). It writes Polish,
and short simple sentences come back clean, but on realistic longer dictation it drops content,
invents details, inverts polarity and occasionally leaves English tokens or a whole wrong language in
the output, and it is unstable between identical runs. Treat Polish output as best-effort; English
output is the reliable direction.

Dictation history always keeps the raw transcript, and recordings transcribed from the list (queued or
re-run files) are never transformed. To get language awareness on the dictation hotkey, set the
language picker to **Auto-detect** with a multilingual model (e.g. Turbo V3); a fixed setting is
trusted as-is. An English-only model in Auto-detect (e.g. `ggml-tiny.en.bin`) will turn Polish speech
into English hallucination before the transform ever runs — use a multilingual model.

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
