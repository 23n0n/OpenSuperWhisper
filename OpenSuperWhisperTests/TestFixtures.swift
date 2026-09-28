import AVFoundation
import CryptoKit
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

    /// A real capture: one second of 16 kHz mono PCM written by the same writer
    /// `AudioRecorder` uses, with the samples that came out of it.
    ///
    /// Fixtures for a dictation the app must report are built with this rather
    /// than a stub file: the app reports a failure over audio that was recorded
    /// and stays silent over a capture that carried nothing, so a fixture of a
    /// few bytes with no samples stands for the silenced case and cannot stand
    /// for the reported one.
    static func recordedAudio(at url: URL, seconds: Double = 1) throws -> RecordedAudio {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let writer = try PCMRecordingWriter(url: url, inputFormat: format)
        let frames = AVAudioFrameCount(16000 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        buffer.floatChannelData![0].initialize(repeating: 0.25, count: Int(frames))
        try writer.append(buffer)
        return try writer.finish()
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

    // MARK: - The machine's real clipboard

    /// Every type on a pasteboard and the bytes of each, plus the changeCount
    /// read with them.
    ///
    /// For the cases that have to touch the machine's **real** clipboard — the
    /// only one whose behaviour is in question — and put it back exactly as they
    /// found it. The contents are never printed: reports use
    /// `description`, which carries type identifiers, byte counts and SHA-256
    /// prefixes.
    struct ClipboardSnapshot {
        let items: [(type: NSPasteboard.PasteboardType, data: Data)]
        let changeCount: Int

        var description: String {
            let parts = items.map { "\($0.type.rawValue):\(Self.digest($0.data))(\($0.data.count)B)" }
            return "changeCount=\(changeCount) types=\(items.map(\.type.rawValue)) "
                + "digests=[\(parts.joined(separator: " "))]"
        }

        var text: String? {
            items.first { $0.type == .string }.flatMap { String(data: $0.data, encoding: .utf8) }
        }

        static func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16).description
        }
    }

    /// Where a case leaves a copy of the clipboard it displaced, so the user can
    /// restore it by hand even if the case crashes.
    static let realClipboardBackup = URL(fileURLWithPath: "/tmp/osw-clipboard-measurement-backup.plist")

    static func snapshotClipboard(_ pasteboard: NSPasteboard = .general) -> ClipboardSnapshot {
        let items = (pasteboard.types ?? []).compactMap { type in
            pasteboard.data(forType: type).map { (type: type, data: $0) }
        }
        return ClipboardSnapshot(items: items, changeCount: pasteboard.changeCount)
    }

    static func restoreClipboard(_ snapshot: ClipboardSnapshot, on pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        pasteboard.declareTypes(snapshot.items.map(\.type), owner: nil)
        for item in snapshot.items {
            pasteboard.setData(item.data, forType: item.type)
        }
    }

    /// Captures the real clipboard, writes a copy of it to `realClipboardBackup`
    /// for the user, and hands the body a snapshot it can always put back.
    static func withTheRealClipboardPreserved(
        _ body: (NSPasteboard, ClipboardSnapshot) throws -> Void
    ) rethrows {
        let pasteboard = NSPasteboard.general
        let before = snapshotClipboard(pasteboard)
        let backup = Dictionary(uniqueKeysWithValues: before.items.map { ($0.type.rawValue, $0.data) })
        try? (backup as NSDictionary).write(to: realClipboardBackup)
        report("[clipboard] backup of the real clipboard written to \(realClipboardBackup.path) "
               + "(\(before.items.count) types)")
        defer { restoreClipboard(before, on: pasteboard) }
        try body(pasteboard, before)
    }
}
