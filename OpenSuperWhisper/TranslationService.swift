import Foundation

/// Tone applied to the transformed text — a translation into the target
/// language, or a same-language rewrite of English.
enum ToneMode: String, CaseIterable, Identifiable {
    case neutral
    case formal
    case casual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .formal: return "Formal"
        case .casual: return "Casual"
        }
    }

    /// One-line instruction appended to the system prompt.
    var instruction: String {
        switch self {
        case .neutral: return "Keep a neutral, natural tone."
        case .formal: return "Use a formal, professional tone."
        case .casual: return "Use a casual, conversational tone."
        }
    }
}

enum TranslationError: Error, LocalizedError {
    case invalidEndpoint
    case httpError(statusCode: Int)
    case emptyResponse
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "The translation endpoint URL is invalid."
        case .httpError(let statusCode): return "The translation endpoint returned HTTP \(statusCode)."
        case .emptyResponse: return "The translation endpoint returned an empty response."
        case .malformedResponse: return "The translation endpoint returned a malformed response."
        }
    }
}

/// The languages the transform can speak, and the one the user picks as its
/// target.
///
/// Only these two are ever translated or toned. A third language — and any
/// transcript the engine and the heuristic both fail to place — is pasted
/// unchanged, so the target is always one of the two the gate can act on.
enum TransformLanguage: String, CaseIterable, Identifiable {
    case english
    case polish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .polish: return "Polish"
        }
    }

    /// The transform language for a detector verdict, or `nil` when the
    /// detector has no usable signal.
    init?(verdict: LanguageDetector.Verdict) {
        switch verdict {
        case .english: self = .english
        case .polish: self = .polish
        case .unknown: return nil
        }
    }
}

/// Everything the transform gate reads from the preferences for one dictation.
///
/// Read on every call, so a switch flipped in Settings takes effect on the next
/// dictation — and injectable as one unit: the test suite runs classes in
/// parallel processes that share a single preference file, so a test that wants
/// to drive the decision table must not do it by writing those shared switches.
struct GateSettings: Equatable {
    var translate: Bool
    var tone: Bool
    var toneMode: ToneMode
    var target: TransformLanguage

    static var current: GateSettings {
        let prefs = AppPreferences.shared
        return GateSettings(
            translate: prefs.translateEnabled,
            tone: prefs.toneEnabled,
            toneMode: prefs.transformToneMode,
            target: prefs.transformTargetLanguage
        )
    }
}

/// What the transform gate decided to do with one dictation.
///
/// The absence of a value is the passthrough case: the raw transcript goes
/// straight to the keypress path, with no request, no tone text and no language
/// detection work. `TranslationService.transformIfEnabled` returns before it
/// builds any request for that case.
enum TransformPolicy: Equatable {
    /// `source` → `target`, with no tone wording in the prompt at all.
    case translate(from: TransformLanguage, to: TransformLanguage)
    /// `source` → `target`, then that tone.
    case translateWithTone(from: TransformLanguage, to: TransformLanguage, tone: ToneMode)

    /// The tone embedded in the prompt, if this policy sends any tone text.
    var promptTone: ToneMode? {
        switch self {
        case .translate: return nil
        case .translateWithTone(_, _, let tone): return tone
        }
    }

    /// The decision table for one dictation.
    ///
    /// * Both switches off ⇒ `nil`, and the caller never even looks up the
    ///   language.
    /// * Spoken language **equals** `target` ⇒ `nil`: there is nothing to
    ///   translate, so the transcript is pasted untouched and no model call is
    ///   made at all. Tone does not change that. A same-language rewrite is
    ///   exactly the mutation the captain complained about (`"Do it tomorrow."`
    ///   → `"I'll do it tomorrow."`), and a tone sentence only has a
    ///   translation to describe — see the class doc.
    /// * Spoken language **differs** from `target` and the translation switch is
    ///   on ⇒ the demanded direction, toned when the tone switch is on. Speech
    ///   the user did not ask to translate never reaches the model: every model
    ///   call rewrites it, which is the behaviour language awareness exists to
    ///   stop.
    /// * `unknown`, and any third language, always pass through. The design
    ///   report ranked a single unified "translate if Polish, otherwise return
    ///   unchanged" call for this case (measured 19/22, English identity only
    ///   7/10); it is deliberately not implemented. The case is rare — the
    ///   heuristic agreed with the engine on 16/16 real engine transcripts —
    ///   and pasting what was actually said is the safest outcome. This also
    ///   subsumes the report's "≤ 3 words" row: it only ever guarded transforms
    ///   of unknown-language text, and there are none left.
    static func resolve(
        translate: Bool,
        tone: Bool,
        language: String?,
        toneMode: ToneMode,
        target: TransformLanguage
    ) -> TransformPolicy? {
        guard translate || tone else { return nil }

        guard let verdict = language.flatMap(LanguageDetector.Verdict.init(languageCode:)),
              let source = TransformLanguage(verdict: verdict) else {
            return nil
        }

        // Nothing to translate: paste what was said, with no call.
        guard source != target else { return nil }
        guard translate else { return nil }

        return tone
            ? .translateWithTone(from: source, to: target, tone: toneMode)
            : .translate(from: source, to: target)
    }
}

/// Transforms dictation into the target language and applies a tone.
///
/// The tone belongs to the translation: it describes the *output* of a
/// direction change. A dictation already in the target language is pasted
/// untouched with no call, so the tone switch cannot rewrite it — the app never
/// spends a model call on the language the user actually spoke.
///
/// Two backends, one entry point: the engine built into the app (llama.cpp,
/// linked in-process, weights in app-owned storage) is the default, and an
/// OpenAI-compatible local endpoint stays available as an advanced override.
/// Either way the prompts, the temperature and the response handling are the
/// same code.
final class TranslationService {
    static let shared = TranslationService()

    /// Session used for translation requests. Injected at construction so
    /// tests can supply a `URLProtocol`-stubbed session without mutable global
    /// state; production uses `URLSession.shared`.
    let urlSession: URLSession

    /// The built-in runtime, injectable for the same reason: a test can drive
    /// the dispatch without loading 986 MB of weights.
    let localTransform: LocalTransform

    /// Whether the transform goes to the external endpoint. Read on every call,
    /// so flipping the switch takes effect on the next dictation; injectable so
    /// a test can exercise both backends without writing the shared
    /// preferences that other test classes run against in parallel.
    let usesExternalEndpoint: () -> Bool

    /// The switches, tone and target the gate reads for one dictation, as one
    /// unit. Read on every call, so the picker and the switches take effect on
    /// the next dictation; injectable for the same reason as
    /// `usesExternalEndpoint`.
    let gateSettings: () -> GateSettings

    typealias LocalTransform = (_ systemPrompt: String, _ userText: String) async throws -> String

    init(
        urlSession: URLSession = .shared,
        localTransform: @escaping LocalTransform = { systemPrompt, userText in
            try await TransformRuntime.shared.transform(systemPrompt: systemPrompt, userText: userText)
        },
        usesExternalEndpoint: @escaping () -> Bool = {
            AppPreferences.shared.transformUseExternalEndpoint
        },
        gateSettings: @escaping () -> GateSettings = { .current }
    ) {
        self.urlSession = urlSession
        self.localTransform = localTransform
        self.usesExternalEndpoint = usesExternalEndpoint
        self.gateSettings = gateSettings
    }

    // MARK: - Public API

    /// The only entry point used by the UI.
    ///
    /// Returns `text` unchanged when no transform applies, when `text` is
    /// empty, or on ANY failure. The app must always be able to paste
    /// something, so this method never throws.
    ///
    /// `sourceLanguage` is the language the transcription engine reported for
    /// this utterance (`TranscriptionOutput.language`). A fixed whisper
    /// language setting and a multilingual model's own detection are both
    /// authoritative; only when the engine had no signal is the transcript
    /// classified with `LanguageDetector`.
    func transformIfEnabled(_ text: String, sourceLanguage: String? = nil) async -> String {
        guard !text.isEmpty else { return text }
        let settings = gateSettings()
        // Nothing is switched on: skip the language work entirely.
        guard settings.translate || settings.tone else { return text }

        let language = sourceLanguage ?? LanguageDetector.languageCode(for: text)
        guard let policy = TransformPolicy.resolve(
            translate: settings.translate,
            tone: settings.tone,
            language: language,
            toneMode: settings.toneMode,
            target: settings.target
        ) else {
            return text
        }

        do {
            return try await performTransform(text, policy: policy)
        } catch {
            // Surface the failure so a down/misconfigured endpoint is
            // distinguishable from translation simply being disabled.
            print("[TranslationService] transform failed, returning raw text: \(error)")
            return text
        }
    }

    /// Performs the transform on the selected backend. Throws on any failure so
    /// the caller can fall back to the raw transcript.
    ///
    /// The built-in runtime is the default because the app ships it: llama.cpp
    /// is linked into this process and the weights are downloaded into
    /// app-owned storage on first use. `transformUseExternalEndpoint` switches
    /// to the HTTP override, which is what someone running their own
    /// `llama-server` (or any OpenAI-compatible endpoint) wants.
    func performTransform(_ text: String, policy: TransformPolicy) async throws -> String {
        if usesExternalEndpoint() {
            return try await transformOverHTTP(text, policy: policy)
        }
        return try await transformInProcess(text, policy: policy)
    }

    /// The built-in runtime: one in-process chat completion with the same
    /// system prompt and, in `LlamaModel`, the same temperature the HTTP path
    /// sends. The response is cleaned exactly like an HTTP one, so a reasoning
    /// trace or an empty reply is rejected the same way.
    func transformInProcess(_ text: String, policy: TransformPolicy) async throws -> String {
        let raw = try await localTransform(Self.systemPrompt(for: policy), text)
        let stripped = Self.stripReasoning(from: raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return stripped
    }

    /// Performs the HTTP request and parsing. Throws on any failure so the
    /// caller can fall back to the raw transcript.
    func transformOverHTTP(_ text: String, policy: TransformPolicy) async throws -> String {
        let prefs = AppPreferences.shared
        let endpoint = prefs.transformEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint) else {
            throw TranslationError.invalidEndpoint
        }

        let body = try Self.buildRequestBody(
            text: text,
            policy: policy,
            model: prefs.transformModel
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = max(1, min(prefs.transformTimeout, 120))

        try Task.checkCancellation()
        let (data, response) = try await urlSession.data(for: request)
        try Task.checkCancellation()

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw TranslationError.httpError(statusCode: httpResponse.statusCode)
        }

        return try Self.parseContent(from: data)
    }

    // MARK: - Request building

    /// Builds the OpenAI-compatible chat completions request body. Pure and
    /// testable without a network.
    static func buildRequestBody(text: String, policy: TransformPolicy, model: String) throws -> Data {
        let request = ChatRequest(
            model: model,
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt(for: policy)),
                ChatRequest.Message(role: "user", content: text)
            ],
            temperature: 0.2,
            stream: false,
            chatTemplateKwargs: ["enable_thinking": false]
        )
        return try JSONEncoder().encode(request)
    }

    /// The system prompt for `policy`, naming the demanded direction and
    /// embedding tone text only where the policy asks for it: translation with
    /// the tone switch off sends no tone wording at all — not even the neutral
    /// instruction, which is the text that used to make every translation carry
    /// a tone sentence.
    static func systemPrompt(for policy: TransformPolicy) -> String {
        switch policy {
        case .translate(let source, let target):
            return """
            You are a translation assistant. Translate the user's \(source.displayName) text into natural \(target.displayName). Output ONLY the final \(target.displayName) text, with no quotes, labels, or explanation.
            /no_think
            """
        case .translateWithTone(let source, let target, let tone):
            return """
            You are a translation assistant. Translate the user's \(source.displayName) text into natural \(target.displayName), then rewrite the result in a tone matching the instruction below. \(tone.instruction) Output ONLY the final \(target.displayName) text, with no quotes, labels, or explanation.
            /no_think
            """
        }
    }

    // MARK: - Response parsing

    /// Decodes the endpoint response, strips any reasoning traces, and returns
    /// the trimmed final text. Throws on malformed or empty results.
    static func parseContent(from data: Data) throws -> String {
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw TranslationError.malformedResponse
        }

        guard let message = decoded.choices.first?.message,
              let content = message.content else {
            throw TranslationError.emptyResponse
        }

        // If only reasoning_content came back (content empty), fall through to
        // the empty check below and throw so the caller uses the raw transcript.
        let stripped = stripReasoning(from: content)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return trimmed
    }

    /// Removes Qwen3 reasoning traces from `text`: paired and unterminated
    /// think/thinking/reasoning blocks, the bare end-of-thinking token, and any
    /// orphan closing tag. It never removes the plain words "thinking" or
    /// "reasoning".
    static func stripReasoning(from text: String) -> String {
        // Build every reasoning tag from Unicode scalars so the source never
        // contains literal angle brackets (which are easy to corrupt).
        let openThinkTag = "\u{3C}think\u{3E}"              // <think>
        let closeThinkTag = "\u{3C}/think\u{3E}"            // </think>
        let openMarkupTag = "\u{3C}thinking\u{3E}"          // <thinking>
        let closeMarkupTag = "\u{3C}/thinking\u{3E}"        // </thinking>
        let openReasoningTag = "\u{3C}reasoning\u{3E}"      // <reasoning>
        let closeReasoningTag = "\u{3C}/reasoning\u{3E}"    // </reasoning>

        // The Qwen3 end-of-thinking token uses full-width/special characters;
        // build it from scalars too so it never depends on editor encoding.
        let endThinkToken = "<\u{FF5C}end\u{2581}of\u{2581}thinking\u{FF5C}>"

        let escapedOpenThink = NSRegularExpression.escapedPattern(for: openThinkTag)
        let escapedCloseThink = NSRegularExpression.escapedPattern(for: closeThinkTag)
        let escapedEndThink = NSRegularExpression.escapedPattern(for: endThinkToken)
        let escapedOpenMarkup = NSRegularExpression.escapedPattern(for: openMarkupTag)
        let escapedCloseMarkup = NSRegularExpression.escapedPattern(for: closeMarkupTag)
        let escapedOpenReasoning = NSRegularExpression.escapedPattern(for: openReasoningTag)
        let escapedCloseReasoning = NSRegularExpression.escapedPattern(for: closeReasoningTag)

        // Terminated blocks first (lazy), then any unterminated trailing block.
        let patterns = [
            "(?is)\(escapedOpenThink).*?\(escapedEndThink)",
            "(?is)\(escapedOpenThink).*?\(escapedCloseThink)",
            "(?is)\(escapedOpenThink).*",
            "(?is)\(escapedOpenMarkup).*?\(escapedCloseMarkup)",
            "(?is)\(escapedOpenReasoning).*?\(escapedCloseReasoning)",
            "(?is)\(escapedOpenMarkup).*",
            "(?is)\(escapedOpenReasoning).*"
        ]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        // A Qwen3 response can carry the end token without any preceding opener
        // (the `enable_thinking:false` template can prefill it), so remove it
        // anywhere it survives the paired-block patterns above.
        result = result.replacingOccurrences(of: endThinkToken, with: "")

        // A lone closing tag can lead the text (or stand alone) when no opener
        // precedes it. Paired openers were already consumed above, so any
        // remaining closing tag is orphaned. Only the tags are removed; a bare
        // mention of the word "thinking" is preserved.
        let orphanCloseTags = [escapedCloseThink, escapedCloseMarkup, escapedCloseReasoning]
            .joined(separator: "|")
        result = result.replacingOccurrences(
            of: "(?is)\(orphanCloseTags)",
            with: "",
            options: .regularExpression
        )
        return result
    }
}

// MARK: - Codable payloads

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
    let chatTemplateKwargs: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case stream
        case chatTemplateKwargs = "chat_template_kwargs"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let message: Message
    }

    let choices: [Choice]
}
