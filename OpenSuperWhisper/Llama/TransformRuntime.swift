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
/// after `idleUnloadInterval` without a request, so the weights it holds are
/// only resident while the feature is actually in use.
///
/// One model at a time, by design: a dictation writes exactly one output
/// language, so the runtime holds the backend for that direction and swaps it
/// (unload, then load) when the direction changes. Holding both would cost the
/// 8B's 5.3 GB *and* the 1.5B's 1.1 GB wired for a switch the user makes once.
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
    /// The catalogue id of `model`, so a request for the other direction can
    /// tell whether what is resident is the right backend.
    private var residentModelID: String?
    private var lastUse = Date.distantPast
    private var idleTimer: DispatchSourceTimer?

    /// The catalogue the runtime loads from. Injectable so a test can drive real
    /// weights staged outside the user's Application Support, exactly like
    /// `TransformModelManager(directory:catalogue:)`.
    private let models: TransformModelManager

    /// How long the weights stay resident after the last transform. Defaults to
    /// the shipped window; injectable so a test can watch the timer actually
    /// fire without sitting here for ten minutes.
    private let idleUnloadInterval: TimeInterval

    init(
        models: TransformModelManager = .shared,
        idleUnloadInterval: TimeInterval = TransformRuntime.idleUnloadInterval
    ) {
        self.models = models
        self.idleUnloadInterval = idleUnloadInterval
    }

    /// Whether weights are currently resident. Read by the settings UI.
    var isLoaded: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return model?.isLoaded ?? false
    }

    /// The catalogue id of the resident backend, or `nil` when nothing is
    /// loaded. One backend is resident at a time, so this is also the answer to
    /// "which one is in memory right now".
    var loadedModelID: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let model, model.isLoaded else { return nil }
        return residentModelID
    }

    // MARK: - Public API

    /// Runs one transform in process, on `model`'s weights.
    ///
    /// Throws on every failure (missing model, load failure, decode failure,
    /// cancellation); `TranslationService` turns that into the raw transcript.
    /// A missing model is **not** substituted: the caller asked for the Polish
    /// backend because the output is Polish, and the small model is not the
    /// answer to that question.
    func transform(systemPrompt: String, userText: String, model: TransformModel) async throws -> String {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        let text = try run(
                            systemPrompt: systemPrompt,
                            userText: userText,
                            model: model,
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
    /// multi-gigabyte model for a feature that is off.
    ///
    /// Which backend the next dictation needs cannot be known before the speech
    /// is in, but with translation on it can: the output language *is* the
    /// target. Without translation the output language is whatever was spoken,
    /// and the target is the only signal there is — so it picks the model for
    /// the target in both cases. A dictation that arrives in the other language
    /// then pays one swap (unload, load) instead of a cold load.
    func warmUpIfEnabled() {
        let prefs = AppPreferences.shared
        guard prefs.translateEnabled || prefs.toneEnabled else { return }
        guard !prefs.transformUseExternalEndpoint else { return }
        warmUp(for: models.model(forOutputLanguage: prefs.transformTargetLanguage))
    }

    /// Loads `model`'s weights and runs one throwaway decode, so the first
    /// dictation does not pay for Metal pipeline creation and the weight
    /// mapping. The llama.cpp counterpart of
    /// `TranscriptionService.prepareForRecording()` — and what hides the 8B's
    /// ~3.2 s cold load behind the user's own speech.
    ///
    /// A no-op when that model is not installed, and never throws: a failure
    /// here must not disturb dictation.
    func warmUp(for model: TransformModel) {
        queue.async { [self] in
            if let resident = self.model, resident.isLoaded, residentModelID == model.id {
                lastUse = Date()
                return
            }
            do {
                let loaded = try loadedModel(for: model)
                _ = try loaded.complete(systemPrompt: "You are a helpful assistant.", userText: "Hi")
                lastUse = Date()
                scheduleIdleUnload()
                print("[TransformRuntime] warmed up \(model.id)")
            } catch {
                print("[TransformRuntime] warm-up skipped for \(model.id): \(error)")
            }
        }
    }

    /// Releases the weights. Called on idle, when a model is removed, and on
    /// application termination — hence synchronous: the process may be about to
    /// exit and the caller should be able to say the memory really was given
    /// back.
    func unload() {
        queue.sync {
            if releaseResident() {
                print("[TransformRuntime] unloaded")
            }
        }
    }

    /// Releases the weights only when they are the ones `modelID` names, so
    /// removing one backend's file does not evict the other one that is in use.
    func unloadIfResident(modelID: String) {
        queue.sync {
            guard residentModelID == modelID, releaseResident() else { return }
            print("[TransformRuntime] unloaded the removed \(modelID)")
        }
    }

    // MARK: - Queue-confined work

    private func run(
        systemPrompt: String,
        userText: String,
        model: TransformModel,
        isCancelled: () -> Bool
    ) throws -> String {
        let loaded = try loadedModel(for: model)
        let output = try loaded.complete(
            systemPrompt: systemPrompt,
            userText: userText,
            isCancelled: isCancelled
        )
        lastUse = Date()
        scheduleIdleUnload()
        return output
    }

    private func loadedModel(for requested: TransformModel) throws -> LlamaModel {
        if let resident = model, resident.isLoaded, residentModelID == requested.id {
            return resident
        }

        // A direction change: the other backend's weights must go before this
        // one is mapped, or the app would be holding both.
        if releaseResident() {
            print("[TransformRuntime] unloaded the previous backend for a direction change")
        }

        guard let path = models.verifiedPath(for: requested) else {
            throw TransformModelError.notInstalled(requested.displayName)
        }
        let created = try LlamaModel(modelPath: path)
        stateLock.lock()
        model = created
        residentModelID = requested.id
        stateLock.unlock()
        print("[TransformRuntime] loaded \(requested.id)")
        return created
    }

    /// Drops the resident weights, whatever they are. Queue-confined. Returns
    /// whether there were any.
    @discardableResult
    private func releaseResident() -> Bool {
        idleTimer?.cancel()
        idleTimer = nil
        stateLock.lock()
        let resident = model
        model = nil
        residentModelID = nil
        stateLock.unlock()
        resident?.unload()
        return resident != nil
    }

    /// One repeating timer per residency window; it only unloads once the model
    /// has been untouched for a whole interval.
    private func scheduleIdleUnload() {
        guard idleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + idleUnloadInterval, repeating: 60)
        timer.setEventHandler { [self] in
            guard Date().timeIntervalSince(lastUse) >= idleUnloadInterval else { return }
            if releaseResident() {
                print("[TransformRuntime] unloaded after \(Int(idleUnloadInterval))s idle")
            }
        }
        idleTimer = timer
        timer.resume()
    }
}
