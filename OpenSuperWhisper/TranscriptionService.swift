import Foundation

@MainActor
class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var currentSegment = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Float = 0.0
    @Published private(set) var isConverting = false
    @Published private(set) var conversionProgress: Float = 0.0
    
    /// The English-only-model conflict for one transcript, or `nil` when there
    /// is nothing to refuse.
    ///
    /// Only whisper can be wrong this way — the model's own context is asked
    /// (`whisper_is_multilingual() == 0`), and the file name stands in for a
    /// model that is not loaded. The evidence is the transcript itself: the
    /// manual language picker is gone, and an English-only model measures
    /// nothing, so what the text looks like is all there is.
    @MainActor
    private func speechLanguageConflict(
        engine: TranscriptionEngine,
        transcript: String
    ) -> SpeechLanguageConflict? {
        guard let whisper = engine as? WhisperEngine else { return nil }
        let selectedPath = engineSelection?.modelPath
            ?? AppPreferences.shared.selectedWhisperModelPath
            ?? AppPreferences.shared.selectedModelPath
        return SpeechModelLanguageGate.conflict(
            modelPath: selectedPath,
            isMultilingual: whisper.isModelMultilingual,
            transcript: transcript
        )
    }

    /// The result of one transcription: the text, plus the language the engine
    /// measured. The language decides whether the transform gate tones or
    /// cleans up the transcript or pastes it as-is, and which model does the
    /// work, so it travels with the text instead of living in ambient state
    /// that concurrent operations could overwrite.
    struct TranscriptionOutput {
        let text: String
        /// Engine-reported language, or `nil` when the engine has no signal
        /// (Parakeet/FluidAudio, or a whisper model that is not multilingual).
        let language: String?
    }

    private final class TranscriptionTaskBox {
        let id: UUID
        let engine: TranscriptionEngine
        let task: Task<TranscriptionOutput, Error>

        init(id: UUID, engine: TranscriptionEngine, task: Task<TranscriptionOutput, Error>) {
            self.id = id
            self.engine = engine
            self.task = task
        }
    }
    
    private var currentEngine: TranscriptionEngine?
    private var transcriptionTask: TranscriptionTaskBox? = nil
    var activeOperationID: UUID? { transcriptionTask?.id }
    private var cancellationRequestedFor: UUID?

    private struct RecordingPreparation {
        let engine: WhisperEngine
        let task: Task<Void, Error>
    }

    private var recordingPreparation: RecordingPreparation?
    private var backgroundOperations: [UUID: Task<Void, Never>] = [:]
    private var shutdownTask: Task<Void, Never>?
    private var shutdownEngines: [WhisperEngine] = []
    private(set) var isShuttingDown = false

    func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        isShuttingDown = true
        engineLoadTask?.cancel()
        cancelTranscription()
        let engine = currentEngine
        let preparation = recordingPreparation
        let activeTask = transcriptionTask
        let operations = Array(backgroundOperations.values)
        let task = Task {
            _ = await activeTask?.task.result
            _ = await preparation?.task.result
            for operation in operations {
                await operation.value
            }
            for engine in shutdownEngines {
                engine.unload()
            }
            shutdownEngines.removeAll()
            (activeTask?.engine as? WhisperEngine)?.unload()
            preparation?.engine.unload()
            (engine as? WhisperEngine)?.unload()
            currentEngine = nil
            recordingPreparation = nil
            transcriptionTask = nil
            engineLoadTask = nil
            engineLoadID = nil
            isLoading = false
            isTranscribing = false
        }
        shutdownTask = task
        await task.value
    }

    func prepareForRecording() {
        guard !isShuttingDown, !isLoading, transcriptionTask == nil, recordingPreparation == nil,
              let engine = currentEngine as? WhisperEngine else { return }
        let task = Task.detached(priority: .userInitiated) {
            try engine.prepareForRecording()
        }
        recordingPreparation = RecordingPreparation(engine: engine, task: task)
        let id = UUID()
        backgroundOperations[id] = Task { [weak self] in
            _ = await task.result
            self?.backgroundOperations[id] = nil
        }
    }
    
    struct EngineSelection: Equatable {
        let engine: String
        let modelPath: String?
        let modelVersion: String

        static var current: Self {
            let prefs = AppPreferences.shared
            return Self(engine: prefs.selectedEngine,
                        modelPath: prefs.selectedWhisperModelPath ?? prefs.selectedModelPath,
                        modelVersion: prefs.fluidAudioModelVersion)
        }
    }

    @Published private(set) var loadingError: String?
    private let engineLoader: (EngineSelection) async throws -> TranscriptionEngine
    private var engineLoadTask: Task<TranscriptionEngine, Error>?
    private var engineLoadID: UUID?
    private var engineSelection: EngineSelection?

    init(selection: EngineSelection = .current, engineLoader: @escaping (EngineSelection) async throws -> TranscriptionEngine = TranscriptionService.makeEngine) {
        self.engineLoader = engineLoader
        loadEngine(selection: selection)
    }

    init(engine: TranscriptionEngine) {
        engineLoader = Self.makeEngine
        currentEngine = engine
    }

    private static func makeEngine(_ selection: EngineSelection) async throws -> TranscriptionEngine {
        let engine: TranscriptionEngine
        if selection.engine == "fluidaudio" {
            engine = FluidAudioEngine(modelVersion: selection.modelVersion)
        } else {
            guard let path = selection.modelPath else { throw TranscriptionError.contextInitializationFailed }
            engine = WhisperEngine(modelPath: path)
        }
        try await engine.initialize()
        return engine
    }

    func cancelTranscription() {
        guard let activeTask = transcriptionTask else { return }

        cancel(activeTask)
    }

    func cancelTranscription(operationID: UUID) {
        guard let activeTask = transcriptionTask,
              activeTask.id == operationID else { return }

        cancel(activeTask)
    }

    private func cancel(_ activeTask: TranscriptionTaskBox) {

        // Keep the task registered, and keep isTranscribing true, until the
        // engine's native call has actually returned. Clearing either here lets
        // a new recording enter the same engine while whisper.cpp is aborting.
        cancellationRequestedFor = activeTask.id
        activeTask.engine.cancelTranscription()
        activeTask.task.cancel()

        currentSegment = ""
        transcribedText = ""
        progress = 0.0
    }
    
    func loadEngine(selection: EngineSelection) {
        guard !isShuttingDown else { return }
        guard selection != engineSelection || (!isLoading && currentEngine == nil) else { return }
        engineLoadTask?.cancel()
        engineSelection = selection
        let id = UUID()
        engineLoadID = id
        currentEngine = nil
        recordingPreparation = nil
        loadingError = nil
        isLoading = true
        let loader = engineLoader
        let task = Task.detached(priority: .userInitiated) {
            let engine = try await loader(selection)
            try Task.checkCancellation()
            return engine
        }
        engineLoadTask = task
        backgroundOperations[id] = Task { [weak self] in
            let result = await task.result
            self?.finishEngineLoad(id: id, result: result)
            self?.backgroundOperations[id] = nil
        }
    }

    private func finishEngineLoad(id: UUID, result: Result<TranscriptionEngine, Error>) {
        guard !isShuttingDown else {
            if case .success(let engine as WhisperEngine) = result {
                shutdownEngines.append(engine)
            }
            return
        }
        guard engineLoadID == id else { return }
        engineLoadTask = nil
        engineLoadID = nil
        isLoading = false
        switch result {
        case .success(let engine): currentEngine = engine
        case .failure(let error): loadingError = error.localizedDescription
        }
    }

    func waitUntilReady() async throws {
        guard !isShuttingDown else { throw CancellationError() }
        while let task = engineLoadTask, let id = engineLoadID {
            let result = await task.result
            try Task.checkCancellation()
            guard !isShuttingDown else { throw CancellationError() }
            finishEngineLoad(id: id, result: result)
        }
        try Task.checkCancellation()
        guard !isShuttingDown else { throw CancellationError() }
        guard currentEngine != nil else { throw TranscriptionError.contextInitializationFailed }
    }

    func reloadEngine() {
        loadEngine(selection: .current)
    }

    func reloadModel(with path: String) {
        if AppPreferences.shared.selectedEngine == "whisper" {
            AppPreferences.shared.selectedWhisperModelPath = path
            reloadEngine()
        }
    }
    
    /// Convenience overload for callers that only need the text; the language is
    /// still computed and simply dropped here.
    func transcribeAudio(url: URL, settings: Settings, pcmSamples: [Float]? = nil) async throws -> String {
        try await transcribeAudio(
            url: url,
            settings: settings,
            operationID: UUID(),
            pcmSamples: pcmSamples
        ).text
    }

    func transcribeAudio(
        url: URL,
        settings: Settings,
        operationID: UUID,
        pcmSamples: [Float]? = nil
    ) async throws -> TranscriptionOutput {
        try Task.checkCancellation()

        // Serialize access to the engine: a whisper context must not process
        // two transcriptions concurrently (indicator flow and queue flow can
        // both reach this point due to async busy checks).
        while true {
            try await waitUntilReady()
            guard let existing = transcriptionTask else { break }
            _ = try? await existing.task.value
            try Task.checkCancellation()
            if transcriptionTask === existing {
                transcriptionTask = nil
                if cancellationRequestedFor == existing.id {
                    cancellationRequestedFor = nil
                }
            }
        }

        progress = 0.0
        conversionProgress = 0.0
        isConverting = true
        isTranscribing = true
        transcribedText = ""
        currentSegment = ""
        cancellationRequestedFor = nil
        
        guard let engine = currentEngine else {
            isTranscribing = false
            isConverting = false
            throw TranscriptionError.contextInitializationFailed
        }

        let preparation = recordingPreparation
        recordingPreparation = nil

        // Setup progress callback for engines
        if let whisperEngine = engine as? WhisperEngine {
            whisperEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self,
                          self.transcriptionTask?.id == operationID,
                          self.cancellationRequestedFor != operationID else { return }
                    self.progress = newProgress
                }
            }
        } else if let fluidEngine = engine as? FluidAudioEngine {
            fluidEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self,
                          self.transcriptionTask?.id == operationID,
                          self.cancellationRequestedFor != operationID else { return }
                    self.progress = newProgress
                }
            }
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            if let preparation, preparation.engine === engine {
                try await preparation.task.value
            }
            try Task.checkCancellation()
            
            let cancelled = await MainActor.run {
                guard let self = self else { return true }
                return self.cancellationRequestedFor == operationID
            }
            
            guard !cancelled else {
                throw CancellationError()
            }
            
            let output: TranscriptionOutput
            do {
                if let whisper = engine as? WhisperEngine {
                    // Whisper reports the language of the utterance it just
                    // decoded; the other engines cannot, so they fall back to the
                    // transcript text at the gate.
                    let detailed: WhisperEngine.DetailedTranscription
                    if let pcmSamples {
                        detailed = try await whisper.transcribeSamplesDetailed(pcmSamples, settings: settings)
                    } else {
                        detailed = try await whisper.transcribeAudioDetailed(url: url, settings: settings)
                    }
                    output = TranscriptionOutput(text: detailed.text, language: detailed.language)
                } else {
                    output = TranscriptionOutput(
                        text: try await engine.transcribeAudio(url: url, settings: settings),
                        language: nil
                    )
                }
            } catch {
                // Native engines may surface their own generic error after an
                // abort callback. Preserve cancellation as cancellation for the
                // indicator and queue instead of treating it as a failed decode.
                try Task.checkCancellation()
                let cancellationRequested = await MainActor.run {
                    guard let self = self else { return true }
                    return self.cancellationRequestedFor == operationID
                }
                if cancellationRequested {
                    throw CancellationError()
                }
                throw error
            }

            // The one combination that cannot work is refused before anything is
            // published: an English-only model writing English over speech it
            // never understood must not reach the paste path, and must not be
            // saved as the record of what the user said. The transcript is the
            // evidence — see `SpeechModelLanguageGate`.
            if let conflict = await MainActor.run(body: {
                self?.speechLanguageConflict(engine: engine, transcript: output.text)
            }) {
                throw TranscriptionError.speechLanguageConflict(conflict)
            }

            try Task.checkCancellation()
            
            let finalCancelled = await MainActor.run {
                guard let self = self else { return true }
                return self.cancellationRequestedFor == operationID
                    || self.transcriptionTask?.id != operationID
            }

            guard !finalCancelled else {
                throw CancellationError()
            }

            let didPublish = await MainActor.run {
                guard let self,
                      self.transcriptionTask?.id == operationID,
                      self.cancellationRequestedFor != operationID else { return false }
                self.transcribedText = output.text
                self.progress = 1.0
                return true
            }

            guard didPublish else { throw CancellationError() }
            try Task.checkCancellation()
            
            return output
        }
        
        let taskBox = TranscriptionTaskBox(
            id: operationID,
            engine: engine,
            task: task
        )
        transcriptionTask = taskBox

        defer {
            if transcriptionTask === taskBox {
                let wasCancelled = cancellationRequestedFor == taskBox.id
                transcriptionTask = nil
                if wasCancelled {
                    cancellationRequestedFor = nil
                    transcribedText = ""
                }
                isTranscribing = false
                isConverting = false
                currentSegment = ""
                progress = wasCancelled ? 0.0 : 1.0
            }
        }
        
        do {
            return try await task.value
        } catch is CancellationError {
            throw CancellationError()
        }
    }
}

enum TranscriptionError: Error {
    case contextInitializationFailed
    case audioConversionFailed
    case processingFailed
    /// A speech model that cannot hear the selected language, carrying the whole
    /// story so every surface — the indicator, the queue, the history row —
    /// tells the same one.
    case speechLanguageConflict(SpeechLanguageConflict)
}

extension TranscriptionError: LocalizedError {
    var errorDescription: String? {
        guard case .speechLanguageConflict(let conflict) = self else { return nil }
        return conflict.message
    }
}
