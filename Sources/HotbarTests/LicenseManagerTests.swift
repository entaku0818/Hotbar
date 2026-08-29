import XCTest
@testable import Hotbar

final class LicenseManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.entaku.HotbarTests.License"

    override func setUp() {
        super.setUp()
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        self.defaults = defaults
        self.defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Trial countdown

    func testFreshInstallStartsFourteenDayTrial() {
        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { Self.epoch })
        guard case .trial(let daysRemaining) = manager.status else {
            return XCTFail("Expected trial status, got \(manager.status)")
        }
        XCTAssertEqual(daysRemaining, 14)
        XCTAssertFalse(manager.isGated)
    }

    func testTrialStatusCountsDownAsDaysPass() {
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { now })
        now = now.addingTimeInterval(5 * 86400)
        manager.refreshStatus()
        guard case .trial(let daysRemaining) = manager.status else {
            return XCTFail("Expected trial status, got \(manager.status)")
        }
        XCTAssertEqual(daysRemaining, 9)
    }

    func testTrialExpiresAfterFourteenDays() {
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { now })
        now = now.addingTimeInterval(15 * 86400)
        manager.refreshStatus()
        XCTAssertEqual(manager.status, .trialExpired)
        XCTAssertTrue(manager.isGated)
    }

    func testTrialExpiresExactlyAtBoundary() {
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { now })
        now = now.addingTimeInterval(LicenseManager.trialDuration)
        manager.refreshStatus()
        XCTAssertEqual(manager.status, .trialExpired)
    }

    func testTrialStartDatePersistsAcrossRelaunch() {
        let manager1 = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { Self.epoch })
        guard case .trial(let firstDaysRemaining) = manager1.status else {
            return XCTFail("Expected trial status")
        }

        let laterNow = Self.epoch.addingTimeInterval(3 * 86400)
        let manager2 = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { laterNow })
        guard case .trial(let secondDaysRemaining) = manager2.status else {
            return XCTFail("Expected trial status")
        }

        XCTAssertEqual(firstDaysRemaining, 14)
        XCTAssertEqual(secondDaysRemaining, 11)
    }

    // MARK: - Activation

    func testSuccessfulActivationGrantsLicensedStatus() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        let manager = LicenseManager(defaults: defaults, client: client, now: { Self.epoch })

        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        XCTAssertEqual(manager.status, .licensed)
        XCTAssertNil(manager.activationErrorMessage)
        XCTAssertFalse(manager.isGated)
    }

    func testFailedActivationKeepsGatedAndSurfacesServerError() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: false, error: "This license key is not valid.", instance: nil)
        )
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: client, now: { now })
        now = now.addingTimeInterval(20 * 86400)
        manager.refreshStatus()

        await manager.activate(licenseKey: "BAD-KEY", instanceName: "Test Mac")

        XCTAssertEqual(manager.status, .trialExpired)
        XCTAssertEqual(manager.activationErrorMessage, "This license key is not valid.")
    }

    func testActivationNetworkErrorSurfacesMessage() async {
        let client = MockLicenseClient()
        client.activationResult = .failure(LicenseClientError.invalidResponse)
        let manager = LicenseManager(defaults: defaults, client: client, now: { Self.epoch })

        await manager.activate(licenseKey: "ANY-KEY", instanceName: "Test Mac")

        XCTAssertNotNil(manager.activationErrorMessage)
        XCTAssertNotEqual(manager.status, .licensed)
    }

    func testActivationWithBlankKeyIsRejectedWithoutNetworkCall() async {
        let client = MockLicenseClient()
        let manager = LicenseManager(defaults: defaults, client: client, now: { Self.epoch })

        await manager.activate(licenseKey: "   ", instanceName: "Test Mac")

        XCTAssertEqual(client.activateCallCount, 0)
        XCTAssertEqual(manager.activationErrorMessage, "Please enter a license key.")
    }

    func testLicensedStatusPersistsAcrossRelaunchWithinGracePeriod() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        let manager = LicenseManager(defaults: defaults, client: client, now: { Self.epoch })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        let withinGrace = Self.epoch.addingTimeInterval(13 * 86400)
        let relaunched = LicenseManager(defaults: defaults, client: client, now: { withinGrace })

        XCTAssertEqual(relaunched.status, .licensed)
        XCTAssertFalse(relaunched.isGated)
    }

    // MARK: - Offline grace period

    func testLicenseLapsesOnceGracePeriodElapsesWithoutRevalidation() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        let manager = LicenseManager(defaults: defaults, client: client, now: { Self.epoch })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        let muchLater = Self.epoch.addingTimeInterval(365 * 86400)
        let relaunched = LicenseManager(defaults: defaults, client: client, now: { muchLater })

        XCTAssertEqual(relaunched.status, .licenseValidationExpired)
        XCTAssertTrue(relaunched.isGated)
    }

    func testGracePeriodExpiresExactlyAtBoundary() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: client, now: { now })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        now = Self.epoch.addingTimeInterval(LicenseManager.offlineGracePeriod)
        manager.refreshStatus()

        XCTAssertEqual(manager.status, .licenseValidationExpired)
    }

    func testSuccessfulRevalidationRestartsGracePeriod() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        client.validationResult = .success(LicenseValidationResponse(valid: true, error: nil))
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: client, now: { now })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        // Day 10: still inside the original grace window, revalidation succeeds.
        now = Self.epoch.addingTimeInterval(10 * 86400)
        await manager.revalidate()
        XCTAssertEqual(client.validateCallCount, 1)

        // Day 20: would have lapsed without the day-10 check, but the clock restarted.
        now = Self.epoch.addingTimeInterval(20 * 86400)
        manager.refreshStatus()
        XCTAssertEqual(manager.status, .licensed)
    }

    func testRevalidationNetworkFailureKeepsLicenseInsideGracePeriod() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        client.validationResult = .failure(LicenseClientError.invalidResponse)
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: client, now: { now })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        now = Self.epoch.addingTimeInterval(5 * 86400)
        await manager.revalidate()

        XCTAssertEqual(manager.status, .licensed)
    }

    func testRevalidationNetworkFailureGatesOnceGracePeriodHasElapsed() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        client.validationResult = .failure(LicenseClientError.invalidResponse)
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: client, now: { now })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        now = Self.epoch.addingTimeInterval(15 * 86400)
        await manager.revalidate()

        XCTAssertEqual(manager.status, .licenseValidationExpired)
        XCTAssertTrue(manager.isGated)
    }

    func testServerSaysInvalidClearsTheStoredLicenseImmediately() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        client.validationResult = .success(LicenseValidationResponse(valid: false, error: "Revoked"))
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: client, now: { now })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        // Day 1 — well inside the grace period, but Polar says the key is dead.
        now = Self.epoch.addingTimeInterval(86400)
        await manager.revalidate()

        XCTAssertNil(defaults.string(forKey: "licenseKey"))
        XCTAssertNil(defaults.string(forKey: "licenseInstanceID"))
        XCTAssertNotEqual(manager.status, .licensed)
    }

    func testRevalidationIsSkippedWhenNoLicenseIsStored() async {
        let client = MockLicenseClient()
        let manager = LicenseManager(defaults: defaults, client: client, now: { Self.epoch })

        await manager.revalidate()

        XCTAssertEqual(client.validateCallCount, 0)
    }

    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
}

/// UserDefaults is user-writable, so these pin down what a hand-edited
/// defaults domain can and cannot buy you.
final class LicenseTamperResistanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.entaku.HotbarTests.LicenseTamper"

    override func setUp() {
        super.setUp()
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite")
            return
        }
        self.defaults = defaults
        self.defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// `defaults write com.entaku.Hotbar licenseKey any` must not unlock the app.
    func testArbitraryLicenseKeyInDefaultsDoesNotUnlockTheApp() {
        defaults.set("any", forKey: "licenseKey")

        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { Self.epoch })

        XCTAssertNotEqual(manager.status, .licensed)
        XCTAssertEqual(manager.status, .licenseValidationExpired)
        XCTAssertTrue(manager.isGated)
    }

    /// Forging the key + activation id still leaves no validation timestamp.
    func testForgedKeyAndInstanceIDWithoutValidationTimestampDoesNotUnlock() {
        defaults.set("any", forKey: "licenseKey")
        defaults.set("inst-forged", forKey: "licenseInstanceID")

        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { Self.epoch })

        XCTAssertNotEqual(manager.status, .licensed)
        XCTAssertTrue(manager.isGated)
    }

    /// A validation timestamp in the future (clock rolled back) is treated as
    /// stale, not as an unlimited grace period.
    func testFutureValidationTimestampDoesNotGrantUnlimitedGrace() {
        defaults.set("any", forKey: "licenseKey")
        defaults.set("inst-forged", forKey: "licenseInstanceID")
        defaults.set(Self.epoch.addingTimeInterval(365 * 86400), forKey: "licenseLastValidatedAt")

        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { Self.epoch })

        XCTAssertNotEqual(manager.status, .licensed)
        XCTAssertTrue(manager.isGated)
    }

    /// An empty-string key must not read as "a key is present".
    func testEmptyLicenseKeyFallsBackToTrialComputation() {
        defaults.set("", forKey: "licenseKey")

        let manager = LicenseManager(defaults: defaults, client: MockLicenseClient(), now: { Self.epoch })

        guard case .trial = manager.status else {
            return XCTFail("Expected trial status, got \(manager.status)")
        }
    }

    func testDeactivateRevertsToTrialComputation() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        var now = Self.epoch
        let manager = LicenseManager(defaults: defaults, client: client, now: { now })
        now = now.addingTimeInterval(20 * 86400)
        manager.refreshStatus()
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")
        XCTAssertEqual(manager.status, .licensed)

        manager.deactivate()

        XCTAssertEqual(manager.status, .trialExpired)
    }

    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
}

final class MockLicenseClient: LicenseClient {
    var activationResult: Result<LicenseActivationResponse, Error> = .failure(LicenseClientError.invalidResponse)
    var validationResult: Result<LicenseValidationResponse, Error> = .failure(LicenseClientError.invalidResponse)
    private(set) var activateCallCount = 0
    private(set) var validateCallCount = 0

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationResponse {
        activateCallCount += 1
        return try activationResult.get()
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidationResponse {
        validateCallCount += 1
        return try validationResult.get()
    }
}
