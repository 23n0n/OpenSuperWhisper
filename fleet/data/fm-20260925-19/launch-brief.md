# Task fm-20260925-19 — OpenSuperWhisper — ship — mode=local-only

## Captain's requirement (verbatim)

> "I need the application to be idempotent. It needs to work after each install and uninstall. And the models should
> install and uninstall automatically with the package. This must work."

## The half you own, and the decision you are changing

Today a fresh install had **no models**: the app's engines could not transcribe or rewrite until someone restored
files by hand. The app's own comment states the current policy —
`TransformModelManager.swift:65`: *"Weights are NOT shipped in the app bundle (a 1–5 GB payload in every update …)"* —
which is why they live per-user and are downloaded on demand. The captain wants a fresh install to work **immediately**,
with the models coming and going with the package. That does not require shipping them in the app bundle (which would
bloat every update, exactly what the comment rejects); it requires the app to **use the copies the installer placed**.

# The interface contract (fix this first; two crews depend on it)

**Shipped models live at** `/Library/Application Support/ru.starmel.OpenSuperWhisper/Models/`, laid out exactly like
the per-user directory the app already uses:

```
/Library/Application Support/ru.starmel.OpenSuperWhisper/Models/whisper-models/ggml-large-v3-turbo.bin
/Library/Application Support/ru.starmel.OpenSuperWhisper/Models/transform-models/qwen2.5-1.5b-instruct-q4_k_m.gguf
```

**Resolution order in the app** (both managers): the user's explicit selection → the per-user
`~/Library/Application Support/<bundle id>/...` copy → the **shipped** `/Library/...` copy → (whisper only) the tiny
model already inside the bundle → otherwise "download required".

**Shipped copies are read-only to the app**: they can be selected and used, and they must be refused by any delete
path, because the installer owns them. The existing "the last model was removed, so the bundled one came back" message
must keep being true with the shipped directory in the chain.

**What ships in the package:** the speech model (`ggml-large-v3-turbo.bin`, 1.62 GB) and the 1.5B transform weights
(`qwen2.5-1.5b-instruct-q4_k_m.gguf`, 986 MB) — ~2.6 GB of payload. The 5 GB 8B stays a download, and the app must
say so rather than silently meaning something different on a fresh install.


## What to build

1. **Resolution in both managers**, in the order above, with the shipped directory consulted **before** declaring a
   model missing. `WhisperModelManager` already has the shape for this (`bundledModelURL`, the "the last model was
   removed, so the bundled one came back" fallback); extend it to the shipped directory rather than inventing a second
   mechanism. `TransformModelManager` needs the same for `hasModelFile`/`verifiedPath`/`fileURL`, so a fresh install's
   tone and clean-up work with **zero downloads**.
2. **Ship-read-only.** Every delete path must refuse a shipped model and say why; the UI must not offer a delete that
   cannot work. A shipped model that is selected stays selected across relaunch.
3. **The 8B stays a download** and the app must not imply otherwise: with only the shipped 1.5B, the tone path uses the
   1.5B (that is the documented floor) and Settings keeps saying which model tone runs on. No silent behaviour change.
4. **Tests that would have caught today's failure:** a fresh install (scratch per-user dir, models only in the shipped
   location) resolves a speech model and a transform model; deleting is refused for shipped ones; removing a downloaded
   model falls back through the chain; and a per-user copy still wins over the shipped one so a user's own file is never
   ignored.

## Constraints

- Do not edit `packaging/*`, `Scripts/verify-packaging.sh` or the docs: that is the sibling task (`fm-20260925-18`,
  branch `fm/package-idempotent`), which puts the files where this contract says they are.
- Nothing writes to the captain's stored preferences, and no code path deletes from `/Library` — the installer owns that
  directory; the app only reads it.
- Headless only: no app launch, no `osascript`, no `screencapture`, no bare `xcodebuild test`, no `pkill`/`killall`.
- Detach long runs; gate on a free machine (no `xcodebuild`/`llama-server`).

## Definition of done

The four tests above, plus the full suite green with real counts and an identity-signed bundle; `fleet/data/fm-20260925-19/report.md` quoting the resolution order as implemented with file:line and the test output; a UTC-stamped `status.log`; an honest note on what the app cannot verify itself (that a real installer put the files there — the first mate's step).
