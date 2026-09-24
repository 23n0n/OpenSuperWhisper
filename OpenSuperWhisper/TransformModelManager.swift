import Combine
import CryptoKit
import Foundation

enum TransformModelError: Error, LocalizedError {
    /// Nothing installed for the direction that was asked for. Carries the
    /// model's name: the app routes Polish output to its own backend, so "the
    /// model is missing" has to say *which* one.
    case notInstalled(String)
    case checksumMismatch(expected: String, actual: String)
    case downloadFailed(String)
    case cancellation

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name):
            return "The \(name) transform model is not downloaded yet."
        case .checksumMismatch(let expected, let actual):
            return "The downloaded transform model does not match the pinned checksum (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .downloadFailed(let reason):
            return "The transform model download failed: \(reason)"
        case .cancellation:
            return "The transform model download was cancelled."
        }
    }
}

/// One downloadable transform model.
struct TransformModel: Equatable, Identifiable {
    /// The id the built-in runtime loads this entry for
    /// (`AppPreferences.transformModel` names it too when the external endpoint
    /// override is on). It is the file's stem, which is also the alias
    /// `Scripts/transform-server.sh` serves the same weights under.
    let id: String
    let displayName: String
    let fileName: String
    let downloadURL: URL
    /// Pinned by the repository, and the only place either backend's digest
    /// lives: the download, the install and every later use are all checked
    /// against this value. For the shipped small model it is also the hash
    /// `Scripts/transform-server.sh` verifies its own copy of those weights with.
    let sha256: String
    let sizeBytes: Int64
    /// What the model costs in wired memory while it is loaded — weights, KV
    /// cache and compute buffer on the Metal device, measured in-process for
    /// this machine family (`fm-20260923-24`). Shown next to the switch, so the
    /// footprint is visible before it is paid.
    let memoryBytes: Int64
    /// Shown before anything is fetched.
    let licence: String
    let source: String

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var memoryDescription: String {
        ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory)
    }

    /// One line naming the weights, their licence and where they come from.
    var sourceDescription: String {
        "\(displayName), \(licence), from \(source)"
    }
}

/// Owns the transform weights: app-owned storage, pinned hash, atomic install.
///
/// Weights are NOT shipped in the app bundle (a 1–5 GB payload in every update
/// is the wrong trade for a menu-bar utility). They live in
/// `~/Library/Application Support/<bundle id>/transform-models/`, exactly like
/// the whisper models next door, so uninstalling the app removes them and
/// reinstalling fetches them again. The catalogue holds one entry per output
/// direction; `model(forOutputLanguage:)` is what the runtime asks it for.
final class TransformModelManager {
    static let shared = TransformModelManager()

    /// The id the built-in runtime falls back to when the stored preference
    /// names something the app does not ship.
    static let defaultModelID = "qwen2.5-1.5b-instruct-q4_k_m"

    /// The backend for **Polish output**, the one direction the shipped 1.5B was
    /// measured unreliable on: 4/15 clean, 2 of them inventing content and 5
    /// with broken grammar, against this model's 11/15 clean and none invented
    /// (`fm-20260923-24/raw/verdicts.json`; a second scorer called the small
    /// model 1/15). It is 5×
    /// the weights and 5× the wired memory, so it is only loaded when Polish is
    /// actually being written.
    static let polishOutputModelID = "qwen3-8b-q4_k_m"

    /// The model that must write `language`. Routing is by **output direction**
    /// and nothing else: the preference picks which direction the user wants,
    /// never which backend serves it.
    static func modelID(forOutputLanguage language: TransformLanguage) -> String {
        language == .polish ? polishOutputModelID : defaultModelID
    }

    static let availableModels: [TransformModel] = [
        TransformModel(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            displayName: "Qwen2.5 1.5B Instruct (Q4_K_M)",
            fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf")!,
            sha256: "1adf0b11065d8ad2e8123ea110d1ec956dab4ab038eab665614adba04b6c3370",
            sizeBytes: 986_048_768,
            // 934.69 MiB weights + 112.00 MiB KV (4096 ctx) + 62.51 MiB compute.
            memoryBytes: 1_159_641_497,
            licence: "Apache-2.0",
            source: "bartowski/Qwen2.5-1.5B-Instruct-GGUF on Hugging Face"
        ),
        TransformModel(
            id: "qwen3-8b-q4_k_m",
            displayName: "Qwen3 8B (Q4_K_M)",
            fileName: "qwen3-8b-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf")!,
            sha256: "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
            sizeBytes: 5_027_783_488,
            // 4789.19 MiB weights + 576.00 MiB KV (4096 ctx) + 92.01 MiB compute.
            memoryBytes: 5_723_163_853,
            licence: "Apache-2.0",
            source: "Qwen/Qwen3-8B-GGUF on Hugging Face"
        )
    ]

    /// Where the GGUF files live. Overridable so tests can install into a
    /// temporary directory instead of the user's Application Support.
    let modelsDirectory: URL
    private let catalogue: [TransformModel]
    private let fileManager: FileManager

    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private let downloadLock = NSLock()

    init(
        directory: URL? = nil,
        catalogue: [TransformModel] = TransformModelManager.availableModels,
        fileManager: FileManager = .default
    ) {
        self.modelsDirectory = directory ?? Self.defaultDirectory
        self.catalogue = catalogue
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        removeStalePartialDownloads()
    }

    /// `~/Library/Application Support/<bundle id>/transform-models/`
    static var defaultDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "ru.starmel.OpenSuperWhisper"
        return applicationSupport
            .appendingPathComponent(bundleID)
            .appendingPathComponent("transform-models")
    }

    // MARK: - Catalogue

    func model(forID id: String) -> TransformModel? {
        catalogue.first { $0.id == id }
    }

    /// The model `id` names, or the default one when `id` is empty or names
    /// something this build does not ship (a preference left over from an
    /// older version, or a hand-typed id meant for an external endpoint).
    func resolvedModel(forID id: String?) -> TransformModel {
        if let id, !id.isEmpty, let match = model(forID: id) {
            return match
        }
        return catalogue.first { $0.id == Self.defaultModelID } ?? catalogue[0]
    }

    var defaultModel: TransformModel {
        resolvedModel(forID: nil)
    }

    /// The backend for the language the model is about to write.
    ///
    /// Resolved from the catalogue, not from a preference: the user picks the
    /// *direction*, the app picks the weights for it. A build that does not ship
    /// the Polish backend still resolves to the small one here — the caller
    /// checks `verifiedPath(for:)` and reports the miss rather than substituting.
    func model(forOutputLanguage language: TransformLanguage) -> TransformModel {
        resolvedModel(forID: Self.modelID(forOutputLanguage: language))
    }

    func fileURL(for model: TransformModel) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    // MARK: - Installed state

    /// Cheap check: the file is there and its size matches what is pinned.
    /// Says nothing about the checksum — `verifiedPath(for:)` does that.
    func hasModelFile(_ model: TransformModel) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL(for: model).path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value == model.sizeBytes
    }

    func verifiedPath(for model: TransformModel) -> String? {
        let url = fileURL(for: model)
        guard hasModelFile(model) else { return nil }
        if let stamp = readVerificationStamp(for: model), stamp.sha256 == model.sha256 {
            return url.path
        }
        guard verifyChecksum(ofFileAt: url, model: model) else { return nil }
        writeVerificationStamp(for: model, url: url)
        return url.path
    }

    /// Recomputes the pinned sha256 of the installed file.
    func verifyInstalledModel(_ model: TransformModel) -> Bool {
        let url = fileURL(for: model)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let ok = verifyChecksum(ofFileAt: url, model: model)
        if ok { writeVerificationStamp(for: model, url: url) } else { clearVerificationStamp(for: model) }
        return ok
    }

    private func verifyChecksum(ofFileAt url: URL, model: TransformModel) -> Bool {
        guard let digest = try? Self.sha256(ofFileAt: url) else { return false }
        return digest == model.sha256.lowercased()
    }

    /// Streaming SHA-256 of a file. `CryptoKit` keeps it constant-memory, which
    /// matters for a 5 GB GGUF.
    static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Install

    /// Installs `source` as `model`, atomically and only after the bytes on disk
    /// in the app's own directory hash to the pinned checksum.
    func install(fileAt source: URL, model: TransformModel) throws {
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destination = fileURL(for: model)
        let partial = modelsDirectory.appendingPathComponent(model.fileName + ".part")
        try? fileManager.removeItem(at: partial)
        try? fileManager.removeItem(at: destination)

        // Copy into the destination directory first, so the hash below is
        // computed over the bytes that actually land, and the final move is a
        // same-volume rename that either happened or did not.
        try fileManager.copyItem(at: source, to: partial)

        let digest: String
        do {
            digest = try Self.sha256(ofFileAt: partial)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw TransformModelError.downloadFailed("\(error)")
        }
        guard digest == model.sha256.lowercased() else {
            try? fileManager.removeItem(at: partial)
            throw TransformModelError.checksumMismatch(expected: model.sha256, actual: digest)
        }

        do {
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw TransformModelError.downloadFailed("\(error)")
        }
        writeVerificationStamp(for: model, url: destination)
    }

    /// Fetches the weights with a URLSession download task (progress, atomic
    /// install, checksum before use) — the same idiom `WhisperModelManager` uses.
    func download(model: TransformModel, progress: @escaping (Double) -> Void) async throws {
        if verifiedPath(for: model) != nil {
            progress(1.0)
            return
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ModelDownloadDelegate(progressCallback: progress)
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 24 * 60 * 60

            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
            let downloadTask = session.downloadTask(with: model.downloadURL)
            delegate.downloadTask = downloadTask

            downloadLock.lock()
            activeDownloads[model.id] = downloadTask
            downloadLock.unlock()

            delegate.completionHandler = { [weak self] location, error in
                session.finishTasksAndInvalidate()

                guard let self else {
                    continuation.resume(throwing: TransformModelError.cancellation)
                    return
                }

                self.downloadLock.lock()
                let isCurrent = self.activeDownloads[model.id] === downloadTask
                if isCurrent { self.activeDownloads.removeValue(forKey: model.id) }
                self.downloadLock.unlock()
                guard isCurrent else {
                    continuation.resume(throwing: TransformModelError.cancellation)
                    return
                }

                if let error = error as? URLError, error.code == .cancelled {
                    continuation.resume(throwing: TransformModelError.cancellation)
                    return
                }
                if let error {
                    continuation.resume(throwing: TransformModelError.downloadFailed(error.localizedDescription))
                    return
                }
                guard let location else {
                    continuation.resume(throwing: TransformModelError.downloadFailed("no file was received"))
                    return
                }

                do {
                    try self.install(fileAt: location, model: model)
                    try? FileManager.default.removeItem(at: location)
                    progress(1.0)
                    continuation.resume()
                } catch {
                    try? FileManager.default.removeItem(at: location)
                    continuation.resume(throwing: error)
                }
            }

            downloadTask.resume()
        }
    }

    func cancelDownload(modelID: String) {
        downloadLock.lock()
        defer { downloadLock.unlock() }
        activeDownloads[modelID]?.cancel()
        activeDownloads.removeValue(forKey: modelID)
    }

    /// Removes the installed weights (and any partial download). Idempotent.
    func remove(_ model: TransformModel) throws {
        cancelDownload(modelID: model.id)
        try? fileManager.removeItem(at: fileURL(for: model))
        try? fileManager.removeItem(at: partialURL(for: model))
        clearVerificationStamp(for: model)
    }

    func removeAll() throws {
        for model in catalogue { try remove(model) }
    }

    // MARK: - Verification stamp
    //
    // Records the checksum that was confirmed for the file currently on disk,
    // keyed by the file's size and modification date, so a launch only hashes
    // once per download instead of once per start.

    private struct VerificationStamp: Codable {
        let sha256: String
        let size: Int64
        let modified: Double
    }

    private func partialURL(for model: TransformModel) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName + ".part")
    }

    private func stampURL(for model: TransformModel) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName + ".verified.json")
    }

    private func readVerificationStamp(for model: TransformModel) -> VerificationStamp? {
        let url = fileURL(for: model)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
              let data = try? Data(contentsOf: stampURL(for: model)),
              let stamp = try? JSONDecoder().decode(VerificationStamp.self, from: data) else {
            return nil
        }
        // Exact comparison: any change to the file's size or modification time
        // invalidates the stamp and forces a re-hash. APFS keeps sub-second
        // modification times, so a rewrite is always visible here.
        guard stamp.size == size, stamp.modified == modified else { return nil }
        return stamp
    }

    private func writeVerificationStamp(for model: TransformModel, url: URL) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 else {
            return
        }
        let stamp = VerificationStamp(sha256: model.sha256.lowercased(), size: size, modified: modified)
        guard let data = try? JSONEncoder().encode(stamp) else { return }
        try? data.write(to: stampURL(for: model), options: .atomic)
    }

    private func clearVerificationStamp(for model: TransformModel) {
        try? fileManager.removeItem(at: stampURL(for: model))
    }

    /// A partial download from a killed app is never resumable: drop it.
    private func removeStalePartialDownloads() {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.pathExtension == "part" {
            try? fileManager.removeItem(at: entry)
        }
    }
}
