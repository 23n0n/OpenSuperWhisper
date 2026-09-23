import XCTest
@testable import OpenSuperWhisper

/// The language whisper reports for one utterance — the signal the transform
/// gate turns into "translate, tone, or paste as-is".
///
/// Needs a real model, and resolves it itself: the bundled English-only
/// `ggml-tiny.en.bin` for the fixed-setting cases, and the test's own
/// multilingual model (`OSW_TEST_MULTILINGUAL_MODEL`, or a copy cached in the
/// checkout) for Auto-detect, the only setting that measures a language. The
/// machine's own selection is never consulted — see `TestFixtures`.
final class WhisperLanguageReportTests: XCTestCase {

    // MARK: - Helpers

    private func transcribeFixture(
        language: String,
        model: URL
    ) async throws -> WhisperEngine.DetailedTranscription {
        let engine = WhisperEngine(modelPath: model.path)
        try await engine.initialize()
        defer { engine.unload() }

        // The language is set on this value, not in the preference store: the
        // struct copies what it needs, so no other test and no running app can
        // decide what this one measures.
        var settings = Settings()
        settings.selectedLanguage = language
        settings.showTimestamps = false
        settings.initialPrompt = ""
        settings.useBeamSearch = false
        settings.temperature = 0
        settings.noSpeechThreshold = 0.6
        settings.suppressBlankAudio = true

        return try await engine.transcribeAudioDetailed(
            url: try TestFixtures.speechSample(),
            settings: settings
        )
    }

    // MARK: - Fixed setting

    /// The configuration an English-only model forces: the setting is what the
    /// decoder was conditioned on, so the gate must see English and never send
    /// the transcript to the Polish→English transform.
    func testEnglishOnlyModelReportsItsFixedSetting() async throws {
        let result = try await transcribeFixture(language: "en", model: try TestFixtures.tinyEnglishModel())

        XCTAssertEqual(result.language, "en")
        XCTAssertFalse(result.text.isEmpty)
    }

    /// A fixed setting is authoritative even when the model could have detected
    /// something else: with `pl` the decoder is conditioned on Polish, so that is
    /// what the gate must be told — not the language the model would have
    /// detected on its own.
    func testMultilingualModelReportsItsFixedSettingNotItsDetection() async throws {
        let result = try await transcribeFixture(language: "pl", model: try TestFixtures.multilingualModel())

        XCTAssertEqual(result.language, "pl")
    }

    // MARK: - Auto-detect

    /// Auto-detect with a multilingual model: the language comes from the same
    /// `whisper_full` call that produced the text (the design study measured `en`
    /// at p = 0.9982 on this fixture), and costs nothing extra on top of the
    /// transcription.
    func testMultilingualModelReportsTheSpokenLanguageOnAuto() async throws {
        let result = try await transcribeFixture(language: "auto", model: try TestFixtures.multilingualModel())

        XCTAssertEqual(result.language, "en")
        XCTAssertFalse(result.text.isEmpty)
    }

    /// Auto-detect on a model that cannot detect: whisper.cpp reports a
    /// meaningless id for English-only models (`fa`/`ur` at p = 0.01, measured),
    /// so the engine must refuse it and let the transcript heuristic decide.
    func testEnglishOnlyModelOnAutoReportsNothing() async throws {
        let result = try await transcribeFixture(language: "auto", model: try TestFixtures.tinyEnglishModel())

        XCTAssertNil(result.language, "A non-multilingual model cannot measure a language")
    }
}
