import AppKit

final class ThemedScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        let expanded = knob.width > 6 || hitPart == .knob
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let width: CGFloat = expanded || highContrast ? 5 : 3
        let rect = NSMakeRect(knob.midX - width / 2, knob.minY, width, knob.height)
        let color = knobColor(expanded: expanded, highContrast: highContrast)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
    }

    func knobColor(expanded: Bool, highContrast: Bool) -> NSColor {
        guard highContrast else { return presentation.colors.grayText.withAlphaComponent(expanded ? 0.85 : 0.55) }
        let text = presentation.colors.text.withAlphaComponent(1)
        let background = surfaceBackgroundColor()
        if contrast(text, background) >= 4.5 { return text }
        return contrast(.white, background) >= contrast(.black, background) ? .white : .black
    }

    private func surfaceBackgroundColor() -> NSColor {
        var colors: [NSColor] = []
        var view = superview
        while let current = view {
            let color: NSColor?
            if let scroll = current as? NSScrollView {
                color = scroll.drawsBackground ? scroll.backgroundColor : nil
            } else if let themed = current as? View {
                color = themed.backgroundColor
            } else {
                color = current.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }
            }
            if let color = color?.usingColorSpace(.sRGB), color.alphaComponent > 0 {
                colors.append(color)
                if color.alphaComponent == 1 { break }
            }
            view = current.superview
        }
        var result = presentation.colors.background.usingColorSpace(.sRGB) ?? .white
        for color in colors.reversed() {
            let alpha = color.alphaComponent
            result = NSColor(srgbRed: color.redComponent * alpha + result.redComponent * (1 - alpha), green: color.greenComponent * alpha + result.greenComponent * (1 - alpha), blue: color.blueComponent * alpha + result.blueComponent * (1 - alpha), alpha: 1)
        }
        return result
    }

    private func contrast(_ foreground: NSColor, _ background: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            guard let color = color.usingColorSpace(.sRGB) else { return 0 }
            let components = [color.redComponent, color.greenComponent, color.blueComponent].map { value in
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
        }
        let first = luminance(foreground), second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

}

public extension NSScrollView {
    func applyThemedVerticalScroller() {
        guard hasVerticalScroller, !(verticalScroller is ThemedScroller) else { return }
        let size = verticalScroller?.controlSize ?? .regular
        let width = NSScroller.scrollerWidth(for: size, scrollerStyle: scrollerStyle)
        let scroller = ThemedScroller(frame: NSMakeRect(0, 0, width, max(frame.height, width + 1)))
        scroller.controlSize = size
        verticalScroller = scroller
    }
}
