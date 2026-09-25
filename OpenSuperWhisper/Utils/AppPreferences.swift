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
    /// `toneEnabled` is another suite's state — and a test's tidy-up writes
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

        // 2. `transformModel` (the id an external endpoint used to be told) is
        //    no longer read by anything, so nothing migrates it: the stale id
        //    stays in the domain exactly as the other removed translation keys
        //    do, and no code path looks at it.
        defaults.set(Self.prefsSchemaVersion, forKey: Self.prefsSchemaVersionKey)
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

    // Transcription settings
    @UserDefault(key: "suppressBlankAudio", defaultValue: true)
    var suppressBlankAudio: Bool
    
    @UserDefault(key: "showTimestamps", defaultValue: false)
    var showTimestamps: Bool

    /// "Long Pauses End the Sentence" — the switch that keeps a pause instead of
    /// dissolving it.
    ///
    /// The name says what the behaviour is, not what the captain first asked
    /// for: the nonsense came from *dissolving* the pause into a 0.1 s breath,
    /// so "ignore pauses" would name the defect. On, a pause of at least
    /// `PauseBoundaryPolicy.restored.sentenceThreshold` between two speech
    /// segments is kept as real silence (up to `maxPause`) and closes the
    /// sentence in the assembled text when the decoder did not close it.
    ///
    /// On by default: the transcript it produces is the one without the defect,
    /// and a default of off would leave an install that never opens Settings
    /// with the fragments the switch exists to remove. Off is upstream's
    /// stitching, byte for byte.
    @UserDefault(key: "longPausesEndSentences", defaultValue: true)
    var longPausesEndSentences: Bool
    
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

    // Tone and clean-up settings
    //
    // The translation feature is gone, and so are the preferences that
    // configured it: `translateEnabled`, `transformTargetLanguage`,
    // `transformEndpoint`, `transformModel`, `transformTimeout`,
    // `transformUseExternalEndpoint` and `whisperLanguage` are no longer read
    // or written anywhere. A domain that still holds them — the captain's own
    // does — simply carries values nothing looks at, which is the honest
    // handling: no migration, because there is nothing to migrate to, and
    // nothing that could resurrect a removed control.

    /// Gates every piece of tone text sent to the model. Defaults to `false`
    /// on purpose: a `true` default would start rewriting the dictation of
    /// installs that never enabled anything. There is deliberately no migration
    /// for it — existing installs stay bit-identical until the switch is
    /// flipped.
    ///
    /// The tone is a same-language rewrite: it changes the register of the
    /// transcript, never its language.
    @UserDefault(key: "toneEnabled", defaultValue: false)
    var toneEnabled: Bool

    @UserDefault(key: "transformToneMode", defaultValue: ToneMode.neutral.rawValue)
    private var transformToneModeRaw: String

    var transformToneMode: ToneMode {
        get { ToneMode(rawValue: transformToneModeRaw) ?? .neutral }
        set { transformToneModeRaw = newValue.rawValue }
    }

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

    @UserDefault(key: "escCancelWithoutConfirmation", defaultValue: false)
    var escCancelWithoutConfirmation: Bool

    @UserDefault(key: "startHiddenInMenuBar", defaultValue: false)
    var startHiddenInMenuBar: Bool

    @UserDefault(key: "autoDeleteRecordingsEnabled", defaultValue: false)
    var autoDeleteRecordingsEnabled: Bool

    @UserDefault(key: "autoDeleteRecordingsAfterDays", defaultValue: 30)
    var autoDeleteRecordingsAfterDays: Int
}
