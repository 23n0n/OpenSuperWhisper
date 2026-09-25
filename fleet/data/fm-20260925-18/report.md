# fm-20260925-18 — packaging idempotence and a non-destructive uninstall

Branch `fm/package-idempotent`, worktree `repo/worktrees/OpenSuperWhisper-fm-packaging`.
Machine: this Mac (darwin 27.0.0, arm64). No push, no tag, no merge, no `sudo`, no writes to the
live `/Applications`, `/Library` or the captain's home directory.

Status: **done**, with the root-only steps listed under *What a real install still needs*.

## 1. What changed, and why

`packaging/uninstall.sh:140-142` used to be one `rm -rf "$SUPPORT_DIR"` standing for six different
kinds of thing: the app's recordings, its transcriptions database, its settings, its downloaded
models, its caches and its saved state. One uninstall therefore took the captain's 87 recordings,
his preferences and every model, unrecoverably — nothing went to the Trash. That is the defect.

| File | Change |
| --- | --- |
| `packaging/uninstall.sh` | Path-granular list (below). New `--remove-user-data`; `--help` says what each option does. Also removes the shipped `/Applications/Uninstall OpenSuperWhisper.command` and any model copies an earlier package left under `/Library/.../Models`. |
| `Scripts/verify-packaging.sh` | Extended from "check the path list" to "run the cycle": install → assert → uninstall → assert → install again → assert, on scratch roots, plus the keep/wipe assertions and the package payload checks. |
| `packaging/build-pkg.sh` | Refuses to package an app whose embedded `Contents/Resources/uninstall.sh` differs from `packaging/uninstall.sh` (Xcode copies it in at build time, so an app older than the script would run the old, data-destroying path list from the in-app Uninstall action). Reports the package size and payload in its output. No model weights (see §4). |
| `OpenSuperWhisper/UninstallService.swift` | The confirmation sheet promised "Dictation history" and "Settings" as removed. It now lists what is removed and, as plainly, what is kept, and names `--remove-user-data` as the full wipe. |
| `OpenSuperWhisperTests/UninstallServiceTests.swift` | 7 → 10 tests: the scratch install now has the `/Library` model copy and the downloaded models; the old "the support directory is gone" assertion became "recordings, transcriptions and settings survive, models do not", plus `--remove-user-data` and the kept-list assertions. |
| `docs/release_build.md`, `Readme.md` §10, `packaging/conclusion.html`, `packaging/distribution.xml`, `make_release.sh` (cask comment) | What the package contains, what uninstall keeps and removes, that models are downloads. |

The list, which is also what `--help` prints:

* **removed without options** — the app; the uninstall command; model copies an earlier package
  left in `/Library/Application Support/ru.starmel.OpenSuperWhisper/Models`; the models the app
  downloaded; caches, HTTP storage, saved state, application scripts; crash and diagnostic
  reports named after the app; the installer receipt.
* **kept without options** — the recordings, the transcriptions database and
  `~/Library/Preferences/ru.starmel.OpenSuperWhisper.plist`.
* **removed only by `--remove-user-data`** — those three, and nothing else.

`~/models`, `/opt/homebrew` and other applications' data are never touched. Every removal goes
through a variable built from `$ROOT`, which the harness asserts from the script's own text.

## 2. The cycle, quoted

`bash Scripts/verify-packaging.sh` (uninstaller contract; no app needed) → **79 checks, exit 0**;
`bash Scripts/verify-packaging.sh --app <app>` (adds the package and the cycle from its real
payload) → **132 checks, exit 0**. Both logs are `/tmp/fm2418x-final-uninstaller.log` and
`/tmp/fm2418x-final-app.log`; the full runs are also in `status.log`.

```
== cycle (scratch install) ==
  ok   install: the app bundle is installed
  ok   install: the uninstall command is installed
  ok   install: the downloaded whisper model is there
  ok   install: the downloaded transform model is there
  ok   install: the recordings are there
  ok   install: the transcriptions database is there
  ok   install: the preferences are there

-- uninstall --
       | OpenSuperWhisper has been removed.
       | Removed: …/install/Applications/OpenSuperWhisper.app
       | Removed: …/install/Library/Application Support/ru.starmel.OpenSuperWhisper/Models (model copies an earlier package installed for the app, if any)
       | Removed: …/install/Users/tester/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models and …/transform-models (downloaded models)
       | Removed: caches, HTTP storage, saved state and the installer receipt
       | Kept: …/install/Users/tester/Library/Application Support/ru.starmel.OpenSuperWhisper (recordings, transcriptions and settings)
       |       run this again with --remove-user-data to remove those too.
  ok   uninstall exits 0
  ok   uninstall: the app bundle is gone
  ok   uninstall: the uninstall command is gone
  ok   uninstall: the downloaded whisper model is gone
  ok   uninstall: the downloaded transform model is gone
  ok   uninstall: the caches are gone
  ok   uninstall: the HTTP storage is gone
  ok   uninstall: the saved application state is gone
  ok   uninstall: the application scripts directory is gone
  ok   uninstall: the recordings survive          <-- the 87 recordings' case
  ok   uninstall: the transcriptions database survives
  ok   uninstall: the preferences survive
  ok   uninstall: ~/models is untouched
  ok   uninstall: another application's data is untouched
  ok   the uninstaller says in its output what it kept

-- install again --
  ok   reinstall: the app bundle is installed
  ok   reinstall: the uninstall command is installed
  ok   reinstall: the recordings are there       <-- found again after the uninstall
  ok   reinstall: the transcriptions database is there
  ok   reinstall: the preferences are there
```

Idempotence, including the two cases that broke today:

```
== idempotence ==
  ok   uninstalling twice exits 0
  ok   uninstalling twice says nothing (--quiet)
  ok   uninstalling twice still reports success
  ok   twice: the recordings survive
  ok   uninstalling with the app already gone exits 0
  ok   and still clears the app's own paths
  ok   app gone: the recordings survive
  ok   uninstalling a machine with an earlier package's model copy exits 0
  ok   the model copy an earlier package left under /Library is gone
  ok   leftover models: the recordings survive
  ok   reinstalling over a previous install leaves a complete app again
  ok   and something survived the uninstall to be found again
```

The full wipe is the only thing that takes the data:

```
== --remove-user-data (the only thing that takes the recordings) ==
       | Removed: …/wipe/Users/tester/Library/Application Support/ru.starmel.OpenSuperWhisper (recordings, transcriptions and settings)
       | Removed: …/wipe/Users/tester/Library/Preferences/ru.starmel.OpenSuperWhisper.plist
  ok   --remove-user-data exits 0
  ok   wipe: the app bundle is gone
  ok   wipe: the app support directory is gone
  ok   wipe: the preferences are gone
  ok   wipe: ~/models is still untouched
  ok   wipe: another application's data is still untouched
  ok   the uninstaller says it removed the recordings, transcriptions and settings
  ok   and does not claim to have kept them
  ok   a wiped uninstall is idempotent too
```

Script surface (`--help` is the captain's "say exactly what each does"):

```
== script surface ==
  ok   --help exits 0
  ok   --help documents --remove-user-data
  ok   --help says what is kept without any option
  ok   --help says what is removed without any option
  ok   an unknown argument exits 2
  ok   and says which argument
  ok   the uninstaller never removes anything under /opt/homebrew or ~/models
  ok   the uninstaller never removes the filesystem root
  ok   the uninstaller supports the scratch-root test hook
  ok   every rm target is a quoted root-relative variable
```

The cycle run a second time against a package's **own extracted payload** (same assertions, plus
the app and command coming from the `.pkg` itself) also passes — see
`== cycle (from the package payload) ==` in `/tmp/fm2418x-final-app.log`, and:

```
-- install again (from the package payload) --
  ok   reinstall: the app bundle is back
  ok   reinstall: the uninstall command is back
  ok   reinstall: the recordings from before are still there
  ok   reinstall: the transcriptions database from before is still there
  ok   reinstall: the settings from before are still there
ALL CHECKS PASSED (checks: 132)
```

## 3. The package

Built on this machine, unsigned:

```
$ bash packaging/build-pkg.sh --app <app> --out …/OpenSuperWhisper-0.1.0-payload-proof.pkg
==> Payload
    App: OpenSuperWhisper.app (107M)
    Uninstall command: packaging/uninstall.sh, byte for byte with …/Contents/Resources/uninstall.sh
    No model weights: the app downloads those itself, on first use.
==> Built …/OpenSuperWhisper-0.1.0-payload-proof.pkg: 88 MB (84M on disk)
Receipt id: ru.starmel.OpenSuperWhisper (this is what the uninstaller forgets)
Models: not in the package (downloaded by the app on first use); uninstall removes them.
```

`pkgutil --payload-files` on that artifact — 137 entries, every one inside the app bundle except
the command, and nothing at all for `/Library` or a home directory:

```
./Applications/Uninstall OpenSuperWhisper.command
./Applications/OpenSuperWhisper.app
$ pkgutil --payload-files … | grep -E '^\./(Library|Users)/'
(no output)
$ shasum -a 256 …/OpenSuperWhisper-0.1.0-payload-proof.pkg
bb3f62aebb6ff02e03ee47c436dd29ac6026e8d27c302661578fb537834559c9
```

Harness payload assertions on a built package (all `ok`): contains the app; contains the
uninstall command; writes nothing into a home directory; carries no model weights; puts nothing
in `/Library`; exactly two entries in `/Applications`; carries the receipt id; ships the
preinstall hook; is under 500 MB (87,533,465 bytes); the shipped command is
`packaging/uninstall.sh` byte for byte and executable; the app inside it carries the same script
byte for byte (the in-app Uninstall action runs that copy); the app carries the default tiny
model; no AppleDouble files on disk; the distribution keeps the arm64/macOS 14 floor, the
conclusion page and the substituted version.

## 4. The direction change: no model payload

The brief first asked for the models to ride in the package; partway through, Main relayed the
captain's decision to keep the download-from-Hugging-Face strategy and not ship weights. I
dropped that work rather than leaving it in the branch:

* **deleted** — the model-payload block in `packaging/build-pkg.sh` (model resolution, the
  pinned size/sha256 checks, the read-only `/Library/.../Models` placement, `--models-dir`,
  `--whisper-model`, `--transform-model`, `--allow-fixture-models`, the `FIXTURE` output);
* **deleted** — the model constants, the sparse-fixture model files, the payload length/digest
  assertions and `--models-dir` in `Scripts/verify-packaging.sh` (replaced by the inverse
  assertions in §3: the payload carries *no* weights and writes nothing to `/Library`);
* **deleted** — the "What the package contains"/"The model files" payload docs and the 2.6 GB
  update-size paragraph in `docs/release_build.md`, the payload text in
  `packaging/conclusion.html` and `packaging/distribution.xml`, the `Readme.md` §10 payload
  sentence, and the `packaging/models/` line I had added to `.gitignore`;
* **deleted** — the scratch model directory (hard links to two files, see the disclosure
  below), and the 2.6 GB package build that was in flight when the change arrived (killed;
  nothing was installed from it and no artifact was kept — the `.pkg` on disk is the 87.5 MB
  one from §3);
* **kept, deliberately** — the uninstaller still removes `/Library/Application Support/
  <bundle id>/Models` if it exists. The bridge package installed weights there, so a machine
  that has it has the files, and leaving a stale GB behind (or letting it shadow a fresh
  download) is not an uninstall. The harness has a scenario for exactly that
  (`the model copy an earlier package left under /Library is gone`), and the sibling's marker
  literal `Library/Application Support/$BUNDLE_ID/Models` is in the script as they asked.
* **superseded** — Main asked for the harness to assert the payload's model digests against the
  pins in `Settings.swift:947` / `TransformModelManager.swift:110`. That requirement is moot now
  that no payload carries models. The pins did not stop mattering, they moved: they are what the
  app verifies at download time, `docs/release_build.md` names them, and the harness asserts the
  inverse (the payload carries no weights at all). `TransformRuntime`'s `verifiedPath(for:)`
  refuses a transform model whose digest does not match, so the pins remain the contract — they
  are simply no longer a packaging concern.
* **decided deliberately: no per-user copy, no postinstall.** The bridge cloned the payload
  weights into the console user's `~/Library` because the *published* app build cannot read
  `/Library`. I did not keep that: it needs a postinstall script running as root that writes
  into a user's home, it stores 2.6 GB per user, and it exists only to work around the older
  build. The sibling's task (`fm-20260925-19`) is what makes it unnecessary, and this package
  contains no weights to clone in the first place.

## 5. Honesty notes, disclosures and what I could not exercise

**Disclosure (standing rule about the captain's commercial app).** Before the rule was issued I
used the file at `/Volumes/home/zenon/Library/Application Support/superwhisper/ggml-large-v3-turbo.bin`
twice: I ran `shasum -a 256` on it (~10:33Z), and at 10:35Z I created a hard link to it in
`fleet/data/fm-20260925-18/scratch/models/ggml-large-v3-turbo.bin` while preparing a real-model
payload build. When the rule arrived I removed the link (the source file's link count is back to
1 and it is untouched), deleted the scratch models directory, and stopped the build that was in
flight: it had not reached `pkgbuild` — the run failed at that point on the already-deleted
models directory (`build-pkg.sh: no ggml-large-v3-turbo.bin in …`), so **no package was ever
built with it**. Nothing in the branch, the docs, the tests or the harness references that
directory or that app; I grepped `packaging/`, `Scripts/`, `docs/`, `Readme.md`,
`make_release.sh`, `notarize_app.sh` for the bundle id and the path and there are no matches.
The fork's tests here need nothing from it: every fixture is synthetic files under a scratch
root, so they pass with that directory absent.

**What a real (root) install still needs — not exercised here, by contract:**

| Step | Why it needs root/authorisation | Where it is proven otherwise |
| --- | --- | --- |
| Installing the package to `/Applications` | `installer` asks for an admin password; passwordless `sudo` is not available | the payload is exercised by expanding the real `.pkg` and installing it into a scratch root |
| Removing the root-owned app with `osascript … with administrator privileges` | same | that branch is `IS_REAL_ROOT`-only and is skipped for any scratch root by construction |
| `pkgutil --forget ru.starmel.OpenSuperWhisper` | receipt lives in the root receipt database | same conditional |
| `defaults delete` + `killall cfprefsd` (only under `--remove-user-data`) | touches the live preference daemon | same conditional; the plist removal itself is tested |
| `tccutil reset All` (`--reset-permissions`) | TCC database | same conditional, pre-existing |
| Quitting a running app (`osascript`/`pkill`) | live app | same conditional |
| The in-app Uninstall action and its sheet | requires launching the app (headless run forbidden) | the Swift side is `xcrun swiftc -parse`-clean; the sheet's promises are asserted against the script by `UninstallServiceTests`; the harness proves the script's behaviour. The suite itself must be run by the validator (`Scripts/dev-run.sh test`) |

**Design decisions worth knowing**

* `--remove-user-data` has **no in-app control**: adding one means another parameter on
  `UninstallService.startUninstall`, whose call sites are in `Settings.swift` — the sibling's
  file. The sheet therefore names the Terminal command instead, and the app's own uninstall
  keeps the data (the captain's requirement).
* The app's transient `${TMPDIR}/temp_recordings` is removed by default: it holds in-progress
  audio buffers, not the recording library, which lives in the Application Support directory.
* `rmdir` (never `rm -rf`) tidies the two `/Library` directories the installer created, so the
  uninstaller can only remove an *empty* directory there.
* **Interface after the direction change** (from `fm-20260925-19`, 10:52Z): the app no longer
  reads `/Library` at all — their shipped-models tier was deleted too, and a fresh install runs
  on the app's own bundled `ggml-tiny.en.bin`, with everything else a Hugging Face download. So
  the `/Library/.../Models` removal in my script is now purely "clean up what the earlier bridge
  package left", the sheet row is mine alone, and the sibling withdrew their request for a
  literal marker (the literal is still there, and their promise test passes). Their resolution
  order: explicit selection → the per-user copy → the bundled tiny model → download.
* `build-pkg.sh` now refuses an app whose embedded `uninstall.sh` is stale — it exits 1 with the
  exact paths and the rebuild command. On this machine that fires for the current Release build
  at `repo/build/Build/Products/Release/OpenSuperWhisper.app` (built 24 Sep 18:30, before this
  change), which is why the payload evidence run uses a copy of it with the current script in
  place (ad-hoc re-signed, scratch only). **A release must be built after the Swift and script
  changes land** — `notarize_app.sh`, which the first mate runs.
* The `Readme.md` §11 sentence "The suite on this tree is **473 tests**" is now stale by the net
  +3 tests in `UninstallServiceTests`; the validating run should re-derive the number.
* `make_release.sh`'s generated cask has `zap trash: [~/Library/Application Support/…]`, which
  is a Homebrew full wipe — it removes the recordings, as `--remove-user-data` does. The comment
  now says so; `brew uninstall` alone still goes through `uninstall quit/pkgutil` and keeps them.

**Evidence inventory**

| Artifact | Content |
| --- | --- |
| `/tmp/fm2418x-final-uninstaller.log` | the 79-check uninstaller/cycle run |
| `/tmp/fm2418x-final-app.log` | the 132-check run including the package and the payload cycle |
| `fleet/data/fm-20260925-18/scratch/OpenSuperWhisper-0.1.0-payload-proof.pkg` | the 87,533,621-byte artifact from §3 (scratch; unsigned, ad-hoc app) |
| `fleet/data/fm-20260925-18/scratch/resigned/OpenSuperWhisper.app` | the local app copy used as `--app` (Release build + current uninstaller resource, ad-hoc re-signed) |
| `fleet/data/fm-20260925-18/status.log` | UTC-stamped log of the steps, including the killed run |
| `fleet/data/fm-20260925-18/report.md` | this file |

**Tested revision** (the runs above were made against these bytes; nothing was edited afterwards
except this report and `status.log`):

```
23bc9c10c4f202bb1e8331b3c7ebe1c96b21e43030dd983db2c94f8aad75e1c8  packaging/uninstall.sh
ffad1945e59686cc0a8f0f288df54db36b7b75640d0951207eb725ba7fa1156a  packaging/build-pkg.sh
b1351eb72bb15f107937dcfc5897fe7bfc49692ebbd377053a23bbbe42f822dd  Scripts/verify-packaging.sh
```
