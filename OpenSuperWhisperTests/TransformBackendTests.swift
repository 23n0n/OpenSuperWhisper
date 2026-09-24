import XCTest
@testable import OpenSuperWhisper

/// Which backend `transformIfEnabled` uses, and what the built-in one does with
/// the model's answer. The built-in runtime is driven through an injected local
/// transform, so no test here loads real weights.
final class TransformBackendTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private final class LocalRecorder {
        var systemPrompts: [String] = []
        var userTexts: [String] = []
        /// The backend each call was routed to, so a test can assert which model
        /// a direction resolved to — by name, without loading any weights.
        var models: [TransformModel] = []
        var result: Result<String, Error> = .success("Hello from the app.")
    }

    private func service(
        local: LocalRecorder,
        externalEndpoint: Bool,
        stubContent: String? = nil,
        settings: GateSettings = GateSettings(
            translate: true,
            tone: false,
            cleanUp: false,
            toneMode: .neutral,
            target: .english
        )
    ) -> TranslationService {
        if let stubContent {
            StubURLProtocol.outcome = .success(
                statusCode: 200,
                body: try! JSONSerialization.data(
                    withJSONObject: ["choices": [["message": ["content": stubContent]]]]
                )
            )
        } else {
            StubURLProtocol.outcome = .failure(URLError(.cannotConnectToHost))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranslationService(
            urlSession: URLSession(configuration: configuration),
            localTransform: { systemPrompt, userText, model in
                local.systemPrompts.append(systemPrompt)
                local.userTexts.append(userText)
                local.models.append(model)
                return try local.result.get()
            },
            usesExternalEndpoint: { externalEndpoint },
            gateSettings: { settings }
        )
    }

    // MARK: - Dispatch

    func testBuiltInRuntimeIsTheDefault_andNeverTouchesTheNetwork() async {
        let local = LocalRecorder()
        let service = service(local: local, externalEndpoint: false, stubContent: "from the endpoint")

        let result = await service.transformIfEnabled("Cześć, jak się masz?", sourceLanguage: "pl")

        XCTAssertEqual(result, "Hello from the app.")
        XCTAssertEqual(local.systemPrompts, [TranslationService.systemPrompt(for: .translate(from: .polish, to: .english), cleanUp: false)])
        XCTAssertEqual(local.userTexts, ["Cześć, jak się masz?"])
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "the default backend is in process")
    }

    func testExternalEndpointOverride_usesHTTP() async {
        let local = LocalRecorder()
        let service = service(local: local, externalEndpoint: true, stubContent: "from the endpoint")

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "from the endpoint")
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
        XCTAssertTrue(local.systemPrompts.isEmpty, "the built-in runtime must not run as well")
    }

    /// The stored switch is what production reads; this is the only test that
    /// writes it, and nothing else in the suite depends on its value.
    func testStoredSwitchChoosesTheBackend() async {
        let prefs = AppPreferences.shared
        let saved = prefs.transformUseExternalEndpoint
        defer { prefs.transformUseExternalEndpoint = saved }

        let local = LocalRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.reset()
        StubURLProtocol.outcome = .success(
            statusCode: 200,
            body: try! JSONSerialization.data(
                withJSONObject: ["choices": [["message": ["content": "from the endpoint"]]]]
            )
        )

        // Production backend selection (no injected selector), with only the
        // gate inputs pinned so the test does not depend on the shared switches.
        let service = TranslationService(
            urlSession: URLSession(configuration: configuration),
            localTransform: { _, _, _ in local.systemPrompts.append("called"); return "in process" },
            gateSettings: {
                GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .english)
            }
        )

        prefs.transformUseExternalEndpoint = true
        let overridden = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")
        XCTAssertEqual(overridden, "from the endpoint")
        XCTAssertEqual(StubURLProtocol.requestCount, 1)

        prefs.transformUseExternalEndpoint = false
        let builtIn = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")
        XCTAssertEqual(builtIn, "in process")
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "the switch off must not reach the network")
    }

    // MARK: - Built-in response handling

    func testBuiltInRuntime_failureReturnsTheRawTranscript() async {
        let local = LocalRecorder()
        local.result = .failure(TransformModelError.notInstalled("Test Model"))
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć", "a missing or broken model must still paste what was said")
    }

    func testBuiltInRuntime_cancellationReturnsTheRawTranscript() async {
        let local = LocalRecorder()
        local.result = .failure(CancellationError())
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć")
    }

    func testBuiltInRuntime_stripsReasoningTraces() async {
        let local = LocalRecorder()
        local.result = .success("<think>let me think</think>Hello there.")
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Hello there.")
    }

    func testBuiltInRuntime_rejectsAnEmptyAnswer() async {
        let local = LocalRecorder()
        local.result = .success("<think>nothing useful</think>")
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć")
    }

    /// The target rule holds for the built-in runtime too: a dictation already
    /// in the target language never reaches the model, even with tone on.
    func testSameLanguageNeverReachesTheBuiltInRuntime() async {
        let local = LocalRecorder()
        local.result = .success("should never be produced")
        let service = service(
            local: local,
            externalEndpoint: false,
            settings: GateSettings(translate: true, tone: true, cleanUp: false, toneMode: .formal, target: .english)
        )

        let result = await service.transformIfEnabled(
            "Please send the report.",
            sourceLanguage: "en"
        )

        XCTAssertEqual(result, "Please send the report.")
        XCTAssertTrue(
            local.systemPrompts.isEmpty,
            "speech already in the target language must not reach the model"
        )
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    /// The demanded reverse direction reaches the built-in runtime with the
    /// English→Polish prompt.
    func testBuiltInRuntime_translatesIntoTheTargetLanguage() async {
        let local = LocalRecorder()
        local.result = .success("Proszę wysłać raport.")
        let service = service(
            local: local,
            externalEndpoint: false,
            settings: GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .polish)
        )

        let result = await service.transformIfEnabled(
            "Please send the report.",
            sourceLanguage: "en"
        )

        XCTAssertEqual(result, "Proszę wysłać raport.")
        XCTAssertEqual(
            local.systemPrompts,
            [TranslationService.systemPrompt(for: .translate(from: .english, to: .polish), cleanUp: false)]
        )
    }

    // MARK: - Routing by output direction

    /// Polish output — the direction the shipped 1.5B was measured unreliable
    /// on — must resolve to the larger backend, by name.
    func testPolishOutputResolvesToThePolishBackend() async {
        let local = LocalRecorder()
        local.result = .success("Proszę wysłać raport.")
        let service = service(
            local: local,
            externalEndpoint: false,
            settings: GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .polish)
        )

        _ = await service.transformIfEnabled("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(
            local.models.map(\.id),
            [TransformModelManager.polishOutputModelID],
            "English→Polish must run on the Polish backend"
        )
        TestFixtures.report("[routing] en→pl backend: \(local.models.map(\.id).joined(separator: ", "))")
    }

    /// The daily direction keeps the shipped model: Polish→English was measured
    /// 8/8 correct at ~0.3 s and ~1.1 GB, and this change must not move it.
    func testEnglishOutputKeepsTheShippedBackend() async {
        let local = LocalRecorder()
        local.result = .success("Please send the report.")
        let service = service(
            local: local,
            externalEndpoint: false,
            settings: GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .english)
        )

        let result = await service.transformIfEnabled("Proszę wysłać raport.", sourceLanguage: "pl")

        XCTAssertEqual(result, "Please send the report.")
        XCTAssertEqual(
            local.models.map(\.id),
            [TransformModelManager.defaultModelID],
            "Polish→English must stay on the shipped 1.5B"
        )
        TestFixtures.report("[routing] pl→en backend: \(local.models.map(\.id).joined(separator: ", "))")
    }

    /// A same-language clean-up writes the language that was spoken, so a Polish
    /// dictation cleaned up with a Polish target is Polish output and takes the
    /// Polish backend.
    func testPolishCleanUpResolvesToThePolishBackend() async {
        let local = LocalRecorder()
        local.result = .success("Proszę wysłać raport.")
        let service = service(
            local: local,
            externalEndpoint: false,
            settings: GateSettings(translate: true, tone: false, cleanUp: true, toneMode: .neutral, target: .polish)
        )

        _ = await service.transformIfEnabled("Prosze wyslac raport", sourceLanguage: "pl")

        XCTAssertEqual(
            local.models.map(\.id),
            [TransformModelManager.polishOutputModelID],
            "a Polish clean-up is Polish output"
        )
    }

    /// Speech already in the target language is pasted untouched — no model is
    /// even resolved, so no weights are loaded, for either target.
    func testSpokenLanguageEqualToTargetResolvesNoModelAtAll() async {
        for target in TransformLanguage.allCases {
            let local = LocalRecorder()
            let service = service(
                local: local,
                externalEndpoint: false,
                settings: GateSettings(translate: true, tone: true, cleanUp: false, toneMode: .formal, target: target)
            )

            let result = await service.transformIfEnabled(
                target == .polish ? "Proszę wysłać raport." : "Please send the report.",
                sourceLanguage: target == .polish ? "pl" : "en"
            )

            XCTAssertEqual(result, target == .polish ? "Proszę wysłać raport." : "Please send the report.")
            XCTAssertTrue(local.models.isEmpty, "\(target): spoken == target must not resolve a backend")
            XCTAssertTrue(local.systemPrompts.isEmpty, "\(target): spoken == target must not call a model")
            XCTAssertEqual(StubURLProtocol.requestCount, 0)
        }
    }

    /// The Polish backend is not installed: the call fails and the raw
    /// transcript is delivered. The small model is never asked to stand in for
    /// it — the routing recorder shows the only backend that was ever requested.
    func testMissingPolishBackendIsNeverSwappedForTheShippedOne() async {
        let local = LocalRecorder()
        local.result = .failure(
            TransformModelError.notInstalled(TransformModelManager.shared.model(forOutputLanguage: .polish).displayName)
        )
        let service = service(
            local: local,
            externalEndpoint: false,
            settings: GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .polish)
        )

        let result = await service.transformIfEnabled("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(result, "Please send the report.", "a missing backend must still deliver the transcript")
        XCTAssertEqual(local.models.map(\.id), [TransformModelManager.polishOutputModelID])
        XCTAssertFalse(
            local.models.contains { $0.id == TransformModelManager.defaultModelID },
            "the 1.5B must never be substituted for Polish"
        )
    }
}
