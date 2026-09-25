# fm-20260925-19 — the app's half of "it must work after each install"

Branch `fm/model-resolution`, worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo/worktrees/OpenSuperWhisper-fm-modelfind`.

## What the task became (direction changed twice while I worked)

1. **First brief**: the app must resolve models the installer placed at
   `/Library/Application Support/ru.starmel.OpenSuperWhisper/Models/…`, with a shipped tier ahead of the bundled model.
   I built and locally verified that tier (five test cases, digest-stamped package copies, delete refusals).
2. **Captain's direction, mid-flight**: *"the model download from Hugging Face is a good strategy to make the
   application package smaller. Do not go harder than you have to go, but do the work in honest way."* → the
   `/Library` tier is dropped. **I deleted the whole tier**: `OpenSuperWhisper/Utils/ShippedModels.swift` and
   `OpenSuperWhisperTests/ShippedModelTests.swift` are gone, and `Settings.swift`, `TransformModelManager.swift`,
   `Utils/AppPreferences.swift`, `Utils/SpeechModelLanguageGate.swift`, `Onboarding/OnboardingView.swift` and
   `Tests/TestFixtures.swift` were reverted to `HEAD` — no `/Library` path, no delete-refusal, no new search tier,
   no `ShippedModels` reference anywhere in the app.

What is left is the smallest thing that makes a fresh install work, inside the mechanism that already existed.

## The resolution order, as implemented

The app carries one speech model inside its own bundle (`ggml-tiny.en.bin`, 77.7 MB, in `Contents/Resources`) and
downloads everything else from the catalogue. What a dictation loads is:

1. **the user's explicit selection**, when its file is on disk —
   `TranscriptionService.resolvedWhisperModelPath()` (`OpenSuperWhisper/TranscriptionService.swift:160-167`), first
   branch; the same rule `WhisperEngine.init` already had (`Engines/WhisperEngine.swift:173`).
2. **otherwise the app's own model** — `WhisperModelManager.bundledModelPath`
   (`OpenSuperWhisper/WhisperModelManager.swift:198-202`): the copy in the app's directory
   (`~/Library/Application Support/<bundle id>/whisper-models/ggml-tiny.en.bin`, put there on first run by
   `copyDefaultModelIfNeeded`, `:164`), or, if that copy is not there yet, the file **inside the bundle** itself.
3. **`nil` only when the bundle does not carry its model** — a broken build, not a user-reachable state. Nothing
   else is consulted: a model nobody downloaded is not a model on disk.

Two callers use that order, and they are the two that decide whether dictation works:

- `TranscriptionService.EngineSelection.current` (`OpenSuperWhisper/TranscriptionService.swift:135-140`) — what the
  engine loader is handed. Before this change it read the preference alone, so with nothing selected the engine got
  `nil`, `makeEngine` threw `contextInitializationFailed` (`:189`), and `ContentView` showed **"Model could not be
  loaded"** (`ContentView.swift:752`).
- `WhisperModelManager.ensureDefaultModelPresent()` (`OpenSuperWhisper/WhisperModelManager.swift:205-232`), which
  `OpenSuperWhisperApp.init` calls once per launch (`OpenSuperWhisperApp.swift:58`). It already repaired a
  *selection that went missing*; it now also covers *nothing selected at all* — a fresh install — and points the
  preference at the bundled model. When there **was** a selection and its file is gone it still reports
  `.selectionWasMissing` (`:75-79`), unchanged, so the Model tab keeps saying the model changed under the user.

The transform weights are untouched: `TransformModelManager.verifiedPath` (`TransformModelManager.swift:239-250`)
still refuses any file whose sha256 does not match the pin, `TransformRuntime.load` still throws
`notInstalled` rather than running unverified weights (`Llama/TransformRuntime.swift:241`), and the 8B stays a
download with the 1.5B as the documented floor.

### Digests stay the source of truth (checked, not trusted)

The catalogue's pins are the digests of the files the app downloads:

```
$ cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/build-models && shasum -a 256 ggml-large-v3-turbo.bin qwen2.5-1.5b-instruct-q4_k_m.gguf
1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69  ggml-large-v3-turbo.bin
1adf0b11065d8ad2e8123ea110d1ec956dab4ab038eab665614adba04b6c3370  qwen2.5-1.5b-instruct-q4_k_m.gguf
```

`1fc70f77…` is `Settings.swift:949`; `1adf0b11…` is `TransformModelManager.swift:111` — equal, so the pins identify
exactly the payload (1624555275 and 986048768 bytes), and a same-size variant would still be refused. Nothing in
that check was loosened.

### The Polish trap, stated rather than hidden

A fresh install runs on `ggml-tiny.en.bin`, which is English-only. The app's own `SpeechModelLanguageGate` already
detects that a non-English transcript through an English-only model measures nothing
(`Utils/SpeechModelLanguageGate.swift:66-96`) and its message names the fix: *"Download a multilingual model in
Settings → Model."* New test `testAFreshInstallRefusesPolishThroughTheBundledEnglishOnlyModel` pins that refusal and
that sentence, so a fresh install cannot look as if it could hear Polish.

## Tests

`OpenSuperWhisperTests/FreshInstallModelTests.swift` (new, four cases). They run in a scratch models directory
(`WhisperModelManager.modelsDirectory` is the seam), so no test reads or writes the models of the app on this
machine, and none depends on any other application's storage:

| case | what it pins |
|---|---|
| `testAFreshInstallResolvesAModelAndLoadsIt` | empty directory, nothing downloaded: the launch hook selects the bundled model, `EngineSelection.current` hands it over, and the **production** `TranscriptionService(selection:)` comes up with `loadingError == nil` — the exact failure "Model could not be loaded". |
| `testTheBundledModelIsResolvableWithoutAnyPreference` | with no preference at all the resolution still returns the bundle's own file — and remembers that resolution is a read, not a write. |
| `testADownloadedModelStaysSelectedAcrossARestartAndStillLoads` | a model in the app's directory stays the model in use across two launches' worth of the startup hook, with no notice, and still loads. |
| `testAMissingSelectionFallsBackToTheBundledModelAndKeepsWorking` | the existing `.selectionWasMissing` notice fires, the fallback is the bundled model, and that model loads — the app keeps transcribing. |
| `testAFreshInstallRefusesPolishThroughTheBundledEnglishOnlyModel` | the English-only refusal and the remedy it names. |

The notice path is also already covered by
`ModelStorageTests.testAMissingSelectionIsReportedInsteadOfSwitchingModelsSilently`; the new case adds the link that
was missing (the fallback model actually loads).

### Run output

<!--RUN-OUTPUT-->

## What only a real installer can prove

The app half is proven headlessly: a fresh install resolves and loads, a downloaded model survives a restart, and a
Polish dictation through the bundled English-only model is refused with the fix named. What no test here can prove:

- **That a real first launch creates the copy in a real home.** Every case runs against a scratch models directory;
  the copy into `~/Library/Application Support/<bundle id>/whisper-models/` under the captain's own account is the
  first mate's step, with the app launched by a human.
- **That the downloads work from this machine.** The digests above match the payload, and
  `WhisperModelManager.verifyModel` / the Model tab's `Verify` are the check against the published digest — but
  reaching Hugging Face, and a 1.6 GB download finishing, is an install-time fact, not a test fact.
- **That nothing regressed for a user who already had a selection.** The migration keeps a stored path that exists
  and drops one that does not (`Utils/AppPreferences.swift:79-100`, unchanged, covered by
  `PreferencesMigrationTests`), but the only real such preference is the captain's.

## Environment notes

- The worktree had **empty submodules**, so `Scripts/dev-run.sh test` failed at `build-native.sh`. Fixed with
  `git -c protocol.file.allow=always submodule update --init --reference <main checkout>/<path> <path>` for the
  three submodules — local references, no re-download, and the main checkout's `git submodule status` was verified
  identical before and after (git 2.54 keeps the worktree's module git dirs separate).
- No `sudo`, no writes to `/Applications`, `/Library` or the captain's real home; no branch, merge, push or tag.
