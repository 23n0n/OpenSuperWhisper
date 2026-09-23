import Foundation

/// Tone applied to the translated English text.
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

/// What the transform gate decided to do with one dictation.
///
/// The absence of a value is the passthrough case: the raw transcript goes
/// straight to the keypress path, with no request, no tone text and no language
/// detection work. `TranslationService.transformIfEnabled` returns before it
/// builds any request for that case.
enum TransformPolicy: Equatable {
    /// Polish → English, with no tone wording in the prompt at all.
    case translate
    /// Same language in, same language out, in the given tone.
    case toneOnly(ToneMode)
    /// Polish → English, then that tone.
    case translateWithTone(ToneMode)

    /// The tone embedded in the prompt, if this policy sends any tone text.
    var promptTone: ToneMode? {
        switch self {
        case .translate: return nil
        case .toneOnly(let tone), .translateWithTone(let tone): return tone
        }
    }

    /// The decision table for one dictation.
    ///
    /// * Both switches off ⇒ `nil`, and the caller never even looks up the
    ///   language.
    /// * Only Polish is ever translated. English must never reach the
    ///   Polish→English transform: every model call rewrites it (measured
    ///   `"Do it tomorrow."` → `"I'll do it tomorrow."`), which is exactly the
    ///   behaviour language awareness is meant to stop.
    /// * Only English is ever toned. A tone-only prompt on Polish translates it
    ///   anyway — measured 6/6, with and without an explicit "do not
    ///   translate" — which would silently defeat "Polish without translation",
    ///   so Polish with the tone switch alone passes through. For English the
    ///   tone switch decides on its own: there is nothing to translate, so the
    ///   translation switch must not silently veto a tone rewrite the user
    ///   asked for. The two switches stay independent.
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
        toneMode: ToneMode
    ) -> TransformPolicy? {
        guard translate || tone else { return nil }

        switch language.flatMap(LanguageDetector.Verdict.init(languageCode:)) {
        case .polish:
            guard translate else { return nil }
            return tone ? .translateWithTone(toneMode) : .translate
        case .english:
            // Nothing to translate, so the translation switch has no say here.
            guard tone else { return nil }
            return .toneOnly(toneMode)
        case .unknown, .none:
            return nil
        }
    }
}

/// Translates Polish dictation into English and applies a tone, using an
/// OpenAI-compatible local chat completions endpoint.
final class TranslationService {
    static let shared = TranslationService()

    /// Session used for translation requests. Injected at construction so
    /// tests can supply a `URLProtocol`-stubbed session without mutable global
    /// state; production uses `URLSession.shared`.
    let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
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
        let prefs = AppPreferences.shared
        guard !text.isEmpty else { return text }
        // Nothing is switched on: skip the language work entirely.
        guard prefs.translateEnabled || prefs.toneEnabled else { return text }

        let language = sourceLanguage ?? LanguageDetector.languageCode(for: text)
        guard let policy = TransformPolicy.resolve(
            translate: prefs.translateEnabled,
            tone: prefs.toneEnabled,
            language: language,
            toneMode: prefs.transformToneMode
        ) else {
            return text
        }

        do {
            let result = try await transform(text, policy: policy)
            if case .toneOnly = policy,
               !Self.toneOnlyPreservesLanguage(input: text, output: result, sourceLanguage: sourceLanguage) {
                print("[TranslationService] tone-only rewrite changed the language, returning raw text")
                return text
            }
            return result
        } catch {
            // Surface the failure so a down/misconfigured endpoint is
            // distinguishable from translation simply being disabled.
            print("[TranslationService] transform failed, returning raw text: \(error)")
            return text
        }
    }

    /// Tone-only means "same language in, same language out". The local model
    /// translates Polish even when the prompt forbids it, so a tone-only result
    /// whose language changed is a failure and the raw transcript is used
    /// instead. The engine's language is authoritative when it has one;
    /// otherwise the input is classified from its text, like the input side of
    /// the gate.
    static func toneOnlyPreservesLanguage(input: String, output: String, sourceLanguage: String?) -> Bool {
        let inputVerdict = sourceLanguage.flatMap(LanguageDetector.Verdict.init(languageCode:))
            ?? LanguageDetector.detect(input)
        return LanguageDetector.detect(output) == inputVerdict
    }

    /// Performs the HTTP request and parsing. Throws on any failure so the
    /// caller can fall back to the raw transcript.
    func transform(_ text: String, policy: TransformPolicy) async throws -> String {
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

    /// The system prompt for `policy`, embedding tone text only where the
    /// policy asks for it: translation with the tone switch off sends no tone
    /// wording at all — not even the neutral instruction, which is the text that
    /// used to make every translation carry a tone sentence.
    static func systemPrompt(for policy: TransformPolicy) -> String {
        switch policy {
        case .translate:
            return """
            You are a translation assistant. Translate the user's Polish text into natural English. Output ONLY the final English text, with no quotes, labels, or explanation.
            /no_think
            """
        case .toneOnly(let tone):
            return """
            You are a rewriting assistant. Rewrite the user's text in the requested tone, keeping the same language as the input. Do not translate. \(tone.instruction) Output ONLY the final text, with no quotes, labels, or explanation.
            /no_think
            """
        case .translateWithTone(let tone):
            return """
            You are a translation assistant. Translate the user's Polish text into natural English, then rewrite the result in a tone matching the instruction below. \(tone.instruction) Output ONLY the final English text, with no quotes, labels, or explanation.
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
