import Cocoa
import Combine
import SwiftUI

enum RecordingState {
    case idle
    case connecting
    case recording
    case decoding
    case busy
    case noMicrophone
    /// The selected speech model cannot hear the selected language — refused
    /// rather than transcribed into invented English.
    case incompatibleModel
}

@MainActor
protocol IndicatorViewDelegate: AnyObject {
    
    @discardableResult
    func didFinishDecoding(from viewModel: IndicatorViewModel) -> Bool
}

@MainActor
class IndicatorViewModel: ObservableObject {
    static let cancelConfirmationThreshold: TimeInterval = 10.0
    static let cancelConfirmationWindow: TimeInterval = 5.0
    
    @Published var state: RecordingState = .idle
    @Published var isBlinking = false
    @Published var isConfirmingCancel = false
    @Published var recorder: AudioRecorder = .shared
    
    var recordingStartedAt: Date?
    
    var delegate: IndicatorViewDelegate?
    private var blinkTimer: Timer?
    private var hideTimer: Timer?
    private var confirmCancelTimer: Timer?
    private var decodingTask: Task<Void, Never>?
    private var decodingSessionID: UUID?
    private var recordingSessionID: UUID?
    private var cancellables = Set<AnyCancellable>()
    
    private let recordingStore: RecordingStore
    private let transcriptionService: TranscriptionService
    private let transcriptionQueue: TranscriptionQueue
    private let stopRecordingOperation: () async -> RecordedAudio?
    private let cancelAudioRecordingOperation: () -> Void
    private let injectTextOperation: (String) -> KeyboardSimulator.InjectionResult
    private let transformTextOperation: (String, String?) async -> TranslationService.TransformOutcome
    private let cleanUpOperation: (String) -> DictationScrubber.Result
    private let cleanUpEnabledOperation: () -> Bool
    private let reportCenter: DictationReportCenter

    init(
        transcriptionService: TranscriptionService = .shared,
        recordingStore: RecordingStore = .shared,
        stopRecording: @escaping () async -> RecordedAudio? = {
            await AudioRecorder.shared.stopRecording()
        },
        cancelAudioRecording: @escaping () -> Void = {
            AudioRecorder.shared.cancelRecording()
        },
        injectText: @escaping (String) -> KeyboardSimulator.InjectionResult = {
            KeyboardSimulator.typeText($0)
        },
        transformText: @escaping (String, String?) async -> TranslationService.TransformOutcome = {
            await TranslationService.shared.transformDetailed($0, sourceLanguage: $1)
        },
        cleanUp: @escaping (String) -> DictationScrubber.Result = { text in
            // The switch is read per dictation, so flipping it in Settings takes
            // effect on the next one — and the scrub itself is a pure function
            // with no model behind it.
            guard AppPreferences.shared.cleanUpEnabled else {
                return DictationScrubber.Result(
                    text: text,
                    removedFillers: 0,
                    removedRepetitions: 0,
                    removedAnnotations: 0
                )
            }
            return DictationScrubber.scrub(text)
        },
        cleanUpEnabled: @escaping () -> Bool = { AppPreferences.shared.cleanUpEnabled },
        reportCenter: DictationReportCenter = .shared
    ) {
        self.recordingStore = recordingStore
        self.transcriptionService = transcriptionService
        self.transcriptionQueue = TranscriptionQueue.shared
        self.stopRecordingOperation = stopRecording
        self.cancelAudioRecordingOperation = cancelAudioRecording
        self.injectTextOperation = injectText
        self.transformTextOperation = transformText
        self.cleanUpOperation = cleanUp
        self.cleanUpEnabledOperation = cleanUpEnabled
        self.reportCenter = reportCenter
        
        recorder.$startFailure
            .compactMap { $0 }
            .sink { [weak self] failure in
                guard let self, self.recordingSessionID == failure.sessionID else { return }
                self.resetAfterRecordingFailure()
                AppErrorCenter.shared.report("Recording failed", message: failure.message)
            }
            .store(in: &cancellables)

        recorder.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self, let id = self.recordingSessionID,
                      RecordingSessionController.shared.currentID == id,
                      RecordingSessionController.shared.isCapturing else { return }
                if isConnecting && self.recorder.isConnecting {
                    self.state = .connecting
                    self.stopBlinking()
                }
            }
            .store(in: &cancellables)
        
        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self, let id = self.recordingSessionID,
                      RecordingSessionController.shared.currentID == id,
                      RecordingSessionController.shared.isCapturing else { return }
                if isRecording && self.recorder.isRecording {
                    self.state = .recording
                    self.startBlinking()
                }
            }
            .store(in: &cancellables)
    }
    
    var isTranscriptionBusy: Bool {
        transcriptionService.isLoading || transcriptionService.isTranscribing || transcriptionQueue.isProcessing
    }
    
    func showBusyMessage() {
        showAutoDismissingMessage(.busy)
    }

    private func showAutoDismissingMessage(_ message: RecordingState) {
        state = message

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                _ = self.delegate?.didFinishDecoding(from: self)
            }
        }
    }

    func resetAfterRecordingFailure() {
        RecordingSessionController.shared.finish(recordingSessionID)
        recordingSessionID = nil
        state = .idle
        stopBlinking()
        recordingStartedAt = nil
        resetCancelConfirmation()
        _ = delegate?.didFinishDecoding(from: self)
    }

    func startRecording() {
        // The microphone is checked before the busy state, not after it. The
        // engine load starts inside TranscriptionService's own initializer, so
        // "busy" is the normal state for the first seconds after launch - and the
        // old order answered "Processing..." to every attempt in that window,
        // never mentioning the input device the user is missing. A missing
        // microphone is a precondition for recording; busy only describes work
        // that is already running.
        //
        // getActiveMicrophone() only reads the cached currentMicrophone, so
        // this guard costs no CoreAudio HAL round-trip on the main thread.
        guard MicrophoneService.shared.getActiveMicrophone() != nil else {
            showAutoDismissingMessage(.noMicrophone)
            return
        }

        if isTranscriptionBusy {
            showBusyMessage()
            return
        }
        
        // Optimistically assume recording: querying the microphone here costs
        // CoreAudio HAL round-trips on the main thread right before the appear
        // animation. The recorder resolves the real state on its own queue and
        // publishes isConnecting/isRecording, which the sinks above translate
        // into .connecting/.recording.
        guard let id = RecordingSessionController.shared.begin(stop: { self.decodeRecording() }) else { return }
        recordingSessionID = id
        state = .recording
        startBlinking()
        recordingStartedAt = Date()
        
        recorder.startRecording(sessionID: id)
    }
    
    func handleCancelRequest() -> Bool {
        guard state == .recording,
              !AppPreferences.shared.escCancelWithoutConfirmation,
              !isConfirmingCancel,
              let startedAt = recordingStartedAt,
              Date().timeIntervalSince(startedAt) >= Self.cancelConfirmationThreshold
        else {
            return true
        }
        
        isConfirmingCancel = true
        confirmCancelTimer?.invalidate()
        confirmCancelTimer = Timer.scheduledTimer(withTimeInterval: Self.cancelConfirmationWindow, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resetCancelConfirmation()
            }
        }
        return false
    }
    
    private func resetCancelConfirmation() {
        confirmCancelTimer?.invalidate()
        confirmCancelTimer = nil
        isConfirmingCancel = false
    }
    
    func startDecoding() {
        if RecordingSessionController.shared.hasSession {
            RecordingSessionController.shared.requestStop()
        } else {
            decodeRecording()
        }
    }

    private func decodeRecording() {
        // A second stop request (double hotkey press, hold-mode key-up) must not
        // restart decoding or hide the window while transcription is in flight.
        guard state == .recording || state == .connecting else { return }
        
        resetCancelConfirmation()
        stopBlinking()
        
        if isTranscriptionBusy {
            // The engine is busy with another transcription: keep the user's audio
            // and put it into the queue instead of deleting it.
            Task { [weak self] in
                guard let self = self else { return }
                defer {
                    RecordingSessionController.shared.finish(self.recordingSessionID)
                    self.recordingSessionID = nil
                }
                if let audio = await self.stopRecordingOperation() {
                    await self.transcriptionQueue.addFileToQueue(url: audio.url)
                }
            }
            showBusyMessage()
            return
        }
        
        state = .decoding

        let sessionID = UUID()
        decodingSessionID = sessionID
        decodingTask = Task { [weak self] in
            guard let self = self else { return }

            guard let audio = await self.stopRecordingOperation() else {
                print("!!! Not found record url !!!")
                self.finishDecoding(sessionID: sessionID)
                return
            }
            let tempURL = audio.url
            var savedRecording: Recording?

            do {
                try Task.checkCancellation()
                guard self.decodingSessionID == sessionID else {
                    throw CancellationError()
                }

                print("start decoding...")
                let duration = audio.duration
                try Task.checkCancellation()
                guard self.decodingSessionID == sessionID else {
                    throw CancellationError()
                }

                let output = try await transcriptionService.transcribeAudio(
                    url: tempURL,
                    settings: Settings(),
                    operationID: sessionID,
                    pcmSamples: audio.samples
                )
                let rawText = output.text
                try Task.checkCancellation()
                guard self.decodingSessionID == sessionID else {
                    throw CancellationError()
                }

                // The deterministic clean-up runs first and without a model:
                // filler, stutters, repeated words and the recogniser's own
                // annotations are gone before anything is asked of a transform.
                // History keeps the raw transcript either way.
                let scrub = self.cleanUpOperation(rawText)
                let text = scrub.text

                if text.isEmpty {
                    try? FileManager.default.removeItem(at: tempURL)
                    print(
                        rawText.isEmpty
                            ? "No speech detected, dictation discarded"
                            : "Nothing but filler or an annotation; dictation discarded"
                    )
                } else {
                    let timestamp = Date()
                    let recordingId = UUID()
                    let fileName = Recording.fileName(for: recordingId)
                    let newRecording = Recording(
                        id: recordingId,
                        timestamp: timestamp,
                        fileName: fileName,
                        transcription: rawText,
                        duration: duration,
                        status: .completed,
                        progress: 1.0,
                        sourceFileURL: nil
                    )

                    try recorder.moveTemporaryRecording(from: tempURL, to: newRecording.url)
                    savedRecording = newRecording
                    do { try await self.recordingStore.addRecordingSync(newRecording) }
                    catch { throw PreservedAudioError(url: newRecording.url, underlying: error) }

                    try Task.checkCancellation()
                    guard self.decodingSessionID == sessionID else { throw CancellationError() }
                    let outcome = await transformTextOperation(text, output.language)
                    try Task.checkCancellation()
                    guard self.decodingSessionID == sessionID else { throw CancellationError() }
                    self.reportCenter.publish(DictationReport(
                        language: output.language,
                        raw: rawText,
                        cleaned: text,
                        final: outcome.text,
                        policy: outcome.policy,
                        didRunModel: outcome.didRunModel,
                        cleanUpEnabled: cleanUpEnabledOperation(),
                        removedFillers: scrub.removedFillers,
                        removedRepetitions: scrub.removedRepetitions,
                        removedAnnotations: scrub.removedAnnotations,
                        date: timestamp
                    ))
                    insertText(outcome.text)
                    print("Transcription result: \(rawText)")
                }
            } catch TranscriptionError.speechLanguageConflict(let conflict) {
                // The refused combination, reported where the user is looking:
                // the model and the setting named, the installed multilingual
                // model offered as a button, and the audio preserved so the
                // dictation can be re-run once the fix is applied. Nothing was
                // transcribed and nothing is pasted.
                self.showAutoDismissingMessage(.incompatibleModel)
                if let savedRecording {
                    do { try await Task { try await recordingStore.deleteRecordingSync(savedRecording, cancelTranscription: false) }.value }
                    catch { AppErrorCenter.shared.report("Cancelled recording could not be removed", error: error) }
                } else {
                    await self.recordingStore.preserveFailedDictation(
                        RecordedAudio(url: tempURL, samples: audio.samples),
                        error: TranscriptionError.speechLanguageConflict(conflict)
                    )
                }
                self.reportSpeechLanguageConflict(conflict)
            } catch is CancellationError {
                if let savedRecording {
                    do { try await Task { try await recordingStore.deleteRecordingSync(savedRecording, cancelTranscription: false) }.value }
                    catch { AppErrorCenter.shared.report("Cancelled recording could not be removed", error: error) }
                } else {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                print("Transcription cancelled")
            } catch {
                if Task.isCancelled || self.decodingSessionID != sessionID {
                    if let savedRecording {
                        do { try await Task { try await recordingStore.deleteRecordingSync(savedRecording, cancelTranscription: false) }.value }
                        catch { AppErrorCenter.shared.report("Cancelled recording could not be removed", error: error) }
                    } else {
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                    print("Transcription cancelled")
                } else {
                    let source = (error as? PreservedAudioError)?.url ?? audio.url
                    await self.recordingStore.preserveFailedDictation(RecordedAudio(url: source, samples: audio.samples), error: error)
                }
            }

            self.finishDecoding(sessionID: sessionID)
        }
    }

    private func finishDecoding(sessionID: UUID) {
        guard decodingSessionID == sessionID else { return }
        decodingSessionID = nil
        decodingTask = nil
        RecordingSessionController.shared.finish(recordingSessionID)
        recordingSessionID = nil
        _ = delegate?.didFinishDecoding(from: self)
    }
    
    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        let finalText = Self.applyPostProcessing(text)
        let prefs = AppPreferences.shared

        if prefs.autoPasteTranscription {
            // Deliver the transcription as synthetic keystrokes. When the user
            // also asked to keep it on the clipboard, copy first so the
            // "keep in clipboard" toggle still holds; otherwise leave the
            // clipboard untouched on this path.
            if prefs.autoCopyToClipboard {
                ClipboardUtil.copyToClipboard(finalText)
            }
            let result = injectTextOperation(finalText)
            KeyboardSimulator.logDictation(
                trusted: result.trusted,
                characters: finalText.count,
                injected: result.injected,
                eventsPosted: result.eventsPosted
            )
            if !result.trusted {
                reportInjectionWithoutAccessibilityTrust()
            }
        } else {
            KeyboardSimulator.logDictation(
                trusted: KeyboardSimulator.isTrustedForInjection,
                characters: finalText.count,
                injected: false,
                eventsPosted: 0
            )
            if prefs.autoCopyToClipboard {
                // Only copy to clipboard, don't paste
                ClipboardUtil.copyToClipboard(finalText)
            }
        }
        // If both are false, do nothing
    }

    /// The refusal, surfaced where the user can act on it.
    ///
    /// The message names the model file and the language setting and says what
    /// whisper does instead of transcribing; when a multilingual model is
    /// already installed, the alert carries the button that selects it — the
    /// fix in place, applied only because the user pressed it.
    private func reportSpeechLanguageConflict(_ conflict: SpeechLanguageConflict) {
        if let remedyTitle = conflict.remedyButtonTitle, let path = conflict.remedyModelPath {
            AppErrorCenter.shared.report(
                conflict.title,
                message: conflict.message,
                remedyTitle: remedyTitle
            ) {
                SpeechLanguageRemedy.useMultilingualModel(atPath: path)
            }
        } else {
            AppErrorCenter.shared.report(conflict.title, message: conflict.message)
        }
    }

    /// macOS drops every event an untrusted process posts, so a dictation that
    /// reached this point was typed nowhere. Say so through the app's existing
    /// permission surface instead of letting the text look lost — the
    /// transcript stays in the history, and the grant can be restored.
    private func reportInjectionWithoutAccessibilityTrust() {
        // The permission UI reads a value refreshed while a window was key; the
        // indicator is a non-activating panel, so that value can still claim
        // the grant is present while macOS refuses the keystrokes. Ask for a
        // fresh check now rather than trusting the cached one.
        NotificationCenter.default.post(name: .accessibilityPermissionNeededForInjection, object: nil)
        AppErrorCenter.shared.report(
            "Transcription was not typed",
            message: "macOS discarded OpenSuperWhisper's simulated keystrokes because this copy of "
                + "the app is not trusted for Accessibility, so the dictation did not reach the "
                + "focused app. It is saved in the History tab.\n\n"
                + "Open System Settings › Privacy & Security › Accessibility and make sure the "
                + "OpenSuperWhisper entry for this copy is switched on. If it already looks "
                + "enabled, switch it off and on again — several builds of the app share that "
                + "name, and a grant made for a different copy does not apply to the one "
                + "running. Removing the stale row and granting the app again also works."
        )
    }
    
    static func applyPostProcessing(_ text: String) -> String {
        guard AppPreferences.shared.addSpaceAfterSentence,
              let lastChar = text.last,
              lastChar.isPunctuation else {
            return text
        }
        return text + " "
    }
    
    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            // Update UI on the main thread
            Task { @MainActor in
                guard let self = self else { return }
                self.isBlinking.toggle()
            }
        }
    }
    
    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinking = false
    }

    func cleanup() {
        stopBlinking()
        resetCancelConfirmation()
        recordingStartedAt = nil
        hideTimer?.invalidate()
        hideTimer = nil
        cancellables.removeAll()
    }

    func cancelRecording() {
        hideTimer?.invalidate()
        hideTimer = nil

        if state == .decoding {
            // In decoding the recorder is already stopped. Cancel both the
            // Swift task and the native engine operation, and invalidate the
            // session before either can save or paste a late result.
            let cancelledSessionID = decodingSessionID
            decodingSessionID = nil
            decodingTask?.cancel()
            decodingTask = nil
            if let cancelledSessionID {
                transcriptionService.cancelTranscription(
                    operationID: cancelledSessionID
                )
            }
        }

        if state != .decoding {
            cancelAudioRecordingOperation()
        }
        RecordingSessionController.shared.finish(recordingSessionID)
        recordingSessionID = nil
    }
}

struct RecordingIndicator: View {
    let isBlinking: Bool
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.red.opacity(0.8),
                        Color.red
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 8, height: 8)
            .shadow(color: .red.opacity(0.5), radius: 4)
            .opacity(isBlinking ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.4), value: isBlinking)
    }
}

struct CancelConfirmationBar: View {
    @State private var progress: CGFloat = 1
    
    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.orange)
                .frame(width: geo.size.width * progress, height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 3)
        .onAppear {
            withAnimation(.linear(duration: IndicatorViewModel.cancelConfirmationWindow)) {
                progress = 0
            }
        }
    }
}

struct IndicatorWindow: View {
    /// Geometry shared with IndicatorWindowManager. The panel must be larger
    /// than the card: everything drawn outside the window bounds is cut off,
    /// so the appear offset (moves the card down) and the spring overshoot
    /// need margins, otherwise the card edges are visibly clipped mid-animation.
    static let cardSize = CGSize(width: 200, height: 36)
    static let windowSize = CGSize(width: 256, height: 96)
    static let appearOffset: CGFloat = 20
    static let appearInitialScale: CGFloat = 0.5
    
    @ObservedObject var viewModel: IndicatorViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.24)
            : Color.white.opacity(0.24)
    }
    
    var body: some View {

        let rect = RoundedRectangle(cornerRadius: 24)
        
        VStack(spacing: 12) {
            switch viewModel.state {
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24)
                    
                    Text("Connecting...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .recording:
                HStack(spacing: 8) {
                    RecordingIndicator(isBlinking: viewModel.isBlinking)
                        .frame(width: 24)
                    
                    if viewModel.isConfirmingCancel {
                        Text("Press Esc to cancel")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                            .transition(.opacity)
                    } else {
                        Text("Recording...")
                            .font(.system(size: 13, weight: .semibold))
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isConfirmingCancel)
                
            case .decoding:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24)
                    
                    Text("Transcribing...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .busy:
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    Text("Processing...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .noMicrophone:
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    Text("No microphone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .incompatibleModel:
                HStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    // The card is 200pt wide, so the full story (the model, the
                    // setting, the fix) is in the alert this state accompanies.
                    Text("Needs a multilingual model")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 24)
        .frame(height: Self.cardSize.height)
        .background {
            rect
                .fill(backgroundColor)
                .background {
                    rect
                        .fill(Material.thinMaterial)
                }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isConfirmingCancel {
                CancelConfirmationBar()
            }
        }
        .clipShape(rect)
        .frame(width: Self.cardSize.width)
        // The ideal size of the root view must match the panel: NSHostingView
        // resizes the window down to SwiftUI's ideal size, and a window sized
        // to the bare card clips the appear offset, bounce overshoot and shadow.
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        // The appear/hide animation is NOT done in SwiftUI on purpose:
        // animating scaleEffect/offset/opacity re-rasterizes the card (material
        // + gradients + shadow) on the CPU every frame and stalls the main
        // thread in CABackingStoreUpdate/wait_for_synchronize (20-60 ms per
        // frame in traces). IndicatorWindowManager animates the hosting view's
        // layer with CASpringAnimation instead: content is drawn once and the
        // spring runs entirely in the render server on the GPU.
    }
}

struct IndicatorWindowPreview: View {
    @StateObject private var recordingVM = {
        let vm = IndicatorViewModel()
//        vm.startRecording()
        return vm
    }()
    
    @StateObject private var decodingVM = {
        let vm = IndicatorViewModel()
        vm.state = .decoding
        return vm
    }()
    
    var body: some View {
        VStack(spacing: 20) {
            IndicatorWindow(viewModel: recordingVM)
            IndicatorWindow(viewModel: decodingVM)
        }
        .padding()
        .frame(height: 200)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    IndicatorWindowPreview()
}
