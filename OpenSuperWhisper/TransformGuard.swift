import Foundation

/// Why a tone result was thrown away in favour of the raw transcript.
///
/// Every case is decided from the *text alone*: the guard makes no model call
/// and runs no second pass, so it cannot itself hallucinate. It exists because
/// the small shipped model answered a dictation as if it were a chat request and
/// prefixed the rewrite with an acknowledgement; the prompt makes that rarer,
/// the 8B makes it rarer still, and this makes the class impossible.
enum TransformGuardRejection: Equatable {
    /// The answer opens by addressing the user as an assistant would.
    case assistantFrame(String)
    /// The answer carries a label line (`Register:`/`Output:`) or announces the
    /// rewritten text instead of being it.
    case label(String)
    /// The dictation carried a sentence and the answer is a fragment of it.
    case stub(wordsIn: Int, wordsOut: Int)
    /// The answer holds no word of the language that went in, although the text
    /// that went in had content words.
    case languageFlip(expected: TransformLanguage)

    /// What the notice under the transcript says.
    var notice: String {
        switch self {
        case .assistantFrame(let frame):
            return "The model answered with an acknowledgement (\"\(frame)\") instead of rewriting "
                + "the dictation, so your own words were used instead."
        case .label(let label):
            return "The model wrapped the rewrite in a label (\"\(label)\") instead of returning the "
                + "text alone, so your own words were used instead."
        case .stub:
            return "The model returned a small fragment of the dictation instead of rewriting it, so "
                + "your own words were used instead."
        case .languageFlip(let expected):
            return "The model answered in another language instead of keeping \(expected.displayName), "
                + "so your own words were used instead."
        }
    }
}

/// The deterministic rejection the app applies to a tone result before it can
/// reach the transcript.
///
/// It reads text only — no model call, no second pass. What it catches is the
/// class a user actually notices and cannot repair: an assistant frame, a label,
/// a stub, a language flip. What it cannot catch is subtle content drift (an
/// article dropped, a noun invented); that is the prompt's and the 8B's job, and
/// it is stated as a limit rather than papered over.
enum TransformGuard {
    /// Openings an assistant uses when it is answering rather than rewriting.
    /// Matched on the first words of the first non-empty line, after markdown
    /// and quote marks are stripped, case-insensitively.
    static let assistantFrames: [String] = [
        "sure", "certainly", "of course", "understood", "here is", "here's",
        "i've", "oczywiście", "oto", "jasne"
    ]

    /// Phrases that announce a rewrite instead of being one.
    static let announcingPhrases: [String] = ["rewritten text", "rewritten version"]

    /// Label prefixes that may open a line (`Register: formal`).
    static let labelPrefixes: [String] = ["register:", "output:"]

    /// A dictation with fewer words than this is not "a sentence", so the stub
    /// rule never applies to it — a two-word dictation or a fragment comes back
    /// as it is. Measured against the cases in `fm-20260924-10`: the collapse
    /// the small model produced at temperature 0 replaced a 12-word run-on with
    /// `Understood.` (1 word).
    static let stubMinimumInputWords = 8
    /// The answer must keep at least this fraction of the dictation's words.
    /// `Understood.` keeps 1/12; a legitimate register rewrite keeps almost all.
    static let stubMinimumKeptFraction = 0.25

    /// A flip is only claimed when the text that went in carried content words:
    /// a one-word or number-only dictation gives the detector nothing to hold on
    /// to, and an unchanged short text is never a flip.
    static let flipMinimumInputWords = 3

    /// The rejection for this answer, or `nil` when it may be delivered.
    static func rejection(
        of output: String,
        for input: String,
        language: TransformLanguage
    ) -> TransformGuardRejection? {
        let answer = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return nil }

        // Already in register: the model is allowed — expected — to return the
        // dictation unchanged. Nothing below can be true of the user's own text,
        // and the language rule in particular must not be read as a flip.
        if answer == input.trimmingCharacters(in: .whitespacesAndNewlines) { return nil }

        if let frame = assistantFrame(in: answer) {
            return .assistantFrame(frame)
        }
        if let label = label(in: answer) {
            return .label(label)
        }
        if let stub = stub(output: answer, input: input) {
            return stub
        }
        if let flip = languageFlip(output: answer, input: input, language: language) {
            return flip
        }
        return nil
    }

    /// The frame the answer opens with, if any.
    ///
    /// Only the opening counts: a dictation may legitimately *contain* "sure" or
    /// a first-person "I've" in the middle, and rejecting that would throw away
    /// good output.
    static func assistantFrame(in answer: String) -> String? {
        guard let opening = firstContentLine(of: answer)?.lowercased() else { return nil }
        for frame in assistantFrames {
            if opening == frame { return frame }
            if opening.hasPrefix(frame) {
                let next = opening[opening.index(opening.startIndex, offsetBy: frame.count)]
                if next == "," || next == "!" || next == "." || next == ":" || next == " " {
                    return frame
                }
            }
        }
        return nil
    }

    /// The label the answer carries, if any.
    ///
    /// Two shapes: a line that opens with a label prefix, and an announcement
    /// phrase anywhere (`Sure, here's the rewritten text in a casual register:` —
    /// the measured 1.5B preamble; its opening is caught by the frame rule as
    /// well, this catches the same sentence when the opener differs).
    static func label(in answer: String) -> String? {
        let lowered = answer.lowercased()
        for phrase in announcingPhrases where lowered.contains(phrase) {
            return phrase
        }
        for line in answer.components(separatedBy: .newlines) {
            let trimmed = stripMarkup(line).trimmingCharacters(in: .whitespaces)
            let lineLowered = trimmed.lowercased()
            for prefix in labelPrefixes where lineLowered.hasPrefix(prefix) {
                return prefix
            }
        }
        return nil
    }

    /// The stub, if the answer is a small fragment of a dictation that carried a
    /// sentence.
    static func stub(output: String, input: String) -> TransformGuardRejection? {
        let inWords = words(in: input).count
        guard inWords >= stubMinimumInputWords else { return nil }
        let outWords = words(in: output).count
        let floor = Int((Double(inWords) * stubMinimumKeptFraction).rounded(.down))
        guard outWords < max(1, floor) else { return nil }
        return .stub(wordsIn: inWords, wordsOut: outWords)
    }

    /// The flip, when the answer holds no word of the language that went in.
    ///
    /// The app's own `LanguageDetector` decides, which is also what classifies
    /// the dictation in the first place. Three things must hold before a flip is
    /// claimed, so the legitimate cases stay untouched:
    ///
    /// * the *dictation* itself classifies as the language the policy pinned —
    ///   a text that mixes in a technical term from another language does not,
    ///   and an answer to it is never called a flip (measured: "We deploy the
    ///   backend na produkcję every Friday evening." classifies as Polish);
    /// * the answer classifies as the other language (or the detector cannot
    ///   place it, in which case it is not a flip either — "cannot place" is not
    ///   "flipped");
    /// * the answer shares no content word with the dictation. A rewrite that
    ///   keeps any of the user's own words has not flipped wholesale.
    static func languageFlip(
        output: String,
        input: String,
        language: TransformLanguage
    ) -> TransformGuardRejection? {
        guard words(in: input).count >= flipMinimumInputWords else { return nil }
        guard let inputVerdict = TransformLanguage(verdict: LanguageDetector.detect(input)),
              inputVerdict == language else { return nil }
        guard let outputVerdict = TransformLanguage(verdict: LanguageDetector.detect(output)),
              outputVerdict != language else { return nil }
        let inputWords = Set(words(in: input).map { $0.lowercased() })
        let shared = words(in: output).contains { inputWords.contains($0.lowercased()) }
        guard !shared else { return nil }
        return .languageFlip(expected: language)
    }

    // MARK: - Text helpers

    /// The first line that carries something other than markdown or quotes.
    private static func firstContentLine(of text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let stripped = stripMarkup(line).trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return nil
    }

    /// Removes the decoration a chat model wraps around its answer: markdown
    /// emphasis, bullets and surrounding quote marks.
    private static func stripMarkup(_ line: String) -> String {
        var result = line.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "#", with: "")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”„«»-—–•"))
        return result
    }

    /// The words of `text`: runs of letters, which is what both the stub rule
    /// and the flip rule need. Numbers are deliberately not words — a list of
    /// numbers is not a sentence and must not be measured as one.
    static func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }
}
