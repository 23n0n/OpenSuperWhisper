import Foundation

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    
    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@propertyWrapper
struct OptionalUserDefault<T> {
    let key: String
    
    var wrappedValue: T? {
        get { UserDefaults.standard.object(forKey: key) as? T }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

final class AppPreferences {
    static let shared = AppPreferences()
    private init() {
        migrateOldPreferences()
    }
    
    private func migrateOldPreferences() {
        if let oldPath = UserDefaults.standard.string(forKey: "selectedModelPath"),
           UserDefaults.standard.string(forKey: "selectedWhisperModelPath") == nil {
            UserDefaults.standard.set(oldPath, forKey: "selectedWhisperModelPath")
        }
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
    
    @UserDefault(key: "qwen3Variant", defaultValue: "f32")
    var qwen3Variant: String
    
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
