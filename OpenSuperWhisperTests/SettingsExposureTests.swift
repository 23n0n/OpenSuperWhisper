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
        func entry(_ id: String, _ name: String, _ file: String) -> TransformModel {
            TransformModel(
                id: id,
                displayName: name,
                fileName: file,
                downloadURL: URL(string: "https://example.invalid/\(file)")!,
                sha256: digest,
                sizeBytes: Int64(payload.count),
                memoryBytes: 1024,
                licence: "Apache-2.0",
                source: "test"
            )
        }
        let shipped = entry(TransformModelManager.defaultModelID, "Shipped Test Model", "shipped.gguf")
        let eightBee = entry(TransformModelManager.polishOutputModelID, "Eight Bee Test Model", "8b.gguf")

        let manager = TransformModelManager(directory: directory, catalogue: [shipped, eightBee])
        let model = SettingsViewModel(transformModelManager: manager)
        return (model, manager, directory, shipped, eightBee)
    }

    /// Stages `model`'s bytes in the manager's own directory, so the card's
    /// "is it installed" answer comes from a real verified file.
    private func stage(_ model: TransformModel, in manager: TransformModelManager, directory: URL) throws {
        let source = directory.appendingPathComponent("source-\(model.id).gguf")
        let payload = Data(repeating: 0x5A, count: Int(model.sizeBytes))
        try payload.write(to: source)
        try manager.install(fileAt: source, model: model)
    }

    /// The card says which model each language uses — and states, rather than
    /// warns, that Polish runs on the shipped model while the optional 8B is not
    /// installed. Nothing is refused for a missing 8B.
    func testTheCardSaysWhichModelEachLanguageUses() throws {
        let (model, _, directory, shipped, eightBee) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        model.installedTransformModelIDs = [shipped.id]

        let description = model.transformLanguageModelDescription
        XCTAssertTrue(description.contains("Polish runs on \(shipped.displayName)"), description)
        XCTAssertTrue(description.contains("English runs on \(shipped.displayName)"), description)
        XCTAssertTrue(description.contains("The 8B is not installed"), description)
        XCTAssertTrue(description.contains("nothing is refused"), description)

        // The shipped model is the only requirement; the 8B is never a warning.
        XCTAssertNil(model.transformMissingNotice(for: eightBee),
                     "a missing optional model is not a problem: \(model.transformModelRoleDescription(eightBee))")
        XCTAssertNil(model.transformMissingNotice(for: shipped), "the shipped model is installed here")
    }

    /// With the 8B installed the card says Polish runs on it — and the shipped
    /// model still serves English.
    func testWithTheEightBeeInstalledPolishRunsOnIt() throws {
        let (model, manager, directory, shipped, eightBee) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        try stage(eightBee, in: manager, directory: directory)
        model.installedTransformModelIDs = [shipped.id, eightBee.id]

        let description = model.transformLanguageModelDescription
        XCTAssertTrue(description.contains("Polish runs on \(eightBee.displayName)"), description)
        XCTAssertTrue(description.contains("The 8B is installed"), description)
        XCTAssertTrue(description.contains("English runs on \(shipped.displayName)"), description)
    }

    /// The shipped model missing is the one real problem: it is the model every
    /// language runs on, and the card says what waits for it.
    func testTheShippedModelMissingIsTheOnlyWarning() throws {
        let (model, _, directory, shipped, _) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        model.installedTransformModelIDs = []
        let notice = try XCTUnwrap(model.transformMissingNotice(for: shipped))
        XCTAssertTrue(notice.contains("every language runs on"), notice)
        XCTAssertTrue(notice.contains("8B is optional"), notice)
    }

    /// Every row states what its model costs before it is paid, and which
    /// languages it serves.
    func testEachRowStatesItsLanguagesAndItsCost() throws {
        let (model, _, directory, shipped, eightBee) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(model.transformModelRoleDescription(shipped).contains("English always"),
                      model.transformModelRoleDescription(shipped))
        XCTAssertTrue(model.transformModelRoleDescription(eightBee).contains("Preferred for Polish"),
                      model.transformModelRoleDescription(eightBee))

        for entry in [shipped, eightBee] {
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
