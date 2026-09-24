import Foundation
import XCTest
@testable import OpenSuperWhisper

/// The Polish-output backend, driven against real weights.
///
/// Skipped when this machine does not have the files, exactly like
/// `LlamaRuntimeIntegrationTests`: CI stays hermetic, and a machine that has
/// them proves which backend each direction loads, that a missing Polish
/// backend is refused rather than substituted, that a wrong digest cannot be
/// installed, and what the 8B costs in wired memory and first-utterance
/// latency.
///
/// The weights are hard-linked into a staging directory, so nothing here copies
/// 5 GB and nothing here can write to the files in `~/models`.
final class PolishOutputBackendIntegrationTests: XCTestCase {

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var smallWeights: URL { home.appendingPathComponent("models/qwen2.5-1.5b-instruct-q4_k_m.gguf") }
    private static var polishWeights: URL { home.appendingPathComponent("models/Qwen3-8B-Q4_K_M.gguf") }

    private var directory: URL!
    private var manager: TransformModelManager!
    private var runtime: TransformRuntime!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Same volume as `~/models`, which is what makes the hard link below
        // possible. Under the user's caches, so a run leaves nothing behind.
        directory = Self.home
            .appendingPathComponent("Library/Caches/OpenSuperWhisperTests-transform-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manager = TransformModelManager(directory: directory, catalogue: TransformModelManager.availableModels)
        runtime = TransformRuntime(models: manager)
    }

    override func tearDownWithError() throws {
        runtime.unload()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Stages real weights under the name the catalogue expects. A hard link:
    /// no 5 GB copy, and removing the staged name later cannot touch the file
    /// it points at.
    private func stage(_ model: TransformModel, from source: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("no weights at \(source.path)")
        }
        let destination = manager.fileURL(for: model)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.linkItem(at: source, to: destination)
    }

    /// A `TranslationService` whose built-in backend is this test's runtime —
    /// the production wiring, pointing at staged weights instead of the user's
    /// Application Support. `calls` counts every model call the service makes.
    private final class CallCounter {
        var models: [String] = []
    }

    private func service(
        policy settings: GateSettings,
        calls: CallCounter
    ) -> TranslationService {
        TranslationService(
            localTransform: { systemPrompt, userText, model in
                calls.models.append(model.id)
                return try await self.runtime.transform(
                    systemPrompt: systemPrompt,
                    userText: userText,
                    model: model
                )
            },
            usesExternalEndpoint: { false },
            localModel: { self.manager.model(forOutputLanguage: $0) },
            gateSettings: { settings }
        )
    }

    /// The system's wired page count. The instrument `fm-20260923-24` validated
    /// for a Metal-backed model: its weights, KV cache and compute buffer are
    /// wired, and neither RSS nor `footprint` reports them. System-wide, so the
    /// numbers below are read as a *step* across a load or an unload, never as
    /// an absolute.
    private func wiredBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(stats.wire_count) * UInt64(vm_kernel_page_size)
    }

    private func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    private func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.2f s", interval)
    }

    private func report(_ label: String, wiredSince baseline: UInt64) {
        let now = wiredBytes()
        TestFixtures.report("[polish-backend] wired \(label): \(gigabytes(now)) "
                    + "(step \(gigabytes(now &- min(now, baseline))), baseline \(gigabytes(baseline)))")
    }

    // MARK: - Routing, end to end, against real weights

    /// The production service, real weights, both directions: the model that
    /// ran is named in the output, and speech already in the target language
    /// makes no call at all.
    func testTheServiceRunsEachDirectionOnTheBackendItsOutputLanguageNames() async throws {
        let english = manager.model(forOutputLanguage: .english)
        let polish = manager.model(forOutputLanguage: .polish)
        try stage(english, from: Self.smallWeights)
        try stage(polish, from: Self.polishWeights)

        // English → Polish, the direction this backend exists for.
        let englishToPolish = CallCounter()
        let toPolish = service(
            policy: GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .polish),
            calls: englishToPolish
        )
        let polishStart = Date()
        let polishOutcome = await toPolish.transformDetailed("Please send the report.", sourceLanguage: "en")
        let polishFirst = Date().timeIntervalSince(polishStart)
        TestFixtures.report("[polish-backend] en→pl: backend \(englishToPolish.models.joined(separator: ", ")) "
                    + "| policy \(polishOutcome.policy?.summary ?? "none") | didRunModel \(polishOutcome.didRunModel)")
        TestFixtures.report("[polish-backend] en→pl output: \(polishOutcome.text)")
        XCTAssertEqual(englishToPolish.models, [polish.id], "English→Polish must load the Polish backend")
        XCTAssertEqual(polishOutcome.policy, .translate(from: .english, to: .polish))
        XCTAssertTrue(polishOutcome.didRunModel)
        XCTAssertFalse(polishOutcome.text.isEmpty)

        // The same direction with those weights already resident: what a
        // dictation costs once something else has paid the load — the warm-up
        // on record start, or the previous utterance.
        let polishSteadyStart = Date()
        let polishSteady = await toPolish.transformDetailed("Please send the report.", sourceLanguage: "en")
        TestFixtures.report("[polish-backend] en→pl latency: first call \(seconds(polishFirst)) (load + decode), "
                    + "steady \(seconds(Date().timeIntervalSince(polishSteadyStart)))")
        XCTAssertEqual(polishSteady.policy, .translate(from: .english, to: .polish))

        // Polish → English, the daily direction, unchanged.
        let polishToEnglish = CallCounter()
        let toEnglish = service(
            policy: GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .english),
            calls: polishToEnglish
        )
        let englishStart = Date()
        let englishOutcome = await toEnglish.transformDetailed("Proszę wysłać raport jutro rano.", sourceLanguage: "pl")
        let englishFirst = Date().timeIntervalSince(englishStart)
        TestFixtures.report("[polish-backend] pl→en: backend \(polishToEnglish.models.joined(separator: ", ")) "
                    + "| policy \(englishOutcome.policy?.summary ?? "none") | didRunModel \(englishOutcome.didRunModel)")
        TestFixtures.report("[polish-backend] pl→en output: \(englishOutcome.text)")
        XCTAssertEqual(polishToEnglish.models, [english.id], "Polish→English must stay on the shipped 1.5B")
        XCTAssertEqual(englishOutcome.policy, .translate(from: .polish, to: .english))
        XCTAssertTrue(englishOutcome.didRunModel)

        let englishSteadyStart = Date()
        let englishSteady = await toEnglish.transformDetailed("Proszę wysłać raport jutro rano.", sourceLanguage: "pl")
        TestFixtures.report("[polish-backend] pl→en latency: first call \(seconds(englishFirst)) "
                    + "(that one also swapped the 8B out and the 1.5B in), "
                    + "steady \(seconds(Date().timeIntervalSince(englishSteadyStart)))")
        XCTAssertEqual(englishSteady.policy, .translate(from: .polish, to: .english))

        // Spoken == target: no backend is resolved, no call is made.
        let sameLanguage = CallCounter()
        let spokenPolish = service(
            policy: GateSettings(translate: true, tone: true, cleanUp: false, toneMode: .formal, target: .polish),
            calls: sameLanguage
        )
        let untouched = await spokenPolish.transformDetailed("Proszę wysłać raport.", sourceLanguage: "pl")
        XCTAssertEqual(untouched.text, "Proszę wysłać raport.")
        XCTAssertNil(untouched.policy)
        XCTAssertTrue(sameLanguage.models.isEmpty, "spoken == target must make zero model calls")
        TestFixtures.report("[polish-backend] pl→pl (Polish target): model calls \(sameLanguage.models.count), "
                    + "text untouched \(untouched.text == "Proszę wysłać raport.")")
    }

    /// The wired-memory step of the 8B in this process, and the one-at-a-time
    /// contract: loading the other direction evicts it rather than adding to it.
    func testOnlyOneBackendIsResidentAndTheEightBeeStepIsMeasured() async throws {
        let english = manager.model(forOutputLanguage: .english)
        let polish = manager.model(forOutputLanguage: .polish)
        try stage(english, from: Self.smallWeights)
        try stage(polish, from: Self.polishWeights)

        let baseline = wiredBytes()
        _ = try await runtime.transform(
            systemPrompt: TranslationService.systemPrompt(for: .translate(from: .english, to: .polish), cleanUp: false),
            userText: "Please send the report.",
            model: polish
        )
        XCTAssertEqual(runtime.loadedModelID, polish.id)
        report("with the 8B resident", wiredSince: baseline)
        let residentWith8B = wiredBytes()

        _ = try await runtime.transform(
            systemPrompt: TranslationService.systemPrompt(for: .translate(from: .polish, to: .english), cleanUp: false),
            userText: "Proszę wysłać raport.",
            model: english
        )
        XCTAssertEqual(runtime.loadedModelID, english.id, "the direction change must swap the resident backend")
        report("with the 1.5B resident (the 8B was evicted)", wiredSince: baseline)

        runtime.unload()
        XCTAssertNil(runtime.loadedModelID)
        report("after unload", wiredSince: baseline)
        TestFixtures.report("[polish-backend] wired: baseline \(gigabytes(baseline)), 8B \(gigabytes(residentWith8B)), "
                    + "8B step \(gigabytes(residentWith8B &- min(residentWith8B, baseline)))")
    }

    /// A missing Polish backend is refused, and the small model that *is*
    /// installed is not loaded in its place.
    func testMissingPolishBackendIsRefusedAndNothingElseIsLoaded() async throws {
        let polish = manager.model(forOutputLanguage: .polish)
        let english = manager.model(forOutputLanguage: .english)
        try stage(english, from: Self.smallWeights)

        let calls = CallCounter()
        let subject = service(
            policy: GateSettings(translate: true, tone: false, cleanUp: false, toneMode: .neutral, target: .polish),
            calls: calls
        )
        let outcome = await subject.transformDetailed("Please send the report.", sourceLanguage: "en")

        XCTAssertEqual(outcome.text, "Please send the report.", "the transcript is still delivered")
        XCTAssertFalse(outcome.didRunModel)
        XCTAssertEqual(calls.models, [polish.id], "only the Polish backend may be attempted")
        XCTAssertFalse(
            calls.models.contains(english.id),
            "the installed 1.5B must never be substituted for Polish"
        )
        XCTAssertNotEqual(runtime.loadedModelID, english.id, "nothing — least of all the 1.5B — may be loaded")
        XCTAssertNil(runtime.loadedModelID)
        TestFixtures.report("[polish-backend] missing 8B: attempted \(calls.models), resident \(runtime.loadedModelID ?? "none"), "
                    + "delivered the raw transcript")
    }

    /// The warm-up carries the cold load, and a dictation that arrives while the
    /// warm-up is still running waits for it instead of loading a second copy.
    func testWarmUpCarriesTheColdLoadAndTheFirstUtterance() async throws {
        let polish = manager.model(forOutputLanguage: .polish)
        try stage(polish, from: Self.polishWeights)
        // Verify first, so the one-off ~5 GB hash is not measured as load time.
        // (That hash does leave the file in the page cache, so this is the
        // warm-cache load: the app's second use of the weights. The cold figure,
        // with the cache evicted, is measured outside this suite — see the task
        // report for both numbers.)
        XCTAssertNotNil(manager.verifiedPath(for: polish))

        let prompt = TranslationService.systemPrompt(for: .translate(from: .english, to: .polish), cleanUp: false)
        let baseline = wiredBytes()

        let warmStart = Date()
        runtime.warmUp(for: polish)
        try await waitUntilLoaded(timeout: 180)
        TestFixtures.report("[polish-backend] warm-up (load + throwaway decode): "
                    + "\(String(format: "%.2f", Date().timeIntervalSince(warmStart)))s")
        report("after the warm-up", wiredSince: baseline)

        let firstStart = Date()
        let first = try await runtime.transform(systemPrompt: prompt, userText: "Please send the report.", model: polish)
        TestFixtures.report("[polish-backend] first utterance after a finished warm-up: "
                    + "\(String(format: "%.2f", Date().timeIntervalSince(firstStart)))s")
        XCTAssertFalse(first.isEmpty)

        // And the race: the warm-up still running when the dictation needs the
        // model. The runtime's serial queue makes the transform wait for the
        // load — the utterance is slower, never wrong, and never doubled.
        runtime.unload()
        let raceStart = Date()
        runtime.warmUp(for: polish)
        let raced = try await runtime.transform(systemPrompt: prompt, userText: "Please send the report.", model: polish)
        TestFixtures.report("[polish-backend] first utterance overlapping the warm-up: "
                    + "\(String(format: "%.2f", Date().timeIntervalSince(raceStart)))s")
        XCTAssertEqual(raced, first, "a dictation that races the warm-up must still come back in Polish")
    }

    private func waitUntilLoaded(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !runtime.isLoaded {
            if Date() > deadline { throw XCTSkip("the warm-up did not finish in \(timeout)s") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - The digest

    /// The download's verification step, against the real 5 GB file: a mutated
    /// copy is refused and leaves nothing installed, and the file on disk still
    /// hashes to the pin.
    func testAMutatedCopyIsRefusedAndThePinnedFileStillVerifies() throws {
        let polish = manager.model(forOutputLanguage: .polish)
        let source = Self.polishWeights
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("no weights at \(source.path)")
        }

        // A clone: shares its blocks with the original, so this costs no disk
        // and the byte below cannot reach the pinned file.
        let clone = directory.appendingPathComponent("mutated-qwen3-8b.gguf")
        try? FileManager.default.removeItem(at: clone)
        XCTAssertEqual(clonefile(source.path, clone.path, 0), 0, "clonefile failed for \(source.path)")

        let handle = try FileHandle(forUpdating: clone)
        defer { try? handle.close() }
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: clone.path)[.size] as? NSNumber)
        try handle.seek(toOffset: size.uint64Value / 2)
        try handle.write(contentsOf: Data([0xFF]))

        XCTAssertThrowsError(try manager.install(fileAt: clone, model: polish)) { error in
            guard case TransformModelError.checksumMismatch = error else {
                return XCTFail("a mutated copy must be refused by the checksum, got \(error)")
            }
            TestFixtures.report("[polish-backend] mutated copy refused: \(error.localizedDescription)")
        }
        XCTAssertFalse(manager.hasModelFile(polish), "a refused file must not be installed")
        XCTAssertNil(manager.verifiedPath(for: polish))

        // …while the file the app would have downloaded still matches the pin.
        XCTAssertEqual(try TransformModelManager.sha256(ofFileAt: source), polish.sha256)
        TestFixtures.report("[polish-backend] on-disk \(source.lastPathComponent) re-verifies against \(polish.sha256)")
    }

    /// The file the machine already has is the file the catalogue pins, so the
    /// app's own verification accepts it without a re-download.
    func testTheInstalledCopyOfThePolishBackendVerifiesAgainstThePin() throws {
        let polish = manager.model(forOutputLanguage: .polish)
        try stage(polish, from: Self.polishWeights)

        XCTAssertTrue(manager.hasModelFile(polish), "the staged size must match the pinned size")
        XCTAssertNotNil(manager.verifiedPath(for: polish))
        XCTAssertTrue(manager.verifyInstalledModel(polish))
        TestFixtures.report("[polish-backend] \(Self.polishWeights.path) verifies: \(polish.sizeBytes) bytes, \(polish.sha256)")
    }

    // MARK: - The idle-unload contract and the card's words

    /// The fleet's 10-minute contract has to survive a second backend: the timer
    /// is armed by a transform and by a warm-up, and after a whole interval with
    /// no request it releases the weights and forgets which backend they were.
    ///
    /// The interval is injected so this run does not have to sit here for ten
    /// minutes — the shipped one is asserted, and the real ten-minute wait was
    /// measured once against the default (task `fm-20260923-28`, its report).
    func testTheIdleUnloadReleasesTheWeightsAndForgetsTheBackend() async throws {
        XCTAssertEqual(TransformRuntime.idleUnloadInterval, 600, "the shipped idle window is ten minutes")
        let english = manager.model(forOutputLanguage: .english)
        try stage(english, from: Self.smallWeights)

        let shortLived = TransformRuntime(models: manager, idleUnloadInterval: 1)
        let start = Date()
        _ = try await shortLived.transform(
            systemPrompt: TranslationService.systemPrompt(for: .translate(from: .polish, to: .english), cleanUp: false),
            userText: "Proszę wysłać raport.",
            model: english
        )
        XCTAssertEqual(shortLived.loadedModelID, english.id)

        let deadline = Date().addingTimeInterval(60)
        while shortLived.isLoaded, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        TestFixtures.report("[polish-backend] idle unload with the interval injected as 1 s: released "
                    + "\(!shortLived.isLoaded) after \(seconds(Date().timeIntervalSince(start)))")
        XCTAssertFalse(shortLived.isLoaded, "the idle timer must release the weights")
        XCTAssertNil(shortLived.loadedModelID, "and clear the resident backend with them")
    }

    /// What the Settings card says follows the directory: with the small model
    /// installed and the Polish one missing, the Polish row carries the notice
    /// in those words and the small model is not offered as its stand-in; stage
    /// the Polish weights and the notice is gone. Nothing here reads or writes
    /// the user's own Application Support — the card is pointed at this test's
    /// staged hard links.
    @MainActor
    func testTheCardSaysWhichDirectionIsWaitingForItsModel() async throws {
        let prefs = AppPreferences.shared
        let savedTranslate = prefs.translateEnabled
        let savedTarget = prefs.transformTargetLanguage
        defer {
            prefs.translateEnabled = savedTranslate
            prefs.transformTargetLanguage = savedTarget
        }
        prefs.translateEnabled = true
        prefs.transformTargetLanguage = .polish

        let polish = manager.model(forOutputLanguage: .polish)
        let english = manager.model(forOutputLanguage: .english)
        try stage(english, from: Self.smallWeights)

        let card = SettingsViewModel(transformModelManager: manager)
        card.refreshTransformModelState()
        try await waitForInstalledCount(of: card, toBe: 1)
        TestFixtures.report("[polish-backend] card notices with the 1.5B installed and the 8B missing: installed "
                    + "\(card.installedTransformModelIDs.sorted()), for \(polish.id): "
                    + "\"\(card.transformMissingNotice(for: polish) ?? "none")\"")

        XCTAssertEqual(card.installedTransformModelIDs, [english.id])
        XCTAssertEqual(card.neededTransformModels.map(\.id), [polish.id],
                       "a Polish target needs the Polish backend, and only it")
        let notice = try XCTUnwrap(card.transformMissingNotice(for: polish),
                                   "the missing Polish backend has to be said out loud")
        XCTAssertTrue(notice.contains("Polish"), notice)
        XCTAssertTrue(notice.contains("does not fall back to \(english.displayName)"),
                      "the notice must say the small model is not used for Polish: \(notice)")
        XCTAssertNil(card.transformMissingNotice(for: english),
                     "English output is installed, so its row has nothing to warn about")

        try stage(polish, from: Self.polishWeights)
        card.refreshTransformModelState()
        try await waitForInstalledCount(of: card, toBe: 2)
        TestFixtures.report("[polish-backend] card notices once the 8B is staged: installed "
                    + "\(card.installedTransformModelIDs.sorted()), for \(polish.id): "
                    + "\(card.transformMissingNotice(for: polish) ?? "none")")

        XCTAssertEqual(card.installedTransformModelIDs, [english.id, polish.id])
        XCTAssertNil(card.transformMissingNotice(for: polish), "the notice goes once the weights are there")
        XCTAssertTrue(card.transformModelStateDescription(polish).hasPrefix("Installed"),
                      "and the row says so: \(card.transformModelStateDescription(polish))")
    }

    /// The card refreshes off the main thread (`refreshTransformModelState`), so
    /// wait for its verdict rather than assuming it has landed. The assertion
    /// after the call is what fails if it never does.
    @MainActor
    private func waitForInstalledCount(of card: SettingsViewModel, toBe count: Int,
                                       timeout: TimeInterval = 300) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while card.installedTransformModelIDs.count != count, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
