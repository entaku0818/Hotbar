import XCTest
@testable import Hotbar

// MARK: - Same-app window matching

final class WindowMatchingTests: XCTestCase {
    private typealias Candidate = WindowFetcher.WindowCandidate
    private let frameA = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let frameB = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testPrefersWindowIDOverDuplicateTitles() {
        let candidates = [
            Candidate(windowID: 10, frame: frameA, title: "New Tab"),
            Candidate(windowID: 20, frame: frameB, title: "New Tab")
        ]
        XCTAssertEqual(WindowFetcher.matchingWindowIndex(id: 20, frame: frameB, title: "New Tab",
                                                         candidates: candidates), 1)
    }

    func testFallsBackToFrameWhenIDUnavailable() {
        let candidates = [
            Candidate(windowID: nil, frame: frameA, title: "Google Chrome"),
            Candidate(windowID: nil, frame: frameB, title: "Google Chrome")
        ]
        XCTAssertEqual(WindowFetcher.matchingWindowIndex(id: 20, frame: frameB, title: "Google Chrome",
                                                         candidates: candidates), 1)
    }

    func testDoesNotGuessWhenTitlesAreAmbiguous() {
        let candidates = [
            Candidate(windowID: nil, frame: nil, title: "Google Chrome"),
            Candidate(windowID: nil, frame: nil, title: "Google Chrome")
        ]
        XCTAssertNil(WindowFetcher.matchingWindowIndex(id: 20, frame: nil, title: "Google Chrome",
                                                       candidates: candidates))
    }

    func testUsesUniqueTitleAsLastResort() {
        let candidates = [
            Candidate(windowID: nil, frame: nil, title: "Inbox"),
            Candidate(windowID: nil, frame: nil, title: "Docs")
        ]
        XCTAssertEqual(WindowFetcher.matchingWindowIndex(id: 20, frame: nil, title: "Docs",
                                                         candidates: candidates), 1)
    }
}

// MARK: - Grid navigation

final class GridNavigationTests: XCTestCase {
    /// 3 columns × 2 rows, last row partially filled: [0 1 2] / [3 4]
    private let frames: [Int: CGRect] = {
        var result: [Int: CGRect] = [:]
        for index in 0..<5 {
            result[index] = CGRect(x: CGFloat(index % 3) * 200, y: CGFloat(index / 3) * 180, width: 180, height: 160)
        }
        return result
    }()

    private func move(_ from: Int, _ direction: MoveDirection) -> Int {
        HotbarStore.neighborIndex(from: from, direction: direction, frames: frames, count: 5)
    }

    func testUpMovesToSameColumnInPreviousRow() {
        XCTAssertEqual(move(4, .up), 1)
        XCTAssertEqual(move(3, .up), 0)
    }

    func testDownMovesToSameColumnInNextRow() {
        XCTAssertEqual(move(0, .down), 3)
        XCTAssertEqual(move(1, .down), 4)
    }

    func testDownFromColumnMissingInLastRowPicksNearestCell() {
        XCTAssertEqual(move(2, .down), 4)
    }

    func testUpFromTopRowWrapsToBottomRow() {
        XCTAssertEqual(move(0, .up), 3)
    }

    func testDownFromBottomRowWrapsToTopRow() {
        XCTAssertEqual(move(4, .down), 1)
    }

    func testLeftRightStepThroughListWithWrap() {
        XCTAssertEqual(move(2, .right), 3)
        XCTAssertEqual(move(0, .left), 4)
    }

    func testSingleRowFallsBackToStepping() {
        let row = [0: CGRect(x: 0, y: 0, width: 100, height: 100), 1: CGRect(x: 120, y: 0, width: 100, height: 100)]
        XCTAssertEqual(HotbarStore.neighborIndex(from: 0, direction: .down, frames: row, count: 2), 1)
        XCTAssertEqual(HotbarStore.neighborIndex(from: 0, direction: .up, frames: row, count: 2), 1)
    }

    func testMissingFramesFallBackToStepping() {
        XCTAssertEqual(HotbarStore.neighborIndex(from: 1, direction: .up, frames: [:], count: 3), 0)
        XCTAssertEqual(HotbarStore.neighborIndex(from: 2, direction: .down, frames: [:], count: 3), 0)
    }

    func testArrowKeyMapping() {
        XCTAssertEqual(HotKeyManager.arrowDirection(for: 126), .up)
        XCTAssertEqual(HotKeyManager.arrowDirection(for: 125), .down)
        XCTAssertEqual(HotKeyManager.arrowDirection(for: 123), .left)
        XCTAssertEqual(HotKeyManager.arrowDirection(for: 124), .right)
        XCTAssertNil(HotKeyManager.arrowDirection(for: 36))
    }
}
