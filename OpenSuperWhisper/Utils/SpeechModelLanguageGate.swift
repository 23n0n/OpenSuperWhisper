import Foundation

/// An English-only speech model that produced a transcript it cannot have heard.
///
/// This is the captain's first failure, made impossible to miss: his selected
/// model was `ggml-tiny.en.bin`, so whisper could not hear the Polish he spoke
/// and produced confident English instead ("There are some people who are going
/// to go to the airport."). Nothing warned him; nothing named the model.
///
/// There is no language setting left to compare against, so the evidence is the
/// transcript itself: an `.en` model cannot detect anything, and when the text
/// it produced is not English, what the user is looking at is a model writing
/// English over speech it never understood.
struct SpeechLanguageConflict: Equatable {
    /// The speech model's file name, e.g. `ggml-tiny.en.bin`.
    let modelName: String
    /// The language the transcript itself looks like, e.g. `pl`.
    let detectedLanguageCode: String
    /// That language in words, e.g. "Polish".
    let detectedLanguageName: String
    /// An already-installed multilingual model that fixes it, if there is one.
    let remedyModelName: String?
    let remedyModelPath: String?

    var title: String { "This dictation needs a multilingual model" }

    /// The whole story in one paragraph: the model, what the transcript looks
    /// like, what whisper did instead, and the fix — the file that is already on
    /// this machine when there is one.
    var message: String {
        var text = "\(modelName) understands English only, but this dictation is "
            + "\(detectedLanguageName). Whisper cannot transcribe \(detectedLanguageName) with that "
            + "model — it writes English sentences instead of what was said. Dictation is blocked "
            + "until this is fixed."
        if let remedyModelName {
            text += " Select \(remedyModelName) (already on this machine)."
        } else {
            text += " Download a multilingual model in Settings → Model."
        }
        return text
    }

    /// The fix offered in place, when there is an installed model to offer.
    var remedyButtonTitle: String? {
        remedyModelName.map { "Use \($0)" }
    }
}

/// What the decoder measured about the speech in the audio it was given.
///
/// The transcript cannot answer this. Whisper writes its most likely phrase
/// over anything it is handed — silence comes back as "Thank you for watching"
/// in text that reads exactly like speech — so the text is no evidence at all
/// that a voice was there. What is evidence is the VAD in front of the decoder
/// and the decoder's own `no_speech_prob` for the segments it produced, which
/// is why the engine puts its measurement here and the gate below refuses on
/// it. `nil` — no measurement — is not evidence and never refuses.
enum SpeechPresence: Equatable {
    /// The VAD found no speech segment at all: what the decoder was given could
    /// not have been words.
    case noSpeechSegment
    /// Speech was there, and this is what the segments the decoder produced look
    /// like to it: whisper's own `no_speech_prob`, averaged over them. It is the
    /// quantity the user's `noSpeechThreshold` is compared against inside
    /// whisper, so the same line decides here.
    case measured(meanNoSpeechProbability: Double)
}

/// A transcript produced from audio that held no speech.
///
/// This is the second way text appears out of nothing: the language conflict
/// above needs a model that cannot hear the language, but whisper invents a
/// fluent phrase over a room with no voice in it just as readily — and with a
/// multilingual model there is no language conflict to catch it. The refusal is
/// the same shape as the other one: nothing is published, nothing is pasted,
/// the audio is kept so nothing the user said is lost, and the message says
/// what the user has to act on — that no speech was detected.
struct SpeechPresenceConflict: Equatable {
    /// The speech model that produced the text, e.g. `ggml-tiny.en.bin`.
    let modelName: String
    /// What refused the transcript.
    let presence: SpeechPresence
    /// The user's `noSpeechThreshold`, the line the measurement was over.
    let noSpeechThreshold: Double

    var title: String { "No speech was detected" }

    /// The whole story, in the user's terms: no speech, not a language error,
    /// and what happened to the recording.
    var message: String {
        var text = "No speech was detected in this recording, so nothing was transcribed and nothing "
            + "was typed. \(modelName) wrote text over audio it heard no speech in — silence is where "
            + "whisper invents phrases nobody said — so the transcript was discarded instead of "
            + "pasted."
        switch presence {
        case .noSpeechSegment:
            text += " The voice activity detector found no speech in this recording at all."
        case .measured(let meanNoSpeechProbability):
            text += String(
                format: " The segments it produced look like non-speech (no-speech probability "
                    + "%.2f, and your threshold is %.2f).",
                meanNoSpeechProbability,
                noSpeechThreshold
            )
        }
        return text + " The audio is kept, so the recording is not lost."
    }
}

/// The rule that refuses to keep a transcript only an English-only model could
/// have invented.
///
/// The model is English-only when the loaded context says
/// `whisper_is_multilingual() == 0`, and — for the window before a model is
/// loaded, and for the Settings card, where there is no engine at all — when its
/// file name declares it (`ggml-tiny.en.bin`, `ggml-base.en.bin`).
///
/// The language, now, is **read off the transcript**: with the manual language
/// picker gone there is no setting to compare against, and an English-only model
/// measures nothing — the text it produced is the only evidence in the app. The
/// existing `LanguageDetector` heuristic supplies the verdict, so a transcript
/// that looks Polish under a `.en` model is refused and named, and English
/// dictation can never be caught by this guard.
///
/// Nothing here changes a preference. The remedy is offered, and applied only
/// when the user takes it.
enum SpeechModelLanguageGate {

    /// The multilingual model the app prefers to offer, because it is the one
    /// the machine and the download list both know.
    static let preferredMultilingualModelName = "ggml-large-v3-turbo.bin"

    /// The conflict for this model and this transcript, or `nil` when there is
    /// nothing to refuse.
    static func conflict(
        modelPath: String?,
        isMultilingual: Bool?,
        transcript: String?,
        modelsDirectory: URL = WhisperModelManager.modelsDirectory,
        fileManager: FileManager = .default
    ) -> SpeechLanguageConflict? {
        guard isEnglishOnlyModel(modelPath: modelPath, isMultilingual: isMultilingual) else { return nil }

        // The transcript is the whole of the evidence, so no text — or text the
        // heuristic cannot place — is not a conflict.
        guard let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let detected = LanguageDetector.detect(transcript).languageCode,
              detected != "en" else {
            return nil
        }

        let remedy = installedMultilingualModel(in: modelsDirectory, fileManager: fileManager)
        let modelName = modelPath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "The selected speech model"

        return SpeechLanguageConflict(
            modelName: modelName,
            detectedLanguageCode: detected,
            detectedLanguageName: LanguageUtil.languageNames[detected] ?? detected,
            remedyModelName: remedy?.lastPathComponent,
            remedyModelPath: remedy?.path
        )
    }

    /// The refusal for a transcript produced from audio with no speech in it, or
    /// `nil` when the audio held speech — and, just as important, when nothing
    /// measured either way.
    ///
    /// Only evidence refuses. The VAD finding no speech segment is evidence on
    /// its own; a measured no-speech probability is evidence against the user's
    /// own `noSpeechThreshold`, the same line whisper is handed
    /// (`params.no_speech_thold`). `nil` — an engine that measures nothing, a
    /// call site that does not populate it — is not evidence, so the transcript
    /// goes on to the language gate exactly as it did before.
    static func noSpeechConflict(
        presence: SpeechPresence?,
        noSpeechThreshold: Double,
        modelPath: String? = nil
    ) -> SpeechPresenceConflict? {
        guard let presence else { return nil }

        // Speech was there and the measurement is under the user's own line:
        // whatever produced this text, it was not silence.
        if case .measured(let meanNoSpeechProbability) = presence,
           meanNoSpeechProbability < noSpeechThreshold {
            return nil
        }

        let modelName = modelPath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "The selected speech model"

        return SpeechPresenceConflict(
            modelName: modelName,
            presence: presence,
            noSpeechThreshold: noSpeechThreshold
        )
    }

    /// Whether this model can only speak English.
    ///
    /// The loaded context is authoritative when there is one; the file name is
    /// the only signal for a model that is not loaded yet.
    static func isEnglishOnlyModel(modelPath: String?, isMultilingual: Bool?) -> Bool {
        if let isMultilingual { return !isMultilingual }
        guard let path = modelPath, !path.isEmpty else { return false }
        return isEnglishOnlyFileName(URL(fileURLWithPath: path).lastPathComponent)
    }

    /// `ggml-tiny.en.bin`, `ggml-base.en.bin`, `ggml-small.en-xyz.bin`: the
    /// naming whisper.cpp uses for the English-only family.
    static func isEnglishOnlyFileName(_ fileName: String) -> Bool {
        let name = fileName.lowercased()
        return name.hasSuffix(".en.bin") || name.contains(".en-")
    }

    /// A usable multilingual whisper model already on this machine, preferring
    /// the one the app recommends. The silero VAD model next to the weights is
    /// not a speech model and is skipped.
    static func installedMultilingualModel(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return nil }

        let candidates = entries.filter { url in
            let name = url.lastPathComponent.lowercased()
            guard name.hasSuffix(".bin") else { return false }
            guard !name.hasPrefix("ggml-silero") else { return false }
            return !isEnglishOnlyFileName(name)
        }

        if let preferred = candidates.first(where: {
            $0.lastPathComponent == preferredMultilingualModelName
        }) {
            return preferred
        }
        return candidates.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    /// The model the dictation runs on: the resolved one, unless it can only
    /// speak English and a multilingual model is installed next to it.
    ///
    /// An English-only model is not merely worse at other languages — it cannot
    /// hear them at all. It has nothing to detect (its language is `en` by
    /// construction), so Polish speech comes back as fluent English that was
    /// never said, and no gate can catch that: the text *is* English. Where a
    /// multilingual model is already on this machine, running the dictation
    /// through it is the only way the speech can come back as what was said.
    /// Where only English-only models exist, the resolved path stands — and the
    /// conflict gate above still refuses the transcript and names the remedy.
    ///
    /// Nothing is written down: this answers which file a model is loaded from,
    /// and the user's own selection is used unchanged the moment it can hear
    /// the language.
    static func preferredDictationModelPath(
        over resolvedPath: String?,
        modelsDirectory: URL = WhisperModelManager.modelsDirectory,
        fileManager: FileManager = .default
    ) -> String? {
        guard isEnglishOnlyModel(modelPath: resolvedPath, isMultilingual: nil),
              let multilingual = installedMultilingualModel(in: modelsDirectory, fileManager: fileManager)
        else { return resolvedPath }
        return multilingual.path
    }
}

/// Applying the offered fix.
///
/// The user pressed the button, so the selection changes as a deliberate act —
/// the one thing this whole guard must never do on its own is change the model
/// behind the user's back.
@MainActor
enum SpeechLanguageRemedy {
    /// Selects a multilingual model and shows the Settings card it belongs to,
    /// so the user sees both what changed and where.
    static func useMultilingualModel(atPath path: String) {
        TranscriptionService.shared.reloadModel(with: path)
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}
