import XCTest
@testable import OpenSuperWhisper

/// The language whisper reports for one utterance — the signal the transform
/// gate turns into "translate, tone, or paste as-is".
///
/// Needs a real model: the English-only `ggml-tiny.en.bin` the app bundles
/// covers the fixed-setting cases, and a multilingual model
/// (`OSW_TEST_MULTILINGUAL_MODEL`, `.build/test-models/ggml-tiny.bin` or
/// `./ggml-tiny.bin`) covers Auto-detect, which is the only setting that
/// measures a language at all.
final class WhisperLanguageReportTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // MARK: - Fixtures

    private func multilingualModelURL() throws -> URL {
        let candidates = [
            ProcessInfo.processInfo.environment["OSW_TEST_MULTILINGUAL_MODEL"]
                .map(URL.init(fileURLWithPath:)),
            Self.repoRoot.appendingPathComponent(".build/test-models/ggml-tiny.bin"),
            Self.repoRoot.appendingPathComponent("ggml-tiny.bin"),
        ].compactMap { $0 }

        guard let model = candidates.first(where: { candidate in
            guard let size = try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return false }
            return size > 10_000_000
        }) else {
            throw XCTSkip("Set OSW_TEST_MULTILINGUAL_MODEL to a real multilingual ggml model")
        }
        return model
    }

    // MARK: - Helpers

    private func transcribeFixture(
        language: String,
        model: URL
    ) async throws -> WhisperEngine.DetailedTranscription {
        // `Settings.selectedLanguage` persists itself, so put the user's choice
        // back exactly as it was.
        let savedLanguage = AppPreferences.shared.whisperLanguage
        defer { AppPreferences.shared.whisperLanguage = savedLanguage }

        let engine = WhisperEngine(modelPath: model.path)
        try await engine.initialize()
        defer { engine.unload() }

        var settings = Settings()
        settings.selectedLanguage = language
        settings.showTimestamps = false
        settings.initialPrompt = ""
        settings.useBeamSearch = false
        settings.temperature = 0
        settings.noSpeechThreshold = 0.6
        settings.suppressBlankAudio = true

        return try await engine.transcribeAudioDetailed(
            url: Self.repoRoot.appendingPathComponent("jfk.wav"),
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
        let result = try await transcribeFixture(language: "pl", model: try multilingualModelURL())

        XCTAssertEqual(result.language, "pl")
    }

    // MARK: - Auto-detect

    /// Auto-detect with a multilingual model: the language comes from the same
    /// `whisper_full` call that produced the text (the design study measured `en`
    /// at p = 0.9982 on this fixture), and costs nothing extra on top of the
    /// transcription.
    func testMultilingualModelReportsTheSpokenLanguageOnAuto() async throws {
        let result = try await transcribeFixture(language: "auto", model: try multilingualModelURL())

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
