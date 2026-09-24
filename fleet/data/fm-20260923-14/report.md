# fm-20260923-14 — OpenSuperWhisper: every user-affecting preference and behaviour, and whether the UI shows it

Read-only audit. No branch, no commit, no file under `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`
(or any worktree) was modified. Deliverable: this report.

- **Repo state audited:** primary checkout `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`, tip `550d9d1`
  (`fix(dev-sign): unlock the dev keychain instead of failing the build`), working tree clean at read time.
- **Running app checked:** `build/Build/Products/Debug/OpenSuperWhisper.app`, executable mtime
  `2026-09-23 19:25:56`, 73.1 MB, contains `uninstall.sh` and `ggml-silero-v5.1.2.bin` in `Contents/Resources`.
- **Paths below are relative to the repo root.**

## 0. Method, and two corrections to the dispatch context

1. Enumerated every stored preference: all keys are declared as `@UserDefault` / `@OptionalUserDefault`
   property wrappers in `OpenSuperWhisper/Utils/AppPreferences.swift`; a whole-repo scan for `forKey:`
   string literals found no other preference keys (the two hits outside that file are Core Animation
   `forKey:` animation names in `Indicator/IndicatorWindowManager.swift:151,153`, not defaults).
2. Read every UI surface: `Settings.swift` (four-tab sheet, 2253 lines), `ContentView.swift` (main window),
   `Onboarding/OnboardingView.swift`, `OpenSuperWhisperApp.swift` (status-bar menu), `Indicator/IndicatorWindow.swift`
   (recording indicator), `UninstallService.swift`.
3. Read the behaviour files that decide what a preference does: `IndicatorWindow.swift` (inject path),
   `Utils/KeyboardSimulator.swift`, `Utils/ClipboardUtil.swift`, `TranslationService.swift`,
   `TransformModelManager.swift`, `WhisperModelManager.swift`, `TranscriptionService.swift`,
   `TranscriptionQueue.swift`, `Engines/WhisperEngine.swift`, `Utils/LanguageDetector.swift`,
   `Utils/LanguageUtil.swift`, `ShortcutManager.swift`, `AudioRecorder.swift`, `PermissionsManager.swift`.
4. Cross-checked the **built** app's executable for the new UI strings (a binary substring probe, listed in §4),
   so "the feature is in the running build" is verified, not assumed.

Two corrections to the facts I was dispatched with:

- **Settings is not opened from the menu bar.** The only poster of `.openSettings` is the SwiftUI *app-menu*
  command "Settings…" (⌘,) at `OpenSuperWhisper/OpenSuperWhisperApp.swift:46`; `ContentView` consumes it at
  `ContentView.swift:683`. The **status-bar menu contains no Settings item at all** — its items are
  `OpenSuperWhisper`, `Language`▸, `Copy` (hidden until a transcription exists), `Microphone`▸,
  `Uninstall OpenSuperWhisper…`, `Quit` (`OpenSuperWhisperApp.swift:250-342`). In-window, Settings opens only
  from the gear button (`ContentView.swift:601-612`). When the app launches hidden
  (`startHiddenInMenuBar`), it runs as `.accessory`, so there is no app menu bar and ⌘, is unreachable until
  the main window is opened.
- The launch brief at `data/fm-20260923-14/launch-brief.md` still contains the unfilled `{TASK}` /
  `{FIRSTMATE_SPEC}` placeholders, so completeness against the captain's own list rests on my dispatch context.

`fm-20260923-12` reported mid-audit (IRC) that it is deleting `ContentView`'s
`PermissionsView`/`PermissionRow` and replacing them with a non-blocking inline permission-notice stack,
touching `OnboardingView` (skip button), `run.sh` and `Scripts/dev-run.sh`. **Those edits were not in my
snapshot**: at read time `PermissionsView`/`PermissionRow` still exist at `ContentView.swift:697-762`, and
`git status --porcelain` was empty both before and after the audit (so fm-12 is editing a separate worktree,
not the primary checkout). Permission/onboarding rows below describe tip `550d9d1` as read, with fm-12's
reported direction noted in the ownership column.

---

## 1. Full inventory — every user-affecting preference

Legend for **In UI?** — `yes` = the user can see and change it; `state only` = visible but not changeable;
`no` = not reachable anywhere in the UI; `internal` = plumbing that is not meant to be user-facing.

Preferences are declared in `OpenSuperWhisper/Utils/AppPreferences.swift` unless stated otherwise; the
"file:line" column gives the declaration line, the "where" column the exact UI site.

### 1.1 Trigger and recording

| # | Key / API | file:line | Default | In UI? | Where (tab → section → label) / why not |
|---|---|---|---|---|---|
| 1 | Trigger mode (derived, not stored) | `Settings.swift:1618-1641` (derivation `:1602-1606`) | Key Combination | yes | **Shortcuts → Recording Trigger** → segmented `Key Combination` / `Single Modifier Key` / `Mouse Button` |
| 2 | `KeyboardShortcuts.Name.toggleRecord` (library-stored) | `ShortcutManager.swift:11` | ⌥ + ` `` ` | yes | Shortcuts → Recording Trigger → `Shortcut` recorder (`Settings.swift:1709-1714`) |
| 3 | `KeyboardShortcuts.Name.escape` | `ShortcutManager.swift:12`; disabled at setup `ShortcutManager.swift:88`; enabled per session `IndicatorWindowManager.swift:19`, disabled `:279` | Esc, live only during a recording session | **state only** | Only prose: Shortcuts → Recording Behavior → "Skip the double-Esc confirmation…" (`Settings.swift:1769`). The binding itself is never listed; the recorder shows only the record toggle |
| 4 | `modifierOnlyHotkey` | `AppPreferences.swift:205` | `"none"` | yes | Shortcuts → Recording Trigger → Single Modifier Key → `Modifier Key` picker (`Settings.swift:1649-1663`) |
| 5 | `lastModifierOnlyHotkey` | `AppPreferences.swift:210` | `"leftCommand"` | internal | No control (remembers the picker value when the mode is toggled away and back; visible only as the picker's retained selection) |
| 6 | `mouseButtonHotkey` | `AppPreferences.swift:213` | `"none"` | yes | Shortcuts → Recording Trigger → Mouse Button → `Mouse Button` picker (`Settings.swift:1679-1693`); names: `Button 3 (Middle)`, `Button 4 (Back)`, `Button 5 (Forward)`, `Button 6` (`MouseButtonMonitor.swift:19-27`) |
| 7 | `holdToRecord` | `AppPreferences.swift:217` | `true` | yes | Shortcuts → Recording Behavior → `Hold to Record` ("Hold the shortcut to record, release to stop") |
| 8 | Hold arming threshold `0.3 s` | `ShortcutManager.swift:23,167` | 0.3 s | **no** | Hard-coded; not mentioned anywhere in the UI |
| 9 | `playSoundOnRecordStart` | `AppPreferences.swift:193` | `false` | yes | Shortcuts → Recording Behavior → `Play sound when recording starts` |
| 10 | `escCancelWithoutConfirmation` | `AppPreferences.swift:266` | `false` | yes | Shortcuts → Recording Behavior → `Cancel without confirmation` |
| 11 | Esc cancel rule: ≥10 s recording ⇒ second Esc within 5 s | `IndicatorWindow.swift:23-24,167-185` | confirmation required | state only | Indicator shows `Press Esc to cancel` + 5 s orange bar (`IndicatorWindow.swift:540-544,478-500`, bar mounted `:603-606`); thresholds themselves not surfaced |
| 12 | Minimum recording length `1.0 s` | `AudioRecorder.swift:15,257,298` | 1.0 s | **no** | Hard-coded: shorter recordings are deleted and the audio dropped, with no message (see G-15) |
| 13 | Stop tail `0.25 s` | `AudioRecorder.swift:19,243` | 0.25 s | **no** | Hard-coded capture tail after stop |
| 14 | Temporary-file max age `24 h` | `AudioRecorder.swift:16,50` | 24 h | internal | Cleanup only |
| 15 | `selectedMicrophoneData` | `AppPreferences.swift:202` | unset (system default) | yes | Main window → mic button popover (`ContentView.swift:1202-1270`) **and** status-bar menu → `Microphone`▸ (`OpenSuperWhisperApp.swift:278-330`) |
| 16 | Mic permission state (`AVCaptureDevice.authorizationStatus`) | `PermissionsManager.swift:124-128` | — | state only | Main window `PermissionsView` (`ContentView.swift:697-726`), shown **instead of** the whole content when either permission is missing; nothing in the Settings sheet (see G-03) |
| 17 | Accessibility / injection trust (`AXIsProcessTrusted()`) | `PermissionsManager.swift:31,129` | — | state only (conditional) | Settings → Shortcuts → trigger-mode warning, **only** in `Single Modifier Key` and `Mouse Button` modes (`Settings.swift:1667-1675,1697-1705`, renderer `:1585-1601`). Nothing in the default `Key Combination` mode (see G-02) |

### 1.2 Delivery and output of the transcript

| # | Key / API | file:line | Default | In UI? | Where / why not |
|---|---|---|---|---|---|
| 18 | `autoPasteTranscription` | `AppPreferences.swift:227` | `true` | yes | **Transcription → Clipboard & Paste** → `Auto-paste Transcription` ("Automatically paste into the focused app") |
| 19 | Delivery mechanism: synthetic `CGEvent` keystrokes | `IndicatorWindow.swift:338-355`, `Utils/KeyboardSimulator.swift:80-146` | always keystrokes when #18 is on | **no** | No control and no wording: the label says "paste", the mechanism is typing (display-only list, D-01) |
| 20 | `autoCopyToClipboard` | `AppPreferences.swift:224` | `false` | yes | Transcription → Clipboard & Paste → `Copy to Clipboard` ("Keep transcription in clipboard after recording") |
| 21 | Both off ⇒ dictation only lands in history | `IndicatorWindow.swift:356-367` | — | no | `// If both are false, do nothing` — no UI statement of this outcome |
| 22 | `addSpaceAfterSentence` | `AppPreferences.swift:220` | `true` | yes | Transcription → Output Options → `Add Space After Sentence` |
| 23 | `showTimestamps` | `AppPreferences.swift:172` | `false` | yes | Transcription → Output Options → `Show Timestamps` |
| 24 | Accessibility-missing injection failure alert | `IndicatorWindow.swift:375-392` | — | state only (runtime) | Modal `AppErrorCenter` alert "Transcription was not typed", plus a live re-check via `.accessibilityPermissionNeededForInjection` (`PermissionsManager.swift:93-100`) |

### 1.3 Engine, model and language

| # | Key / API | file:line | Default | In UI? | Where / why not |
|---|---|---|---|---|---|
| 25 | `selectedEngine` | `AppPreferences.swift:138` | `"whisper"` | yes | **Model → Speech Recognition Engine** → `Engine` segmented picker `Parakeet` / `Whisper` (`Settings.swift:952-961`) |
| 26 | `selectedWhisperModelPath` | `AppPreferences.swift:156` | unset ⇒ `availableModels.first` (`Settings.swift:434`), else bundled `ggml-tiny.en` (`WhisperModelManager.swift:120-133`) | state only | Model tab shows a green checkmark only on a **catalogue** row (`ModelDownloadItemView.isSelected`, `Settings.swift:2195-2199`); a hand-placed model shows no selection anywhere (see G-05) |
| 27 | `selectedModelPath` (legacy alias) | `AppPreferences.swift:142-153` | — | internal | Computed forwarding to `selectedWhisperModelPath` |
| 28 | `fluidAudioModelVersion` | `AppPreferences.swift:159` | `"v3"` | yes | Model → Parakeet Model → per-row `Select` / tap (`FluidAudioModelDownloadItemView`, `Settings.swift:1960-1970`) |
| 29 | Whisper model download / cancel / progress | `WhisperModelManager.swift:157-260`, `Settings.swift:2143-2240` | — | yes | Model → Download Models → `Download` / `Cancel` / progress bar, size, Hugging Face link |
| 30 | Parakeet model download / cancel / progress | `Settings.swift:1916-2000` | — | yes | Model → Parakeet Model → `Download` / `Cancel` / progress |
| 31 | Speech-model **removal** | — (no code) | — | **no** | No remove/delete control for Whisper or Parakeet models anywhere (see G-04). Only the transform model has `Remove` (`Settings.swift:1258`) |
| 32 | Speech-model **verification** | `WhisperModelManager.swift:27-35` (HTTP status only) | — | **no** | No checksum, no size check, no verify state for speech models (see G-06) |
| 33 | Models directory path + reveal | `Settings.swift:986-1006` (Whisper), `:1026-1049` (Parakeet) | — | yes | Model tab → `Models Directory:` + `Open Folder` |
| 34 | Installed models on disk (`getAvailableModels()`) | `WhisperModelManager.swift:136-147`, loaded `Settings.swift:432` | — | **no** | `availableModels` is never rendered; the Model tab lists only the 4 catalogue entries (`Settings.swift:725-760`) (see G-05) |
| 35 | Silent model fallback when the selected file is gone | `WhisperModelManager.swift:120-133` | — | **no** | `print` only; the user is never told the model changed (see G-07) |
| 36 | Bundled default model copied on first launch | `WhisperModelManager.swift:96-118` | `ggml-tiny.en.bin` | **no** | Silent bootstrap |
| 37 | `whisperLanguage` | `AppPreferences.swift:165` | `"en"` (onboarding overwrites it with the system language, `OnboardingView.swift:57-59`) | yes | **Transcription → Language Settings** → `Transcription Language` picker (`Settings.swift:1069-1082`) **and** status-bar menu → `Language`▸ (`OpenSuperWhisperApp.swift:445-465`) |
| 38 | Auto-detect | `LanguageUtil.swift:5-7,16` (`"auto"`), engine use `WhisperEngine.swift:340-361,394` | not the default (`"en"`) | yes | Same picker, entry `Auto-detect`; the requirement (multilingual model) is stated only in the caption at `Settings.swift:1300` (see G-14) |
| 39 | Engine-reported per-utterance language | `TranscriptionService.swift:17-23,339`, `WhisperEngine.swift:335-361` | — | **state only, in prose** | Feeds only the transform gate (`IndicatorWindow.swift:291`); the detected language of a dictation is never displayed (see G-08) |
| 40 | `qwen3Variant` | `AppPreferences.swift:162` | `"f32"` | **no** | Orphan: declared, never read anywhere in the app or tests, no UI (see G-11) |
| 41 | `useAsianAutocorrect` | `AppPreferences.swift:199` | `true` | yes (conditional) | Transcription → Language Settings → `Use Asian Autocorrect`, rendered only when the language is zh/ja/ko (`Settings.swift:1086-1094`); also Onboarding (`OnboardingView.swift:400-406`) |
| 42 | Parakeet language support set | `LanguageUtil.swift:11-19` | v2 English-only / v3 25 languages | state only | The picker contents change silently with the engine/model; nothing says why languages vanished |

### 1.4 Translation and tone (the new capabilities)

| # | Key / API | file:line | Default | In UI? | Where / why not |
|---|---|---|---|---|---|
| 43 | `translateEnabled` | `AppPreferences.swift:231` | `false` | yes | **Transcription → Translation & Tone** → `Translate Polish to English` |
| 44 | `toneEnabled` | `AppPreferences.swift:239` | `false` | yes | Transcription → Translation & Tone → `Apply tone` |
| 45 | `transformToneMode` | `AppPreferences.swift:242` | `neutral` | yes | Transcription → Translation & Tone → `Tone` picker (`Neutral`/`Formal`/`Casual`, `TranslationService.swift:4-8`), disabled while tone is off |
| 46 | Target language | — (does not exist) | fixed Polish→English | **no** | No key, no control, and the binary contains no "target language" string. In flight; owned by `fm-20260923-13` (see G-09) |
| 47 | Transform model id | `AppPreferences.swift:260` | `qwen2.5-1.5b-instruct-q4_k_m` (`TransformModelManager.swift:59`) | yes | Advanced → Transform Backend → `Model id` field (enabled only with the external override) **and** shown read-only as the resolved model in Transcription → Translation & Tone (`Settings.swift:1491-1500`, `1297`) |
| 48 | Transform model state + download / cancel / remove | `Settings.swift:360-440`, `TransformModelManager.swift:222-320` | not downloaded | yes | Transcription → Translation & Tone → `Transform model` with `Download model` / `Cancel` / `Remove`, progress, "Installed — <size>", "Until this model is downloaded, dictation is pasted unchanged." |
| 49 | Transform model **verification** (pinned SHA-256) | `TransformModelManager.swift:150-176` | verified silently on use | **state only** | `Installed — <size>` is the only state; `verifyInstalledModel(_:)` has no UI caller (see G-06) |
| 50 | Transform backend: in-process llama.cpp (default) | `TranslationService.swift:210-238`, `Llama/TransformRuntime.swift` | in-process | state only | Prose only: "Runs inside the app: …" (`Settings.swift:1295`) and the Advanced note (`:1514`) |
| 51 | `transformUseExternalEndpoint` | `AppPreferences.swift:254` | `false` | yes | Advanced → Transform Backend → `Use an external endpoint` |
| 52 | `transformEndpoint` | `AppPreferences.swift:257` | `http://127.0.0.1:1919/v1/chat/completions` | yes | Advanced → Transform Backend → `Endpoint` |
| 53 | `transformTimeout` | `AppPreferences.swift:263` | `8.0 s` | yes | Advanced → Transform Backend → `Timeout (seconds):` |
| 54 | Raw-transcript history rule | `IndicatorWindow.swift:275-296` (recording saved before the transform), `TranscriptionQueue.swift:262-297` (never transforms) | — | **state only, in prose** | One caption at `Settings.swift:1300`; the Readme table at `Readme.md:166-183` documents it properly, the UI does not (display-only list D-02) |
| 55 | Transform outcome per dictation (raw / translated / toned, and which policy fired) | `TranslationService.swift:88-110,166-208` | raw | **no** | Nothing recorded or displayed; the user infers it from the pasted text (see G-08) |

### 1.5 Decoding parameters and advanced

| # | Key / API | file:line | Default | In UI? | Where / why not |
|---|---|---|---|---|---|
| 56 | `useBeamSearch` | `AppPreferences.swift:184` | `false` | yes | **Advanced → Decoding Strategy** → `Use Beam Search` |
| 57 | `beamSize` | `AppPreferences.swift:187` | `5` | yes (conditional) | Advanced → Decoding Strategy → `Beam Size:` stepper 1…10, shown only when beam search is on |
| 58 | `temperature` | `AppPreferences.swift:175` | `0.0` | yes | Advanced → Model Parameters → `Temperature:` slider 0…1 step 0.1 (`Settings.swift:1429-1438`) |
| 59 | `noSpeechThreshold` | `AppPreferences.swift:178` | `0.6` | yes | Advanced → Model Parameters → `No Speech Threshold:` slider (`Settings.swift:1443-1452`); applied at `WhisperEngine.swift:397` |
| 60 | `initialPrompt` | `AppPreferences.swift:181` | `""` | yes | Transcription → `Initial Prompt` `TextEditor` |
| 61 | `suppressBlankAudio` | `AppPreferences.swift:169` | `true` | yes | Transcription → Output Options → `Suppress Blank Audio` |
| 62 | VAD gate (Silero) always on | `WhisperEngine.swift:66-67,201` | always on | **no** | Non-speech audio never reaches whisper; not configurable and not shown (display-only list D-04) |
| 63 | `debugMode` | `AppPreferences.swift:190` | `false` | yes, **inert** | Advanced → Debug Options → `Debug Mode`; the preference is written and never read (the native `debug_mode` is a separate, always-default parameter — `WhisperFullParams.swift:27,86`, `Whis.swift:534`) (see G-11) |
| 64 | `startHiddenInMenuBar` | `AppPreferences.swift:269` | `false` | yes | **Shortcuts → Application** → `Start hidden in menu bar` |
| 65 | `hasCompletedOnboarding` | `AppPreferences.swift:196` | `false` | **no** | Gates `OnboardingView` vs `ContentView` (`OpenSuperWhisperApp.swift:26-32`); no UI to reset it (only a DEBUG `dev_config.json`, `Utils/DevConfig.swift`) (see G-12) |
| 66 | `prefsSchemaVersion` / `prefsSchemaVersionKey` | `AppPreferences.swift:30-31`, migration `:44-83` | `1` | internal | One-time migration of model paths and transform model id |
| 67 | Free-space precondition for downloads `10 GB` | `Utils/DiskSpaceUtil.swift:10` | 10 GB | state only on failure | Surfaced only as the error text in the download alert / transform error line |
| 68 | Disk usage of recordings | `Settings.swift:2028-2036`, `RecordingStore.recordingsDiskUsage()` | — | yes | **Transcription → History Storage** → `Recordings on disk:` |
| 69 | `autoDeleteRecordingsEnabled` | `AppPreferences.swift:272` | `false` | yes | Transcription → History Storage → `Auto-delete old recordings` |
| 70 | `autoDeleteRecordingsAfterDays` | `AppPreferences.swift:275` | `30` | yes | Transcription → History Storage → `Delete recordings older than` (1/7/14/30/90 days), with a destructive confirmation naming the count and oldest date |
| 71 | Retention sweep schedule (launch + every 24 h) | `OpenSuperWhisperApp.swift:127-146` | 24 h | **no** | Hard-coded; not stated in the UI |
| 72 | Transcriptions directory path + reveal | `Settings.swift:1339-1360` | — | yes | Transcription → `Transcriptions Directory` + `Open Folder` |
| 73 | History list, search, play, copy, regenerate, delete | `ContentView.swift:309-695`, `RecordingRow` `:764-1060` | — | yes | Main window |

### 1.6 Uninstall and app-level actions

| # | Key / API | file:line | Default | In UI? | Where / why not |
|---|---|---|---|---|---|
| 74 | Uninstall action | `UninstallService.swift:104-146`, UI `Settings.swift:1526-1550` | — | yes | **Advanced → Uninstall** → `Uninstall OpenSuperWhisper…` → confirmation sheet listing every removed item + `Left alone:` note |
| 75 | Uninstall from the status-bar menu | `OpenSuperWhisperApp.swift:333-340,396-421` | — | yes | Status-bar `Uninstall OpenSuperWhisper…` → critical `NSAlert` with the same removal list |
| 76 | Reset permissions on uninstall | `UninstallService.swift:169-170`, script arg `--reset-permissions` | `false` | yes (partial) | Toggle `Also reset microphone and accessibility permissions` **only** in the Settings sheet; the menu-bar alert has no such option and calls `startUninstall(resetPermissions: false)` (see G-17) |
| 77 | Uninstaller payload / idempotence | `UninstallService.swift:46-92`, `packaging/uninstall.sh` | — | state only | Listing in the sheet is bound to script markers by `UninstallServiceTests` |
| 78 | Last-transcription copy in the menu bar | `OpenSuperWhisperApp.swift:255-274,346-392` | hidden until one exists | yes | Status-bar `Copy` with a 6-word preview |
| 79 | Drag-and-drop / `openFile` transcription | `ContentView.swift` `.fileDropHandler()`, `OpenSuperWhisperApp.swift:148-196` | — | state only | Hint text "Drop audio file here to transcribe" (`ContentView.swift:557`) |
| 80 | Queue behaviour when the engine is busy | `IndicatorWindow.swift:209-222`, `TranscriptionQueue.swift` | — | state only | Indicator shows `Processing…` (`IndicatorWindow.swift:565-574`); the fact that the dictation is queued rather than lost is not stated |

---

## 2. Judgement per entry

A feature counts as **shown** only if the user can see and change it, or see its state. Applied to §1:

**Shown (control or state visible) — 51 of 80 entries:** #1, #2, #4, #6–#11, #15–#18, #20, #22–#25, #28–#30, #33, #37, #38, #41–#45, #47, #48, #50–#53, #56–#61, #63, #64, #68–#70, #72–#75, #77, #78.
Within that set, #11, #16, #17, #24, #42, #50, #77 are **state only** (visible, not changeable); #16 and #17 are visible only in the main window, never in the Settings sheet, which is exactly G-02/G-03.

**Internal plumbing, not user-facing by design — 4 entries:** #5, #14, #27, #66.

**Counted as missing (not shown) — 25 entries, the gap source:** #3 (binding), #8 (hold threshold), #12, #13, #19, #21, #26 (current model identity), #31, #32, #34, #35, #36, #39, #40, #46, #49, #54 (only prose), #55, #62, #65, #67 (only on failure), #71, #76 (partial), #79, #80.

The 17 gaps of §3 are not one-per-row: several rows share one gap (e.g. #31/#32/#34/#35/#36 land in G-04…G-07), and three gaps (G-01, G-10, G-17) come from surfaces rather than preference rows.

### 2.1 Display-only list — hard-coded behaviour the captain demanded, no control wanted

These are deliberate, code-enforced behaviours that genuinely have no preference. They belong in the UI as
**statements of state**, not as controls. None of them is in the missing-control list of §3 except where the
state itself is invisible.

| ID | Behaviour | Evidence | UI state today |
|---|---|---|---|
| D-01 | Delivered text is **always synthetic keystrokes** (`CGEvent` + `keyboardSetUnicodeString`), never a pasteboard paste; 20 UTF-16 units per event, newline→Return, tab→Tab, modifier flags cleared | `IndicatorWindow.swift:338-355`, `Utils/KeyboardSimulator.swift:80-146` | Label says "Auto-paste… / Automatically paste into the focused app"; the mechanism is unstated. The old pasteboard path is dead app code (`Utils/ClipboardUtil.insertText`/`insertTextAndKeepInClipboard`/`insertTextUsingPasteboard`/`restoreIfUnchanged`/input-source switching have **no** app caller — only tests) |
| D-02 | **History always keeps the raw transcript**; the transform is applied only to the text that is typed/copied, and list/queued transcriptions are never transformed | `IndicatorWindow.swift:275-296` (recording persisted, then `transformTextOperation`), `TranscriptionQueue.swift:262-297` | One caption, `Settings.swift:1300`; the Readme table is authoritative |
| D-03 | **Fully local inference by default**: llama.cpp linked into the process, weights in app-owned storage; with the override off nothing listens on a port | `TranslationService.swift:210-238`, `Llama/TransformRuntime.swift`, `app/Contents/Frameworks` | Prose in Transcription and Advanced sections |
| D-04 | Silero VAD gate always on — silence never reaches whisper | `WhisperEngine.swift:66-67,201` | Not stated anywhere |
| D-05 | Empty/no-speech dictation is discarded (temp audio deleted, nothing added to history) | `ContentView.swift:220-228`, `TranscriptionQueue.swift:180-186`, `IndicatorWindow.swift:263-266` | Not stated; nothing appears at all |
| D-06 | Recordings shorter than 1.0 s are deleted silently | `AudioRecorder.swift:15,257,298` | Nothing shown |
| D-07 | Hold-mode arms only after 0.3 s of holding | `ShortcutManager.swift:23,167` | Nothing shown |
| D-08 | Esc cancel needs a second Esc within 5 s for recordings ≥10 s | `IndicatorWindow.swift:23-24,181-199` | Indicator bar + "Press Esc to cancel" prose |
| D-09 | Retention sweep at launch and every 24 h | `OpenSuperWhisperApp.swift:127-146` | Nothing shown |
| D-10 | 10 GB free space required before a model download | `Utils/DiskSpaceUtil.swift:10` | Error text only |
| D-11 | Selecting the Hebrew catalogue model silently switches the language to `he` | `Settings.swift:62-67,753-754` | Visible only as the language picker changing |
| D-12 | Busy engine ⇒ the dictation is queued instead of lost | `IndicatorWindow.swift:209-222` | Indicator `Processing…` |
| D-13 | Bundled `ggml-tiny.en.bin` copied into app storage on first launch | `WhisperModelManager.swift:96-118` | Nothing shown |
| D-14 | The trigger modes that need Accessibility are gated by it and the trigger is rebuilt on grant change | `ShortcutManager.swift:36-42`, `PermissionsManager.swift:93-100` | Stated in the modifier/mouse warnings only |

---

## 3. Ordered gap list

Ordered by impact on the captain's problem ("can't see it ⇒ concludes it doesn't exist"). Owner column:
`fm-12` = owned by `fm-20260923-12`, `fm-13` = owned by `fm-20260923-13`, `—` = unowned.

| # | What is missing | Where it belongs | Label / state to add | Owner |
|---|---|---|---|---|
| G-01 | The status-bar menu has no Settings entry; Settings is reachable only from the main-window gear or the app-menu ⌘, (unavailable when launched hidden) | Status-bar menu, between `Microphone`▸ and `Uninstall` | menu item `Settings…` posting `.openSettings` | — |
| G-02 | Accessibility/injection state is invisible in Settings whenever the trigger is `Key Combination` (the default); the warning exists only for the modifier and mouse modes | Shortcuts → new `Permissions` section | `Accessibility — keystrokes are on/off` + `Open System Settings` | fm-12 for the state (it reports a main-window inline notice, and explicitly **not** a Settings section) ⇒ Settings section unowned |
| G-03 | Microphone permission/state is invisible in Settings entirely (main window only, and only while something is missing) | Shortcuts → same `Permissions` section | `Microphone — granted/blocked` | fm-12 (main window) ⇒ Settings section unowned |
| G-04 | Speech models cannot be removed: `Download`/`Select`/`Cancel` exist, no `Remove`; only the transform model can be removed | Model tab → per-row control in `ModelDownloadItemView` and `FluidAudioModelDownloadItemView` | `Remove` (+ size freed) | — |
| G-05 | Models installed on disk but absent from the catalogue are never listed, and a non-catalogue selection produces **no** checkmark — the Model tab can show no current model at all | Model tab → `Installed models` list + `Selected model` line | `Installed models (N)` with path and a selected marker | — |
| G-06 | No visible verification: transform weights verify a pinned SHA-256 only silently; speech downloads are checked for HTTP status only, with no checksum and no verify action | Model tab rows + Transcription → `Transform model` | `Verified ✓ (sha256 …)` / `Verify` action | — |
| G-07 | When the selected model file disappears the app silently falls back to the bundled model (log only) | Model tab → status line | `Selected model was missing — now using ggml-tiny.en.bin` | — |
| G-08 | The transform stage and its decision are invisible: the indicator says only `Transcribing…`; the detected language and whether the paste was raw / translated / toned are never shown or recorded | Indicator (a `Translating… / Toning…` state) + Transcription → `Translation & Tone` | `Last dictation: Polish → translated (neutral)` and/or a per-dictation badge in the history row | fm-13 partially (owns the language control); outcome display unowned |
| G-09 | No target-language control at all: the transform is hard-wired Polish→English and the toggle label says so | Transcription → `Translation & Tone` | `Target language` picker (next to `Translate Polish to English`) | fm-13 (owns) |
| G-10 | The keypress-delivery mechanism is undescribed: "Auto-paste Transcription / Automatically paste into the focused app" never says the text is typed as synthetic keystrokes, that the clipboard is untouched, or that Accessibility is required | Transcription → `Clipboard & Paste` subtitle | "Types the text as keystrokes into the focused app (no clipboard paste); needs Accessibility" | — (fm-12 touches the permission side) |
| G-11 | `Debug Mode` is a visible toggle whose preference nothing reads (no observable effect); `qwen3Variant` is a stored key with neither UI nor reader | Advanced → `Debug Options` (wire it or drop the toggle); drop or expose `qwen3Variant` | `Debug Mode — writes verbose logs to the unified log` | — |
| G-12 | `hasCompletedOnboarding` cannot be reset from the UI (only a DEBUG `dev_config.json`), so the welcome flow cannot be re-shown | Advanced → new `Welcome screen` action | `Show welcome screen again` | — |
| G-13 | The fixed Esc cancel binding is not listed; only prose mentions double-Esc, and the recorder exposes just the record shortcut | Shortcuts → `Recording Behavior` | `Esc — cancel recording (fixed)` | — |
| G-14 | With `Auto-detect` + an English-only model (the bundled `ggml-tiny.en`) language awareness silently does nothing; the picker gives no hint | Transcription → `Language Settings` | warning `Auto-detect needs a multilingual model (e.g. Turbo V3)` | — (adjacent to fm-13) |
| G-15 | Recordings under 1.0 s and no-speech dictations vanish with no message, no history row and no audio | Indicator + main window | `Discarded — too short (min 1 s)` / `No speech detected` | — |
| G-16 | The engine in use and the active model are not surfaced outside the Settings sheet (no status line anywhere) | Model tab header and/or main window | `Whisper · ggml-tiny.en.bin` / `Parakeet v3` | — |
| G-17 | Uninstall from the status-bar menu cannot reset permissions and offers no control for it, while the Settings sheet does | Status-bar uninstall alert, or route it to the sheet | checkbox `Also reset microphone and accessibility permissions` | — |

**Gap count: 17** (G-01…G-17). Ownership tally, stated exactly: **only G-09 is owned outright** (`fm-13`).
G-02 and G-03 have their main-window side covered by `fm-12`, but the Settings-sheet half of each is unowned.
G-08 is half-owned (`fm-13` owns the language control; nobody owns the outcome display). Every other gap —
G-01, G-04, G-05, G-06, G-07, G-10, G-11, G-12, G-13, G-14, G-15, G-16, G-17 — **has no owner at all** (13 of 17).

---

## 4. What I could not determine

1. **No live-UI verification.** The app was not running, and launching the Debug build would have written
   preferences, `Application Support` state and possibly history — outside a read-only audit. No screenshot of
   the Settings sheet was taken. Every "where in the UI" claim is read from the SwiftUI source, and the
   *presence* of the new labels in the running build was verified by substring probe of the executable
   (`Contents/MacOS/OpenSuperWhisper`, 73.1 MB, mtime 2026-09-23 19:25:56), which contains, uniquely:
   `Translate Polish to English`, `Apply tone`, `Transform model`, `Download model`,
   `Uninstall OpenSuperWhisper…`, `Uninstall OpenSuperWhisper?`, `Hold to Record`, `Mouse Button`,
   `Single Modifier Key`, `Auto-paste Transcription`, `Dictation history always keeps the raw transcript`,
   `Language awareness needs a multilingual whisper model`, `Use an external endpoint`, `Transform Backend`,
   `History Storage`, `Auto-delete old recordings`, `Use Asian Autocorrect`, `Start hidden in menu bar`,
   `Cancel without confirmation`, `Press Esc to cancel`, `Transcription was not typed`.
   The same probe found **no** occurrence of `target language` / `targetLanguage`, consistent with §1 #46.
2. **The captain's own list is not fully known to me.** The launch brief's `{TASK}` and `{FIRSTMATE_SPEC}`
   placeholders are unfilled; I worked from the dispatch context (translation switch, tone switch, target
   language, language awareness, keypress delivery, in-process model download/removal, push-to-talk modes,
   hold-to-record, uninstall, permission states, raw-transcript history rule). If the captain listed anything
   else, it is not covered.
3. **`Debug Mode`'s intent.** It is written and never read on any path I found; whether some runtime path
   (unified-log verbosity, launch argument) consumes it from `UserDefaults` outside the Swift sources could not
   be established by static reading.
4. **`fm-12`'s in-flight edits are not in my snapshot.** It reports deleting `ContentView`'s
   `PermissionsView`/`PermissionRow`, adding an inline permission notice stack and live re-check, an onboarding
   skip button, and changes to `run.sh` / `Scripts/dev-run.sh`. My permission and onboarding rows describe tip
   `550d9d1` as read; the Settings-sheet permission gaps (G-02, G-03) are marked with its reported scope.
5. **`fm-13`'s design is unknown to me** (not visible in the live roster). I marked G-09 as its own per the
   dispatch, but I could not read its intent for the target-language control's placement, so the "where it
   belongs" line for G-09 may collide with its plan.
6. **Runtime confirmation that the transform executes in-process** (llama.cpp load, GGUF hash check, latency)
   was not exercised; statically the path is `TranslationService` → `TransformRuntime` → linked `libllama`, with
   the GGUF in app-owned storage (`TransformModelManager.swift:96-104`), and the bundle carries the runtime but
   no transform weights (correct: weights are downloaded).
7. **Whether the packaged `.pkg`/release build matches this Debug build** was not checked
   (`packaging/`, `make_release.sh`, `Scripts/verify-packaging.sh` were outside this audit's scope); the
   captain's running app per the dispatch is the Debug product above, which I verified.
