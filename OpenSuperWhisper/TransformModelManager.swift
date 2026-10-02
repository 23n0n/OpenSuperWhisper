import Combine
import CryptoKit
import Foundation

enum TransformModelError: Error, LocalizedError {
    /// Nothing installed for the language that was asked for. Carries the
    /// model's name: the shipped model is the floor for every language, so "the
    /// model is missing" has to say *which* one.
    case notInstalled(String)
    /// The file is there and is not what it says it is: the size or the
    /// checksum the catalogue pins does not match the bytes on disk. It is a
    /// different problem from a file that was never downloaded — one is fixed
    /// by downloading, the other by downloading again — and the user is told
    /// which one he has.
    case notVerified(String)
    case checksumMismatch(expected: String, actual: String)
    case downloadFailed(String)
    case cancellation

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name):
            return "The \(name) transform model is not downloaded yet."
        case .notVerified(let name):
            return "The \(name) transform model is on disk but does not match its pinned checksum, so it was not loaded."
        case .checksumMismatch(let expected, let actual):
            return "The downloaded transform model does not match the pinned checksum (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .downloadFailed(let reason):
            return "The transform model download failed: \(reason)"
        case .cancellation:
            return "The transform model download was cancelled."
        }
    }
}

/// The input contract a backend was trained on.
///
/// The catalogue's entries are not interchangeable: the two Qwen models are
/// instruction followers that take the app's own system instruction and the
/// dictation, while S1-mini is not one at all — its card states it "is not a
/// chat model and will not follow general instructions", that it takes one exact
/// system prompt and a control line, and that rewording either makes it
/// "hallucinate or produce garbled output". So its prompt is composed by a
/// different builder (`TransformService.normalizerSystemPrompt` /
/// `normalizerUserPrompt`) and its answers are decoded greedily.
enum TransformPromptStyle: Equatable {
    /// The app's instruction prompt, for an instruct model.
    case instruction
    /// Superwhisper S1-mini: the card's exact system prompt, then a control
    /// line, then the raw transcript, and nothing else.
    case normalizer

    /// The literal the normalizer's assistant turn has to open with.
    ///
    /// The card requires the template be applied with thinking disabled and
    /// gives the literal that means: the assistant turn, then an empty think
    /// block — two newlines inside it, two after it. llama.cpp's server does it
    /// with `--chat-template-kwargs '{"enable_thinking":false}'`, but the C API
    /// this app drives (`llama_chat_apply_template`, `include/llama.h`) takes no
    /// template kwargs at all, and the card warns against the two substitutes a
    /// server offers. So the app writes the block into the prompt string it
    /// sends, byte for byte, and this is that block.
    ///
    /// Built from Unicode scalars, for the same reason
    /// `TransformService.stripReasoning` builds its tags that way: the source
    /// then carries no literal angle brackets that an editor or a patch can
    /// corrupt.
    var assistantPrefix: String {
        switch self {
        case .instruction: return ""
        case .normalizer: return "\u{3C}think\u{3E}\n\n\u{3C}/think\u{3E}\n\n"
        }
    }

    /// Whether this backend's answers are decoded greedily.
    ///
    /// The card: "Decode greedily. `generation_config.json` already ships
    /// `do_sample: false` … If you override the config, use temperature 0." The
    /// GGUF's own metadata (temp 0.6, top_p 0.95, top_k 20, inherited from
    /// Qwen3-0.6B) and the app's established chain (top_k 40, top_p 0.95, min_p
    /// 0.05, temp 0.2) are both wrong for it, so the sampler follows this and
    /// neither of those.
    var isGreedy: Bool { self == .normalizer }
}

/// One downloadable transform model.
struct TransformModel: Equatable, Identifiable {
    /// The id the built-in runtime loads this entry for. It is the file's stem.
    let id: String
    let displayName: String
    let fileName: String
    /// The input contract these weights were trained on. It decides how the
    /// prompt is composed and how the answer is decoded — it is a fact about the
    /// model, not a preference.
    let style: TransformPromptStyle
    let downloadURL: URL
    /// Pinned by the repository, and the only place the digest lives: the
    /// download, the install and every later use are all checked against this
    /// value.
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
/// reinstalling fetches them again. The catalogue holds the English backend
/// every transform prefers, the floor English falls back to, and the larger
/// instruction-follower that no longer resolves a job; `model(for:)` is what the
/// runtime asks it for, because the language is part of the choice.
final class TransformModelManager {
    static let shared = TransformModelManager()

    /// The floor every language can run on, and the one the app ships: an
    /// English transform runs on it while S1-mini is not installed, and Polish
    /// runs on it whenever the optional 8B is not installed.
    static let defaultModelID = "qwen2.5-1.5b-instruct-q4_k_m"

    /// The English backend: `superwhisper/s1-mini`, a 0.6B text normalizer
    /// trained for exactly this job — it takes a raw ASR transcript and returns
    /// clean written text, fillers and false starts resolved, punctuation and
    /// capitalisation applied, spoken numbers, dates, times, currency and email
    /// addresses written out. Every English transform runs on it when it is
    /// installed, on both switches, and the shipped 1.5B does that work while it
    /// is not: a *preference*, never a requirement.
    ///
    /// It is not an instruct model and cannot be given the app's prompt: its
    /// card states it "is not a chat model and will not follow general
    /// instructions", and that rewriting the system prompt, dropping the control
    /// line or sending values outside the trained sets makes it "hallucinate or
    /// produce garbled output". Hence `TransformPromptStyle.normalizer`, its own
    /// prompt builder and its own greedy sampler.
    ///
    /// One thing the app used to give the English transform that this one cannot
    /// take: the reference list of names and jargon. The normalizer's input is
    /// the system prompt, a control line and the transcript, in that order, with
    /// nothing else — there is no slot for it, and inventing one is what the
    /// card forbids. The list still rides the prompt of the shipped model.
    static let normalizerModelID = "s1-mini-q4_k_m"

    /// The Polish backend: **no job since the transform became English-only**
    /// (`TransformPolicy.resolve` sends a Polish dictation straight to the
    /// keypad). It is the larger instruction-follower the Polish clean-up and
    /// every tone rewrite preferred when it was installed, and it is kept in the
    /// catalogue for two reasons that are both about the user rather than about
    /// routing: the 5 GB file is already in the app's own directory on a machine
    /// that has downloaded it, and a catalogue entry is the only thing that can
    /// show that file — and remove it — from Settings; and Polish's row of
    /// `model(forSpokenLanguage:)` is the table a flip back reads.
    static let polishOutputModelID = "qwen3-8b-q4_k_m"

    /// The id of the model a dictation in `language` prefers.
    ///
    /// Test-facing: it names the preference without consulting the disk, so the
    /// transform path does not read it — the service asks `model(for:)`, which
    /// resolves the same preference against what is actually installed. It is
    /// kept because the preference table is pinned through it.
    static func modelID(forSpokenLanguage language: TransformLanguage) -> String {
        switch language {
        case .english: return normalizerModelID
        case .polish: return polishOutputModelID
        }
    }

    /// The catalogue, in the order Settings lists it: the English backend, the
    /// floor every language can run on, then the larger instruction-follower no
    /// job resolves to any more.
    static let availableModels: [TransformModel] = [
        TransformModel(
            id: "s1-mini-q4_k_m",
            displayName: "S1-mini by Superwhisper (Q4_K_M)",
            fileName: "s1-mini-q4_k_m.gguf",
            style: .normalizer,
            downloadURL: URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf")!,
            sha256: "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634",
            sizeBytes: 484_219_808,
            // The engine's own breakdown for these weights at this app's
            // 4096-token context, every layer on the GPU (llama.cpp's
            // `common_memory_breakdown_print`): 456 MiB weights + 448 MiB KV +
            // 50 MiB compute = 954 MiB. A wired step was not measurable in
            // process on this machine — the suite's instrument reported 0.00 GB
            // across the load — so this is the engine's accounting rather than
            // the wired figure the other two entries carry.
            memoryBytes: 1_000_341_504,
            // Apache-2.0 with one additional term, quoted in the report this
            // entry was added from: any use "must continue to identify it by its
            // original name, \"S1-mini\" by \"Superwhisper\", using that exact
            // capitalization". The display name is where this app does that.
            licence: "Apache-2.0 plus a naming clause: it keeps the name \"S1-mini\" by \"Superwhisper\"",
            source: "superwhisper/s1-mini-GGUF on Hugging Face"
        ),
        TransformModel(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            displayName: "Qwen2.5 1.5B Instruct (Q4_K_M)",
            fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            style: .instruction,
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
            style: .instruction,
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

    /// The shipped model: the one entry in the catalogue every language can run
    /// on, and the floor the transform falls back to.
    var defaultModel: TransformModel {
        catalogue.first { $0.id == Self.defaultModelID } ?? catalogue[0]
    }

    /// The English backend: the normalizer every English transform runs on when
    /// it is installed.
    var normalizerModel: TransformModel {
        catalogue.first { $0.id == Self.normalizerModelID } ?? defaultModel
    }

    /// Whether the English backend is installed and its bytes verified. False is
    /// a normal state, not a problem: the English work then runs on
    /// `defaultModel` and nothing is refused.
    var isNormalizerInstalled: Bool {
        verifiedPath(for: normalizerModel) != nil
    }

    /// The optional larger instruction-follower. It resolves no job any more —
    /// see `polishOutputModelID` — and its installed state is what the card
    /// reports about the file on disk.
    var polishModel: TransformModel {
        catalogue.first { $0.id == Self.polishOutputModelID } ?? defaultModel
    }

    /// Whether the larger instruction-follower is installed and its bytes
    /// verified.
    var isPolishModelInstalled: Bool {
        verifiedPath(for: polishModel) != nil
    }

    /// The backend a dictation in `language` runs on — the transform's one
    /// language-based choice.
    ///
    /// A **preference**, resolved from the catalogue and from what is on disk:
    /// English prefers S1-mini and uses the shipped 1.5B while it is not
    /// installed. Nothing is refused for a missing optional model, and nothing
    /// is substituted silently — the caller is handed the model it will really
    /// run on, so Settings can say so.
    ///
    /// Polish's row is kept whole (the 8B when it is installed, the shipped
    /// model otherwise) although no Polish dictation reaches a model any more:
    /// that is the table a flip back reads, and the change that made the
    /// transform English-only was required to leave Polish exactly as it was.
    func model(forSpokenLanguage language: TransformLanguage) -> TransformModel {
        switch language {
        case .english:
            return isNormalizerInstalled ? normalizerModel : defaultModel
        case .polish:
            return isPolishModelInstalled ? polishModel : defaultModel
        }
    }

    /// The backend a *policy* runs on: the **language** decides and the job does
    /// not.
    ///
    /// The job used to decide — a tone rewrite took the larger instruction-follower
    /// in both languages, clean-up alone stayed on the language's own preference.
    /// Since the transform is English-only and English has one backend, both jobs
    /// resolve the same way, which leaves this function a single honest line: the
    /// policy carries the language, and the language carries the model. Nothing is
    /// refused, and the caller is handed the model that will really run, so
    /// Settings can say which.
    func model(for policy: TransformPolicy) -> TransformModel {
        model(forSpokenLanguage: policy.language)
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
