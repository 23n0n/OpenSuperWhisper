import AppKit
import Carbon
import Combine
import Foundation
import KeyboardShortcuts
import SwiftUI
import FluidAudio

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var selectedEngine: String {
        didSet {
            AppPreferences.shared.selectedEngine = selectedEngine
            if selectedEngine == "whisper" {
                loadAvailableModels()
            } else {
                initializeFluidAudioModels()
            }
            resetLanguageIfUnsupported()
            Task { @MainActor in
                TranscriptionService.shared.reloadEngine()
            }
        }
    }
    
    @Published var fluidAudioModelVersion: String {
        didSet {
            AppPreferences.shared.fluidAudioModelVersion = fluidAudioModelVersion
            if selectedEngine == "fluidaudio" {
                Task { @MainActor in
                    TranscriptionService.shared.reloadEngine()
                }
            }
            initializeFluidAudioModels()
            resetLanguageIfUnsupported()
        }
    }
    
    var supportedLanguages: [String] {
        LanguageUtil.supportedLanguages(engine: selectedEngine, fluidAudioModelVersion: fluidAudioModelVersion)
    }
    
    private func resetLanguageIfUnsupported() {
        if !supportedLanguages.contains(selectedLanguage) {
            selectedLanguage = LanguageUtil.fallbackLanguage(engine: selectedEngine)
        } else {
            NotificationCenter.default.post(name: .appPreferencesLanguageChanged, object: nil)
        }
    }
    
    @Published var selectedModelURL: URL? {
        didSet {
            if let url = selectedModelURL {
                AppPreferences.shared.selectedWhisperModelPath = url.path
            }
        }
    }

    /// User-initiated model selection. Persists the model and, if the model declares a
    /// preferred language (e.g. the ivrit.ai Hebrew model), switches the language to it.
    /// Do not call from init/restore — only in response to an explicit user action.
    func selectModel(_ url: URL) {
        selectedModelURL = url
        if let lang = SettingsDownloadableModels.preferredLanguage(forFilename: url.lastPathComponent),
           selectedLanguage != lang {
            selectedLanguage = lang
        }
    }

    @Published var availableModels: [URL] = []
    
    @Published var downloadableModels: [SettingsDownloadableModel] = []
    @Published var downloadableFluidAudioModels: [SettingsFluidAudioModel] = []
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadingModelName: String?
    private var downloadTask: Task<Void, Error>?
    private var downloadID: UUID?
    
    @Published var selectedLanguage: String {
        didSet {
            AppPreferences.shared.whisperLanguage = selectedLanguage
            NotificationCenter.default.post(name: .appPreferencesLanguageChanged, object: nil)
        }
    }

    @Published var suppressBlankAudio: Bool {
        didSet {
            AppPreferences.shared.suppressBlankAudio = suppressBlankAudio
        }
    }

    @Published var showTimestamps: Bool {
        didSet {
            AppPreferences.shared.showTimestamps = showTimestamps
        }
    }
    
    @Published var temperature: Double {
        didSet {
            AppPreferences.shared.temperature = temperature
        }
    }

    @Published var noSpeechThreshold: Double {
        didSet {
            AppPreferences.shared.noSpeechThreshold = noSpeechThreshold
        }
    }

    @Published var initialPrompt: String {
        didSet {
            AppPreferences.shared.initialPrompt = initialPrompt
        }
    }

    @Published var useBeamSearch: Bool {
        didSet {
            AppPreferences.shared.useBeamSearch = useBeamSearch
        }
    }

    @Published var beamSize: Int {
        didSet {
            AppPreferences.shared.beamSize = beamSize
        }
    }

    @Published var debugMode: Bool {
        didSet {
            AppPreferences.shared.debugMode = debugMode
        }
    }
    
    @Published var playSoundOnRecordStart: Bool {
        didSet {
            AppPreferences.shared.playSoundOnRecordStart = playSoundOnRecordStart
        }
    }
    
    @Published var useAsianAutocorrect: Bool {
        didSet {
            AppPreferences.shared.useAsianAutocorrect = useAsianAutocorrect
        }
    }
    
    @Published var modifierOnlyHotkey: ModifierKey {
        didSet {
            AppPreferences.shared.modifierOnlyHotkey = modifierOnlyHotkey.rawValue
            if modifierOnlyHotkey != .none {
                AppPreferences.shared.lastModifierOnlyHotkey = modifierOnlyHotkey.rawValue
            }
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }

    @Published var mouseButtonHotkey: MouseButton {
        didSet {
            AppPreferences.shared.mouseButtonHotkey = mouseButtonHotkey.rawValue
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }
    
    @Published var holdToRecord: Bool {
        didSet {
            AppPreferences.shared.holdToRecord = holdToRecord
        }
    }
    
    @Published var escCancelWithoutConfirmation: Bool {
        didSet {
            AppPreferences.shared.escCancelWithoutConfirmation = escCancelWithoutConfirmation
        }
    }

    @Published var startHiddenInMenuBar: Bool {
        didSet {
            AppPreferences.shared.startHiddenInMenuBar = startHiddenInMenuBar
        }
    }
    
    @Published var addSpaceAfterSentence: Bool {
        didSet {
            AppPreferences.shared.addSpaceAfterSentence = addSpaceAfterSentence
        }
    }

    @Published var autoCopyToClipboard: Bool {
        didSet {
            AppPreferences.shared.autoCopyToClipboard = autoCopyToClipboard
        }
    }

    @Published var autoPasteTranscription: Bool {
        didSet {
            AppPreferences.shared.autoPasteTranscription = autoPasteTranscription
        }
    }

    @Published var translateEnabled: Bool {
        didSet {
            AppPreferences.shared.translateEnabled = translateEnabled
        }
    }

    @Published var toneEnabled: Bool {
        didSet {
            AppPreferences.shared.toneEnabled = toneEnabled
        }
    }

    @Published var transformToneMode: ToneMode {
        didSet {
            AppPreferences.shared.transformToneMode = transformToneMode
        }
    }

    @Published var transformTargetLanguage: TransformLanguage {
        didSet {
            AppPreferences.shared.transformTargetLanguage = transformTargetLanguage
        }
    }

    @Published var transformEndpoint: String {
        didSet {
            AppPreferences.shared.transformEndpoint = transformEndpoint
        }
    }

    @Published var transformModel: String {
        didSet {
            AppPreferences.shared.transformModel = transformModel
        }
    }

    @Published var transformTimeout: Double {
        didSet {
            AppPreferences.shared.transformTimeout = transformTimeout
        }
    }

    /// Advanced override: run the transform against an external endpoint
    /// instead of the engine built into the app.
    @Published var transformUseExternalEndpoint: Bool {
        didSet {
            AppPreferences.shared.transformUseExternalEndpoint = transformUseExternalEndpoint
            refreshTransformModelState()
        }
    }

    // MARK: - Built-in transform model

    @Published var transformModelInstalled = false
    @Published var isDownloadingTransformModel = false
    @Published var transformModelDownloadProgress: Double = 0
    @Published var transformModelError: String?

    private var transformDownloadTask: Task<Void, Never>?

    /// The catalogue entry for the stored id, resolved to the built-in default
    /// when the stored id is not one this build ships.
    var resolvedTransformModel: TransformModel {
        TransformModelManager.shared.resolvedModel(forID: transformModel)
    }

    var transformModelStateDescription: String {
        if isDownloadingTransformModel {
            return "Downloading \(resolvedTransformModel.sizeDescription)…"
        }
        if transformModelInstalled {
            return "Installed — \(resolvedTransformModel.sizeDescription)"
        }
        return "Not downloaded — \(resolvedTransformModel.sizeDescription)"
    }

    var transformModelSourceDescription: String {
        "\(resolvedTransformModel.displayName), \(resolvedTransformModel.licence), from \(resolvedTransformModel.source)"
    }

    /// True when a switch wants the transform but nothing could run it yet.
    var transformNeedsModel: Bool {
        (translateEnabled || toneEnabled)
            && !transformUseExternalEndpoint
            && !transformModelInstalled
            && !isDownloadingTransformModel
    }

    /// Recomputes the installed state off the main thread: the first check of a
    /// hand-placed model hashes ~1 GB.
    func refreshTransformModelState() {
        let model = resolvedTransformModel
        let usesExternal = transformUseExternalEndpoint
        Task.detached(priority: .utility) { [weak self] in
            let installed = TransformModelManager.shared.verifiedPath(for: model) != nil
            await MainActor.run {
                guard let self else { return }
                self.transformModelInstalled = installed || usesExternal
            }
        }
    }

    @MainActor
    func downloadTransformModel() async {
        guard !isDownloadingTransformModel else { return }
        transformModelError = nil

        do {
            try DiskSpaceUtil.ensureEnoughFreeSpaceForModelDownload()
        } catch {
            transformModelError = error.localizedDescription
            return
        }

        let model = resolvedTransformModel
        isDownloadingTransformModel = true
        transformModelDownloadProgress = 0
        defer {
            isDownloadingTransformModel = false
            transformModelDownloadProgress = 0
        }

        do {
            try await TransformModelManager.shared.download(model: model) { progress in
                Task { @MainActor [weak self] in
                    self?.transformModelDownloadProgress = progress
                }
            }
            await MainActor.run { self.refreshTransformModelState() }
        } catch {
            transformModelError = error.localizedDescription
        }
    }

    func cancelTransformModelDownload() {
        TransformModelManager.shared.cancelDownload(modelID: resolvedTransformModel.id)
        isDownloadingTransformModel = false
        transformModelDownloadProgress = 0
    }

    func removeTransformModel() {
        transformModelError = nil
        do {
            try TransformModelManager.shared.remove(resolvedTransformModel)
            TransformRuntime.shared.unload()
            refreshTransformModelState()
        } catch {
            transformModelError = error.localizedDescription
        }
    }

    private let downloadWhisper: (URL, String, @escaping (Double) -> Void) async throws -> Void

    private let downloadFluid: (AsrModelVersion, ProgressHandler?) async throws -> AsrModels

    init(downloadWhisper: @escaping (URL, String, @escaping (Double) -> Void) async throws -> Void = {
        try await WhisperModelManager.shared.downloadModel(url: $0, name: $1, progressCallback: $2)
    }, downloadFluid: @escaping (AsrModelVersion, ProgressHandler?) async throws -> AsrModels = {
        try await AsrModels.downloadAndLoad(version: $0, progressHandler: $1)
    }) {
        self.downloadFluid = downloadFluid
        self.downloadWhisper = downloadWhisper
        let prefs = AppPreferences.shared
        self.selectedEngine = prefs.selectedEngine
        self.fluidAudioModelVersion = prefs.fluidAudioModelVersion
        self.selectedLanguage = prefs.whisperLanguage
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.debugMode = prefs.debugMode
        self.playSoundOnRecordStart = prefs.playSoundOnRecordStart
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
        self.modifierOnlyHotkey = ModifierKey(rawValue: prefs.modifierOnlyHotkey) ?? .none
        self.mouseButtonHotkey = MouseButton(rawValue: prefs.mouseButtonHotkey) ?? .none
        self.holdToRecord = prefs.holdToRecord
        self.escCancelWithoutConfirmation = prefs.escCancelWithoutConfirmation
        self.startHiddenInMenuBar = prefs.startHiddenInMenuBar
        self.addSpaceAfterSentence = prefs.addSpaceAfterSentence
        self.autoCopyToClipboard = prefs.autoCopyToClipboard
        self.autoPasteTranscription = prefs.autoPasteTranscription
        self.translateEnabled = prefs.translateEnabled
        self.toneEnabled = prefs.toneEnabled
        self.transformToneMode = prefs.transformToneMode
        self.transformTargetLanguage = prefs.transformTargetLanguage
        self.transformEndpoint = prefs.transformEndpoint
        self.transformModel = prefs.transformModel
        self.transformTimeout = prefs.transformTimeout
        self.transformUseExternalEndpoint = prefs.transformUseExternalEndpoint

        if let savedPath = prefs.selectedWhisperModelPath ?? prefs.selectedModelPath {
            self.selectedModelURL = URL(fileURLWithPath: savedPath)
        }
        loadAvailableModels()
        initializeDownloadableModels()
        initializeFluidAudioModels()
        refreshTransformModelState()
        
        if !supportedLanguages.contains(selectedLanguage) {
            let fallback = LanguageUtil.fallbackLanguage(engine: selectedEngine)
            selectedLanguage = fallback
            AppPreferences.shared.whisperLanguage = fallback
            NotificationCenter.default.post(name: .appPreferencesLanguageChanged, object: nil)
        }
    }
    
    func initializeFluidAudioModels() {
        downloadableFluidAudioModels = SettingsFluidAudioModels.availableModels.map { model in
            var updatedModel = model
            updatedModel.isDownloaded = isFluidAudioModelDownloaded(version: model.version)
            return updatedModel
        }
    }
    
    func isFluidAudioModelDownloaded(version: String) -> Bool {
        let asrVersion: AsrModelVersion = version == "v2" ? .v2 : .v3
        
        // Используем правильный путь к кэшу согласно документации:
        // ~/Library/Application Support/FluidAudio/Models/<version-folder>/
        let cacheDirectory = AsrModels.defaultCacheDirectory(for: asrVersion)
        
        // Проверяем наличие всех необходимых файлов модели
        return AsrModels.modelsExist(at: cacheDirectory, version: asrVersion)
    }
    
    func initializeDownloadableModels() {
        let modelManager = WhisperModelManager.shared
        downloadableModels = SettingsDownloadableModels.availableModels.map { model in
            var updatedModel = model
            let filename = model.filename
            updatedModel.isDownloaded = modelManager.isModelDownloaded(name: filename)
            return updatedModel
        }
    }
    
    func loadAvailableModels() {
        availableModels = WhisperModelManager.shared.getAvailableModels()
        if selectedModelURL == nil {
            selectedModelURL = availableModels.first
        }
        initializeDownloadableModels()
        refreshInstalledModels()
    }

    // MARK: - What is on disk (G-04, G-05, G-06, G-07)

    /// One model file in the models directory, catalogue entry or not.
    struct InstalledWhisperModel: Identifiable, Equatable {
        let url: URL
        let name: String
        let sizeBytes: Int64
        let isSelected: Bool
        /// Set when the catalogue knows this file: it is then also the digest the
        /// publisher reports, which is what `Verify` compares against.
        let pinnedSHA256: String?

        var id: String { url.path }
        var sizeDescription: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
        var catalogueName: String? {
            SettingsDownloadableModels.availableModels.first { $0.filename == name }?.name
        }
    }

    @Published var installedWhisperModels: [InstalledWhisperModel] = []
    /// The last thing that happened to the models on disk, as the Model tab says it.
    @Published var modelStorageNotice: ModelStorageNotice?
    /// What the last check said, per checked path, in the words the row shows.
    @Published var checkSummaries: [String: String] = [:]
    /// Paths whose check found something wrong, so the row can say so loudly.
    @Published var checkProblems: Set<String> = []
    /// The path currently being checked, if any.
    @Published var checkingPath: String?
    /// The typed result of the last whisper-file check, for callers that want
    /// more than the sentence (the digest, and whether it matched).
    @Published var verificationResults: [String: ModelVerification] = [:]
    @Published var verificationError: String?

    /// Every model file on disk, selected one marked, catalogue digests attached.
    func refreshInstalledModels() {
        let manager = WhisperModelManager.shared
        let selectedPath = selectedModelURL?.path
        installedWhisperModels = manager.getAvailableModels().map { url in
            InstalledWhisperModel(url: url,
                                  name: url.lastPathComponent,
                                  sizeBytes: manager.fileSize(at: url),
                                  isSelected: selectedPath.map { WhisperModelManager.isSameFile(url.path, $0) } ?? false,
                                  pinnedSHA256: SettingsDownloadableModels.pinnedSHA256(forFilename: url.lastPathComponent))
        }
        modelStorageNotice = manager.lastNotice
    }

    /// How the Model tab names the model in use.
    var selectedModelDescription: String {
        guard let selectedModelURL else {
            return installedWhisperModels.isEmpty ? "none — no model file is on disk" : "none"
        }
        return selectedModelURL.lastPathComponent
    }

    /// Deletes a model file and updates everything that described it.
    func removeInstalledModel(_ model: InstalledWhisperModel) {
        do {
            modelStorageNotice = try WhisperModelManager.shared.removeModel(at: model.url)
        } catch {
            verificationError = error.localizedDescription
            return
        }
        verificationResults[model.url.path] = nil
        checkSummaries[model.url.path] = nil
        checkProblems.remove(model.url.path)
        loadAvailableModels()
        if selectedModelURL?.path != model.url.path,
           let reloadPath = selectedModelURL?.path {
            Task { @MainActor in
                TranscriptionService.shared.reloadModel(with: reloadPath)
            }
        }
    }

    /// Removes a catalogue row's downloaded file by name.
    func removeDownloadedModel(named filename: String) {
        let url = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            modelStorageNotice = try WhisperModelManager.shared.removeModel(at: url)
        } catch {
            verificationError = error.localizedDescription
            return
        }
        verificationResults[url.path] = nil
        checkSummaries[url.path] = nil
        checkProblems.remove(url.path)
        loadAvailableModels()
    }

    /// Checks a model file against the digest the catalogue pins for it. The
    /// digest of a 1.6 GB file takes seconds, so it runs off the main thread.
    func verifyModel(at url: URL, pinnedSHA256: String?) {
        guard checkingPath == nil else { return }
        checkingPath = url.path
        verificationError = nil
        Task.detached(priority: .userInitiated) { [pinnedSHA256] in
            let outcome = Result { try WhisperModelManager.shared.verifyModel(at: url, pinnedSHA256: pinnedSHA256) }
            await MainActor.run {
                self.checkingPath = nil
                switch outcome {
                case .success(let verification):
                    self.verificationResults[url.path] = verification
                    self.checkSummaries[url.path] = verification.summary
                    if verification.matchesPinnedDigest == false { self.checkProblems.insert(url.path) }
                    else { self.checkProblems.remove(url.path) }
                case .failure(let error):
                    self.verificationError = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    func verification(for url: URL) -> ModelVerification? {
        verificationResults[url.path]
    }

    /// Checks a Parakeet model's files: FluidAudio publishes no digest for them,
    /// so what is checked is that every file the engine needs is on disk and
    /// none of them is empty, and the row says exactly that.
    func verifyFluidAudioModel(version: String) {
        let asrVersion: AsrModelVersion = version == "v2" ? .v2 : .v3
        let directory = AsrModels.defaultCacheDirectory(for: asrVersion)
        guard checkingPath == nil else { return }
        checkingPath = directory.path
        verificationError = nil

        Task.detached(priority: .userInitiated) { [directory, asrVersion] in
            let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                      includingPropertiesForKeys: [.fileSizeKey]))
                ?? []
            let totalBytes = files.reduce(Int64(0)) { sum, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sum + Int64(size)
            }
            let empty = files.filter { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) == 0 }
            let complete = AsrModels.modelsExist(at: directory, version: asrVersion)
            await MainActor.run {
                self.checkingPath = nil
                let sizeText = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                if complete && empty.isEmpty {
                    self.checkSummaries[directory.path] =
                        "Verified ✓ — \(countLabel(files.count, singular: "file", plural: "files")), \(sizeText) on disk"
                    self.checkProblems.remove(directory.path)
                } else {
                    self.checkSummaries[directory.path] =
                        "Incomplete — \(countLabel(files.count, singular: "file", plural: "files")), \(sizeText) on disk"
                        + (empty.isEmpty ? "" : ", \(empty.count) of them empty")
                    self.checkProblems.insert(directory.path)
                }
            }
        }
    }

    /// Size on disk of a Parakeet model, for the "Installed" line.
    func fluidAudioModelSizeDescription(version: String) -> String {
        let asrVersion: AsrModelVersion = version == "v2" ? .v2 : .v3
        let directory = AsrModels.defaultCacheDirectory(for: asrVersion)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let totalBytes = files.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Deletes a Parakeet model's files. The engine downloads them again on
    /// demand, and the row stops claiming to be installed.
    func removeFluidAudioModel(version: String) {
        let asrVersion: AsrModelVersion = version == "v2" ? .v2 : .v3
        let directory = AsrModels.defaultCacheDirectory(for: asrVersion)
        let freed = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: [.fileSizeKey]))?
            .reduce(Int64(0)) { sum, url in
                sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            } ?? 0
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            verificationError = error.localizedDescription
            return
        }
        checkSummaries[directory.path] = nil
        checkProblems.remove(directory.path)
        modelStorageNotice = .removed(name: "Parakeet \(version)", bytesFreed: freed)
        initializeFluidAudioModels()
    }
    
    @MainActor
    func downloadModel(_ model: SettingsDownloadableModel) async throws {
        guard !isDownloading else { return }
        try DiskSpaceUtil.ensureEnoughFreeSpaceForModelDownload()
        
        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0
        
        let id = UUID()
        downloadID = id
        downloadTask = Task {
            defer {
                if downloadID == id { downloadTask = nil; downloadID = nil }
            }
            do {
                let filename = model.filename
                
                try await downloadWhisper(model.url, filename) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.downloadID == id, !Task.isCancelled else { return }
                        guard let task = self.downloadTask, !task.isCancelled else { return }
                        
                        self.downloadProgress = progress
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = progress
                        }
                    }
                }
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard self.downloadID == id else { return }
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = 0.0
                        }
                    }
                    return
                }
                
                await MainActor.run {
                    guard self.downloadID == id else { return }
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].isDownloaded = true
                        downloadableModels[index].downloadProgress = 0.0
                    }
                    loadAvailableModels()
                    let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(filename).path
                    selectModel(URL(fileURLWithPath: modelPath))
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    
                    Task { @MainActor in
                        TranscriptionService.shared.reloadModel(with: modelPath)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.downloadID == id else { return }
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
            } catch {
                guard self.downloadID == id, !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.downloadID == id else { return }
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
                throw error
            }
        }
        
        try await downloadTask?.value
    }
    
    func cancelDownload() {
        downloadID = nil
        downloadTask?.cancel()
        if let modelName = downloadingModelName {
            if selectedEngine == "whisper", let model = downloadableModels.first(where: { $0.name == modelName }) {
                let filename = model.filename
                WhisperModelManager.shared.cancelDownload(name: filename)
            }
            // Reset progress for the downloading model
            if let index = downloadableModels.firstIndex(where: { $0.name == modelName }) {
                downloadableModels[index].downloadProgress = 0.0
            }
            if let index = downloadableFluidAudioModels.firstIndex(where: { $0.name == modelName }) {
                downloadableFluidAudioModels[index].downloadProgress = 0.0
            }
        }
        isDownloading = false
        downloadingModelName = nil
        downloadProgress = 0.0
    }
    
    @MainActor
    func downloadFluidAudioModel(_ model: SettingsFluidAudioModel) async throws {
        guard !isDownloading else { return }
        try DiskSpaceUtil.ensureEnoughFreeSpaceForModelDownload()
        
        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0
        
        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
            downloadableFluidAudioModels[index].downloadProgress = 0.0
        }
        
        var wasCancelled = false
        
        let id = UUID()
        downloadID = id
        downloadTask = Task {
            defer {
                if downloadID == id { downloadTask = nil; downloadID = nil }
            }
            do {
                let version: AsrModelVersion = model.version == "v2" ? .v2 : .v3
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard self.downloadID == id else { return }
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }
                
                let modelId = model.id
                let models = try await downloadFluid(version) { [weak self] progress in
                    print("[ParakeetProgress] fraction=\(progress.fractionCompleted) phase=\(progress.phase)")
                    Task { @MainActor [weak self] in
                        guard let self = self, self.downloadID == id, !Task.isCancelled else { return }
                        guard let task = self.downloadTask, !task.isCancelled else { return }
                        self.downloadProgress = progress.fractionCompleted
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == modelId }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = progress.fractionCompleted
                        }
                    }
                }
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard self.downloadID == id else { return }
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }
                
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                
                await MainActor.run {
                    guard self.downloadID == id else { return }
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].isDownloaded = true
                        downloadableFluidAudioModels[index].downloadProgress = 1.0
                    }
                    fluidAudioModelVersion = model.version
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 1.0
                    
                    Task { @MainActor in
                        TranscriptionService.shared.reloadEngine()
                    }
                }
            } catch is CancellationError {
                wasCancelled = true
                await MainActor.run {
                    guard self.downloadID == id else { return }
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].downloadProgress = 0.0
                    }
                }
                // Don't re-throw CancellationError - it's a manual cancellation
            } catch {
                guard self.downloadID == id, !Task.isCancelled else { return }
                // Check if we were cancelled before the error occurred
                if Task.isCancelled {
                    wasCancelled = true
                    await MainActor.run {
                        guard self.downloadID == id else { return }
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                } else {
                    await MainActor.run {
                        guard self.downloadID == id else { return }
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw error
                }
            }
        }
        
        // Handle cancellation gracefully - don't throw if cancelled
        do {
            try await downloadTask?.value
        } catch is CancellationError {
            // Already handled in catch block above, just consume the error
            wasCancelled = true
        } catch {
            // If we were cancelled, don't throw
            if !wasCancelled {
                throw error
            }
        }
    }
    
    @MainActor
    func downloadFluidAudioModel() async throws {
        let versionString = AppPreferences.shared.fluidAudioModelVersion
        if let model = downloadableFluidAudioModels.first(where: { $0.version == versionString }) {
            try await downloadFluidAudioModel(model)
        }
    }
}

struct SettingsDownloadableModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let url: URL
    let size: Int
    let description: String
    var downloadProgress: Double = 0.0
    let filename: String
    let preferredLanguage: String?
    /// The digest the model's publisher reports for this file. `Verify` in the
    /// Model tab compares the file on disk against it, so "it downloaded" is not
    /// the only thing the user has to go on.
    let sha256: String?

    var sizeString: String {
        formatModelSize(megabytes: size)
    }

    var huggingFacePageURL: URL? {
        makeHuggingFacePageURL(fromDownloadURL: url)
    }

    init(name: String, isDownloaded: Bool, url: URL, size: Int, description: String,
         filename: String? = nil, preferredLanguage: String? = nil, sha256: String? = nil) {
        self.name = name
        self.isDownloaded = isDownloaded
        self.url = url
        self.size = size
        self.description = description
        self.filename = filename ?? url.lastPathComponent
        self.preferredLanguage = preferredLanguage
        self.sha256 = sha256
    }
}

struct SettingsDownloadableModels {
    static let availableModels = [
        SettingsDownloadableModel(
            name: "Turbo V3 large",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
            size: 1624,
            description: "High accuracy, best quality",
            sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 medium",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
            size: 874,
            description: "Balanced speed and accuracy",
            sha256: "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1"
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 small",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
            size: 574,
            description: "Fastest processing",
            sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 Hebrew",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin?download=true")!,
            size: 1624,
            description: "Hebrew fine-tune of Turbo V3 by ivrit.ai. Sets the language to Hebrew.",
            filename: "ggml-ivrit-large-v3-turbo.bin",
            preferredLanguage: "he",
            sha256: "c8090411113357097bfafc2b8e228ec1639fa7f5fe4ecb5d054ac0ccef8641b1"
        )
    ]

    static func preferredLanguage(forFilename filename: String) -> String? {
        availableModels.first { $0.filename == filename }?.preferredLanguage
    }

    /// The digest published for a file, or `nil` for one nobody publishes a
    /// checksum for (a hand-placed model, say).
    ///
    /// The model the app ships with is not a catalogue entry — it comes from the
    /// bundle, not a download — but its publisher does publish a digest for it,
    /// so `Verify` can still compare it instead of shrugging.
    static func pinnedSHA256(forFilename filename: String) -> String? {
        if filename == WhisperModelManager.defaultModelName {
            return bundledModelSHA256
        }
        return availableModels.first { $0.filename == filename }?.sha256
    }

    /// sha256 of `ggml-tiny.en.bin`, as published by the whisper.cpp repository
    /// it is released from.
    static let bundledModelSHA256 = "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"

    static func isVisible(_ model: SettingsDownloadableModel,
                          selectedLanguage: String,
                          systemLanguage: String) -> Bool {
        guard let lang = model.preferredLanguage else { return true }
        if model.isDownloaded { return true }
        return selectedLanguage == lang || systemLanguage == lang
    }
}

func countLabel(_ count: Int, singular: String, plural: String) -> String {
    count == 1 ? "\(count) \(singular)" : "\(count) \(plural)"
}

func formatModelSize(megabytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: Int64(megabytes) * 1000000)
}

func makeHuggingFacePageURL(fromDownloadURL url: URL) -> URL? {
    let absoluteString = url.absoluteString
    guard let range = absoluteString.range(of: "/resolve/") else { return nil }
    return URL(string: String(absoluteString[..<range.lowerBound]))
}

/// The Hugging Face owner (user / organization) from a model page URL,
/// e.g. https://huggingface.co/ivrit-ai/whisper-... -> "ivrit-ai".
func huggingFaceOwner(fromPageURL url: URL) -> String? {
    url.pathComponents.first { $0 != "/" }
}

struct Settings {
    static let asianLanguages: Set<String> = ["zh", "ja", "ko"]
    
    var selectedLanguage: String
    /// Advanced → Debug Options. Whisper prints its verbose decode trace when
    /// this is on; read here so the toggle takes effect on the next dictation.
    var debugMode: Bool
    var suppressBlankAudio: Bool
    var showTimestamps: Bool
    var temperature: Double
    var noSpeechThreshold: Double
    var initialPrompt: String
    var useBeamSearch: Bool
    var beamSize: Int
    var useAsianAutocorrect: Bool
    
    var isAsianLanguage: Bool {
        Settings.asianLanguages.contains(selectedLanguage)
    }
    
    var shouldApplyAsianAutocorrect: Bool {
        isAsianLanguage && useAsianAutocorrect
    }
    
    init() {
        let prefs = AppPreferences.shared
        self.selectedLanguage = prefs.whisperLanguage
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
        self.debugMode = prefs.debugMode
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var permissionsManager = PermissionsManager()
    /// G-12: the Advanced tab resets the welcome flow through the same state the
    /// app's root reads.
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var isRecordingNewShortcut = false
    @State private var selectedTab = 0
    @State private var previousModelURL: URL?
    @State private var showingUninstallSheet = false
    @State private var resetPermissionsOnUninstall = false
    @State private var uninstallError: String?

    /// Lets the offscreen snapshot harness (SettingsLayoutSnapshotTests) open a
    /// tab other than the first; the app keeps using `SettingsView()`.
    init(selectedTab: Int = 0) {
        _selectedTab = State(initialValue: selectedTab)
    }

    // The four tab bodies below are internal rather than private so the offscreen
    // layout snapshot harness (SettingsLayoutSnapshotTests) can render one tab at
    // a time; nothing outside this file uses them.

    /// The sheet's natural size. The width fits the 450 pt main window that
    /// presents the sheet: at 550 pt the sheet was wider than its own window.
    private var sheetSize: CGSize {
        let visibleFrame = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let width = min(450, visibleFrame.width - 40)
        let height = min(500, visibleFrame.height - 60)
        return CGSize(width: width, height: height)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsTabStrip
            settingsTabContent
        }
        .padding()
        // Flexible on purpose: whatever room the sheet window ends up with — a
        // 400 pt tall window on a small screen, a taller one on a big screen —
        // the cards lay out in it and the tab scrolls instead of hanging off the
        // panel edge.
        .frame(minWidth: 380, idealWidth: sheetSize.width, maxWidth: .infinity,
               minHeight: 300, idealHeight: sheetSize.height, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                
                Spacer()
                
                Link(destination: URL(string: "https://github.com/Starmel/OpenSuperWhisper")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 10))
                        Text("GitHub")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .onAppear {
            previousModelURL = viewModel.selectedModelURL
            if viewModel.selectedEngine == "fluidaudio" {
                viewModel.initializeFluidAudioModels()
            }
        }
        .onChange(of: viewModel.selectedEngine) { _, newEngine in
            if newEngine == "fluidaudio" {
                viewModel.initializeFluidAudioModels()
            }
        }
        .onChange(of: viewModel.selectedModelURL) { _, newURL in
            if viewModel.selectedEngine == "whisper", let modelPath = newURL?.path {
                Task { @MainActor in
                    TranscriptionService.shared.reloadModel(with: modelPath)
                }
            }
        }
        .sheet(isPresented: $showingUninstallSheet) {
            UninstallConfirmationSheet(
                resetPermissions: $resetPermissionsOnUninstall,
                onCancel: { showingUninstallSheet = false },
                onConfirm: {
                    showingUninstallSheet = false
                    performUninstall()
                }
            )
        }
    }

    /// The tab strip.
    ///
    /// This is a plain segmented control rather than the `TabView` strip it
    /// replaced, because inside a sheet a `TabView`'s strip never gets a size on
    /// this macOS: `NSTabViewSegmentedControl` stays 0x0, so the four labels are
    /// drawn on top of each other and there is nothing to click — which is how
    /// the Transcription tab, and with it the tone controls, became unreachable.
    /// The same four tabs, the same `selectedTab`, nothing else moved.
    private var settingsTabStrip: some View {
        Picker("", selection: $selectedTab) {
            Text("Shortcuts").tag(0)
            Text("Model").tag(1)
            Text("Transcription").tag(2)
            Text("Advanced").tag(3)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch selectedTab {
        case 1:
            modelSettings
        case 2:
            transcriptionSettings
        case 3:
            advancedSettings
        default:
            shortcutSettings
        }
    }

    /// Starts the uninstaller and quits. The script waits for this process to
    /// exit before it removes anything, which is the only way an app can delete
    /// the bundle it is running from.
    private func performUninstall() {
        do {
            try UninstallService.startUninstall(resetPermissions: resetPermissionsOnUninstall)
        } catch {
            uninstallError = error.localizedDescription
            return
        }
        NSApplication.shared.terminate(nil)
    }
    
    var modelSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Speech Recognition Engine")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Picker("Engine", selection: $viewModel.selectedEngine) {
                    Text("Parakeet").tag("fluidaudio")
                    Text("Whisper").tag("whisper")
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
                
                if viewModel.selectedEngine == "whisper" {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Whisper Model")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Download Models")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                        
                        VStack(spacing: 12) {
                            ForEach($viewModel.downloadableModels) { $model in
                                if SettingsDownloadableModels.isVisible(model,
                                        selectedLanguage: viewModel.selectedLanguage,
                                        systemLanguage: LanguageUtil.getSystemLanguage()) {
                                    ModelDownloadItemView(model: $model, viewModel: viewModel)
                                }
                            }
                        }
                        
                        // G-05: everything on disk, catalogue row or not, with
                        // the file in use marked. G-07: what the app did about
                        // the models last, including a fallback nobody asked for.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Installed models (\(viewModel.installedWhisperModels.count))")
                                    .font(.headline)
                                Spacer()
                                Button("Refresh") {
                                    viewModel.loadAvailableModels()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .help("Re-read the models directory")
                            }

                            Text("Selected model: \(viewModel.selectedModelDescription)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let notice = viewModel.modelStorageNotice {
                                Text(notice.message)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let error = viewModel.verificationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(viewModel.installedWhisperModels) { model in
                                InstalledWhisperModelView(model: model, viewModel: viewModel)
                            }

                            if viewModel.installedWhisperModels.isEmpty {
                                Text("No model files on disk.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Models Directory:")
                                    .font(.subheadline)
                                Button(action: {
                                    NSWorkspace.shared.open(WhisperModelManager.shared.modelsDirectory)
                                }) {
                                    Label("Open Folder", systemImage: "folder")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.borderless)
                                .help("Open models directory")
                            }
                            Text(WhisperModelManager.shared.modelsDirectory.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                        }
                        .padding(.top, 8)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Parakeet Model")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Download Models")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                        
                        VStack(spacing: 12) {
                            ForEach($viewModel.downloadableFluidAudioModels) { $model in
                                FluidAudioModelDownloadItemView(model: $model, viewModel: viewModel)
                            }
                        }
                        
                        if let notice = viewModel.modelStorageNotice {
                            Text(notice.message)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let error = viewModel.verificationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Models Directory:")
                                    .font(.subheadline)
                                Button(action: {
                                    let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
                                    let parentDir = cacheDir.deletingLastPathComponent()
                                    NSWorkspace.shared.open(parentDir)
                                }) {
                                    Label("Open Folder", systemImage: "folder")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.borderless)
                                .help("Open models directory")
                            }
                            Text(AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor).opacity(0.3))
            .cornerRadius(12)
        }
        .padding()
    }
    
    var transcriptionSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Language Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Language Settings")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcription Language")
                            .font(.subheadline)
                        
                        Picker("Language", selection: $viewModel.selectedLanguage) {
                            ForEach(viewModel.supportedLanguages, id: \.self) { code in
                                Text(LanguageUtil.languageNames[code] ?? code)
                                    .tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if Settings.asianLanguages.contains(viewModel.selectedLanguage) {
                            HStack {
                                Text("Use Asian Autocorrect")
                                    .font(.subheadline)
                                Spacer()
                                Toggle("", isOn: $viewModel.useAsianAutocorrect)
                                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                    .labelsHidden()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Output Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Output Options")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Show Timestamps")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.showTimestamps)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Suppress Blank Audio")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.suppressBlankAudio)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Space After Sentence")
                                    .font(.subheadline)
                                Text("Appends a space when transcription ends with punctuation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.addSpaceAfterSentence)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Clipboard & Paste
                VStack(alignment: .leading, spacing: 16) {
                    Text("Clipboard & Paste")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Copy to Clipboard")
                                    .font(.subheadline)
                                Text("Keep transcription in clipboard after recording")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.autoCopyToClipboard)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-paste Transcription")
                                    .font(.subheadline)
                                Text("Types the text into the focused app as keystrokes — "
                                     + "the clipboard is not used, and Accessibility is required "
                                     + "for the keystrokes to land")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.autoPasteTranscription)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Translation & Tone
                VStack(alignment: .leading, spacing: 16) {
                    Text("Translation & Tone")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Translate into \(viewModel.transformTargetLanguage.displayName)")
                                    .font(.subheadline)
                                Text("Translate dictation into the target language below; speech already in it is pasted unchanged")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.translateEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Target language")
                                .font(.subheadline)
                            Picker("Target language", selection: $viewModel.transformTargetLanguage) {
                                ForEach(TransformLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .disabled(!viewModel.translateEnabled)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apply tone")
                                    .font(.subheadline)
                                Text("Rewrite the translated text in the selected tone — a tone rides on a translation, so it needs the translation switch on")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.toneEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tone")
                                .font(.subheadline)
                            Picker("Tone", selection: $viewModel.transformToneMode) {
                                ForEach(ToneMode.allCases) { tone in
                                    Text(tone.displayName).tag(tone)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .disabled(!viewModel.toneEnabled)
                        }

                        // Built-in runtime: the weights the app downloads and
                        // runs itself. The endpoint fields live in Advanced,
                        // because they are the override, not the default.
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Transform model")
                                        .font(.subheadline)
                                    Text(viewModel.transformModelStateDescription)
                                        .font(.caption)
                                        .foregroundColor(viewModel.transformModelInstalled ? .secondary : .orange)
                                }
                                Spacer()
                                if viewModel.isDownloadingTransformModel {
                                    Button("Cancel") {
                                        viewModel.cancelTransformModelDownload()
                                    }
                                    .font(.subheadline)
                                } else if viewModel.transformModelInstalled {
                                    Button("Remove") {
                                        viewModel.removeTransformModel()
                                    }
                                    .font(.subheadline)
                                } else {
                                    Button("Download model") {
                                        Task { await viewModel.downloadTransformModel() }
                                    }
                                    .font(.subheadline)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(viewModel.transformUseExternalEndpoint)
                                }
                            }

                            if viewModel.isDownloadingTransformModel {
                                ProgressView(value: viewModel.transformModelDownloadProgress)
                                Text(String(
                                    format: "%.0f%% of %@",
                                    viewModel.transformModelDownloadProgress * 100,
                                    viewModel.resolvedTransformModel.sizeDescription
                                ))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }

                            if viewModel.transformNeedsModel {
                                Text("Until this model is downloaded, dictation is pasted unchanged.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            if let error = viewModel.transformModelError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            Text("Runs inside the app: \(viewModel.transformModelSourceDescription). Downloaded into the app's own folder, so uninstalling takes it with it.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("The pasted text depends on the spoken language, the target language and the two switches: raw by default, translated into the target when the spoken language differs from it and the translation switch is on, and toned with the tone switch on. Speech already in the target language is always pasted untouched — it never reaches the model. Dictation history always keeps the raw transcript, and recordings transcribed from the list are never transformed. Language awareness needs a multilingual whisper model in Auto-detect; with a fixed language the app trusts your setting. Polish output is best-effort with the bundled model — English output is the reliable direction.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Initial Prompt
                VStack(alignment: .leading, spacing: 16) {
                    Text("Initial Prompt")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $viewModel.initialPrompt)
                            .frame(height: 60)
                            .padding(6)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
                        Text("Optional text to guide the model's transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Transcriptions Directory
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transcriptions Directory")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Directory:")
                                .font(.subheadline)
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(Recording.recordingsDirectory)
                            }) {
                                Label("Open Folder", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .help("Open transcriptions directory")
                        }
                        
                        Text(Recording.recordingsDirectory.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                RecordingStorageSettingsView()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(12)
            }
            .padding()
        }
    }
    
    var advancedSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Decoding Strategy
                VStack(alignment: .leading, spacing: 16) {
                    Text("Decoding Strategy")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Use Beam Search")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.useBeamSearch)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Beam search can provide better results but is slower")
                        }
                        
                        if viewModel.useBeamSearch {
                            HStack {
                                Text("Beam Size:")
                                    .font(.subheadline)
                                Spacer()
                                Stepper("\(viewModel.beamSize)", value: $viewModel.beamSize, in: 1...10)
                                    .help("Number of beams to use in beam search")
                                    .frame(width: 120)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Model Parameters
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Parameters")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.temperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.1)
                                .help("Higher values make the output more random")
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("No Speech Threshold:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.noSpeechThreshold))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $viewModel.noSpeechThreshold, in: 0.0...1.0, step: 0.1)
                                .help("Threshold for detecting speech vs. silence")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Transform backend (advanced override)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transform Backend")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use an external endpoint")
                                    .font(.subheadline)
                                Text("Send the transform to an OpenAI-compatible endpoint instead of the engine built into the app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.transformUseExternalEndpoint)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Endpoint")
                                .font(.subheadline)
                            TextField("http://127.0.0.1:1919/v1/chat/completions", text: $viewModel.transformEndpoint)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!viewModel.transformUseExternalEndpoint)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model id")
                                .font(.subheadline)
                            TextField("qwen2.5-1.5b-instruct-q4_k_m", text: $viewModel.transformModel)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!viewModel.transformUseExternalEndpoint)
                            Text(viewModel.transformUseExternalEndpoint
                                 ? "The id the endpoint reports in /v1/models."
                                 : "The model the built-in engine loads: \(viewModel.resolvedTransformModel.displayName).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Timeout (seconds):")
                                .font(.subheadline)
                            Spacer()
                            TextField("", value: $viewModel.transformTimeout, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                .disabled(!viewModel.transformUseExternalEndpoint)
                        }

                        Text("With the override off, translation and tone are processed in this process against the downloaded model; nothing listens on a port and no other process has to be running.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // G-12: the welcome flow could only be re-shown by editing a
                // DEBUG config file; this is the same reset, from the UI.
                welcomeScreenSettings

                // Uninstall
                VStack(alignment: .leading, spacing: 16) {
                    Text("Uninstall")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Removes the app, your dictation history, the downloaded models and the installer receipt in one operation.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Uninstall OpenSuperWhisper…") {
                            uninstallError = nil
                            showingUninstallSheet = true
                        }
                        .foregroundColor(.red)

                        if let uninstallError {
                            Text(uninstallError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Debug Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Debug Options")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Debug Mode")
                                .font(.subheadline)
                            Text("Prints whisper.cpp's verbose decode trace while transcribing "
                                 + "(temperatures, fallbacks, timings) — for bug reports")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.debugMode)
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                            .labelsHidden()
                            .help("Print the decoder's verbose trace to the app's output")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    private enum TriggerMode: Hashable {
        case keyCombo
        case modifier
        case mouse
    }

    @ViewBuilder
    private func permissionWarning(message: String, isGranted: Bool, grantAction: @escaping () -> Void) -> some View {
        if permissionsManager.hasCompletedInitialCheck && !isGranted {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.orange)
                
                Button("Grant Permission") {
                    grantAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    private var triggerMode: TriggerMode {
        if viewModel.mouseButtonHotkey != .none { return .mouse }
        if viewModel.modifierOnlyHotkey != .none { return .modifier }
        return .keyCombo
    }
    
    /// G-12: show the welcome flow again.
    ///
    /// It sets the language, the shortcut and the model, and it was reachable
    /// only once — resetting `hasCompletedOnboarding` needed a DEBUG
    /// `dev_config.json`. This is the same reset, and it changes nothing until
    /// something is picked in the flow.
    private var welcomeScreenSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome Screen")
                .font(.headline)
                .foregroundColor(.primary)

            Text("The welcome screen sets your dictation language, shortcut and speech model. "
                 + "Showing it again changes none of them until you choose something there. "
                 + "The main window shows it as soon as this sheet closes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Show the welcome screen again") {
                appState.hasCompletedOnboarding = false
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    /// G-02/G-03: the two grants this app needs, in Settings, where everything
    /// else about its state lives.
    ///
    /// Both were invisible here before: the Accessibility warning existed only
    /// inside two of the three trigger modes (never for the default key
    /// combination), and the microphone was not mentioned in the sheet at all —
    /// the only place it appeared was the main window, and only while something
    /// was missing.
    private var permissionsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.headline)
                .foregroundColor(.primary)

            permissionSettingsRow(
                title: "Keystrokes into other apps",
                detail: "Accessibility. Needed to type a transcription into the app you are dictating into.",
                granted: permissionsManager.isAccessibilityPermissionGranted,
                action: { permissionsManager.requestAccessibilityPermissionOrOpenSystemPreferences() })

            permissionSettingsRow(
                title: "Microphone",
                detail: "Needed to record your dictation.",
                granted: permissionsManager.isMicrophonePermissionGranted,
                action: { permissionsManager.requestMicrophonePermissionOrOpenSystemPreferences() })
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        // The sheet is not the main window, so the manager's own poll does not
        // run here: read both grants when the tab is opened, and again when the
        // app comes back from System Settings (the manager watches activation).
        .onAppear {
            permissionsManager.checkAccessibilityPermission()
            permissionsManager.checkMicrophonePermission()
        }
    }

    @ViewBuilder
    private func permissionSettingsRow(title: String, detail: String, granted: Bool,
                                       action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .orange)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if permissionsManager.hasCompletedInitialCheck {
                    Text(granted ? "Granted" : "Not granted")
                        .font(.caption)
                        .foregroundColor(granted ? .green : .orange)
                } else {
                    Text("Checking…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !granted {
                Button("Open System Settings", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    var shortcutSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                permissionsSettings

                // Recording Trigger
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Trigger")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("", selection: Binding(
                            get: { triggerMode },
                            set: { newMode in
                                switch newMode {
                                case .keyCombo:
                                    viewModel.mouseButtonHotkey = .none
                                    viewModel.modifierOnlyHotkey = .none
                                case .modifier:
                                    viewModel.mouseButtonHotkey = .none
                                    if viewModel.modifierOnlyHotkey == .none {
                                        viewModel.modifierOnlyHotkey =
                                            ModifierKey(rawValue: AppPreferences.shared.lastModifierOnlyHotkey) ?? .leftCommand
                                    }
                                case .mouse:
                                    viewModel.modifierOnlyHotkey = .none
                                    if viewModel.mouseButtonHotkey == .none {
                                        viewModel.mouseButtonHotkey = .middle
                                    }
                                }
                            }
                        )) {
                            Text("Key Combination").tag(TriggerMode.keyCombo)
                            Text("Single Modifier Key").tag(TriggerMode.modifier)
                            Text("Mouse Button").tag(TriggerMode.mouse)
                        }
                        .pickerStyle(.segmented)

                        switch triggerMode {
                        case .modifier:
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Modifier Key")
                                        .font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $viewModel.modifierOnlyHotkey) {
                                        ForEach(ModifierKey.allCases.filter { $0 != .none }) { key in
                                            Text(key.displayName).tag(key)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 200)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(8)

                                Text("One-tap to toggle recording")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                permissionWarning(
                                    message: "This mode requires Accessibility permission so single modifier key presses can be detected globally. Only modifier key events (⌘, ⌥, ⇧, ⌃, Fn) are monitored — no regular keystrokes are captured.",
                                    isGranted: permissionsManager.isAccessibilityPermissionGranted
                                ) {
                                    permissionsManager.requestAccessibilityPermissionOrOpenSystemPreferences()
                                }
                            }
                        case .mouse:
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Mouse Button")
                                        .font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $viewModel.mouseButtonHotkey) {
                                        ForEach(MouseButton.allCases.filter { $0 != .none }) { button in
                                            Text(button.displayName).tag(button)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 200)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(8)

                                Text("Click to toggle recording, or hold when Hold to Record is on. The left and right buttons are reserved — pick the middle or an extra (thumb) button.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                permissionWarning(
                                    message: "⚠️ This mode requires Accessibility permission so the button can be detected globally and used only as a recording trigger. Only the selected mouse button is intercepted — no other clicks or keystrokes are captured.",
                                    isGranted: permissionsManager.isAccessibilityPermissionGranted
                                ) {
                                    permissionsManager.requestAccessibilityPermissionOrOpenSystemPreferences()
                                }
                            }
                        case .keyCombo:
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Shortcut")
                                        .font(.subheadline)
                                    Spacer()
                                    KeyboardShortcuts.Recorder("", name: .toggleRecord)
                                        .frame(width: 150)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(8)

                                if isRecordingNewShortcut {
                                    Text("Press your new shortcut combination...")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Recording Behavior
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Behavior")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold to Record")
                                    .font(.subheadline)
                                Text("Hold the shortcut to record, release to stop")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.holdToRecord)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Play sound when recording starts")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.playSoundOnRecordStart)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Play a notification sound when recording begins")
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cancel without confirmation")
                                    .font(.subheadline)
                                Text("Skip the double-Esc confirmation for recordings longer than 10 seconds")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.escCancelWithoutConfirmation)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Application
                VStack(alignment: .leading, spacing: 16) {
                    Text("Application")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start hidden in menu bar")
                                .font(.subheadline)
                            Text("Launch without opening the main window; use the menu bar icon to open it")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.startHiddenInMenuBar)
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                            .labelsHidden()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

struct SettingsFluidAudioModel: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    var isDownloaded: Bool
    let description: String
    let size: Int
    var downloadProgress: Double = 0.0

    var sizeString: String {
        formatModelSize(megabytes: size)
    }
}

struct SettingsFluidAudioModels {
    static let availableModels = [
        SettingsFluidAudioModel(
            name: "Parakeet v3",
            version: "v3",
            isDownloaded: false,
            description: "Multilingual, 25 languages",
            size: 483
        ),
        SettingsFluidAudioModel(
            name: "Parakeet v2",
            version: "v2",
            isDownloaded: false,
            description: "English-only, higher recall",
            size: 464
        )
    ]
}

enum OnboardingModelType {
    case whisper(url: URL, size: Int)
    case parakeet(version: String)
}

struct OnboardingUnifiedModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let description: String
    let type: OnboardingModelType
    var downloadProgress: Double = 0.0

    var huggingFacePageURL: URL? {
        switch type {
        case .whisper(let url, _):
            return makeHuggingFacePageURL(fromDownloadURL: url)
        case .parakeet(let version):
            let repo = version == "v2" ? "parakeet-tdt-0.6b-v2-coreml" : "parakeet-tdt-0.6b-v3-coreml"
            return URL(string: "https://huggingface.co/FluidInference/\(repo)")
        }
    }
}

struct OnboardingUnifiedModels {
    static let availableModels = [
        OnboardingUnifiedModel(
            name: "Whisper V3 Large",
            isDownloaded: false,
            description: "High accuracy, best quality",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
                size: 1624
            )
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v3",
            isDownloaded: false,
            description: "Fastest processing and accurate",
            type: .parakeet(version: "v3")
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v2",
            isDownloaded: false,
            description: "Fastest processing and English-only, higher recall",
            type: .parakeet(version: "v2")
        ),
        OnboardingUnifiedModel(
            name: "Whisper Medium",
            isDownloaded: false,
            description: "Balanced speed and accuracy",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
                size: 874
            )
        ),
        OnboardingUnifiedModel(
            name: "Whisper Small",
            isDownloaded: false,
            description: "Very fast processing",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
                size: 574
            )
        )
    ]
}

struct FluidAudioModelDownloadItemView: View {
    @Binding var model: SettingsFluidAudioModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""
    
    var isSelected: Bool {
        viewModel.fluidAudioModelVersion == model.version
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if model.isDownloaded {
                    Text("Downloaded — \(viewModel.fluidAudioModelSizeDescription(version: model.version)) on disk")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 6)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        if isSelected {
                            Label("In use", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Button(action: {
                                viewModel.fluidAudioModelVersion = model.version
                            }) {
                                Text("Select")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Remove") {
                            viewModel.removeFluidAudioModel(version: model.version)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Delete this model's files and free the space they take")

                        Button("Verify") {
                            viewModel.verifyFluidAudioModel(version: model.version)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    if viewModel.checkingPath == AsrModels.defaultCacheDirectory(for: model.version == "v2" ? .v2 : .v3).path {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    if let summary = viewModel.checkSummaries[
                        AsrModels.defaultCacheDirectory(for: model.version == "v2" ? .v2 : .v3).path] {
                        Text(summary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text(model.sizeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        Task {
                            do {
                                try await viewModel.downloadFluidAudioModel(model)
                            } catch is CancellationError {
                                // Don't show error for manual cancellation
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isDownloading)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color(.controlBackgroundColor).opacity(0.7) : Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded && !isSelected {
                viewModel.fluidAudioModelVersion = model.version
            }
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

struct RecordingStorageSettingsView: View {
    @State private var autoDeleteEnabled = AppPreferences.shared.autoDeleteRecordingsEnabled
    @State private var retentionDays = AppPreferences.shared.autoDeleteRecordingsAfterDays
    @State private var diskUsage: Int64 = 0
    @State private var showConfirmation = false
    @State private var pendingDays = 0
    @State private var pendingCount = 0
    @State private var pendingOldestDate: Date?

    private let dayOptions = [1, 7, 14, 30, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History Storage")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recordings on disk:")
                        .font(.subheadline)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: diskUsage, countStyle: .file))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Delete recordings older than")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { retentionDays },
                        set: { newValue in
                            if autoDeleteEnabled {
                                requestAutoDelete(days: newValue)
                            } else {
                                retentionDays = newValue
                                AppPreferences.shared.autoDeleteRecordingsAfterDays = newValue
                            }
                        }
                    )) {
                        ForEach(dayOptions, id: \.self) { days in
                            Text(countLabel(days, singular: "day", plural: "days")).tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-delete old recordings")
                            .font(.subheadline)
                        Text("Removes both audio files and their transcriptions from history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { autoDeleteEnabled },
                        set: { newValue in
                            if newValue {
                                requestAutoDelete(days: retentionDays)
                            } else {
                                autoDeleteEnabled = false
                                AppPreferences.shared.autoDeleteRecordingsEnabled = false
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                    .labelsHidden()
                    .help("Automatically delete recordings and their transcriptions older than the selected number of days")
                }
            }
        }
        .onAppear {
            refreshDiskUsage()
        }
        .alert("Delete Old Recordings?", isPresented: $showConfirmation) {
            Button("Delete", role: .destructive) {
                confirmAutoDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(countLabel(pendingCount, singular: "recording", plural: "recordings")) with \(pendingCount == 1 ? "its transcription" : "their transcriptions") starting from \(formattedDate(pendingOldestDate)) will be deleted.")
        }
    }

    private func requestAutoDelete(days: Int) {
        Task { @MainActor in
            let result: (count: Int, oldestDate: Date?) = (try? await RecordingStore.shared.recordingsOlderThan(days: days)) ?? (count: 0, oldestDate: nil)
            if result.count > 0 {
                pendingDays = days
                pendingCount = result.count
                pendingOldestDate = result.oldestDate
                showConfirmation = true
            } else {
                applyAutoDelete(days: days)
            }
        }
    }

    private func confirmAutoDelete() {
        applyAutoDelete(days: pendingDays)
    }

    private func applyAutoDelete(days: Int) {
        retentionDays = days
        autoDeleteEnabled = true
        AppPreferences.shared.autoDeleteRecordingsAfterDays = days
        AppPreferences.shared.autoDeleteRecordingsEnabled = true
        Task { @MainActor in
            try? await RecordingStore.shared.deleteRecordings(olderThanDays: days)
            refreshDiskUsage()
        }
    }

    private func refreshDiskUsage() {
        Task.detached {
            let usage = RecordingStore.recordingsDiskUsage()
            await MainActor.run {
                diskUsage = usage
            }
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// The verify control every model row shares: the button, a spinner while the
/// file is hashed, and the sentence the check produced.
struct ModelVerificationView: View {
    let path: String
    let pinnedSHA256: String?
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if viewModel.checkingPath == path {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Checking…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("Verify") {
                    viewModel.verifyModel(at: URL(fileURLWithPath: path), pinnedSHA256: pinnedSHA256)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(pinnedSHA256 == nil
                      ? "Read this file's sha256 — its publisher reports no checksum, so nothing is compared"
                      : "Compare this file against the sha256 its publisher reports")
            }

            if let summary = viewModel.checkSummaries[path] {
                Text(summary)
                    .font(.caption2)
                    .foregroundColor(viewModel.checkProblems.contains(path) ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One speech model file that is on disk right now: a catalogue row or a file
/// someone put there by hand, with the model in use marked.
struct InstalledWhisperModelView: View {
    let model: SettingsViewModel.InstalledWhisperModel
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if model.isSelected {
                        Label("In use", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                    if model.name == WhisperModelManager.defaultModelName {
                        Text("shipped with the app")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help("This is the model inside the app bundle, copied into the models directory on first run")
                    } else if model.catalogueName == nil {
                        Text("not in the catalogue")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help("This file was not downloaded from the list above, so no publisher checksum is known for it")
                    }
                }

                Text("\(model.sizeDescription) on disk")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ModelVerificationView(path: model.url.path,
                                      pinnedSHA256: model.pinnedSHA256,
                                      viewModel: viewModel)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if !model.isSelected {
                    Button("Use") {
                        viewModel.selectModel(model.url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Remove") {
                    viewModel.removeInstalledModel(model)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete this file and free \(model.sizeDescription)")
            }
        }
        .padding(12)
        .background(model.isSelected ? Color(.controlBackgroundColor).opacity(0.7)
                                     : Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct ModelDownloadItemView: View {
    @Binding var model: SettingsDownloadableModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""
    
    var isSelected: Bool {
        if let selectedURL = viewModel.selectedModelURL {
            let filename = model.filename
            return selectedURL.lastPathComponent == filename
        }
        return false
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let pageURL = model.huggingFacePageURL,
                       let owner = huggingFaceOwner(fromPageURL: pageURL) {
                        Link(owner, destination: pageURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("View on Hugging Face")
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if model.isDownloaded {
                    Text("Downloaded — \(model.sizeString) on disk")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 6)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        if isSelected {
                            Label("In use", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Button(action: {
                                let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(model.filename).path
                                viewModel.selectModel(URL(fileURLWithPath: modelPath))
                            }) {
                                Text("Select")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Remove") {
                            viewModel.removeDownloadedModel(named: model.filename)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Delete this model and free \(model.sizeString)")
                    }

                    // G-06: the file is on disk — this says whether it is the
                    // file the publisher signed.
                    ModelVerificationView(
                        path: WhisperModelManager.shared.modelsDirectory.appendingPathComponent(model.filename).path,
                        pinnedSHA256: model.sha256,
                        viewModel: viewModel)
                }
            } else {
                HStack(spacing: 8) {
                    Text(model.sizeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        Task {
                            do {
                                try await viewModel.downloadModel(model)
                            } catch is CancellationError {
                                // Don't show error for manual cancellation
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isDownloading)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color(.controlBackgroundColor).opacity(0.7) : Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded && !isSelected {
                let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(model.filename).path
                viewModel.selectModel(URL(fileURLWithPath: modelPath))
            }
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

