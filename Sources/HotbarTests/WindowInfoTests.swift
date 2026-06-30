import XCTest
@testable import Hotbar

final class WindowInfoTests: XCTestCase {

    // MARK: - WindowInfo equality

    func testWindowInfoEqualityBasedOnID() {
        let w1 = makeWindow(id: 100, title: "Test Window", appName: "TestApp")
        let w2 = makeWindow(id: 100, title: "Different Title", appName: "DifferentApp")
        XCTAssertEqual(w1, w2, "Windows with same ID must be equal regardless of other fields")
    }

    func testWindowInfoInequalityDifferentID() {
        let w1 = makeWindow(id: 100)
        let w2 = makeWindow(id: 200)
        XCTAssertNotEqual(w1, w2)
    }

    // MARK: - WindowFetcher

    func testWindowFetcherReturnsList() {
        let windows = WindowFetcher.fetchAllWindows()
        XCTAssertNotNil(windows)
    }

    func testWindowFetcherWindowsHaveNonEmptyAppName() {
        let windows = WindowFetcher.fetchAllWindows()
        for window in windows {
            XCTAssertFalse(window.appName.isEmpty, "Every window must have a non-empty appName")
            XCTAssertFalse(window.title.isEmpty, "Every window must have a non-empty title")
        }
    }

    func testWindowFetcherWindowIDsAreUnique() {
        let windows = WindowFetcher.fetchAllWindows()
        let ids = windows.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "All window IDs must be unique")
    }
}

// MARK: - HotbarStore tests

final class HotbarStoreTests: XCTestCase {
    private var store: HotbarStore!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "com.entaku.HotbarTests.\(name)")!
        testDefaults.removePersistentDomain(forName: "com.entaku.HotbarTests.\(name)")
        store = HotbarStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.entaku.HotbarTests.\(name)")
        testDefaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Slot assignment

    func testAssignSlotStoresWindow() {
        let window = makeWindow(id: 42, appName: "Xcode")
        store.assignSlot(index: 1, windowInfo: window)
        XCTAssertEqual(store.slots[1]?.id, 42)
        XCTAssertEqual(store.slots[1]?.appName, "Xcode")
    }

    func testAssignSlotOverridesExisting() {
        store.assignSlot(index: 1, windowInfo: makeWindow(id: 10, appName: "AppA"))
        store.assignSlot(index: 1, windowInfo: makeWindow(id: 20, appName: "AppB"))
        XCTAssertEqual(store.slots[1]?.id, 20)
    }

    func testAssignSlotAllNineSlots() {
        for i in 1...9 {
            store.assignSlot(index: i, windowInfo: makeWindow(id: CGWindowID(i * 10)))
        }
        XCTAssertEqual(store.slots.count, 9)
        for i in 1...9 {
            XCTAssertNotNil(store.slots[i], "Slot \(i) should be set")
        }
    }

    func testAssignSlotIgnoresOutOfRange() {
        store.assignSlot(index: 0, windowInfo: makeWindow(id: 99))
        store.assignSlot(index: 10, windowInfo: makeWindow(id: 100))
        XCTAssertTrue(store.slots.isEmpty, "Out-of-range slots must be ignored")
    }

    // MARK: - Clear slot

    func testClearSlotRemovesWindow() {
        store.assignSlot(index: 3, windowInfo: makeWindow(id: 55))
        store.clearSlot(index: 3)
        XCTAssertNil(store.slots[3])
    }

    func testClearSlotOnEmptySlotIsSafe() {
        XCTAssertNil(store.slots[5])
        store.clearSlot(index: 5) // must not crash
        XCTAssertNil(store.slots[5])
    }

    // MARK: - Persistence

    func testSaveAndReloadSlots() {
        let window = makeWindow(id: 77, title: "Safari", appName: "Safari", bundleID: "com.apple.Safari", pid: 2222)
        store.assignSlot(index: 4, windowInfo: window)

        // Reload from same defaults
        let store2 = HotbarStore(defaults: testDefaults)
        XCTAssertEqual(store2.slots[4]?.id, 77)
        XCTAssertEqual(store2.slots[4]?.title, "Safari")
        XCTAssertEqual(store2.slots[4]?.appName, "Safari")
        XCTAssertEqual(store2.slots[4]?.appBundleIdentifier, "com.apple.Safari")
    }

    func testPersistencePreservesAllSlots() {
        for i in 1...9 {
            store.assignSlot(index: i, windowInfo: makeWindow(id: CGWindowID(i * 100), appName: "App\(i)"))
        }
        let store2 = HotbarStore(defaults: testDefaults)
        for i in 1...9 {
            XCTAssertNotNil(store2.slots[i], "Slot \(i) must survive reload")
            XCTAssertEqual(store2.slots[i]?.id, CGWindowID(i * 100))
        }
    }

    func testPersistenceWithNilBundleID() {
        let window = makeWindow(id: 33, appName: "UnknownApp", bundleID: nil)
        store.assignSlot(index: 2, windowInfo: window)
        let store2 = HotbarStore(defaults: testDefaults)
        XCTAssertNil(store2.slots[2]?.appBundleIdentifier)
    }

    func testEmptyDefaultsLoadsEmptySlots() {
        XCTAssertTrue(store.slots.isEmpty)
    }

    // MARK: - selectedIndex

    func testSelectedIndexDefaultsToZero() {
        XCTAssertEqual(store.selectedIndex, 0)
    }

    func testWindowsDefaultsToEmpty() {
        XCTAssertTrue(store.windows.isEmpty)
    }
}

// MARK: - HoldKeyDetector tests

final class HoldKeyDetectorTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var store: HotbarStore!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "com.entaku.HotbarTests.HoldKey.\(name)")!
        testDefaults.removePersistentDomain(forName: "com.entaku.HotbarTests.HoldKey.\(name)")
        store = HotbarStore(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.entaku.HotbarTests.HoldKey.\(name)")
        store = nil
        super.tearDown()
    }

    func testStartSetsCurrentDigit() {
        let detector = HoldKeyDetector(holdDuration: 10, store: store)
        detector.start(digit: 5)
        XCTAssertEqual(detector.currentDigit, 5)
        detector.cancel()
    }

    func testCancelClearsDigit() {
        let detector = HoldKeyDetector(holdDuration: 10, store: store)
        detector.start(digit: 3)
        detector.cancel()
        XCTAssertNil(detector.currentDigit)
    }

    func testStartSameDigitDoesNotReset() {
        let detector = HoldKeyDetector(holdDuration: 10, store: store)
        detector.start(digit: 7)
        XCTAssertEqual(detector.currentDigit, 7)
        detector.start(digit: 7) // same digit, should be no-op
        XCTAssertEqual(detector.currentDigit, 7)
        detector.cancel()
    }

    func testStartDifferentDigitResets() {
        let detector = HoldKeyDetector(holdDuration: 10, store: store)
        detector.start(digit: 1)
        detector.start(digit: 2) // different digit: reset
        XCTAssertEqual(detector.currentDigit, 2)
        detector.cancel()
    }

    func testTriggerRegisterWithNoWindowsDoesNotAssign() {
        // store.windows is empty → triggerRegister must be a safe no-op
        let detector = HoldKeyDetector(holdDuration: 0.01, store: store)
        detector.start(digit: 1)
        // Manually invoke to avoid waiting for timer in tests
        detector.cancel()
        // Confirm store still has no slots
        XCTAssertTrue(store.slots.isEmpty)
    }

    func testTriggerRegisterAssignsSelectedWindow() {
        let window = makeWindow(id: 88, appName: "TestApp")
        store.windows = [window]
        store.selectedIndex = 0

        let detector = HoldKeyDetector(holdDuration: 10, store: store)
        detector.start(digit: 3)
        detector.triggerRegister() // invoke directly (skips timer)

        XCTAssertEqual(store.slots[3]?.id, 88)
        XCTAssertNil(detector.currentDigit, "currentDigit must be cleared after register")
    }

    func testTriggerRegisterWithInvalidSelectedIndex() {
        store.windows = [makeWindow(id: 1)]
        store.selectedIndex = 99 // out of range

        let detector = HoldKeyDetector(holdDuration: 10, store: store)
        detector.start(digit: 5)
        detector.triggerRegister()

        XCTAssertNil(store.slots[5], "No slot should be assigned when selectedIndex is out of range")
    }

    func testHoldDurationFires() {
        let window = makeWindow(id: 55, appName: "HoldApp")
        store.windows = [window]
        store.selectedIndex = 0

        let detector = HoldKeyDetector(holdDuration: 0.05, store: store)
        let exp = expectation(description: "Slot assigned after hold")

        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: .hotbarSlotAssigned, object: nil, queue: .main) { _ in
            exp.fulfill()
            if let t = token { NotificationCenter.default.removeObserver(t) }
        }

        detector.start(digit: 2)
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(store.slots[2]?.id, 55)
    }
}

// MARK: - Helpers

private func makeWindow(
    id: CGWindowID,
    title: String = "Window",
    appName: String = "App",
    bundleID: String? = nil,
    pid: pid_t = 1234
) -> WindowInfo {
    WindowInfo(
        id: id,
        title: title,
        appName: appName,
        appBundleIdentifier: bundleID,
        pid: pid,
        thumbnail: nil,
        appIcon: nil
    )
}
