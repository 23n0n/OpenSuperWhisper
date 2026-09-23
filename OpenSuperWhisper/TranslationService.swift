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

/// Translates Polish dictation into English and applies a tone, using an
/// OpenAI-compatible local chat completions endpoint.
final class TranslationService {
    static let shared = TranslationService()

    private init() {}

    // MARK: - Public API

    /// The only entry point used by the UI.
    ///
    /// Returns `text` unchanged when translation is disabled, when `text` is
    /// empty, or on ANY failure. The app must always be able to paste
    /// something, so this method never throws.
    func transformIfEnabled(_ text: String) async -> String {
        guard AppPreferences.shared.translateEnabled, !text.isEmpty else {
            return text
        }
        do {
            return try await transform(text)
        } catch {
            return text
        }
    }

    /// Performs the HTTP request and parsing. Throws on any failure so the
    /// caller can fall back to the raw transcript.
    func transform(_ text: String) async throws -> String {
        let prefs = AppPreferences.shared
        guard let url = URL(string: prefs.transformEndpoint) else {
            throw TranslationError.invalidEndpoint
        }

        let body = try Self.buildRequestBody(
            text: text,
            tone: prefs.transformToneMode,
            model: prefs.transformModel
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = prefs.transformTimeout

        try Task.checkCancellation()
        let (data, response) = try await URLSession.shared.data(for: request)
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
    static func buildRequestBody(text: String, tone: ToneMode, model: String) throws -> Data {
        let request = ChatRequest(
            model: model,
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt(for: tone)),
                ChatRequest.Message(role: "user", content: text)
            ],
            temperature: 0.2,
            stream: false,
            chatTemplateKwargs: ["enable_thinking": false]
        )
        return try JSONEncoder().encode(request)
    }

    static func systemPrompt(for tone: ToneMode) -> String {
        """
        You are a translation assistant. Translate the user's Polish text into natural English, then rewrite the result in a tone matching the instruction below. \(tone.instruction) Output ONLY the final English text, with no quotes, labels, or explanation.
        /no_think
        """
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

    /// Removes ` thinking...<｜end▁of▁thinking｜>` blocks and other common
    /// reasoning markers from `text`.
    static func stripReasoning(from text: String) -> String {
        // The Qwen3 end-of-thinking token uses full-width/special characters;
        // build it from scalars so it never depends on editor encoding.
        let endThinkToken = "<\u{FF5C}end\u{2581}of\u{2581}thinking\u{FF5C}>"
        let escapedEndThink = NSRegularExpression.escapedPattern(for: endThinkToken)

        // Terminated blocks first (lazy), then any unterminated trailing block.
        let patterns = [
            "(?is) thinking.*?\(escapedEndThink)",
            "(?is) thinking.*? response",
            "(?is) thinking.*",
            "(?is)<thinking>.*?</thinking>",
            "(?is)<reasoning>.*?</reasoning>"
        ]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
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
