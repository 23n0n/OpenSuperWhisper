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
