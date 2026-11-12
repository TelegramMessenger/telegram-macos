import Foundation

#if os(iOS) || os(visionOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

public struct MTMathRenderedFormula {
    public let image: MTImage
    public let size: CGSize
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat

    public init(image: MTImage, size: CGSize, width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        self.image = image
        self.size = size
        self.width = width
        self.ascent = ascent
        self.descent = descent
    }
}

public enum MTMathRenderer {
    static let maximumRenderedDimension = CGFloat(8192)
    static let maximumRenderedArea = CGFloat(4096 * 1024)

    public static func render(latex: String, fontSize: CGFloat, textColor: MTColor, mode: MTMathUILabelMode = .display) -> MTMathRenderedFormula? {
        var error: NSError?
        guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error), error == nil else {
            return nil
        }
        return render(mathList: mathList, fontSize: fontSize, textColor: textColor, mode: mode)
    }

    public static func renderForAuthoring(latex: String, fontSize: CGFloat, textColor: MTColor, mode: MTMathUILabelMode = .display) -> MTMathRenderedFormula? {
        guard let mathList = MTMathListBuilder.buildForAuthoring(fromString: latex) else {
            return nil
        }
        return render(mathList: mathList, fontSize: fontSize, textColor: textColor, mode: mode)
    }

    private static func render(mathList: MTMathList, fontSize: CGFloat, textColor: MTColor, mode: MTMathUILabelMode) -> MTMathRenderedFormula? {
        guard let font = MTFontManager.fontManager.defaultFont?.copy(withSize: fontSize) else {
            return nil
        }
        let style: MTLineStyle
        switch mode {
        case .display:
            style = .display
        case .text:
            style = .text
        }

        guard let displayList = MTTypesetter.createLineForMathList(mathList, font: font, style: style) else {
            return nil
        }

        displayList.textColor = textColor

        let width = max(1.0, ceil(displayList.width))
        let height = max(1.0, ceil(displayList.ascent + displayList.descent))
        guard width.isFinite, height.isFinite, width <= maximumRenderedDimension, height <= maximumRenderedDimension, width * height <= maximumRenderedArea else {
            return nil
        }
        let size = CGSize(width: width, height: height)
        displayList.position = CGPoint(x: 0.0, y: displayList.descent)

        #if os(iOS) || os(visionOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { rendererContext in
            rendererContext.cgContext.saveGState()
            var transform = CGAffineTransform(scaleX: 1.0, y: -1.0)
            transform = transform.translatedBy(x: 0.0, y: -size.height)
            rendererContext.cgContext.concatenate(transform)
            displayList.draw(rendererContext.cgContext)
            rendererContext.cgContext.restoreGState()
        }
        return MTMathRenderedFormula(image: image, size: size, width: displayList.width, ascent: displayList.ascent, descent: displayList.descent)
        #endif

        #if os(macOS)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            context.saveGState()
            displayList.draw(context)
            context.restoreGState()
            return true
        }
        return MTMathRenderedFormula(image: image, size: size, width: displayList.width, ascent: displayList.ascent, descent: displayList.descent)
        #endif
    }
}
