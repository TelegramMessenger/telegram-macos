import XCTest
import Cocoa
import WidgetSandbox
import TelegramTheme
import ColorPalette
@testable import HTMLBubbles

final class WidgetThemeMappingTests: XCTestCase {
    private let palette = dayClassicPalette

    private func theme(incoming: Bool, fontSize: CGFloat = 14) -> WidgetTheme {
        return HTMLBubbleStyle.widgetTheme(chat: TelegramChatColors(palette, true), palette: palette, bubbled: true, fontSize: fontSize, incoming: incoming)
    }

    func testWidgetThemeTakesTheBubbleItSitsIn() {
        let chat = TelegramChatColors(palette, true)
        let incoming = theme(incoming: true)
        let outgoing = theme(incoming: false)
        XCTAssertEqual(incoming.params["bg_color"], hex(chat.bubbleBackgroundColor(true, true)))
        XCTAssertEqual(outgoing.params["bg_color"], hex(chat.bubbleBackgroundColor(false, true)))
        XCTAssertNotEqual(incoming.params["bg_color"], outgoing.params["bg_color"])
        XCTAssertEqual(outgoing.params["text_color"], hex(chat.textColor(false, true)))
        XCTAssertEqual(outgoing.params["section_bg_color"], outgoing.params["bg_color"])
        XCTAssertEqual(WidgetThemeMappingTests.keys.filter { outgoing.params[$0] == nil }, [])
        XCTAssertEqual(WidgetThemeMappingTests.keys.filter { incoming.params[$0] == nil }, [])
        XCTAssertEqual(outgoing.button.text, outgoing.params["bg_color"])
    }

    func testWidgetTextTokensFollowTheChatText() {
        let text = theme(incoming: true, fontSize: 17).text
        XCTAssertEqual(text.fontSize, 17)
        XCTAssertEqual(text.padding, "7px 11px")
        let lineHeight = text.lineHeight ?? 0
        XCTAssertGreaterThanOrEqual(lineHeight, 1)
        XCTAssertLessThanOrEqual(lineHeight, 3)
        XCTAssertEqual(theme(incoming: false, fontSize: 17).button.font, "500 17px system-ui")
    }

    private static let keys = [
        "bg_color", "text_color", "hint_color", "link_color", "button_color", "button_text_color",
        "secondary_bg_color", "accent_text_color", "subtitle_text_color", "destructive_text_color",
        "section_bg_color", "section_header_text_color", "section_separator_color", "header_bg_color", "bottom_bar_bg_color",
    ]

    private func hex(_ color: NSColor) -> String {
        let base = palette.background.usingColorSpace(.sRGB) ?? palette.background
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let alpha = rgb.alphaComponent
        let mix: (CGFloat, CGFloat) -> Int = { value, under in
            return Int((max(0, min(1, value * alpha + under * (1 - alpha))) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", mix(rgb.redComponent, base.redComponent), mix(rgb.greenComponent, base.greenComponent), mix(rgb.blueComponent, base.blueComponent))
    }
}
