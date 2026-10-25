import XCTest
import AppKit
@testable import Hotbar

final class CustomizationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "Hotbar.CustomizationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testNumberRowSlotsUseMacVirtualKeyCodes() {
        let keyCodes: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        XCTAssertEqual(keyCodes.compactMap { HotKeyManager.slotDigit(for: $0) }, Array(1...9))
        for code: Int64 in [24, 27, 29, 48, 83] {
            XCTAssertNil(HotKeyManager.slotDigit(for: code))
        }
    }

    func testExistingPreferencesSurviveNewSettings() {
        defaults.set(false, forKey: "holdMode")
        defaults.set(200.0, forKey: "thumbnailSize")
        defaults.set(["Safari"], forKey: "excludedApps")
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.holdMode)
        XCTAssertEqual(settings.thumbnailSize, 200)
        XCTAssertEqual(settings.excludedApps, ["Safari"])
        XCTAssertEqual(settings.windowOrder, .recent)
        XCTAssertEqual(settings.overlayPosition, .center)
        XCTAssertEqual(settings.accent, .system)
    }

    func testCustomizationPersistsAcrossLaunches() {
        let settings = AppSettings(defaults: defaults)
        settings.favoriteApps = ["Xcode", "Safari"]
        settings.windowOrder = .title
        settings.overlayPosition = .bottom
        settings.accent = .purple
        settings.showSlotNames = false
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.favoriteApps, ["Xcode", "Safari"])
        XCTAssertEqual(restored.windowOrder, .title)
        XCTAssertEqual(restored.overlayPosition, .bottom)
        XCTAssertEqual(restored.accent, .purple)
        XCTAssertFalse(restored.showSlotNames)
    }

    func testUnknownStoredOptionsUseDefaults() {
        for key in ["windowOrder", "overlayPosition", "hotbarAccent"] { defaults.set("unknown", forKey: key) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.windowOrder, .recent)
        XCTAssertEqual(settings.overlayPosition, .center)
        XCTAssertEqual(settings.accent, .system)
    }

    func testFavoritesKeepRecentOrderWithinGroups() {
        let windows = [window(1, "Safari"), window(2, "Xcode"), window(3, "Safari"), window(4, "Notes")]
        let sorted = HotbarStore.orderWindows(windows, favorites: ["Xcode", "Notes"], order: .recent)
        XCTAssertEqual(sorted.map(\.id), [2, 4, 1, 3])
    }

    func testAppSortIsStableAndExclusionsWinOverFavorites() {
        let windows = [window(1, "Safari"), window(2, "Xcode"), window(3, "Notes"), window(4, "Notes")]
        let visible = HotbarStore.applyExclusions(windows, excluded: ["Xcode"])
        let sorted = HotbarStore.orderWindows(visible, favorites: ["Xcode"], order: .appName)
        XCTAssertEqual(sorted.map(\.id), [3, 4, 1])
    }

    func testTitleOrderStillPutsFavoritesFirst() {
        let windows = [window(1, "Safari", "Z"), window(2, "Notes", "B"), window(3, "Notes", "A")]
        let sorted = HotbarStore.orderWindows(windows, favorites: ["Safari"], order: .title)
        XCTAssertEqual(sorted.map(\.id), [1, 3, 2])
    }

    func testOverlayPositionsRespectDisplayOriginAndMenuBar() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let size = CGSize(width: 900, height: 560)
        XCTAssertEqual(OverlayPosition.center.origin(in: visible, panelSize: size), CGPoint(x: -1170, y: 190))
        XCTAssertEqual(OverlayPosition.top.origin(in: visible, panelSize: size), CGPoint(x: -1170, y: 324))
        XCTAssertEqual(OverlayPosition.bottom.origin(in: visible, panelSize: size), CGPoint(x: -1170, y: 56))
    }

    func testRelativeOverlayFitsAllDisplaySizesAndPositions() {
        let displays = [
            CGRect(x: 0, y: 25, width: 1280, height: 775),
            CGRect(x: -1920, y: 40, width: 1920, height: 1040),
            CGRect(x: 0, y: 0, width: 3440, height: 1400),
            CGRect(x: 0, y: 0, width: 900, height: 1400)
        ]
        for display in displays {
            let size = OverlayWindowController.panelSize(in: display)
            XCTAssertEqual(size.width / display.width, 0.85, accuracy: 0.002)
            XCTAssertEqual(size.height / display.height, 0.82, accuracy: 0.002)
            for position in [OverlayPosition.center, .top, .bottom] {
                let frame = CGRect(origin: position.origin(in: display, panelSize: size), size: size)
                XCTAssertTrue(display.contains(frame))
            }
        }
    }

    func testLanguagePreferencePersistsAndUnknownValuesUseSystem() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.language, .system)
        settings.language = .japanese
        XCTAssertEqual(AppSettings(defaults: defaults).language, .japanese)
        settings.language = .english
        XCTAssertEqual(AppSettings(defaults: defaults).language, .english)
        defaults.set("unsupported", forKey: "appLanguage")
        XCTAssertEqual(AppSettings(defaults: defaults).language, .system)
    }

    func testLanguageResolutionRespectsPreferredSupportedLanguage() {
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["ja-JP", "en-US"]), "ja")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["en-GB", "ja"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR", "ja_JP"]), "ja")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.english.resolvedCode(preferredLanguages: ["ja"]), "en")
        XCTAssertEqual(AppLanguage.japanese.resolvedCode(preferredLanguages: ["en"]), "ja")
    }

    func testBundledLanguagesHaveMatchingKeysAndPlaceholders() throws {
        let english = try strings(for: "en")
        let japanese = try strings(for: "ja")
        XCTAssertGreaterThan(english.count, 100)
        XCTAssertEqual(Set(english.keys), Set(japanese.keys))
        for (key, value) in english {
            let translation = try XCTUnwrap(japanese[key])
            XCTAssertFalse(translation.isEmpty, key)
            for token in ["%@", "%d"] {
                XCTAssertEqual(value.components(separatedBy: token).count,
                               translation.components(separatedBy: token).count, key)
            }
        }
        XCTAssertEqual(L10n.text("General", language: .japanese), "一般")
        XCTAssertEqual(L10n.text("General", language: .english), "General")
        XCTAssertEqual(L10n.text("Unknown server error", language: .japanese), "Unknown server error")
    }

    private func strings(for language: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private func window(_ identifier: CGWindowID, _ app: String, _ title: String = "Window") -> WindowInfo {
        WindowInfo(id: identifier, title: title, appName: app, appBundleIdentifier: nil,
                   pid: 123, thumbnail: nil, appIcon: nil)
    }
}

final class WindowArrangementTests: XCTestCase {
    private let visible = CGRect(x: -1440, y: 25, width: 1440, height: 850)
    private let current = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testHalvesTileVisibleFrameWithoutOverlapping() {
        let left = WindowAction.left.frame(current: current, visible: visible)
        let right = WindowAction.right.frame(current: current, visible: visible)
        XCTAssertEqual(left.minX, visible.minX)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(right.maxX, visible.maxX)
        XCTAssertEqual(left.height, visible.height)
        XCTAssertEqual(left.minY, visible.minY)
    }

    func testMaximizeUsesVisibleFrame() {
        XCTAssertEqual(WindowAction.maximize.frame(current: current, visible: visible), visible)
    }

    func testCenterPreservesSize() {
        let target = WindowAction.center.frame(current: current, visible: visible)
        XCTAssertEqual(target.size, current.size)
        XCTAssertEqual(target.midX, visible.midX)
        XCTAssertEqual(target.midY, visible.midY)
    }

    func testMovingToSmallDisplayClampsSize() {
        let destination = CGRect(x: 1800, y: -600, width: 600, height: 400)
        XCTAssertEqual(WindowAction.nextScreen.frame(current: current, visible: destination), destination)
    }

    func testCoordinateConversionSupportsDisplaysAboveAndBelowPrimary() {
        let upper = CGRect(x: -100, y: 1080, width: 1440, height: 900)
        XCTAssertEqual(WindowArranger.axFrame(upper, primaryHeight: 1080),
                       CGRect(x: -100, y: -900, width: 1440, height: 900))
        let lower = CGRect(x: 0, y: -900, width: 1440, height: 900)
        XCTAssertEqual(WindowArranger.axFrame(lower, primaryHeight: 1080).minY, 1080)
    }

    func testSelectsDisplayContainingMostOfWindow() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        XCTAssertEqual(WindowArranger.screenIndex(for: CGRect(x: 900, y: 100, width: 600, height: 400), frames: screens), 1)
    }

    func testAmbiguousOrStaleWindowNeverMatchesAnotherWindow() {
        XCTAssertNil(WindowArranger.matchingIndex(frame: current, candidates: [current, current]))
        XCTAssertNil(WindowArranger.matchingIndex(frame: current, candidates: [nil, visible]))
        XCTAssertNil(WindowArranger.matchingIndex(frame: current, candidates: []))
        XCTAssertEqual(WindowArranger.matchingIndex(frame: current, candidates: [nil, visible, current]), 2)
    }
}
