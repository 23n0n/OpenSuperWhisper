# Scout report — "one package to install, one operation to uninstall" for OpenSuperWhisper

Task: `fm-20260923-07` (read-only scout). Deliverable: this file.
Repo: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo` @ `bd5ad0e` (`feat/local-translate-tone`).
**Nothing under any checkout was modified.** Every build and probe ran under `/tmp/fm07`. No branch, no commit, no subagent.

Captain's requirement (verbatim):
> "The whole app needs to ship in one package. It cannot be a few different applications connected by a goodwill. It needs to be idempotent. I need to be able to simply install it and uninstall it with a single package."

Evidence conventions used throughout:
* **[M]** measured — I ran the command and quote its real output;
* **[R]** read — file/line or script I read, not executed;
* **[I]** inference from measured facts, stated as such;
* **[NV]** not verified.

---

## 0. Verdict up front

1. **The app is already self-contained at runtime, but not at build time, and it has never bundled a usable model.** The Release `.app` (28 MB) carries its two third-party dylibs in `Contents/Frameworks` and statically links whisper.cpp/ggml/Metal; there is **no `Contents/Helpers`, no port, no external process** anywhere in the app today **[M]** — the transform feature is the *only* thing that introduced all four kinds of "goodwill" (Homebrew `llama.cpp`, a repo shell script, a listening socket on 1919, a 986 MB file in `~/models`).
2. **Vendoring llama.cpp next to whisper.cpp cannot be done as "just another static library": the two vendored `ggml` copies collide.** whisper.cpp v1.9.3 vendors **ggml 0.20.2**, current llama.cpp vendors **ggml 0.25.0**; linking both static archives into one image fails with **duplicate symbol** errors (936 shared global symbol names in `libggml-base`, 602 in `libggml-cpu`, 259 in `libggml-metal`) — measured by actually attempting the link.
3. **The clean architecture works and I proved it end-to-end in one process:** rebuild whisper.cpp against llama.cpp's *single* ggml (`WHISPER_USE_SYSTEM_GGML=ON`, an upstream-supported option) and link both engines statically. A probe binary built that way transcribed `jfk.wav` with whisper **and** loaded the real 986 MB Q4_K_M GGUF and decoded tokens on Metal in the same process, `APP_IMAGE_GGML_VERSION=0.25.0`, exit 0. That is the recommendation (**A″**). A second proven variant (**A′**: llama.cpp as small embedded dylibs, whisper untouched) is the in-process fallback; a bundled `llama-server` helper (**B**, 13.9 MB, system-frameworks-only, built and measured) is the fallback that keeps today's HTTP contract and the 132-check harness byte-identical.
4. **Model weights should be downloaded on first use into app-owned storage, not bundled** — that is exactly what the app already does for whisper models (`WhisperModelManager` + `SettingsDownloadableModels`, both in-repo **[M]**, 132/132 harness passing **[M]**). A 986 MB payload inside every update is the wrong trade for a menu-bar utility. *(Note: `model-manifest.json` / `model-installs.json` / `models/` in `~/Library/Application Support/superwhisper/` do **not** belong to this fork — that directory belongs to the commercial SuperWhisper 2.18.3, `com.superduper.superwhisper`, installed at `/Applications/superwhisper.app` **[M]**.)*
5. **One artifact + one uninstall is achievable today with stock macOS tooling** (`pkgbuild`/`productbuild`/`notarytool`/`stapler` all present **[M]**), but **this machine cannot sign or notarize anything right now**: `security find-identity -v` → **0 valid identities**, and there is no notarytool profile ("Slava" not in the keychain) **[M]**. Packaging can be built and tested here; the signed/notarized release cannot.
6. Side observation that a ship task should not ignore: `~/Library/Logs/DiagnosticReports/` holds **12 `OpenSuperWhisper-*.ips` crash reports from today** (14:10–14:16), all `EXC_CRASH / SIGABRT` **[M]**. Not diagnosed here (out of scope), but "install once, works" and "aborts on launch" are hard to separate for the user.

---

## 1. Out-of-bundle inventory of a built app

### 1.1 What I built, and how

I did **not** touch the checkout. I copied the pristine working tree to `/tmp` and built the *Release* configuration (what the package actually ships) there:

```console
$ rsync -a --exclude='.git' --exclude='build' --exclude='libautocorrect/target' \
      /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo/ /tmp/fm07/repo/     # 5 s, 975 MB  [M]
$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# exactly the make_release.sh/notarize_app.sh build steps, minus signing:
$ cmake -G Xcode -B libwhisper/build -S libwhisper
$ cargo build -p autocorrect-swift --release --target aarch64-apple-darwin --manifest-path=libautocorrect/Cargo.toml
$ install_name_tool -id @rpath/libautocorrect_swift.dylib build/libautocorrect_swift.dylib
$ cp -f /opt/homebrew/opt/libomp/lib/libomp.dylib build/libomp.dylib
$ install_name_tool -id @rpath/libomp.dylib build/libomp.dylib
$ xcodebuild -scheme OpenSuperWhisper -configuration Release -jobs 8 -derivedDataPath build \
    -destination 'platform=macOS,arch=arm64' -clonedSourcePackagesDirPath SourcePackages \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
    OTHER_CODE_SIGN_FLAGS="--entitlements OpenSuperWhisper/OpenSuperWhisper.entitlements" build
```

Result: `/tmp/fm07/repo/build/Build/Products/Release/OpenSuperWhisper.app` **[M]**. The whole run finished in one background job the harness timed at 157 s (*approximate, not phase-instrumented*); the equivalent phase measurements from the llama.cpp probe below (`cmake` configure 23 s, static libs 29 s on this M4 with `-jobs 8`) bound the C++ half of that **[M]**.

I also used the **already-built Debug app** in the primary checkout (`build/Build/Products/Debug/OpenSuperWhisper.app`, built by `./run.sh`, mtime 14:16) for the unstripped-symbol evidence — read-only **[M]**.

Environment **[M]**: macOS 27.0 (26A428), Xcode 27.0 (27A266a), cmake 4.4.3, rustc 1.98.1 (Homebrew, no rustup), Apple M4. Both `cmake`/`cargo` on `PATH`, `swifty-dmg` **not** installed (see §4).

### 1.2 Bundle contents and `otool -L`

Release app, measured:

```
$ du -sh OpenSuperWhisper.app                                        → 28M
OpenSuperWhisper.app/Contents/Frameworks/libomp.dylib                → 721,120 B
OpenSuperWhisper.app/Contents/Frameworks/libautocorrect_swift.dylib  → 3,212,288 B
OpenSuperWhisper.app/Contents/MacOS/OpenSuperWhisper                 → 23,470,928 B   (single binary, stripped, LTO)
OpenSuperWhisper.app/Contents/Resources/                             → 2.1 MB
OpenSuperWhisper.app/Contents/Helpers                                → does not exist
```

Release `Contents/Resources`: `AppIcon.icns`, `FluidAudio_FluidAudio.bundle`, `GRDB_GRDB.bundle`, `KeyboardShortcuts_KeyboardShortcuts.bundle`, `ggml-silero-v5.1.2.bin` (885,098 B), `notification.mp3`, `tray_icon.pdf` **[M]**. Debug adds `Contents/MacOS/OpenSuperWhisper.debug.dylib` (59,589,776 B) and `__preview.dylib` (Xcode 16+ debug-dylib build) **[M]**.

`otool -L` of the Release main binary — the only non-system entries are the two bundled dylibs **[M]**:

```
@rpath/libomp.dylib
@rpath/libautocorrect_swift.dylib
/usr/lib/libc++.1.dylib
… 45 further entries, all /System/Library or /usr/lib (Accelerate, Metal, MetalKit, AVFoundation,
   SwiftUI, CoreML, libswift*.dylib, libsqlite3.dylib …)
```

`LC_RPATH` of the Release binary **[M]**: `/usr/lib/swift`, `@executable_path/../Frameworks`. **No build-machine path leaks into the Release binary.** The Debug binary *does* carry an absolute rpath `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo/build/Build/Products/Debug/PackageFrameworks` **[M]** — Debug-only, never shipped.

The two dylibs `run.sh` copies **[M]**:

```
libomp.dylib:                  LC_ID_DYLIB = @rpath/libomp.dylib
                               deps: /usr/lib/libSystem.B.dylib            (nothing else)
libautocorrect_swift.dylib:    LC_ID_DYLIB = @rpath/libautocorrect_swift.dylib
                               deps: /usr/lib/libiconv.2.dylib, /usr/lib/libSystem.B.dylib
```

They are embedded in the bundle by a **Copy Files phase with `dstSubfolderSpec = 10` (= Frameworks)** — `project.pbxproj:112-124`, `CodeSignOnCopy` attributes at `:35-36` — staged from `$(PROJECT_DIR)/build/` by `run.sh`/`notarize_app.sh` **[R]**. `LD_RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks` resolves them **[M]**.

**Statically linked, not dylibs** **[M]**: `libwhisper.a`, `libggml.a`, `libggml-base.a`, `libggml-blas.a`, `libggml-cpu.a`, `libggml-metal.a` are linked as products of the CMake-generated subproject `libwhisper/build/libwhisper.xcodeproj` **[R `project.pbxproj:22-27,127,213-222`]**:

```
$ nm -gU …/Debug/OpenSuperWhisper.app/Contents/MacOS/OpenSuperWhisper.debug.dylib | grep -c _ggml_metallib_   → 2
$ nm -gU … | grep _ggml_metal_init                                                                          → T _ggml_metal_init
$ strings -a …/Release/…/OpenSuperWhisper | grep -cE 'kernel_mul_mm|ggml_metal_init'                        → 122
```

**Metal shaders are embedded in the static library, not shipped as a resource**: the repo's CMake cache has `GGML_METAL=ON` and `GGML_METAL_EMBED_LIBRARY=ON` **[M]** and the build produces no `.metallib` file **[M]**. This is why the whisper engine needs no resource bundle — the pattern llama.cpp reproduces exactly (same option, same result; see §2).

**One packaging wart, measured:** `OTHER_LDFLAGS = -lomp`, `LIBRARY_SEARCH_PATHS` includes `/opt/homebrew/opt/libomp/lib`, and `libomp.dylib` is copied into `Contents/Frameworks` — but **nothing calls OpenMP**: `xl dyld_info -undefined … | grep -ci omp` → **0**, `nm -u` has no `omp_*` symbols, `libggml-cpu.a` has 0 undefined `_omp_*` symbols, and ggml was configured `GGML_OPENMP_ENABLED=OFF` (OpenMP not found at configure time) **[M]**. So: Homebrew `libomp` is a **build-time hard dependency** (the link fails without it; CI does `brew install libomp` **[R `.github/workflows/build.yml`]**) that ships a 721 KB dylib nobody needs. Removing the three references (`OTHER_LDFLAGS`, the search path, the Copy Files entry, the CI brew line) makes the app build with only cmake+rust+ruby and removes a Homebrew coupling from the release path **[I]**.

### 1.3 What the bundle does *not* contain: a usable model

`WhisperModelManager.copyDefaultModelIfNeeded()` looks for `Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin")` and copies it to app support **[R `WhisperModelManager.swift:88-107`]**. Measured facts:

* `ggml-tiny.en.bin` (77,704,715 B) **is tracked in git at the repo root** (`git cat-file -s HEAD:ggml-tiny.en.bin` → 77704715) **[M]**;
* it is referenced by a stale `PBXFileReference` (`project.pbxproj:168`) but belongs to **no build phase** — the app target's `PBXResourcesBuildPhase` has an empty `files = ()` (`project.pbxproj:583-605`) **[M]**;
* the app's `OpenSuperWhisper/` folder is a `PBXFileSystemSynchronizedRootGroup` (`project.pbxproj:184-203`, attached to the target at `:424-426`) **[M]**, which is *why* `ggml-silero-v5.1.2.bin`, `notification.mp3`, `tray_icon.pdf` and the three SPM bundles *are* in `Resources` while a file at the repo root is not;
* the built bundles (Debug and Release) contain **no `ggml-tiny.en.bin`** **[M]**.

Consequence: on a clean machine `copyDefaultModelIfNeeded()` silently does nothing (`Bundle.main.url` → nil), the app-owned model folder `~/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/` stays empty **[M]**, and `WhisperEngine` throws `TranscriptionError.contextInitializationFailed` when the configured path is missing **[R `WhisperEngine.swift:100-111`]**. The app therefore *cannot* transcribe out of the box today, and the captain's machine only works because his `selectedWhisperModelPath` points **inside a git checkout** (see §1.5) **[M]**. **One-line fix for the ship task:** move (or copy) `ggml-tiny.en.bin` under `OpenSuperWhisper/` so the synchronized folder bundles it (74 MB, and it is already in the repo's history).

### 1.4 Every path the app writes outside its bundle

Commands behind each row are given verbatim; all were run on the captain's live machine, read-only.

| # | Path | Evidence | Written by |
|---|---|---|---|
| 1 | `~/Library/Application Support/ru.starmel.OpenSuperWhisper/` | `find ~/Library -maxdepth 5 -iname '*starmel*'` | `WhisperModelManager.swift:71-75`, `Recording.swift:37-41` (`Bundle.main.bundleIdentifier` + folder) |
| 2 | `…/ru.starmel.OpenSuperWhisper/recordings/` (`.wav` per recording) | `ls -la …/recordings` → empty, 14:15 | `Recording.recordingsDirectory` + `url` **[R `Recording.swift:37-48`]** |
| 3 | `…/ru.starmel.OpenSuperWhisper/recordings.sqlite` (28,672 B) | `ls -la …` → 28 KB, 14:02 | `RecordingStore.init` **[R `Recording.swift:86-91`]** (GRDB) |
| 4 | `…/ru.starmel.OpenSuperWhisper/whisper-models/` (currently empty) | `ls -la …/whisper-models` | `WhisperModelManager.modelsDirectory`, created in `init` **[R `WhisperModelManager.swift:77-87`]** |
| 5 | `~/Library/Preferences/ru.starmel.OpenSuperWhisper.plist` (1,077 B; 16 keys) | `defaults read ru.starmel.OpenSuperWhisper`; `defaults domains \| tr , '\n' \| grep starmel` | `AppPreferences` (`UserDefaults.standard`) **[R `AppPreferences.swift:1-34`]** — also SwiftUI window-frame autosave keys |
| 6 | `~/Library/Caches/ru.starmel.OpenSuperWhisper/` (80 KB: `Cache.db`, `-shm`, `-wal`, `fsCachedData/`) | `find ~/Library/Caches/ru.starmel.OpenSuperWhisper -maxdepth 2` | `URLSession.shared` / `URLSessionConfiguration.default` in `TranslationService` and `WhisperModelManager.downloadModel` (URLCache) **[R]** |
| 7 | `~/Library/HTTPStorages/ru.starmel.OpenSuperWhisper/` (60 KB: `httpstorages.sqlite` + `-shm`/`-wal`) | `find ~/Library/HTTPStorages/ru.starmel.OpenSuperWhisper` | CFNetwork, automatic for the same URLSessions **[I]** |
| 8 | `$TMPDIR/temp_recordings/` (+ per-conversion temp copies) | `ls -la "${TMPDIR}/temp_recordings"` → exists, 14:02 | `AudioRecorder.temporaryRecordingsDirectory` **[R `AudioRecorder.swift:40-41,98`]**; `WhisperEngine.swift:421-423,439` |
| 9 | `~/Library/Application Support/CrashReporter/OpenSuperWhisper_C759CB27-….plist` | `find ~/Library -maxdepth 5 -iname '*OpenSuperWhisper*'` | macOS (crash metadata), not app code |
| 10 | `~/Library/Logs/DiagnosticReports/OpenSuperWhisper-*.ips` (**12 files**, all SIGABRT, today 14:10–14:16) | `ls ~/Library/Logs/DiagnosticReports/OpenSuperWhisper-*.ips \| wc -l` → 12; `grep termination` → `"SIGNAL","Abort trap: 6"` | macOS (ReportCrash) |
| 11 | `~/Library/Application Support/FluidAudio/Models/<version>/` | **absent** on this machine; path comes from `AsrModels.defaultCacheDirectory` called at `Settings.swift:295-299` and implemented in `FluidAudio/…/Tdt/AsrModels.swift:683-685` | FluidAudio package, only if the Parakeet engine is used **[R]** |
| 12 | TCC grants: microphone, accessibility, input-monitoring | entitlements file; `PermissionsManager` queries `AVCaptureDevice.authorizationStatus` / `IOHIDCheckAccess` **[R `PermissionsManager.swift:21-25`]** | macOS `tccd` (cannot be inspected without Full Disk Access; **[NV]** contents) |

Checked and **absent** on this machine — so the uninstall list must not pretend they exist **[M]**: `~/Library/Saved Application State/*` (no entry for this bundle id), `~/Library/LaunchAgents` + `/Library/LaunchAgents|LaunchDaemons` (no entry), `~/Library/Containers|Group Containers` (none), `~/Library/Application Scripts/ru.starmel.OpenSuperWhisper` (none — though the released cask's `zap` lists it, §4.3), Keychain items (no `SecItem`/`kSec*` code in the app at all **[R]**, grep → empty), login items (`launchOnLogin|SMAppService|LoginItem|launchctl|NSTask|Process()` → **no matches** in `OpenSuperWhisper/` **[M]** — the app has **no launch-at-login and spawns no processes**).

`~/Library/Application Support/superwhisper/` (`model-manifest.json`, `model-installs.json`, `models/{argmaxinc,supervocab,cohere-transcribe}`, `s1-mini.gguf`, `ggml-large-v3-turbo.bin`, `*.onnx`, `agent/inbox`) is **not this app's**: it belongs to `com.superduper.superwhisper` 2.18.3 at `/Applications/superwhisper.app` (`defaults read /Applications/superwhisper.app/Contents/Info.plist CFBundleIdentifier` → `com.superduper.superwhisper`) **[M]**. This fork's bundle id is `ru.starmel.OpenSuperWhisper` **[M, built Info.plist]**; its `CFBundleShortVersionString` is 0.1.0, `CFBundleVersion` 13, `LSMinimumSystemVersion` 14.0, no `LSUIElement`, no `CFBundleURLTypes` **[M]**.

### 1.5 The transform feature's out-of-bundle inventory (the "goodwill")

| Need | Evidence |
|---|---|
| Homebrew `llama.cpp` 0.3.0 | `which llama-server` → `/opt/homebrew/bin/llama-server` → `../Cellar/llama.cpp/0.3.0/bin/llama-server`; `brew list --versions llama.cpp` → 0.3.0; Cellar 18 MB **[M]** |
| A repo script to run it | `Scripts/transform-server.sh` (4.8 KB) **[R]** — also `--fetch` (986 MB download with sha256 pin) and `--check` |
| A live process on a fixed port | `lsof -nP -iTCP:1919 -sTCP:LISTEN` → `llama-ser PID 86481`; `ps` cmdline: `llama-server --model ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf --alias … --port 1919 --ctx-size 4096 --n-gpu-layers 99`; `curl /health` → `{"status":"ok"}` **[M]** |
| A 986 MB model outside the app | `~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf` = 986,048,768 B **[M]** (identical to the HF file size for `bartowski/Qwen2.5-1.5B-Instruct-GGUF` Q4_K_M → 986048768 **[M]**). The same `~/models` also holds an unrelated `Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf` (19,032,651,904 B) that the uninstaller must never touch **[M]** |
| User preferences pointing at all of it | `defaults read ru.starmel.OpenSuperWhisper` → `transformEndpoint = http://127.0.0.1:1919/v1/chat/completions`, `transformModel = "Qwen/Qwen3-14B-MLX-6bit"` (**stale**, code default is `qwen2.5-1.5b-instruct-q4_k_m`), `transformTimeout = 8`, `translateEnabled = 0`, `whisperLanguage = en`, `selectedEngine = whisper`, `selectedWhisperModelPath = "/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo/ggml-tiny.en.bin"` **[M** — full 16-key dump]** |
| The verification harness | `Scripts/verify-transform.sh` — I ran it against the live backend: **`ALL CHECKS PASSED (checks: 132)` in 3.98 s** **[M]**. It extracts the system prompt from `TranslationService.swift` and defaults from `AppPreferences.swift` **[R `verify-transform.sh:25-29`]**, so it fails if app and backend drift |

**The fragility the design must absorb [M]:** `selectedWhisperModelPath` is an absolute path **inside a git checkout**. A `git clean`, a branch switch, a moved/renamed worktree, or uninstalling the source tree breaks dictation with `contextInitializationFailed` and no fallback. Any packaging design must (a) own model storage under `~/Library/Application Support/<bundle id>/`, and (b) migrate/reject stored paths that point outside it (§5).

---

## 2. Runtime options for the transform model, evaluated

### 2.0 The blocker I found by testing it: two vendored `ggml`s cannot share one image

Both engines vendor `ggml` as a submodule at different versions **[M]**:

| | whisper.cpp (this repo, `libwhisper/whisper.cpp`, v1.9.3 `371b5a75`) | llama.cpp (master at probe time `4e416ee`, version 0.4.1-dev) |
|---|---|---|
| vendored ggml | **0.20.2** | **0.25.0** |

Global symbols defined by both archive pairs **[M]** (`nm -gU … | awk '$2 ~ /^[TDSRB]$/' | sort -u | comm -12`):

```
libggml-base.a   whisper 2552 unique globals, llama 951, shared  → 936
libggml-cpu.a                                                    → 602
libggml-metal.a                                                  → 259
```

A real link of a program using both engines statically **[M]**:

```
duplicate symbol '_ggml_soft_max_add_sinks' in:
    …/libwhisper/build/whisper.cpp/ggml/src/Release/libggml-base.a[8](ggml-f3b137e2….o)
    …/llama.cpp/build-static/ggml/src/Release/libggml-base.a[8](ggml-c50b4262….o)
duplicate symbol '_ggml_dup' in: … duplicate symbol '_ggml_graph_nodes' in: …
ld: symbol(s) not found / duplicate symbol(s) — no binary produced
```

Two safe in-process shapes follow from this (both then **proven by running**), plus the helper-process shape:

### 2.1 Option A″ — one ggml, both engines statically in-process (**recommended**)

Build llama.cpp static (as today's `libwhisper/` does), **install its ggml**, then build whisper.cpp against *that same ggml* (`WHISPER_USE_SYSTEM_GGML=ON` → `find_package(ggml REQUIRED)` **[R `whisper.cpp/CMakeLists.txt:89,158-166`]**; llama.cpp likewise has `LLAMA_USE_SYSTEM_GGML` **[R `llama.cpp/CMakeLists.txt:51`]**). One ggml, one Metal backend, no port, no process, no Homebrew.

Measured **[M]**:

```
cmake --install llama.cpp/build-static --config Release --prefix /tmp/fm07/ggml-prefix
   → prefix/lib/{libggml,libggml-base,libggml-cpu,libggml-blas,libggml-metal}.a + include/ggml.h
   → prefix/lib/cmake/ggml/ggml-config.cmake                                    (4.7 MB total)
     (exit status 1 only because LLAMA_BUILD_TOOLS=OFF made the tools install manifest
      reference a non-existent batched-bench binary — the ggml package itself installed fine)
cmake -G Xcode -B wh-ggml25 -S libwhisper/whisper.cpp -DWHISPER_USE_SYSTEM_GGML=ON \
      -Dggml_DIR=/tmp/fm07/ggml-prefix/lib/cmake/ggml -DBUILD_SHARED_LIBS=OFF …   → configure OK 6.7 s
xcodebuild -scheme whisper -configuration Release …                                → compiles, warnings only
   → libwhisper.a 530,280 B
```

Then the decisive run — **both engines, one process, one ggml** (`/tmp/fm07/coexist.cpp`, throwaway):

```
APP_IMAGE_GGML_VERSION=0.25.0
APP_IMAGE_GGML_COMMIT=4e416ee
WHISPER_LOAD_OK
WHISPER_PCM_SAMPLES=176000
WHISPER_FULL_RC=0 NSEG=2
WHISPER_TEXT= And so my fellow Americans ask not what your country can do for you ask what you can do for your country.
LLAMA_LOAD_OK
LLAMA_VOCAB_TOKENS=151936
LLAMA_CTX_OK
LLAMA_TOKENS=11
LLAMA_DECODE_RC=0
COEXIST_DONE                      (exit 0)
ggml_metal_library_init: using embedded metal library
ggml_metal_library_compile_all: loaded 20 libraries from embedded data in 0.011 sec
```

Build cost **[M]**: llama.cpp configure 23 s + static build 29 s (`-jobs 8`, M4); whisper.cpp rebuilt against ggml 0.25 in seconds. Size **[M]**: `libllama.a` 5,677,928 + `libwhisper.a` (ggml 0.25) 530,280 + the single ggml set 4.4 MB ≈ **10.6 MB of archive input**; today's whisper-only archive input is 7.7 MB (whisper 788,984 + ggml-base 2,164,376 + ggml-cpu 3,150,544 + ggml-metal 1,454,112 + ggml 71,808 + ggml-blas 51,520). Expect the Release binary (23.5 MB today, stripped + LTO) to grow by roughly the size of `libllama` net of dead-strip — **order of +4–6 MB [I]**, not a package-size decision changer.

**Cost/risk of A″:** whisper.cpp becomes coupled to the pinned llama.cpp ggml version (an upstream-supported but version-sensitive configuration). Mitigation: pin both submodules, add the ggml compatibility check to CI, and lean on the repo's existing whisper regression tests (`WhisperTurboRegressionTests`, `LongFormTranscriptionTests`, `WhisperPreparationTests`) to prove the rebuild changed nothing **[R]**.

### 2.2 Option A′ — llama.cpp as embedded dylibs (**in-process fallback, also proven**)

Leave whisper's static build alone; build llama.cpp with `BUILD_SHARED_LIBS=ON` and embed its dylibs in `Contents/Frameworks` exactly like `libomp`/`libautocorrect_swift` (the repo already has this pattern, `install_name_tool -id @rpath/…` + Copy Files + `CodeSignOnCopy` **[R `run.sh`, `project.pbxproj:35-36,118-120`]**). Two-level namespace keeps the two ggml copies apart.

Measured **[M]**: shared build whole job 42 s; dylib set 7.25 MB —

```
build-shared/bin/Release/libllama.0.4.1.dylib        3,203,200
                          libggml-metal.0.25.0.dylib 2,171,856
                          libggml-cpu.0.25.0.dylib   1,033,312
                          libggml-base.0.25.0.dylib    731,344
                          libggml.0.25.0.dylib          59,984
                          libggml-blas.0.25.0.dylib     58,528
(+ the `.0` / unversioned name symlink chain, e.g. libggml.0.dylib → libggml.0.25.0.dylib)
```

Their cross-references are already `@rpath/libggml.0.dylib` etc. **[M]**, so embedding means: copy the six versioned files **plus their name symlinks**, sign each, done — no `install_name_tool` surgery beyond the `-id` convention. Metal is embedded (`GGML_METAL_EMBED_LIBRARY=ON` **[M]**), same as whisper.

Coexistence proven **[M]**: the same probe linked against whisper's *static* ggml 0.20.2 + llama's *shared* ggml 0.25.0 (binary 4,990,568 B) printed `APP_IMAGE_GGML_VERSION=0.20.2` while llama's own Metal context reported its 0.25.0 buffers, and both engines ran to completion in 24 s wall (dominated by first-run Metal pipeline creation) **[M]**: whisper transcribed `jfk.wav`, llama loaded the 986 MB GGUF and decoded on Metal.

**Cost/risk of A′:** two ggml copies in one process (≈ two Metal backends, duplicated code/RSS), six dylibs to sign and keep coherent; in exchange, **zero change to the shipped STT path**.

### 2.3 Option B — bundled `llama-server` helper (smallest code change)

Ship a self-contained `llama-server` inside the bundle and let the app start/stop it. Measured **[M]**: a static, `LLAMA_OPENSSL=OFF`, `LLAMA_BUILD_SERVER=ON`, `LLAMA_USE_PREBUILT_UI=OFF`, `LLAMA_BUILD_UI=OFF` build produces **`llama-server` 14,551,472 B** in **50 s** linking **only Apple system frameworks**:

```
/System/Library/Frameworks/{Accelerate,Foundation,Metal,MetalKit,CoreFoundation}.framework
/usr/lib/{libc++.1,libSystem.B,libobjc.A}.dylib        (no OpenSSL, no rpath, no dylib siblings)
```

For comparison, the Homebrew helper this feature *must stop requiring* is a dynamic build: `llama-server` + `libllama-server-impl` 6.19 MB + `libllama-common` 4.78 MB + `libllama` 2.80 MB + `libmtmd` 1.14 MB + ggml 0.22 dylibs ≈ 8.9 MB measured `du`, plus an `openssl@3` dependency **[M]** — and Homebrew keeps it in a store the app cannot own.

Lifecycle work B needs (none of it exists in the app today — no `Process`/`NSTask` anywhere **[M]**): pick a port (or dynamic port + plumb it into the endpoint the app uses), spawn at launch/lazily, wait for `/health`, kill on quit + guard against orphans on force-quit, restart on crash, drain logs, handle "port already in use by the user's own `llama-server`" (a real condition on this machine right now, PID 86481 **[M]**; `transform-server.sh` itself refuses to start in that case **[R]**), and firewall/Screen-Recording-style prompts are replaced by a Metal/GPU-sharing story between two processes. Cost: fewer new *language-boundary* risks, more operational failure modes.

**Its one genuine advantage:** the app's HTTP request contract, the live-verified `TranslationService`, and `Scripts/verify-transform.sh` (132/132 **[M]**) survive essentially unchanged.

### 2.4 Option C — MLX / `mlx-swift` (rejected)

* **Dependency weight [R, upstream `Package.swift`]:** `mlx-swift` vendors the whole MLX C++ core as an SPM target (`Cmlx`) requiring `cxxLanguageStandard: .gnucxx20` and a plugin/`swift-syntax`-based macro package for the LLM half (`mlx-swift-lm`, `swift-tools-version: 6.2`, depends on `swift-syntax 602–604`), plus the vendored `xgrammar` C++ in newer layouts. Platform floor macOS 14.0 — fine — but the toolchain floor is Swift 6.2/6.3 packages **against an app project that sets `SWIFT_VERSION = 5.0`**; whether that combination builds here is **[NV]**.
* **It cannot read GGUF:** the SwiftPM package explicitly excludes `mlx/mlx/io/gguf.cpp`, `gguf_quants.cpp` **[R]**, so weights must be MLX/safetensors — a model *directory*, not one file.
* **Model size [M]** (`huggingface.co/api/models/mlx-community/Qwen2.5-1.5B-Instruct-4bit/tree/main`): `model.safetensors` 868,628,559 B + tokenizer/vocab/merges ≈ 11.5 MB ⇒ **≈ 880 MB**, versus **986,048,768 B** for the current Q4_K_M GGUF (and the stale per-machine pref `Qwen/Qwen3-14B-MLX-6bit` would be ~11 GB — not shippable).
* **Fit:** it adds a *third* inference stack to a repo whose only native inference is whisper.cpp, and the existing prompt/parse/timeout code would have to be rewritten against MLX's API. Rejected for this ticket; keep as a future option if a larger model is ever wanted.

### 2.5 Comparison, and what each does to the verified HTTP service

| | **A″ one ggml, both static** (rec.) | A′ llama as embedded dylibs | B bundled `llama-server` helper | C MLX |
|---|---|---|---|---|
| Ports / processes | none | none | 1 process, 1 port, lifecycle code | none |
| Extra package weight | ≈ +4–6 MB [I] (10.6 MB archive in) | 7.25 MB dylibs + symlinks [M] | 13.9 MB helper [M] | MLX core (unmeasured, large) + ~880 MB model |
| Build cost | configure 23 s + 29 s static, + whisper rebuild (seconds) [M] | shared build 42 s [M] | 50 s tool build [M] | **[NV]** |
| Metal | embedded metallib, one backend [M] | embedded, two backends in-process [M] | embedded, separate process [M] | MLX metallib, separate stack |
| Homebrew needed at build | **no** | no | no | no |
| New app code | llama C API wrapper (~as `Whis.swift`) + prompt/template port | same wrapper | process supervisor + readiness/crash/port + endpoint plumbing | new stack + API rewrite everywhere |
| Verified today by running? | **yes, both engines, real models** [M] | **yes, both engines, real models** [M] | helper built + self-containment measured; app-side lifecycle not built **[NV]** | no |
| Effect on `TranslationService` + `verify-transform.sh` | `transform()`'s HTTP call becomes an in-process call; prompt/parse code kept as the *advanced override* path ⇒ the harness stays valid for override configs, and the default path needs a new in-process contract test | same | **unchanged**, harness stays byte-identical (strongest continuity) | rewrite |
| Settings | `transformEndpoint`/`transformModel`/`transformTimeout` become **Advanced overrides** (empty endpoint ⇒ built-in local runtime); the model picker stays and gains the transform model | same | endpoint becomes app-managed (dynamic port) ⇒ overrides only | model id changes format |

**Migration shape common to A″/A′, to keep the sibling tone/language work independent:** keep `TranslationService.transformIfEnabled(_:) async -> String` as the *only* entry point and its "never throws, always returns text" contract (`TranslationService.swift:66-78` **[R]**), so `IndicatorWindow.swift:280` does not move; put the new runtime behind it, and keep the static/pure helpers (`systemPrompt(for:)`, `parseContent`, `stripReasoning`) because the HTTP override still uses them. `Scripts/verify-transform.sh` then needs a new sibling check for the in-process path (its current 132 checks are HTTP-shaped **[R]**), while remaining valid for override configurations.

---

## 3. Model weights: bundled vs downloaded

### 3.1 What the fork actually has (and what it does not)

**[M/R]** The fork **owns no manifest machinery**. Its model story is three pieces of code:

1. **`WhisperModelManager`** **[R `WhisperModelManager.swift`]** — one directory, `~/Library/Application Support/<bundle id>/whisper-models/`, a generic `downloadModel(url:name:progressCallback:)` (URLSession download task, progress, cancellation, atomic move into place) plus `isModelDownloaded(name:)` and `getAvailableModels()`.
2. **The catalogue + download UI** `SettingsDownloadableModels.availableModels` **[R `Settings.swift:600-640`]** — hard-coded Hugging Face URLs (whisper turbo variants, Hebrew fine-tune) with a progress UI and "Open Folder" button **[R `Settings.swift:844-856,1914-1957`]**.
3. **The Parakeet path** — FluidAudio's own cache dir `~/Library/Application Support/FluidAudio/Models/<version>/` **[R `Settings.swift:295-299`, FluidAudio `AsrModels.swift:683-685`]**, absent on this machine **[M]**.

`model-manifest.json` / `model-installs.json` / `models/` are the **commercial SuperWhisper's** state (§1.4) **[M]**. Nothing in this fork reads or writes them **[R, repo-wide grep]**.

Where a transform model would belong: **`~/Library/Application Support/ru.starmel.OpenSuperWhisper/transform-models/`**, written by a `TransformModelManager` built on the same download primitive, with **sha256 verification** using the hash the repository already pins (`Scripts/transform-server.sh` `MODEL_SHA256=1adf0b11…6c3370` **[R]**).

### 3.2 Bundled vs downloaded

| | **Bundled in the package** | **Downloaded on first use into app-owned storage** (recommended) |
|---|---|---|
| Artifact size | ~1 GB DMG/pkg (986 MB model + 28 MB app; notarization upload of ~1 GB) | ~30–40 MB artifact |
| Install = one package | yes, and never touches the network again; matches "install with a single package" most literally | yes, but the first transform needs network (or a manual side-load) |
| Offline from minute one | yes | only after the first download |
| Every app update | re-downloads 1 GB; cask/`brew` store keeps a second copy while upgrading; dSYM/notary cost grows | unchanged |
| State outside the app | none | ~1 GB in Application Support that **uninstall must delete** and reinstall must re-fetch |
| Precedent in this product | the 74 MB `ggml-tiny.en.bin` is in git but *not* bundled (bug, §1.3); FluidAudio models are app-cached, whisper models are downloaded | exactly how whisper models already work **[M/R]** |
| Failure modes | packaging size, notarization timeouts, "app is 1 GB" reviews | partial/corrupt download → must be sha256-verified and re-fetchable; needs a visible state in Settings |

**Recommendation: download on first use, sha256-pinned, into `…/transform-models/`, with an explicit "Download model (~986 MB)" affordance in Translation & Tone and a **fully-offline variant** (same `.pkg`, model pre-seeded into the app support dir by an installer *choice*) only if the captain wants a 1 GB artifact.** Rationale: the app is useless offline anyway until a whisper model is fetched (today it ships none), so a 986 MB fetch is consistent product behaviour, whereas doubling every release artifact and notarization upload is a permanent tax. **[I]**

Licensing, measured **[M]**: `Qwen/Qwen2.5-1.5B-Instruct` → `license: apache-2.0`; `bartowski/Qwen2.5-1.5B-Instruct-GGUF` → `apache-2.0`; llama.cpp → MIT. If the model is *bundled*, the package must carry the Apache-2.0 notice; if downloaded, the app should show source + licence before fetching.

---

## 4. Install and uninstall as one unit

### 4.1 How releases are made today

**[R]** `run.sh` (dev/builder): `cmake -G Xcode -B libwhisper/build -S libwhisper` → cargo `autocorrect-swift` → `install_name_tool -id @rpath/…` → `cp /opt/homebrew/opt/libomp/lib/libomp.dylib build/` → `xcodebuild -scheme OpenSuperWhisper -configuration Debug … -derivedDataPath build -clonedSourcePackagesDirPath SourcePackages CODE_SIGNING_ALLOWED=NO`. Then it strips quarantine with `xattr -d com.apple.quarantine …` and runs the binary in the foreground.

`make_release.sh <version> <identity> <token>`: bumps `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.pbxproj`, `rm -rf build`, calls `notarize_app.sh`, writes `OpenSuperWhisper.dmg` + `.sha256`, optionally zips the dSYM, commits the version bump, tags, pushes, uploads DMG+dSYM to a GitHub release, and prints a **Homebrew cask** snippet.

`notarize_app.sh <identity>` **[R]**: clean `libwhisper/build`, cmake, cargo, `install_name_tool`, `codesign --force --sign <identity> --timestamp` on both dylibs, `xcodebuild -configuration Release` with `CODE_SIGN_STYLE=Manual`, `DEVELOPMENT_TEAM=8LLDD7HWZK`, `OTHER_CODE_SIGN_FLAGS=--timestamp`, then `zip` → `xcrun notarytool submit --wait --keychain-profile Slava` → `xcrun stapler staple <app>` → `swifty-dmg` → `codesign` the DMG → notarize + staple the DMG.

Artifacts: `OpenSuperWhisper.dmg` (+ `.sha256`), `OpenSuperWhisper.app.dSYM.zip`, a git tag, a GitHub release; distribution is the DMG and the Homebrew cask `opensuperwhisper` (`app "OpenSuperWhisper.app"`, `zap trash:` with **only two** entries) **[R]**.

`.github/workflows/build.yml` is a **build check only** (ubuntu-style `macos-latest` runner: `brew install cmake libomp rust`, `gem install xcpretty`, `./run.sh build`) — **no release job, no signing, no notarization in CI** **[R]**. Note also: `notarize_app.sh` requires `swifty-dmg`, which is **not declared in the `Gemfile`/`Gemfile.lock`** (`fastlane`, `xcpretty` only) and is **not installed on this machine** **[M]** — so the release path is currently broken-by-omission unless the operator installs that gem by hand.

### 4.2 What a user must do on a clean machine today

* **Released app (cask or DMG):** `brew install opensuperwhisper`, or drag from the DMG. Nothing else — the DMG *and* the app are notarized and stapled **[R]**, so no quarantine override is needed **[I]**. If a user encounters a quarantined copy, the repo's own idiom is `xattr -d com.apple.quarantine` **[R `run.sh`]**.
* **Building locally:** `git clone` + `git submodule update --init --recursive`, `brew install cmake libomp rust ruby`, `gem install xcpretty`, `./run.sh build` **[R `Readme.md`]**. `run.sh` hard-requires Homebrew `libomp` to exist even though nothing links against OpenMP symbols (§1.2) **[M]**, so this list cannot be shortened without the small edit described there.
* **To use the transform feature (today's state):** `brew install llama.cpp`, then run `Scripts/transform-server.sh --fetch` once (986 MB) and keep that script running in a terminal, and set endpoint/model by hand in Settings **[R `Readme.md`, `Scripts/transform-server.sh`]**. This is the "few different applications connected by goodwill".
* **On this machine specifically:** signing/notarization is impossible right now — `security find-identity -v` → **0 valid identities**, no `Slava` notarytool profile **[M]**. `pkgbuild`, `productbuild`, `productsign`, `codesign`, `spctl`, `notarytool`, `stapler`, `hdiutil` are all present **[M]**, so packaging can be *built* and tested here; only the final sign/notarize step needs the captain's Developer ID machine or CI.

### 4.3 The recipe: one artifact to install, one operation to uninstall

**One artifact — `OpenSuperWhisper-<version>.pkg`** (stock tooling, no third-party gems):

```console
# payload: just the app bundle, and (option A″) the vendored llama.cpp is inside it
$ pkgbuild --root pkgroot --identifier ru.starmel.OpenSuperWhisper --version <ver> \
      --install-location / --scripts scripts/ OpenSuperWhisper-component.pkg
$ productbuild --distribution distribution.xml --package-path . \
      --sign "Developer ID Installer: … (8LLDD7HWZK)" OpenSuperWhisper-<ver>.pkg
$ xcrun notarytool submit OpenSuperWhisper-<ver>.pkg --wait --keychain-profile <profile>
$ xcrun stapler staple OpenSuperWhisper-<ver>.pkg
```

* `scripts/preinstall` **[to write]**: quit a running copy (`osascript -e 'quit app "OpenSuperWhisper"'`, then `pkill -x OpenSuperWhisper` as a fallback) so a bundle replacement cannot corrupt an in-flight recording/DB write; refuse to proceed only if the app cannot be quit.
* No `postinstall` is needed if the migration lives in the app (§5.1); a `postinstall` **must not** delete user data.
* The pkg receipt id is `ru.starmel.OpenSuperWhisper` — that is what makes "uninstall" auditable (`pkgutil --pkg-info ru.starmel.OpenSuperWhisper`).
* Keep emitting the DMG **only** for the Homebrew cask, and point the cask at the pkg (`pkg "OpenSuperWhisper-<ver>.pkg"`) so there is exactly one payload definition **[I]**.

**One uninstall operation.** macOS has no native uninstall for `.pkg` — the *package* must ship the operation. Canonical: a single script with two entry points.

1. **In-app menu item** (`Settings` → General and/or the status-bar menu): *"Uninstall OpenSuperWhisper…"* → explanation of exactly what will be deleted → user confirms → the app writes a small script to `$TMPDIR`, launches it detached with `/bin/sh`, then quits. The script waits for the app's PID to exit, removes the paths below, forgets the receipt, and deletes itself. (An app cannot delete its own running bundle; this is the standard two-step.)
2. **Shipped `Uninstall OpenSuperWhisper.command`** (double-clickable, same script) inside the pkg payload (e.g. `/Applications/OpenSuperWhisper Uninstall.command`) for users who already dragged the app to the Trash.
3. **Homebrew users:** complete the cask `zap trash:` list so `brew uninstall --cask --zap opensuperwhisper` is equally complete.

The script — every path from §1.4, all idempotent:

```sh
#!/bin/sh
set -u
BID=ru.starmel.OpenSuperWhisper
APP=/Applications/OpenSuperWhisper.app
# 1. the app
osascript -e 'quit app "OpenSuperWhisper"' 2>/dev/null
pkill -x OpenSuperWhisper 2>/dev/null
rm -rf "$APP"
# 2. app-owned state (recordings, DB, whisper models, transform models)
rm -rf "$HOME/Library/Application Support/$BID"
rm -rf "$HOME/Library/Caches/$BID"
rm -rf "$HOME/Library/HTTPStorages/$BID"
rm -rf "$HOME/Library/Saved Application State/$BID.savedState"
rm -rf "$HOME/Library/Application Scripts/$BID"
defaults delete "$BID" 2>/dev/null; rm -f "$HOME/Library/Preferences/$BID.plist"
killall cfprefsd 2>/dev/null            # flush the prefs cache
# 3. OS leftovers named after the app
rm -f "$HOME/Library/Application Support/CrashReporter/OpenSuperWhisper_"*.plist
rm -f "$HOME/Library/Logs/DiagnosticReports/OpenSuperWhisper-"*.ips
rm -rf "${TMPDIR:-/tmp}/temp_recordings"
# 4. installer receipt
pkgutil --forget "$BID" 2>/dev/null
# 5. optional, off by default in the UI: privacy grants
# tccutil reset All "$BID"
exit 0
```

Explicitly **not** touched (and the UI should say so): `/opt/homebrew/**` (llama.cpp or anything else the user installed), `~/models/**`, any other app's data. After option A″ nothing outside `$HOME`'s app-owned paths is needed at all, so this list is complete by construction.

**Cask `zap` today vs what it should be [R/M]:** it currently lists `~/Library/Application Scripts/ru.starmel.OpenSuperWhisper` (which does not exist **[M]**) and `~/Library/Application Support/ru.starmel.OpenSuperWhisper` — missing prefs plist, `Caches`, `HTTPStorages`, `Saved Application State`, crash reports. The pkg-based uninstaller above supersedes it.

**Ask if the captain wants the crash-report and TCC cleanup:** removing `.ips` files is cosmetic; `tccutil reset` removes the microphone/accessibility grants (§1.4 #12) and will re-prompt on next launch. Ship it as a checkbox in the confirm sheet, default **off** (re-prompting is a worse experience than a stale grant).

---

## 5. Idempotence guarantees, and the change each one needs

| # | Invariant | Why it fails today | Specific change |
|---|---|---|---|
| 5.1a | **Install over an existing version converges** | Two superseded facts on the captain's machine: `selectedWhisperModelPath` points **inside a git checkout** **[M]**, and `transformModel = "Qwen/Qwen3-14B-MLX-6bit"` is **stale** versus the code default `qwen2.5-1.5b-instruct-q4_k_m` **[M]**. A new runtime must ignore a stored model id it does not recognise, and a model path outside app-owned storage must not be trusted. | Add a **versioned migration** in `AppPreferences.migrateOldPreferences()` (`AppPreferences.swift:30-34` **[R]**): a `prefsSchemaVersion` key; on upgrade (i) rewrite `selectedWhisperModelPath`/`selectedModelPath` to app-owned storage or clear it if the file is absent **[R `Settings.swift:269-271`]**; (ii) drop `transformEndpoint`/`transformModel`/`transformTimeout` values written before the runtime change (make them **advanced overrides** only, §2.5); (iii) never delete recordings/DB. |
| 5.1b | Installing over a **running** app is safe | The pkg would replace a live bundle; a recording or GRDB write can be in flight (`recordings.sqlite`, 28 KB live **[M]**). | `preinstall` script quits the app first (§4.3). |
| 5.1c | A downloaded model is never trusted blindly | A partial/old download is indistinguishable from a good one today: `isModelDownloaded` is an existence check only **[R `WhisperModelManager.swift:232-235`]**. | `TransformModelManager` verifies **sha256** before use (hash already pinned in `transform-server.sh` **[R]**) and re-downloads on mismatch; write to `.part` then atomically rename (same shape as the existing downloader **[R `WhisperModelManager.swift:131-215`]**). |
| 5.1d | Reinstall over an install with **bundled** models behaves the same | If the model ships in the bundle (rejected, §3.2), an upgrade must not leave a stale copy in Application Support shadowing the new one. | N/A for the recommended (download) option; if bundling is chosen, bump a model-version key and re-copy on change. |
| 5.2a | **Uninstall twice is harmless** | Not yet true: nothing implements uninstall at all. | Every step tolerant: `rm -rf` (no error on absence), `defaults delete … 2>/dev/null`, `pkgutil --forget … 2>/dev/null`, `killall`/`pkill` ignored, `exit 0` unconditionally, `rm -f` for globs. The script must also work when the app is **already gone** from `/Applications` (entry point 2). |
| 5.2b | Uninstall while the app runs | The app deletes its own bundle while executing. | Detached helper waits for the PID to exit (entry point 1, §4.3). |
| 5.2c | Uninstall never damages anything else | `~/models` holds an unrelated 19 GB Qwen3 GGUF **[M]**; Homebrew packages serve other tools. | Hard-coded path list (§4.3); no globs outside app-named paths; explicitly documented in the confirm UI. |
| 5.3a | **Reinstall after uninstall behaves like a first install** | Residual prefs/model/receipt state can make run #2 differ (e.g. a stale model path silently skipped). | Removal of every path in §1.4 (incl. `.plist` + `cfprefsd` flush) + the §5.1a migration. With prefs gone, `hasCompletedOnboarding` defaults to `false` **[R `AppPreferences.swift:96-97`]** and the app routes to `OnboardingView` again **[R `OpenSuperWhisperApp.swift:26-28`]** — that is the desired clean path. |
| 5.3b | Reinstall does not inherit a broken model | If the uninstaller missed `…/transform-models/`, a reinstall would silently reuse it. | The uninstaller removes the whole `<bundle id>` support dir (models included), **and** 5.1c verifies hashes anyway (belt and braces). |
| 5.3c | Model storage survives legitimate re-`install` (upgrade), not `uninstall` | Deleting user data on upgrade is as bad as keeping it on uninstall. | Uninstall removes data; the **installer never touches** `$HOME` (§4.3). |

---

## 6. Recommendation, fallback, work breakdown, risks

### 6.1 Recommendation — **A″**

**Vendor llama.cpp through the same CMake + Xcode flow the repo already uses for whisper.cpp, unify `ggml` (build whisper.cpp with `WHISPER_USE_SYSTEM_GGML=ON` against llama.cpp's ggml), link both engines statically into the app, and call the llama C API in-process.** No Homebrew, no shell script, no port, no second process, no file outside the app bundle — the transform feature becomes exactly the kind of dependency the whisper engine already is. Proven by running both engines against the real models in one process (§2.1) **[M]**.

Model weights are fetched on first use into `…/transform-models/` in app-owned storage (§3).

**Ship as:** one `OpenSuperWhisper-<ver>.pkg` (app + everything inside it, notarized + stapled) and one `Uninstall OpenSuperWhisper.command` + in-app uninstall action (§4.3).

### 6.2 Smaller fallback — **A′**, then **B**

* **A′** (llama.cpp as 6 embedded dylibs, whisper's build untouched): same in-process UX, zero risk to the shipped STT path, +7.25 MB of dylibs and two ggml copies in-process. Choose this if the ship task wants no coupling between whisper.cpp and llama.cpp's ggml version. **Proven by running [M].**
* **B** (bundled static `llama-server`, 13.9 MB, system frameworks only): the only option that leaves `TranslationService`, its 132-check harness **[M]** and the user-visible endpoint semantics untouched; cost is a process supervisor that does not exist in the app today. Choose this if the C-API wrapper turns out to be the risky part of the schedule.

Reject **C** (MLX) for this ticket (§2.4).

### 6.3 Work breakdown for a ship task, in order

1. **Vendor + unify ggml.** Add `third_party/llama.cpp` (submodule, pinned commit) and a `libllama/CMakeLists.txt` mirroring `libwhisper/CMakeLists.txt` (same `-G Xcode` flow, `GGML_METAL_EMBED_LIBRARY=ON`, `BUILD_SHARED_LIBS=OFF`, tools/tests/examples off, `LLAMA_CURL=OFF`, `LLAMA_OPENSSL=OFF`). Configure → install the ggml package to a build prefix → configure `libwhisper` with `WHISPER_USE_SYSTEM_GGML=ON -Dggml_DIR=<prefix>/lib/cmake/ggml`. Update `run.sh`, `notarize_app.sh`, and `.github/workflows/build.yml` with the new build order (and see step 7).
2. **Wire the Xcode project.** Add the llama CMake subproject reference, link `libllama.a` + the single ggml set, extend `HEADER_SEARCH_PATHS`, add `#include "llama.h"` to `Bridge.h`. Expected: no new bundle resources (Metal embedded), no `Contents/Helpers`.
3. **Swift C-API wrapper.** New `Whis/Llama.swift` (+ context/session types) modelled on `Whis.swift`: load/unload, `llama_chat_apply_template`, tokenize, sampler (temperature 0.2, same as today's body **[R `TranslationService.swift:118-129`]**), decode loop with stop conditions, cancellation between tokens, idle unload, and a warm-up path alongside `TranscriptionService.prepareForRecording()`.
4. **Keep the gate contract.** Keep `transformIfEnabled(_:) async -> String` and its never-throws contract; put the in-process runtime behind it; keep `systemPrompt(for:)` and the advanced-override HTTP path. **Coordination point with the sibling tone/language ship task: `transformIfEnabled`'s signature/contract and `transformEndpoint|Model|Timeout` are owned by one task at a time** (the fm-04 spec changes the gate's *inputs*; this packaging task changes what happens *after* the gate).
5. **`TransformModelManager`.** App-owned `transform-models/`, sha256 pinned (reuse `transform-server.sh`'s hash), atomic install, progress UI, "remove downloaded models" action, and a first-use download prompt in Translation & Tone.
6. **Packaging.** `packaging/` with `pkgbuild` + `productbuild` (+ `preinstall` quit hook), the uninstall script with both entry points, the in-app uninstall action, a completed cask `zap` list, and `make_release.sh` updated to emit `OpenSuperWhisper-<ver>.pkg` (+ DMG for the cask). Keep `notarize_app.sh`'s `swifty-dmg` dependency out of the pkg path, or declare it in the `Gemfile`.
7. **Independent small fixes that make the package honest:** bundle `ggml-tiny.en.bin` by moving it under `OpenSuperWhisper/` (§1.3); drop `-lomp`/`libomp.dylib`/the Homebrew search path/the CI `brew install libomp` (§1.2); decide the fate of the stale stored `transformModel` (§5.1a); delete the README's `brew install llama.cpp` + `transform-server.sh` section (keep the script only as an optional *external-backend* tool, if at all).
8. **Harness/tests.** `Scripts/verify-transform.sh` gains an in-process mode (or stays for the override path only) and must stay green; add an XCTest for the wrapper's template/prompt/stop behaviour; keep the repo's whisper regression tests as the proof that the ggml unification changed nothing.
9. **Docs.** Readme install/uninstall sections, the uninstall path list, and "what the app writes where".

### 6.4 Risks

| Risk | Severity | Mitigation |
|---|---|---|
| whisper.cpp pinned against a *foreign* ggml version (A″) regresses transcription | High if silent | Pin both submodules; run `WhisperTurboRegressionTests`, `LongFormTranscriptionTests`, `WhisperPreparationTests` + the fixture-based language tests on every ggml bump; CI gate. (A′ removes the risk entirely at +7.25 MB.) |
| Duplicate-symbol/ABI mixing creeps back in (e.g. someone links llama's `libggml*.a` "just to try") | High, silent | Never link two ggml copies statically; document it where `libllama` is configured; a CI link check catches it immediately (it is a hard link error, as measured). |
| Two Metal consumers in one process (A′; also A″ with whisper+llama) | Medium | Measured to work on M4 for both variants **[M]**; serialize heavy work (dictation and transform are sequential in the UI path **[R `IndicatorWindow.swift:244-291`]**); measure RSS/GPU during the ship task. |
| `.pkg` still "one artifact" but the model download is a hidden second step | Medium (user trust) | Make it explicit in the installer README + Settings, show progress, allow pre-seeding (offline variant) and a manual "Add model file…" path. |
| Uninstaller deletes too much or too little | High | Path list is closed and enumerated from §1.4; test the three scenarios in §5 by hand (install twice, uninstall twice, reinstall) with `find`/`defaults read` before/after. |
| Signing/notarization unavailable where the work happens (0 identities here **[M]**) | Medium | Keep the packaging script parameterised by identity/profile; validate with `codesign --verify --deep --strict` + `pkgutil --check-signature` locally and let the captain's machine/CI notarize. |
| `swifty-dmg` undeclared in the `Gemfile` | Low but blocking at release time | Either add it to `Gemfile.lock` or drop the DMG from the pkg path. |
| App currently aborts on some launch paths (12 SIGABRT reports today **[M]**) | Unknown | Out of scope here; the ship task should confirm a clean install actually launches before claiming "install once". |

---

## 7. Verified vs read vs not verified

**Verified by running something [M]:** the Release app build in `/tmp`; the in-repo Debug/Release bundle contents and every `otool`/`nm`/`strings`/`codesign`/`spctl` output quoted; the app-support/prefs/caches/HTTPStorages/crash-report inventory; the live endpoint (`/health`), the live `llama-server` process and its cmdline; `Scripts/verify-transform.sh` → 132/132; ggml version skew and the duplicate-symbol link failure; both coexistence variants (V1 dylib, V3 unified-ggml) running both engines against the real `ggml-tiny.en.bin`, the real 986 MB Q4_K_M GGUF and `jfk.wav`; llama.cpp static (29 s), shared (42 s) and `llama-server` (50 s, 14,551,472 B) builds and their sizes; whisper.cpp compiling and linking against ggml 0.25; the absence of signing identities and notary profiles on this machine; availability of `pkgbuild`/`productbuild`/`codesign`/`notarytool`/`stapler`/`hdiutil`.

**Read, not executed [R]:** `run.sh`, `make_release.sh`, `notarize_app.sh`, `.github/workflows/build.yml`, `Scripts/transform-server.sh`, `Scripts/verify-transform.sh` (its internals), `project.pbxproj` (build settings, Copy Files phase, synchronized groups), the app sources cited by `file:line` (`AppPreferences`, `WhisperModelManager`, `Recording`, `Settings` model catalogue, `TranslationService`, `WhisperEngine`, `IndicatorWindow`), FluidAudio's cache-directory implementation, and upstream `mlx-swift` / `mlx-swift-lm` package manifests.

**Not verified [NV], and should be treated as open:** I did not launch the built app (launching it would write into the captain's **live** preference/Application Support state, which the brief forbids — self-containment is therefore asserted from `otool -L` + the presence of the referenced files, not from an actual `open`); I did not sign, package, install or uninstall anything; I did not run the app's test suite; I did not measure Release binary growth when llama.cpp is linked in (the +4–6 MB is an estimate); I did not test the MLX option's buildability under this Xcode; the TCC database contents, the cause of today's 12 aborts, GPU/RSS behaviour with both engines warm, and the exact whisper-transcription quality after the ggml unification (both engines' outputs were validated functionally, not against the repo's fixtures).

## 8. Probe artefacts (all under `/tmp`, outside every checkout)

```
/tmp/fm07/repo/                     pristine copy + Release build (build-release.sh, build-release.log)
/tmp/fm07/llamaprobe/llama.cpp      llama.cpp clone (4e416ee, 0.4.1-dev) + build-static / build-srv / build-shared
/tmp/fm07/wh-ggml25                 whisper.cpp configured against ggml 0.25 (libwhisper.a 530,280 B)
/tmp/fm07/ggml-prefix               installed ggml 0.25 package (4.7 MB) from the llama.cpp build tree
/tmp/fm07/coexist.cpp               both-engines-in-one-process probe
/tmp/fm07/coexist_v1                whisper static + llama shared   → ran OK (APP_IMAGE_GGML_VERSION=0.20.2)
/tmp/fm07/coexist_v2                both static                     → link FAILS (duplicate symbols)
/tmp/fm07/coexist_v3                one ggml, both static           → ran OK (APP_IMAGE_GGML_VERSION=0.25.0)
/tmp/fm07/{llama-probe,server-probe,shared-probe,install}.log   raw command/timing evidence
```
