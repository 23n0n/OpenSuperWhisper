import XCTest
@testable import OpenSuperWhisper

/// A whisper engine that answers with a canned transcript and a canned language
/// instead of running a model, so the plumbing from the engine's own
/// `fullLangId` through `TranscriptionService` and into the transform gate can
/// be tested without a model on disk. Also the engine
/// `SpeechModelLanguageGateTests` pairs with an English-only model path, where
/// the guard has to fire before any transcription happens.
final class StubLanguageWhisperEngine: WhisperEngine {
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

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
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
        // The gate's HTTP path is what these tests stub, injected rather than
        // read from the shared preferences (parallel test processes share one
        // preference file).
        return TranslationService(
            urlSession: URLSession(configuration: configuration),
            usesExternalEndpoint: { true },
            gateSettings: {
                GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .english)
            }
        )
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

/// The English-only-model guard: the captain's combination — `ggml-tiny.en.bin`
/// with the language on Auto-detect — must be refused, named, and offered a fix,
/// instead of quietly producing invented English for the transform to fail on.
///
/// The rule is asserted with no model at all (`SpeechModelLanguageGate.conflict`
/// takes the model's verdict and its path as inputs), and the refusal is then
/// driven through the real `TranscriptionService`, because "surfaced" is only
/// true if nothing was transcribed.
@MainActor
final class SpeechModelLanguageGateTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var modelsDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-language-gate-\(UUID().uuidString)")
        modelsDirectory = temporaryDirectory
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        // What is on a real machine: the English-only model the app ships, the
        // multilingual one the app recommends, and the VAD weights that sit
        // beside the weights but are not a speech model.
        for name in ["ggml-tiny.en.bin", "ggml-large-v3-turbo.bin", "ggml-silero-v5.1.2.bin"] {
            try Data([0]).write(to: modelsDirectory.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try super.tearDownWithError()
    }

    // MARK: - The rule

    /// The exact failure, and the story the user is told: the model, the
    /// setting, what whisper does instead, and the model already on this machine
    /// that fixes it.
    func testEnglishOnlyModelWithAutoDetectIsRefusedWithTheModelAndSettingNamed() throws {
        let conflict = try XCTUnwrap(SpeechModelLanguageGate.conflict(
            modelPath: "/models/ggml-tiny.en.bin",
            isMultilingual: false,
            languageCode: "auto",
            modelsDirectory: modelsDirectory
        ))

        XCTAssertEqual(conflict.modelName, "ggml-tiny.en.bin")
        XCTAssertEqual(conflict.languageCode, "auto")
        XCTAssertEqual(conflict.languageName, "Auto-detect")
        XCTAssertEqual(conflict.remedyModelName, "ggml-large-v3-turbo.bin")
        XCTAssertEqual(conflict.remedyButtonTitle, "Use ggml-large-v3-turbo.bin")
        XCTAssertTrue(conflict.message.contains("ggml-tiny.en.bin"))
        XCTAssertTrue(conflict.message.contains("Auto-detect"))
        XCTAssertTrue(conflict.message.contains("ggml-large-v3-turbo.bin"))
    }

    /// English is the one language an English-only model can serve: the guard
    /// must never stand between the user and plain English dictation.
    func testEnglishIsNeverRefused() throws {
        XCTAssertNil(SpeechModelLanguageGate.conflict(
            modelPath: "/models/ggml-tiny.en.bin",
            isMultilingual: false,
            languageCode: "en",
            modelsDirectory: modelsDirectory
        ))
    }

    /// A multilingual model hears every language, so nothing is refused —
    /// including when the loaded context and the file name disagree, where the
    /// context is the one that counts.
    func testAMultilingualModelIsNeverRefused() throws {
        XCTAssertNil(SpeechModelLanguageGate.conflict(
            modelPath: "/models/ggml-large-v3-turbo.bin",
            isMultilingual: true,
            languageCode: "pl",
            modelsDirectory: modelsDirectory
        ))
        XCTAssertNil(SpeechModelLanguageGate.conflict(
            modelPath: "/models/ggml-tiny.en.bin",
            isMultilingual: true,
            languageCode: "pl",
            modelsDirectory: modelsDirectory
        ))
    }

    /// Before a model is loaded there is no context to ask, so the file name is
    /// the only signal — and it is enough for the captain's own file.
    func testTheFileNameAloneRefusesAnEnglishOnlyModel() throws {
        for name in ["ggml-tiny.en.bin", "ggml-base.en.bin", "ggml-small.en-q5_1.bin"] {
            XCTAssertNotNil(
                SpeechModelLanguageGate.conflict(
                    modelPath: "/models/\(name)",
                    isMultilingual: nil,
                    languageCode: "auto",
                    modelsDirectory: modelsDirectory
                ),
                name
            )
        }
    }

    /// Nothing selected is not this guard's business: there is no model to blame
    /// and nothing to refuse.
    func testNoModelIsNotRefused() throws {
        XCTAssertNil(SpeechModelLanguageGate.conflict(
            modelPath: nil,
            isMultilingual: nil,
            languageCode: "auto",
            modelsDirectory: modelsDirectory
        ))
    }

    /// Every non-English setting on an English-only model is refused, not just
    /// Auto-detect.
    func testEveryNonEnglishSettingIsRefused() throws {
        for language in ["auto", "pl", "de", "zh"] {
            XCTAssertNotNil(
                SpeechModelLanguageGate.conflict(
                    modelPath: "/models/ggml-tiny.en.bin",
                    isMultilingual: false,
                    languageCode: language,
                    modelsDirectory: modelsDirectory
                ),
                language
            )
        }
    }

    /// The offered fix is a real multilingual model: the recommended one when it
    /// is installed, and never the English-only model or the VAD weights.
    func testTheOfferedFixIsAUsableMultilingualModel() throws {
        XCTAssertEqual(
            SpeechModelLanguageGate.installedMultilingualModel(in: modelsDirectory)?.lastPathComponent,
            "ggml-large-v3-turbo.bin"
        )

        let bare = temporaryDirectory.appendingPathComponent("bare")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        for name in ["ggml-tiny.en.bin", "ggml-silero-v5.1.2.bin"] {
            try Data([0]).write(to: bare.appendingPathComponent(name))
        }
        XCTAssertNil(
            SpeechModelLanguageGate.installedMultilingualModel(in: bare),
            "Neither an English-only model nor the VAD weights can fix this"
        )
    }

    // MARK: - The refusal

    private func englishOnlyService(text: String, language: String) -> TranscriptionService {
        TranscriptionService(
            selection: TranscriptionService.EngineSelection(
                engine: "whisper",
                modelPath: "/models/ggml-tiny.en.bin",
                modelVersion: ""
            ),
            engineLoader: { _ in StubLanguageWhisperEngine(text: text, language: language) }
        )
    }

    private func transcribe(
        _ service: TranscriptionService,
        language: String
    ) async throws -> TranscriptionService.TranscriptionOutput {
        var settings = Settings()
        settings.selectedLanguage = language
        return try await service.transcribeAudio(
            url: URL(fileURLWithPath: "/unused-dictation.wav"),
            settings: settings,
            operationID: UUID(),
            pcmSamples: nil
        )
    }

    /// The captain's case, refused by the service rather than passed through: no
    /// transcript, and nothing that looks like a transcription in progress.
    func testEnglishOnlyModelWithAutoDetectIsRefusedInsteadOfTranscribed() async throws {
        let service = englishOnlyService(text: "There are some people who are going to go to the airport.", language: "en")

        do {
            let output = try await transcribe(service, language: "auto")
            XCTFail("An English-only model with Auto-detect must not transcribe; got \(output.text)")
        } catch let error as TranscriptionError {
            guard case .speechLanguageConflict(let conflict) = error else {
                return XCTFail("expected speechLanguageConflict, got \(error)")
            }
            XCTAssertEqual(conflict.modelName, "ggml-tiny.en.bin")
            XCTAssertEqual(conflict.languageCode, "auto")
        }

        XCTAssertFalse(service.isTranscribing, "A refused dictation must not look like one in progress")
        XCTAssertEqual(service.transcribedText, "")
    }

    /// The same model and engine, with the language on English: dictation works,
    /// so the guard refuses the combination and not the model.
    func testEnglishOnlyModelStillTranscribesEnglish() async throws {
        let service = englishOnlyService(text: "Please send the report.", language: "en")

        let output = try await transcribe(service, language: "en")

        XCTAssertEqual(output.text, "Please send the report.")
        XCTAssertEqual(output.language, "en")
    }

    /// A multilingual model on disk — the remedy the alert offers — is not
    /// refused, so taking the fix really does unblock the dictation.
    func testTakingTheOfferedFixUnblocksTheDictation() async throws {
        let service = TranscriptionService(
            selection: TranscriptionService.EngineSelection(
                engine: "whisper",
                modelPath: "/models/ggml-large-v3-turbo.bin",
                modelVersion: ""
            ),
            engineLoader: { _ in StubLanguageWhisperEngine(text: "Cześć, jak się masz?", language: "pl") }
        )

        let output = try await transcribe(service, language: "auto")

        XCTAssertEqual(output.text, "Cześć, jak się masz?")
        XCTAssertEqual(output.language, "pl")
    }
}
