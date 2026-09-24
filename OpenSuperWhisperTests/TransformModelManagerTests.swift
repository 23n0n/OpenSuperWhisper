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

    func testResolvedModel_fallsBackForAnIdTheCatalogueDoesNotKnow() {
        XCTAssertEqual(manager.resolvedModel(forID: "test-model").id, "test-model")
        XCTAssertEqual(manager.resolvedModel(forID: "nope").id, "test-model")
        XCTAssertEqual(manager.resolvedModel(forID: nil).id, "test-model")
        XCTAssertEqual(manager.resolvedModel(forID: "").id, "test-model")
    }

    func testResolvedModel_turnsAStaleStoredIdIntotheShippedDefault() {
        XCTAssertEqual(
            TransformModelManager.shared.resolvedModel(forID: "Qwen/Qwen3-14B-MLX-6bit").id,
            TransformModelManager.defaultModelID,
            "a stored id this build does not ship must resolve to the default, not to nothing"
        )
    }

    func testShippedCatalogue_pinsTheHashTheRepositoryAlreadyCarries() throws {
        let shipped = try XCTUnwrap(
            TransformModelManager.availableModels.first { $0.id == TransformModelManager.defaultModelID }
        )

        // The same weights and the same hash Scripts/transform-server.sh pins.
        let script = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/transform-server.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(
            script.contains(shipped.sha256),
            "the app and Scripts/transform-server.sh must pin the same weights"
        )
        XCTAssertTrue(script.contains(shipped.fileName))
    }

    // MARK: - Routing by output direction

    func testOutputLanguageSelectsTheBackend() {
        XCTAssertEqual(TransformModelManager.modelID(forOutputLanguage: .polish), "qwen3-8b-q4_k_m")
        XCTAssertEqual(TransformModelManager.modelID(forOutputLanguage: .english), "qwen2.5-1.5b-instruct-q4_k_m")
        XCTAssertEqual(
            TransformModelManager.modelID(forOutputLanguage: .english),
            TransformModelManager.defaultModelID,
            "English output keeps the shipped model"
        )
    }

    func testOutputLanguageResolvesWithinTheCatalogue() throws {
        let manager = TransformModelManager.shared
        XCTAssertEqual(manager.model(forOutputLanguage: .polish).id, TransformModelManager.polishOutputModelID)
        XCTAssertEqual(manager.model(forOutputLanguage: .english).id, TransformModelManager.defaultModelID)
        XCTAssertNotEqual(
            manager.model(forOutputLanguage: .polish).id,
            manager.model(forOutputLanguage: .english).id,
            "the two directions must not resolve to the same weights"
        )
    }

    /// The Polish entry is pinned by the brief: the URL, the size and the
    /// digest the download is verified against, with no second source of truth.
    func testPolishBackendIsPinned() throws {
        let polish = try XCTUnwrap(
            TransformModelManager.availableModels.first { $0.id == TransformModelManager.polishOutputModelID }
        )

        XCTAssertEqual(
            polish.downloadURL.absoluteString,
            "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf"
        )
        XCTAssertEqual(polish.sha256, "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785")
        XCTAssertEqual(polish.sizeBytes, 5_027_783_488)
        XCTAssertEqual(polish.fileName, "qwen3-8b-q4_k_m.gguf")
        XCTAssertEqual(polish.licence, "Apache-2.0")
        XCTAssertGreaterThan(
            polish.memoryBytes,
            TransformModelManager.shared.model(forOutputLanguage: .english).memoryBytes,
            "the Polish backend is the larger one, and the UI states that"
        )
    }

    /// A stored id cannot move the built-in runtime: routing is by direction.
    func testAStoredPreferenceCannotMoveTheBuiltInBackends() {
        for stored in TransformModelManager.availableModels.map(\.id) + ["Qwen/Qwen3-14B-MLX-6bit"] {
            XCTAssertEqual(
                TransformModelManager.shared.model(forOutputLanguage: .polish).id,
                TransformModelManager.polishOutputModelID,
                "stored \(stored) must not change the Polish backend"
            )
            XCTAssertEqual(
                TransformModelManager.shared.model(forOutputLanguage: .english).id,
                TransformModelManager.defaultModelID,
                "stored \(stored) must not change the English backend"
            )
        }
    }
}
