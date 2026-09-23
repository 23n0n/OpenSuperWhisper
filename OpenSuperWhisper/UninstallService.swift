import AppKit
import Foundation
import SwiftUI

enum UninstallError: Error, LocalizedError {
    case scriptMissing
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptMissing:
            return "This build does not contain the uninstaller script, so the app cannot remove itself."
        case .launchFailed(let reason):
            return "The uninstaller could not be started: \(reason)"
        }
    }
}

/// The single uninstall operation, as seen from inside the app.
///
/// macOS has no uninstall for a `.pkg`, so the package ships one:
/// `packaging/uninstall.sh`, which the app also carries as a resource. An app
/// cannot delete the bundle it is running from, so this copies that script to a
/// temporary file, starts it detached with the app's own pid, and quits. The
/// script waits for that pid to disappear, then removes the app, everything the
/// app wrote in the user's home directory, and the installer receipt.
///
/// The same script is installed as `/Applications/Uninstall OpenSuperWhisper.command`,
/// so a user whose app is already in the Trash runs exactly the same code.
enum UninstallService {

    /// The uninstaller inside the app bundle.
    static var scriptURL: URL? {
        Bundle.main.url(forResource: "uninstall", withExtension: "sh")
    }

    /// One thing the uninstaller removes, as shown in the confirmation sheet.
    struct RemovedItem {
        let title: String
        let detail: String
        /// A literal fragment of the uninstaller's path list. The sheet is only
        /// allowed to promise what the script actually deletes, and
        /// `UninstallServiceTests` holds the two together.
        let scriptMarker: String
    }

    /// What uninstalling removes. Nothing outside this list is touched.
    static var removedItems: [RemovedItem] {
        [
            RemovedItem(
                title: "The app",
                detail: "/Applications/OpenSuperWhisper.app",
                scriptMarker: "Applications/$APP_NAME.app"
            ),
            RemovedItem(
                title: "Dictation history",
                detail: "recordings and the transcriptions database",
                scriptMarker: "Library/Application Support/$BUNDLE_ID"
            ),
            RemovedItem(
                title: "Speech and transform models",
                detail: "everything the app downloaded",
                scriptMarker: "Library/Application Support/$BUNDLE_ID"
            ),
            RemovedItem(
                title: "Settings",
                detail: "ru.starmel.OpenSuperWhisper.plist",
                scriptMarker: "Library/Preferences/$BUNDLE_ID.plist"
            ),
            RemovedItem(
                title: "Caches and window state",
                detail: "caches, HTTP storage, saved state",
                scriptMarker: "Library/Caches/$BUNDLE_ID"
            ),
            RemovedItem(
                title: "Installer receipt",
                detail: "so a later install is a clean first install",
                scriptMarker: "pkgutil --forget"
            )
        ]
    }

    /// What uninstalling deliberately leaves alone.
    static let untouchedNote = """
        Left alone: ~/models, /opt/homebrew and every other application's data.
        """

    /// Starts the uninstaller and returns immediately. The caller quits the app:
    /// the script waits for this process to be gone before it removes anything.
    static func startUninstall(resetPermissions: Bool) throws {
        guard let scriptURL else { throw UninstallError.scriptMissing }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenSuperWhisper-uninstall-\(UUID().uuidString).sh")
        do {
            try FileManager.default.copyItem(at: scriptURL, to: temporary)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: temporary.path
            )
        } catch {
            throw UninstallError.launchFailed(error.localizedDescription)
        }

        var arguments = [
            "--wait-pid", String(ProcessInfo.processInfo.processIdentifier),
            "--self-delete"
        ]
        if resetPermissions {
            arguments.append("--reset-permissions")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [temporary.path] + arguments
        // Detached in the only sense that matters here: nothing waits for it, it
        // survives this process exiting, and it removes itself when done.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw UninstallError.launchFailed(error.localizedDescription)
        }
    }
}

/// The confirmation sheet. Everything the user is about to lose is listed, and
/// the one thing that is not removed is stated too.
struct UninstallConfirmationSheet: View {
    @Binding var resetPermissions: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Uninstall OpenSuperWhisper?")
                .font(.headline)

            Text("This removes the app and everything it has stored on this Mac. It cannot be undone.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(UninstallService.removedItems, id: \.title) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 10))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 12))
                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            Text(UninstallService.untouchedNote)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Also reset microphone and accessibility permissions", isOn: $resetPermissions)
                .font(.system(size: 12))

            Text("An administrator password may be requested to remove the app from /Applications.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Uninstall", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
