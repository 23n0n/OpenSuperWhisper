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
        var result: Result<String, Error> = .success("Please send the report.")
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

        let result = await subject.transformIfEnabled("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(result, "Please send the report.")
        // A tone turn is framed and delimited — the transcript is handed over
        // inside the delimiters, not as a bare request the model could obey.
        // That framing is the invariant here; the sentences themselves are
        // `TransformServiceTests`' business, not a copy pinned twice.
        let userTurn = local.userTexts.first ?? ""
        XCTAssertEqual(local.calls, 1)
        XCTAssertNotEqual(userTurn, "Please send the report.", "the transcript is not sent as it was dictated")
        XCTAssertTrue(userTurn.contains("<<<TRANSCRIPT\nPlease send the report.\nTRANSCRIPT>>>"), userTurn)
    }

    // MARK: - Response handling

    func testFailure_returnsTheRawTranscript() async {
        let local = LocalRecorder()
        local.result = .failure(TransformModelError.notInstalled("Test Model"))
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(result, "Please send the report.",
                       "a missing or broken model must still paste what was said")
    }

    func testCancellation_returnsTheRawTranscript() async {
        let local = LocalRecorder()
        local.result = .failure(CancellationError())
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(result, "Please send the report.")
    }

    func testReasoningTracesAreStripped() async {
        let local = LocalRecorder()
        local.result = .success("<think>let me think</think>Please send it.")
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(result, "Please send it.")
    }

    func testAnEmptyAnswerIsRejected() async {
        let local = LocalRecorder()
        local.result = .success("<think>nothing useful</think>")
        let subject = service(local: local)

        let result = await subject.transformIfEnabled("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(result, "Please send the report.")
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

    /// The model choice is a **preference**, resolved from what is on disk, and
    /// **the language is what makes it**: English takes S1-mini while it is
    /// installed and the floor while it is not, and the job — tone, clean-up, or
    /// both — does not change the answer. Nothing is refused for a missing
    /// optional model, and nothing is substituted silently.
    func testEnglishPrefersTheNormalizerAndTheFloorWithoutIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-preference-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data(repeating: 0x5A, count: 512)
        let shipped = TransformModel(
            id: TransformModelManager.defaultModelID,
            displayName: "Shipped",
            fileName: "shipped.gguf",
            style: .instruction,
            downloadURL: URL(string: "https://example.invalid/shipped.gguf")!,
            sha256: sha256(payload),
            sizeBytes: Int64(payload.count),
            memoryBytes: 1,
            licence: "Apache-2.0",
            source: "test"
        )
        let normalizer = TransformModel(
            id: TransformModelManager.normalizerModelID,
            displayName: "S1-mini",
            fileName: "s1-mini.gguf",
            style: .normalizer,
            downloadURL: URL(string: "https://example.invalid/s1-mini.gguf")!,
            sha256: sha256(payload),
            sizeBytes: Int64(payload.count),
            memoryBytes: 5,
            licence: "Apache-2.0",
            source: "test"
        )
        let manager = TransformModelManager(directory: directory, catalogue: [shipped, normalizer])

        // Neither installed: English runs on the floor, whatever the switches
        // asked for. Nothing is refused for a missing optional model, and the
        // caller is told which model it will really run on.
        XCTAssertFalse(manager.isNormalizerInstalled)
        XCTAssertEqual(manager.model(forSpokenLanguage: .english).id, shipped.id)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, shipped.id)
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .formal)).id, shipped.id)
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .neutral)).id, shipped.id)

        // The record-start warm-up resolves through the same function, so it
        // warms what the next dictation will use rather than a model nothing
        // then asks for.
        XCTAssertEqual(
            manager.model(for: TransformRuntime.warmUpPolicy(toneEnabled: true, toneMode: .neutral)).id,
            shipped.id,
            "with the normalizer missing, the warm-up warms the floor"
        )

        // Install the normalizer: **every** English job moves onto it. The job
        // does not decide — tone alone, clean-up alone and both together all
        // resolve to the English backend.
        let source = directory.appendingPathComponent("downloaded.gguf")
        try payload.write(to: source)
        try manager.install(fileAt: source, model: normalizer)
        XCTAssertTrue(manager.isNormalizerInstalled)
        XCTAssertEqual(manager.model(forSpokenLanguage: .english).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .formal)).id, normalizer.id,
                       "an English tone rewrite runs on the normalizer when it is installed")
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .casual)).id, normalizer.id)
        XCTAssertEqual(
            manager.model(for: TransformRuntime.warmUpPolicy(toneEnabled: false, toneMode: .neutral)).id,
            normalizer.id,
            "clean-up alone warms the same backend: the language is what chooses"
        )

        TestFixtures.report("[transform] model preference: English runs on \(shipped.id) while the "
                    + "normalizer is missing and on \(normalizer.id) once it is installed, for tone and "
                    + "clean-up alike; the warm-up warms the same one")
    }

    /// The English-only gate did not delete Polish's row. `model(forSpokenLanguage:)`
    /// still answers for Polish — the 8B when it is installed, the floor when it
    /// is not — so a flip back of the one decision that changed
    /// (`TransformPolicy.resolve`) finds the rest of the table as it was.
    func testPolishKeepsItsRowForAFlipBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-preference-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TransformModelManager(
            directory: directory,
            catalogue: TransformModelManager.availableModels
        )

        XCTAssertFalse(manager.isPolishModelInstalled)
        XCTAssertEqual(manager.model(forSpokenLanguage: .polish).id, TransformModelManager.defaultModelID,
                       "Polish's row still falls back to the floor rather than being refused")
        XCTAssertEqual(manager.model(for: .cleanUp(language: .polish)).id, TransformModelManager.defaultModelID)
        XCTAssertEqual(manager.model(for: .tone(language: .polish, tone: .formal)).id,
                       TransformModelManager.defaultModelID)
        TestFixtures.report("[transform] Polish still resolves through the same table: "
                    + "\(TransformModelManager.defaultModelID) without the 8B, "
                    + "\(TransformModelManager.polishOutputModelID) with it")
    }

    /// The service hands the **policy's** model to the runtime, so the preference
    /// is what the transform actually runs on. The policy carries the language,
    /// and the language carries the model.
    func testThePreferredModelIsTheOneTheRuntimeIsHanded() async {
        let normalizer = TransformModelManager.shared.normalizerModel
        let local = LocalRecorder()
        let subject = service(local: local, model: { policy in
            policy.language == .english ? normalizer : TransformModelManager.shared.defaultModel
        })

        _ = await subject.transformIfEnabled("Please send the report.", sourceLanguage: "en")
        XCTAssertEqual(local.models.map(\.id), [normalizer.id])

        // A Polish dictation is not handed to any model at all.
        _ = await subject.transformIfEnabled("Cześć", sourceLanguage: "pl")
        XCTAssertEqual(local.models.map(\.id), [normalizer.id],
                       "Polish resolves no model, so the runtime is handed nothing more")
    }

    private func sha256(_ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
