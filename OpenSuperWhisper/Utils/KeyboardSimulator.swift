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

        /// Whether any keystroke was actually handed to the system.
        var injected: Bool { eventsPosted > 0 }
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
    static func logDictation(
        trusted: Bool,
        characters: Int,
        injected: Bool,
        eventsPosted: Int
    ) {
        log.notice("""
            dictation-injection trusted=\(trusted ? 1 : 0, privacy: .public) \
            chars=\(characters, privacy: .public) \
            injected=\(injected ? 1 : 0, privacy: .public) \
            events=\(eventsPosted, privacy: .public)
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
    /// - Parameters:
    ///   - text: The text to type.
    ///   - post: Sink for the generated events. Defaults to posting to the HID
    ///     event tap; tests inject a capture closure.
    /// - Returns: What was observed and posted. When `trusted` is false the
    ///   events are still handed to `post`, but macOS discards every event an
    ///   untrusted process posts, so the text did not reach the focused app —
    ///   the caller must tell the user instead of discarding the text silently.
    @discardableResult
    static func typeText(
        _ text: String,
        post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) -> InjectionResult {
        let trusted = isTrustedForInjection
        var eventsPosted = 0

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
            }
        }

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            for chunk in chunks(of: buffer, maxUTF16: maxUTF16PerEvent) {
                emit(makeUnicodeEvents(for: chunk))
            }
            buffer = ""
        }

        for character in normalized {
            switch character {
            case "\n":
                flushBuffer()
                emit(makeKeyEvents(for: returnKeyCode))
            case "\t":
                flushBuffer()
                emit(makeKeyEvents(for: tabKeyCode))
            default:
                buffer.append(character)
            }
        }

        flushBuffer()

        return InjectionResult(trusted: trusted, eventsPosted: eventsPosted)
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
