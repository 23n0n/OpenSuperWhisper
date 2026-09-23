import XCTest
@testable import OpenSuperWhisper

/// A `URLProtocol` stub that lets the suite drive `TranslationService`'s network
/// layer without opening a real socket. It records whether a request was
/// actually attempted so tests can distinguish "attempted and failed" from
/// "never attempted".
final class StubURLProtocol: URLProtocol {

    enum Outcome {
        case success(statusCode: Int, body: Data)
        case failure(Error)
        /// Never responds; used to exercise task cancellation.
        case hang
    }

    private static let lock = NSLock()
    private static var _outcome: Outcome = .failure(URLError(.cannotConnectToHost))
    private static var _requestCount = 0
    private static var _lastRequest: URLRequest?

    static var outcome: Outcome {
        get { lock.lock(); defer { lock.unlock() }; return _outcome }
        set { lock.lock(); _outcome = newValue; lock.unlock() }
    }

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }; return _requestCount
    }

    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }; return _lastRequest
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _outcome = .failure(URLError(.cannotConnectToHost))
        _requestCount = 0
        _lastRequest = nil
    }

    private static func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        _requestCount += 1
        _lastRequest = request
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.record(request)

        switch StubURLProtocol.outcome {
        case .success(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty {
                client?.urlProtocol(self, didLoad: body)
            }
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hang:
            break
        }
    }

    override func stopLoading() {}
}

final class TranslationServiceTests: XCTestCase {

    // The real reasoning tags, built from Unicode scalars exactly like the
    // production code. Never use a literal angle-bracket tag here: the round-1
    // literal was corrupted and the tests silently proved nothing.
    private let openThinkTag = "\u{3C}think\u{3E}"
    private let closeThinkTag = "\u{3C}/think\u{3E}"
    private let openMarkupTag = "\u{3C}thinking\u{3E}"
    private let closeMarkupTag = "\u{3C}/thinking\u{3E}"
    private let openReasoningTag = "\u{3C}reasoning\u{3E}"
    private let closeReasoningTag = "\u{3C}/reasoning\u{3E}"
    private let endThinkToken = "<\u{FF5C}end\u{2581}of\u{2581}thinking\u{FF5C}>"

    // AppPreferences reads/writes `UserDefaults.standard` internally, so the
    // suite snapshots and restores every preference it touches in
    // setUp/tearDown (crash-mid-test is the only case this cannot repair).
    private var savedTranslateEnabled = false
    private var savedToneMode: ToneMode = .neutral
    private var savedEndpoint = ""
    private var savedModel = ""
    private var savedTimeout: Double = 8
    private var savedAddSpaceAfterSentence = true

    // Every test drives an instance whose session points at the stub. The
    // default stub outcome is an always-failing transport, so a test that
    // forgets to set an outcome still cannot reach the real network.
    private var service: TranslationService!

    override func setUp() {
        super.setUp()
        let prefs = AppPreferences.shared
        savedTranslateEnabled = prefs.translateEnabled
        savedToneMode = prefs.transformToneMode
        savedEndpoint = prefs.transformEndpoint
        savedModel = prefs.transformModel
        savedTimeout = prefs.transformTimeout
        savedAddSpaceAfterSentence = prefs.addSpaceAfterSentence
        prefs.translateEnabled = false

        StubURLProtocol.reset()
        service = TranslationService(urlSession: makeStubbedSession())
    }

    override func tearDown() {
        let prefs = AppPreferences.shared
        prefs.translateEnabled = savedTranslateEnabled
        prefs.transformToneMode = savedToneMode
        prefs.transformEndpoint = savedEndpoint
        prefs.transformModel = savedModel
        prefs.transformTimeout = savedTimeout
        prefs.addSpaceAfterSentence = savedAddSpaceAfterSentence

        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func enableTranslation(
        endpoint: String = "http://127.0.0.1:1919/v1/chat/completions",
        timeout: Double = 8
    ) {
        let prefs = AppPreferences.shared
        prefs.translateEnabled = true
        prefs.transformEndpoint = endpoint
        prefs.transformTimeout = timeout
    }

    private func makeResponse(content: String?, reasoning: String? = nil) throws -> Data {
        var message: [String: Any] = [:]
        if let content { message["content"] = content }
        if let reasoning { message["reasoning_content"] = reasoning }
        let object: [String: Any] = ["choices": [["message": message]]]
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - buildRequestBody

    func testBuildRequestBody_includesModelMessagesAndThinkingDisabled() throws {
        let data = try TranslationService.buildRequestBody(
            text: "Cześć, jak się masz?",
            tone: .neutral,
            model: "test-model"
        )
        let json = try jsonObject(from: data)

        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["temperature"] as? Double, 0.2)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "Cześć, jak się masz?")

        let system = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(system.contains("/no_think"))
        XCTAssertTrue(system.contains(ToneMode.neutral.instruction))

        let kwargs = try XCTUnwrap(json["chat_template_kwargs"] as? [String: Bool])
        XCTAssertEqual(kwargs["enable_thinking"], false)
    }

    func testBuildRequestBody_eachToneIncludesItsInstruction() throws {
        for tone in ToneMode.allCases {
            let data = try TranslationService.buildRequestBody(text: "tekst", tone: tone, model: "m")
            let json = try jsonObject(from: data)
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let system = try XCTUnwrap(messages.first?["content"] as? String)
            XCTAssertTrue(
                system.contains(tone.instruction),
                "System prompt missing instruction for tone \(tone.rawValue)"
            )
        }
    }

    // MARK: - parseContent

    func testParseContent_returnsTrimmedContent() throws {
        let data = try makeResponse(content: "  Hello world.  ")
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Hello world.")
    }

    func testParseContent_stripsQwen3ThinkBlock() throws {
        let content = openThinkTag + "internal reasoning" + endThinkToken + "Visible English."
        let data = try makeResponse(content: content)
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Visible English.")
    }

    func testParseContent_stripsClosedThinkTagBlock() throws {
        let content = openThinkTag + "hidden reasoning" + closeThinkTag + "Visible English."
        let data = try makeResponse(content: content)
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Visible English.")
    }

    func testParseContent_stripsUnterminatedTrailingThinkBlock() throws {
        let content = "Visible first. " + openThinkTag + "trailing reasoning"
        let data = try makeResponse(content: content)
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Visible first.")
    }

    func testParseContent_stripsThinkingTagBlock() throws {
        let content = openMarkupTag + "hidden reasoning" + closeMarkupTag + "Visible English."
        let data = try makeResponse(content: content)
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Visible English.")
    }

    func testParseContent_stripsReasoningTagBlock() throws {
        let content = openReasoningTag + "hidden reasoning" + closeReasoningTag + "Visible English."
        let data = try makeResponse(content: content)
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Visible English.")
    }

    func testStripReasoning_removesBareEndTokenAnywhere() {
        XCTAssertEqual(
            TranslationService.stripReasoning(from: "Before " + endThinkToken + " after"),
            "Before  after",
            "An end token with no opener must be removed wherever it appears"
        )
        XCTAssertEqual(
            TranslationService.stripReasoning(from: endThinkToken + "Visible English."),
            "Visible English."
        )
    }

    func testStripReasoning_removesOrphanClosingTags() {
        for tag in [closeThinkTag, closeMarkupTag, closeReasoningTag] {
            XCTAssertEqual(
                TranslationService.stripReasoning(from: tag + "Visible English."),
                "Visible English.",
                "A leading \(tag) with no opener must be removed"
            )
            XCTAssertEqual(
                TranslationService.stripReasoning(from: "Visible " + tag + " English."),
                "Visible  English.",
                "A standalone \(tag) with no opener must be removed"
            )
        }
    }

    func testStripReasoning_bareWordThinkingAndReasoningSurvive() {
        let content = "I keep thinking and reasoning about the translation."
        XCTAssertEqual(TranslationService.stripReasoning(from: content), content)
    }

    func testParseContent_wordThinkingWithoutTags_isUnchanged() throws {
        // Guards against over-truncation: a bare word `thinking` must survive.
        let content = "I keep thinking about the translation."
        let data = try makeResponse(content: content)
        XCTAssertEqual(try TranslationService.parseContent(from: data), content)
    }

    func testStripReasoning_wordThinkingWithoutTags_isUnchanged() {
        let content = "I keep thinking about the translation."
        XCTAssertEqual(TranslationService.stripReasoning(from: content), content)
    }

    func testParseContent_reasoningOnlyWithEmptyContent_throws() throws {
        let data = try makeResponse(content: "", reasoning: "only reasoning here")
        XCTAssertThrowsError(try TranslationService.parseContent(from: data))
    }

    func testParseContent_missingContent_throws() throws {
        let data = try makeResponse(content: nil, reasoning: "only reasoning here")
        XCTAssertThrowsError(try TranslationService.parseContent(from: data))
    }

    func testParseContent_emptyContent_throws() throws {
        let data = try makeResponse(content: "   \n  ")
        XCTAssertThrowsError(try TranslationService.parseContent(from: data))
    }

    func testParseContent_emptyChoices_throws() throws {
        let data = try JSONSerialization.data(withJSONObject: ["choices": []])
        XCTAssertThrowsError(try TranslationService.parseContent(from: data))
    }

    func testParseContent_malformedJSON_throws() {
        XCTAssertThrowsError(try TranslationService.parseContent(from: Data("not json".utf8)))
    }

    func testParseContent_emptyData_throws() {
        XCTAssertThrowsError(try TranslationService.parseContent(from: Data()))
    }

    // MARK: - transformIfEnabled fallbacks

    func testTransformIfEnabled_disabled_returnsRawInputWithoutNetwork() async {
        AppPreferences.shared.translateEnabled = false
        StubURLProtocol.reset()

        let result = await service.transformIfEnabled("Cześć")

        XCTAssertEqual(result, "Cześć")
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "Disabled translation must not hit the network")
    }

    func testTransformIfEnabled_emptyText_returnsEmptyWithoutNetwork() async {
        enableTranslation()
        StubURLProtocol.reset()

        let result = await service.transformIfEnabled("")

        XCTAssertEqual(result, "")
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "Empty input must not hit the network")
    }

    func testTransformIfEnabled_requestFailure_returnsRawInputAndAttemptsRequest() async {
        enableTranslation()
        StubURLProtocol.outcome = .failure(URLError(.cannotConnectToHost))

        let result = await service.transformIfEnabled("Cześć")

        XCTAssertEqual(result, "Cześć")
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "The request was never attempted")
    }

    // MARK: - transform (stubbed transport)

    func testTransform_successfulResponse_returnsParsedContent() async throws {
        enableTranslation()
        let body = try makeResponse(content: "Hello world.")
        StubURLProtocol.outcome = .success(statusCode: 200, body: body)

        let result = try await service.transform("Cześć")

        XCTAssertEqual(result, "Hello world.")
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(
            StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    func testTransform_non2xxResponse_throwsHTTPError() async {
        enableTranslation()
        StubURLProtocol.outcome = .success(statusCode: 500, body: Data())

        do {
            _ = try await service.transform("Cześć")
            XCTFail("Expected an httpError")
        } catch let error as TranslationError {
            guard case .httpError(let statusCode) = error else {
                return XCTFail("Unexpected TranslationError: \(error)")
            }
            XCTAssertEqual(statusCode, 500)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTransform_invalidEndpoint_throwsInvalidEndpoint() async {
        enableTranslation(endpoint: "")

        do {
            _ = try await service.transform("Cześć")
            XCTFail("Expected an invalidEndpoint error")
        } catch TranslationError.invalidEndpoint {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransform_trimsEndpointWhitespaceBeforeParsing() async throws {
        enableTranslation(endpoint: "  http://127.0.0.1:1919/v1/chat/completions  ")
        StubURLProtocol.outcome = .success(
            statusCode: 200,
            body: try makeResponse(content: "Hello.")
        )

        _ = try await service.transform("Cześć")

        XCTAssertEqual(
            StubURLProtocol.lastRequest?.url?.absoluteString,
            "http://127.0.0.1:1919/v1/chat/completions"
        )
    }

    func testTransform_clampsTimeoutToValidRange() async throws {
        enableTranslation(timeout: 0)
        StubURLProtocol.outcome = .success(
            statusCode: 200,
            body: try makeResponse(content: "Hello.")
        )

        _ = try await service.transform("Cześć")

        let timeout = try XCTUnwrap(StubURLProtocol.lastRequest?.timeoutInterval)
        XCTAssertEqual(timeout, 1, accuracy: 0.001, "A 0s timeout must be clamped up to 1s")
    }

    func testTransform_clampsTimeoutUpperBoundAndPassesThroughInRange() async throws {
        StubURLProtocol.outcome = .success(
            statusCode: 200,
            body: try makeResponse(content: "Hello.")
        )

        enableTranslation(timeout: 999)
        _ = try await service.transform("Cześć")
        let upper = try XCTUnwrap(StubURLProtocol.lastRequest?.timeoutInterval)
        XCTAssertEqual(upper, 120, accuracy: 0.001, "A 999s timeout must be clamped down to 120s")

        enableTranslation(timeout: 8)
        _ = try await service.transform("Cześć")
        let inRange = try XCTUnwrap(StubURLProtocol.lastRequest?.timeoutInterval)
        XCTAssertEqual(inRange, 8, accuracy: 0.001, "An in-range timeout must pass through unchanged")
    }

    func testTransform_taskCancellation_failsPromptly() async throws {
        enableTranslation(timeout: 5)
        StubURLProtocol.outcome = .hang

        let task = Task { try await service.transform("Cześć") }

        // Wait until the in-flight request reaches the stub.
        let deadline = Date().addingTimeInterval(5)
        while StubURLProtocol.requestCount == 0 && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(StubURLProtocol.requestCount, 0, "Request never reached the stub")

        let cancelStart = Date()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected the cancelled transform to fail")
        } catch is CancellationError {
            // expected
        } catch let error as URLError where error.code == .cancelled {
            // expected
        } catch {
            XCTFail("Expected CancellationError or URLError(.cancelled), got: \(error)")
        }

        XCTAssertLessThan(
            Date().timeIntervalSince(cancelStart),
            3.0,
            "Cancellation should not wait for the request timeout"
        )
    }

    // MARK: - Production default session

    func testProductionDefaultUsesSharedSession() {
        XCTAssertTrue(
            TranslationService.shared.urlSession === URLSession.shared,
            "The shared service must default to URLSession.shared"
        )
        XCTAssertTrue(
            TranslationService().urlSession === URLSession.shared,
            "A default-constructed service must use URLSession.shared"
        )
    }

    // MARK: - Ordering contract (translate first, then post-process)

    @MainActor
    func testApplyPostProcessing_addsTrailingSpaceToTranslatedEnglish() {
        AppPreferences.shared.addSpaceAfterSentence = true
        XCTAssertEqual(IndicatorViewModel.applyPostProcessing("Hello world."), "Hello world. ")
    }

    @MainActor
    func testApplyPostProcessing_disabled_leavesTextUnchanged() {
        AppPreferences.shared.addSpaceAfterSentence = false
        XCTAssertEqual(IndicatorViewModel.applyPostProcessing("Hello world."), "Hello world.")
    }

    @MainActor
    func testApplyPostProcessing_unpunctuatedTextUnchanged() {
        AppPreferences.shared.addSpaceAfterSentence = true
        XCTAssertEqual(IndicatorViewModel.applyPostProcessing("Cześć"), "Cześć")
    }

    // MARK: - ToneMode

    func testToneMode_rawValueRoundTrip() {
        XCTAssertEqual(ToneMode(rawValue: ToneMode.neutral.rawValue), .neutral)
        XCTAssertEqual(ToneMode(rawValue: ToneMode.formal.rawValue), .formal)
        XCTAssertEqual(ToneMode(rawValue: ToneMode.casual.rawValue), .casual)
        XCTAssertNil(ToneMode(rawValue: "bogus"))
        XCTAssertEqual(ToneMode.allCases.count, 3)
    }

    func testAppPreferences_toneModeRoundTrip() {
        AppPreferences.shared.transformToneMode = .casual
        XCTAssertEqual(AppPreferences.shared.transformToneMode, .casual)

        AppPreferences.shared.transformToneMode = .formal
        XCTAssertEqual(AppPreferences.shared.transformToneMode, .formal)
    }
}
