import AppKit
import XCTest
@testable import OpenSuperWhisper

/// The delivery mechanism: which one carries the transcript, and what that costs.
///
/// The captain dictates into a native macOS terminal, where the text arrives
/// whole, and into his Parallels guest, where it did not. `TextDelivery` answers
/// the two with two mechanisms. A design judgment, not an observation, decides
/// that split — what a guest received cannot be observed from this side at all —
/// so these cases pin the choice and everything it does on this side of the
/// boundary: the mechanism selected for a given application and preference, the
/// ⌘V pair that goes out, the state of the pasteboard while the paste is made,
/// and the previous contents coming back afterwards. Whether the guest then pastes
/// the transcript is not claimed here and cannot be tested in this suite.
///
/// Every case here uses a pasteboard of its own, named with a fresh UUID. The
/// general pasteboard is one system-wide object shared with every other process
/// on the machine, so a case that asserted a restore through it would race
/// whatever else is running — `StorageAndLanguageSettingsTests` already pins the
/// restore-on-a-changeCount contract, and these cases pin the delivery path that
/// uses it.
@MainActor
final class TextDeliveryTests: XCTestCase {

    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("osw-delivery-test-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    /// The transcript the captain would dictate: longer than one chunk, and
    /// carrying the Polish diacritics a guest's own layout cannot rebuild.
    private static let transcript = "Zażółć gęślą jaźń, ówdzie łan — 中文 ok"

    /// The clipboard the user already had when the dictation happened.
    private static let usersClipboard = "something the captain copied before dictating"

    private func seedClipboard(_ contents: String) {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(contents, forType: .string)
    }

    private func clipboardContents() -> String? {
        pasteboard.string(forType: .string)
    }

    /// Runs the run loop until the clipboard holds `contents`, or the timeout
    /// passes, and answers what it holds then. The restore is scheduled on the
    /// main queue by `ClipboardUtil`, so a test that slept instead of running
    /// the loop would wait for something that cannot happen.
    private func waitForClipboard(_ contents: String, timeout: TimeInterval = 6) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if clipboardContents() == contents { return contents }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return clipboardContents()
    }

    // MARK: - The mechanism the target calls for

    /// The captain's case: an application that forwards input to a guest is
    /// delivered through the clipboard, because nothing about what such a target
    /// does with forwarded events can be observed from here, while the clipboard
    /// carries the text itself.
    func testAVirtualMachineTargetIsDeliveredThroughTheClipboard() {
        seedClipboard(Self.usersClipboard)
        var posted: [CGEvent] = []

        let result = TextDelivery.deliver(
            Self.transcript,
            trusted: true,
            preference: .automatic,
            frontmostBundleIdentifier: "com.parallels.desktop.console",
            pasteboard: pasteboard,
            post: { posted.append($0) }
        )

        XCTAssertEqual(result.mechanism, .clipboardPaste)
        XCTAssertTrue(result.injected)
        XCTAssertEqual(result.deliveredCharacters, Self.transcript.count)
        // The ⌘V pair, and nothing else: the text is not spelled out in key
        // codes, so there is nothing for a guest to rebuild wrong.
        XCTAssertEqual(posted.map(\.type), [.keyDown, .keyUp])
        for event in posted {
            XCTAssertTrue(event.flags.contains(.maskCommand), "the paste is ⌘V")
        }
        XCTAssertEqual(clipboardContents(), Self.transcript,
                       "the transcript has to be on the clipboard for the paste to carry it")
        // Drained so the scheduled restore has run before the pasteboard is
        // released; the restore itself is asserted by the case below.
        XCTAssertEqual(waitForClipboard(Self.usersClipboard), Self.usersClipboard)
    }

    /// …and the clipboard promise, kept: the contents the captain already had
    /// come back once the target has had its chance to paste.
    func testThePreviousClipboardContentsComeBackAfterAPasteDelivery() {
        seedClipboard(Self.usersClipboard)

        TextDelivery.deliver(
            Self.transcript,
            trusted: true,
            preference: .clipboardPaste,
            frontmostBundleIdentifier: "com.apple.Terminal",
            pasteboard: pasteboard,
            post: { _ in }
        )

        XCTAssertEqual(clipboardContents(), Self.transcript,
                       "the transcript is on the clipboard while the paste is being made")
        XCTAssertEqual(
            waitForClipboard(Self.usersClipboard), Self.usersClipboard,
            "the clipboard the user had must be restored after the paste"
        )
    }

    /// A native macOS target keeps the path this fork has always used, and its
    /// clipboard is never written.
    func testANativeTargetIsDeliveredByKeystrokesWithoutTouchingTheClipboard() {
        seedClipboard(Self.usersClipboard)
        let changeCountBefore = pasteboard.changeCount
        var posted: [CGEvent] = []

        let result = TextDelivery.deliver(
            Self.transcript,
            trusted: true,
            preference: .automatic,
            frontmostBundleIdentifier: "com.apple.Terminal",
            pasteboard: pasteboard,
            post: { posted.append($0) }
        )

        XCTAssertEqual(result.mechanism, .keystrokes)
        XCTAssertTrue(result.injected)
        XCTAssertEqual(result.deliveredCharacters, Self.transcript.count)
        XCTAssertEqual(result.eventsPosted, posted.count)
        XCTAssertGreaterThan(result.eventsPosted, 2, "the text is spelled out, not pasted")
        XCTAssertFalse(
            posted.contains { $0.flags.contains(.maskCommand) },
            "no ⌘V on the keystroke path"
        )
        XCTAssertEqual(pasteboard.changeCount, changeCountBefore, "the clipboard is not touched")
        XCTAssertEqual(clipboardContents(), Self.usersClipboard)
    }

    /// The preference is the user's override, and it wins over what the
    /// application in front is — in both directions.
    func testThePreferenceOverridesTheApplicationInFront() {
        XCTAssertEqual(
            TextDelivery.mechanism(preference: .keystrokes,
                                   frontmostBundleIdentifier: "com.parallels.desktop.console"),
            .keystrokes
        )
        XCTAssertEqual(
            TextDelivery.mechanism(preference: .clipboardPaste,
                                   frontmostBundleIdentifier: "com.apple.Terminal"),
            .clipboardPaste
        )
        // No application in front is not a virtual machine: the keystroke path
        // is the one that cannot be wrong about the target.
        XCTAssertEqual(
            TextDelivery.mechanism(preference: .automatic, frontmostBundleIdentifier: nil),
            .keystrokes
        )
    }

    // MARK: - Giving up safely

    /// An interrupted delivery writes nothing at all: the check runs before the
    /// clipboard is touched, so a delivery that stops itself leaves the user's
    /// clipboard as it found it rather than carrying the transcript until the
    /// restore delay.
    func testAStoppedDeliveryNeverWritesTheClipboard() {
        seedClipboard(Self.usersClipboard)
        var posted: [CGEvent] = []
        let watch = KeyboardSimulator.DeliveryWatch { _ in .focusChanged }

        let result = TextDelivery.deliver(
            Self.transcript,
            trusted: true,
            preference: .automatic,
            frontmostBundleIdentifier: "com.parallels.desktop.console",
            watch: watch,
            pasteboard: pasteboard,
            post: { posted.append($0) }
        )

        XCTAssertEqual(result.mechanism, .clipboardPaste)
        XCTAssertEqual(result.interruptedBy, .focusChanged)
        XCTAssertFalse(result.injected)
        XCTAssertEqual(result.deliveredCharacters, 0)
        XCTAssertTrue(posted.isEmpty, "nothing may go out once the target changed")
        XCTAssertEqual(clipboardContents(), Self.usersClipboard)
    }

    /// An empty transcript is nothing to deliver on either path.
    func testAnEmptyTranscriptPostsNothing() {
        let result = TextDelivery.deliver(
            "",
            trusted: true,
            preference: .clipboardPaste,
            frontmostBundleIdentifier: "com.parallels.desktop.console",
            pasteboard: pasteboard,
            post: { _ in }
        )

        XCTAssertFalse(result.injected)
        XCTAssertEqual(result.eventsPosted, 0)
        XCTAssertEqual(result.deliveredCharacters, 0)
    }
}
