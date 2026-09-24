import XCTest

@testable import OpenSuperWhisper

/// The Advanced tab's Debug Mode used to be a toggle that wrote a preference
/// nothing read, so it changed nothing at all. It now reaches the decoder's
/// parameters, which is the difference between a control and a decoration.
@MainActor
final class SettingsExposureTests: XCTestCase {

    private var savedDebugMode: Bool!

    override func setUp() {
        super.setUp()
        savedDebugMode = AppPreferences.shared.debugMode
    }

    override func tearDown() {
        AppPreferences.shared.debugMode = savedDebugMode
        super.tearDown()
    }

    func testDebugModeReachesTheDecoderParameters() {
        AppPreferences.shared.debugMode = true
        let on = WhisperEngine.makeFullParams(settings: Settings(), nThreads: 4,
                                              modelTextContext: 448, initialPromptTokenCount: 0)
        XCTAssertTrue(on.debugMode, "Debug Mode has to turn the decoder's verbose trace on")

        AppPreferences.shared.debugMode = false
        let off = WhisperEngine.makeFullParams(settings: Settings(), nThreads: 4,
                                               modelTextContext: 448, initialPromptTokenCount: 0)
        XCTAssertFalse(off.debugMode, "…and off again when the toggle is off")
    }

    func testTheSettingsSnapshotCarriesTheStoredDebugMode() {
        AppPreferences.shared.debugMode = true
        XCTAssertTrue(Settings().debugMode, "the per-dictation settings read the preference")
    }
}
