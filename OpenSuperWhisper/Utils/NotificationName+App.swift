import Foundation

extension Notification.Name {
    /// Posted when a dictation could not be typed because macOS discarded the
    /// synthetic keystrokes: the Accessibility grant is missing. The permission
    /// surface re-checks live on this instead of trusting a cached value.
    static let accessibilityPermissionNeededForInjection = Notification.Name("AccessibilityPermissionNeededForInjection")
    static let hotkeySettingsChanged = Notification.Name("HotkeySettingsChanged")
    static let indicatorWindowDidHide = Notification.Name("IndicatorWindowDidHide")
    static let indicatorWindowWillShow = Notification.Name("IndicatorWindowWillShow")
    static let openSettings = Notification.Name("OpenSettings")
}
