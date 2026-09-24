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

    /// The shipped entry is what the app falls back to, and the 8B is the
    /// larger of the two — which is what the card states.
    func testTheCatalogueHoldsTheShippedModelAndTheLargerPolishOne() throws {
        let shipped = TransformModelManager.shared.defaultModel
        let eightBee = TransformModelManager.shared.polishModel

        XCTAssertEqual(shipped.id, TransformModelManager.defaultModelID)
        XCTAssertEqual(eightBee.id, TransformModelManager.polishOutputModelID)
        XCTAssertNotEqual(shipped.id, eightBee.id, "Polish's preferred model is not the shipped one")
        XCTAssertGreaterThan(eightBee.memoryBytes, shipped.memoryBytes,
                             "the Polish backend is the larger one, and the UI states that")
    }

    /// The Polish entry is pinned by the brief: the URL, the size and the
    /// digest the download is verified against, with no second source of truth.
    func testTheEightBeeIsPinned() throws {
        let polish = TransformModelManager.shared.polishModel

        XCTAssertEqual(
            polish.downloadURL.absoluteString,
            "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf"
        )
        XCTAssertEqual(polish.sha256, "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785")
        XCTAssertEqual(polish.sizeBytes, 5_027_783_488)
        XCTAssertEqual(polish.fileName, "qwen3-8b-q4_k_m.gguf")
        XCTAssertEqual(polish.licence, "Apache-2.0")
    }

    /// The shipped model is pinned too: it is the one every language can run on,
    /// so its digest is the floor the whole feature stands on.
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

    /// The id a language prefers: Polish the 8B, everything else the shipped
    /// model. What is *installed* is the caller's business
    /// (`isPolishModelInstalled`), because the preference is allowed to miss.
    func testThePreferredModelIDPerLanguage() {
        XCTAssertEqual(TransformModelManager.modelID(forSpokenLanguage: .polish), "qwen3-8b-q4_k_m")
        XCTAssertEqual(
            TransformModelManager.modelID(forSpokenLanguage: .english),
            TransformModelManager.defaultModelID,
            "English always prefers the shipped model"
        )
    }

    /// Nothing installed: Polish runs on the shipped model rather than being
    /// refused, and English is unaffected.
    func testWithoutTheEightBeePolishFallsBackToTheShippedModel() throws {
        // The real catalogue, pointed at a directory with nothing in it — so
        // "the 8B is not installed" is this test's fact and not the machine's.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-preference-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = TransformModelManager(
            directory: directory,
            catalogue: TransformModelManager.availableModels
        )

        XCTAssertFalse(manager.isPolishModelInstalled)
        XCTAssertEqual(manager.model(forSpokenLanguage: .polish).id, TransformModelManager.defaultModelID,
                       "Polish runs on the shipped model instead of being refused")
        XCTAssertEqual(manager.model(forSpokenLanguage: .english).id, TransformModelManager.defaultModelID)
        XCTAssertNil(manager.verifiedPath(for: manager.polishModel), "nothing is staged, so nothing verifies")
    }
}
