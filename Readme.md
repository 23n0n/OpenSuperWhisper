# OpenSuperWhisper

OpenSuperWhisper is a macOS application that provides real-time audio transcription using the Whisper model. It offers a seamless way to record and transcribe audio with customizable settings and keyboard shortcuts.

> **This tree is a fork of [Starmel/OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) (MIT).**
> Everything the original does is still here; on top of it this fork adds local tone and clean-up rewrites that
> **never change the language of what you dictated** (Polish stays Polish, English stays English), a dictation
> clean-up pass, keystroke delivery that never touches the clipboard, and a repaired long-form decode path. Section [What this fork changes](#what-this-fork-changes) describes every difference in detail, and
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

- 🌐 **Local tone and clean-up, in the language you spoke** — an instruction-tuned model runs inside the app
  (llama.cpp linked in, no server, no port); two independent switches, off by default. The transcript is rewritten
  in place: **the app never changes the language of your dictation**
- 🇵🇱 **Polish prefers Qwen3-8B when it is installed** — the shipped 1.5B does the work when it is not, and the
  app says which model each language uses. Nothing is refused, nothing is substituted silently
- 🧭 **Auto-detected language, always** — the engine measures the language of every utterance (no language
  picker); a transcript nothing can place is pasted raw, untouched
- 🛡️ **English-only model guard** — an `.en` model cannot detect anything, so when the transcript it produced is
  not English the app says so and offers the multilingual model instead of keeping the invented text
- 🧹 **Dictation clean-up** — filler words, `hmm`, `aaa` and stutters are scrubbed, punctuation, articles and word
  order repaired, all in the language that was spoken, through the same single transform call
- 📚 **Reference / glossary field** — names and terms fed into the transform prompt
- ⌨️ **Keystroke delivery** — the transcript is typed into the focused app; the clipboard is never written to
- 🔒 **Accessibility only** — Input Monitoring is no longer used or required anywhere, and no permission screen
  blocks the app
- 📊 **Last-dictation card** — the detected language and the raw, cleaned and final text of the last dictation
- 🗂️ **Model storage controls** — installed models listed with the one in use, SHA-256 verification against the
  digest each publisher reports, removal with the space it frees
- 🧯 **Long-form audio fix** — dictation longer than 30 s no longer skips audio
- ⏸️ **A long pause ends the sentence** — a switch (off by default, with the reason measured in §8) that keeps the
  pause the speaker left instead of dissolving it into a 0.1 s breath, so a pause cannot split a thought into a
  fragment or run two thoughts together — Polish in particular, where the model's punctuation is weaker than
  English's
- 🧾 **Readable settings, reachable settings** — the Settings sheet lays out correctly, and the status-bar menu
  reaches it even with the main window closed
- 📦 **One-package install, one-operation uninstall** — from inside the app
- 🛠️ **Developer tooling** — identity-signed builds whose permission grants survive rebuilds, one build script for
  the vendored engines, and a contract check for the installer

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

### 1. Tone and clean-up, inside the app — never a language change

Upstream transcribes; it has no notion of tone and no rewriting pass at all. This fork adds two independent
switches in **Settings → Transcription** ("Apply tone" and "Clean up dictation"), both riding one call to a model
that runs **inside the app**. The transcript is rewritten **in the language it was spoken in**: Polish stays
Polish, English stays English, and there is no direction change anywhere in the product.

The rewrite is performed **in-process** by one of two models, picked by the **language of the dictation**:
`Qwen2.5-1.5B-Instruct-Q4_K_M` (~986 MB on disk, ~1.1 GB of RAM while loaded) is the model every language can
run on, and `Qwen3-8B-Q4_K_M` (~5 GB on disk, ~5.3 GB while loaded) is what Polish **prefers when it is
installed** — the shipped model does Polish work when it is not, and the card says which one is in use. Each is
downloaded on demand into the app's own Application Support folder and verified against its pinned checksum
before it is used. llama.cpp is vendored as `libllama/` and linked into the app exactly like whisper.cpp, so
there is no background server, no listening port and no endpoint override: the transform
(`OpenSuperWhisper/TransformService.swift`) is the only way the text can be rewritten.

### 2. The language is auto-detected, and never changed

The decision is a table (`TransformPolicy` in `TransformService.swift`), not a per-call guess, and it is fed by the
language the speech engine reports *for that same utterance* — whisper's own detection, the only mode there is
now that the **Language picker is gone from Settings, onboarding and the menu bar** — or by the text heuristic in
`Utils/LanguageDetector.swift` (Polish diacritics, function words, bigrams) for engines that cannot report one,
such as Parakeet. `params.language` is always `nil` and `params.detectLanguage` stays `false`. The rules that
matter:

- The transcript is rewritten **in its own language**, always: there is no target language in the product, and no
  prompt that could move the text into another one.
- Both switches off is the default install: **no model call at all**, and the transcript is bit-for-bit what the
  engine produced.
- A transcript nothing could place (an engine that reports nothing, and a text too short for the heuristic) is
  pasted raw; no model is asked to guess its language.
- Tone no longer rides on anything: it is a same-language rewrite, so it needs no other switch to be on.

The full switch table is in [Tone and clean-up](#tone-and-clean-up-in-the-language-you-spoke) below.

### 3. English-only model guard, re-keyed to the transcript

An `.en` whisper model cannot detect a language at all, and with the language picker gone there is no setting left
to compare against — so the evidence is the text the model produced. `Utils/SpeechModelLanguageGate.swift` reads
the transcript with the same `LanguageDetector` heuristic the transform uses, and when an English-only model's
transcript is not English (the captain's own case: `ggml-tiny.en.bin` writing confident English over Polish
speech) the dictation is refused with a notice naming the model *and* what the dictation looks like, plus the
multilingual model already on the machine as a one-click remedy. English dictation can never be caught by it.

### 4. Dictation clean-up and the reference field

Two more controls in **Settings → Transcription**. **Clean up dictation** removes filler sounds, drawn-out
vowel runs, stutters and false starts, and repairs the sentence language (Polish affixes, casing, diacritics) —
deterministically in `Utils/DictationScrubber.swift`, and where grammar is at stake through the *same* single
transform call the tone already uses: measured on the captain's own recordings with the bundled model, clean-up
**adds no model call** where a tone rewrite is already happening (the clean-up wording travels inside that
prompt), and it adds exactly **one** call — median 0.17–0.38 s — where the app previously made none, which is a
dictation with clean-up on and the tone switch off. The deterministic scrub itself costs ~0.13 ms. **Reference** takes free text — names, product
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

### 8. A long pause ends the sentence

The pause was never ignored — it was **dissolved**. Decoding takes the silence-removed path
(`params.language = nil`, so `showTimestamps` decides only the `[t0->t1]` prefixes), and
`Engines/WhisperEngine.swift` rebuilt the speech-only audio by replacing **every** gap the VAD found with a fixed
**0.1 s of zeros** — the same 0.1 s upstream `whisper_full` uses when it stitches VAD segments
(`libwhisper/whisper.cpp/src/whisper.cpp:6730-6800`). A pause of any length therefore reached the decoder as a
breath, and `assembleSegmentTexts` joined the decoder's segments with `""`, so the VAD's own timing — the one
signal that survived — was discarded. The decoder then decided sentence boundaries from prosody alone, which is
enough in English and is not enough in Polish, where the model's punctuation is markedly weaker.

**The switch is named for what it does, not for what was asked.** One line in **Settings → Transcription →
Language Settings**: **Long Pauses End the Sentence** — "a pause of 0.6 s or longer keeps its silence and closes the
sentence, instead of dissolving into a breath that lets two thoughts merge". Off is byte-for-byte the behaviour
every earlier build had, and it ships **off by default** — not out of caution, but because the measurement below
says the switch-on state regresses the English control while this app sends no decoder prompt.

What it does, in the decoder's terms:

* `PauseBoundaryPolicy.restored` keeps `min(pause, 0.8 s)` of the recording's **own** silence at each gap, and
  zero-pads only up to upstream's 0.1 s minimum — so the silence the decoder hears is the silence the speaker
  left, never a synthetic block;
* the same pass returns the pauses it measured, with their span in the decoder's own centisecond clock, and a
  pause of **0.6 s or more** ends the sentence: the join gets a terminator where the decoder left the sentence
  open. A segment that already closed its sentence is untouched, so nothing is doubled; a segment that *starts*
  before the pause ends decoded straight through the pause, and no boundary is invented inside its text;
* the terminator is language-aware (`.` — `。` for Chinese, Japanese and Korean), timestamp mode is unchanged
  (one decoder segment per line), no word is ever altered, and no punctuation is added inside a sentence.

**What the measurement said, including the parts that argue against it.** Measured on his own two Polish
recordings and an English control, through this app's own decode path, with his settings and the decoder prompt
this app actually sends — **none**.

* The same arm decoded twice is identical on all three recordings, so a before/after difference is the switch and
  not sampling. The transcripts the app stored for those recordings are reproduced **byte for byte by the
  switch-off arm with the instruction-shaped prompt an earlier brief attributed to his preferences** as the
  decoder prompt — which is evidence that *that* string was reaching the decoder when he dictated them, not of
  anything the app ships: `initialPrompt` defaults to the empty string and his stored domain holds no value. (On
  `pl-2` the switch off with that string reads "Ben super whisper… Dałem drugi model"; with no prompt, "Będę super
  whisper… Dałem drugi model".)
* The pause being kept is what fixes the Polish: `pl-2` comes back "**Open Super Whisper**" and "**Dodałem** drugi
  model" where the switch off garbles the same two places ("Będę super whisper… Dałem drugi model" with no prompt,
  "Ben super whisper… Dałem drugi model" with the attributed string), and `pl-1`'s verb arrives as "spieprzył po
  całości" instead of "pieprzył po całości"; with no prompt the switch also turns `pl-1` from two comma-joined
  sentences back into three.
* **With no decoder prompt the English control regresses** — and not by two words, by inventing a fragment:
  "Basically, now it creates,. **based, no,** now it creates a sentences…" where the switch off is clean, **at
  every silence cap tried** (0.2 s, 0.4 s, 0.6 s, 0.8 s; 0.4 s and 0.6 s are worse still — "profound sense",
  lowercase drift). That is why the switch ships off.
* **A deliberate decoder prompt removes that regression and keeps the Polish win.** Four prompts were measured on
  the same recordings with the same sampling — none, the instruction-shaped string the brief attributed to him,
  and two candidates written as ordinary Polish dictation with full punctuation and no instruction — and each is
  reported as a **counted word-level delta** against the no-prompt arm, because a prompt that fixes punctuation by
  moving words is not a win. With the English counterpart of candidate 1 the control comes back clean ("Basically,
  now it creates a sentences…", nothing invented); on `pl-2` the instruction-shaped string is the only arm that
  recovers the words he said ("spój" → "swój", "forkę" → "fork", and it drops a spurious "I"); on `pl-1` every arm
  keeps the words identical and only punctuation moves, where the two candidates add the commas but trade away a
  sentence boundary. The app ships none of them: that is the captain's setting to choose, and this branch does not
  set it for him.
* **The threshold was 0.5 s and the measurement removed it.** On `pl-1` a pause the VAD measured at 0.52 s falls
  inside "…o to, że żeś | spieprzył po całości", and 0.5 s closed the sentence there — "że żeś. spieprzył" (the
  same wrong break appears at 0.4 s). On the app's own numbers every pause he talks across is 0.52 s or below and
  every boundary he punctuates is 0.74 s or above, so the threshold is **0.6 s**, and at 0.6 s that arm comes back
  unchanged.
* **The cap is measured too.** At 0.2 s the decoder loses `pl-1`'s sentence break (two comma-joined sentences
  where the switch off has a full stop and the stored text has three), 0.4 s and 0.6 s leave a stray ". ," at the
  join, and only 0.8 s keeps `pl-1` at three sentences while leaving the join clean — so the cap is 0.8 s.
* **A smaller cap does not save the English control**, which is worth knowing before anyone tries: the invented
  fragment is there at 0.2 s, 0.4 s, 0.6 s and 0.8 s alike. What perturbs it is keeping *any* real silence where
  upstream had a 0.1 s breath, not how long that silence is — the switch, or a prompt, is the answer to that, not
  another cap.

### 9. Settings, models and diagnostics made visible

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

### 10. Packaging and uninstall

Upstream ships a package built from its own release process and has no uninstaller. This fork adds
`packaging/{build-pkg.sh,distribution.xml,scripts/preinstall,uninstall.sh}` plus `UninstallService.swift`: one
package installs the app with everything it needs inside it, and one operation — **Settings → Advanced → Uninstall
OpenSuperWhisper…**, the same item in the menu-bar menu, or `/Applications/Uninstall OpenSuperWhisper.command` if
the app is already gone — removes the app, the dictation history, the downloaded models and the installer receipt,
leaving other applications' data alone. Running it twice is harmless, and `Scripts/verify-packaging.sh` checks the
path list, the idempotence and a built package's payload rather than trusting them.

### 11. Developer tooling

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
language detection (now always automatic — see §2), Asian-language autocorrect, the Hebrew (ivrit.ai) model
entry, onboarding, and the MIT licence. Upstream's own README sections — Installation, Requirements, Support, Building locally, Contributing,
Whisper Models — are kept as they are, apart from the notes this fork needed.

### Known limits and what is not built yet

- **Polish rewrite quality is a preference, not a guarantee.** `Qwen3-8B-Q4_K_M` is what Polish *prefers*, and
  it is not required: with only the shipped 1.5B installed, Polish work runs on it. The 8B/1.5B measurement that
  justified the preference was taken on the translation direction this task removed (`fm-20260923-24`: 8B 11/15
  clean and nothing invented, 1.5B 4/15 with 2 invented), so it is carried as a preference that is stated in the
  Settings card rather than as a claim about same-language rewriting — which this tree measures in
  `SameLanguageTransformIntegrationTests` but does not grade at scale.
- **The better 30B-A3B is not shipped.** It measured well and is fast per call, but it needs ~18 GB of RAM and
  ~44 s to load, which the 10-minute idle unload cannot hide on a 32 GB machine — and with the external-endpoint
  override gone there is no supported way to run it against the app.
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
plus llama.cpp for tone and clean-up) is linked into the app, its Metal
shaders are embedded in it, and neither needs Homebrew, a background server or a
listening port. Speech models (and, if you use the tone or clean-up switches, the
rewrite models: ~1 GB for the model every language can run on, plus an optional
~5 GB 8B that Polish prefers) are downloaded by the app into its own folder on
first use.

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
screen again**, which re-runs the first-run flow (shortcut and speech model)
without changing either until you choose.

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

## Tone and clean-up (in the language you spoke)

Two independent switches in **Settings → Transcription**, both off by default: **Apply tone** (with a
Formal / Casual / Neutral picker) and **Clean up dictation**. When either is on, the app runs an
instruction-tuned model **inside itself** — llama.cpp is linked into the app exactly like whisper.cpp, no
server, no port, no cloud service, and there is no endpoint override any more. Turn a switch on and press
**Download model** next to a model in Settings → Transcription: the app fetches those weights into its own
Application Support folder, verifies the pinned checksum, and keeps them there.

**The language of the transcript is never changed.** Polish comes back Polish, English comes back English.
The tone switch asks for a different register of the *same* text; the clean-up switch removes filler, repairs
punctuation, articles and word order, and drops stutters. Neither one is a translation, and no setting in the
app can make them one.

**Which model each language uses.** The model follows the language of the dictation, and it is a preference,
not a requirement:

| Language | Model (Apache-2.0) | Download | RAM while loaded |
|---|---|---|---|
| English — always | `Qwen2.5-1.5B-Instruct-Q4_K_M` | ~986 MB | ~1.1 GB |
| Polish — preferred when installed | `Qwen3-8B-Q4_K_M` | ~5.0 GB | ~5.3 GB |
| Polish — when the 8B is not installed | `Qwen2.5-1.5B-Instruct-Q4_K_M` | ~986 MB | ~1.1 GB |

Nothing has to be downloaded for Polish to work: with only the shipped 1.5B installed, Polish dictation is
rewritten by it, and the Settings card says exactly that ("Polish runs on … The 8B is not installed, so the
shipped model does the work — nothing is refused…"). The 8B is what Polish *prefers* when it is there, and
its larger size is why it is not required. Only one model is ever resident: a language change unloads one
before loading the other, so the wired memory is the model in use, not the sum. Either is released after ten
minutes without a transform; because the 8B's cold load is seconds rather than milliseconds, the app warms
up the shipped model when recording starts, so the load happens while you are still speaking.

| Tone | Clean up | Spoken language | Pasted text |
|---|---|---|---|
| off | off | any | the raw transcript — nothing is detected, nothing is called |
| on | off | Polish | rewritten Polish, formal/casual/neutral, same language |
| on | off | English | rewritten English, same language |
| off | on | any placed language | the transcript repaired in the language it was spoken in |
| on | on | either | one call carrying both instructions |
| any | any | unplaceable text | the raw transcript — no prompt can name the language to keep |

Dictation history always keeps the raw transcript, and recordings transcribed from the list (queued or re-run
files) are never rewritten. The language of each utterance is detected automatically, which needs a
multilingual whisper model (e.g. Turbo V3): an English-only model such as `ggml-tiny.en.bin` cannot detect
anything, so when the transcript it produces does not read as English the app refuses that dictation, names
the model, and offers the multilingual model to switch to.

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
