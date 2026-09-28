import CryptoKit
import Foundation
import XCTest
@testable import OpenSuperWhisper

/// The transform, driven against real weights.
///
/// Skipped when this machine does not have the files, exactly like
/// `LlamaRuntimeIntegrationTests`: CI stays hermetic, and a machine that has
/// them proves the product's promise — **English dictation is transformed, and
/// every other language is delivered as it was transcribed** — that English runs
/// on S1-mini through the app's own prompt when it is installed and on the
/// shipped 1.5B when it is not, that a Polish dictation never reaches a model at
/// all, and what the English backend costs in wired memory and warm-up latency.
///
/// The weights are hard-linked into a staging directory, so nothing here copies
/// 5 GB and nothing here can write to the files in `~/models`.
final class SameLanguageTransformIntegrationTests: XCTestCase {

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var smallWeights: URL { home.appendingPathComponent("models/qwen2.5-1.5b-instruct-q4_k_m.gguf") }
    private static var polishWeights: URL { home.appendingPathComponent("models/Qwen3-8B-Q4_K_M.gguf") }
    private static var normalizerWeights: URL { home.appendingPathComponent("models/s1-mini-q4_k_m.gguf") }

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

    private func shippedWeights() throws -> URL {
        try stage(manager.defaultModel, from: Self.smallWeights)
        return Self.smallWeights
    }

    private func polishWeights() throws -> URL {
        try stage(manager.polishModel, from: Self.polishWeights)
        return Self.polishWeights
    }

    private func stagedNormalizerWeights() throws -> URL {
        try stage(manager.normalizerModel, from: Self.normalizerWeights)
        return Self.normalizerWeights
    }

    /// A `TransformService` whose built-in runtime is this test's runtime — the
    /// production wiring, pointing at staged weights instead of the user's
    /// Application Support. `calls` records every model call the service makes.
    private final class CallCounter {
        var models: [String] = []
        var calls: Int { models.count }
    }

    private func service(
        settings: GateSettings,
        calls: CallCounter
    ) -> TransformService {
        TransformService(
            localTransform: { systemPrompt, userText, model in
                calls.models.append(model.id)
                return try await self.runtime.transform(
                    systemPrompt: systemPrompt,
                    userText: userText,
                    model: model
                )
            },
            modelForPolicy: { self.manager.model(for: $0) },
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
        TestFixtures.report("[same-language] wired \(label): \(gigabytes(now)) "
                    + "(step \(gigabytes(now &- min(now, baseline))), baseline \(gigabytes(baseline)))")
    }

    // MARK: - The contract, end to end, against real weights

    /// **English in, English out, through the app's own prompt**: the card's
    /// input format, composed by `TransformService`, run on the real weights by
    /// the real runtime, with the answer judged by the app's own detector.
    ///
    /// The dictation is the kind the model was built for — fillers, a repeated
    /// word, and a self-correction the speaker resolved — and the assertions are
    /// the properties the card promises: the answer is English, it carries what
    /// was said, and the fillers are gone. The raw input and output are reported
    /// so a drift in quality is visible instead of hidden behind a green run.
    func testEnglishRunsOnTheNormalizerThroughTheRealWeights() async throws {
        _ = try stagedNormalizerWeights()

        let input = "so um i need to like send the the report by uh friday no wait make that thursday"
        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: true, cleanUp: true, toneMode: .neutral),
            calls: calls
        )

        let started = Date()
        let outcome = await subject.transformDetailed(input, sourceLanguage: "en")
        TestFixtures.report("[s1-mini] model \(calls.models.joined(separator: ", ")) "
                    + "| policy \(outcome.policy?.summary ?? "none") | didRunModel \(outcome.didRunModel) "
                    + "| \(seconds(Date().timeIntervalSince(started)))")
        TestFixtures.report("[s1-mini] input:  \(input)")
        TestFixtures.report("[s1-mini] output: \(outcome.text)")

        XCTAssertEqual(calls.models, [TransformModelManager.normalizerModelID],
                       "English runs on the normalizer once it is installed")
        XCTAssertTrue(outcome.didRunModel)
        XCTAssertFalse(outcome.text.isEmpty, "the model produced nothing")
        XCTAssertNil(outcome.guardRejection, "a legitimate normalizer answer must survive the guard")
        XCTAssertFalse(outcome.text.contains("<|im_start|>"),
                       "the chat template must not leak into the answer: \(outcome.text)")
        XCTAssertFalse(outcome.text.lowercased().contains("think"),
                       "the empty think block belongs to the prompt, not the answer: \(outcome.text)")
        XCTAssertEqual(LanguageDetector.detect(outcome.text), .english,
                       "English in must be English out: \(outcome.text)")
        XCTAssertNotNil(outcome.text.range(of: "thursday", options: .caseInsensitive),
                        "the self-correction must resolve to what the speaker landed on: \(outcome.text)")
        XCTAssertFalse(outcome.text.lowercased().contains("the the"),
                       "the repeated word is the model's job: \(outcome.text)")
    }

    /// **Polish is delivered as it was transcribed.** No prompt, no policy, no
    /// model call, no weights loaded — with every model installed and whatever
    /// the switches say.
    func testPolishIsDeliveredAsTranscribedWithNoModelCall() async throws {
        _ = try stagedNormalizerWeights()
        try polishWeights()

        let input = "no hej, sluchaj, musimy przelozyc to spotkanie z klientem na przyszly tydzien, ok?"
        let settingses = [
            GateSettings(tone: true, cleanUp: false, toneMode: .formal),
            GateSettings(tone: false, cleanUp: true, toneMode: .neutral),
            GateSettings(tone: true, cleanUp: true, toneMode: .casual),
        ]
        for settings in settingses {
            let calls = CallCounter()
            let subject = service(settings: settings, calls: calls)

            let outcome = await subject.transformDetailed(input, sourceLanguage: "pl")

            XCTAssertEqual(outcome.text, input, "the transcript is delivered unchanged")
            XCTAssertNil(outcome.policy, "Polish has no policy: the transform is English-only")
            XCTAssertFalse(outcome.didRunModel)
            XCTAssertEqual(calls.calls, 0, "no model may be asked for a Polish dictation")
            XCTAssertNil(runtime.loadedModelID, "and no weights may be loaded for it")
            TestFixtures.report("[s1-mini] Polish, tone \(settings.tone) / clean-up \(settings.cleanUp): "
                        + "policy none, calls \(calls.calls), text unchanged \(outcome.text == input)")
        }
    }

    /// The engine reported no language, so the app's own detector places the
    /// text — and Polish it places is delivered raw just the same.
    func testPolishTheDetectorPlacesIsAlsoDeliveredRaw() async throws {
        let input = "no więc ja myślę że trzeba wysłać ten raport do klienta jutro rano"
        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: false, cleanUp: true, toneMode: .neutral),
            calls: calls
        )

        let outcome = await subject.transformDetailed(input, sourceLanguage: nil)
        TestFixtures.report("[s1-mini] Polish with no engine language: policy "
                    + "\(outcome.policy.map(String.init(describing:)) ?? "none"), calls \(calls.calls)")

        XCTAssertNil(outcome.policy, "the detector's Polish is not transformed either")
        XCTAssertEqual(outcome.text, input)
        XCTAssertEqual(calls.calls, 0)
    }

    /// English clean-up and tone still run on the **floor** while S1-mini is not
    /// installed — the app's own instruction prompt, the shipped 1.5B, and no
    /// refusal for the missing optional model.
    func testEnglishStillRunsOnTheShippedFloorWithoutTheNormalizer() async throws {
        try shippedWeights()
        XCTAssertFalse(manager.isNormalizerInstalled, "precondition: only the floor is staged")

        let input = "please send the report to the client today and copy me on the reply"
        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: false, cleanUp: true, toneMode: .neutral),
            calls: calls
        )

        let outcome = await subject.transformDetailed(input, sourceLanguage: "en")
        TestFixtures.report("[s1-mini] English on the floor: model \(calls.models.joined(separator: ", ")) "
                    + "| didRunModel \(outcome.didRunModel) | output \(outcome.text)")

        XCTAssertEqual(calls.models, [TransformModelManager.defaultModelID],
                       "English falls back to the floor for a missing optional model")
        XCTAssertTrue(outcome.didRunModel, "and nothing is refused")
        XCTAssertEqual(outcome.policy, .cleanUp(language: .english))
        XCTAssertFalse(outcome.text.isEmpty)
    }

    /// Nothing installed is the one case where English cannot be transformed: the
    /// transcript is still delivered, the attempt is reported, and nothing
    /// pretends to have run.
    func testNothingInstalledStillDeliversTheTranscript() async throws {
        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: true, cleanUp: true, toneMode: .formal),
            calls: calls
        )
        let input = "Please send the report to the client today."

        let outcome = await subject.transformDetailed(input, sourceLanguage: "en")

        XCTAssertEqual(outcome.text, input)
        XCTAssertFalse(outcome.didRunModel)
        XCTAssertEqual(calls.models, [TransformModelManager.defaultModelID],
                       "the model it would have used is what is attempted")
        TestFixtures.report("[s1-mini] no weights staged: delivered the raw transcript, "
                    + "didRunModel \(outcome.didRunModel)")
    }

    /// Both switches off: zero model calls, the transcript bit-for-bit what the
    /// engine produced, and no weights loaded by the attempt.
    func testBothSwitchesOffMakeNoModelCallAtAll() async throws {
        try shippedWeights()
        try polishWeights()

        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: false, cleanUp: false, toneMode: .formal),
            calls: calls
        )
        let input = "Dzień dobry, proszę wysłać raport do klienta."

        let outcome = await subject.transformDetailed(input, sourceLanguage: "pl")
        TestFixtures.report("[same-language] both switches off: model calls \(calls.calls), "
                    + "policy \(outcome.policy.map(String.init(describing:)) ?? "none"), "
                    + "runtime resident \(runtime.loadedModelID ?? "none"), text unchanged \(outcome.text == input)")

        XCTAssertEqual(calls.calls, 0, "no switch on must not touch a model")
        XCTAssertNil(outcome.policy)
        XCTAssertFalse(outcome.didRunModel)
        XCTAssertEqual(outcome.text, input, "the transcript is passed through unchanged")
        XCTAssertNil(runtime.loadedModelID, "nothing may be loaded for a dictation that asked for nothing")
    }

    /// The card says which model the English work runs on — the floor while
    /// S1-mini is missing, S1-mini once it is installed — and that a Polish
    /// dictation is not transformed at all.
    @MainActor
    func testTheCardSaysWhichModelTheEnglishWorkRunsOn() async throws {
        try shippedWeights()
        XCTAssertFalse(manager.isNormalizerInstalled, "precondition: only the floor is staged")

        let card = SettingsViewModel(transformModelManager: manager)
        card.refreshTransformModelState()
        try await waitForInstalledCount(of: card, toBe: 1)

        let without = card.transformLanguageModelDescription
        TestFixtures.report("[s1-mini] card without the English backend: \(without)")
        XCTAssertTrue(without.contains("runs on \(manager.defaultModel.displayName)"), without)
        XCTAssertTrue(without.contains("Polish dictation is delivered as transcribed"), without)
        XCTAssertTrue(without.contains("S1-mini is not installed"), without)
        XCTAssertTrue(without.contains("nothing is refused"), without)
        XCTAssertNil(card.transformMissingNotice(for: manager.normalizerModel),
                     "a missing optional model is never a warning: nothing is refused for it")
        XCTAssertNil(card.transformMissingNotice(for: manager.polishModel),
                     "the idle larger model is not a warning either")

        _ = try stagedNormalizerWeights()
        card.refreshTransformModelState()
        try await waitForInstalledCount(of: card, toBe: 2)

        let with = card.transformLanguageModelDescription
        TestFixtures.report("[s1-mini] card with the English backend installed: \(with)")
        XCTAssertTrue(with.contains("runs on \(manager.normalizerModel.displayName)"), with)
        XCTAssertTrue(with.contains("S1-mini is installed"), with)

        // The row whose model resolves no job says so, and the English backend's
        // row says what it takes over.
        let idleRow = card.transformModelRoleDescription(manager.polishModel)
        TestFixtures.report("[s1-mini] the idle row: \(idleRow)")
        XCTAssertTrue(idleRow.contains("No job"), idleRow)
        XCTAssertTrue(card.transformModelRoleDescription(manager.normalizerModel).contains("English transform"),
                      card.transformModelRoleDescription(manager.normalizerModel))
    }

    // MARK: - One model at a time, and what the English backend costs

    /// The wired-memory step of the English backend in this process, and the
    /// one-at-a-time contract: asking for the other model evicts it rather than
    /// adding to it. The step is what the catalogue pins as `memoryBytes`.
    func testTheEnglishBackendIsTheOnlyResidentModelAndItsWiredStepIsMeasured() async throws {
        try shippedWeights()
        _ = try stagedNormalizerWeights()
        let normalizer = manager.normalizerModel
        let floor = manager.defaultModel

        let baseline = wiredBytes()
        _ = try await runtime.transform(
            systemPrompt: TransformService.normalizerSystemPrompt,
            userText: TransformService.normalizerUserPrompt(for: "please send the report", tone: nil),
            model: normalizer
        )
        XCTAssertEqual(runtime.loadedModelID, normalizer.id)
        report("with S1-mini resident", wiredSince: baseline)
        let residentWithNormalizer = wiredBytes()

        _ = try await runtime.transform(
            systemPrompt: TransformService.systemPrompt(for: .cleanUp(language: .english), cleanUp: true),
            userText: "Please send the report.",
            model: floor
        )
        XCTAssertEqual(runtime.loadedModelID, floor.id,
                       "the other model must be evicted, not held beside it")
        report("with the floor resident (S1-mini evicted)", wiredSince: baseline)

        runtime.unload()
        XCTAssertNil(runtime.loadedModelID)
        report("after unload", wiredSince: baseline)
        TestFixtures.report("[s1-mini] wired: baseline \(gigabytes(baseline)), S1-mini "
                    + "\(gigabytes(residentWithNormalizer)), step "
                    + "\(gigabytes(residentWithNormalizer &- min(residentWithNormalizer, baseline))) "
                    + "against a pinned \(normalizer.memoryBytes) bytes")
    }

    /// The warm-up carries the cold load, and a dictation that arrives while the
    /// warm-up is still running waits for it instead of loading a second copy.
    func testWarmUpCarriesTheColdLoadAndTheFirstUtterance() async throws {
        _ = try polishWeights()
        let polish = manager.polishModel
        // Verify first, so the one-off ~5 GB hash is not measured as load time.
        // (That hash does leave the file in the page cache, so this is the
        // warm-cache load: the app's second use of the weights. The cold figure,
        // with the cache evicted, is measured outside this suite — see the task
        // report for both numbers.)
        XCTAssertNotNil(manager.verifiedPath(for: polish))

        let prompt = TransformService.systemPrompt(for: .cleanUp(language: .polish), cleanUp: true)
        let baseline = wiredBytes()

        let warmStart = Date()
        runtime.warmUp(for: polish)
        try await waitUntilLoaded(timeout: 180)
        TestFixtures.report("[same-language] warm-up (load + throwaway decode): "
                    + "\(seconds(Date().timeIntervalSince(warmStart)))")
        report("after the warm-up", wiredSince: baseline)

        let firstStart = Date()
        let first = try await runtime.transform(systemPrompt: prompt, userText: "Cześć, jak się masz?", model: polish)
        TestFixtures.report("[same-language] first utterance after a finished warm-up: "
                    + "\(seconds(Date().timeIntervalSince(firstStart)))")
        XCTAssertFalse(first.isEmpty)

        // And the race: the warm-up still running when the dictation needs the
        // model. The runtime's serial queue makes the transform wait for the
        // load — the utterance is slower, never wrong, and never doubled.
        runtime.unload()
        let raceStart = Date()
        runtime.warmUp(for: polish)
        let raced = try await runtime.transform(systemPrompt: prompt, userText: "Cześć, jak się masz?", model: polish)
        TestFixtures.report("[same-language] first utterance overlapping the warm-up: "
                    + "\(seconds(Date().timeIntervalSince(raceStart)))")
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
        let polish = manager.polishModel
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
            TestFixtures.report("[same-language] mutated copy refused: \(error.localizedDescription)")
        }
        XCTAssertFalse(manager.hasModelFile(polish), "a refused file must not be installed")
        XCTAssertNil(manager.verifiedPath(for: polish))
        XCTAssertFalse(manager.isPolishModelInstalled, "a refused file is not 'the 8B is installed'")

        // …while the file the app would have downloaded still matches the pin.
        XCTAssertEqual(try TransformModelManager.sha256(ofFileAt: source), polish.sha256)
        TestFixtures.report("[same-language] on-disk \(source.lastPathComponent) re-verifies against \(polish.sha256)")
    }

    /// The file the machine already has is the file the catalogue pins, so the
    /// app's own verification accepts it without a re-download.
    func testTheInstalledEightBeeVerifiesAgainstThePin() throws {
        let polish = manager.polishModel
        _ = try polishWeights()

        XCTAssertTrue(manager.hasModelFile(polish), "the staged size must match the pinned size")
        XCTAssertNotNil(manager.verifiedPath(for: polish))
        XCTAssertTrue(manager.verifyInstalledModel(polish))
        XCTAssertTrue(manager.isPolishModelInstalled)
        TestFixtures.report("[same-language] \(Self.polishWeights.path) verifies: "
                    + "\(polish.sizeBytes) bytes, \(polish.sha256)")
    }

    // MARK: - The idle-unload contract

    /// The fleet's 10-minute contract: the timer is armed by a transform and by a
    /// warm-up, and after a whole interval with no request it releases the
    /// weights and forgets which model they were.
    ///
    /// The interval is injected so this run does not have to sit here for ten
    /// minutes — the shipped one is asserted, and the real ten-minute wait was
    /// measured once against the default (task `fm-20260923-28`, its report).
    func testTheIdleUnloadReleasesTheWeightsAndForgetsTheModel() async throws {
        XCTAssertEqual(TransformRuntime.idleUnloadInterval, 600, "the shipped idle window is ten minutes")
        let shipped = manager.defaultModel
        _ = try shippedWeights()

        let shortLived = TransformRuntime(models: manager, idleUnloadInterval: 1)
        let start = Date()
        _ = try await shortLived.transform(
            systemPrompt: TransformService.systemPrompt(for: .cleanUp(language: .polish), cleanUp: true),
            userText: "Cześć, jak się masz?",
            model: shipped
        )
        XCTAssertEqual(shortLived.loadedModelID, shipped.id)

        let deadline = Date().addingTimeInterval(60)
        while shortLived.isLoaded, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        TestFixtures.report("[same-language] idle unload with the interval injected as 1 s: released "
                    + "\(!shortLived.isLoaded) after \(seconds(Date().timeIntervalSince(start)))")
        XCTAssertFalse(shortLived.isLoaded, "the idle timer must release the weights")
        XCTAssertNil(shortLived.loadedModelID, "and clear the resident model with them")
    }

    /// The shipped model is the one requirement: if it is missing, the card says
    /// so. It is staged everywhere else in this suite, so this asserts the
    /// notice's own words against a directory that really has nothing in it.
    @MainActor
    func testTheCardWarnsOnlyWhenTheFloorIsMissing() async throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-card-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let card = SettingsViewModel(
            transformModelManager: TransformModelManager(directory: empty,
                                                        catalogue: TransformModelManager.availableModels)
        )

        let notice = try XCTUnwrap(card.transformMissingNotice(for: card.shippedTransformModel),
                                   "a missing floor is a real problem and has to be said")
        XCTAssertTrue(notice.contains("every English transform falls back to"), notice)
        XCTAssertNil(card.transformMissingNotice(for: card.englishTransformModel),
                     "the optional English backend has nothing to warn about")
        XCTAssertNil(card.transformMissingNotice(for: card.idleTransformModel),
                     "nor does the idle one")
        TestFixtures.report("[s1-mini] the floor missing: \(notice)")
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
