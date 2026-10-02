import CryptoKit
import XCTest

@testable import OpenSuperWhisper

/// The Advanced tab's Debug Mode used to be a toggle that wrote a preference
/// nothing read, so it changed nothing at all. It now reaches the decoder's
/// parameters, which is the difference between a control and a decoration.
@MainActor
final class SettingsExposureTests: XCTestCase {

    private var savedDebugMode: Bool!

    override func setUp() {
        super.setUp()
        savedDebugMode = AppPreferences.shared.debugMode
    }

    override func tearDown() {
        AppPreferences.shared.debugMode = savedDebugMode
        super.tearDown()
    }

    func testDebugModeReachesTheDecoderParameters() {
        AppPreferences.shared.debugMode = true
        let on = WhisperEngine.makeFullParams(settings: Settings(), nThreads: 4,
                                              modelTextContext: 448, initialPromptTokenCount: 0)
        XCTAssertTrue(on.debugMode, "Debug Mode has to turn the decoder's verbose trace on")

        AppPreferences.shared.debugMode = false
        let off = WhisperEngine.makeFullParams(settings: Settings(), nThreads: 4,
                                               modelTextContext: 448, initialPromptTokenCount: 0)
        XCTAssertFalse(off.debugMode, "…and off again when the toggle is off")
    }

    func testTheSettingsSnapshotCarriesTheStoredDebugMode() {
        AppPreferences.shared.debugMode = true
        XCTAssertTrue(Settings().debugMode, "the per-dictation settings read the preference")
    }

    // MARK: - The transform model card

    /// A view model over a temporary directory and a small stand-in for the two
    /// catalogue entries (same ids, same shape, bytes instead of gigabytes), so
    /// what the card says is decided by this test's staging and nothing here
    /// touches the user's Application Support.
    private func card() throws -> (SettingsViewModel, TransformModelManager, URL, TransformModel, TransformModel) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-card-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let payload = Data(repeating: 0x5A, count: 512)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        func entry(_ id: String, _ name: String, _ file: String,
                   style: TransformPromptStyle) -> TransformModel {
            TransformModel(
                id: id,
                displayName: name,
                fileName: file,
                style: style,
                downloadURL: URL(string: "https://example.invalid/\(file)")!,
                sha256: digest,
                sizeBytes: Int64(payload.count),
                memoryBytes: 1024,
                licence: "Apache-2.0",
                source: "test"
            )
        }
        let shipped = entry(TransformModelManager.defaultModelID, "Shipped Test Model", "shipped.gguf",
                            style: .instruction)
        let normalizer = entry(TransformModelManager.normalizerModelID, "S1-mini Test Model", "s1-mini.gguf",
                               style: .normalizer)

        let manager = TransformModelManager(directory: directory,
                                           catalogue: [normalizer, shipped])
        let model = SettingsViewModel(transformModelManager: manager)
        return (model, manager, directory, shipped, normalizer)
    }

    /// Stages `model`'s bytes in the manager's own directory, so the card's
    /// "is it installed" answer comes from a real verified file.
    private func stage(_ model: TransformModel, in manager: TransformModelManager, directory: URL) throws {
        let source = directory.appendingPathComponent("source-\(model.id).gguf")
        let payload = Data(repeating: 0x5A, count: Int(model.sizeBytes))
        try payload.write(to: source)
        try manager.install(fileAt: source, model: model)
    }

    /// The card says which model the work uses — and states, rather than warns,
    /// that English runs on the floor while S1-mini is not installed, and that a
    /// Polish dictation is delivered as transcribed. Nothing is refused for a
    /// missing optional model.
    ///
    /// What is asserted is the model the card is built from: `model(for:)` is
    /// what the description reads, so pinning the resolution pins the claim
    /// without pinning the sentence that carries it.
    func testTheCardSaysWhichModelTheEnglishWorkUses() throws {
        let (model, manager, directory, shipped, normalizer) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        model.installedTransformModelIDs = [shipped.id]

        let description = model.transformLanguageModelDescription
        XCTAssertTrue(description.contains("runs on \(shipped.displayName)"), description)
        XCTAssertTrue(description.contains("Polish dictation is delivered as transcribed"), description)
        XCTAssertTrue(description.contains("S1-mini is not installed"), description)
        XCTAssertTrue(description.contains("nothing is refused"), description)
        // English falls back to the floor for every job while S1-mini is absent
        // — the resolution behind the card's sentence.
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .neutral)).id, shipped.id)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, shipped.id)

        // The floor is the only requirement; the optional English backend is not a
        // warning while it is missing.
        XCTAssertNil(model.transformMissingNotice(for: normalizer),
                     "a missing optional model is not a problem: "
                         + model.transformModelRoleDescription(normalizer))
        XCTAssertNil(model.transformMissingNotice(for: shipped), "the shipped model is installed here")
    }

    /// With the English backend installed every English job runs on it — tone and
    /// clean-up alike — and the card says so.
    func testWithTheEnglishBackendInstalledEveryEnglishJobRunsOnIt() throws {
        let (model, manager, directory, shipped, normalizer) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        try stage(normalizer, in: manager, directory: directory)
        model.installedTransformModelIDs = [shipped.id, normalizer.id]

        let description = model.transformLanguageModelDescription
        XCTAssertTrue(description.contains("runs on \(normalizer.displayName)"), description)
        XCTAssertTrue(description.contains("S1-mini is installed"), description)
        TestFixtures.report("[settings] the card with the English backend installed: \(description)")

        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .neutral)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .casual)).id, normalizer.id)
    }

    /// The floor missing is the one real problem: it is what every English
    /// transform falls back to while S1-mini is absent, and the card says what
    /// waits for it.
    func testTheFloorMissingIsTheOnlyWarning() throws {
        let (model, _, directory, shipped, _) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        model.installedTransformModelIDs = []
        let notice = try XCTUnwrap(model.transformMissingNotice(for: shipped))
        XCTAssertTrue(notice.contains("every English transform falls back to"), notice)
        XCTAssertTrue(notice.contains("S1-mini is optional"), notice)
        TestFixtures.report("[settings] the floor missing: \(notice)")
    }

    /// Every row states its job and what its model costs before it is paid, and
    /// the routing its role sentence describes is asserted as the resolution
    /// itself — the sentence cannot fail, the routing can.
    func testEachRowStatesItsJobAndItsCost() throws {
        let (model, _, directory, shipped, normalizer) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(model.transformModelRoleDescription(normalizer).contains("Every English transform"),
                      model.transformModelRoleDescription(normalizer))
        XCTAssertTrue(model.transformModelRoleDescription(shipped).contains("The floor"),
                      model.transformModelRoleDescription(shipped))
        // Two entries, two kinds, and the card has to name them: the row whose
        // text leaves "which one is S1-mini" to be inferred from prose is the
        // defect this pins. Each row states what its own model *is*.
        XCTAssertTrue(model.transformModelRoleDescription(normalizer).contains("normalizer"),
                      model.transformModelRoleDescription(normalizer))
        XCTAssertTrue(model.transformModelRoleDescription(normalizer).contains("not an instruction follower"),
                      model.transformModelRoleDescription(normalizer))
        XCTAssertTrue(model.transformModelRoleDescription(shipped).contains("instruction follower"),
                      model.transformModelRoleDescription(shipped))

        // And the question the rows cannot answer between them — is it a mistake
        // to download both? — is answered before them.
        let header = model.transformModelsHeaderDescription
        XCTAssertTrue(header.contains("Downloading both is fine"), header)
        XCTAssertTrue(header.contains("At most one of them is ever resident"), header)
        XCTAssertTrue(header.contains("never the sum"), header)
        XCTAssertTrue(header.contains("S1-mini"), header)

        XCTAssertEqual(model.transformModelManager.model(for: .tone(language: .english, tone: .casual)).id,
                       shipped.id, "without S1-mini installed, tone runs on the floor")
        XCTAssertEqual(model.transformModelManager.model(for: .cleanUp(language: .english)).id, shipped.id,
                       "and so does clean-up")

        for entry in [normalizer, shipped] {
            let state = model.transformModelStateDescription(entry)
            XCTAssertTrue(state.hasPrefix("Not downloaded"), state)
            XCTAssertTrue(state.contains(entry.memoryDescription), state)
            XCTAssertTrue(state.contains(entry.sizeDescription), state)
        }

        model.installedTransformModelIDs = [shipped.id]
        XCTAssertTrue(model.transformModelStateDescription(shipped).hasPrefix("Installed"),
                      model.transformModelStateDescription(shipped))
    }
}
