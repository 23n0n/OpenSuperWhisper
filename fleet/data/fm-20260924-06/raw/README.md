# raw evidence — fm-20260924-06

Run on the delivered worktree (`fm/shortcut-recorder` @ base `ffda358`), macOS 27.0 (26A428), arm64,
Xcode 27A266a. Every command below is a real run; nothing here is reconstructed.

| file | command | what it shows |
|---|---|---|
| `recorder-after.txt` | `TEST_RUNNER_OSW_TEST_EVIDENCE=/tmp/fleet-recorder-after.txt Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/ShortcutRecorderTests` | the whole class green, with the library's own recording notification as the detector: the click through the host reports `[false, true]` and ⌥⇧K is stored and shown; the mode cases report `armed=true` (key combination, nothing stored) and `armed=false` (modifier hotkey) |
| `recorder-without-host.txt` | the same scoped run with the host's `hitTest` temporarily set back to `super.hitTest(point)` (the app's old behaviour), then reverted | `recording=[false, true, false]`, `stored=nil`, `shown=K` — the regression case fails exactly as the captain sees it |
| `suite.log` | `rm -rf build && Scripts/dev-run.sh test` | the whole suite from a clean state, and the bundle's designated requirement after the run |

`recorder-without-host.txt` was produced by mutating one line of product code on purpose and reverting it;
`git status` after the run was back to the two modified product files plus the new test file.
