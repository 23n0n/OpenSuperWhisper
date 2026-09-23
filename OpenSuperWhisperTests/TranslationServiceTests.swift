import XCTest
@testable import OpenSuperWhisper

final class TranslationServiceTests: XCTestCase {

    private let endThinkMarker = "<\u{FF5C}end\u{2581}of\u{2581}thinking\u{FF5C}>"

    private var savedTranslateEnabled = false
    private var savedToneMode: ToneMode = .neutral
    private var savedEndpoint = ""
    private var savedModel = ""
    private var savedTimeout: Double = 8

    override func setUp() {
        super.setUp()
        let prefs = AppPreferences.shared
        savedTranslateEnabled = prefs.translateEnabled
        savedToneMode = prefs.transformToneMode
        savedEndpoint = prefs.transformEndpoint
        savedModel = prefs.transformModel
        savedTimeout = prefs.transformTimeout
        prefs.translateEnabled = false
    }

    override func tearDown() {
        let prefs = AppPreferences.shared
        prefs.translateEnabled = savedTranslateEnabled
        prefs.transformToneMode = savedToneMode
        prefs.transformEndpoint = savedEndpoint
        prefs.transformModel = savedModel
        prefs.transformTimeout = savedTimeout
        super.tearDown()
    }

    // MARK: - Helpers

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
        let content = " thinkinginternal reasoning\(endThinkMarker)Visible English."
        let data = try makeResponse(content: content)
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Visible English.")
    }

    func testParseContent_stripsStandardThinkTags() throws {
        let data = try makeResponse(content: " thinkinghidden reasoning<｜end▁of▁thinking｜>Visible.")
        XCTAssertEqual(try TranslationService.parseContent(from: data), "Visible.")
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

    func testTransformIfEnabled_disabled_returnsRawInput() async {
        AppPreferences.shared.translateEnabled = false
        let result = await TranslationService.shared.transformIfEnabled("Cześć")
        XCTAssertEqual(result, "Cześć")
    }

    func testTransformIfEnabled_emptyText_returnsEmpty() async {
        AppPreferences.shared.translateEnabled = true
        let result = await TranslationService.shared.transformIfEnabled("")
        XCTAssertEqual(result, "")
    }

    func testTransformIfEnabled_requestFailure_returnsRawInput() async {
        AppPreferences.shared.translateEnabled = true
        AppPreferences.shared.transformEndpoint = "http://127.0.0.1:1/v1/chat/completions"
        AppPreferences.shared.transformTimeout = 2.0
        let result = await TranslationService.shared.transformIfEnabled("Cześć")
        XCTAssertEqual(result, "Cześć")
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
        let original = AppPreferences.shared.transformToneMode
        defer { AppPreferences.shared.transformToneMode = original }

        AppPreferences.shared.transformToneMode = .casual
        XCTAssertEqual(AppPreferences.shared.transformToneMode, .casual)

        AppPreferences.shared.transformToneMode = .formal
        XCTAssertEqual(AppPreferences.shared.transformToneMode, .formal)
    }
}
