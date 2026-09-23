import XCTest
@testable import OpenSuperWhisper

/// Where the tests find their fixtures.
///
/// `ggml-tiny.en.bin` ships inside the app (`OpenSuperWhisper/ggml-tiny.en.bin`
/// lands in the app's `Contents/Resources`) and the test host *is* the app, so
/// the bundle is the one place to read it — the same route
/// `WhisperModelManager` takes in production. These tests used to look for a
/// copy next to the checkout; that copy stopped existing when the model moved
/// into the bundle, and every test that needed a real model went on passing by
/// skipping instead of running.
enum TestFixtures {

    /// The repository root, derived from this file's own location.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The English-only whisper model the app bundles.
    ///
    /// A missing copy fails the test rather than skipping it: the bundle copy is
    /// the app's default whisper model, so its absence is a packaging defect,
    /// not a reason to stop testing.
    static func tinyEnglishModel(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        try XCTUnwrap(
            Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin"),
            "the app bundle must carry ggml-tiny.en.bin (WhisperModelManager.defaultModelName)",
            file: file,
            line: line
        )
    }

    /// A checked-in audio sample, e.g. `jfk.wav` at the repository root.
    static func speechSample(
        _ name: String = "jfk.wav",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let url = repositoryRoot.appendingPathComponent(name)
        return try XCTUnwrap(
            FileManager.default.fileExists(atPath: url.path) ? url : nil,
            "\(name) must be checked in at the repository root",
            file: file,
            line: line
        )
    }
}
