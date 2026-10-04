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
        model: @escaping (TransformPolicy) -> TransformModel = { _ in TransformModelStandIn.instruct }
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
                    return TransformModelStandIn.instruct
                }
            )

            let text = language == "pl" ? "Cześć, jak się masz?" : "Please send the report."
            let result = await subject.transformIfEnabled(text, sourceLanguage: language)

            XCTAssertEqual(result, text)
            XCTAssertTrue(local.models.isEmpty, "\(language): no model call")
        }
    }

    // MARK: - Which model a language runs on

    /// There is no model choice any more: one backend, and the job — tone,
    /// clean-up, or both — does not change it. What changes is only whether it is
    /// installed, and that is what decides whether the transform runs at all.
    func testEnglishAlwaysResolvesToTheOneBackend() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-preference-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data(repeating: 0x5A, count: 512)
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
        let manager = TransformModelManager(directory: directory, catalogue: [normalizer])

        // Nothing installed: the routing still answers with the one model, and
        // `isNormalizerInstalled` is what says the transform cannot run — the
        // runtime raises `notInstalled` with this name when a dictation asks.
        XCTAssertFalse(manager.isNormalizerInstalled)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .formal)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .neutral)).id, normalizer.id)

        // The record-start warm-up resolves through the same function, so it
        // warms what the next dictation will use rather than a model nothing
        // then asks for.
        XCTAssertEqual(
            manager.model(for: TransformRuntime.warmUpPolicy(toneEnabled: true, toneMode: .neutral)).id,
            normalizer.id,
            "the warm-up warms the one model"
        )

        // Installed: the same answer, now backed by weights on disk.
        let source = directory.appendingPathComponent("downloaded.gguf")
        try payload.write(to: source)
        try manager.install(fileAt: source, model: normalizer)
        XCTAssertTrue(manager.isNormalizerInstalled)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .formal)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .casual)).id, normalizer.id)

        TestFixtures.report("[transform] model resolution: every English job — tone, clean-up, both — "
                    + "resolves to \(normalizer.id), installed or not; a missing file is what the runtime "
                    + "refuses on")
    }

    /// Polish has no backend, and the catalogue says so rather than keeping a row
    /// nothing resolves to: the transform is English-only, so the one model the
    /// app offers is the one the English work runs on. A policy that carried
    /// Polish would be handed it too — there is nothing else — and
    /// `TransformPolicy.resolve` is what keeps such a policy from existing.
    func testPolishHasNoBackendOfItsOwn() throws {
        XCTAssertEqual(TransformModelManager.availableModels.map(\.id),
                       [TransformModelManager.normalizerModelID],
                       "one entry, and it is not a Polish model")
        XCTAssertNil(TransformPolicy.resolve(tone: true, cleanUp: true, language: "pl", toneMode: .formal),
                     "Polish never reaches a model, so it never resolves a policy either")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-preference-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TransformModelManager(
            directory: directory,
            catalogue: TransformModelManager.availableModels
        )

        XCTAssertEqual(manager.model(for: .cleanUp(language: .polish)).id, TransformModelManager.normalizerModelID,
                       "if a Polish policy ever existed, the one model is all it could run on")
        TestFixtures.report("[transform] Polish resolves through no backend of its own: the catalogue is "
                    + "\(TransformModelManager.availableModels.map(\.id).joined(separator: ", "))")
    }

    /// The service hands the **policy's** model to the runtime, so the preference
    /// is what the transform actually runs on. The policy carries the language,
    /// and the language carries the model.
    func testThePreferredModelIsTheOneTheRuntimeIsHanded() async {
        let normalizer = TransformModelManager.shared.normalizerModel
        let local = LocalRecorder()
        let subject = service(local: local, model: { policy in
            policy.language == .english ? normalizer : TransformModelManager.shared.normalizerModel
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
