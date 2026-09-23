import XCTest
@testable import OpenSuperWhisper

/// The app's half of the uninstall contract: the script must be in the bundle,
/// and the confirmation sheet may only promise what the script actually removes.
final class UninstallServiceTests: XCTestCase {

    func testUninstallerScriptShipsInsideTheApp() throws {
        let url = try XCTUnwrap(
            UninstallService.scriptURL,
            "packaging/uninstall.sh must be copied into the app bundle as a resource"
        )
        let script = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(script.contains("ru.starmel.OpenSuperWhisper"))
        XCTAssertTrue(script.contains("--wait-pid"))
    }

    func testEveryPromisedRemovalIsInTheShippedScript() throws {
        let script = try String(contentsOf: try XCTUnwrap(UninstallService.scriptURL), encoding: .utf8)

        for item in UninstallService.removedItems {
            XCTAssertTrue(
                script.contains(item.scriptMarker),
                "the confirmation sheet promises '\(item.title)' (\(item.scriptMarker)) but the uninstaller does not do it"
            )
        }
    }

    /// Every removal in the script goes through a path variable that is built
    /// from the install root. Nothing outside the app's own paths can be named
    /// literally, which is what keeps the uninstaller away from ~/models,
    /// /opt/homebrew and other applications.
    func testEveryRemovalTargetIsARootRelativeVariable() throws {
        let script = try String(contentsOf: try XCTUnwrap(UninstallService.scriptURL), encoding: .utf8)
        let removals = script
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("rm ") || $0.hasPrefix("rm -") }

        XCTAssertFalse(removals.isEmpty, "precondition: the uninstaller removes something")

        for line in removals {
            XCTAssertTrue(
                line.contains("\"$"),
                "the uninstaller removes a hardcoded path instead of a root-relative variable: \(line)"
            )
        }
    }

    func testScriptRefusesUnknownArguments() throws {
        // A scratch root even here: no test may ever point the uninstaller at
        // the real /Applications.
        let result = try runScript(["--not-a-flag"], root: try makeScratchInstall())

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("unknown argument"))
    }

    // MARK: - Running the script against a scratch root
    //
    // `OSW_INSTALL_ROOT` prefixes every path, and everything that needs the real
    // machine (quitting the app, cfprefsd, the installer receipt, TCC) runs only
    // for the real root. That makes the whole path list testable without
    // touching anything the user owns -- verified from the shell too, by
    // Scripts/verify-packaging.sh.

    func testUninstallRemovesTheScratchInstallAndIsIdempotent() throws {
        let root = try makeScratchInstall()

        let first = try runScript([], root: root)
        XCTAssertEqual(first.status, 0, first.output)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Applications/OpenSuperWhisper.app").path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Users/tester/Library/Application Support/ru.starmel.OpenSuperWhisper").path
            )
        )

        // Second run: nothing left to remove, still exit 0.
        let second = try runScript([], root: root)
        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertTrue(second.output.contains("has been removed"))
    }

    func testUninstallWorksWhenTheAppIsAlreadyGone() throws {
        let root = try makeScratchInstall()
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("Applications/OpenSuperWhisper.app")
        )

        let result = try runScript([], root: root)

        XCTAssertEqual(result.status, 0, result.output)
    }

    func testUninstallLeavesUnrelatedFilesAlone() throws {
        let root = try makeScratchInstall()
        let unrelated = root.appendingPathComponent("Users/tester/models/Qwen3-30B-A3B.gguf")
        try FileManager.default.createDirectory(
            at: unrelated.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("keep me".utf8).write(to: unrelated)

        _ = try runScript([], root: root)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: unrelated.path),
            "the uninstaller must never touch ~/models"
        )
    }

    // MARK: - Helpers

    private struct ScriptRun {
        let status: Int32
        let output: String
    }

    private func uninstallerSource() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("packaging/uninstall.sh")
    }

    /// Runs the uninstaller against a scratch root. There is deliberately no way
    /// to run it against the real one from a test.
    private func runScript(_ arguments: [String], root: URL) throws -> ScriptRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [try uninstallerSource().path] + arguments

        var environment = ProcessInfo.processInfo.environment
        environment["OSW_INSTALL_ROOT"] = root.path
        environment["HOME"] = "/Users/tester"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ScriptRun(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }

    /// A scratch tree shaped like a real install: the app, the state the app
    /// writes, and a preferences plist.
    private func makeScratchInstall() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("osw-uninstall-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Users/tester/Library/Application Support/ru.starmel.OpenSuperWhisper")
        let caches = root.appendingPathComponent("Users/tester/Library/Caches/ru.starmel.OpenSuperWhisper")
        let preferences = root.appendingPathComponent("Users/tester/Library/Preferences")
        let app = root.appendingPathComponent("Applications/OpenSuperWhisper.app/Contents/MacOS")

        for directory in [app, support.appendingPathComponent("recordings"), support.appendingPathComponent("transform-models"), caches, preferences] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("app".utf8).write(to: app.appendingPathComponent("OpenSuperWhisper"))
        try Data("db".utf8).write(to: support.appendingPathComponent("recordings.sqlite"))
        try Data("wav".utf8).write(to: support.appendingPathComponent("recordings/dictation.wav"))
        try Data("weights".utf8).write(to: support.appendingPathComponent("transform-models/qwen2.5-1.5b-instruct-q4_k_m.gguf"))
        try Data("plist".utf8).write(to: preferences.appendingPathComponent("ru.starmel.OpenSuperWhisper.plist"))

        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
