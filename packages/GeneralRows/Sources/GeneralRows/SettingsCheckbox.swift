import Cocoa
import TGUIKit
import TelegramTheme

public enum SettingsCheckbox {
    public static let size: CGFloat = 14
    public static let cornerRadius: CGFloat = 4

    private static var cache: [String: CGImage] = [:]

    public static func selected(_ fill: NSColor = theme.colors.accent) -> CGImage {
        let color = fill.usingColorSpace(.sRGB) ?? fill
        let key = "on-\(color.redComponent)-\(color.greenComponent)-\(color.blueComponent)-\(color.alphaComponent)-\(System.backingScale)"
        if let image = cache[key] {
            return image
        }
        let image = generateImage(NSMakeSize(size, size), rotatedContext: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
            let rect = CGRect(origin: .zero, size: size)
            ctx.addPath(CGPath.continuousRoundedRect(rect, topLeft: cornerRadius, topRight: cornerRadius, bottomLeft: cornerRadius, bottomRight: cornerRadius, smoothing: SettingsRowMetrics.cornerSmoothing))
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.75)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: 3.6, y: 7.3))
            ctx.addLine(to: CGPoint(x: 6.0, y: 9.7))
            ctx.addLine(to: CGPoint(x: 10.5, y: 4.4))
            ctx.strokePath()
        })!
        cache[key] = image
        return image
    }

    public static var unselected: CGImage {
        let key = "off-\(theme.colors.isDark)-\(System.backingScale)"
        if let image = cache[key] {
            return image
        }
        let image = generateImage(NSMakeSize(size, size), rotatedContext: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let radius = cornerRadius - 0.5
            let path = CGPath.continuousRoundedRect(rect, topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius, smoothing: SettingsRowMetrics.cornerSmoothing)
            ctx.addPath(path)
            ctx.setFillColor(theme.colors.text.withAlphaComponent(0.06).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(theme.colors.text.withAlphaComponent(0.28).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        })!
        cache[key] = image
        return image
    }
}

public enum SettingsPopUpIndicator {
    public static let size: CGFloat = 20

    private static var cache: [String: CGImage] = [:]

    public static var image: CGImage {
        let key = "\(theme.colors.isDark)-\(System.backingScale)"
        if let image = cache[key] {
            return image
        }
        let image = generateImage(NSMakeSize(size, size), rotatedContext: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
            ctx.setFillColor(theme.colors.text.withAlphaComponent(0.1).cgColor)
            ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
            ctx.setStrokeColor(theme.colors.text.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: 7, y: 8.5))
            ctx.addLine(to: CGPoint(x: 10, y: 5.5))
            ctx.addLine(to: CGPoint(x: 13, y: 8.5))
            ctx.move(to: CGPoint(x: 7, y: 11.5))
            ctx.addLine(to: CGPoint(x: 10, y: 14.5))
            ctx.addLine(to: CGPoint(x: 13, y: 11.5))
            ctx.strokePath()
        })!
        cache[key] = image
        return image
    }
}

public enum SettingsRadio {
    private static var cache: [String: CGImage] = [:]

    public static var selected: CGImage {
        let color = theme.colors.accent.usingColorSpace(.sRGB) ?? theme.colors.accent
        let key = "on-\(color.redComponent)-\(color.greenComponent)-\(color.blueComponent)-\(System.backingScale)"
        if let image = cache[key] {
            return image
        }
        let size = SettingsCheckbox.size
        let image = generateImage(NSMakeSize(size, size), rotatedContext: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: (size.width - 6) / 2, y: (size.height - 6) / 2, width: 6, height: 6))
        })!
        cache[key] = image
        return image
    }

    public static var unselected: CGImage {
        let key = "off-\(theme.colors.isDark)-\(System.backingScale)"
        if let image = cache[key] {
            return image
        }
        let size = SettingsCheckbox.size
        let image = generateImage(NSMakeSize(size, size), rotatedContext: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            ctx.setFillColor(theme.colors.text.withAlphaComponent(0.06).cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(theme.colors.text.withAlphaComponent(0.28).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: rect)
        })!
        cache[key] = image
        return image
    }
}
