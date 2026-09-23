import Foundation
import GRDB
import XCTest
@testable import OpenSuperWhisper

/// Returns one prepared transcript per call, so two consecutive dictations can
/// be told apart without a model.
private final class ScriptedTranscriptionEngine: TranscriptionEngine {
    var isModelLoaded: Bool { true }
    var engineName: String { "Scripted test engine" }

    private let lock = NSLock()
    private var remaining: [String]

    init(transcripts: [String]) { remaining = transcripts }

    func initialize() async throws {}

    func transcribeAudio(url: URL, settings: Settings) async throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !remaining.isEmpty else { return "" }
        return remaining.removeFirst()
    }

    func cancelTranscription() {}

    func getSupportedLanguages() -> [String] { ["en"] }
}

/// Hands out the recording URLs the view model will stop, in order. The decode
/// pipeline moves each one into the recordings directory, so every dictation
/// needs its own source file.
private final class RecordingURLQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL]

    init(count: Int) {
        urls = (0..<count).map { _ in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("osw-injection-\(UUID().uuidString).wav")
        }
    }

    var createdURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    func next() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return urls.isEmpty ? nil : urls.removeFirst()
    }
}

/// The captain's failure: transcription is saved every time, but the synthetic
/// keystrokes stop arriving after the first dictation. These tests drive the
/// real decode pipeline through `IndicatorViewModel` with a stubbed engine, so
/// the question "does the app reach the injection call on the second
/// dictation?" is answered deterministically instead of by dictating.
@MainActor
final class DictationInjectionTests: XCTestCase {
    private var temporaryFiles: [URL] = []

    override func setUp() {
        // The dictation pipeline reads one shared recording session, so a
        // session left behind by another test would redirect `startDecoding()`
        // into someone else's stop closure.
        RecordingSessionController.shared.finish(RecordingSessionController.shared.currentID)
        super.setUp()
    }

    override func tearDown() {
        for url in temporaryFiles {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryFiles = []
        AppErrorCenter.shared.issue = nil
        super.tearDown()
    }

    private func makeStore() throws -> RecordingStore {
        try RecordingStore(databaseQueue: DatabaseQueue())
    }

    /// These tests are about the injection hook, not about the transform gate.
    /// An identity transform keeps them independent of the user's
    /// translate/tone switches and of whether a local model endpoint happens to
    /// be running — the real gate reaches the network.
    private static let passthroughTransform: (String, String?) async -> String = { text, _ in text }

    /// Auto-paste must be on for the injection path to run. Pin it, but write
    /// nothing when the domain already holds what the test needs: a test host
    /// without a distinct bundle id would otherwise write the preferences of the
    /// app someone is using.
    private func pinAutoPasteOn() -> () -> Void {
        let preferences = AppPreferences.shared
        guard !preferences.autoPasteTranscription else { return {} }
        preferences.autoPasteTranscription = true
        return { preferences.autoPasteTranscription = false }
    }

    private func makeSourceFiles(count: Int) -> RecordingURLQueue {
        let queue = RecordingURLQueue(count: count)
        for url in queue.createdURLs {
            try? Data([1, 2, 3, 4]).write(to: url)
            temporaryFiles.append(url)
        }
        return queue
    }

    /// Drives one full dictation through the real pipeline and waits for its
    /// injection. Returns without asserting, so the caller decides what the
    /// observable outcome should be.
    private func dictate(_ viewModel: IndicatorViewModel) async throws {
        viewModel.state = .recording
        viewModel.startDecoding()
    }

    private func waitForInjections(_ count: Int, _ injected: () -> [String]) async throws {
        for _ in 0..<200 {
            if injected().count >= count { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testTwoConsecutiveDictationsBothReachTheInjectionHook() async throws {
        let transcripts = ["first dictation", "second dictation"]
        let store = try makeStore()
        let sources = makeSourceFiles(count: transcripts.count)
        var injected: [String] = []

        // The injection path is only taken when auto-paste is on.
        let restoreAutoPaste = pinAutoPasteOn()
        defer { restoreAutoPaste() }

        let viewModel = IndicatorViewModel(
            transcriptionService: TranscriptionService(
                engine: ScriptedTranscriptionEngine(transcripts: transcripts)
            ),
            recordingStore: store,
            stopRecording: {
                guard let url = sources.next() else { return nil }
                return RecordedAudio(url: url, samples: [])
            },
            cancelAudioRecording: {},
            injectText: { text in
                injected.append(text)
                return KeyboardSimulator.InjectionResult(trusted: true, eventsPosted: 4)
            },
            transformText: Self.passthroughTransform
        )
        defer { viewModel.cleanup() }

        try await dictate(viewModel)
        try await waitForInjections(1, { injected })
        try await dictate(viewModel)
        try await waitForInjections(2, { injected })

        XCTAssertEqual(
            injected, transcripts,
            "Every dictation must reach the injection hook, not just the first one"
        )

        // The product contract on both counts: saved in history AND typed.
        let rows = try await store.fetchRecordings(limit: 10, offset: 0)
        temporaryFiles.append(contentsOf: rows.map(\.url))
        XCTAssertEqual(rows.count, transcripts.count)
        XCTAssertEqual(Set(rows.map(\.transcription)), Set(transcripts))
        XCTAssertTrue(rows.allSatisfy { $0.status == .completed })
    }

    /// When macOS is discarding the keystrokes the transcript must not look
    /// like it vanished: the user is told, the permission surface is asked to
    /// re-check, and the recording is still saved.
    func testUntrustedInjectionIsReportedToTheUserAndTheDictationIsStillSaved() async throws {
        let store = try makeStore()
        let sources = makeSourceFiles(count: 1)
        var injected: [String] = []

        let restoreAutoPaste = pinAutoPasteOn()
        defer { restoreAutoPaste() }

        let viewModel = IndicatorViewModel(
            transcriptionService: TranscriptionService(
                engine: ScriptedTranscriptionEngine(transcripts: ["nobody received this"])
            ),
            recordingStore: store,
            stopRecording: {
                guard let url = sources.next() else { return nil }
                return RecordedAudio(url: url, samples: [])
            },
            cancelAudioRecording: {},
            injectText: { text in
                injected.append(text)
                return KeyboardSimulator.InjectionResult(trusted: false, eventsPosted: 0)
            },
            transformText: Self.passthroughTransform
        )
        defer { viewModel.cleanup() }
        AppErrorCenter.shared.issue = nil

        let recheck = expectation(description: "permission surface asked to re-check")
        let observer = NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionNeededForInjection,
            object: nil,
            queue: .main
        ) { _ in recheck.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await dictate(viewModel)
        try await waitForInjections(1, { injected })
        await fulfillment(of: [recheck], timeout: 2)

        XCTAssertEqual(injected, ["nobody received this"])
        let issue = try XCTUnwrap(
            AppErrorCenter.shared.issue,
            "A dictation that was not typed must be reported, never dropped silently"
        )
        XCTAssertTrue(issue.message.contains("Accessibility"))

        let rows = try await store.fetchRecordings(limit: 10, offset: 0)
        temporaryFiles.append(contentsOf: rows.map(\.url))
        XCTAssertEqual(rows.map(\.transcription), ["nobody received this"])
    }
}
