import Cocoa
import XCTest

extension NSRect {
    func focus(_ size: NSSize) -> NSRect {
        return NSMakeRect(CGFloat(round((self.width - size.width) / 2.0)), CGFloat(round((self.height - size.height) / 2.0)), size.width, size.height)
    }
}

enum ChatInputTextView {
    __TEXT_FRAME__
}

final class InputAnchorTests: XCTestCase {
    func testWithoutAHoldTheTextSitsWhereItAlwaysHas() {
        XCTAssertEqual(ChatInputTextView.textFrame(in: NSMakeSize(300, 34), textHeight: 18, anchor: nil), NSMakeRect(0, 8, 300, 18))
        XCTAssertEqual(ChatInputTextView.textFrame(in: NSMakeSize(300, 54), textHeight: 54, anchor: nil), NSMakeRect(0, 0, 300, 54))
        XCTAssertEqual(ChatInputTextView.textFrame(in: NSMakeSize(300, 34), textHeight: 18, anchor: 34), NSMakeRect(0, 8, 300, 18))
    }

    func testAHeldFieldKeepsTheTextWhereItsOwnHeightWouldPutIt() {
        XCTAssertEqual(ChatInputTextView.textFrame(in: NSMakeSize(300, 54), textHeight: 18, anchor: 34), NSMakeRect(0, 8, 300, 18))
        XCTAssertEqual(ChatInputTextView.textFrame(in: NSMakeSize(300, 72), textHeight: 36, anchor: 36), NSMakeRect(0, 0, 300, 36))
        XCTAssertEqual(ChatInputTextView.textFrame(in: NSMakeSize(300, 72), textHeight: 18, anchor: 34).minY, ChatInputTextView.textFrame(in: NSMakeSize(300, 34), textHeight: 18, anchor: nil).minY)
    }
}
