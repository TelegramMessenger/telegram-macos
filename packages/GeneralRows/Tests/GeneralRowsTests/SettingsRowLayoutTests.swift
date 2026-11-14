import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import GeneralRows

final class SettingsRowLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    func testHeightDependsOnContentAndNotCardPosition() {
        for position in [GeneralViewType.firstItem, .innerItem, .lastItem, .singleItem] {
            for type in [GeneralInteractedType.none, .switchable(true), .nextContext("Default"), .selectable(true)] {
                let text = GeneralInteractedRowItem(NSMakeSize(400, 50), name: "Notifications", type: type, viewType: position).withSettingsLayout()
                XCTAssertEqual(text.height, 38)
                let icon = GeneralInteractedRowItem(NSMakeSize(400, 50), name: "Private Chats", icon: theme.icons.settingsGeneral, type: type, viewType: position).withSettingsLayout()
                XCTAssertEqual(icon.height, 43)
                let subtitle = GeneralInteractedRowItem(NSMakeSize(400, 50), name: "Private Chats", icon: theme.icons.settingsGeneral, description: "On", type: type, viewType: position).withSettingsLayout()
                XCTAssertEqual(subtitle.height, 53)
            }
        }
    }

    func testSidebarRetainsOriginalAssetsAndUsesNativeGeometry() {
        let icon = theme.icons.settingsGeneral
        let item = GeneralInteractedRowItem(NSMakeSize(240, 50), name: "General", icon: icon, type: .next, viewType: .singleItem).withSettingsLayout(.sidebar)
        XCTAssertTrue(item.thumb?.thumb === icon)
        XCTAssertEqual(item.height, 32)
        XCTAssertEqual(item.settingsIconSize, NSMakeSize(20, 20))
        let row = GeneralInteractedRowView(frame: NSMakeRect(0, 0, 240, item.height))
        row.set(item: item, animated: false)
        row.layout()
        XCTAssertEqual(row.containerView.frame.minX, 3)
        XCTAssertEqual(row.nameView.frame.minX, 37)
        XCTAssertTrue(row.nextView.isHidden)
        XCTAssertTrue(row.borderView.isHidden)
    }

    func testTextAndAccessoriesAreCenteredWithContentInsetSeparators() {
        let item = GeneralInteractedRowItem(NSMakeSize(400, 50), name: "Notifications", icon: theme.icons.settingsGeneral, type: .switchable(true), viewType: .firstItem).withSettingsLayout()
        let row = GeneralInteractedRowView(frame: NSMakeRect(0, 0, 400, item.height))
        row.set(item: item, animated: false)
        row.layout()
        XCTAssertEqual(row.nameView.frame.minX, 40)
        XCTAssertEqual(row.borderView.frame.minX, 10)
        XCTAssertEqual(row.borderView.frame.maxX, row.containerView.frame.width - 10)
        XCTAssertEqual(row.switchView!.frame.midY, row.containerView.frame.height / 2, accuracy: 0.5)
        XCTAssertEqual(row.nameView.frame.midY, row.containerView.frame.height / 2, accuracy: 0.5)
    }

    func testLongSubtitlesGrowAndNarrowRowsReserveAccessorySpace() {
        let item = GeneralInteractedRowItem(NSMakeSize(280, 50), name: "A long notification setting", icon: theme.icons.settingsGeneral, description: String(repeating: "A long explanation. ", count: 15), type: .nextContext("A long trailing value"), viewType: .singleItem).withSettingsLayout()
        XCTAssertGreaterThan(item.height, 53)
        XCTAssertGreaterThan(item.nameWidth, 0)
        XCTAssertLessThan(item.nameWidth, item.blockWidth - 50)
        let row = GeneralInteractedRowView(frame: NSMakeRect(0, 0, 280, item.height))
        row.set(item: item, animated: false)
        row.layout()
        XCTAssertLessThanOrEqual(row.nameView.frame.maxX + 10, row.textView!.frame.minX + 1)
        XCTAssertLessThanOrEqual(row.descriptionView!.frame.maxY + 9, row.containerView.frame.height)
    }

    func testSectionSpacingAndTextSizeControlUseSettingsMetrics() {
        let gap = GeneralRowItem(NSMakeSize(400, 20), height: 20, viewType: .separator).withSettingsLayout()
        XCTAssertEqual(gap.height, 10)
        let header = GeneralTextRowItem(NSMakeSize(400, 20), text: .plain("Message Notifications"), viewType: .textTopItem).withSettingsLayout()
        XCTAssertEqual(header.viewType.innerInset.left, 10)
        XCTAssertEqual(header.viewType.innerInset.bottom, 6)
        let slider = SelectSizeRowItem(NSMakeSize(400, 40), stableId: 1, current: 13, sizes: [11, 12, 13, 14, 15], hasMarkers: true, viewType: .singleItem, selectAction: { _ in }).withSettingsLayout()
        XCTAssertEqual(slider.height, 38)
    }

    func testUnrelatedRowsRetainTheirExistingPresentation() {
        let item = GeneralInteractedRowItem(NSMakeSize(400, 50), name: "General", viewType: .singleItem)
        XCTAssertNil(item.settingsPresentation)
        XCTAssertEqual(item.viewType.innerInset.left, 14)
        XCTAssertEqual(item.nameStyle.font.pointSize, 14)
    }
}
