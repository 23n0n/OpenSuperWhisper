import CryptoKit
import Foundation
import XCTest
@testable import OpenSuperWhisper

/// Same input, same settings, same model — the same bytes out.
///
/// The sampler is already pinned (`LlamaModel.makeSampler()` builds
/// `top_k(40) -> top_p(0.95) -> min_p(0.05) -> temp(0.2) -> dist(seed: 0)` for
/// every request), so what is left that could vary between two identical
/// dictations is the backend's own accumulation. Repeating one call on one
/// loaded model is therefore the check a fixed seed cannot make vacuous: either
/// it comes back byte for byte identical every time, or it does not.
///
/// Driven with the real weights and skipped when this machine has none, exactly
/// like `LlamaRuntimeIntegrationTests`, so CI stays hermetic.
final class TransformDeterminismIntegrationTests: XCTestCase {

    /// The weights the app installs, as `Scripts/transform-server.sh` places
    /// them. Read-only: nothing here writes to the user's model directory.
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var englishWeights: URL { home.appendingPathComponent("models/qwen2.5-1.5b-instruct-q4_k_m.gguf") }
    private static var polishWeights: URL { home.appendingPathComponent("models/Qwen3-8B-Q4_K_M.gguf") }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs one dictation `runs` times through the real in-process transform and
    /// requires every output to be identical to the first.
    private func assertOneInputGivesOneOutput(
        weights: URL,
        from source: TransformLanguage,
        to target: TransformLanguage,
        input: String,
        runs: Int = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard FileManager.default.fileExists(atPath: weights.path) else {
            throw XCTSkip("no transform weights at \(weights.path)")
        }

        // One model, one context, `runs` requests: nothing is reloaded between
        // them, so a difference can never be blamed on a fresh set of weights.
        let model = try LlamaModel(modelPath: weights.path)
        defer { model.unload() }

        let prompt = TranslationService.systemPrompt(
            for: .translate(from: source, to: target),
            cleanUp: false
        )

        let started = Date()
        let outputs = try (0..<runs).map { _ in
            try model.complete(systemPrompt: prompt, userText: input)
        }
        let elapsed = Date().timeIntervalSince(started)
        let digests = outputs.map(Self.sha256)

        TestFixtures.report("[determinism] \(source.rawValue)→\(target.rawValue) on "
                    + "\(weights.lastPathComponent): \(runs) runs in \(String(format: "%.2f", elapsed))s, "
                    + "\(Set(digests).count) distinct output(s), sha256 \(digests[0]) "
                    + "(\(outputs[0].utf8.count) bytes)")

        XCTAssertFalse(outputs[0].isEmpty, "the model produced nothing, so there is nothing to compare")
        for index in outputs.indices where outputs[index] != outputs[0] {
            XCTFail("run \(index + 1) of \(runs) differs from run 1 "
                    + "(\(digests[index]) vs \(digests[0])):\n"
                    + "run 1: \(outputs[0])\nrun \(index + 1): \(outputs[index])",
                    file: file, line: line)
        }
    }

    /// Polish → English: the shipped small model, the direction used every day.
    func testPolishToEnglishIsIdenticalOnEveryRepeat() throws {
        try assertOneInputGivesOneOutput(
            weights: Self.englishWeights,
            from: .polish, to: .english,
            input: "Nie mogę dzisiaj przyjść na spotkanie, przepraszam. "
                 + "Czy możemy przełożyć je na przyszły tydzień?"
        )
    }

    /// English → Polish: the direction the Polish-output backend serves, so the
    /// 8B is the model whose accumulation this pins.
    func testEnglishToPolishIsIdenticalOnEveryRepeat() throws {
        try assertOneInputGivesOneOutput(
            weights: Self.polishWeights,
            from: .english, to: .polish,
            input: "I can't come to the meeting today, I'm sorry. "
                 + "Could we move it to next week?"
        )
    }
}
