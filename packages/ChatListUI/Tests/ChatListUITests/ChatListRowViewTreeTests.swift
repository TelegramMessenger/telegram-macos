import XCTest
import AppKit
import TGUIKit
@testable import ChatListUI

final class ChatListRowViewTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func makeRow() -> ChatListRowView {
        return ChatListRowView(frame: NSMakeRect(0, 0, 320, 70))
    }

    func testIdleRowHoldsOnlyTheSwipeContainer() {
        let row = makeRow()
        XCTAssertEqual(viewClassNames(row.subviews), ["ChatListDraggingContainerView"])
    }

    func testIdleContainerHoldsContentAndAvatarOnly() {
        let row = makeRow()
        let container = row.subviews.first
        XCTAssertEqual(viewClassNames(container?.subviews ?? []), ["View", "AvatarStoryControl"])
    }

    func testIdleRowViewCount() {
        XCTAssertEqual(viewTreeCount(makeRow()), 5)
    }

    private func selectionPlate(_ row: ChatListRowView) -> CALayer? {
        return row.subviews.first?.layer?.sublayers?.first(where: { $0 is SimpleLayer && $0.zPosition < 0 })
    }

    func testSelectionBackgroundIsAHiddenBottomLayerOfTheContainer() {
        let row = makeRow()
        let plate = selectionPlate(row)
        XCTAssertNotNil(plate)
        XCTAssertEqual(plate?.isHidden, true)
        XCTAssertEqual(plate?.cornerRadius, 14)
        XCTAssertEqual(plate?.masksToBounds, true)
        XCTAssertEqual(plate?.anchorPoint, .zero)
    }

    func testAvatarTakesTheFrameOfTheRemovedAvatarContainer() {
        let row = makeRow()
        let avatar = row.subviews.first?.subviews.last
        XCTAssertEqual(avatar?.frame, NSMakeRect(10, 10, 50, 50))
        XCTAssertEqual(viewClassNames(avatar?.subviews ?? []), ["AvatarControl"])
    }

    func testAvatarPassesClicksThroughUntilLayoutEnablesIt() {
        let row = makeRow()
        let avatar = row.subviews.first?.subviews.last as? Control
        XCTAssertNotNil(avatar)
        XCTAssertEqual(avatar?.userInteractionEnabled, false)
    }

    func testColorUpdateWithoutSelectionKeepsTheSelectionBackgroundHidden() {
        let row = makeRow()
        row.updateColors()
        XCTAssertEqual(viewTreeCount(row), 5)
        XCTAssertEqual(selectionPlate(row)?.isHidden, true)
    }

    func testSwipeWithoutActionsKeepsRevealContainersDetached() {
        let row = makeRow()
        let controller = ViewController()
        XCTAssertFalse(row.handleRevealSwipe(.right(.start(controller: controller)), cancelled: false))
        _ = row.handleRevealSwipe(.right(.swiping(delta: 40, controller: controller)), cancelled: false)
        _ = row.handleRevealSwipe(.left(.swiping(delta: 40, controller: controller)), cancelled: false)
        XCTAssertFalse(row.isRevealActive)
        XCTAssertEqual(viewClassNames(row.subviews), ["ChatListDraggingContainerView"])
    }

    func testRevealCompletionWithoutActionsKeepsRevealContainersDetached() {
        let row = makeRow()
        let controller = ViewController()
        _ = row.handleRevealSwipe(.right(.success(delta: 120, controller: controller)), cancelled: false)
        _ = row.handleRevealSwipe(.none, cancelled: false)
        row.closeReveal()
        XCTAssertEqual(viewClassNames(row.subviews), ["ChatListDraggingContainerView"])
    }
}
