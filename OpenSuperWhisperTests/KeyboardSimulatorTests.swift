import XCTest
import AppKit
@testable import OpenSuperWhisper

final class KeyboardSimulatorTests: XCTestCase {

    // MARK: - Chunking

    func testChunksReconstituteLongASCIITextInOrder() {
        let text = String(repeating: "abcdefghij", count: 7) // 70 ASCII characters
        let chunks = KeyboardSimulator.chunks(of: text)

        XCTAssertEqual(chunks.joined(), text)
        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.utf16.count, 20, "chunk exceeds 20 UTF-16 units: \(chunk)")
        }
        // 70 units / 20 per chunk => 4 chunks.
        XCTAssertEqual(chunks.count, 4)
    }

    func testChunksDoNotSplitSurrogatePairs() {
        // Emoji are surrogate pairs; combining diacritics add extra code points.
        let text = "a😀bé😀café🇵🇱d😀é"
        let chunks = KeyboardSimulator.chunks(of: text)

        XCTAssertEqual(chunks.joined(), text)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.utf16.count, 20, "chunk exceeds 20 UTF-16 units")
            XCTAssertTrue(Self.decodesCleanly(chunk), "chunk's UTF-16 does not decode cleanly: \(chunk)")
        }
    }

    func testChunksNeverExceedCapForGraphemeLongerThanCap() {
        // A single grapheme cluster: "e" plus 30 combining acutes == 31 UTF-16 units.
        let text = "e" + String(repeating: "\u{0301}", count: 30)
        XCTAssertEqual(text.count, 1, "expected a single grapheme cluster")
        XCTAssertEqual(text.utf16.count, 31)

        let cap = 20
        let chunks = KeyboardSimulator.chunks(of: text, maxUTF16: cap)

        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.utf16.count, cap, "chunk exceeds cap: \(chunk)")
            XCTAssertTrue(Self.decodesCleanly(chunk), "chunk's UTF-16 does not decode cleanly")
        }
        // No code unit may be lost even though the grapheme was split.
        XCTAssertEqual(chunks.flatMap { Array($0.utf16) }, Array(text.utf16))
    }

    func testChunksWithNonPositiveMaximumReturnEmpty() {
        XCTAssertTrue(KeyboardSimulator.chunks(of: "abc", maxUTF16: 0).isEmpty)
        XCTAssertTrue(KeyboardSimulator.chunks(of: "abc", maxUTF16: -5).isEmpty)
        XCTAssertTrue(KeyboardSimulator.chunks(of: "😀", maxUTF16: 0).isEmpty)
    }

    func testChunksWithTinyMaximumKeepCharactersIntact() {
        let text = "ab😀cd"
        let chunks = KeyboardSimulator.chunks(of: text, maxUTF16: 2)
        XCTAssertEqual(chunks, ["ab", "😀", "cd"])
        XCTAssertEqual(chunks.joined(), text)
    }

    // MARK: - Event production

    /// The chunk travels on the keyDown and on nothing else.
    ///
    /// This used to assert the opposite — that both events carried the chunk —
    /// which is the duplication hazard this pair was carrying: a target that
    /// inserts the text every event carries receives the chunk twice. What the
    /// keyUp must be is a release of the same key that says "no text here", and
    /// the payload has to be *cleared* to say that: an event whose Unicode string
    /// was never set reads back as whatever its key code produces, and key code 0
    /// is `a`.
    func testShortStringPostsKeyDownCarryingUnicodeAndAPayloadFreeKeyUp() throws {
        var events: [CGEvent] = []
        KeyboardSimulator.typeText("Hé!") { events.append($0) }

        XCTAssertEqual(events.count, 2)
        let keyDown = try XCTUnwrap(events.first)
        let keyUp = try XCTUnwrap(events.last)
        XCTAssertEqual(keyDown.type, .keyDown)
        XCTAssertEqual(keyUp.type, .keyUp)

        XCTAssertEqual(Self.unicodeString(of: keyDown), "Hé!")
        XCTAssertNil(
            Self.unicodeString(of: keyUp),
            "the keyUp must carry no text: a target that inserts what each event carries would "
            + "otherwise insert the chunk a second time"
        )
        // …and it stays the release of the key the chunk was pressed with, so a
        // target tracking key state sees a press and a release, not a stuck key.
        XCTAssertEqual(keyUp.getIntegerValueField(.keyboardEventKeycode),
                       keyDown.getIntegerValueField(.keyboardEventKeycode))
    }

    func testLongStringPostsTwoEventsPerChunkInOrder() throws {
        let text = String(repeating: "x", count: 45) // 3 chunks of 20/20/5
        var events: [CGEvent] = []
        KeyboardSimulator.typeText(text) { events.append($0) }

        XCTAssertEqual(events.count, 6)
        for index in stride(from: 0, to: events.count, by: 2) {
            XCTAssertEqual(events[index].type, .keyDown)
            XCTAssertEqual(events[index + 1].type, .keyUp)
        }
        let typed = events.enumerated()
            .filter { $0.offset % 2 == 0 }
            .compactMap { Self.unicodeString(of: $0.element) }
            .joined()
        XCTAssertEqual(typed, text)
    }

    // MARK: - Control characters

    func testNewlineMapsToReturnKeyCode() throws {
        var events: [CGEvent] = []
        KeyboardSimulator.typeText("\n") { events.append($0) }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].type, .keyDown)
        XCTAssertEqual(events[1].type, .keyUp)
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode),
                           Int64(KeyboardSimulator.returnKeyCode))
        }
    }

    func testTabMapsToTabKeyCode() throws {
        var events: [CGEvent] = []
        KeyboardSimulator.typeText("\t") { events.append($0) }

        XCTAssertEqual(events.count, 2)
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode),
                           Int64(KeyboardSimulator.tabKeyCode))
        }
    }

    /// Return and Tab travel as key codes with no text on them, press and
    /// release alike. An event whose Unicode string is merely left unset still
    /// reads back as the character its key code produces, so a target that
    /// inserts the text each event carries would insert the newline twice — once
    /// for the press and once for the release.
    func testReturnAndTabEventsCarryNoUnicodeText() {
        for control in ["\n", "\t"] {
            var events: [CGEvent] = []
            KeyboardSimulator.typeText(control) { events.append($0) }

            XCTAssertEqual(events.count, 2)
            for event in events {
                XCTAssertNil(
                    Self.unicodeString(of: event),
                    "\(control.debugDescription) has to travel as a key code alone, not as text"
                )
            }
        }

        // …and the key codes are still the ones that make the characters, in
        // press/release order.
        var events: [CGEvent] = []
        KeyboardSimulator.typeText("\n\t") { events.append($0) }
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) },
                       [Int64(KeyboardSimulator.returnKeyCode),
                        Int64(KeyboardSimulator.returnKeyCode),
                        Int64(KeyboardSimulator.tabKeyCode),
                        Int64(KeyboardSimulator.tabKeyCode)])
    }

    // MARK: - The key code a text event carries

    /// Key code 0 is the `A` key, not "no key".
    ///
    /// A target that rebuilds characters from key codes instead of reading the
    /// Unicode string — a Citrix session above all: its viewer links no
    /// Unicode-payload reader at all — types `a` once per chunk for key code 0,
    /// which is the worst thing a text event can carry. So the key code comes
    /// from the active layout for the chunk's first character, and the events for
    /// a chunk the layout has no key for carry a code no key is defined for.
    func testTextEventsCarryTheLayoutsKeyForTheFirstCharacterAndNeverASilentA() throws {
        var events: [CGEvent] = []
        // Every chunk of this payload starts with a base-layer character: "Z",
        // "ó" (Option+o), "j"… — the common shape of dictated text.
        KeyboardSimulator.typeText("Zażółć gęślą jaźń — 中文測試 Ж їß 😀 ok\n\ttail") { events.append($0) }

        let keyDowns = events.filter { $0.type == .keyDown }
        XCTAssertFalse(keyDowns.isEmpty)

        for keyDown in keyDowns {
            let keyCode = CGKeyCode(keyDown.getIntegerValueField(.keyboardEventKeycode))
            // A Return or Tab event is its own key; the rest carry text.
            if keyCode == KeyboardSimulator.returnKeyCode || keyCode == KeyboardSimulator.tabKeyCode {
                continue
            }
            guard let chunk = Self.unicodeString(of: keyDown), let first = chunk.first else {
                XCTFail("a text event carries no text at all")
                continue
            }
            let layoutKey = ClipboardUtil.findKeycodeForCharacter(first)
            XCTAssertEqual(
                keyCode, layoutKey ?? KeyboardSimulator.unmappedKeyCode,
                "chunk \(String(reflecting: chunk)) is posted with the layout's key for "
                + "\(String(reflecting: first)), or with the unmapped code"
            )
            if keyCode == 0 {
                XCTAssertEqual(
                    first.lowercased(), "a",
                    "key code 0 means the `a` key and may only ride a chunk that starts with `a`; "
                    + "\(String(reflecting: chunk)) starts with \(String(reflecting: first))"
                )
            }
        }
    }

    /// A chunk whose first character the layout has no key for — every Polish
    /// diacritic is an Option combination here, and CJK, Cyrillic and emoji have
    /// no key at all — carries `unmappedKeyCode`, so no target can turn it into a
    /// character the user did not dictate.
    func testAChunkTheLayoutCannotTypeCarriesTheUnmappedKeyCode() {
        XCTAssertEqual(KeyboardSimulator.keyCode(for: "中文測試"), KeyboardSimulator.unmappedKeyCode)
        XCTAssertEqual(KeyboardSimulator.keyCode(for: "Ж їß"), KeyboardSimulator.unmappedKeyCode)
        XCTAssertEqual(KeyboardSimulator.keyCode(for: "😀 ok"), KeyboardSimulator.unmappedKeyCode)
        XCTAssertEqual(KeyboardSimulator.keyCode(for: "ą ć ę ł ń ó ś ź ż"),
                       ClipboardUtil.findKeycodeForCharacter("ą") ?? KeyboardSimulator.unmappedKeyCode)
        XCTAssertEqual(KeyboardSimulator.unmappedKeyCode, 0x7F)
        XCTAssertNotEqual(KeyboardSimulator.unmappedKeyCode, KeyboardSimulator.returnKeyCode)
        XCTAssertNotEqual(KeyboardSimulator.unmappedKeyCode, KeyboardSimulator.tabKeyCode)
    }

    func testCarriageReturnAndCRLFMapToSingleReturn() {
        var crEvents: [CGEvent] = []
        KeyboardSimulator.typeText("\r") { crEvents.append($0) }
        XCTAssertEqual(crEvents.count, 2)

        var crlfEvents: [CGEvent] = []
        KeyboardSimulator.typeText("\r\n") { crlfEvents.append($0) }
        XCTAssertEqual(crlfEvents.count, 2)
        for event in crlfEvents {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode),
                           Int64(KeyboardSimulator.returnKeyCode))
        }
    }

    func testMixedContentSplitsAroundControlCharacter() throws {
        var events: [CGEvent] = []
        KeyboardSimulator.typeText("ab\ncd") { events.append($0) }

        // "ab" keyDown/keyUp, Return keyDown/keyUp, "cd" keyDown/keyUp
        XCTAssertEqual(events.count, 6)
        XCTAssertEqual(Self.unicodeString(of: events[0]), "ab")
        XCTAssertEqual(events[2].getIntegerValueField(.keyboardEventKeycode),
                       Int64(KeyboardSimulator.returnKeyCode))
        XCTAssertEqual(Self.unicodeString(of: events[4]), "cd")
    }

    // MARK: - Empty input

    func testEmptyStringPostsNothing() {
        var events: [CGEvent] = []
        KeyboardSimulator.typeText("") { events.append($0) }
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Clipboard isolation

    func testTypeTextDoesNotTouchPasteboard() {
        let changeCountBefore = NSPasteboard.general.changeCount
        KeyboardSimulator.typeText("clipboard must stay untouched 😀\n") { _ in }
        XCTAssertEqual(NSPasteboard.general.changeCount, changeCountBefore)
    }

    // MARK: - Reported outcome

    /// The outcome is what the one-line dictation log and the user-facing
    /// warning are built from, so it must report the trust state the injection
    /// actually saw and count the events it actually posted.
    func testTypeTextReportsLiveTrustAndPostedEventCount() {
        var events: [CGEvent] = []
        let result = KeyboardSimulator.typeText("Hé!") { events.append($0) }

        XCTAssertEqual(result.eventsPosted, events.count)
        XCTAssertEqual(result.eventsPosted, 2)
        XCTAssertTrue(result.injected)
        XCTAssertEqual(result.trusted, KeyboardSimulator.isTrustedForInjection)
    }

    func testTypeTextReportsNothingPostedForEmptyText() {
        let result = KeyboardSimulator.typeText("") { _ in }

        XCTAssertEqual(result.eventsPosted, 0)
        XCTAssertFalse(result.injected)
    }

    /// The trust answer is injectable, so a test can pin it instead of depending
    /// on whether the host process happens to hold the Accessibility grant.
    func testTypeTextHonoursAnInjectedTrustValue() {
        var events: [CGEvent] = []
        let result = KeyboardSimulator.typeText("pinned", trusted: false) { events.append($0) }

        XCTAssertFalse(result.trusted)
        XCTAssertEqual(result.eventsPosted, events.count)
        XCTAssertEqual(result.eventsPosted, 2)
    }

    // MARK: - Helpers

    /// True when a chunk's UTF-16 round-trips losslessly and contains no
    /// replacement character (which would signal a lone/unpaired surrogate).
    private static func decodesCleanly(_ chunk: String) -> Bool {
        let units = Array(chunk.utf16)
        let decoded = String(decoding: units, as: UTF16.self)
        return Array(decoded.utf16) == units
            && !decoded.unicodeScalars.contains { $0.value == 0xFFFD }
    }

    /// Reads the Unicode string stored on a synthetic keyboard event.
    private static func unicodeString(of event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 64)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count,
                                      actualStringLength: &length,
                                      unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }
}

// MARK: - End-to-end delivery

/// The smallest receiver that can host real key events: it is handed the events
/// the delivery path posts and gives each one to AppKit's key-binding machinery,
/// and every insertion goes through a real `NSTextView` — the characters, the
/// Return and the Tab are inserted by AppKit, not by this class.
///
/// It is a plain `NSView` rather than a subclass of `NSTextView` because
/// `NSTextView.keyDown` routes through its window's input context, and a
/// headless test has no key window; a bare view's `interpretKeyEvents` uses the
/// same standard key bindings (Return resolves to `insertNewline:`, Tab to
/// `insertTab:`).
final class TypingReceiverView: NSView {
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))

    override var acceptsFirstResponder: Bool { true }

    /// Hands one event of the posted stream to the receiver, the way the window
    /// server would after routing it to the focused application.
    func receive(_ event: NSEvent) {
        switch event.type {
        case .keyDown: keyDown(with: event)
        case .keyUp: keyUp(with: event)
        default: break
        }
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func keyUp(with event: NSEvent) {}

    override func insertText(_ string: Any) {
        switch string {
        case let text as String:
            editor.insertText(text, replacementRange: caretAtEnd())
        case let attributed as NSAttributedString:
            editor.insertText(attributed.string, replacementRange: caretAtEnd())
        default:
            break
        }
    }

    override func insertNewline(_ sender: Any?) {
        _ = caretAtEnd()
        editor.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        _ = caretAtEnd()
        editor.insertTab(sender)
    }

    /// Puts the caret after the last character and answers where that is.
    @discardableResult
    private func caretAtEnd() -> NSRange {
        let end = NSRange(location: editor.string.utf16.count, length: 0)
        editor.setSelectedRange(end)
        return end
    }
}

/// A receiver for the class of target whose behaviour cannot be observed from
/// this side — the virtual-machine guest the captain dictates into by way of a
/// host application that forwards its input.
///
/// It is a model, not a capture. It reads the events the delivery path posts the
/// way a HID-forwarding host reads them: it takes the text the event itself
/// carries (`kCGEventKeyboardUnicodeString`, the field `keyboardSetUnicodeString`
/// fills) and inserts it for **every event that carries one, keyUp included**,
/// because what a guest receives from such a host is a stream of insertions, not
/// a stream of key transitions. Nothing here says the captain's target behaves
/// this way — nothing ever recorded what it received — and the case that drives
/// this receiver is written as a guard on the event shape for exactly that
/// reason.
///
/// An event with no text on it is reconstructed from its key code, the way a
/// guest with a keyboard layout of its own does; a keyUp with no text is a
/// release and inserts nothing.
///
/// The difference from `TypingReceiverView` above is what makes this one worth
/// having: that receiver goes through AppKit's key bindings and therefore ignores
/// keyUp exactly as the framework's own text system does, so it could not see a
/// chunk posted twice no matter how the events were built.
final class HidForwardedReceiverView: NSView {
    /// Everything the target ended up with, in the order it inserted it.
    private(set) var inserted = ""

    override var acceptsFirstResponder: Bool { true }

    /// Hands one event of the posted stream to this target.
    func receive(_ event: CGEvent) {
        if let payload = Self.unicodePayload(of: event), !payload.isEmpty {
            inserted += payload
            return
        }
        // No text on the event: a guest inserts from the key code it was given,
        // under its own layout. Only a key *press* inserts; a release does not.
        guard event.type == .keyDown else { return }
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case Int64(KeyboardSimulator.returnKeyCode):
            inserted += "\n"
        case Int64(KeyboardSimulator.tabKeyCode):
            inserted += "\t"
        default:
            // Whatever this key code means in the guest's own layout — the
            // character the delivery never asked for.
            inserted += "«\(event.getIntegerValueField(.keyboardEventKeycode))»"
        }
    }

    /// The text an event carries, or `nil` when it carries none.
    static func unicodePayload(of event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 512)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count,
                                       actualStringLength: &length,
                                       unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }
}

/// The path the captain dictates through every day — the transcript reaches the
/// focused application as synthetic keystrokes, the clipboard untouched — end to
/// end and without naming a keyboard layout.
///
/// `ClipboardUtilPasteIntegrationTests` is gated on layouts a normal machine does
/// not have, so on the machine the app ships to it proves nothing about delivered
/// text. This case reads the input source that is *active* at run time, never
/// switches it, and types a payload the active layout has no keys for, so a
/// delivery path that consulted the layout is caught here on any machine; that is
/// the layout-independence the layout-gated cases above can only check on the
/// machines that have their layout.
///
/// Not covered: the HID event tap and the window server's routing of the posted
/// events to the frontmost application, the one step a headless test must not
/// take. Everything from the posted event onwards is real.
@MainActor
final class KeyboardSimulatorDeliveryTests: XCTestCase {

    /// Multi-chunk and multi-script: longer than
    /// `KeyboardSimulator.maxUTF16PerEvent`, so the text is split, and carrying
    /// characters no single layout produces (CJK, Cyrillic, emoji) plus a
    /// newline and a tab.
    private static let payload = "Zažółć gęślą jaźń — 中文測試 Ж їß 😀 ok\n\ttail"

    /// The payload's single-scalar BMP characters: `findKeycodeForCharacter`
    /// reads one UTF-16 unit, so the emoji and the control characters are left
    /// out of the layout probe rather than fed to it.
    private static let payloadCharacters: [Character] = Array(payload).filter { character in
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.value <= 0xFFFF
        else { return false }
        return !character.isWhitespace && !character.isNewline
    }

    func testTypesTheExactTextThroughTheActiveInputSource() throws {
        // Resolved at run time and never switched: whatever layout this machine
        // has active is the layout the typing happens under.
        let activeSourceID = try XCTUnwrap(
            ClipboardUtil.getCurrentInputSourceID(),
            "a machine in a GUI session always has an active input source"
        )

        let receiver = TypingReceiverView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        var posted: [CGEvent] = []

        // The one step replaced: the app posts each event to the HID event tap
        // for the window server to route to the focused application; here the
        // event goes straight to the receiver.
        let result = KeyboardSimulator.typeText(Self.payload, trusted: true) { event in
            posted.append(event)
            guard let keyEvent = NSEvent(cgEvent: event) else { return }
            receiver.receive(keyEvent)
        }

        XCTAssertTrue(result.injected)
        XCTAssertEqual(result.eventsPosted, posted.count)
        XCTAssertEqual(
            receiver.editor.string, Self.payload,
            "the focused application must receive the transcript character for character"
        )
        // The other half of this path's contract — the clipboard stays untouched
        // — is asserted by `KeyboardSimulatorTests.testTypeTextDoesNotTouchPasteboard`
        // and deliberately not repeated here: the pasteboard is process-wide and
        // the paste cases run in parallel with this one.

        // Layout independence, shown at run time rather than assumed: the
        // payload carries characters the active layout has no key for, so the
        // delivered text above cannot have come from that layout's key codes.
        let untypedByTheLayout = Self.payloadCharacters.filter {
            ClipboardUtil.findKeycodeForCharacter($0) == nil
        }
        XCTAssertFalse(
            untypedByTheLayout.isEmpty,
            "the active input source (\(activeSourceID)) has a key for every payload character, "
            + "so this case would not show that delivery ignores the layout"
        )
        TestFixtures.report(
            "keyboard delivery: active input source \(activeSourceID), \(result.eventsPosted) events, "
            + "payload characters that layout cannot type: "
            + untypedByTheLayout.map(String.init).joined()
        )
    }

    /// The event shape, pinned against the hazard it carried: a target that
    /// inserts the text every event carries must receive each chunk once, not
    /// once per posted event.
    ///
    /// This is a guard, not a reproduction. Nothing ever captured the events the
    /// captain's failing target received, so no claim is made here that his
    /// target inserts on both transitions — what the case pins is that the pair
    /// this app posts does not hand the same text over twice, whatever the target
    /// does with the events. It failed against the old shape, where the chunk
    /// travelled on the keyUp as well as the keyDown: 80 characters received for
    /// a 40-character payload.
    func testATargetThatInsertsOnBothEventsReceivesTheChunkOnce() {
        let receiver = HidForwardedReceiverView()

        let result = KeyboardSimulator.typeText(Self.payload, trusted: true) { receiver.receive($0) }

        XCTAssertTrue(result.injected)
        XCTAssertEqual(
            receiver.inserted, Self.payload,
            "a target that inserts what each event carries has to receive the transcript once; "
            + "it received \(receiver.inserted.count) characters for a \(Self.payload.count)-character payload"
        )
    }
}
