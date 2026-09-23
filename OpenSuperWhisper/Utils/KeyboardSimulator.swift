import CoreGraphics
import Foundation

/// Delivers text to the focused application by simulating keyboard events.
///
/// Unlike pasteboard-based injection, this never touches `NSPasteboard`. Each
/// chunk of text is carried by a `CGEvent` via `keyboardSetUnicodeString`, which
/// makes the output Unicode-complete and independent of the active keyboard
/// layout.
enum KeyboardSimulator {

    /// Maximum number of UTF-16 code units carried by a single event.
    static let maxUTF16PerEvent = 20

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
    static func typeText(_ text: String, post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        guard !text.isEmpty else { return }

        // Normalize CRLF and CR to a single newline so no line break is lost.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var buffer = ""

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            for chunk in chunks(of: buffer, maxUTF16: maxUTF16PerEvent) {
                for event in makeUnicodeEvents(for: chunk) {
                    post(event)
                }
            }
            buffer = ""
        }

        for character in normalized {
            switch character {
            case "\n":
                flushBuffer()
                for event in makeKeyEvents(for: returnKeyCode) {
                    post(event)
                }
            case "\t":
                flushBuffer()
                for event in makeKeyEvents(for: tabKeyCode) {
                    post(event)
                }
            default:
                buffer.append(character)
            }
        }

        flushBuffer()
    }

    /// Splits `text` into chunks of at most `maxUTF16` UTF-16 code units.
    ///
    /// Splitting happens on `Character` boundaries, so a surrogate pair (or any
    /// other multi-scalar grapheme) is never broken across chunks.
    static func chunks(of text: String, maxUTF16: Int = 20) -> [String] {
        guard !text.isEmpty else { return [] }
        guard maxUTF16 > 0 else { return [text] }

        var result: [String] = []
        var current = ""
        var currentUTF16 = 0

        for character in text {
            let characterUTF16 = character.utf16.count
            if currentUTF16 + characterUTF16 > maxUTF16 && !current.isEmpty {
                result.append(current)
                current = ""
                currentUTF16 = 0
            }
            current.append(character)
            currentUTF16 += characterUTF16
        }

        if !current.isEmpty {
            result.append(current)
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
        return [keyDown, keyUp]
    }
}
