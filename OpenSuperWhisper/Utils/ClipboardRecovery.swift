import AppKit
import CryptoKit
import Foundation
import os

/// The clipboard a paste delivery displaced, kept on disk for exactly as long as
/// the delivery might die before it puts that clipboard back.
///
/// A paste delivery writes the transcription onto the pasteboard and restores
/// what was there 1.5 s later. That restore is an in-process block, and the
/// measurement in `DeliveryMeasurementTests` shows what happens when the process
/// does not survive the window: the transcription stays on the clipboard and the
/// contents the user had are gone, with nothing scheduled to bring them back.
/// This type closes that hole — it is the only reason the clipboard mechanism is
/// considered acceptable at all — and it is deliberately small:
///
/// * the record is written **before** the pasteboard is mutated, so a crash at
///   any point after that has something to recover from;
/// * it is cleared as soon as the delivery's own restore has run, so the ordinary
///   case leaves nothing behind;
/// * recovery puts the contents back only when the pasteboard is still holding
///   *our* text — checked by digest, not by changeCount, because the pasteboard
///   server resets across a logout or reboot — so a clipboard somebody else has
///   taken since the crash is never overwritten;
/// * anything that does not fit those two cases deletes the record and leaves the
///   clipboard alone.
///
/// # The privacy trade, stated rather than hidden
///
/// The record holds the bytes of whatever the user had copied — that is what
/// "restore it" means — so it is the one place this app writes the user's
/// clipboard to disk. It is written `0600`, it exists only between the copy and
/// the delivery's own restore, and recovery deletes it whether or not it restored
/// anything. If the process survives (the normal case) it is gone within seconds;
/// if it does not, it survives exactly one launch.
///
/// # What it does not do
///
/// It cannot recover a pasteboard the *user* overwrote after the crash (by
/// design: their newer contents win), and it cannot help if the app is never
/// launched again.
enum ClipboardRecovery {

    /// Where the record is written, and where recovery looks for it.
    ///
    /// Settable so a test — and the child process a test kills — can point at a
    /// file of their own instead of the running app's Application Support.
    static var recordURL: URL = defaultRecordURL()

    /// One displaced clipboard, as it sits on disk.
    struct Record: Codable, Equatable {
        /// The pasteboard's types, in order.
        var types: [String]
        /// The bytes of each type.
        var data: [String: Data]
        /// SHA-256 of the text the delivery put on the pasteboard. Recovery uses
        /// it to answer "is the pasteboard still holding what we wrote?" without
        /// storing the transcription a second time.
        var writtenTextDigest: String
        var createdAt: Date
    }

    /// What a launch-time recovery did.
    enum Outcome: Equatable, CustomStringConvertible {
        /// Nothing was pending: the delivery restored its own clipboard.
        case nothingPending
        /// The displaced contents were put back.
        case restored(types: Int)
        /// A record was pending but the pasteboard no longer holds our text, so
        /// leaving it alone was the only safe thing to do.
        case somebodyElseHasTheClipboard
        /// A record was pending and could not be read.
        case unreadableRecord

        var description: String {
            switch self {
            case .nothingPending: return "nothing-pending"
            case .restored(let types): return "restored(\(types) types)"
            case .somebodyElseHasTheClipboard: return "somebody-else-has-the-clipboard"
            case .unreadableRecord: return "unreadable-record"
            }
        }
    }

    /// The same subsystem `KeyboardSimulator` logs under, spelled out here so
    /// this file depends on nothing else in the app: the crash test compiles it
    /// on its own, beside `ClipboardUtil`, into a child process that is then
    /// killed.
    private static let log = Logger(subsystem: "ru.starmel.OpenSuperWhisper",
                                    category: "clipboard-recovery")

    static func digest(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultRecordURL() -> URL {
        let identifier = Bundle.main.bundleIdentifier ?? "OpenSuperWhisper"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("clipboard-recovery.plist")
    }

    /// Captures what `pasteboard` holds into a record for a delivery that is
    /// about to write `text` over it.
    ///
    /// - Returns: `nil` when there is nothing to restore — an empty pasteboard, or
    ///   one whose types hold no readable bytes.
    static func record(for pasteboard: NSPasteboard, writtenText: String) -> Record? {
        let types = pasteboard.types ?? []
        var data: [String: Data] = [:]
        for type in types {
            if let bytes = pasteboard.data(forType: type) {
                data[type.rawValue] = bytes
            }
        }
        guard !data.isEmpty else { return nil }
        return Record(types: types.map(\.rawValue),
                      data: data,
                      writtenTextDigest: digest(of: writtenText),
                      createdAt: Date())
    }

    /// Writes the record `0600` so the user's clipboard bytes are readable by
    /// this user alone, and never world-readable.
    @discardableResult
    static func write(_ record: Record, to url: URL = recordURL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let bytes = try encoder.encode(record)
            try bytes.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: url.path)
            return true
        } catch {
            log.error("clipboard recovery record could not be written: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Reads a pending record, if one is there.
    static func pending(at url: URL = recordURL) -> Record? {
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(Record.self, from: bytes)
    }

    static func clear(at url: URL = recordURL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Answers whether the pasteboard still holds the text a delivery wrote.
    private static func pasteboardHoldsOurText(_ record: Record, _ pasteboard: NSPasteboard) -> Bool {
        guard let current = pasteboard.string(forType: .string) else { return false }
        return digest(of: current) == record.writtenTextDigest
    }

    /// What a launch does about a pending record.
    ///
    /// `OpenSuperWhisperApp.applicationDidFinishLaunching` calls this and nothing
    /// else. The test-mode guard is a parameter here rather than a `guard` at the
    /// call site so that both branches are driven by a test — but what that test
    /// covers is this decision, not the wiring: that a real launch reaches this
    /// line is verified by reading the one-line call site, and both the test and
    /// the Readme say so rather than implying the launch itself is under test.
    ///
    /// - Returns: The outcome, or `nil` when the caller is a test host and
    ///   nothing was looked at.
    @discardableResult
    static func launchStep(isRunningTests: Bool,
                           from url: URL = recordURL,
                           on pasteboard: NSPasteboard = .general) -> Outcome? {
        guard !isRunningTests else { return nil }
        let outcome = recoverIfNeeded(from: url, on: pasteboard)
        if outcome != .nothingPending {
            log.notice("launch: clipboard recovery \(outcome.description, privacy: .public)")
        }
        return outcome
    }

    /// Puts a displaced clipboard back when a previous run died before restoring
    /// it, and deletes the record either way.
    ///
    /// Called once at launch. The record is removed in every path, because a
    /// record that has been looked at is a record that has done its job: if the
    /// clipboard can no longer be restored safely, keeping it would only risk
    /// putting stale contents back later.
    @discardableResult
    static func recoverIfNeeded(from url: URL = recordURL,
                                on pasteboard: NSPasteboard = .general) -> Outcome {
        guard FileManager.default.fileExists(atPath: url.path) else { return .nothingPending }
        guard let record = pending(at: url) else {
            clear(at: url)
            log.notice("clipboard recovery: a record was pending and could not be read; discarded")
            return .unreadableRecord
        }
        defer { clear(at: url) }

        guard pasteboardHoldsOurText(record, pasteboard) else {
            log.notice("""
                clipboard recovery: a record was pending but the pasteboard no longer holds this app's \
                text, so the clipboard was left alone
                """)
            return .somebodyElseHasTheClipboard
        }

        let types = record.types.compactMap { NSPasteboard.PasteboardType(rawValue: $0) }
        pasteboard.clearContents()
        if !types.isEmpty {
            pasteboard.declareTypes(types, owner: nil)
            for type in types {
                if let bytes = record.data[type.rawValue] {
                    pasteboard.setData(bytes, forType: type)
                }
            }
        }
        log.notice("clipboard recovery: put \(types.count, privacy: .public) pasteboard types back after a crash")
        return .restored(types: types.count)
    }
}
