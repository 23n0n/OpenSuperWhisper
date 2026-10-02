import CryptoKit
import XCTest
@testable import OpenSuperWhisper

/// The transform weights are app-owned, checksum-verified and installed
/// atomically. These tests run against a temporary directory and a fake model,
/// so they never touch the user's Application Support.
final class TransformModelManagerTests: XCTestCase {

    private var directory: URL!
    private var manager: TransformModelManager!
    private var payload: Data!
    private var model: TransformModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-transform-\(UUID().uuidString)")
        payload = Data((0..<4096).map { UInt8($0 % 251) })
        model = TransformModel(
            id: "test-model",
            displayName: "Test Model",
            fileName: "test-model.gguf",
            style: .instruction,
            downloadURL: URL(string: "https://example.invalid/test-model.gguf")!,
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(payload.count),
            memoryBytes: 8_589_934_592,
            licence: "Apache-2.0",
            source: "test"
        )
        manager = TransformModelManager(directory: directory, catalogue: [model])
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func writeSourceFile(_ data: Data) throws -> URL {
        let url = directory.appendingPathComponent("source-\(UUID().uuidString).download")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func model(withSHA256 sha256: String) -> TransformModel {
        TransformModel(
            id: model.id,
            displayName: model.displayName,
            fileName: model.fileName,
            style: model.style,
            downloadURL: model.downloadURL,
            sha256: sha256,
            sizeBytes: model.sizeBytes,
            memoryBytes: model.memoryBytes,
            licence: model.licence,
            source: model.source
        )
    }

    // MARK: - Install

    func testInstall_storesTheFileAndAcceptsThePinnedChecksum() throws {
        let source = try writeSourceFile(payload)

        try manager.install(fileAt: source, model: model)

        XCTAssertTrue(manager.hasModelFile(model))
        XCTAssertEqual(manager.verifiedPath(for: model), manager.fileURL(for: model).path)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: manager.fileURL(for: model).path + ".part"),
            "the partial file must not survive a successful install"
        )
    }

    func testInstall_rejectsAMismatchedChecksumAndLeavesNothingBehind() throws {
        let source = try writeSourceFile(Data(repeating: 0xAB, count: 4096))
        let wrong = model(withSHA256: String(repeating: "0", count: 64))

        XCTAssertThrowsError(try manager.install(fileAt: source, model: wrong)) { error in
            guard case TransformModelError.checksumMismatch = error else {
                return XCTFail("expected a checksum mismatch, got \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.fileURL(for: wrong).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.fileURL(for: wrong).path + ".part"))
        XCTAssertNil(manager.verifiedPath(for: wrong))
    }

    // MARK: - Verification

    func testVerifiedPath_rehashesAFileThatWasReplacedBehindTheApp() throws {
        let source = try writeSourceFile(payload)
        try manager.install(fileAt: source, model: model)
        XCTAssertNotNil(manager.verifiedPath(for: model), "precondition: just installed and verified")

        // Same size, different bytes: the size check alone would accept this.
        let replacement = Data(repeating: 0x11, count: payload.count)
        try replacement.write(to: manager.fileURL(for: model))

        XCTAssertNil(
            manager.verifiedPath(for: model),
            "a file whose checksum no longer matches must never be handed to the runtime"
        )
    }

    func testVerifyInstalledModel_reportsTheChecksumOfTheFileOnDisk() throws {
        let source = try writeSourceFile(payload)
        XCTAssertFalse(manager.verifyInstalledModel(model), "nothing installed yet")

        try manager.install(fileAt: source, model: model)
        XCTAssertTrue(manager.verifyInstalledModel(model))

        try Data(repeating: 0x22, count: payload.count).write(to: manager.fileURL(for: model))
        XCTAssertFalse(manager.verifyInstalledModel(model))
    }

    func testHasModelFile_rejectsAFileOfTheWrongSize() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x33, count: 10).write(to: manager.fileURL(for: model))

        XCTAssertFalse(manager.hasModelFile(model))
        XCTAssertNil(manager.verifiedPath(for: model))
    }

    // MARK: - Removal

    func testRemove_isIdempotentAndTakesTheStampWithIt() throws {
        let source = try writeSourceFile(payload)
        try manager.install(fileAt: source, model: model)

        try manager.remove(model)
        XCTAssertNil(manager.verifiedPath(for: model))

        // Twice, and with the file already gone: both are fine.
        XCTAssertNoThrow(try manager.remove(model))
        XCTAssertNil(manager.verifiedPath(for: model))
    }

    func testInit_dropsAPartialDownloadFromAKilledApp() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(model.fileName + ".part")
        try payload.write(to: partial)

        _ = TransformModelManager(directory: directory, catalogue: [model])

        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    // MARK: - Model ids

    func testModelLooksUpACatalogueEntryByID() {
        XCTAssertEqual(manager.model(forID: "test-model")?.id, "test-model")
        XCTAssertNil(manager.model(forID: "nope"), "an id this build does not ship is not a model")
    }

    /// The catalogue holds the two entries the routing knows: the English backend
    /// and the floor every English transform falls back to while it is not
    /// installed. The normalizer is the small one — 462 MB against the floor's
    /// 986 MB — which is the point of moving English onto it, and it is the last
    /// entry the card lists.
    func testTheCatalogueHoldsTheEnglishBackendAndTheFloor() throws {
        let normalizer = TransformModelManager.shared.normalizerModel
        let shipped = TransformModelManager.shared.defaultModel

        XCTAssertEqual(normalizer.id, TransformModelManager.normalizerModelID)
        XCTAssertEqual(shipped.id, TransformModelManager.defaultModelID)
        XCTAssertEqual(normalizer.id, TransformModelManager.availableModels.first?.id,
                       "the card lists the English backend first")
        XCTAssertEqual(TransformModelManager.availableModels.map(\.id), [normalizer.id, shipped.id],
                       "two models, and this is the order the Settings list shows")
        XCTAssertLessThan(normalizer.sizeBytes, shipped.sizeBytes,
                          "the English backend is the smaller model, and the card states that")
        XCTAssertFalse(TransformModelManager.availableModels.contains { $0.id == "qwen3-8b-q4_k_m" },
                       "the 8B no job resolved to is gone from the product, not merely unrouted")

        // The style is what each entry is: the normalizer is not an instruct
        // model, and the floor is.
        XCTAssertEqual(normalizer.style, .normalizer)
        XCTAssertEqual(shipped.style, .instruction)
    }

    /// The English backend is pinned by the brief: the URL, the size and the
    /// digest the download is verified against, with no second source of truth.
    /// The digest is the repository's own published one, and the file this
    /// machine downloaded hashes to it.
    func testTheEnglishBackendIsPinned() throws {
        let normalizer = TransformModelManager.shared.normalizerModel

        XCTAssertEqual(
            normalizer.downloadURL.absoluteString,
            "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf"
        )
        XCTAssertEqual(normalizer.sha256,
                       "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634",
                       "the digest the repository publishes for s1-mini-q4_k_m.gguf")
        XCTAssertEqual(normalizer.sizeBytes, 484_219_808)
        XCTAssertEqual(normalizer.fileName, "s1-mini-q4_k_m.gguf")
    }

    /// The licence is Apache-2.0 plus one additional term, and the name it
    /// requires is in the name the app shows: any use "must continue to identify
    /// it by its original name, \"S1-mini\" by \"Superwhisper\", using that exact
    /// capitalization".
    func testTheEnglishBackendKeepsItsNameAndStatesItsLicence() throws {
        let normalizer = TransformModelManager.shared.normalizerModel

        XCTAssertTrue(normalizer.displayName.contains("S1-mini"), normalizer.displayName)
        XCTAssertTrue(normalizer.displayName.contains("Superwhisper"), normalizer.displayName)
        XCTAssertTrue(normalizer.licence.contains("Apache-2.0"), normalizer.licence)
        XCTAssertTrue(normalizer.licence.contains("S1-mini"), normalizer.licence)
        XCTAssertTrue(normalizer.licence.contains("Superwhisper"), normalizer.licence)
        TestFixtures.report("[transform] licence line shown for the English backend: "
                    + "\(normalizer.licence) — from \(normalizer.source)")
    }

    /// The two facts the runtime reads off the style, both straight from the
    /// card: the assistant turn opens with an empty think block — the literal
    /// llama.cpp would take through a template kwarg this build does not have —
    /// and the answer is decoded greedily.
    func testTheNormalizersContractIsTheCardsAndTheInstructModelsIsNot() throws {
        let openThink = "\u{3C}think\u{3E}"
        let closeThink = "\u{3C}/think\u{3E}"

        XCTAssertEqual(TransformPromptStyle.normalizer.assistantPrefix,
                       "\(openThink)\n\n\(closeThink)\n\n",
                       "two newlines inside the empty block, two after it")
        XCTAssertTrue(TransformPromptStyle.normalizer.isGreedy)
        XCTAssertEqual(TransformPromptStyle.instruction.assistantPrefix, "")
        XCTAssertFalse(TransformPromptStyle.instruction.isGreedy)
    }

    /// The floor is pinned too: it is what an English transform falls back to
    /// while the English backend is not installed, so its digest is the floor the
    /// whole feature stands on.
    func testTheShippedModelIsPinned() throws {
        let shipped = TransformModelManager.shared.defaultModel

        XCTAssertEqual(
            shipped.downloadURL.absoluteString,
            "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf"
        )
        XCTAssertEqual(shipped.sha256, "1adf0b11065d8ad2e8123ea110d1ec956dab4ab038eab665614adba04b6c3370")
        XCTAssertEqual(shipped.sizeBytes, 986_048_768)
        XCTAssertEqual(shipped.fileName, "qwen2.5-1.5b-instruct-q4_k_m.gguf")
    }

    // MARK: - The model is a preference

    /// Nothing installed: English runs on the floor rather than being refused, and
    /// a policy that carried another language would resolve to it too — it is the
    /// only backend left. The catalogue is what makes the second half true, so the
    /// test states both.
    func testNothingInstalledResolvesToTheFloorInsteadOfRefusing() throws {
        // The real catalogue, pointed at a directory with nothing in it — so
        // "the optional models are not installed" is this test's fact and not
        // the machine's.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-preference-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TransformModelManager(
            directory: directory,
            catalogue: TransformModelManager.availableModels
        )

        XCTAssertFalse(manager.isNormalizerInstalled)
        XCTAssertEqual(manager.preferredTransformModel.id, TransformModelManager.defaultModelID,
                       "English runs on the floor instead of being refused")
        XCTAssertEqual(manager.model(for: .cleanUp(language: .english)).id,
                       TransformModelManager.defaultModelID)
        XCTAssertNil(manager.verifiedPath(for: manager.normalizerModel), "nothing is staged, so nothing verifies")
    }
}
