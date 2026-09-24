import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Delivers text to the focused application by simulating keyboard events.
///
/// Unlike pasteboard-based injection, this never touches `NSPasteboard`. Each
/// chunk of text is carried by a `CGEvent` via `keyboardSetUnicodeString`, which
/// makes the output Unicode-complete and independent of the active keyboard
/// layout.
enum KeyboardSimulator {

    /// Maximum number of UTF-16 code units carried by a single event.
    static let maxUTF16PerEvent = 20

    /// What one injection attempt observed and did.
    ///
    /// The trust value is read at the moment of injection, not cached: macOS
    /// re-evaluates an app's Accessibility grant while it runs, so a value read
    /// at launch (or at the previous dictation) can be wrong by the time the
    /// keystrokes are posted.
    struct InjectionResult: Equatable {
        /// Live `AXIsProcessTrusted()` observed immediately before posting.
        let trusted: Bool
        /// How many events were handed to `post`.
        let eventsPosted: Int

        /// What ended the delivery before the whole transcript had been posted,
        /// or `nil` when it was posted in full. `eventsPosted` keeps its meaning
        /// either way: how many events were handed to `post`.
        var interruptedBy: DeliveryInterruption?
        /// How many characters of the transcript had been handed to `post` when
        /// the delivery ended — the whole transcript when `interruptedBy` is
        /// `nil`. Counted over the text after CR/CRLF normalisation, and a
        /// grapheme cluster split by the chunking cap counts once per piece.
        var deliveredCharacters: Int = 0

        /// Whether any keystroke was actually handed to the system.
        var injected: Bool { eventsPosted > 0 }
    }

    /// Why a delivery stopped before it had typed the whole transcript.
    enum DeliveryInterruption: Equatable, CustomStringConvertible {
        /// Another application came to the front: every remaining chunk would
        /// have been typed into that one instead of the intended target.
        case focusChanged
        /// The user typed while the transcript was being posted: continuing
        /// would have mixed the two streams character by character.
        case userTyping

        /// The token the one-line dictation record carries.
        var description: String {
            switch self {
            case .focusChanged: return "focus-changed"
            case .userTyping: return "user-typing"
            }
        }
    }

    /// Watches a delivery for the two interferences that make it unsafe to keep
    /// typing, and answers before each pair of events whether it may go out.
    ///
    /// The checks have to be synchronous queries of the login session's own
    /// state, because a delivery is one uninterrupted main-thread turn — a
    /// 1000-character transcript is posted in a fraction of a millisecond: an
    /// `NSEvent` monitor or an event tap is run-loop driven and cannot run its
    /// callback inside that turn, so it could only report a keystroke after the
    /// delivery was already over.
    struct DeliveryWatch {
        private let check: (_ keyDownsPosted: Int) -> DeliveryInterruption?

        /// A watch built from a check of the caller's own — how a test drives an
        /// interference a headless machine must not be made to produce.
        init(interference: @escaping (_ keyDownsPosted: Int) -> DeliveryInterruption?) {
            self.check = interference
        }

        /// Answers whether anything interfered once the delivery had posted
        /// `keyDownsPosted` key-down events; `nil` means "still safe".
        func interference(keyDownsPosted: Int) -> DeliveryInterruption? {
            check(keyDownsPosted)
        }

        /// A watch over the live login session.
        ///
        /// - Focus: the frontmost application is read once, when the watch is
        ///   made — that is the delivery target, because the watch is made as
        ///   the delivery begins — and compared with the frontmost application
        ///   at every checkpoint. A different process ends the delivery before
        ///   the next event goes out, so nothing reaches the application that
        ///   came to the front. A session with no frontmost application (or one
        ///   the probe cannot read) is treated as "unchanged" rather than as
        ///   interference: this check must never stop a delivery on its own
        ///   ignorance.
        /// - Typing: `CGEventSource.counterForEventType` reports how many key
        ///   downs have been seen in the combined session state. That table, in
        ///   CoreGraphics' words, "reflects the combined state of all event
        ///   sources posting to the current user login session", and this
        ///   process is one of them — it creates its events from a
        ///   `combinedSessionState` source — so the delivery's own key downs are
        ///   part of the number and subtracting the ones it posted leaves the
        ///   keystrokes somebody else made. A keystroke that is not part of this
        ///   delivery is interference whether it came from the keyboard or from
        ///   another process typing into the same application.
        ///
        /// Neither probe can misfire on the quiet case: with nothing competing,
        /// the surplus over the delivery's own posts is exactly zero, and a
        /// counter that has not counted this process's posts (or has gone
        /// backwards) makes the surplus negative, which is also silence. The
        /// arithmetic can never stop a delivery over the events that delivery
        /// itself posted; its failure mode is a missed stop, never a stopped
        /// dictation.
        ///
        /// Both probes are injectable for the same reason `trusted` and `post`
        /// are: a headless test must not produce a real interference, so it
        /// drives the readings instead (see `KeyboardSimulatorInterferenceTests`).
        static func live(
            frontmostPID: @escaping () -> pid_t? = {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            },
            keyDownCount: @escaping () -> UInt32 = {
                CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
            }
        ) -> DeliveryWatch {
            let target = frontmostPID()
            let reference = keyDownCount()
            return DeliveryWatch { keyDownsPosted in
                if let target, let frontmost = frontmostPID(), frontmost != target {
                    return .focusChanged
                }
                let seenSinceDeliveryBegan = keyDownCount()
                guard seenSinceDeliveryBegan >= reference else { return nil }
                let keystrokes = Int(seenSinceDeliveryBegan - reference)
                return keystrokes > keyDownsPosted ? .userTyping : nil
            }
        }
    }

    /// The unified-log subsystem and category of the one-line-per-dictation
    /// injection record, readable with
    /// `log stream --predicate 'subsystem == "ru.starmel.OpenSuperWhisper"'`.
    static let logSubsystem = "ru.starmel.OpenSuperWhisper"
    static let logCategory = "keyboard-injection"
    private static let log = Logger(subsystem: logSubsystem, category: logCategory)

    /// Live answer to "may this process post synthetic keystrokes right now?".
    static var isTrustedForInjection: Bool { AXIsProcessTrusted() }

    /// Records exactly one line per dictation. `print` is invisible for an app
    /// launched by LaunchServices (its stdout is `/dev/null`), which is how the
    /// shipped app runs, so the line that explains a dropped dictation goes to
    /// the unified log with `privacy: .public` fields.
    ///
    /// `deliveredCharacters` and `interruptedBy` say what became of the
    /// transcript: how much of it was handed to the system, and what ended the
    /// delivery early when something did.
    static func logDictation(
        trusted: Bool,
        characters: Int,
        injected: Bool,
        eventsPosted: Int,
        deliveredCharacters: Int = 0,
        interruptedBy: DeliveryInterruption? = nil
    ) {
        log.notice("""
            dictation-injection trusted=\(trusted ? 1 : 0, privacy: .public) \
            chars=\(characters, privacy: .public) \
            injected=\(injected ? 1 : 0, privacy: .public) \
            events=\(eventsPosted, privacy: .public) \
            delivered=\(deliveredCharacters, privacy: .public) \
            interrupted=\(interruptedBy?.description ?? "none", privacy: .public)
            """)
    }

    /// Virtual key code for Return.
    static let returnKeyCode: CGKeyCode = 0x24

    /// Virtual key code for Tab.
    static let tabKeyCode: CGKeyCode = 0x30

    /// Types `text` by posting synthetic key events.
    ///
    /// Text is split into chunks of at most `maxUTF16PerEvent` UTF-16 code units
    /// (never splitting a surrogate pair). Each chunk produces a keyDown
    /// followed by a keyUp event carrying the chunk. Control characters are
    /// handled as dedicated key codes: newlines map to Return and tabs to Tab.
    /// Empty input posts nothing.
    ///
    /// With a `watch`, the delivery is checked before every pair of events and
    /// stops cleanly at the first interference instead of typing into the wrong
    /// place: no further event is posted, and the result carries what ended the
    /// delivery and how much of the transcript had gone out. Chunking, the
    /// events themselves and their timing are unaffected — the checks are two
    /// cheap reads of session state, not delays.
    ///
    /// - Parameters:
    ///   - text: The text to type.
    ///   - trusted: Whether this process may post synthetic events. Defaults to
    ///     the live `AXIsProcessTrusted()` answer, which is what production
    ///     uses; injectable so a test can pin the answer instead of depending on
    ///     whether the machine happens to hold the grant.
    ///   - watch: Interference check consulted between chunks, or `nil` to post
    ///     the whole text unchecked. Production passes `.live()`.
    ///   - post: Sink for the generated events. Defaults to posting to the HID
    ///     event tap; tests inject a capture closure.
    /// - Returns: What was observed and posted, and whether the delivery stopped
    ///   early. When `trusted` is false the events are still handed to `post`,
    ///   but macOS discards every event an untrusted process posts, so the text
    ///   did not reach the focused app — the caller must tell the user instead of
    ///   discarding the text silently.
    @discardableResult
    static func typeText(
        _ text: String,
        trusted: Bool = isTrustedForInjection,
        watch: DeliveryWatch? = nil,
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) -> InjectionResult {
        var eventsPosted = 0
        var keyDownsPosted = 0
        var deliveredCharacters = 0
        var interruptedBy: DeliveryInterruption?

        guard !text.isEmpty else {
            return InjectionResult(trusted: trusted, eventsPosted: 0)
        }

        // Normalize CRLF and CR to a single newline so no line break is lost.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var buffer = ""

        func emit(_ events: [CGEvent]) {
            for event in events {
                post(event)
                eventsPosted += 1
                if event.type == .keyDown {
                    // The live watch subtracts these from the session's own
                    // count, so every one of them has to be counted.
                    keyDownsPosted += 1
                }
            }
        }

        /// Asks the watch whether the delivery may continue, and posts one pair
        /// of events (or two, for a control character) when it may.
        ///
        /// - Returns: `false` once the delivery has stopped, so the caller stops
        ///   walking the transcript instead of posting the rest of it.
        func emitUnlessInterrupted(_ events: [CGEvent], characters: Int) -> Bool {
            if interruptedBy == nil, let watch {
                interruptedBy = watch.interference(keyDownsPosted: keyDownsPosted)
            }
            guard interruptedBy == nil else { return false }
            emit(events)
            deliveredCharacters += characters
            return true
        }

        /// Posts the buffered text, in chunks, unless something interfered.
        @discardableResult
        func flushBuffer() -> Bool {
            if interruptedBy != nil { return false }
            guard !buffer.isEmpty else { return true }
            for chunk in chunks(of: buffer, maxUTF16: maxUTF16PerEvent) {
                guard emitUnlessInterrupted(makeUnicodeEvents(for: chunk), characters: chunk.count) else {
                    return false
                }
            }
            buffer = ""
            return true
        }

        characterLoop: for character in normalized {
            switch character {
            case "\n":
                guard flushBuffer() else { break characterLoop }
                guard emitUnlessInterrupted(makeKeyEvents(for: returnKeyCode), characters: 1) else {
                    break characterLoop
                }
            case "\t":
                guard flushBuffer() else { break characterLoop }
                guard emitUnlessInterrupted(makeKeyEvents(for: tabKeyCode), characters: 1) else {
                    break characterLoop
                }
            default:
                buffer.append(character)
            }
        }

        flushBuffer()

        return InjectionResult(
            trusted: trusted,
            eventsPosted: eventsPosted,
            interruptedBy: interruptedBy,
            deliveredCharacters: deliveredCharacters
        )
    }

    /// Splits `text` into chunks of at most `maxUTF16` UTF-16 code units.
    ///
    /// The walk is over UTF-16 code units, packing up to `maxUTF16` units per
    /// chunk. A high surrogate is always kept together with the low surrogate
    /// that follows it, so no returned chunk contains a lone surrogate. A
    /// grapheme cluster longer than the cap may therefore be spread across
    /// chunks, but no code unit is dropped.
    ///
    /// - Returns: An empty array when `text` is empty or `maxUTF16 <= 0`.
    static func chunks(of text: String, maxUTF16: Int = 20) -> [String] {
        guard !text.isEmpty, maxUTF16 > 0 else { return [] }

        let units = Array(text.utf16)
        var result: [String] = []
        var current: [UInt16] = []
        current.reserveCapacity(maxUTF16)

        var index = 0
        while index < units.count {
            let unit = units[index]
            let isHighSurrogate = (0xD800...0xDBFF).contains(unit)
            let hasPairedLow = isHighSurrogate
                && index + 1 < units.count
                && (0xDC00...0xDFFF).contains(units[index + 1])
            let width = hasPairedLow ? 2 : 1

            if !current.isEmpty && current.count + width > maxUTF16 {
                result.append(String(decoding: current, as: UTF16.self))
                current.removeAll(keepingCapacity: true)
            }

            current.append(unit)
            if hasPairedLow {
                current.append(units[index + 1])
            }
            index += width
        }

        if !current.isEmpty {
            result.append(String(decoding: current, as: UTF16.self))
        }
        return result
    }

    /// Builds the keyDown/keyUp pair that carries `chunk` as a Unicode string.
    ///
    /// Returns an empty array if `chunk` is empty or if event creation fails.
    static func makeUnicodeEvents(for chunk: String) -> [CGEvent] {
        guard !chunk.isEmpty else { return [] }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return [] }

        let utf16 = Array(chunk.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return [] }

        // Clear inherited modifier flags so a still-held hotkey cannot turn
        // this chunk into a shortcut (e.g. Command+A) instead of plain text.
        keyDown.flags = []
        keyUp.flags = []

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        return [keyDown, keyUp]
    }

    /// Builds a plain keyDown/keyUp pair for a virtual key code (no Unicode).
    static func makeKeyEvents(for keyCode: CGKeyCode) -> [CGEvent] {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return [] }

        // Clear inherited modifier flags so a still-held hotkey cannot turn
        // Return/Tab into a modified key.
        keyDown.flags = []
        keyUp.flags = []
        return [keyDown, keyUp]
    }
}
