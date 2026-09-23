//
//  TransformRuntime.swift
//  OpenSuperWhisper
//
//  The in-process transform runtime: one llama.cpp model, loaded on demand,
//  serialized, warmed up ahead of the first dictation and released when idle.
//

import Foundation

/// A one-shot cancellation flag shared between the caller's task and the decode
/// loop running on the runtime's queue.
final class CancellationFlag {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Owns the single in-process llama.cpp model of the app.
///
/// Everything that touches the model runs on one serial queue: a llama context
/// is not thread-safe, and dictation is sequential anyway. The model is released
/// after `idleUnloadInterval` without a request, so the ~1 GB it holds is only
/// resident while the feature is actually in use.
final class TransformRuntime {
    static let shared = TransformRuntime()

    /// How long the weights stay resident after the last transform.
    static let idleUnloadInterval: TimeInterval = 10 * 60

    private let queue = DispatchQueue(
        label: "ru.starmel.OpenSuperWhisper.transform",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var model: LlamaModel?
    private var lastUse = Date.distantPast
    private var idleTimer: DispatchSourceTimer?

    private init() {}

    /// Whether weights are currently resident. Read by the settings UI.
    var isLoaded: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return model?.isLoaded ?? false
    }

    // MARK: - Public API

    /// Runs one transform in process.
    ///
    /// Throws on every failure (missing model, load failure, decode failure,
    /// cancellation); `TranslationService` turns that into the raw transcript.
    func transform(systemPrompt: String, userText: String) async throws -> String {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        let text = try run(
                            systemPrompt: systemPrompt,
                            userText: userText,
                            isCancelled: { cancellation.isCancelled }
                        )
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// Warms up only when the transform could actually run: a switch is on and
    /// the built-in runtime is the selected backend. The app must never hold a
    /// gigabyte of weights for a feature that is off.
    func warmUpIfEnabled() {
        let prefs = AppPreferences.shared
        guard prefs.translateEnabled || prefs.toneEnabled else { return }
        guard !prefs.transformUseExternalEndpoint else { return }
        warmUp()
    }

    /// Loads the weights and runs one throwaway decode, so the first dictation
    /// does not pay for Metal pipeline creation and the weight mapping. The
    /// llama.cpp counterpart of `TranscriptionService.prepareForRecording()`.
    ///
    /// A no-op when the transform has no installed model, and never throws: a
    /// failure here must not disturb dictation.
    func warmUp() {
        queue.async { [self] in
            guard !isLoaded else {
                lastUse = Date()
                return
            }
            do {
                let loaded = try loadedModel()
                _ = try loaded.complete(systemPrompt: "You are a helpful assistant.", userText: "Hi")
                lastUse = Date()
                scheduleIdleUnload()
                print("[TransformRuntime] warmed up")
            } catch {
                print("[TransformRuntime] warm-up skipped: \(error)")
            }
        }
    }

    /// Releases the weights. Called on idle, when the model is removed, and on
    /// application termination — hence synchronous: the process may be about to
    /// exit and the caller should be able to say the memory really was given
    /// back.
    func unload() {
        queue.sync {
            idleTimer?.cancel()
            idleTimer = nil
            stateLock.lock()
            let resident = model
            model = nil
            stateLock.unlock()
            resident?.unload()
            if resident != nil {
                print("[TransformRuntime] unloaded")
            }
        }
    }

    // MARK: - Queue-confined work

    private func run(
        systemPrompt: String,
        userText: String,
        isCancelled: () -> Bool
    ) throws -> String {
        let loaded = try loadedModel()
        let output = try loaded.complete(
            systemPrompt: systemPrompt,
            userText: userText,
            isCancelled: isCancelled
        )
        lastUse = Date()
        scheduleIdleUnload()
        return output
    }

    private func loadedModel() throws -> LlamaModel {
        if let model, model.isLoaded { return model }
        guard let path = TransformModelManager.shared.installedModelPath() else {
            throw TransformModelError.notInstalled
        }
        let created = try LlamaModel(modelPath: path)
        stateLock.lock()
        model = created
        stateLock.unlock()
        return created
    }

    /// One repeating timer per residency window; it only unloads once the model
    /// has been untouched for a whole interval.
    private func scheduleIdleUnload() {
        guard idleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.idleUnloadInterval, repeating: 60)
        timer.setEventHandler { [self] in
            guard Date().timeIntervalSince(lastUse) >= Self.idleUnloadInterval else { return }
            idleTimer?.cancel()
            idleTimer = nil
            stateLock.lock()
            let resident = model
            model = nil
            stateLock.unlock()
            resident?.unload()
            print("[TransformRuntime] unloaded after \(Int(Self.idleUnloadInterval))s idle")
        }
        idleTimer = timer
        timer.resume()
    }
}
