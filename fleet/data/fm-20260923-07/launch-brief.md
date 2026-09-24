# Task fm-20260923-07 — OpenSuperWhisper — scout

## Captain's intent

Captain (verbatim): "The whole app needs to ship in one package. It cannot be a few different
applications connected by a goodwill. It needs to be idempotent. I need to be able to simply install
it and uninstall it with a single package."

Context that makes this urgent: the transform feature currently delivered needs an external
`llama-server` (Homebrew `llama.cpp`), a repo script, a running process on a port, and a 986 MB model
file in `~/models`. That is exactly the "goodwill" the captain rejects. The whisper engine, by
contrast, is already vendored (built as a static library through the existing CMake + Xcode flow) —
that is the standard the whole app now has to meet.

## Firstmate spec

Read-only investigation, **no repo changes, no branch**. Deliverable: a report that says exactly what
must change for one installable and uninstallable package, with a recommended architecture and the
evidence for it.

1. **Inventory what the app needs today beyond its own bundle.**
   - Inspect a built `OpenSuperWhisper.app` (build one in `/tmp` if needed: the worktree pattern is
     `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./run.sh build`; do not modify the
     primary checkout). List its `Contents/Frameworks`, `Contents/Helpers`, `Contents/Resources`, and
     every `@rpath`/`@loader_path` dependency (`otool -L`) of the main binary and of the two dylibs
     `run.sh` copies (`libomp.dylib`, `libautocorrect_swift.dylib`). State plainly which of those are
     embedded in the bundle and which are expected to sit beside it on disk — i.e. whether the app is
     self-contained today even before the transform feature.
   - List every path the app writes outside its bundle: `~/Library/Application Support/*`, preferences
     domains (`defaults domains`), caches, `~/Library/Saved Application State`, containers, launch
     agents. Evidence over recall: show the commands whose output you are reading.
   - Note this live evidence: the app's stored `selectedWhisperModelPath` currently points at
     `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo/ggml-tiny.en.bin`, a path inside a git checkout —
     a fragility the packaging design must absorb (models the app references must live in app-owned
     storage).
2. **Options for the transform runtime, evaluated.** Compare, and recommend one:
   - **A. Vendored in-process inference.** Build `llama.cpp` as a static library through the same
     CMake + Xcode integration the repo already uses for `libwhisper`/whisper.cpp, and call the C API
     in-process (`llama_model_load_from_file`, `llama_decode`). No server, no port, no external
     binary. Report: what the existing whisper integration actually does (read
     `libwhisper/CMakeLists.txt` or equivalent, the Xcode project wiring, how `libwhisper.a` and its
     Metal resource bundle end up in the app), what the equivalent for llama.cpp would take, GPU/Metal
     shader resources, build time, and the app-size impact.
   - **B. Bundled helper process.** Ship a `llama-server` binary inside `Contents/Helpers` and let the
     app start and stop it (no Homebrew, no manual step, still one package). Report the lifecycle
     work this needs: port selection, readiness, crash recovery, shutdown on quit, and what it costs
     versus A.
   - **C. Swift-native MLX.** `mlx-swift`/`mlx-swift-examples` in-process with an MLX 4-bit model.
     Report the dependency weight, model size, and whether it can be linked into this project at all.
   For the recommended option, state how the already-landed HTTP-based `TranslationService`
   (`OpenSuperWhisper/TranslationService.swift`, verified by `Scripts/verify-transform.sh` against
   `127.0.0.1:1919`) migrates, and whether the endpoint/model/timeout preferences should disappear
   from Settings or become advanced overrides.
3. **Model weights.** Two shipping models, with sizes and consequences:
   - bundled inside the app package (an installer around 1 GB+, no network ever), versus
     - downloaded by the app on first use into app-owned storage, using the mechanism the app already
       has for whisper models (find it: the models list/manager in the app and the manifest machinery;
       the live data dir shows `model-manifest.json`, `model-installs.json` and a `models/` tree —
       determine which of those this fork actually owns, and where a new transform model would
       belong).
   State what each choice means for "install with a single package" and for offline operation.
4. **Install and uninstall as one unit.** Report how releases are produced today (`run.sh`,
   `make_release.sh`, `.github/workflows/build.yml`), what artifacts they emit, and the signing /
   notarization / quarantine situation on a clean machine (what the user must do today to run it —
   evidence: entitlements, `codesign -dv`, any `xattr` instructions in the repo). Then specify the
   concrete recipe for the captain's requirement: one artifact to install (`.dmg` with drag-to-
   Applications, or `.pkg` with receipts), and one operation to uninstall that removes the app plus
   every path listed in item 1 — including whether an in-app "Uninstall/Remove all data" action, a
   `pkg`-style uninstall receipt, or a packaged uninstaller script is the right call.
5. **Idempotence.** Define what must hold: installing over an existing version (including one with a
   different model path or older preferences) must converge to the same state; running the uninstall
   twice must be harmless; and no leftover state may make a reinstall behave differently. Name the
   specific code or script change each guarantee needs.
6. **Recommendation.** One architecture, the smaller fallback if it proves impractical, the work
   breakdown (what a ship task would touch, in order), and the risks. Explicitly separate what you
   verified by running something from what you read.

## Delegation guard

You are a crew member. Do not spawn subagents. If you need more depth, say so in your final report.

## Definition of done (scout)

- `data/fm-20260923-07/report.md` — self-contained, with the out-of-bundle inventory, the runtime
  comparison, the weights decision, the install/uninstall recipe, the idempotence guarantees, and the
  recommended architecture with its risks.
- Nothing modified under `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo` or any worktree of it; probe
  builds go to `/tmp`.

Report through your final message: outcome, probes run, recommendation, honest failure.
