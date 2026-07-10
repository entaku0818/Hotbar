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

    func testLicensedStatusPersistsAcrossRelaunchEvenAfterTrialWindow() async {
        let client = MockLicenseClient()
        client.activationResult = .success(
            LicenseActivationResponse(activated: true, error: nil, instance: LicenseInstance(id: "inst-1", name: "Test Mac"))
        )
        let manager = LicenseManager(defaults: defaults, client: client, now: { Self.epoch })
        await manager.activate(licenseKey: "GOOD-KEY", instanceName: "Test Mac")

        let muchLater = Self.epoch.addingTimeInterval(365 * 86400)
        let relaunched = LicenseManager(defaults: defaults, client: client, now: { muchLater })

        XCTAssertEqual(relaunched.status, .licensed)
        XCTAssertFalse(relaunched.isGated)
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

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationResponse {
        activateCallCount += 1
        return try activationResult.get()
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidationResponse {
        try validationResult.get()
    }
}
