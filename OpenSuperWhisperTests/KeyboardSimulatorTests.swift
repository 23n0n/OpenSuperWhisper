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

    func testShortStringPostsKeyDownThenKeyUpCarryingUnicode() throws {
        var events: [CGEvent] = []
        KeyboardSimulator.typeText("Hé!") { events.append($0) }

        XCTAssertEqual(events.count, 2)
        let keyDown = try XCTUnwrap(events.first)
        let keyUp = try XCTUnwrap(events.last)
        XCTAssertEqual(keyDown.type, .keyDown)
        XCTAssertEqual(keyUp.type, .keyUp)

        XCTAssertEqual(Self.unicodeString(of: keyDown), "Hé!")
        XCTAssertEqual(Self.unicodeString(of: keyUp), "Hé!")
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
