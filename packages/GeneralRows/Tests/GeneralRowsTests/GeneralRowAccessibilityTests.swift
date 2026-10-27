import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import GeneralRows

final class GeneralRowAccessibilityTests: XCTestCase {
    private let width: CGFloat = 400
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        TGUIKitAccessibility.isEnabled = true
    }

    override func tearDown() {
        for window in windows {
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        super.tearDown()
    }

    private func makeRow(_ type: GeneralInteractedType, description: String? = nil, enabled: Bool = true, autoswitch: Bool = true, switchAction: (() -> Void)? = nil, action: @escaping () -> Void = {}) -> (GeneralInteractedRowItem, GeneralInteractedRowView) {
        let item = GeneralInteractedRowItem(NSMakeSize(width, 50), stableId: 0, name: "Notifications", description: description, type: type, viewType: .singleItem, action: action, enabled: enabled, autoswitch: autoswitch, switchAction: switchAction)
        _ = item.makeSize(width, oldWidth: 0)
        let row = GeneralInteractedRowView(frame: NSMakeRect(0, 0, width, item.height))
        row.set(item: item, animated: false)
        row.layout()
        let window = SnapshotWindow(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        windows.append(window)
        return (item, row)
    }

    func testNextRowIsOneLabeledButton() {
        let (_, row) = makeRow(.next)
        XCTAssertTrue(row.isAccessibilityElement())
        XCTAssertEqual(row.accessibilityRole(), .button)
        XCTAssertEqual(row.accessibilityLabel(), "Notifications")
        XCTAssertEqual(row.accessibilityChildren()?.count, 0)
        XCTAssertFalse(row.containerView.isAccessibilityElement())
        XCTAssertEqual(AccessibilityAudit.audit(row), [])
    }

    func testContextRowReadsItsValueAndDescription() {
        let (_, row) = makeRow(.context("Everybody"), description: "Who can see your phone number")
        XCTAssertEqual(row.accessibilityValue() as? String, "Everybody")
        XCTAssertEqual(row.accessibilityHelp(), "Who can see your phone number")
    }

    func testSwitchRowIsACheckboxThatToggles() {
        var calls = 0
        let (item, row) = makeRow(.switchable(false), action: { calls += 1 })
        XCTAssertEqual(row.accessibilityRole(), .checkBox)
        XCTAssertEqual(row.accessibilityValue() as? NSNumber, 0)
        XCTAssertTrue(row.accessibilityPerformPress())
        let deadline = Date().addingTimeInterval(2)
        while calls == 0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(item.accessibilityToggleState, true)
        XCTAssertEqual(row.accessibilityValue() as? NSNumber, 1)
        XCTAssertEqual(AccessibilityAudit.audit(row), [])
    }

    func testSelectableRowIsARadioButton() {
        let (_, row) = makeRow(.selectable(true))
        XCTAssertEqual(row.accessibilityRole(), .radioButton)
        XCTAssertEqual(row.accessibilityValue() as? NSNumber, 1)
    }

    func testDisabledRowIsReportedDisabled() {
        var calls = 0
        let (_, row) = makeRow(.next, enabled: false, action: { calls += 1 })
        XCTAssertFalse(row.isAccessibilityEnabled())
        _ = row.accessibilityPerformPress()
        XCTAssertEqual(calls, 0)
    }

    func testDirectSwitchActivationUpdatesTheRowAtRest() {
        var calls = 0
        let committed = expectation(description: "Switch settled")
        let (item, row) = makeRow(.switchable(false), action: {
            calls += 1
            committed.fulfill()
        })
        row.switchView?.performToggle()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(item.accessibilityToggleState, false)
        wait(for: [committed], timeout: 2)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(item.accessibilityToggleState, true)
        XCTAssertEqual(row.accessibilityValue() as? NSNumber, 1)
    }

    func testDedicatedSwitchActionKeepsRowNavigationSeparate() {
        var navigations = 0
        let committed = expectation(description: "Dedicated switch settled")
        let (item, row) = makeRow(.switchable(false), switchAction: { committed.fulfill() }, action: { navigations += 1 })
        row.invokeAction(item)
        XCTAssertEqual(navigations, 1)
        XCTAssertEqual(row.switchView?.isOn, false)
        row.switchView?.performToggle()
        wait(for: [committed], timeout: 2)
        XCTAssertEqual(navigations, 1)
        XCTAssertEqual(row.switchView?.isOn, true)
    }

    func testOwnerControlledRowDoesNotCommitBeforeConfirmation() {
        let requested = expectation(description: "Owner change requested")
        let (item, row) = makeRow(.switchable(false), autoswitch: false, action: { requested.fulfill() })
        row.invokeAction(item)
        XCTAssertEqual(item.accessibilityToggleState, false)
        wait(for: [requested], timeout: 2)
        XCTAssertEqual(row.switchView?.isOn, false)
        XCTAssertEqual(item.accessibilityToggleState, false)
    }

    func testReusingARowCancelsTheOldAction() {
        var calls = 0
        let (item, row) = makeRow(.switchable(false), action: { calls += 1 })
        row.invokeAction(item)
        let replacement = GeneralInteractedRowItem(NSMakeSize(width, 50), stableId: 1, name: "Replacement", type: .switchable(false), viewType: .singleItem)
        row.set(item: replacement, animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(row.switchView?.isOn, false)
    }

}
