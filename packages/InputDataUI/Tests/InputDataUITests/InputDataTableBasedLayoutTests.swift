import XCTest
import AppKit
import TGUIKit
import GeneralRows
import TelegramTheme
@testable import InputDataUI

final class InputDataTableBasedLayoutTests: XCTestCase {
    private let leftColumnWidth: CGFloat = 90

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func text(_ value: String, font: NSFont = .normal(.text), lines: Int32 = 1) -> TextViewLayout {
        return TextViewLayout(.initialize(string: value, color: theme.colors.text, font: font), maximumNumberOfLines: lines, alwaysStaticItems: true)
    }

    private func textWidth(_ value: String, font: NSFont = .normal(.text)) -> CGFloat {
        let layout = text(value, font: font)
        layout.measure(width: .greatestFiniteMagnitude)
        return layout.layoutSize.width
    }

    private func makeRow(label: String? = "From", value: String = "Alexandra", font: NSFont = .medium(.text), lines: Int32 = 1, badge: String? = "send a gift", leadingSize: CGFloat? = 20, trailing: Bool = false, rightToCorner: Bool = false, callback: @escaping () -> Void = {}) -> InputDataTableBasedItem.Row {
        let leftView: ((NSView?) -> NSView)?
        if let leadingSize {
            leftView = { previous in
                let view = previous ?? View(frame: .zero)
                view.setFrameSize(NSMakeSize(leadingSize, leadingSize))
                return view
            }
        } else {
            leftView = nil
        }
        let rightView: ((NSView?) -> NSView?)?
        if trailing {
            rightView = { previous in
                let view = previous ?? View(frame: .zero)
                view.setFrameSize(NSMakeSize(20, 20))
                return view
            }
        } else {
            rightView = nil
        }
        var right = InputDataTableBasedItem.Row.Right(name: text(value, font: font, lines: lines), leftView: leftView, rightView: rightView, badge: badge.map { .init(text: $0, tooltipText: "Gift action", callback: callback) })
        right.rightToCorner = rightToCorner
        return InputDataTableBasedItem.Row(left: label.map { text($0) }, right: right)
    }

    private func update(_ view: InputDataTableBasedItemView.RowView, row: InputDataTableBasedItem.Row, width: CGFloat) {
        row.prepare(width: width)
        row.measure(width - leftColumnWidth, basic: width)
        view.setFrameSize(NSMakeSize(width, row.height))
        view.update(row, startRight: leftColumnWidth + 10, hasSeparator: true, context: nil)
        view.layoutSubtreeIfNeeded()
        view.layout()
    }

    private func makeView(_ row: InputDataTableBasedItem.Row, width: CGFloat) -> InputDataTableBasedItemView.RowView {
        let view = InputDataTableBasedItemView.RowView(frame: .zero)
        update(view, row: row, width: width)
        return view
    }

    private func primary(in view: NSView) throws -> InteractiveTextView {
        return try XCTUnwrap(view.subviews.compactMap { $0 as? InteractiveTextView }.first)
    }

    private func badge(in view: NSView) throws -> Control {
        return try XCTUnwrap(view.subviews.compactMap { $0 as? Control }.first { !($0 is InteractiveTextView) && !($0 is TextView) })
    }

    private func assertContained(_ view: NSView, file: StaticString = #filePath, line: UInt = #line) {
        for subview in view.subviews where !subview.frame.isEmpty {
            XCTAssertGreaterThanOrEqual(subview.frame.minX, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(subview.frame.minY, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(subview.frame.maxX, view.bounds.width, file: file, line: line)
            XCTAssertLessThanOrEqual(subview.frame.maxY, view.bounds.height, file: file, line: line)
        }
    }

    func testSenderKeepsItsNameWhenTheBadgeWouldLeaveTwentyPoints() throws {
        let row = makeRow()
        let badgeWidth = textWidth("send a gift", font: .normal(.small))
        let width = leftColumnWidth + 20 + InputDataTableBasedItem.Row.leftViewReserved + badgeWidth + 16 + 20
        let view = makeView(row, width: width)
        let primary = try primary(in: view)
        let badge = try badge(in: view)
        XCTAssertTrue(row.right.name.isPerfectSized)
        XCTAssertEqual(row.right.name.numberOfLines, 1)
        XCTAssertEqual(row.right.name.layoutSize.width, textWidth("Alexandra", font: .medium(.text)))
        XCTAssertGreaterThanOrEqual(badge.frame.minY, primary.frame.maxY + 6)
        XCTAssertEqual(badge.frame.minX, leftColumnWidth + 10)
        XCTAssertGreaterThan(row.height, (row.left?.layoutSize.height ?? 16) + 8 + row.right.name.layoutSize.height)
        assertContained(view)
        print("Sender layout: column=\(width - leftColumnWidth), primary=\(primary.frame), badge=\(badge.frame), height=\(row.height)")
    }

    func testValueDoesNotWrapDigitsToAccommodateConversionBadge() throws {
        let row = makeRow(label: "Value", value: "50", font: .normal(.text), lines: Int32.max, badge: "sell for 43 stars", leadingSize: 18)
        let badgeWidth = textWidth("sell for 43 stars", font: .normal(.small))
        let width = leftColumnWidth + 20 + InputDataTableBasedItem.Row.leftViewReserved + badgeWidth + 16 + textWidth("5")
        let view = makeView(row, width: width)
        let primary = try primary(in: view)
        let badge = try badge(in: view)
        XCTAssertEqual(row.right.name.numberOfLines, 1)
        XCTAssertEqual(row.right.name.layoutSize.width, textWidth("50"))
        XCTAssertGreaterThanOrEqual(badge.frame.minY, primary.frame.maxY + 6)
        assertContained(view)
        print("Value layout: column=\(width - leftColumnWidth), primary=\(primary.frame), badge=\(badge.frame), height=\(row.height)")
    }

    func testLocalizedBadgeWrapsWithinTheRightColumnAndRemainsClickable() throws {
        var clicks = 0
        let row = makeRow(value: "Александр", badge: "Отправить подарок пользователю", callback: { clicks += 1 })
        let view = makeView(row, width: 250)
        let primary = try primary(in: view)
        let badge = try badge(in: view)
        let badgeText = try XCTUnwrap(badge.subviews.compactMap { $0 as? TextView }.first)
        let layout = try XCTUnwrap(badgeText.textLayout)
        XCTAssertTrue(row.right.name.isPerfectSized)
        XCTAssertGreaterThan(layout.numberOfLines, 1)
        XCTAssertGreaterThanOrEqual(badge.frame.minY, primary.frame.maxY + 6)
        XCTAssertLessThanOrEqual(badge.frame.maxX, view.frame.width - 10)
        XCTAssertEqual(badge.appTooltip, "Gift action")
        badge.send(event: .Click)
        XCTAssertEqual(clicks, 1)
        assertContained(view)
        assertContained(badge)
    }

    func testResizeMovesBadgeBackInlineWithoutChangingTheNameOrAction() throws {
        var clicks = 0
        let row = makeRow(callback: { clicks += 1 })
        let view = makeView(row, width: 420)
        let primary = try primary(in: view)
        let badge = try badge(in: view)
        let inlineHeight = row.height
        XCTAssertEqual(badge.frame.minX, primary.frame.maxX + 6)
        XCTAssertEqual(badge.frame.midY, primary.frame.midY, accuracy: 0.5)
        update(view, row: row, width: 220)
        XCTAssertTrue(row.right.name.isPerfectSized)
        XCTAssertGreaterThanOrEqual(badge.frame.minY, primary.frame.maxY + 6)
        XCTAssertGreaterThan(row.height, inlineHeight)
        assertContained(view)
        update(view, row: row, width: 420)
        XCTAssertTrue(row.right.name.isPerfectSized)
        XCTAssertEqual(badge.frame.minX, primary.frame.maxX + 6)
        XCTAssertEqual(badge.frame.midY, primary.frame.midY, accuracy: 0.5)
        XCTAssertEqual(row.height, inlineHeight)
        XCTAssertTrue(try self.badge(in: view) === badge)
        badge.send(event: .Click)
        XCTAssertEqual(clicks, 1)
        assertContained(view)
    }

    func testRowsWithoutBadgesKeepTheirExistingSpacingAndHeight() throws {
        for label: String? in ["From", nil] {
            let row = makeRow(label: label, badge: nil, trailing: true)
            let view = makeView(row, width: 420)
            let primary = try primary(in: view)
            let startRight = label == nil ? 10 : leftColumnWidth + 10
            let contentWidth = label == nil ? 420 : 420 - leftColumnWidth
            XCTAssertEqual(row.right.name.constrainedWidth, contentWidth - 20 - InputDataTableBasedItem.Row.leftViewReserved - InputDataTableBasedItem.Row.rightViewReserved)
            XCTAssertEqual(row.height, (row.left?.layoutSize.height ?? 16) + 8 + row.right.name.layoutSize.height)
            XCTAssertEqual(primary.frame.minX, startRight + 25)
            XCTAssertEqual(primary.frame.midY, view.frame.midY, accuracy: 0.5)
            XCTAssertEqual(view.subviews.compactMap { $0 as? Control }.count, 2)
            assertContained(view)
        }
    }

    func testUnlabelledRowUsesItsFullWidthAndKeepsTheCornerAccessory() throws {
        let row = makeRow(label: nil, value: "50", font: .normal(.text), lines: Int32.max, badge: "In Sterne umwandeln und dem Guthaben hinzufügen", leadingSize: 18, trailing: true, rightToCorner: true)
        let view = makeView(row, width: 230)
        let primary = try primary(in: view)
        let badge = try badge(in: view)
        let accessory = try XCTUnwrap(view.subviews.first { $0.frame.size == NSMakeSize(20, 20) })
        XCTAssertEqual(row.right.name.constrainedWidth, 230 - 20 - InputDataTableBasedItem.Row.leftViewReserved - InputDataTableBasedItem.Row.rightViewReserved)
        XCTAssertEqual(row.right.name.numberOfLines, 1)
        XCTAssertEqual(badge.frame.minX, 10)
        XCTAssertGreaterThanOrEqual(badge.frame.minY, accessory.frame.maxY + 6)
        XCTAssertEqual(accessory.frame.maxX, view.frame.width - 8)
        XCTAssertEqual(primary.frame.midY, accessory.frame.midY, accuracy: 0.5)
        assertContained(view)
    }

    func testReusedRowRemovesBadgeAndRestoresSingleLineHeight() throws {
        let view = makeView(makeRow(badge: "Отправить подарок пользователю"), width: 220)
        let oldHeight = view.frame.height
        _ = try badge(in: view)
        let row = makeRow(value: "50", font: .normal(.text), badge: nil, leadingSize: nil)
        update(view, row: row, width: 220)
        XCTAssertLessThan(row.height, oldHeight)
        XCTAssertEqual(view.subviews.compactMap { $0 as? Control }.count, 2)
        XCTAssertEqual(try primary(in: view).frame.minX, leftColumnWidth + 10)
        assertContained(view)
    }
}
