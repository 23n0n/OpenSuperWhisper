import CryptoKit
import XCTest
@testable import OpenSuperWhisper

/// What the transform does with the model's answer, and which model each
/// language runs on. The built-in runtime is driven through an injected local
/// transform, so no test here loads real weights.
final class TransformBackendTests: XCTestCase {

    private final class LocalRecorder {
        var systemPrompts: [String] = []
        var userTexts: [String] = []
        /// The model each call was routed to, so a test can assert which one a
        /// language resolved to — by name, without loading any weights.
        var models: [TransformModel] = []
        var result: Result<String, Error> = .success("Cześć, jak się masz?")
        var calls: Int { systemPrompts.count }
    }

    private func service(
        local: LocalRecorder,
        settings: GateSettings = GateSettings(tone: true, cleanUp: false, toneMode: .neutral),
        model: @escaping (TransformPolicy) -> TransformModel = { _ in TransformModelManager.shared.defaultModel }
    ) -> TransformService {
        TransformService(
            localTransform: { systemPrompt, userText, chosen in
                local.systemPrompts.append(systemPrompt)
                local.userTexts.append(userText)
                local.models.append(chosen)
                return try local.result.get()
            },
            modelForPolicy: model,
            gateSettings: { settings }
        )
    }

    // MARK: - The in-process runtime is the only backend

    /// There is no second backend and no endpoint: every transform runs on the
    /// weights the app owns, in this process.
    func testEveryTransformRunsInProcess() async {
        let local = LocalRecorder()
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Cześć, jak się masz?", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć, jak się masz?")
        // A tone turn is framed and delimited — the transcript is handed over
        // inside the delimiters, not as a bare request the model could obey.
        let userTurn = local.userTexts.first ?? ""
        XCTAssertEqual(local.calls, 1)
        XCTAssertTrue(userTurn.hasPrefix("Rewrite this dictated text in a neutral register"), userTurn)
        XCTAssertTrue(userTurn.contains("<<<TRANSCRIPT\nCześć, jak się masz?\nTRANSCRIPT>>>"), userTurn)
    }

    // MARK: - Response handling

    func testFailure_returnsTheRawTranscript() async {
        let local = LocalRecorder()
        local.result = .failure(TransformModelError.notInstalled("Test Model"))
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć", "a missing or broken model must still paste what was said")
    }

    func testCancellation_returnsTheRawTranscript() async {
        let local = LocalRecorder()
        local.result = .failure(CancellationError())
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć")
    }

    func testReasoningTracesAreStripped() async {
        let local = LocalRecorder()
        local.result = .success("<think>let me think</think>Cześć.")
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć.")
    }

    func testAnEmptyAnswerIsRejected() async {
        let local = LocalRecorder()
        local.result = .success("<think>nothing useful</think>")
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć")
    }

    /// Both switches off is the default install: no model is resolved at all, so
    /// no weights can be loaded by a dictation that asked for nothing.
    func testBothSwitchesOff_resolveNoModelAndMakeNoCall() async {
        for language in ["pl", "en"] {
            let local = LocalRecorder()
            let subject = service(
                local: local,
                settings: GateSettings(tone: false, cleanUp: false, toneMode: .neutral),
                model: { _ in
                    XCTFail("no model may be resolved when nothing is switched on")
                    return TransformModelManager.shared.defaultModel
                }
            )

            let text = language == "pl" ? "Cześć, jak się masz?" : "Please send the report."
            let result = await subject.transformIfEnabled(text, sourceLanguage: language)

            XCTAssertEqual(result, text)
            XCTAssertTrue(local.models.isEmpty, "\(language): no model call")
        }
    }

    // MARK: - Which model a language runs on

    /// The model choice is a **preference**, resolved from what is on disk:
    /// Polish takes the 8B when it is installed and the shipped model when it is
    /// not, and English always takes the shipped model. Nothing is refused for a
    /// missing 8B, and nothing is substituted silently.
    func testPolishPrefersTheEightBeeAndUsesTheShippedModelWithoutIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-preference-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data(repeating: 0x5A, count: 512)
        let shipped = TransformModel(
            id: TransformModelManager.defaultModelID,
            displayName: "Shipped",
            fileName: "shipped.gguf",
            downloadURL: URL(string: "https://example.invalid/shipped.gguf")!,
            sha256: sha256(payload),
            sizeBytes: Int64(payload.count),
            memoryBytes: 1,
            licence: "Apache-2.0",
            source: "test"
        )
        let eightBee = TransformModel(
            id: TransformModelManager.polishOutputModelID,
            displayName: "Eight Bee",
            fileName: "8b.gguf",
            downloadURL: URL(string: "https://example.invalid/8b.gguf")!,
            sha256: sha256(payload),
            sizeBytes: Int64(payload.count),
            memoryBytes: 5,
            licence: "Apache-2.0",
            source: "test"
        )
        let manager = TransformModelManager(directory: directory, catalogue: [shipped, eightBee])

        // Neither installed: Polish has to use the shipped model. Nothing is
        // refused, and the caller is told which model it will really run on.
        XCTAssertFalse(manager.isPolishModelInstalled)
        XCTAssertEqual(manager.model(forSpokenLanguage: .polish).id, shipped.id)
        XCTAssertEqual(manager.model(forSpokenLanguage: .english).id, shipped.id)
        // A tone rewrite prefers the larger model in BOTH languages while it is
        // absent, and falls back to the shipped one — nothing is refused.
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .formal)).id, shipped.id)
        XCTAssertEqual(manager.model(for: .tone(language: .polish, tone: .casual)).id, shipped.id)
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .neutral)).id, shipped.id)

        // Install the 8B: Polish now prefers it, English does not move.
        let source = directory.appendingPathComponent("downloaded.gguf")
        try payload.write(to: source)
        try manager.install(fileAt: source, model: eightBee)
        XCTAssertTrue(manager.isPolishModelInstalled)
        XCTAssertEqual(manager.model(forSpokenLanguage: .polish).id, eightBee.id)
        XCTAssertEqual(manager.model(forSpokenLanguage: .english).id, shipped.id)
        // Tone now runs on the 8B in both languages, clean-up alone does not move.
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .formal)).id, eightBee.id,
                       "an English tone rewrite runs on the 8B when it is installed")
        XCTAssertEqual(manager.model(for: .tone(language: .polish, tone: .formal)).id, eightBee.id)
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .formal)).id, eightBee.id)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, shipped.id,
                       "English clean-up alone stays on the shipped model")

        TestFixtures.report("[transform] model preference: 8B absent → tone (both languages) and Polish "
                    + "clean-up on \(shipped.id); 8B installed → tone (both languages) and Polish clean-up on "
                    + "\(eightBee.id), English clean-up always on \(shipped.id)")
    }

    /// The service hands the language's own model to the runtime, so the
    /// preference is what the transform actually runs on.
    func testThePreferredModelIsTheOneTheRuntimeIsHanded() async {
        let eightBee = TransformModelManager.shared.polishModel
        let local = LocalRecorder()
        let subject = service(local: local, model: { policy in
            policy.language == .polish ? eightBee : TransformModelManager.shared.defaultModel
        })

        _ = await subject.transformIfEnabled("Cześć", sourceLanguage: "pl")
        XCTAssertEqual(local.models.map(\.id), [eightBee.id])

        _ = await subject.transformIfEnabled("Report", sourceLanguage: "en")
        XCTAssertEqual(
            local.models.map(\.id),
            [eightBee.id, TransformModelManager.defaultModelID],
            "English clean-up runs on the shipped model"
        )
    }

    private func sha256(_ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
