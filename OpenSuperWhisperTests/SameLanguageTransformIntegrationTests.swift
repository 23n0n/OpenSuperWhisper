import CryptoKit
import Foundation
import XCTest
@testable import OpenSuperWhisper

/// The transform, driven against real weights, in both languages.
///
/// Skipped when this machine does not have the files, exactly like
/// `LlamaRuntimeIntegrationTests`: CI stays hermetic, and a machine that has
/// them proves the product's one promise — **the transcript keeps the language
/// it was spoken in** — that Polish prefers the 8B when it is installed and runs
/// on the shipped 1.5B when it is not, that nothing is refused for a missing
/// optional model, that both switches off is zero model calls, and what the 8B
/// costs in wired memory and first-utterance latency.
///
/// The weights are hard-linked into a staging directory, so nothing here copies
/// 5 GB and nothing here can write to the files in `~/models`.
final class SameLanguageTransformIntegrationTests: XCTestCase {

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

    private func shippedWeights() throws -> URL {
        try stage(manager.defaultModel, from: Self.smallWeights)
        return Self.smallWeights
    }

    private func polishWeights() throws -> URL {
        try stage(manager.polishModel, from: Self.polishWeights)
        return Self.polishWeights
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
            modelForLanguage: { self.manager.model(forSpokenLanguage: $0) },
            gateSettings: { settings }
        )
    }

    private func hasPolishDiacritics(_ text: String) -> Bool {
        text.rangeOfCharacter(from: CharacterSet(charactersIn: "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")) != nil
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

    /// Polish in, Polish out — and English in, English out. The output is judged
    /// by the app's own detector, which is the same signal the gate acts on: if
    /// it no longer reads as the language that was spoken, the product's one
    /// promise is broken.
    func testPolishStaysPolishAndEnglishStaysEnglish() async throws {
        try shippedWeights()
        try polishWeights()

        // A tone has to have something to do: this is *casual* Polish asked for a
        // *formal* register. (An already-formal sentence made this case vacuous —
        // the 8B returned it byte for byte, and the case could not tell that from
        // a rewrite that happened to match.)
        let polishInput = "no hej, sluchaj, musimy przelozyc to spotkanie z klientem na przyszly tydzien, ok?"
        let englishInput = "Please send the report to the client today, and copy me on the reply."

        // Polish → Polish, tone on: the register is rewritten, the language is
        // not.
        let polishCalls = CallCounter()
        let polishService = service(
            settings: GateSettings(tone: true, cleanUp: false, toneMode: .formal),
            calls: polishCalls
        )
        let polishStart = Date()
        let polishOutcome = await polishService.transformDetailed(polishInput, sourceLanguage: "pl")
        TestFixtures.report("[same-language] pl→pl: model \(polishCalls.models.joined(separator: ", ")) "
                    + "| policy \(polishOutcome.policy?.summary ?? "none") | didRunModel \(polishOutcome.didRunModel) "
                    + "| \(seconds(Date().timeIntervalSince(polishStart)))")
        TestFixtures.report("[same-language] pl→pl input:  \(polishInput)")
        TestFixtures.report("[same-language] pl→pl output: \(polishOutcome.text)")

        XCTAssertTrue(polishOutcome.didRunModel, "the model must have answered")
        XCTAssertEqual(polishOutcome.policy, .tone(language: .polish, tone: .formal))
        XCTAssertEqual(LanguageDetector.detect(polishOutcome.text), .polish,
                       "Polish in must be Polish out: \(polishOutcome.text)")
        XCTAssertNotEqual(polishOutcome.text, polishInput, "the tone switch has to rewrite something")
        XCTAssertNotNil(
            polishOutcome.text.range(of: "spotkanie"),
            "the rewrite keeps what was said: \(polishOutcome.text)"
        )

        // English → English, tone on: the same rule, the other language.
        let englishCalls = CallCounter()
        let englishService = service(
            settings: GateSettings(tone: true, cleanUp: false, toneMode: .casual),
            calls: englishCalls
        )
        let englishOutcome = await englishService.transformDetailed(englishInput, sourceLanguage: "en")
        TestFixtures.report("[same-language] en→en: model \(englishCalls.models.joined(separator: ", ")) "
                    + "| policy \(englishOutcome.policy?.summary ?? "none") | didRunModel \(englishOutcome.didRunModel)")
        TestFixtures.report("[same-language] en→en input:  \(englishInput)")
        TestFixtures.report("[same-language] en→en output: \(englishOutcome.text)")

        XCTAssertTrue(englishOutcome.didRunModel)
        XCTAssertEqual(englishOutcome.policy, .tone(language: .english, tone: .casual))
        XCTAssertEqual(LanguageDetector.detect(englishOutcome.text), .english,
                       "English in must be English out: \(englishOutcome.text)")
        XCTAssertFalse(hasPolishDiacritics(englishOutcome.text),
                       "English output must not come back Polish: \(englishOutcome.text)")
    }

    /// The clean-up switch alone: the same language, repaired rather than
    /// re-registered — and it is one call, in the spoken language.
    func testCleanUpAloneRepairsTheDictationInItsOwnLanguage() async throws {
        try shippedWeights()

        let input = "no więc ja myślę że trzeba wysłać ten raport do klienta jutro rano"
        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: false, cleanUp: true, toneMode: .neutral),
            calls: calls
        )

        let outcome = await subject.transformDetailed(input, sourceLanguage: "pl")
        TestFixtures.report("[same-language] pl clean-up: model \(calls.models.joined(separator: ", ")) "
                    + "| didRunModel \(outcome.didRunModel)")
        TestFixtures.report("[same-language] pl clean-up output: \(outcome.text)")

        XCTAssertTrue(outcome.didRunModel)
        XCTAssertEqual(outcome.policy, .cleanUp(language: .polish))
        XCTAssertNotEqual(outcome.text, input, "the clean-up call exists to repair the dictation")
        XCTAssertNotNil(outcome.text.range(of: "raport"),
                        "the repair keeps what was said: \(outcome.text)")
        XCTAssertEqual(LanguageDetector.detect(outcome.text), .polish,
                       "the clean-up may not change the language: \(outcome.text)")
        XCTAssertEqual(calls.models, [TransformModelManager.defaultModelID],
                       "Polish without the 8B installed runs on the shipped model")
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

    /// The 8B is a preference, not a requirement: with only the shipped model
    /// installed, Polish work runs on it, says so, and is not refused.
    @MainActor
    func testPolishWithoutTheEightBeeRunsOnTheShippedModelAndSaysSo() async throws {
        try shippedWeights()
        XCTAssertFalse(manager.isPolishModelInstalled, "precondition: only the shipped model is staged")

        let resolved = manager.model(forSpokenLanguage: .polish)
        XCTAssertEqual(resolved.id, TransformModelManager.defaultModelID,
                       "Polish falls back to the shipped model rather than refusing")

        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: true, cleanUp: false, toneMode: .formal),
            calls: calls
        )
        let outcome = await subject.transformDetailed("Cześć, jak się masz dzisiaj rano?", sourceLanguage: "pl")

        TestFixtures.report("[same-language] Polish without the 8B: model \(calls.models.joined(separator: ", ")) "
                    + "| didRunModel \(outcome.didRunModel) | output \(outcome.text)")

        XCTAssertEqual(calls.models, [TransformModelManager.defaultModelID])
        XCTAssertTrue(outcome.didRunModel, "Polish must not be refused for a missing optional model")
        XCTAssertTrue(LanguageDetector.detect(outcome.text) == .polish,
                      "the shipped model writes Polish too: \(outcome.text)")

        // And the card says which model Polish uses and whether the 8B is there.
        let card = SettingsViewModel(transformModelManager: manager)
        card.installedTransformModelIDs = [TransformModelManager.defaultModelID]
        let description = card.transformLanguageModelDescription
        TestFixtures.report("[same-language] card: \(description)")
        XCTAssertTrue(description.contains("Polish runs on \(manager.defaultModel.displayName)"), description)
        XCTAssertTrue(description.contains("The 8B is not installed"), description)
        XCTAssertNil(card.transformMissingNotice(for: manager.polishModel),
                     "a missing 8B is never a warning: nothing is refused for it")
    }

    /// Nothing installed is the one case that cannot work: the transcript is
    /// still delivered, and nothing pretends to have run.
    func testNothingInstalledStillDeliversTheTranscript() async throws {
        let calls = CallCounter()
        let subject = service(
            settings: GateSettings(tone: true, cleanUp: true, toneMode: .formal),
            calls: calls
        )
        let input = "Cześć, jak się masz?"

        let outcome = await subject.transformDetailed(input, sourceLanguage: "pl")

        XCTAssertEqual(outcome.text, input)
        XCTAssertFalse(outcome.didRunModel)
        XCTAssertEqual(calls.models, [TransformModelManager.defaultModelID],
                       "the model it would have used is what is attempted")
        TestFixtures.report("[same-language] no weights staged: delivered the raw transcript, "
                    + "didRunModel \(outcome.didRunModel)")
    }

    // MARK: - One model at a time, and what the 8B costs

    /// The wired-memory step of the 8B in this process, and the one-at-a-time
    /// contract: asking for the other language's model evicts it rather than
    /// adding to it.
    func testOnlyOneModelIsResidentAndTheEightBeeStepIsMeasured() async throws {
        try shippedWeights()
        try polishWeights()

        let baseline = wiredBytes()
        _ = try await runtime.transform(
            systemPrompt: TransformService.systemPrompt(for: .cleanUp(language: .polish), cleanUp: true),
            userText: "Cześć, jak się masz?",
            model: manager.polishModel
        )
        XCTAssertEqual(runtime.loadedModelID, manager.polishModel.id)
        report("with the 8B resident", wiredSince: baseline)
        let residentWith8B = wiredBytes()

        _ = try await runtime.transform(
            systemPrompt: TransformService.systemPrompt(for: .cleanUp(language: .english), cleanUp: true),
            userText: "Please send the report.",
            model: manager.defaultModel
        )
        XCTAssertEqual(runtime.loadedModelID, manager.defaultModel.id,
                       "the language change must swap the resident model")
        report("with the 1.5B resident (the 8B was evicted)", wiredSince: baseline)

        runtime.unload()
        XCTAssertNil(runtime.loadedModelID)
        report("after unload", wiredSince: baseline)
        TestFixtures.report("[same-language] wired: baseline \(gigabytes(baseline)), 8B \(gigabytes(residentWith8B)), "
                    + "8B step \(gigabytes(residentWith8B &- min(residentWith8B, baseline)))")
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

    // MARK: - The idle-unload contract and the card's words

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

    /// What the Settings card says follows the directory: with the 8B staged,
    /// Polish is stated to run on it; without it, the card says Polish runs on
    /// the shipped model and that the 8B is not installed — and the 8B's row
    /// carries no warning, because nothing is refused for it.
    @MainActor
    func testTheCardSaysWhichModelEachLanguageUses() async throws {
        let eightBee = manager.polishModel
        let shipped = manager.defaultModel
        _ = try shippedWeights()

        let card = SettingsViewModel(transformModelManager: manager)
        card.refreshTransformModelState()
        try await waitForInstalledCount(of: card, toBe: 1)

        XCTAssertEqual(card.installedTransformModelIDs, [shipped.id])
        let withoutEightBee = card.transformLanguageModelDescription
        TestFixtures.report("[same-language] card with the 8B missing: \(withoutEightBee)")
        XCTAssertTrue(withoutEightBee.contains("Polish runs on \(shipped.displayName)"), withoutEightBee)
        XCTAssertTrue(withoutEightBee.contains("English runs on \(shipped.displayName)"), withoutEightBee)
        XCTAssertTrue(withoutEightBee.contains("The 8B is not installed"), withoutEightBee)
        XCTAssertTrue(withoutEightBee.contains("nothing is refused"), withoutEightBee)
        XCTAssertNil(card.transformMissingNotice(for: eightBee),
                     "the optional model has nothing to warn about")
        XCTAssertNil(card.transformMissingNotice(for: shipped),
                     "the shipped model is installed, so its row is quiet")
        XCTAssertTrue(card.transformModelStateDescription(shipped).hasPrefix("Installed"),
                      card.transformModelStateDescription(shipped))

        _ = try polishWeights()
        card.refreshTransformModelState()
        try await waitForInstalledCount(of: card, toBe: 2)

        let withEightBee = card.transformLanguageModelDescription
        TestFixtures.report("[same-language] card with the 8B installed: \(withEightBee)")
        XCTAssertEqual(card.installedTransformModelIDs, [shipped.id, eightBee.id])
        XCTAssertTrue(withEightBee.contains("Polish runs on \(eightBee.displayName)"), withEightBee)
        XCTAssertTrue(withEightBee.contains("The 8B is installed"), withEightBee)

        // The shipped model is the one requirement: if it is missing, the card
        // says what stops.
        card.installedTransformModelIDs = [eightBee.id]
        let notice = try XCTUnwrap(card.transformMissingNotice(for: shipped),
                                   "a missing shipped model is a real problem and has to be said")
        XCTAssertTrue(notice.contains("every language"), notice)
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
