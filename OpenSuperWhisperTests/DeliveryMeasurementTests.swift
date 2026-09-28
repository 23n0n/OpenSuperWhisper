import AppKit
import CryptoKit
import XCTest
@testable import OpenSuperWhisper

/// F4: the measurements, not the design.
///
/// The delivery mechanism on this branch is superseded and undeployed, pending
/// exactly what these cases produce — numbers about the two things the choice
/// between "paste" and "keystrokes only" rests on. Nothing here asserts which
/// mechanism is right; each case reports raw readings and only fails when the
/// reading is not what it says it measured.
///
/// The clipboard cases run against the machine's **real** pasteboard, because
/// that is the only one whose behaviour is in question. Every one of them
/// captures the clipboard first, writes a backup of it to disk, and puts it back
/// in a `defer`, so the user's clipboard survives a failure in the case itself.
/// Clipboard contents are never printed: the reports carry type identifiers,
/// byte counts and SHA-256 prefixes.
@MainActor
final class DeliveryMeasurementTests: XCTestCase {

    private static let backupURL = URL(fileURLWithPath: "/tmp/osw-clipboard-measurement-backup.plist")

    // MARK: - Clipboard capture, kept out of the log

    private struct ClipboardContents {
        let items: [(type: NSPasteboard.PasteboardType, data: Data)]
        /// Read with the contents, so a report of the *before* state cannot end
        /// up quoting a changeCount taken later.
        let changeCount: Int

        /// Types, byte counts and digests — everything a person needs to see the
        /// measurement, and nothing of what the user actually had copied.
        var description: String {
            let parts = items.map { "\($0.type.rawValue):\(Self.digest($0.data))(\($0.data.count)B)" }
            return "changeCount=\(changeCount) types=\(items.map(\.type.rawValue)) digests=[\(parts.joined(separator: " "))]"
        }

        func text() -> String? {
            items.first { $0.type == .string }.flatMap { String(data: $0.data, encoding: .utf8) }
        }

        static func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16).description
        }
    }

    private func capture(_ pasteboard: NSPasteboard) -> ClipboardContents {
        let items = (pasteboard.types ?? []).compactMap { type in
            pasteboard.data(forType: type).map { (type: type, data: $0) }
        }
        return ClipboardContents(items: items, changeCount: pasteboard.changeCount)
    }

    private func putBack(_ contents: ClipboardContents, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !contents.items.isEmpty else { return }
        pasteboard.declareTypes(contents.items.map(\.type), owner: nil)
        for item in contents.items {
            pasteboard.setData(item.data, forType: item.type)
        }
    }

    /// Captures the real clipboard, writes a copy of it to disk as a backup the
    /// user could restore by hand, and hands the case a restorer that always
    /// runs. The backup is the belt to `defer`'s braces: a crash inside the case
    /// still leaves the clipboard recoverable.
    private func withTheRealClipboardPreserved(_ body: (NSPasteboard, ClipboardContents) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.general
        let before = capture(pasteboard)
        let backup = Dictionary(uniqueKeysWithValues: before.items.map { ($0.type.rawValue, $0.data) })
        try? (backup as NSDictionary).write(to: Self.backupURL)
        TestFixtures.report("[clipboard] backup of the real clipboard written to \(Self.backupURL.path) "
                            + "(\(before.items.count) types)")
        defer { putBack(before, to: pasteboard) }
        try body(pasteboard, before)
    }

    /// Waits until the pasteboard stops holding what was written to it, or the
    /// timeout passes, running the run loop so the scheduled restore can fire.
    private func waitForThePasteboardToMove(on from: Int, _ pasteboard: NSPasteboard, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, pasteboard.changeCount == from {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    // MARK: - Measurement 1: the round trip on the real pasteboard

    /// Does save-and-restore actually put the machine's clipboard back?
    ///
    /// Captures the real clipboard (types, bytes, changeCount), writes a
    /// controlled payload through the app's own paste step, waits out the restore
    /// delay, and compares. Reports both states hashed.
    func testTheRealClipboardComesBackByteIdenticalAfterAPasteRoundTrip() {
        withTheRealClipboardPreserved { pasteboard, before in
            TestFixtures.report("[clipboard] BEFORE          \(before.description)")

            // A controlled payload: nothing the user copied is involved.
            let payload = "OpenSuperWhisper paste measurement \(UUID().uuidString)"
            var posted: [CGEvent] = []
            ClipboardUtil.insertText(payload, postEvent: { posted.append($0) }, pasteboard: pasteboard)

            let during = capture(pasteboard)
            TestFixtures.report("[clipboard] DURING THE PASTE \(during.description)")
            XCTAssertEqual(posted.map(\.type), [.keyDown, .keyUp], "the paste step posts a key pair")
            XCTAssertEqual(during.text(), payload, "the payload is on the clipboard while the paste is being made")

            waitForThePasteboardToMove(on: pasteboard.changeCount,
                                       pasteboard,
                                       timeout: ClipboardUtil.clipboardRestoreDelay + 5)

            let after = capture(pasteboard)
            TestFixtures.report("[clipboard] AFTER RESTORE   \(after.description)")
            XCTAssertEqual(after.items.map(\.type), before.items.map(\.type),
                           "the restore has to bring back the same types")
            XCTAssertEqual(after.items.map(\.data), before.items.map(\.data),
                           "the restore has to bring back the same bytes")
        }
    }

    /// Does a third party's clipboard write survive the restore? (The guard the
    /// restore is documented to have.)
    func testAClipboardTakenDuringThePasteIsNotOverwrittenByTheRestore() {
        withTheRealClipboardPreserved { pasteboard, _ in
            let payload = "OpenSuperWhisper interference measurement \(UUID().uuidString)"
            ClipboardUtil.insertText(payload, postEvent: { _ in }, pasteboard: pasteboard)

            // Somebody else copies while the paste is in flight.
            let theirs = "taken by somebody else while the paste was in flight \(UUID().uuidString)"
            pasteboard.clearContents()
            pasteboard.setString(theirs, forType: .string)
            let theirChangeCount = pasteboard.changeCount

            RunLoop.current.run(until: Date().addingTimeInterval(ClipboardUtil.clipboardRestoreDelay + 0.5))

            TestFixtures.report("[clipboard] after a third party's write: changeCount=\(pasteboard.changeCount) "
                                + "(theirs was \(theirChangeCount)), holds theirs: \(pasteboard.string(forType: .string) == theirs)")
            XCTAssertEqual(pasteboard.string(forType: .string), theirs,
                           "a clipboard write by somebody else must never be overwritten")
        }
    }

    // MARK: - Measurement 2: what the process dying between copy and restore leaves

    /// The failure case of the round trip: the process is gone before the restore
    /// runs, so nothing is scheduled to remove the transcription.
    ///
    /// The child runs the app's **own** `ClipboardUtil.insertText` — the source
    /// file is compiled into it, not re-implemented — and then kills itself
    /// before the 1.5 s restore can fire, which is what a crash or a quit inside
    /// that window amounts to. The case reads what the machine's clipboard holds
    /// afterwards and then puts the user's clipboard back.
    func testAProcessThatDiesBetweenCopyAndRestoreLeavesTheTranscriptionOnTheClipboard() throws {
        let helper = try Self.buildDeathHelper()

        withTheRealClipboardPreserved { pasteboard, before in
            let payload = "OpenSuperWhisper death measurement \(UUID().uuidString)"
            let child = Process()
            child.executableURL = helper
            child.arguments = [payload]
            let pipe = Pipe()
            child.standardOutput = pipe
            try? child.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()

            TestFixtures.report("[clipboard] the child ran the app's own insertText and died: exit status "
                                + "\(child.terminationStatus) (9 = SIGKILL), it reported: "
                                + String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))

            let after = capture(pasteboard)
            TestFixtures.report("[clipboard] AFTER THE DEATH   \(after.description)")
            TestFixtures.report("[clipboard] BEFORE THE DEATH  \(before.description)")

            XCTAssertEqual(after.text(), payload,
                           "with the process gone there is nothing to restore, so the transcription stays")
            XCTAssertNotEqual(after.items.map(\.data), before.items.map(\.data),
                              "…and the user's own clipboard contents are gone")
        }
    }

    /// Compiles the death helper from the app's own `ClipboardUtil.swift` plus a
    /// three-line main, into the test's temporary directory.
    ///
    /// - Throws: `XCTSkip` when the Swift compiler is not reachable, because a
    ///   missing toolchain is not a measurement of the clipboard.
    private static func buildDeathHelper() throws -> URL {
        let repo = URL(fileURLWithPath: #filePath)          // …/OpenSuperWhisperTests/DeliveryMeasurementTests.swift
            .deletingLastPathComponent()                    // …/OpenSuperWhisperTests
            .deletingLastPathComponent()                    // repo root
        let source = repo.appendingPathComponent("OpenSuperWhisper/Utils/ClipboardUtil.swift")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("ClipboardUtil.swift not found at \(source.path)")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-clipboard-death-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let main = """
        import Cocoa

        // The app's own ClipboardUtil is compiled in beside this file: the child
        // copies exactly what the app copies, and then dies before the restore
        // its own code scheduled can run.
        let text = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "probe"
        ClipboardUtil.insertText(text, postEvent: { _ in })
        let pasteboard = NSPasteboard.general
        print("child wrote the clipboard, holds the text: \\(pasteboard.string(forType: .string) == text), "
              + "changeCount=\\(pasteboard.changeCount)")
        fflush(stdout)
        kill(getpid(), SIGKILL)
        """
        let mainURL = directory.appendingPathComponent("main.swift")
        try main.write(to: mainURL, atomically: true, encoding: .utf8)
        let binary = directory.appendingPathComponent("clipboard-death")

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-O", source.path, mainURL.path, "-o", binary.path]
        let errors = Pipe()
        compiler.standardError = errors
        try compiler.run()
        let errorOutput = errors.fileHandleForReading.readDataToEndOfFile()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            throw XCTSkip("could not build the death helper: "
                          + String(decoding: errorOutput, as: UTF8.self).suffix(400))
        }
        return binary
    }

    // MARK: - Measurement 3: what is readable about the application being typed into

    /// Everything this process can actually see about the application a delivery
    /// would go to, and what a family filter would match on this machine.
    ///
    /// Reports the frontmost application three ways (what the app itself reads,
    /// `bundleIdentifier`, localized name, pid), every running application's
    /// bundle identifier, which of them the branch's current exact list matches,
    /// which a naive vendor-prefix family filter would match, and which browsers
    /// or remote-session hosts are running that such a filter could confuse.
    func testWhatIsReadableAboutTheApplicationADeliveryWouldGoTo() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        TestFixtures.report(
            "[target] frontmost: bundleIdentifier=\(frontmost?.bundleIdentifier ?? "nil") "
            + "localizedName=\(frontmost?.localizedName ?? "nil") "
            + "pid=\(frontmost?.processIdentifier ?? -1) active=\(frontmost?.isActive ?? false) "
            + "policy=\(frontmost.map { String(describing: $0.activationPolicy) } ?? "nil")"
        )
        TestFixtures.report("[target] what the app's own reader returns: "
                            + (TextDelivery.currentFrontmostBundleIdentifier() ?? "nil"))

        let running = NSWorkspace.shared.runningApplications
        let identifiers = running.compactMap(\.bundleIdentifier).sorted()
        TestFixtures.report("[target] \(running.count) running applications, bundle identifiers: \(identifiers)")

        let exact = identifiers.filter { TextDelivery.hidForwardingHostBundleIDs.contains($0) }
        TestFixtures.report("[target] matched by the branch's current exact list: \(exact)")

        let naiveFamilies = ["com.citrix.", "com.parallels.", "com.vmware.fusion", "org.virtualbox.app.",
                             "com.utmapp.", "com.apple.qemu", "com.apple.ScreenSharing", "com.microsoft.rdc",
                             "com.p5sys.jump", "com.edovia.screens", "com.realvnc.", "com.tigervnc.",
                             "com.teamviewer.", "com.philandro.anydesk", "com.parsecgaming.",
                             "com.carriez.rustdesk", "com.google.chrome.remote_desktop", "com.nomachine."]
        let byFamily = identifiers.filter { id in naiveFamilies.contains { id.hasPrefix($0) } }
        TestFixtures.report("[target] matched by a naive vendor-prefix family filter: \(byFamily)")

        // The Citrix family specifically: the client ships many bundles, and which
        // one is in front during a session is the whole question.
        let citrix = identifiers.filter { $0.hasPrefix("com.citrix.") }
        TestFixtures.report("[target] the Citrix bundles visible to this process: \(citrix)")

        // What a family filter could confuse: browsers (they host remote sessions
        // in a tab) and anything with a remote-session word in its identifier.
        let confusable = identifiers.filter { id in
            let lowered = id.lowercased()
            return lowered.contains("chrome") || lowered.contains("safari") || lowered.contains("firefox")
                || lowered.contains("edge") || lowered.contains("browser")
                || lowered.contains("remote") || lowered.contains("vnc") || lowered.contains("rdp")
                || lowered.contains("desktop") || lowered.contains("screen")
        }
        TestFixtures.report("[target] identifiers a naive filter could confuse with a client: \(confusable)")

        // The reading a delivery would act on is only useful if it is not nil and
        // not this test process itself.
        XCTAssertNotNil(frontmost, "the frontmost application has to be readable at delivery time")
        XCTAssertFalse(
            identifiers.isEmpty,
            "no running application reported a bundle identifier, so no target-class rule could work here"
        )
    }
}
