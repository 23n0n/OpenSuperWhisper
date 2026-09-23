import XCTest
@testable import OpenSuperWhisper

/// Drives the real Swift wrapper against real weights.
///
/// Skipped when this machine has no transform weights, so CI stays fast and
/// hermetic: this is the test that would catch a wrong llama.cpp API flag, a
/// broken chat template or a mis-tracked sequence position, and none of those
/// can be seen with a fake model.
final class LlamaRuntimeIntegrationTests: XCTestCase {

    /// The weights the app downloads, as `Scripts/transform-server.sh` places
    /// them. Read-only: nothing here writes to the user's model directory.
    private static var weightsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("models/qwen2.5-1.5b-instruct-q4_k_m.gguf").path
    }

    private func requireWeights() throws -> String {
        let path = Self.weightsPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("no transform weights at \(path)")
        }
        return path
    }

    func testComplete_translatesPolishThroughTheRealModel() throws {
        let model = try LlamaModel(modelPath: try requireWeights())
        defer { model.unload() }

        let started = Date()
        let text = try model.complete(
            systemPrompt: TranslationService.systemPrompt(for: .translate(from: .polish, to: .english)),
            userText: "Nie mogę dzisiaj przyjść na spotkanie, przepraszam."
        )
        let elapsed = Date().timeIntervalSince(started)
        print("[LlamaRuntimeIntegrationTests] in-process transform: \(String(format: "%.2f", elapsed))s -> \(text)")

        XCTAssertFalse(text.isEmpty, "the model produced nothing")
        XCTAssertFalse(
            text.contains("<|im_start|>"),
            "the chat template must not leak into the answer: \(text)"
        )
        XCTAssertNil(
            text.rangeOfCharacter(from: CharacterSet(charactersIn: "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")),
            "a Polish→English transform must come back in English: \(text)"
        )
    }

    func testComplete_honoursCancellationBeforeSpendingTimeOnDecoding() throws {
        let model = try LlamaModel(modelPath: try requireWeights())
        defer { model.unload() }

        let started = Date()
        XCTAssertThrowsError(
            try model.complete(systemPrompt: "system", userText: "Cześć", isCancelled: { true })
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        let elapsed = Date().timeIntervalSince(started)
        print("[LlamaRuntimeIntegrationTests] cancelled transform returned in \(String(format: "%.3f", elapsed))s")
        XCTAssertLessThan(elapsed, 1.0, "a cancelled request must not wait for generation")
    }

    func testComplete_doesNotCarryOneDictationIntoTheNext() throws {
        // Two prompts, one context: the second must not inherit the first one's
        // sequence (a mis-tracked position shows up as an answer to the wrong
        // question, or as an immediate stop).
        let model = try LlamaModel(modelPath: try requireWeights())
        defer { model.unload() }

        let first = try model.complete(
            systemPrompt: TranslationService.systemPrompt(for: .translate(from: .polish, to: .english)),
            userText: "Dziękuję bardzo za pomoc."
        )
        let second = try model.complete(
            systemPrompt: TranslationService.systemPrompt(for: .translate(from: .polish, to: .english)),
            userText: "Nie mogę dzisiaj przyjść na spotkanie, przepraszam."
        )

        print("[LlamaRuntimeIntegrationTests] first: \(first)")
        print("[LlamaRuntimeIntegrationTests] second: \(second)")
        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(first, second, "two different dictations must not produce the same answer")
    }
}
