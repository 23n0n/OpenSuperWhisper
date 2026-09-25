# Task fm-20260925-18 — OpenSuperWhisper — ship — mode=local-only

## Captain's requirement (verbatim)

> "I need the application to be idempotent. It needs to work after each install and uninstall. And the models should
> install and uninstall automatically with the package. This must work."

## Why it is a real defect, not a nicety — measured today

A "fresh uninstall" through `packaging/uninstall.sh` (installed as `/Applications/Uninstall OpenSuperWhisper.command`)
removed, in one step: the app, **the captain's stored preferences**, **his 87 recordings and their database**, and
**every downloaded model** (the 1.62 GB speech model and the transform weights). The Trash held nothing, so the
recordings are gone. A fresh install then had **no models at all** and no way to work until someone restored them by
hand — which is what happened, by hard link, minutes later. `packaging/uninstall.sh:140-142` is the cause: a single
`rm -rf "$SUPPORT_DIR"` for "dictation history, the database, whisper models, transform weights, caches, saved state
and preferences" — one path for six different kinds of thing, four of which the captain expects to survive.

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

1. **The package carries the models.** `packaging/build-pkg.sh` gains the model payload, installed to the path above
   with the receipt id it already uses, so `pkgutil --payload-files` lists them and the uninstaller can attribute them
   to the package. State the size and where it went in the output, and keep it working with no Developer ID (the
   existing script builds unsigned; that must not change).
2. **Uninstall becomes path-granular.** Remove the app, the shipped models and the *downloaded* models; **preserve the
   captain's recordings and preferences by default**, with an explicit `--remove-user-data` for a full wipe (and say in
   `--help` what each does). Uninstall must stay idempotent: twice, and after the app was deleted by hand.
3. **The contract harness proves the cycle, not the steps.** `Scripts/verify-packaging.sh` already exercises the
   uninstaller against a scratch `OSW_INSTALL_ROOT`. Extend it to an **install → assert models and app present →
   uninstall → assert models gone and recordings intact → install again → assert it is complete again** cycle, run
   against scratch roots so it needs no root and cannot touch the live machine. Also assert the two things that broke
   today: recordings survive a normal uninstall, and `--remove-user-data` is the only thing that takes them.
4. **Docs:** `docs/release_build.md` and `packaging/README.md` (if present) must say what the package now contains, what
   uninstall keeps and removes, and the size implication for updates.

## Constraints

- No `sudo`, no root, no touching the live `/Applications`, `/Library` or the captain's home in tests: everything goes
  through `OSW_INSTALL_ROOT` scratch trees, exactly as the harness already does. A real install is the first mate's
  step, not yours.
- Do not edit the app's Swift sources: `OpenSuperWhisper/WhisperModelManager.swift`, `TransformModelManager.swift` and
  `Settings.swift` belong to the sibling task (`fm-20260925-19`, branch `fm/model-resolution`), which implements the
  resolution order above. Your surface is `packaging/*`, `Scripts/verify-packaging.sh` and the docs.
- Headless only: no app launch, no `osascript`, no `screencapture`, no bare `xcodebuild test`, no `pkill`/`killall`.
- Detach long runs; gate on a free machine (no `xcodebuild`/`llama-server`).

## Definition of done

The pkg builds locally with the model payload, and `pkgutil --payload-files` shows the app, the uninstall command and
the shipped models; the extended harness passes and its output is quoted (each cycle step, not a summary); the
uninstaller preserves recordings in the scratch tree and removes them only with `--remove-user-data`; docs updated;
`fleet/data/fm-20260925-18/report.md` plus a UTC-stamped `status.log`; an honest list of what a real (root) install
still needs that you could not exercise.
