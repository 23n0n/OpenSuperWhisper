import Foundation

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    
    var wrappedValue: T {
        get { AppPreferences.defaults.object(forKey: key) as? T ?? defaultValue }
        set { AppPreferences.defaults.set(newValue, forKey: key) }
    }
}

@propertyWrapper
struct OptionalUserDefault<T> {
    let key: String
    
    var wrappedValue: T? {
        get { AppPreferences.defaults.object(forKey: key) as? T }
        set { AppPreferences.defaults.set(newValue, forKey: key) }
    }
}

final class AppPreferences {
    static let shared = AppPreferences()

    /// Where every preference is read from and written to.
    ///
    /// In production this is `UserDefaults.standard` — the app's own domain,
    /// exactly as before. A test process gets a scratch suite of its own
    /// instead, because the standard domain is shared with everything else on
    /// this machine that runs the same bundle id: Xcode runs test classes in
    /// several processes at once, every crew worktree builds
    /// `ru.starmel.OpenSuperWhisper.dev`, and the app the developer is using
    /// holds the same preferences. With one domain between them, a suite's
    /// `translateEnabled` is another suite's state — and a test's tidy-up writes
    /// into the preferences of a running app.
    ///
    /// Two properties make the scratch suite safe to share between the tests of
    /// one process: the name carries the pid, so two processes can never meet,
    /// and the suite is emptied first, so a reused pid cannot inherit values
    /// from an earlier run.
    static let defaults: UserDefaults = makeDefaults()

    private static func makeDefaults() -> UserDefaults {
        guard OpenSuperWhisperApp.isRunningTests else { return .standard }

        let name = "OpenSuperWhisperTests.\(ProcessInfo.processInfo.processIdentifier)"
        guard let scratch = UserDefaults(suiteName: name) else { return .standard }
        scratch.removePersistentDomain(forName: name)
        return scratch
    }

    /// Shape version of the stored preferences. Bump this whenever a stored
    /// value has to be reinterpreted; `migrateOldPreferences()` then runs the
    /// matching migration once per install.
    static let prefsSchemaVersion = 1
    static let prefsSchemaVersionKey = "prefsSchemaVersion"

    private init() {
        migrateOldPreferences()
    }

    /// One-time migrations for installs that already carry preferences.
    ///
    /// Every step converges an existing install onto the current model of the
    /// world and is safe to run again (a fresh install has nothing stored, so
    /// nothing happens at all). Installing a new version over an old one must
    /// leave the user with working dictation, not with a pointer to a file the
    /// app no longer owns.
    private func migrateOldPreferences() {
        let defaults = Self.defaults

        if let oldPath = defaults.string(forKey: "selectedModelPath"),
           defaults.string(forKey: "selectedWhisperModelPath") == nil {
            defaults.set(oldPath, forKey: "selectedWhisperModelPath")
        }

        guard defaults.integer(forKey: Self.prefsSchemaVersionKey) < Self.prefsSchemaVersion else { return }

        // 1. Whisper model paths are app-owned storage or nothing. A path that
        //    points into a git checkout (or anywhere else outside the app's own
        //    folder) is adopted by copying the file in; a path whose file is
        //    gone is dropped, and the app falls back to the model it ships.
        let modelsDirectory = WhisperModelManager.modelsDirectory
        for key in ["selectedWhisperModelPath", "selectedModelPath"] {
            guard let stored = defaults.string(forKey: key) else { continue }
            if let migrated = Self.adoptedModelPath(stored: stored, modelsDirectory: modelsDirectory) {
                defaults.set(migrated, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        // 2. A transform model id this build does not ship is stale (the
        //    pre-built-in-runtime default was an MLX id the app never loaded).
        //    With the external-endpoint override on, an arbitrary id is the
        //    user's business and is left alone.
        if let stored = defaults.string(forKey: "transformModel") {
            if let migrated = Self.migratedTransformModelID(
                stored: stored,
                externalEndpointEnabled: defaults.bool(forKey: "transformUseExternalEndpoint")
            ) {
                defaults.set(migrated, forKey: "transformModel")
            } else {
                defaults.removeObject(forKey: "transformModel")
            }
        }

        defaults.set(Self.prefsSchemaVersion, forKey: Self.prefsSchemaVersionKey)
    }

    /// The transform model id to keep, or `nil` when the stored one should be
    /// dropped.
    ///
    /// Any id the shipped catalogue knows survives. Anything else is only
    /// meaningful to an external endpoint, so it survives exactly when that
    /// override is on; otherwise the preference falls back to the built-in
    /// default model.
    static func migratedTransformModelID(
        stored: String,
        externalEndpointEnabled: Bool
    ) -> String? {
        if externalEndpointEnabled { return stored }
        if TransformModelManager.availableModels.contains(where: { $0.id == stored }) { return stored }
        return nil
    }

    /// The app-owned path for a stored model path, or `nil` when there is
    /// nothing usable to point at.
    ///
    /// A path already inside `modelsDirectory` is kept as is. One outside it is
    /// copied in — once — and the copy is returned. A path whose file does not
    /// exist yields `nil` so the caller drops it.
    static func adoptedModelPath(
        stored: String,
        modelsDirectory: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let storedURL = URL(fileURLWithPath: trimmed).standardizedFileURL
        let directoryPath = modelsDirectory.standardizedFileURL.path
        if storedURL.path == directoryPath || storedURL.path.hasPrefix(directoryPath + "/") {
            return trimmed
        }

        guard fileManager.fileExists(atPath: storedURL.path) else { return nil }

        let destination = modelsDirectory.appendingPathComponent(storedURL.lastPathComponent)
        if !fileManager.fileExists(atPath: destination.path) {
            do {
                try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: storedURL, to: destination)
                print("[AppPreferences] adopted \(storedURL.path) into app storage")
            } catch {
                print("[AppPreferences] could not adopt \(storedURL.path): \(error)")
                return nil
            }
        }
        return destination.path
    }
    
    // Engine settings
    @UserDefault(key: "selectedEngine", defaultValue: "whisper")
    var selectedEngine: String
    
    // Model settings
    var selectedModelPath: String? {
        get {
            if selectedEngine == "whisper" {
                return selectedWhisperModelPath
            }
            return nil
        }
        set {
            if selectedEngine == "whisper" {
                selectedWhisperModelPath = newValue
            }
        }
    }
    
    @OptionalUserDefault(key: "selectedWhisperModelPath")
    var selectedWhisperModelPath: String?
    
    @UserDefault(key: "fluidAudioModelVersion", defaultValue: "v3")
    var fluidAudioModelVersion: String
    
    
    @UserDefault(key: "whisperLanguage", defaultValue: "en")
    var whisperLanguage: String
    
    // Transcription settings
    @UserDefault(key: "suppressBlankAudio", defaultValue: true)
    var suppressBlankAudio: Bool
    
    @UserDefault(key: "showTimestamps", defaultValue: false)
    var showTimestamps: Bool
    
    @UserDefault(key: "temperature", defaultValue: 0.0)
    var temperature: Double
    
    @UserDefault(key: "noSpeechThreshold", defaultValue: 0.6)
    var noSpeechThreshold: Double
    
    @UserDefault(key: "initialPrompt", defaultValue: "")
    var initialPrompt: String
    
    @UserDefault(key: "useBeamSearch", defaultValue: false)
    var useBeamSearch: Bool
    
    @UserDefault(key: "beamSize", defaultValue: 5)
    var beamSize: Int
    
    @UserDefault(key: "debugMode", defaultValue: false)
    var debugMode: Bool
    
    @UserDefault(key: "playSoundOnRecordStart", defaultValue: false)
    var playSoundOnRecordStart: Bool
    
    @UserDefault(key: "hasCompletedOnboarding", defaultValue: false)
    var hasCompletedOnboarding: Bool
    
    @UserDefault(key: "useAsianAutocorrect", defaultValue: true)
    var useAsianAutocorrect: Bool
    
    @OptionalUserDefault(key: "selectedMicrophoneData")
    var selectedMicrophoneData: Data?
    
    @UserDefault(key: "modifierOnlyHotkey", defaultValue: "none")
    var modifierOnlyHotkey: String
    
    /// Last non-none modifier key, used to restore the user's choice
    /// when switching back to Single Modifier Key mode.
    @UserDefault(key: "lastModifierOnlyHotkey", defaultValue: "leftCommand")
    var lastModifierOnlyHotkey: String
    
    @UserDefault(key: "mouseButtonHotkey", defaultValue: "none")
    var mouseButtonHotkey: String


    @UserDefault(key: "holdToRecord", defaultValue: true)
    var holdToRecord: Bool
    
    @UserDefault(key: "addSpaceAfterSentence", defaultValue: true)
    var addSpaceAfterSentence: Bool

    // Clipboard settings
    @UserDefault(key: "autoCopyToClipboard", defaultValue: false)
    var autoCopyToClipboard: Bool

    @UserDefault(key: "autoPasteTranscription", defaultValue: true)
    var autoPasteTranscription: Bool

    // Translation / tone settings
    @UserDefault(key: "translateEnabled", defaultValue: false)
    var translateEnabled: Bool

    /// Gates every piece of tone text sent to the endpoint. Defaults to `false`
    /// on purpose: a `true` default would start rewriting the dictation of
    /// installs that never enabled anything. There is deliberately no migration
    /// for it — existing installs stay bit-identical until the switch is
    /// flipped.
    @UserDefault(key: "toneEnabled", defaultValue: false)
    var toneEnabled: Bool

    @UserDefault(key: "transformToneMode", defaultValue: ToneMode.neutral.rawValue)
    private var transformToneModeRaw: String

    var transformToneMode: ToneMode {
        get { ToneMode(rawValue: transformToneModeRaw) ?? .neutral }
        set { transformToneModeRaw = newValue.rawValue }
    }

    /// The language the transform writes. Speech already in this language is
    /// pasted untouched and never reaches the model; speech in the other
    /// language is translated into it. Defaults to English — the direction the
    /// app shipped and the one the staged model holds — so an install that
    /// never touches the picker behaves exactly as before. Polish output is
    /// best-effort with that model.
    @UserDefault(key: "transformTargetLanguage", defaultValue: TransformLanguage.english.rawValue)
    private var transformTargetLanguageRaw: String

    var transformTargetLanguage: TransformLanguage {
        get { TransformLanguage(rawValue: transformTargetLanguageRaw) ?? .english }
        set { transformTargetLanguageRaw = newValue.rawValue }
    }

    /// Advanced override. Off by default: the app carries its own llama.cpp
    /// runtime, and the transform runs in this process against app-owned
    /// weights. Turn this on to send the transform to an OpenAI-compatible
    /// endpoint on this machine instead (a self-hosted `llama-server`, say).
    @UserDefault(key: "transformUseExternalEndpoint", defaultValue: false)
    var transformUseExternalEndpoint: Bool

    /// The clean-up pass: the deterministic scrub of filler, stutters and
    /// repeated words, plus the grammar repair folded into the transform call.
    ///
    /// On by default because the deterministic half costs nothing, works
    /// without any model, and only ever removes an artifact — it can never
    /// invent a word. The grammar half rides on a transform call the user has
    /// already enabled, so it adds no call of its own.
    @UserDefault(key: "cleanUpDictation", defaultValue: true)
    var cleanUpEnabled: Bool

    /// Names, jargon and domain terms the user actually says, fed into the
    /// transform prompt so they come back spelled the way the user writes them.
    /// Empty by default and inert while empty: the composed prompt then contains
    /// no reference block at all.
    @UserDefault(key: "transformReference", defaultValue: "")
    var transformReference: String

    @UserDefault(key: "transformEndpoint", defaultValue: "http://127.0.0.1:1919/v1/chat/completions")
    var transformEndpoint: String

    @UserDefault(key: "transformModel", defaultValue: "qwen2.5-1.5b-instruct-q4_k_m")
    var transformModel: String

    @UserDefault(key: "transformTimeout", defaultValue: 8.0)
    var transformTimeout: Double

    @UserDefault(key: "escCancelWithoutConfirmation", defaultValue: false)
    var escCancelWithoutConfirmation: Bool

    @UserDefault(key: "startHiddenInMenuBar", defaultValue: false)
    var startHiddenInMenuBar: Bool

    @UserDefault(key: "autoDeleteRecordingsEnabled", defaultValue: false)
    var autoDeleteRecordingsEnabled: Bool

    @UserDefault(key: "autoDeleteRecordingsAfterDays", defaultValue: 30)
    var autoDeleteRecordingsAfterDays: Int
}
