import AVFoundation
import AppKit
import Foundation

enum Permission {
    case microphone
    case accessibility
}

class PermissionsManager: ObservableObject {
    @Published var isMicrophonePermissionGranted = false
    @Published var isAccessibilityPermissionGranted = false
    /// False until the first async TCC check completes; the UI must not show
    /// "permission missing" warnings while the actual status is still unknown,
    /// otherwise they flash on every settings screen open.
    @Published private(set) var hasCompletedInitialCheck = false

    // TCC status queries (AVCaptureDevice.authorizationStatus) are synchronous
    // XPC round-trips to tccd taking 40-100 ms — they must never run on the
    // main thread (traces showed them dropping animation frames every second
    // while the polling timer was active).
    private let checkQueue = DispatchQueue(label: "com.opensuperwhisper.permissions", qos: .utility)
    private var isCheckInFlight = false

    private var permissionCheckTimer: Timer?
    private var windowObservers: [NSObjectProtocol] = []
    /// Polling is paused for the whole indicator session (prepare → hidden):
    /// every millisecond of the main runloop there belongs to the animation.
    private var isIndicatorSessionActive = false

    init() {
        checkAllPermissions()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityPermissionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        setupWindowObservers()
    }

    deinit {
        stopPermissionChecking()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupWindowObservers() {
        let showObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startPermissionChecking()
        }

        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPermissionChecking()
        }

        let hideObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPermissionChecking()
        }

        let indicatorShowObserver = NotificationCenter.default.addObserver(
            forName: .indicatorWindowWillShow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isIndicatorSessionActive = true
        }

        let indicatorHideObserver = NotificationCenter.default.addObserver(
            forName: .indicatorWindowDidHide,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isIndicatorSessionActive = false
        }

        let injectionTrustObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionNeededForInjection,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccessibilityPermission()
        }

        windowObservers = [showObserver, closeObserver, hideObserver,
                           indicatorShowObserver, indicatorHideObserver,
                           injectionTrustObserver]

        if let window = NSApplication.shared.mainWindow, window.isKeyWindow {
            startPermissionChecking()
        }
    }

    private func startPermissionChecking() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isIndicatorSessionActive else { return }
            self.checkAllPermissions()
        }
    }

    private func stopPermissionChecking() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func checkAllPermissions() {
        guard !isCheckInFlight else { return }
        isCheckInFlight = true

        checkQueue.async { [weak self] in
            let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let accessibility = AXIsProcessTrusted()

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCheckInFlight = false
                self.isMicrophonePermissionGranted = microphone
                self.isAccessibilityPermissionGranted = accessibility
                self.hasCompletedInitialCheck = true
            }
        }
    }

    func checkMicrophonePermission() {
        checkQueue.async { [weak self] in
            let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            DispatchQueue.main.async {
                self?.isMicrophonePermissionGranted = granted
            }
        }
    }

    func checkAccessibilityPermission() {
        checkQueue.async { [weak self] in
            let granted = AXIsProcessTrusted()
            DispatchQueue.main.async {
                self?.isAccessibilityPermissionGranted = granted
            }
        }
    }

    /// A dictation was not typed because macOS discarded the keystrokes: the
    /// grant may have been lost while the app was running (rebuilding an
    /// ad-hoc-signed bundle invalidates it). The `.accessibilityPermissionNeededForInjection`
    /// observer re-reads it live instead of trusting a cached value.
    func requestAccessibilityPermissionOrOpenSystemPreferences() {
        if AXIsProcessTrusted() {
            isAccessibilityPermissionGranted = true
        } else {
            openSystemPreferences(for: .accessibility)
        }
    }

    func requestMicrophonePermissionOrOpenSystemPreferences() {

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isMicrophonePermissionGranted = granted
                }
            }
        case .authorized:
            self.isMicrophonePermissionGranted = true
        default:
            openSystemPreferences(for: .microphone)
        }
    }

    @objc private func accessibilityPermissionChanged() {
        checkAccessibilityPermission()
    }

    func openSystemPreferences(for permission: Permission) {
        let urlString: String
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString =
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
