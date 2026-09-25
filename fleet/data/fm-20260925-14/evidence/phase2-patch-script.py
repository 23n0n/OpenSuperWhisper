#!/usr/bin/env python3
"""fm-20260925-14 phase 2: land the pairing, once the measurement has passed.

Applies, in the worktree:

 1. `WhisperEngine.swift` — the language pre-pass and the prompt choice, restored
    from the phase-1 tree's saved copy (the arms were measured without it).
 2. `Utils/AppPreferences.swift` — the switch defaults **on**, and `initialPrompt`
    gets the doc that says an empty stored value still sends a language default.
 3. `OpenSuperWhisperTests/PauseBoundaryTests.swift` — the case that pinned the
    old ("off") default is deleted; `DecoderPromptDefaultTests` pins the new one.
 4. `OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests.swift` — the arm result
    carries the language the decoder measured, and the shipped-configuration case
    (the criterion, asserted) is appended.

Run from the worktree root. Idempotent-ish: it refuses if the wiring is already
present.
"""
import pathlib
import re
import sys

root = pathlib.Path(".")
engine = root / "OpenSuperWhisper/Engines/WhisperEngine.swift"
prefs = root / "OpenSuperWhisper/Utils/AppPreferences.swift"
pause_tests = root / "OpenSuperWhisperTests/PauseBoundaryTests.swift"
pairing = root / "OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests.swift"

# 1. the engine: the saved phase-2 copy already holds the table, the pre-pass and
#    the wiring, and nothing else changed in the meantime.
wired = pathlib.Path("/tmp/fm2414-WhisperEngine-wired.swift")
current = engine.read_text()
assert "measureLanguage" not in current, "the wiring is already in place"
engine.write_text(wired.read_text())
print("engine: wiring restored from", wired)

# 2. the switch default, on. The phase-1 tree still has the off default and its
#    old doc comment.
text = prefs.read_text()
old_default = '@UserDefault(key: "longPausesEndSentences", defaultValue: false)'
assert old_default in text, "the switch default is not the one this patch expects"
new_doc = pathlib.Path("/tmp/fm2414-appprefs-switch.txt").read_text()
start = text.index('    /// "Long Pauses End the Sentence"')
end = text.index(old_default) + len(old_default)
text = text[:start] + new_doc.rstrip("\n") + text[end:]

old_prompt = '''    @UserDefault(key: "initialPrompt", defaultValue: "")
    var initialPrompt: String'''
new_prompt = '''    /// The decoder context the user has set, or the empty string for none.
    ///
    /// Empty does **not** mean the decoder receives no prompt: when the switch
    /// above is on, an install that has never set one sends the default its
    /// language has (`WhisperEngine.decoderPrompt` — one measured entry for
    /// Polish, one for English, nothing for a language nobody measured). A value
    /// the user sets always wins over it, in any language, and this app never
    /// writes one for them.
    @UserDefault(key: "initialPrompt", defaultValue: "")
    var initialPrompt: String'''
assert old_prompt in text, "the initialPrompt declaration is not the one this patch expects"
prefs.write_text(text.replace(old_prompt, new_prompt))
print("preferences: switch default on, prompt doc added")

# 3. the obsolete default case, replaced by DecoderPromptDefaultTests
text = pause_tests.read_text()
start = text.index("    /// An install that never touches the switch keeps upstream's stitching.")
end = text.index("    // MARK: - Where the boundary lands")
removed = text[start:end]
assert "the shipped default is off" in removed
pause_tests.write_text(text[:start] + text[end:])
print("pause tests: removed the case that pinned the off default")

# 4. the pairing harness: the language the decoder measured, and the shipped case
text = pairing.read_text()
old_arm = '''    private struct ArmResult {
        let arm: String
        let prompt: String
        let text: String
        let sentences: Int
        let milliseconds: Int
    }'''
new_arm = '''    private struct ArmResult {
        let arm: String
        let prompt: String
        let text: String
        let sentences: Int
        let milliseconds: Int
        /// The language this arm's own decode measured — what the shipped path's
        /// pre-pass is compared against.
        let languageAtDecode: String?
    }'''
assert old_arm in text
text = text.replace(old_arm, new_arm)

old_return = '''        return ArmResult(arm: arm, prompt: prompt, text: text, sentences: read.count, milliseconds: milliseconds)'''
new_return = '''        return ArmResult(
            arm: arm,
            prompt: prompt,
            text: text,
            sentences: read.count,
            milliseconds: milliseconds,
            languageAtDecode: detailed.language
        )'''
assert old_return in text
text = text.replace(old_return, new_return)

shipped = pathlib.Path("/tmp/fm2414-shipped-test.swift.txt").read_text()
assert text.rstrip().endswith("}")
text = text.rstrip()
text = text[: text.rfind("}")].rstrip("\n") + "\n\n" + shipped.rstrip("\n") + "\n}\n"
pairing.write_text(text)
print("pairing harness: language recorded, shipped-configuration case appended")
print("phase 2 applied — now build and run")

# 5. the pure tests: the rule now also answers for timestamp mode
defaults_tests = root / "OpenSuperWhisperTests/DecoderPromptDefaultTests.swift"
text = defaults_tests.read_text()

# every call in the file gains the timestamp argument, on its own line
text = re.sub(
    r"(\n)([ \t]*)(spokenLanguage:)",
    lambda m: "{}{}showsTimestamps: false,\n{}{}".format(m.group(1), m.group(2), m.group(2), m.group(3)),
    text,
)
text = text.replace("showsTimestamps: false,\n", "showsTimestamps: false,\n")  # no-op, keeps the diff honest

timestamp_case = '''
    /// Timestamp mode hands the decoder the untrimmed audio and measures no pause,
    /// so the switch has nothing to serve there: no default prompt is sent, and
    /// the mode is byte for byte what it always was.
    func testTimestampModeSendsNoDefault() {
        for language in ["pl", "en"] {
            XCTAssertEqual(
                WhisperEngine.decoderPrompt(
                    userPrompt: "",
                    longPausesEndSentences: true,
                    showsTimestamps: true,
                    spokenLanguage: language
                ),
                "",
                "language \(language)"
            )
        }
    }
}
'''
assert text.rstrip().endswith("}")
text = text.rstrip()
text = text[: text.rfind("}")].rstrip("\n") + "\n" + timestamp_case
defaults_tests.write_text(text)
print("default-prompt tests: signature updated, timestamp case added")
