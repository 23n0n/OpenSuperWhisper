import XCTest
@testable import OpenSuperWhisper

/// A whisper engine that answers with a canned transcript and a canned language
/// instead of running a model, so the plumbing from the engine's own
/// `fullLangId` through `TranscriptionService` and into the transform gate can
/// be tested without a model on disk.
private final class StubLanguageWhisperEngine: WhisperEngine {
    private let cannedText: String
    private let cannedLanguage: String?

    init(text: String, language: String?) {
        self.cannedText = text
        self.cannedLanguage = language
        super.init(modelPath: "/stub-model-not-on-disk")
    }

    override func transcribeAudioDetailed(url: URL, settings: Settings) async throws -> DetailedTranscription {
        DetailedTranscription(text: cannedText, segments: [], language: cannedLanguage)
    }

    override func transcribeSamplesDetailed(_ samples: [Float], settings: Settings) async throws -> DetailedTranscription {
        DetailedTranscription(text: cannedText, segments: [], language: cannedLanguage)
    }
}

/// An engine with no language signal at all (Parakeet/FluidAudio), to pin the
/// `nil` fallback.
private final class LanguageLessEngine: TranscriptionEngine {
    let text: String

    init(text: String) {
        self.text = text
    }

    var isModelLoaded: Bool { true }
    var engineName: String { "LanguageLess" }
    func initialize() async throws {}
    func transcribeAudio(url: URL, settings: Settings) async throws -> String { text }
    func cancelTranscription() {}
    func getSupportedLanguages() -> [String] { ["en"] }
}

/// The wiring that decides whether a dictation is translated, toned or pasted
/// as-is: the engine's language must travel with the text all the way into the
/// gate. A dropped language here is the original bug (English reaching the
/// Polish→English transform) coming back.
@MainActor
final class TranscriptionLanguageGateTests: XCTestCase {

    private let polishText = "Cześć, jak się masz?"
    private let englishText = "Please send the report."
    private let translatedText = "Hello, how are you?"

    private var savedTranslateEnabled = false
    private var savedToneEnabled = false

    override func setUp() {
        super.setUp()
        let prefs = AppPreferences.shared
        savedTranslateEnabled = prefs.translateEnabled
        savedToneEnabled = prefs.toneEnabled
        prefs.translateEnabled = false
        prefs.toneEnabled = false
        StubURLProtocol.reset()
    }

    override func tearDown() {
        let prefs = AppPreferences.shared
        prefs.translateEnabled = savedTranslateEnabled
        prefs.toneEnabled = savedToneEnabled
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func transcribe(
        engine: TranscriptionEngine,
        pcmSamples: [Float]?
    ) async throws -> TranscriptionService.TranscriptionOutput {
        try await TranscriptionService(engine: engine).transcribeAudio(
            url: URL(fileURLWithPath: "/unused-dictation.wav"),
            settings: Settings(),
            operationID: UUID(),
            pcmSamples: pcmSamples
        )
    }

    private func stubbedTranslationService() -> TranslationService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranslationService(urlSession: URLSession(configuration: configuration))
    }

    private func stubContent(_ content: String) throws {
        StubURLProtocol.outcome = .success(
            statusCode: 200,
            body: try JSONSerialization.data(
                withJSONObject: ["choices": [["message": ["content": content]]]]
            )
        )
    }

    // MARK: - Engine language reaches the output

    func testWhisperLanguageReachesTheTranscriptionOutput_forFilesAndSamples() async throws {
        let engine = StubLanguageWhisperEngine(text: polishText, language: "pl")

        let fromFile = try await transcribe(engine: engine, pcmSamples: nil)
        XCTAssertEqual(fromFile.text, polishText)
        XCTAssertEqual(fromFile.language, "pl")

        let fromSamples = try await transcribe(engine: engine, pcmSamples: [0.1, 0.2, 0.3])
        XCTAssertEqual(fromSamples.text, polishText)
        XCTAssertEqual(fromSamples.language, "pl")
    }

    func testSpeechlessEngineReportsNoLanguage() async throws {
        let output = try await transcribe(
            engine: LanguageLessEngine(text: polishText),
            pcmSamples: nil
        )

        XCTAssertEqual(output.text, polishText)
        XCTAssertNil(output.language, "Only whisper reports a language")
    }

    // MARK: - Output language drives the gate

    func testEnglishDictation_isNeverSentToThePolishToEnglishTransform() async throws {
        AppPreferences.shared.translateEnabled = true
        StubURLProtocol.reset()
        try stubContent(translatedText)

        let output = try await transcribe(
            engine: StubLanguageWhisperEngine(text: polishText, language: "en"),
            pcmSamples: [0.1, 0.2]
        )
        let finalText = await stubbedTranslationService().transformIfEnabled(
            output.text,
            sourceLanguage: output.language
        )

        XCTAssertEqual(finalText, polishText, "English must be pasted unchanged")
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    func testPolishDictation_isTranslated() async throws {
        AppPreferences.shared.translateEnabled = true
        StubURLProtocol.reset()
        try stubContent(translatedText)

        let output = try await transcribe(
            engine: StubLanguageWhisperEngine(text: polishText, language: "pl"),
            pcmSamples: [0.1, 0.2]
        )
        let finalText = await stubbedTranslationService().transformIfEnabled(
            output.text,
            sourceLanguage: output.language
        )

        XCTAssertEqual(finalText, translatedText)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testEngineWithNoLanguageSignal_fallsBackToTheTranscriptText() async throws {
        AppPreferences.shared.translateEnabled = true
        StubURLProtocol.reset()
        try stubContent(translatedText)

        let polish = try await transcribe(engine: LanguageLessEngine(text: polishText), pcmSamples: nil)
        XCTAssertNil(polish.language)
        let translated = await stubbedTranslationService().transformIfEnabled(
            polish.text,
            sourceLanguage: polish.language
        )
        XCTAssertEqual(translated, translatedText, "Polish text must still be translated")
        XCTAssertEqual(StubURLProtocol.requestCount, 1)

        StubURLProtocol.reset()
        let english = try await transcribe(engine: LanguageLessEngine(text: englishText), pcmSamples: nil)
        let passthrough = await stubbedTranslationService().transformIfEnabled(
            english.text,
            sourceLanguage: english.language
        )
        XCTAssertEqual(passthrough, englishText, "English text must not be transformed")
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }
}
