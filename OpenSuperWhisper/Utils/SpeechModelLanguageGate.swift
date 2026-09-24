import Foundation

/// An English-only speech model paired with a language setting it cannot serve.
///
/// This is the captain's first failure, made impossible to miss: his selected
/// model was `ggml-tiny.en.bin` with the language on Auto-detect, so whisper
/// could not hear the Polish he spoke and produced confident English instead
/// ("There are some people who are going to go to the airport.") — and the
/// transform, correctly, found nothing to translate in it. Nothing warned him;
/// nothing named the model or the setting.
struct SpeechLanguageConflict: Equatable {
    /// The speech model's file name, e.g. `ggml-tiny.en.bin`.
    let modelName: String
    /// The language setting that is being asked for, e.g. `auto` or `pl`.
    let languageCode: String
    /// That setting in words, e.g. "Auto-detect" or "Polish".
    let languageName: String
    /// An already-installed multilingual model that fixes it, if there is one.
    let remedyModelName: String?
    let remedyModelPath: String?

    var title: String { "This language needs a multilingual model" }

    /// The whole story in one paragraph: the model, the setting, what whisper
    /// does instead, and the fix — the file that is already on this machine
    /// when there is one.
    var message: String {
        var text = "\(modelName) understands English only, but the transcription language is set to "
            + "\(languageName). Whisper cannot transcribe \(languageName) with that model — it invents "
            + "English sentences instead. Dictation is blocked until this is fixed."
        if let remedyModelName {
            text += " Select \(remedyModelName) (already on this machine), or set the language to English."
        } else {
            text += " Download a multilingual model in Settings → Model, or set the language to English."
        }
        return text
    }

    /// The fix offered in place, when there is an installed model to offer.
    var remedyButtonTitle: String? {
        remedyModelName.map { "Use \($0)" }
    }
}

/// The rule that refuses to transcribe with a model that cannot hear the
/// selected language.
///
/// Both halves are exactly what the brief names: the model is English-only when
/// the loaded context says `whisper_is_multilingual() == 0`, and — for the
/// window before a model is loaded, and for the Settings card, where there is no
/// engine at all — when its file name declares it (`ggml-tiny.en.bin`,
/// `ggml-base.en.bin`). The language setting must be something other than
/// English; `en` is a combination that works and is never blocked, and Auto-detect
/// on an English-only model is the captain's case, refused rather than passed
/// through.
///
/// Nothing here changes a preference. The remedy is offered, and applied only
/// when the user takes it.
enum SpeechModelLanguageGate {

    /// The multilingual model the app prefers to offer, because it is the one
    /// the machine and the download list both know.
    static let preferredMultilingualModelName = "ggml-large-v3-turbo.bin"

    /// The conflict for this model, language setting and installed models, or
    /// `nil` when there is nothing to refuse.
    static func conflict(
        modelPath: String?,
        isMultilingual: Bool?,
        languageCode: String,
        modelsDirectory: URL = WhisperModelManager.modelsDirectory,
        fileManager: FileManager = .default
    ) -> SpeechLanguageConflict? {
        let language = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !language.isEmpty, language != "en" else { return nil }
        guard isEnglishOnlyModel(modelPath: modelPath, isMultilingual: isMultilingual) else { return nil }

        let remedy = installedMultilingualModel(in: modelsDirectory, fileManager: fileManager)
        let modelName = modelPath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "The selected speech model"

        return SpeechLanguageConflict(
            modelName: modelName,
            languageCode: language,
            languageName: LanguageUtil.languageNames[language] ?? language,
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
