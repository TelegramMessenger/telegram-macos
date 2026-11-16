import Cocoa
import TGUIKit
private let quoteIcon = referenceSharedQuoteIcon()

final class ReferenceIconQuoteLayer: SimpleLayer {
    var blockQuotes: [TextViewBlockQuote] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    override func draw(in ctx: CGContext) {
        for blockQuote in blockQuotes {
            let radius: CGFloat = 3.0
            let lineWidth: CGFloat = 3.0


            let blockFrame = blockQuote.frame
            let blockColor = blockQuote.isCode ? blockQuote.colors.tertiary ?? blockQuote.colors.main : blockQuote.colors.main
            let tintColor = blockQuote.colors.main
            let secondaryTintColor = blockQuote.colors.secondary
            let tertiaryTintColor = blockQuote.colors.tertiary


            var bg = blockColor
            if blockQuote.isCode {
                bg = bg.darker(amount: 0.5).withAlphaComponent(0.5)
            } else {
                bg = bg.withAlphaComponent(0.1)
            }
            ctx.setFillColor(bg.cgColor)
            ctx.addPath(CGPath(roundedRect: blockFrame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()

            ctx.setFillColor(tintColor.cgColor)

            if !blockQuote.isCode {
                let iconSize = quoteIcon.backingSize
                let quoteRect = CGRect(origin: CGPoint(x: blockFrame.maxX - 4.0 - iconSize.width, y: blockFrame.minY + 4.0), size: iconSize)
                ctx.saveGState()
                ctx.translateBy(x: quoteRect.midX, y: quoteRect.midY)
                ctx.scaleBy(x: 1.0, y: -1.0)
                ctx.translateBy(x: -quoteRect.midX, y: -quoteRect.midY)
                ctx.clip(to: quoteRect, mask: quoteIcon)
                ctx.fill(quoteRect)
                ctx.restoreGState()
                ctx.resetClip()
            }


            drawBlockQuoteLine(ctx: ctx, blockFrame: blockFrame, radius: radius, lineWidth: lineWidth, tintColor: tintColor, secondaryTintColor: secondaryTintColor, tertiaryTintColor: tertiaryTintColor)

            if let header = blockQuote.header {
                let headerHeight = blockQuote.headerInset + 2
                ctx.setFillColor(blockQuote.colors.main.withAlphaComponent(0.2).cgColor)
                let rect = NSMakeRect(blockFrame.minX, blockFrame.minY, blockFrame.width, headerHeight)
                ctx.drawRoundedRect(rect: rect, topLeftRadius: radius, topRightRadius: radius)
                header.1.draw(CGRect(x: blockFrame.minX + 8, y: blockFrame.minY + (headerHeight - header.0.size.height) / 2 - 1, width: header.0.size.width, height: header.0.size.height), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
                let image = TelegramThemeHooks.shared.image(.iconCopyCode).precomposed(blockQuote.colors.main, flipVertical: true)
                ctx.draw(image, in: CGRect(origin: NSMakePoint(blockFrame.width - image.backingSize.width - 3, blockFrame.minY + (headerHeight - image.backingSize.height) / 2), size: image.backingSize))
            }
        }
    }
}
