enum TransformLanguage: String, CaseIterable, Identifiable {
    case english
    case polish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .polish: return "Polish"
        }
    }

    /// The transform language for a detector verdict, or `nil` when the
    /// detector has no usable signal.
    init?(verdict: LanguageDetector.Verdict) {
        switch verdict {
        case .english: self = .english
        case .polish: self = .polish
        case .unknown: return nil
        }
    }
}
