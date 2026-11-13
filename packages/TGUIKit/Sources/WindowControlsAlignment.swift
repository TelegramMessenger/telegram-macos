import Cocoa

public extension NSView {
    var trafficLightsCenterY: CGFloat? {
        guard let window = window, !window.styleMask.contains(.fullScreen), let button = window.standardWindowButton(.closeButton), !button.isHidden, let buttonSuperview = button.superview else {
            return nil
        }
        let rect = convert(buttonSuperview.convert(button.frame, to: nil), from: nil)
        guard rect.maxX > 0, rect.minX < bounds.width else {
            return nil
        }
        return isFlipped ? rect.midY : bounds.height - rect.midY
    }
}

public extension TextView {
    var capCenterY: CGFloat? {
        guard let layout = textLayout, let line = layout.lines.first else {
            return nil
        }
        let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
        guard let run = runs.first else {
            return nil
        }
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let font = attributes[kCTFontAttributeName] else {
            return nil
        }
        let capHeight = CTFontGetCapHeight(font as! CTFont)
        let startY = (frame.height - layout.layoutSize.height) / 2
        return startY + line.frame.minY - capHeight / 2
    }
}
