import AppKit
import QuartzCore
import TGUIKit

final class ChatAIRewriteAnimation {
    private struct Word {
        let range: NSRange
        let layer: CALayer
        let tint: CALayer
        let blur: NSObject?
    }

    private weak var field: NSView?
    private weak var send: ImageButton?
    private weak var text: NSTextView?
    private let light: ChatAIRewriteLight
    private let plane: ChatAIRewritePlane
    private var ticker: ChatDictationRevealTicker?
    private let start = CACurrentMediaTime()
    private var revealStart: CFTimeInterval?
    private var words: [Word] = []
    private var originalCaretColor: NSColor?
    private let hiddenCaretViews = NSHashTable<NSView>.weakObjects()
    private let wordTint: NSColor
    private var dissolvedText: CALayer?

    init?(field: NSView, send: ImageButton, text: NSTextView) {
        guard let fieldLayer = field.layer, let fieldParent = fieldLayer.superlayer,
              let buttonLayer = send.layer, let icon = send.imageView.image, let window = text.window else {
            return nil
        }
        self.field = field
        self.send = send
        self.text = text
        let appearance = text.effectiveAppearance
        let dark: Bool
        if #available(macOS 10.14, *) {
            dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        } else {
            dark = appearance.name == .vibrantDark
        }
        light = ChatAIRewriteLight(dark: dark)
        wordTint = dark ? NSColor(srgbRed: 0.18, green: 0.63, blue: 1, alpha: 1)
                        : NSColor(srgbRed: 0.05, green: 0.39, blue: 0.87, alpha: 1)
        plane = ChatAIRewritePlane(image: icon, scale: window.backingScaleFactor)
        fieldParent.insertSublayer(light.layer, below: fieldLayer)
        buttonLayer.addSublayer(plane.layer)
        send.imageView.layer?.opacity = 0
        originalCaretColor = text.insertionPointColor
        text.insertionPointColor = .clear
        step()
        ticker = ChatDictationRevealTicker(view: text, tick: { [weak self] in
            self?.step()
        })
    }

    deinit {
        stop()
    }

    var remainingProcessingTime: Double {
        max(0, ChatAIRewriteMotion.minimumProcessing - (CACurrentMediaTime() - start))
    }

    func dissolveDraft() {
        guard let text, let parent = text.layer,
              let layout = text.layoutManager, let container = text.textContainer else { return }
        let visible = text.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible.offsetBy(dx: -text.textContainerOrigin.x, dy: -text.textContainerOrigin.y), in: container)
        guard let image = image(of: glyphs, in: visible) else { return }
        let layer = CALayer()
        layer.contents = image
        layer.frame = visible
        layer.opacity = 0
        parent.addSublayer(layer)
        dissolvedText = layer
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.28
        layer.add(fade, forKey: "rewriteDissolve")
        let lift = CABasicAnimation(keyPath: "position.y")
        lift.fromValue = layer.position.y
        lift.toValue = layer.position.y + (text.isFlipped ? -5 : 5)
        lift.duration = fade.duration
        layer.add(lift, forKey: "rewriteLift")
        if let blur = ee2_makeBlurFilter() {
            blur.setValue(5.0, forKey: "inputRadius")
            layer.filters = [blur]
            let defocus = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            defocus.fromValue = 0
            defocus.toValue = 5
            defocus.duration = fade.duration
            layer.add(defocus, forKey: "rewriteDefocus")
        }
    }

    func revealWords() {
        defer {
            revealStart = CACurrentMediaTime()
            step()
        }
        guard let text, let layout = text.layoutManager, let container = text.textContainer,
              let parent = text.layer else { return }
        layout.ensureLayout(for: container)
        let origin = text.textContainerOrigin
        let visible = text.visibleRect
        let textLength = text.string.utf16.count
        let visibleGlyphs = layout.glyphRange(forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let visibleText = layout.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let pattern = try! NSRegularExpression(pattern: "\\S+")
        for match in pattern.matches(in: text.string, range: NSIntersectionRange(visibleText, NSRange(location: 0, length: textLength))).prefix(160) {
            let glyphs = layout.glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            layout.enumerateLineFragments(forGlyphRange: glyphs) { [self] _, _, _, lineRange, _ in
                let lineGlyphs = NSIntersectionRange(glyphs, lineRange)
                guard lineGlyphs.length > 0 else { return }
                let rect = layout.boundingRect(forGlyphRange: lineGlyphs, in: container).offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -4, dy: -3).integral
                guard rect.intersects(visible), let image = image(of: lineGlyphs, in: rect) else { return }
                let layer = CALayer()
                layer.frame = rect
                layer.contents = image
                layer.opacity = 0

                let mask = CALayer()
                mask.frame = layer.bounds
                mask.contents = image
                let tint = CALayer()
                tint.frame = layer.bounds
                tint.backgroundColor = wordTint.cgColor
                tint.mask = mask
                layer.addSublayer(tint)

                let blur = ee2_makeBlurFilter()
                if let blur {
                    blur.setValue(5.0, forKey: "inputRadius")
                    layer.filters = [blur]
                }
                parent.insertSublayer(layer, below: dissolvedText)
                let range = layout.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
                words.append(Word(range: range, layer: layer, tint: tint, blur: blur))
            }
        }
        for word in words {
            layout.addTemporaryAttribute(.foregroundColor, value: NSColor.clear, forCharacterRange: word.range)
        }
    }

    func stop() {
        guard let originalCaretColor else { return }
        self.originalCaretColor = nil
        ticker?.invalidate()
        ticker = nil
        clearWords()
        dissolvedText?.removeFromSuperlayer()
        dissolvedText = nil
        light.layer.removeFromSuperlayer()
        plane.layer.removeFromSuperlayer()
        send?.imageView.layer?.opacity = 1
        text?.insertionPointColor = originalCaretColor
        hiddenCaretViews.allObjects.forEach { $0.isHidden = false }
        hiddenCaretViews.removeAllObjects()
    }

    private func hideCaretIndicators() {
        if #available(macOS 14.0, *), let text {
            for indicator in text.subviews where indicator is NSTextInsertionIndicator && !indicator.isHidden {
                hiddenCaretViews.add(indicator)
                indicator.isHidden = true
            }
        }
    }

    private func clearWords() {
        let length = text?.string.utf16.count ?? 0
        for word in words {
            let range = NSIntersectionRange(word.range, NSRange(location: 0, length: length))
            if range.length > 0 {
                text?.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            }
            word.layer.removeFromSuperlayer()
        }
        words.removeAll()
    }

    private func step() {
        guard originalCaretColor != nil, let field, let send else { return }
        hideCaretIndicators()
        let now = CACurrentMediaTime()
        let elapsed = now - start
        let reveal = revealStart.map { now - $0 }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        light.update(frame: field.frame, cornerRadius: field.layer?.cornerRadius ?? 20, elapsed: elapsed, revealElapsed: reveal)
        plane.update(frame: send.bounds, elapsed: elapsed, revealElapsed: reveal)
        if let reveal {
            if reveal >= ChatAIRewriteMotion.revealDuration {
                clearWords()
                dissolvedText?.removeFromSuperlayer()
                dissolvedText = nil
            } else {
                for (index, word) in words.enumerated() {
                    let progress = ChatAIRewriteMotion.wordProgress(index: index, count: words.count, elapsed: reveal)
                    word.layer.opacity = Float(sqrt(progress))
                    word.tint.opacity = Float(1 - ChatAIRewriteMotion.ease((progress - 0.20) / 0.80))
                    if word.blur != nil {
                        word.layer.setValue(5.0 * (1 - progress), forKeyPath: "filters.gaussianBlur.inputRadius")
                    }
                }
            }
        }
        CATransaction.commit()
    }

    private func image(of glyphs: NSRange, in rect: NSRect) -> CGImage? {
        guard let text, let layout = text.layoutManager, rect.width > 0, rect.height > 0 else { return nil }
        let scale = text.window?.backingScaleFactor ?? 2
        guard let context = CGContext(data: nil, width: Int(ceil(rect.width * scale)), height: Int(ceil(rect.height * scale)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: text.textContainerOrigin.x - rect.minX, y: text.textContainerOrigin.y - rect.minY))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
