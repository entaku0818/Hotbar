import XCTest
@testable import Hotbar

final class WindowInfoTests: XCTestCase {
    func testWindowInfoEquality() {
        let w1 = WindowInfo(
            id: 100,
            title: "Test Window",
            appName: "TestApp",
            appBundleIdentifier: "com.test.app",
            pid: 1234,
            thumbnail: nil,
            appIcon: nil
        )
        let w2 = WindowInfo(
            id: 100,
            title: "Different Title",
            appName: "DifferentApp",
            appBundleIdentifier: nil,
            pid: 9999,
            thumbnail: nil,
            appIcon: nil
        )
        // Equality is based on window ID only
        XCTAssertEqual(w1, w2)
    }

    func testWindowInfoInequality() {
        let w1 = WindowInfo(
            id: 100,
            title: "Window A",
            appName: "App",
            appBundleIdentifier: nil,
            pid: 1234,
            thumbnail: nil,
            appIcon: nil
        )
        let w2 = WindowInfo(
            id: 200,
            title: "Window A",
            appName: "App",
            appBundleIdentifier: nil,
            pid: 1234,
            thumbnail: nil,
            appIcon: nil
        )
        XCTAssertNotEqual(w1, w2)
    }

    func testHotbarStoreSlotAssignment() {
        let store = HotbarStore.shared
        let window = WindowInfo(
            id: 42,
            title: "Xcode",
            appName: "Xcode",
            appBundleIdentifier: "com.apple.dt.Xcode",
            pid: 5678,
            thumbnail: nil,
            appIcon: nil
        )
        store.assignSlot(index: 1, windowInfo: window)
        XCTAssertEqual(store.slots[1]?.id, 42)
        XCTAssertEqual(store.slots[1]?.appName, "Xcode")

        // Override slot
        let window2 = WindowInfo(
            id: 99,
            title: "Safari",
            appName: "Safari",
            appBundleIdentifier: "com.apple.Safari",
            pid: 1111,
            thumbnail: nil,
            appIcon: nil
        )
        store.assignSlot(index: 1, windowInfo: window2)
        XCTAssertEqual(store.slots[1]?.id, 99)
    }

    func testWindowFetcherReturnsArray() {
        // This test requires Accessibility permissions; just verify it doesn't crash
        let windows = WindowFetcher.fetchAllWindows()
        XCTAssertNotNil(windows)
        // Each window must have non-empty appName
        for w in windows {
            XCTAssertFalse(w.appName.isEmpty)
        }
    }
}
