import XCTest
@testable import OpenSuperWhisper

/// The suite must not be able to change — or be changed by — the preferences of
/// the app the developer is running, or of another suite running in parallel.
///
/// That is a property of *where* `AppPreferences` reads and writes, so it is
/// asserted here instead of being re-checked in every test that touches a switch.
/// With the app's own domain behind it, `TransformBackendTests` and
/// `TranslationServiceTests` disagree about `translateEnabled` depending on which
/// process wrote last — which is how `testStoredSwitchChoosesTheBackend` came to
/// fail intermittently, returning the input "Cześć" instead of the stub's "from
/// the endpoint" because another process had left the transform switched off.
final class PreferenceIsolationTests: XCTestCase {
    func testTheSuiteDoesNotRunAgainstTheApplicationsOwnPreferences() {
        XCTAssertFalse(
            AppPreferences.defaults === UserDefaults.standard,
            "the suite is reading and writing the app's own preference domain")
    }

    func testAPreferenceWrittenUnderTestStaysOutOfTheApplicationDomain() {
        let key = "preferenceIsolationProbe"
        AppPreferences.defaults.set("scratch", forKey: key)

        XCTAssertEqual(AppPreferences.defaults.string(forKey: key), "scratch")
        XCTAssertNil(
            UserDefaults.standard.object(forKey: key),
            "a preference written by the suite must never reach the app's own domain")
    }
}
