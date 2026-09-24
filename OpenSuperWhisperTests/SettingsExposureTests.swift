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

    // MARK: - The transform model card

    /// The card has to name the backend each direction needs, and say what is
    /// waiting when the one Polish output needs is not installed — without ever
    /// offering the small model as its substitute.
    func testThePolishDirectionReportsItsOwnMissingModelAndNeverPointsAtTheOtherOne() throws {
        let prefs = AppPreferences.shared
        let savedTranslate = prefs.translateEnabled
        let savedTarget = prefs.transformTargetLanguage
        defer {
            prefs.translateEnabled = savedTranslate
            prefs.transformTargetLanguage = savedTarget
        }

        prefs.translateEnabled = true
        prefs.transformTargetLanguage = .polish
        let model = SettingsViewModel()
        model.installedTransformModelIDs = []

        let polish = TransformModelManager.shared.model(forOutputLanguage: .polish)
        let english = TransformModelManager.shared.model(forOutputLanguage: .english)

        XCTAssertEqual(model.neededTransformModels.map(\.id), [polish.id],
                       "a Polish target needs the Polish backend, and only it")
        XCTAssertEqual(model.transformModelRoleDescription(polish), "Polish output — \(polish.displayName)")

        let state = model.transformModelStateDescription(polish)
        XCTAssertTrue(state.hasPrefix("Not downloaded"), "the row must state that the weights are missing: \(state)")
        XCTAssertTrue(state.contains(polish.memoryDescription), "the row must state the RAM cost too: \(state)")

        let notice = try XCTUnwrap(model.transformMissingNotice(for: polish))
        XCTAssertTrue(notice.contains("Polish"), notice)
        XCTAssertTrue(
            notice.contains("does not fall back to \(english.displayName)"),
            "the notice must say the small model is not used for Polish: \(notice)"
        )
        XCTAssertNil(
            model.transformMissingNotice(for: english),
            "with a Polish target the English backend is not needed, so it has nothing to warn about"
        )
    }

    /// Without translation the output language is whatever was spoken, so both
    /// backends can be asked for — and both get their own row and warning.
    func testWithoutTranslationBothBackendsCanBeNeeded() {
        let prefs = AppPreferences.shared
        let savedTranslate = prefs.translateEnabled
        let savedTone = prefs.toneEnabled
        let savedEndpoint = prefs.transformUseExternalEndpoint
        defer {
            prefs.translateEnabled = savedTranslate
            prefs.toneEnabled = savedTone
            prefs.transformUseExternalEndpoint = savedEndpoint
        }

        prefs.translateEnabled = false
        prefs.toneEnabled = true
        prefs.transformUseExternalEndpoint = false
        let model = SettingsViewModel()
        model.installedTransformModelIDs = []

        let polish = TransformModelManager.shared.model(forOutputLanguage: .polish)
        let english = TransformModelManager.shared.model(forOutputLanguage: .english)

        XCTAssertEqual(Set(model.neededTransformModels.map(\.id)), Set([polish.id, english.id]))
        XCTAssertNotNil(model.transformMissingNotice(for: polish))
        XCTAssertNotNil(model.transformMissingNotice(for: english))

        // With the external endpoint on, no local model is needed at all.
        model.transformUseExternalEndpoint = true
        XCTAssertTrue(model.neededTransformModels.isEmpty)
        XCTAssertNil(model.transformMissingNotice(for: polish))
        XCTAssertNil(model.transformMissingNotice(for: english))
    }

    /// The Target language picker carries both directions' costs, before either
    /// is paid.
    func testTheTargetPickerStatesEachBackendsRamAndDiskCost() {
        let model = SettingsViewModel()
        let caption = model.transformBackendCostDescription

        let polish = TransformModelManager.shared.model(forOutputLanguage: .polish)
        let english = TransformModelManager.shared.model(forOutputLanguage: .english)

        XCTAssertTrue(caption.contains(english.displayName), caption)
        XCTAssertTrue(caption.contains(english.memoryDescription), caption)
        XCTAssertTrue(caption.contains(english.sizeDescription), caption)
        XCTAssertTrue(caption.contains(polish.displayName), caption)
        XCTAssertTrue(caption.contains(polish.memoryDescription), caption)
        XCTAssertTrue(caption.contains(polish.sizeDescription), caption)
    }
}
