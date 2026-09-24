import XCTest
@testable import OpenSuperWhisper

/// A whisper engine that answers with a canned transcript and a canned language
/// instead of running a model, so the plumbing from the engine's own
/// `fullLangId` through `TranscriptionService` and into the transform gate can
/// be tested without a model on disk. Also the engine
/// `SpeechModelLanguageGateTests` pairs with an English-only model path, because
/// the guard decides on the transcript the engine produced.
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

/// The wiring that carries the spoken language with the text: the language the
/// engine measured is what the transform gate rewrites in, what decides the
/// model, and — when the model cannot have heard it — what the guard refuses on.
@MainActor
final class TranscriptionLanguageGateTests: XCTestCase {

    private let polishText = "Cześć, jak się masz?"
    private let englishText = "Please send the report."

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

    // MARK: - The language drives the transform

    /// The Polish and English dictations of the same engine: each is rewritten
    /// in its own language, and neither prompt asks for the other one.
    func testEachSpokenLanguageIsRewrittenInItsOwnLanguage() async throws {
        final class Recorder {
            var prompts: [String] = []
            var texts: [String] = []
        }
        let recorder = Recorder()
        let service = TransformService(
            localTransform: { prompt, text, _ in
                recorder.prompts.append(prompt)
                recorder.texts.append(text)
                return text
            },
            gateSettings: { GateSettings(tone: true, cleanUp: false, toneMode: .formal) }
        )

        let polish = try await transcribe(
            engine: StubLanguageWhisperEngine(text: polishText, language: "pl"),
            pcmSamples: [0.1, 0.2]
        )
        let english = try await transcribe(
            engine: StubLanguageWhisperEngine(text: englishText, language: "en"),
            pcmSamples: [0.1, 0.2]
        )

        _ = await service.transformIfEnabled(polish.text, sourceLanguage: polish.language)
        _ = await service.transformIfEnabled(english.text, sourceLanguage: english.language)

        XCTAssertEqual(recorder.texts, [polishText, englishText], "each transcription is what the model is given")
        XCTAssertEqual(recorder.prompts.count, 2, "both dictations are rewritten: tone is language-independent now")
        XCTAssertTrue(recorder.prompts[0].contains("Polish text"), recorder.prompts[0])
        XCTAssertTrue(recorder.prompts[1].contains("English text"), recorder.prompts[1])
    }

    /// An engine that reports nothing leaves the transcript itself as the signal,
    /// which is the Parakeet path.
    func testEngineWithNoLanguageSignal_fallsBackToTheTranscriptText() async throws {
        final class Recorder {
            var prompts: [String] = []
        }
        let recorder = Recorder()
        let service = TransformService(
            localTransform: { prompt, text, _ in
                recorder.prompts.append(prompt)
                return text
            },
            gateSettings: { GateSettings(tone: false, cleanUp: true, toneMode: .formal) }
        )

        let polish = try await transcribe(engine: LanguageLessEngine(text: polishText), pcmSamples: nil)
        XCTAssertNil(polish.language)
        _ = await service.transformIfEnabled(polish.text, sourceLanguage: polish.language)

        XCTAssertEqual(recorder.prompts.count, 1, "Polish text is placed by the heuristic and cleaned up")
        XCTAssertTrue(recorder.prompts[0].contains("Polish text"), recorder.prompts[0])

        let english = try await transcribe(engine: LanguageLessEngine(text: englishText), pcmSamples: nil)
        _ = await service.transformIfEnabled(english.text, sourceLanguage: english.language)

        XCTAssertEqual(recorder.prompts.count, 2)
        XCTAssertTrue(recorder.prompts[1].contains("English text"), recorder.prompts[1])
    }
}

/// The English-only-model guard, re-keyed to the transcript.
///
/// The captain's combination — `ggml-tiny.en.bin` writing English over Polish
/// speech — must be refused, named, and offered a fix. With the manual language
/// picker gone there is no setting left to compare against, and an `.en` model
/// cannot detect anything, so the evidence is the text the model produced: the
/// `LanguageDetector` heuristic decides, and English dictation can never be
/// caught by it.
///
/// The rule is asserted with no model at all (`SpeechModelLanguageGate.conflict`
/// takes the model's verdict, its path and the transcript as inputs), and the
/// refusal is then driven through the real `TranscriptionService`, because
/// "surfaced" is only true if nothing was transcribed.
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

    /// The exact failure, and the story the user is told: the model, what the
    /// dictation looks like, what whisper did instead, and the model already on
    /// this machine that fixes it.
    func testEnglishOnlyModelWritingOverPolishIsRefusedWithBothNamed() throws {
        let conflict = try XCTUnwrap(SpeechModelLanguageGate.conflict(
            modelPath: "/models/ggml-tiny.en.bin",
            isMultilingual: false,
            transcript: "Cześć, jak się masz? Chciałbym wysłać raport do klienta.",
            modelsDirectory: modelsDirectory
        ))

        XCTAssertEqual(conflict.modelName, "ggml-tiny.en.bin")
        XCTAssertEqual(conflict.detectedLanguageCode, "pl")
        XCTAssertEqual(conflict.detectedLanguageName, "Polish")
        XCTAssertEqual(conflict.remedyModelName, "ggml-large-v3-turbo.bin")
        XCTAssertEqual(conflict.remedyButtonTitle, "Use ggml-large-v3-turbo.bin")
        XCTAssertTrue(conflict.message.contains("ggml-tiny.en.bin"))
        XCTAssertTrue(conflict.message.contains("Polish"))
        XCTAssertTrue(conflict.message.contains("ggml-large-v3-turbo.bin"))
    }

    /// English is what an English-only model is for: the guard must never stand
    /// between the user and plain English dictation.
    func testEnglishIsNeverRefused() throws {
        for transcript in [
            "Please send the report to the client today.",
            "The meeting is at three.",
            "I sent it yesterday.",
        ] {
            XCTAssertNil(SpeechModelLanguageGate.conflict(
                modelPath: "/models/ggml-tiny.en.bin",
                isMultilingual: false,
                transcript: transcript,
                modelsDirectory: modelsDirectory
            ), transcript)
        }
    }

    /// Nothing to read is not a conflict: with no transcript yet, or text too
    /// short for the heuristic to place, there is no evidence of anything.
    func testNoTranscriptOrUnplaceableTextIsNotRefused() throws {
        for transcript in [nil, "", "   \n ", "Do it", "Ok"] as [String?] {
            XCTAssertNil(SpeechModelLanguageGate.conflict(
                modelPath: "/models/ggml-tiny.en.bin",
                isMultilingual: false,
                transcript: transcript,
                modelsDirectory: modelsDirectory
            ), transcript ?? "nil")
        }
    }

    /// A multilingual model hears every language, so nothing is refused —
    /// including when the loaded context and the file name disagree, where the
    /// context is the one that counts.
    func testAMultilingualModelIsNeverRefused() throws {
        XCTAssertNil(SpeechModelLanguageGate.conflict(
            modelPath: "/models/ggml-large-v3-turbo.bin",
            isMultilingual: true,
            transcript: "Cześć, jak się masz?",
            modelsDirectory: modelsDirectory
        ))
        XCTAssertNil(SpeechModelLanguageGate.conflict(
            modelPath: "/models/ggml-tiny.en.bin",
            isMultilingual: true,
            transcript: "Cześć, jak się masz?",
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
                    transcript: "Cześć, jak się masz?",
                    modelsDirectory: modelsDirectory
                ),
                name
            )
        }
    }

    /// Nothing selected is not this guard's business: there is no model to blame
    /// and nothing to refuse — a multilingual model with the same transcript is
    /// fine.
    func testNoModelIsNotRefused() throws {
        XCTAssertNil(SpeechModelLanguageGate.conflict(
            modelPath: nil,
            isMultilingual: nil,
            transcript: "Cześć, jak się masz?",
            modelsDirectory: modelsDirectory
        ))
    }

    /// A model that hears Polish does not need this guard, and a model whose
    /// name is not the English-only family is never blamed.
    func testOnlyEnglishOnlyModelsAreBlamed() throws {
        for name in ["ggml-large-v3-turbo.bin", "ggml-medium.bin", "ggml-ivrit-large-v3-turbo.bin"] {
            XCTAssertNil(SpeechModelLanguageGate.conflict(
                modelPath: "/models/\(name)",
                isMultilingual: nil,
                transcript: "Cześć, jak się masz?",
                modelsDirectory: modelsDirectory
            ), name)
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

    private func englishOnlyService(text: String, language: String?) -> TranscriptionService {
        TranscriptionService(
            selection: TranscriptionService.EngineSelection(
                engine: "whisper",
                modelPath: "/models/ggml-tiny.en.bin",
                modelVersion: ""
            ),
            engineLoader: { _ in StubLanguageWhisperEngine(text: text, language: language) }
        )
    }

    private func transcribe(_ service: TranscriptionService) async throws -> TranscriptionService.TranscriptionOutput {
        try await service.transcribeAudio(
            url: URL(fileURLWithPath: "/unused-dictation.wav"),
            settings: Settings(),
            operationID: UUID(),
            pcmSamples: nil
        )
    }

    /// The captain's case, refused by the service rather than kept: the model
    /// wrote English over Polish speech, so no transcript is published and
    /// nothing is pasted.
    func testEnglishOnlyModelWritingOverPolishIsRefusedInsteadOfKept() async throws {
        // What `ggml-tiny.en.bin` produced from Polish speech: whispered English
        // ("There are some people..."), and — the case the guard can see — the
        // Polish words it wrote instead of hearing.
        let service = englishOnlyService(text: "Cześć, jak się masz? Proszę wysłać raport.", language: nil)

        do {
            let output = try await transcribe(service)
            XCTFail("an English-only model over Polish speech must not publish a transcript; got \(output.text)")
        } catch let error as TranscriptionError {
            guard case .speechLanguageConflict(let conflict) = error else {
                return XCTFail("expected speechLanguageConflict, got \(error)")
            }
            XCTAssertEqual(conflict.modelName, "ggml-tiny.en.bin")
            XCTAssertEqual(conflict.detectedLanguageCode, "pl")
        }

        XCTAssertFalse(service.isTranscribing, "a refused dictation must not look like one in progress")
        XCTAssertEqual(service.transcribedText, "", "nothing was published")
    }

    /// The same model and engine over English speech: dictation works, so the
    /// guard refuses the impossible pair and not the model.
    func testEnglishOnlyModelStillTranscribesEnglish() async throws {
        let service = englishOnlyService(text: "Please send the report.", language: nil)

        let output = try await transcribe(service)

        XCTAssertEqual(output.text, "Please send the report.")
        XCTAssertNil(output.language, "an English-only model measures nothing")
    }

    /// A multilingual model on disk — the remedy the alert offers — produces a
    /// Polish transcript that is kept, because it could really have heard it.
    func testAMultilingualModelKeepsThePolishTranscript() async throws {
        let service = TranscriptionService(
            selection: TranscriptionService.EngineSelection(
                engine: "whisper",
                modelPath: "/models/ggml-large-v3-turbo.bin",
                modelVersion: ""
            ),
            engineLoader: { _ in StubLanguageWhisperEngine(text: "Cześć, jak się masz?", language: "pl") }
        )

        let output = try await transcribe(service)

        XCTAssertEqual(output.text, "Cześć, jak się masz?")
        XCTAssertEqual(output.language, "pl")
    }
}
