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
    /// not a reason to stop testing. The checked-in copy the app target packages
    /// is used when a build's resources are not in place yet.
    static func tinyEnglishModel(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        if let bundled = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin") {
            return bundled
        }
        let checkedIn = repositoryRoot.appendingPathComponent("OpenSuperWhisper/ggml-tiny.en.bin")
        return try XCTUnwrap(
            FileManager.default.fileExists(atPath: checkedIn.path) ? checkedIn : nil,
            "the app bundle must carry ggml-tiny.en.bin (WhisperModelManager.defaultModelName)",
            file: file,
            line: line
        )
    }

    /// A multilingual model, for the cases that measure a language.
    ///
    /// Resolved from the test's own opt-in, never from the machine's selection:
    /// `OSW_TEST_MULTILINGUAL_MODEL` (which `Scripts/dev-run.sh test` offers
    /// through XCTest's `TEST_RUNNER_` forwarding), then a model cached in the
    /// checkout. With none the cases skip, which is the state CI runs in — and
    /// no test may fall back to `selectedWhisperModelPath`, because that value
    /// belongs to whoever last ran the app.
    ///
    /// The check resolves symlinks first: pointing a local run at a model with a
    /// symlink is normal, and `resourceValues(forKeys:)` would report the link's
    /// own size rather than the file's.
    static func multilingualModel(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let candidates = [
            ProcessInfo.processInfo.environment["OSW_TEST_MULTILINGUAL_MODEL"]
                .map(URL.init(fileURLWithPath:)),
            repositoryRoot.appendingPathComponent(".build/test-models/ggml-tiny.bin"),
            repositoryRoot.appendingPathComponent("ggml-tiny.bin"),
        ].compactMap { $0 }

        guard let model = candidates.first(where: { candidate in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: candidate.resolvingSymlinksInPath().path
            )
            guard let size = (attributes?[.size] as? NSNumber)?.intValue else { return false }
            return size > 10_000_000
        }) else {
            throw XCTSkip("Set OSW_TEST_MULTILINGUAL_MODEL to a real multilingual ggml model")
        }
        return model
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

    /// Prints a measurement line, and — when `OSW_TEST_EVIDENCE` names a file —
    /// appends it there too.
    ///
    /// `xcodebuild test` does not carry a test process's stdout into the console
    /// or the result bundle, so a run that measures something (a backend name, a
    /// latency, a wired-memory step) has no way to hand its numbers back. The
    /// file is opt-in, exactly like the model fixtures above: with the variable
    /// unset — the default, and what CI has — this only prints.
    static func report(_ line: String) {
        print(line)
        guard let path = ProcessInfo.processInfo.environment["OSW_TEST_EVIDENCE"] else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
