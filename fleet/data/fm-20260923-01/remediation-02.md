# Remediation round 2 — fm-20260923-01 (OpenSuperWhisper)

Crew returned a green build and 16/16 tests, but first-mate review found a blocking bug: the
literal reasoning tag in the round-1 brief was corrupted (its angle brackets were stripped), and
both the production regex and the tests use that corrupted tagless form. So the strip never fires,
and a fallback pattern can truncate legitimate output. Fix the following on the SAME worktree and
branch. Touch only the two files named. Do not rebuild anything else.

Worktree: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-01`, branch `fm/fm-20260923-01`.

## R1 (blocking) — correct the reasoning-strip patterns

File: `OpenSuperWhisper/TranslationService.swift`, `stripReasoning(from:)`.

- The real Qwen3 opening tag is the three-character sequence: `U+003C` + `think` + `U+003E`.
  The closing tag is `U+003C` + `/think` + `U+003E`.
- Build both from Unicode scalars so the source never needs literal angle brackets, e.g.:
  `let openTag = "\u{3C}think\u{3E}"` and `let closeTag = "\u{3C}/think\u{3E}"`.
  Keep the existing Qwen3 end token, which was already correct:
  `"<\u{FF5C}end\u{2581}of\u{2581}thinking\u{FF5C}>"`.
- Patterns required:
  1. `openTag ... <Qwen3 end token>` (lazy, dot-matches-newline) → removed;
  2. `openTag ... closeTag` (lazy, dot-matches-newline) → removed;
  3. unterminated trailing `openTag ...` to end of string → removed.
- DELETE the pattern that matches a bare space followed by the word `thinking` (no tag). It can
  truncate legitimate translations.
- Keep ASCII `<thinking>` and `<reasoning>` handling, but build those tags from scalars too.
- Acceptance: `parseContent` on a response whose content is
  `openTag + "internal reasoning" + <Qwen3 end token> + "Visible English."` returns exactly
  `Visible English.`. And a response whose visible text merely contains the word `thinking`
  (no tags) is returned unchanged.

## R2 (blocking) — tests must use the real tag and be hermetic

File: `OpenSuperWhisperTests/TranslationServiceTests.swift`.

- Define ONE shared constant for the real opening tag and one for the Qwen3 end token, built the
  same scalar way, and use them in every reasoning test (round-1 tests used the corrupted tagless
  form, so they proved nothing).
- Add an assertion that content containing the word `thinking` with no tags is returned unchanged
  (guards against over-truncation).
- Replace the real-socket fallback test (endpoint `http://127.0.0.1:1/...`) with a `URLProtocol`
  stub that fails the request. Assert both (a) `transformIfEnabled` returns the raw input, and
  (b) the request was actually attempted (stub recorded a call). The current test cannot
  distinguish a real attempt-failure from a no-op path and is non-hermetic.
- Isolate `UserDefaults`: the suite must not write the real `UserDefaults.standard`. Use a
  dedicated `UserDefaults(suiteName:)` (or save/reset every preference the suite touches in
  `setUp`/`tearDown`) so a crash mid-test cannot leave the installed app misconfigured.
- Add missing coverage:
  - non-2xx response (e.g. 500) throws `httpError`;
  - the successful translation/parse path;
  - task cancellation;
  - the ordering contract: a transformed result receives the trailing space from
    `IndicatorWindow.applyPostProcessing` (assert directly on that function).

## R3 (small) — validate/clamp inputs

File: `OpenSuperWhisper/TranslationService.swift`, `transform(_:)`.

- Clamp the timeout: `request.timeoutInterval = max(1, min(prefs.transformTimeout, 120))`
  (a 0/negative value from Settings currently makes every request fail instantly).
- Trim the endpoint before parsing:
  `URL(string: prefs.transformEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))`.

## R4 (small) — surface swallowed failures

File: `OpenSuperWhisper/TranslationService.swift`, `transformIfEnabled(_:)`.

- In the `catch`, log the error (`os_log` default category, or `print`) before returning the raw
  text, so a down/misconfigured endpoint is distinguishable from translation being disabled.
  Still return the raw text (fallback contract unchanged).

## Out of scope (report only; do NOT change)

- Cancel issued while the transform is awaited deletes an already-saved recording (the cancel
  window widened from ~0 to up to the timeout). This is a product decision — the first mate
  escalates it to the captain.
- ATS/`NSExceptionDomains` for non-loopback HTTP endpoints. v1 stays on loopback.

## Definition of done

Same as round 1, on the same branch `fm/fm-20260923-01`:

- `./run.sh build` exits 0 (`Building successful!`) in the worktree.
- All `TranslationServiceTests` pass (the new ones included).
- Only `OpenSuperWhisper/TranslationService.swift` and
  `OpenSuperWhisperTests/TranslationServiceTests.swift` changed since the round-1 HEAD `8e6ed8c`.
- Committed with a conventional message. `git status` clean.

Build/test env:

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="/Volumes/home/zenon/.gem/ruby/2.6.0/bin:$PATH"
```

```
xcodebuild test -scheme OpenSuperWhisper -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  -clonedSourcePackagesDirPath SourcePackages \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:OpenSuperWhisperTests/TranslationServiceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

Report the new HEAD sha and the decisive test output lines. Never claim success you did not verify.
