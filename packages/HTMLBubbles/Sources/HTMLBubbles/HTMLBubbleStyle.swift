import Cocoa
import TGUIKit
import ColorPalette
import TelegramTheme
import WidgetSandbox

public struct HTMLBubbleAppearance: Equatable {
    public let key: String
    public let css: String
    public let dark: Bool
    public let incoming: Bool
    var widgetTheme: WidgetTheme = WidgetTheme()
    var textSelectionColor: NSColor?

    public static func == (lhs: HTMLBubbleAppearance, rhs: HTMLBubbleAppearance) -> Bool {
        return lhs.key == rhs.key
    }
}

public enum HTMLBubbleStyle {
    private static let lock = NSLock()
    private static var cache: [String: HTMLBubbleAppearance] = [:]

    public static func appearance(theme: TelegramPresentationTheme, incoming: Bool) -> HTMLBubbleAppearance {
        let bubbled = theme.bubbled
        let palette = theme.colors
        let text = theme.chat.textColor(incoming, bubbled)
        let gray = theme.chat.grayText(incoming, bubbled)
        let link = theme.chat.linkColor(incoming, bubbled)
        let fontSize = Int(theme.fontSize.rounded())

        let base = [
            "html, body { margin: 0; padding: 0; }",
            "body { font-family: -apple-system; font-size: \(fontSize)px; line-height: 1.3; color: \(css(text)); }",
            "p { margin: 0 0 8px 0; }",
            "h1, h2, h3, h4 { margin: 4px 0 6px 0; line-height: 1.2; }",
            "h1 { font-size: 22px; } h2 { font-size: 19px; } h3 { font-size: 17px; } h4 { font-size: 15px; }",
            "ul, ol { margin: 4px 0 8px 0; padding-left: 22px; }",
            "li { margin: 2px 0; }",
            "blockquote { margin: 4px 0 8px 0; padding: 2px 0 2px 10px; border-left: 3px solid \(css(link)); color: \(css(gray)); }",
            "code { font-family: ui-monospace; font-size: 13px; background-color: \(css(text, alpha: 0.08)); padding: 1px 4px; border-radius: 4px; }",
            "pre { font-family: ui-monospace; font-size: 12.5px; line-height: 1.45; background-color: \(css(text, alpha: 0.07)); padding: 8px 10px; border-radius: 8px; margin: 4px 0 8px 0; white-space: pre-wrap; }",
            "pre code { background-color: transparent; padding: 0; font-size: 12.5px; }",
            "a { color: \(css(link)); text-decoration: none; }",
            "a:hover { text-decoration: underline; }",
            "hr { border: 0; border-top: 1px solid \(css(gray, alpha: 0.4)); margin: 8px 0; height: 0; }",
            "table { border-collapse: collapse; }",
            "img { vertical-align: middle; }",
            "mark { background-color: #ffe066; color: #1c1c1e; padding: 0 2px; border-radius: 3px; }",
            "small { font-size: 12px; }",
            "body > *:first-child { margin-top: 0; }",
            "body > *:last-child { margin-bottom: 0; }",
            ".widget > *:first-child { margin-top: 0; }",
            ".widget > *:last-child { margin-bottom: 0; }",
        ].joined(separator: "\n")

        let tokens: [(String, String)] = [
            ("BLUEH", css(palette.accent.blended(withFraction: 0.15, of: .black) ?? palette.accent)),
            ("BLUE", css(palette.accent)),
            ("CARD", css(palette.background)),
            ("BORDER", css(palette.border)),
            ("FG", css(palette.text)),
            ("MUTED", css(palette.grayText)),
            ("SEP", css(palette.border)),
            ("GREEN", css(palette.greenUI)),
            ("RED", css(palette.redUI)),
            ("ORANGE", css(palette.peerAvatarOrangeTop)),
            ("PURPLE", css(palette.peerAvatarVioletTop)),
            ("TEAL", css(palette.peerAvatarCyanTop)),
            ("KBD", css(palette.background)),
        ]
        let widgetTheme = self.widgetTheme(chat: theme.chat, palette: theme.colors, bubbled: theme.bubbled, fontSize: theme.fontSize, incoming: incoming)
        let widgetKey = widgetTheme.params.sorted { $0.key < $1.key }.map { $0.value }.joined(separator: ",")
        let selectionBackground = flatten(theme.chat.bubbleBackgroundColor(incoming, bubbled), over: palette.background)
        let selectionColor = selectionOverlayColor(theme.chat.selectText(incoming, bubbled), over: selectionBackground)
        let key = css(selectionColor, alpha: selectionColor.alphaComponent) + "|" + tokens.map { $0.1 }.joined(separator: ",") + "|\(css(text))|\(css(gray))|\(css(link))|\(theme.fontSize)|\(palette.isDark)|\(incoming)|\(widgetKey)"

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var kit = kitTemplate
        for (token, value) in tokens {
            kit = kit.replacingOccurrences(of: token, with: value)
        }
        let appearance = HTMLBubbleAppearance(key: key, css: base + "\n" + kit, dark: palette.isDark, incoming: incoming, widgetTheme: widgetTheme, textSelectionColor: selectionColor)

        lock.lock()
        if cache.count > 32 {
            cache.removeAll()
        }
        cache[key] = appearance
        lock.unlock()
        return appearance
    }

    static let widgetTextPadding = "7px 11px"

    static func widgetLineHeight(fontSize: CGFloat) -> Double {
        let font = NSFont.systemFont(ofSize: fontSize)
        let height = (font.ascender - font.descender + font.leading) / max(fontSize, 1)
        return min(max((Double(height) * 1000).rounded() / 1000, 1), 3)
    }

    static func widgetTheme(chat: TelegramChatColors, palette: ColorPalette, bubbled: Bool, fontSize: CGFloat, incoming: Bool) -> WidgetTheme {
        let background = chat.bubbleBackgroundColor(incoming, bubbled)
        let opaque = flatten(background, over: palette.background)
        let bg = hex(opaque, over: opaque)
        let text = hex(chat.textColor(incoming, bubbled), over: opaque)
        let hint = hex(chat.grayText(incoming, bubbled), over: opaque)
        let link = chat.linkColor(incoming, bubbled)
        let linkHex = hex(link, over: opaque)
        let accent = incoming || !bubbled ? palette.accent : chat.activityColor(incoming, bubbled)
        let button = hex(accent, over: opaque)
        let buttonText = incoming || !bubbled ? hex(palette.underSelectedColor, over: palette.accent) : bg
        let separator = incoming || !bubbled ? palette.border : chat.grayText(incoming, bubbled).withAlphaComponent(0.3)
        let params: [String: String] = [
            "bg_color": bg,
            "text_color": text,
            "hint_color": hint,
            "link_color": linkHex,
            "button_color": button,
            "button_text_color": buttonText,
            "secondary_bg_color": hex(link.withAlphaComponent(0.1), over: opaque),
            "accent_text_color": linkHex,
            "subtitle_text_color": hint,
            "destructive_text_color": hex(chat.redUI(incoming, bubbled), over: opaque),
            "section_bg_color": bg,
            "section_header_text_color": hint,
            "section_separator_color": hex(separator, over: opaque),
            "header_bg_color": bg,
            "bottom_bar_bg_color": bg,
        ]
        let tokens = WidgetButtonTokens(bg: button, text: buttonText, radius: "10px", font: "500 \(Int(fontSize.rounded()))px system-ui")
        let textTokens = WidgetTextTokens(fontSize: Double(fontSize), lineHeight: widgetLineHeight(fontSize: fontSize), padding: widgetTextPadding)
        return WidgetTheme(colorScheme: palette.isDark ? .dark : .light, params: params, button: tokens, text: textTokens)
    }

    static func selectionOverlayColor(_ selection: NSColor, over background: NSColor) -> NSColor {
        let color = selection.usingColorSpace(.sRGB) ?? selection
        guard color.alphaComponent >= 1 else {
            return color
        }
        let base = background.usingColorSpace(.sRGB) ?? background
        let target = [color.redComponent, color.greenComponent, color.blueComponent]
        let under = [base.redComponent, base.greenComponent, base.blueComponent]
        let alpha = zip(target, under).map { value, background -> CGFloat in
            if value < background { return (background - value) / max(background, .ulpOfOne) }
            return (value - background) / max(1 - background, .ulpOfOne)
        }.max() ?? 0
        guard alpha > 0 else { return .clear }
        let components = zip(target, under).map { value, background in
            min(1, max(0, (value - background * (1 - alpha)) / alpha))
        }
        return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: alpha)
    }

    private static func flatten(_ color: NSColor, over background: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let base = background.usingColorSpace(.sRGB) ?? background
        let alpha = rgb.alphaComponent
        let mix: (CGFloat, CGFloat) -> CGFloat = { value, under in
            return max(0, min(1, value * alpha + under * (1 - alpha)))
        }
        return NSColor(srgbRed: mix(rgb.redComponent, base.redComponent), green: mix(rgb.greenComponent, base.greenComponent), blue: mix(rgb.blueComponent, base.blueComponent), alpha: 1)
    }

    private static func hex(_ color: NSColor, over background: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let base = background.usingColorSpace(.sRGB) ?? background
        let alpha = rgb.alphaComponent
        let mix: (CGFloat, CGFloat) -> Int = { value, under in
            return Int((max(0, min(1, value * alpha + under * (1 - alpha))) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", mix(rgb.redComponent, base.redComponent), mix(rgb.greenComponent, base.greenComponent), mix(rgb.blueComponent, base.blueComponent))
    }

    private static func css(_ color: NSColor, alpha: CGFloat? = nil) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        let a = alpha ?? rgb.alphaComponent
        return "rgba(\(r),\(g),\(b),\(String(format: "%.3f", a)))"
    }

    private static let kitTemplate = [
        ".card { background-color: CARD; border: 1px solid BORDER; border-radius: 14px; color: FG; }",
        ".pad { padding: 12px 14px; }",
        ".panel { background-color: rgba(127,127,127,0.12); border-radius: 10px; padding: 8px 10px; }",
        ".fg { color: FG; } .muted { color: MUTED; } .small { font-size: 12px; } .tiny { font-size: 11px; }",
        ".caps { font-size: 11px; font-weight: 700; text-transform: uppercase; color: MUTED; }",
        ".row { display: flex; align-items: center; } .between { justify-content: space-between; }",
        ".grow { flex-grow: 1; } .center { text-align: center; } .right { text-align: right; }",
        ".sep { border-top: 1px solid SEP; } .nowrap { white-space: nowrap; }",
        ".t-blue { color: BLUE; } .t-green { color: GREEN; } .t-red { color: RED; } .t-orange { color: ORANGE; } .t-purple { color: PURPLE; } .t-teal { color: TEAL; }",
        ".badge { display: inline-block; padding: 1px 8px; border-radius: 9px; font-size: 11px; font-weight: 700; background-color: rgba(127,127,127,0.18); }",
        ".badge.blue { background-color: rgba(0,122,255,0.16); color: BLUE; } .badge.green { background-color: rgba(52,199,89,0.18); color: GREEN; }",
        ".badge.red { background-color: rgba(255,59,48,0.16); color: RED; } .badge.orange { background-color: rgba(255,149,0,0.18); color: ORANGE; }",
        ".badge.purple { background-color: rgba(175,82,222,0.16); color: PURPLE; }",
        ".btn { display: inline-block; padding: 6px 14px; border-radius: 9px; font-weight: 600; text-align: center; text-decoration: none; background-color: rgba(127,127,127,0.16); color: FG; }",
        ".btn:hover { background-color: rgba(127,127,127,0.28); text-decoration: none; }",
        ".btn.primary { background-color: BLUE; color: #ffffff; } .btn.primary:hover { background-color: BLUEH; }",
        ".btn.success { background-color: GREEN; color: #ffffff; } .btn.danger { background-color: rgba(255,59,48,0.14); color: RED; }",
        ".btn.success:hover { background-color: rgba(52,199,89,0.85); } .btn.danger:hover { background-color: rgba(255,59,48,0.24); }",
        ".chip { display: inline-block; padding: 3px 12px; border-radius: 14px; border: 1px solid BLUE; color: BLUE; margin: 2px 4px 2px 0; text-decoration: none; }",
        ".chip:hover { background-color: rgba(127,127,127,0.12); text-decoration: none; }",
        ".av { display: inline-block; width: 24px; height: 24px; border-radius: 12px; text-align: center; line-height: 24px; color: #ffffff; font-size: 10px; font-weight: 700; background-color: #8e8e93; }",
        ".bar { height: 8px; border-radius: 4px; background-color: rgba(127,127,127,0.22); }",
        ".bar > div { height: 8px; border-radius: 4px; background-color: BLUE; }",
        ".card pre, .panel pre { background-color: rgba(127,127,127,0.13); } .card code, .panel code { background-color: rgba(127,127,127,0.15); }",
        ".card pre code, .panel pre code { background-color: transparent; }",
        "[data-action] { cursor: pointer; }",
        "button { font-size: 14px; font-weight: 600; padding: 5px 13px; border: 0; border-radius: 9px; background-color: rgba(127,127,127,0.16); color: FG; text-align: center; }",
        "button:hover { background-color: rgba(127,127,127,0.28); }",
        "button.primary { background-color: BLUE; color: #ffffff; } button.primary:hover { background-color: BLUEH; }",
        "button:active, .btn:active { background-color: rgba(127,127,127,0.40); } button.primary:active, .btn.primary:active { background-color: BLUEH; }",
        ".lc-script-error { margin-top: 6px; padding: 3px 8px; border-radius: 7px; font-size: 11.5px; line-height: 1.3; background-color: rgba(255,149,0,0.16); color: ORANGE; }",
        "kbd { font-family: ui-monospace; font-size: 12px; padding: 0 6px; border-radius: 5px; border: 1px solid BORDER; border-bottom-width: 2px; background-color: KBD; color: FG; }",
    ].joined(separator: "\n")
}
