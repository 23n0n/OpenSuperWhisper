# Remediation round 3 (final hardening) — fm-20260923-01 (OpenSuperWhisper)

Round 2 fixed the blocking reasoning-strip bug (0 critical findings after re-review; suite green).
This round closes the remaining review findings. Touch only the two files named. No behaviour change
to the happy path.

Worktree: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-01`, branch `fm/fm-20260923-01`,
current HEAD `2d592ba`.

## H1 — strip a bare reasoning terminator (robustness)

File: `OpenSuperWhisper/TranslationService.swift`, `stripReasoning(from:)`.

A Qwen3 response can begin with a stray closing tag or contain the end token without a preceding
opener (the `enable_thinking:false` template can prefill the opener). Round-2 pattern 1 only fires
when an opener is present, so such content leaks. Add, after the existing patterns:

- remove the Qwen3 end token anywhere in the string;
- remove a leading/standalone closing tag for each of the three tag families (`think`, `thinking`,
  `reasoning`) when no opener precedes it.

Keep building every tag from Unicode scalars exactly as round 2 does; introduce no literal
angle-bracket tag text. Do not remove text that merely mentions the word thinking.

## H2 — make the test seam race-free

File: `OpenSuperWhisper/TranslationService.swift`.

The round-2 `static var urlSession` is unsynchronized global mutable state (crew-reviewer 🔵). Replace
it with an instance property injected at construction, defaulting to `.shared`:

- `let urlSession: URLSession`
- `init(urlSession: URLSession = .shared) { self.urlSession = urlSession }`
- keep `static let shared = TranslationService()` and use `urlSession` in `transform`.
- remove the mutable static.

Update the tests to build a service instance with the stub session instead of assigning the static.

## H3 — tighten the tests

File: `OpenSuperWhisperTests/TranslationServiceTests.swift`.

- Cancellation test (crew-reviewer 🟡): assert the thrown error is `CancellationError` or
  `URLError` with `.cancelled`; do not swallow any error.
- Add one case per retained pattern: a `<thinking>…</thinking>` block and a `<reasoning>…</reasoning>`
  block are stripped (these lost coverage in round 2).
- Clamp test: assert the upper bound and pass-through too (e.g. 999 → 120, 8 → 8), not only 0 → 1.
- If a test enables translation without installing a stub, it must not hit the real network:
  default the service's session to an always-failing stub in `setUp`, and assert the production
  default (`.shared`) separately.
- Keep the round-2 UserDefaults isolation.

## Definition of done

- `./run.sh build` exits 0 (`Building successful!`).
- All `TranslationServiceTests` pass.
- Only `OpenSuperWhisper/TranslationService.swift` and
  `OpenSuperWhisperTests/TranslationServiceTests.swift` changed since `2d592ba`.
- Committed on `fm/fm-20260923-01`; `git status` clean.

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

Report the new HEAD sha and decisive test output. Never claim success you did not verify.
