import XCTest
@testable import OpenSuperWhisper

/// Which backend `transformIfEnabled` uses, and what the built-in one does with
/// the model's answer. The built-in runtime is driven through an injected local
/// transform, so no test here loads real weights.
final class TransformBackendTests: XCTestCase {

    private var savedTranslateEnabled = false
    private var savedToneEnabled = false
    private var savedToneMode = ToneMode.neutral

    override func setUp() {
        super.setUp()
        let prefs = AppPreferences.shared
        savedTranslateEnabled = prefs.translateEnabled
        savedToneEnabled = prefs.toneEnabled
        savedToneMode = prefs.transformToneMode
        prefs.translateEnabled = false
        prefs.toneEnabled = false
        StubURLProtocol.reset()
    }

    override func tearDown() {
        let prefs = AppPreferences.shared
        prefs.translateEnabled = savedTranslateEnabled
        prefs.toneEnabled = savedToneEnabled
        prefs.transformToneMode = savedToneMode
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private final class LocalRecorder {
        var systemPrompts: [String] = []
        var userTexts: [String] = []
        var result: Result<String, Error> = .success("Hello from the app.")
    }

    private func service(
        local: LocalRecorder,
        externalEndpoint: Bool,
        stubContent: String? = nil
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
            localTransform: { systemPrompt, userText in
                local.systemPrompts.append(systemPrompt)
                local.userTexts.append(userText)
                return try local.result.get()
            },
            usesExternalEndpoint: { externalEndpoint }
        )
    }

    private func enableTranslation() {
        AppPreferences.shared.translateEnabled = true
    }

    // MARK: - Dispatch

    func testBuiltInRuntimeIsTheDefault_andNeverTouchesTheNetwork() async {
        enableTranslation()
        let local = LocalRecorder()
        let service = service(local: local, externalEndpoint: false, stubContent: "from the endpoint")

        let result = await service.transformIfEnabled("Cześć, jak się masz?", sourceLanguage: "pl")

        XCTAssertEqual(result, "Hello from the app.")
        XCTAssertEqual(local.systemPrompts, [TranslationService.systemPrompt(for: .translate)])
        XCTAssertEqual(local.userTexts, ["Cześć, jak się masz?"])
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "the default backend is in process")
    }

    func testExternalEndpointOverride_usesHTTP() async {
        enableTranslation()
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
        enableTranslation()
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

        // Production construction: no injected selector.
        let service = TranslationService(
            urlSession: URLSession(configuration: configuration),
            localTransform: { _, _ in local.systemPrompts.append("called"); return "in process" }
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
        enableTranslation()
        let local = LocalRecorder()
        local.result = .failure(TransformModelError.notInstalled)
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć", "a missing or broken model must still paste what was said")
    }

    func testBuiltInRuntime_cancellationReturnsTheRawTranscript() async {
        enableTranslation()
        let local = LocalRecorder()
        local.result = .failure(CancellationError())
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć")
    }

    func testBuiltInRuntime_stripsReasoningTraces() async {
        enableTranslation()
        let local = LocalRecorder()
        local.result = .success("<think>let me think</think>Hello there.")
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Hello there.")
    }

    func testBuiltInRuntime_rejectsAnEmptyAnswer() async {
        enableTranslation()
        let local = LocalRecorder()
        local.result = .success("<think>nothing useful</think>")
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled("Cześć", sourceLanguage: "pl")

        XCTAssertEqual(result, "Cześć")
    }

    func testToneOnlyLanguageGuardAppliesInProcessToo() async {
        AppPreferences.shared.toneEnabled = true
        AppPreferences.shared.transformToneMode = .formal
        let local = LocalRecorder()
        local.result = .success("Proszę wysłać raport.")
        let service = service(local: local, externalEndpoint: false)

        let result = await service.transformIfEnabled(
            "Please send the report.",
            sourceLanguage: "en"
        )

        XCTAssertEqual(
            result,
            "Please send the report.",
            "a tone-only rewrite that switched language is discarded whichever backend produced it"
        )
    }
}
