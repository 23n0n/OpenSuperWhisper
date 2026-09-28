import AppKit
import Foundation

/// Which of the two delivery mechanisms carried a dictation.
///
/// The mechanism is a property of the *target*, not a preference of the app, so
/// the choice itself lives in `TextDelivery` and this type only names the
/// outcome. The raw value is the token the one-line dictation record carries.
enum DeliveryMechanism: String, CaseIterable, Equatable {
    /// Unicode-carrying synthetic keystrokes, posted to the HID event tap.
    case keystrokes
    /// The transcript is put on the pasteboard and pasted with ⌘V, and the
    /// clipboard is put back the way it was afterwards.
    case clipboardPaste = "clipboard-paste"

    /// The token `KeyboardSimulator.logDictation` prints.
    var logToken: String { rawValue }
}

/// What the user asked delivery to do, which is the only thing that can override
/// the mechanism `TextDelivery` picks for the application being typed into.
enum DeliveryPreference: String, CaseIterable, Equatable {
    /// Keystrokes, except for an application that forwards input to a machine
    /// this one does not control — see `TextDelivery`.
    case automatic
    /// Keystrokes into every target, whatever it is.
    case keystrokes
    /// The clipboard paste into every target, whatever it is.
    case clipboardPaste = "clipboard-paste"

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .keystrokes: return "Keystrokes only"
        case .clipboardPaste: return "Clipboard paste"
        }
    }

    var explanation: String {
        switch self {
        case .automatic:
            return "Keystrokes, and the clipboard for virtual machines and remote desktops"
        case .keystrokes:
            return "Never touches the clipboard"
        case .clipboardPaste:
            return "Pastes through the clipboard, which is restored afterwards"
        }
    }
}

/// Hands a finished transcript to the focused application.
///
/// # Why there are two mechanisms
///
/// There are two kinds of target, and no single mechanism is correct for both.
///
/// A **native macOS target** (TextEdit, Terminal, a browser) receives key events
/// from the window server and inserts the Unicode string the event carries. One
/// keyDown per chunk is exactly one insertion, which is what
/// `KeyboardSimulator.typeText` posts and what this fork has always done. It is
/// independent of the active keyboard layout, it never touches the clipboard,
/// and the captain's own dictation into a native terminal proves it: that text
/// arrives whole.
///
/// A **HID-forwarded target** — a virtual machine, a remote desktop, a VNC
/// viewer — is not reached by the window server's text at all: the host
/// application forwards what it receives on to a machine with its own input
/// stack, and the guest types what *it* makes of it. The text field on a
/// `CGEvent` is an Apple extension a guest never sees; a guest that gets only
/// the key codes rebuilds the characters from them, in a keyboard layout this
/// app does not control and cannot know, and the key code the keystroke path
/// carries its text on is 0 — `a` on any layout. That is the mechanism behind
/// the captain's report: dictating into a native macOS terminal is correct, and
/// the same transcript injected into his Parallels guest came out spliced, with
/// the text duplicated on top of it.
///
/// # What the alternatives cost, and why this is the ladder
///
/// - **Real per-character key codes.** Rejected, and it cannot be made to work
///   in general. A key code names a *physical* key; the character it produces is
///   the guest's business. The machine this was fixed on has `PolishPro` active,
///   where all nine of `ą ć ę ł ń ó ś ź ż` sit behind Option (`0`→ą, `8`→ć,
///   `14`→ę, `37`→ł, and so on) — so `ClipboardUtil.findKeycodeForCharacter`,
///   which walks the layout's base layer, finds no key code for any of them, and
///   an implementation would have to send Option combinations instead. The guest
///   re-translates those under *its* layout: on a US guest layout, Option-plus-key
///   is `å`, `©`, `ß`… The code would be right only for the one pair of layouts
///   it was written against and wrong — silently, character by character — for
///   every other pair. The one thing per-character key codes can be relied on to
///   do is produce *some* text, which is how a wrong answer is delivered as if it
///   were a right one.
/// - **Accessibility insertion** (`kAXSelectedTextAttribute` on the focused
///   element). Not available for this: the guest holds the text, and the host
///   side of a virtual machine window exposes no text element, no selected
///   range, and no insertion point — `FocusUtils` reads AX only to place the
///   indicator, and the writes it would need do not exist in this tree. It could
///   not reach the target that is broken, so it is not a fallback.
/// - **The clipboard paste.** It works for that target, and it is the reason
///   this file exists. A virtual machine shares the clipboard with the guest by
///   default — clipboard sharing is on in both of the guest machines on the Mac
///   this was fixed on (`ClipboardSync/Enabled = 1` in the `.pvm` configs) — the
///   text travels as *text* (not as key codes), and ⌘V is the one command every
///   guest understands. It costs the fork its stated doctrine —
///   "the clipboard is never used" is no longer unconditionally true, and the
///   `Readme` and the Settings copy say so — plus a write-and-restore of the
///   user's clipboard. It also has a failure mode keystrokes do not: if the
///   guest's clipboard sharing is off, the paste does nothing and this app
///   cannot tell, because the only thing it can observe is its own pasteboard,
///   not what the guest did with it. `ClipboardUtil` writes the previous
///   contents back after `ClipboardUtil.clipboardRestoreDelay`, and only if the
///   clipboard is still the transcript it wrote.
/// - **A ladder that prefers keystrokes and falls back at run time.** There is
///   nothing for a fallback to trigger on. Whether a target reconstructs from
///   key codes or takes the Unicode payload is a property of the target, and the
///   only observable on this side is the pasteboard the app wrote itself; a
///   guest that received nothing tells the host nothing about it. So the ladder
///   is decided *before* the events go out, from what the application in front
///   is, and `DeliveryPreference` is the user's override when the guess is
///   wrong.
///
/// # The rule
///
/// Keystrokes by default, because that is the path that reaches every native
/// macOS application and keeps the clipboard untouched. The clipboard paste for
/// an application that forwards input to a machine this one does not control,
/// which is what `hidForwardingHostBundleIDs` names. The list is a heuristic —
/// a bundle identifier is the only thing the app can see about the application
/// in front — and it fails safe in both directions: a host that is not on the
/// list is typed into as before (its transcript still reaches the app, and the
/// dictation record says which mechanism ran), and a host on the list that would
/// have accepted keystrokes gets a paste instead, which delivers the same text
/// with a clipboard write that is restored.
enum TextDelivery {

    /// Applications that pass the input they receive on to a machine this app
    /// cannot see.
    ///
    /// They are here because the Unicode string on a synthetic event does not
    /// survive that hop — the guest rebuilds characters from key codes — so the
    /// clipboard is the only one of the two mechanisms that delivers the captain's
    /// Polish text to them unchanged.
    ///
    /// A bundle identifier that is wrong here costs a momentary clipboard write
    /// and a paste that lands the same text; it does not cost text. So the list
    /// is allowed to be generous. The user's `DeliveryPreference` overrides it
    /// either way.
    static let hidForwardingHostBundleIDs: Set<String> = [
        // Virtual machines.
        "com.parallels.desktop.console",     // Parallels Desktop
        "com.vmware.fusion",                 // VMware Fusion
        "org.virtualbox.app.VirtualBoxVM",   // VirtualBox
        "com.utmapp.UTM",                    // UTM
        "com.apple.qemu",                    // QEMU
        // Remote desktops and screen sharing, which forward key codes the same
        // way. The ones with a Unicode channel of their own (RDP, Citrix) would
        // accept either mechanism; they are not worth a second list.
        "com.apple.ScreenSharing",           // macOS Screen Sharing
        "com.microsoft.rdc.macos",           // Microsoft Remote Desktop
        "com.citrix.receiver.icaviewer.mac", // Citrix Workspace
        "com.p5sys.jump.mac.viewer",         // Jump Desktop
        "com.p5sys.jump.connect",
        "com.edovia.screens4.mac",           // Screens
        "com.edovia.screens.connect",
        "com.realvnc.vncviewer",             // RealVNC
        "com.tigervnc.tigervnc",             // TigerVNC
        "com.teamviewer.TeamViewer",         // TeamViewer
        "com.philandro.anydesk",             // AnyDesk
        "com.parsecgaming.parsec",           // Parsec
        "com.carriez.rustdesk",              // RustDesk
        "com.google.chrome.remote_desktop",  // Chrome Remote Desktop
        "com.nomachine.nxplayer",            // NoMachine
    ]

    /// The bundle identifier of the application a delivery would go to now.
    static func currentFrontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// The mechanism for one delivery, from the preference and the application
    /// in front.
    static func mechanism(
        preference: DeliveryPreference,
        frontmostBundleIdentifier: String?
    ) -> DeliveryMechanism {
        switch preference {
        case .keystrokes:
            return .keystrokes
        case .clipboardPaste:
            return .clipboardPaste
        case .automatic:
            guard let frontmostBundleIdentifier else { return .keystrokes }
            return hidForwardingHostBundleIDs.contains(frontmostBundleIdentifier)
                ? .clipboardPaste
                : .keystrokes
        }
    }

    /// Delivers `text` to the focused application by the mechanism the target
    /// calls for.
    ///
    /// The parameters mirror `KeyboardSimulator.typeText`: `trusted` is the live
    /// Accessibility answer (production uses the default), `watch` is the
    /// interference check, `post` is the event sink a test replaces with a
    /// capture closure. `preference`, `frontmostBundleIdentifier` and
    /// `pasteboard` are the seams the choice is made at, and are read live in
    /// production: the preference from `AppPreferences`, the application from
    /// the frontmost one, the pasteboard from the general one.
    ///
    /// - Returns: What was observed and posted, including which mechanism ran
    ///   and whether the delivery stopped early. A `trusted: false` answer means
    ///   macOS discarded whatever was posted; a `injected: false` answer means
    ///   nothing was posted at all. Neither is a delivery, and the caller owes
    ///   the user the difference — the transcript is in the history either way.
    @discardableResult
    static func deliver(
        _ text: String,
        trusted: Bool = KeyboardSimulator.isTrustedForInjection,
        preference: DeliveryPreference = AppPreferences.shared.deliveryPreference,
        frontmostBundleIdentifier: String? = TextDelivery.currentFrontmostBundleIdentifier(),
        watch: KeyboardSimulator.DeliveryWatch? = nil,
        pasteboard: NSPasteboard = .general,
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) -> KeyboardSimulator.InjectionResult {
        let mechanism = mechanism(preference: preference,
                                  frontmostBundleIdentifier: frontmostBundleIdentifier)

        guard !text.isEmpty else {
            return KeyboardSimulator.InjectionResult(trusted: trusted,
                                                    eventsPosted: 0,
                                                    mechanism: mechanism)
        }

        switch mechanism {
        case .keystrokes:
            return KeyboardSimulator.typeText(text, trusted: trusted, watch: watch, post: post)
        case .clipboardPaste:
            return paste(text, trusted: trusted, watch: watch, pasteboard: pasteboard, post: post)
        }
    }

    /// Puts `text` on the pasteboard, posts ⌘V, and restores the clipboard.
    ///
    /// The interference check runs before anything is written, so a delivery
    /// that stops itself leaves the clipboard exactly as it found it. Everything
    /// after that is `ClipboardUtil.insertText`, which saves the previous
    /// contents, writes the transcript, posts the ⌘V pair through `post`, and
    /// puts the saved contents back after its restore delay — the mechanism the
    /// upstream app used, kept for exactly this case.
    private static func paste(
        _ text: String,
        trusted: Bool,
        watch: KeyboardSimulator.DeliveryWatch?,
        pasteboard: NSPasteboard,
        post: (CGEvent) -> Void
    ) -> KeyboardSimulator.InjectionResult {
        if let watch, let interruption = watch.interference(keyDownsPosted: 0) {
            return KeyboardSimulator.InjectionResult(trusted: trusted,
                                                    eventsPosted: 0,
                                                    interruptedBy: interruption,
                                                    mechanism: .clipboardPaste)
        }

        // Counted rather than assumed: the ⌘V pair is two events when the paste
        // path could build them, and none when it could not — the difference
        // between a delivery and a transcript that went nowhere.
        var eventsPosted = 0
        ClipboardUtil.insertText(text, postEvent: { event in
            eventsPosted += 1
            post(event)
        }, pasteboard: pasteboard)

        return KeyboardSimulator.InjectionResult(
            trusted: trusted,
            eventsPosted: eventsPosted,
            deliveredCharacters: eventsPosted > 0 ? text.count : 0,
            mechanism: .clipboardPaste
        )
    }
}
