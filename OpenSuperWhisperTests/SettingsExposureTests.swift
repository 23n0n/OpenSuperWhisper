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

    /// A view model over a temporary directory and a small stand-in for the
    /// catalogue's one entry (same id, same shape, bytes instead of gigabytes), so
    /// what the card says is decided by this test's staging and nothing here
    /// touches the user's Application Support.
    private func card() throws -> (SettingsViewModel, TransformModelManager, URL, TransformModel) {
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
        let normalizer = entry(TransformModelManager.normalizerModelID, "S1-mini Test Model", "s1-mini.gguf",
                               style: .normalizer)

        let manager = TransformModelManager(directory: directory,
                                           catalogue: [normalizer])
        let model = SettingsViewModel(transformModelManager: manager)
        return (model, manager, directory, normalizer)
    }

    /// Stages `model`'s bytes in the manager's own directory, so the card's
    /// "is it installed" answer comes from a real verified file.
    private func stage(_ model: TransformModel, in manager: TransformModelManager, directory: URL) throws {
        let source = directory.appendingPathComponent("source-\(model.id).gguf")
        let payload = Data(repeating: 0x5A, count: Int(model.sizeBytes))
        try payload.write(to: source)
        try manager.install(fileAt: source, model: model)
    }

    /// The card names the one model the work runs on and says a Polish dictation
    /// is delivered as transcribed — and, with the weights missing, that the
    /// transform cannot run at all: there is nothing behind it to fall back to.
    ///
    /// What is asserted is both the card's words and the resolution behind them:
    /// `model(for:)` is what the description reads, so pinning the resolution
    /// pins the claim without pinning the sentence that carries it.
    func testTheCardSaysWhichModelTheEnglishWorkUses() throws {
        let (model, manager, directory, normalizer) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        model.installedTransformModelIDs = []

        let description = model.transformLanguageModelDescription
        XCTAssertTrue(description.contains("runs on \(normalizer.displayName)"), description)
        XCTAssertTrue(description.contains("Polish dictation is delivered as transcribed"), description)
        XCTAssertTrue(description.contains("S1-mini is not installed"), description)
        // Every job resolves to the one model, installed or not — the resolution
        // behind the card's sentence.
        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .neutral)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, normalizer.id)

        // The one model is a requirement: missing, it is the card's warning, and
        // the warning names the download that fixes it.
        let notice = try XCTUnwrap(model.transformMissingNotice(for: normalizer))
        XCTAssertTrue(notice.contains("no English dictation can be transformed at all"), notice)
        XCTAssertTrue(notice.contains("Download it here"), notice)
    }

    /// With the weights on disk every English job runs on them — tone and
    /// clean-up alike — the card says so, and the warning it gave while they were
    /// missing is gone.
    func testWithTheWeightsInstalledEveryEnglishJobRunsOnThem() throws {
        let (model, manager, directory, normalizer) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        try stage(normalizer, in: manager, directory: directory)
        model.installedTransformModelIDs = [normalizer.id]

        let description = model.transformLanguageModelDescription
        XCTAssertTrue(description.contains("runs on \(normalizer.displayName)"), description)
        XCTAssertTrue(description.contains("S1-mini is installed"), description)
        XCTAssertNil(model.transformMissingNotice(for: normalizer), "nothing is missing here")
        TestFixtures.report("[settings] the card with the weights installed: \(description)")

        XCTAssertEqual(manager.model(for: .tone(language: .english, tone: .neutral)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id, normalizer.id)
        XCTAssertEqual(manager.model(for: .cleanUpWithTone(language: .english, tone: .casual)).id, normalizer.id)
    }

    /// The row states its job and what the model costs before it is paid, and the
    /// routing its role sentence describes is asserted as the resolution itself —
    /// the sentence cannot fail, the routing can.
    func testTheRowStatesItsJobAndItsCost() throws {
        let (model, _, directory, normalizer) = try card()
        defer { try? FileManager.default.removeItem(at: directory) }

        // One row, one kind, and the card has to name it: the row whose text
        // leaves what the model *is* to be inferred from prose is the defect this
        // pins.
        let role = model.transformModelRoleDescription(normalizer)
        XCTAssertTrue(role.contains("only backend"), role)
        XCTAssertTrue(role.contains("normalizer"), role)
        XCTAssertTrue(role.contains("not an instruction follower"), role)

        // What the header answers is what the rows cannot: there is nothing to
        // download a second time, and nothing behind the one file.
        let header = model.transformModelsHeaderDescription
        XCTAssertTrue(header.contains("Polish dictation is delivered as transcribed"), header)
        XCTAssertTrue(header.contains("released after ten minutes"), header)
        XCTAssertTrue(header.contains("S1-mini"), header)

        XCTAssertEqual(model.transformModelManager.model(for: .tone(language: .english, tone: .casual)).id,
                       normalizer.id, "tone runs on the one model")
        XCTAssertEqual(model.transformModelManager.model(for: .cleanUp(language: .english)).id, normalizer.id,
                       "and so does clean-up")

        let state = model.transformModelStateDescription(normalizer)
        XCTAssertTrue(state.hasPrefix("Not downloaded"), state)
        XCTAssertTrue(state.contains(normalizer.memoryDescription), state)
        XCTAssertTrue(state.contains(normalizer.sizeDescription), state)

        model.installedTransformModelIDs = [normalizer.id]
        XCTAssertTrue(model.transformModelStateDescription(normalizer).hasPrefix("Installed"),
                      model.transformModelStateDescription(normalizer))
    }
}
