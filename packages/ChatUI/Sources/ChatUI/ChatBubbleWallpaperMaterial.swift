import AppKit
import ColorPalette
import TGUIKit
import TelegramTheme
import ThemeSettings

final class ChatBubbleWallpaperMaterial {
    enum Style {
        case incoming(tint: NSColor?, tintOpacity: CGFloat)
        case outgoing(tint: NSColor)
    }

    static let blurDownsample: CGFloat = 0.25
    static let blurRadius: CGFloat = 12
    private static let glassGroupName = "chat-bubble-glass"
    private static let backdropLayerClass = NSClassFromString("CABackdropLayer") as? CALayer.Type
    private static let filterClass = NSClassFromString("CAFilter") as? NSObject.Type

    private static func makeFilter(_ name: String) -> NSObject? {
        guard let filterClass else {
            return nil
        }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else {
            return nil
        }
        return filterClass.perform(selector, with: name)?.takeUnretainedValue() as? NSObject
    }

    static func makeGlassLayer() -> CALayer? {
        guard let backdropLayerClass, let blur = makeFilter("gaussianBlur"), let color = makeFilter("colorMatrix") else {
            return nil
        }
        let layer = backdropLayerClass.init()
        layer.setValue(glassGroupName, forKey: "groupName")
        layer.setValue(blurDownsample, forKey: "scale")
        blur.setValue("blur", forKey: "name")
        blur.setValue(blurRadius, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        color.setValue("color", forKey: "name")
        layer.filters = [blur, color]
        layer.actions = ["bounds": NSNull(), "position": NSNull(), "filters": NSNull(), "hidden": NSNull()]
        return layer
    }

    static func applyGlassMatrix(_ values: [CGFloat], to layer: CALayer) {
        var floats = values.map { Float($0) }
        let value = NSValue(bytes: &floats, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: "filters.color.inputColorMatrix")
        CATransaction.commit()
    }

    static func glassColor(over average: NSColor, matrix values: [CGFloat]) -> NSColor {
        let rgb = average.usingColorSpace(.sRGB) ?? average
        let input = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, 1]
        func channel(_ row: Int) -> CGFloat {
            let base = row * 5
            return min(1, max(0, values[base] * input[0] + values[base + 1] * input[1] + values[base + 2] * input[2] + values[base + 3] * input[3] + values[base + 4]))
        }
        return NSColor(srgbRed: channel(0), green: channel(1), blue: channel(2), alpha: 1)
    }

    static let incomingGlassReference = NSColor(0x3B3B3D)
    static let incomingOutlineColor = NSColor.white.withAlphaComponent(0.18)
    static let glassGlyphColor = NSColor.white.withAlphaComponent(0.55)

    static func tinted(_ image: CGImage, _ color: NSColor) -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        context.clip(to: bounds, mask: image)
        context.setFillColor(color.cgColor)
        context.fill(bounds)
        return context.makeImage() ?? image
    }

    static func isActive(_ presentation: TelegramPresentationTheme, hasBubble: Bool, liteBlur: Bool) -> Bool {
        return hasBubble && presentation.bubbled && presentation.liquidGlass && !liteBlur && presentation.hasWallpaper
    }


    static func legible(_ color: NSColor, on background: NSColor, minimum: CGFloat = 4.5) -> NSColor {
        var result = color
        var fraction: CGFloat = 0
        while contrastRatio(result, background) < minimum, fraction < 1 {
            fraction = min(1, fraction + 0.1)
            result = color.blended(withFraction: fraction, of: .white) ?? result
        }
        return result
    }

    static func frostedFill(_ color: NSColor) -> NSColor {
        return (color.blended(withFraction: 0.45, of: .white) ?? color).withAlphaComponent(0.22)
    }

    private struct ContentThemeKey: Equatable {
        let palette: String
        let accent: UInt32
        let outgoing: [UInt32]
        let bubbled: Bool
        let fontSize: CGFloat
        let wallpaper: ThemeWallpaper
        let backgroundSize: NSSize
        let liquidGlass: Bool
    }

    private static let contentThemeLock = NSLock()
    private static var contentThemes: [(key: ContentThemeKey, theme: TelegramPresentationTheme)] = []
    private static let contentThemeLimit = 6

    static func contentTheme(for presentation: TelegramPresentationTheme, liteBlur: Bool) -> TelegramPresentationTheme {
        guard !presentation.colors.isDark, isActive(presentation, hasBubble: true, liteBlur: liteBlur) else {
            return presentation
        }
        let source = presentation.colors
        let key = ContentThemeKey(
            palette: source.name,
            accent: source.accent.argb,
            outgoing: source.bubbleBackground_outgoing.map { $0.argb },
            bubbled: presentation.bubbled,
            fontSize: presentation.fontSize,
            wallpaper: presentation.wallpaper,
            backgroundSize: presentation.backgroundSize,
            liquidGlass: presentation.liquidGlass
        )
        contentThemeLock.lock()
        defer {
            contentThemeLock.unlock()
        }
        if let index = contentThemes.firstIndex(where: { $0.key == key }) {
            let cached = contentThemes.remove(at: index)
            contentThemes.append(cached)
            return cached.theme
        }
        let palette = darkPalette.withAccentColor(PaletteAccentColor(source.accent, source.bubbleBackground_outgoing), disableTint: true)
        let theme = generateTheme(palette: palette, cloudTheme: nil, bubbled: presentation.bubbled, fontSize: presentation.fontSize, wallpaper: presentation.wallpaper, backgroundSize: presentation.backgroundSize, liquidGlass: presentation.liquidGlass)
        contentThemes.append((key, theme))
        if contentThemes.count > contentThemeLimit {
            contentThemes.removeFirst()
        }
        return theme
    }

    static func matrix(outgoing: Bool, tint: NSColor, luminance: CGFloat) -> [CGFloat] {
        let light = min(1, max(0, luminance))
        if outgoing {
            let rgb = tint.usingColorSpace(.sRGB) ?? tint.usingColorSpace(.deviceRGB) ?? .white
            let bias = 0.17 + 0.1 * light
            let weights: [CGFloat] = [0.08504, 0.28608, 0.02888, 0]
            return weights + [min(0.97, rgb.redComponent) - bias]
                + weights + [min(0.97, rgb.greenComponent) - bias]
                + weights + [min(0.97, rgb.blueComponent) - bias]
                + [0, 0, 0, 1, 0]
        }
        let index = light * CGFloat(grayBlueWeights.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, grayBlueWeights.count - 1)
        let blue = grayBlueWeights[lower] + (grayBlueWeights[upper] - grayBlueWeights[lower]) * (index - CGFloat(lower))
        let red = -0.03720494 * (1 + light)
        let green = -0.12516013 * (1 + light)
        let bias = 0.125 * (1 - light)
        return [0.8 + red, green, blue, 0, bias,
                red, 0.8 + green, blue, 0, bias,
                red, green, 0.8 + blue, 0, bias,
                0, 0, 0, 1, 0]
    }

    static func matrix(style: Style, luminance: CGFloat) -> [CGFloat] {
        switch style {
        case let .outgoing(tint):
            return matrix(outgoing: true, tint: tint, luminance: luminance)
        case let .incoming(tint, opacity):
            var values = matrix(outgoing: false, tint: .white, luminance: luminance)
            guard let tint, opacity > 0 else {
                return values
            }
            let alpha = min(1, max(0, opacity))
            let rgb = tint.usingColorSpace(.sRGB) ?? tint.usingColorSpace(.deviceRGB) ?? .white
            let overlay: [CGFloat] = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            for channel in 0 ..< 3 {
                let row = channel * 5
                for column in 0 ..< 4 {
                    values[row + column] *= (1 - alpha)
                }
                values[row + 4] = values[row + 4] * (1 - alpha) + overlay[channel] * alpha
            }
            return values
        }
    }

    static func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return 0
        }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }

    private static let grayBlueWeights: [CGFloat] = [
        0.050365116, 0.045841020, 0.041519698, 0.037396270, 0.033465903, 0.029723700,
        0.026164811, 0.022784363, 0.019577485, 0.016539324, 0.013665002, 0.010949653,
        0.008388419, 0.005976420, 0.003708798, 0.001580697, -0.000412773, -0.002276465,
        -0.004015248, -0.005633991, -0.007137552, -0.008530803, -0.009818614, -0.011005852,
        -0.012097377, -0.013098057, -0.014012761, -0.014846351, -0.015603706, -0.016289681,
        -0.016909145, -0.017466966, -0.017968010, -0.018417142, -0.018819232, -0.019179143,
        -0.019501746, -0.019791905, -0.020054486, -0.020294353, -0.020516377, -0.020725425,
        -0.020926360, -0.021124028, -0.021321450, -0.021518867, -0.021716290, -0.021913711,
        -0.022111136, -0.022308558, -0.022505980, -0.022703398, -0.022900820, -0.023098245,
        -0.023295667, -0.023493089, -0.023690510, -0.023887932, -0.024085354, -0.024282776,
        -0.024480198, -0.024677620, -0.024875041, -0.025072463, -0.025269885
    ]
}

final class ChatBubbleWallpaperMaterialRenderer {
    static let shared = ChatBubbleWallpaperMaterialRenderer()

    struct Sample {
        let luminance: Float
        let average: NSColor
    }

    private struct SnapshotKey: Equatable {
        let mode: TableBackgroundMode
        let width: CGFloat
        let height: CGFloat
    }

    private final class Snapshot {
        weak var view: BackgroundView?
        let key: SnapshotKey
        let pixels: [UInt8]
        let width: Int
        let height: Int

        init(view: BackgroundView, key: SnapshotKey, pixels: [UInt8], width: Int, height: Int) {
            self.view = view
            self.key = key
            self.pixels = pixels
            self.width = width
            self.height = height
        }
    }

    private var snapshots: [ObjectIdentifier: Snapshot] = [:]
    private var snapshotOrder: [ObjectIdentifier] = []
    private let snapshotLimit = 4
    private let sampleScale: CGFloat = 0.25
    private let linearTable: [CGFloat] = (0 ..< 256).map {
        let value = CGFloat($0) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private init() {}

    func sample(for backgroundView: BackgroundView, rect: NSRect) -> Sample? {
        guard rect.width > 0, rect.height > 0, let snapshot = snapshot(for: backgroundView) else {
            return nil
        }
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: snapshot.key.width, height: snapshot.key.height))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return nil
        }
        var luminance: CGFloat = 0
        var red = 0, green = 0, blue = 0
        for row in 0 ..< 4 {
            for column in 0 ..< 8 {
                let x = clipped.minX + (CGFloat(column) + 0.5) * clipped.width / 8
                let y = clipped.minY + (CGFloat(row) + 0.5) * clipped.height / 4
                let px = min(snapshot.width - 1, max(0, Int(x / snapshot.key.width * CGFloat(snapshot.width))))
                let py = min(snapshot.height - 1, max(0, Int(y / snapshot.key.height * CGFloat(snapshot.height))))
                let offset = (py * snapshot.width + px) * 4
                let r = Int(snapshot.pixels[offset]), g = Int(snapshot.pixels[offset + 1]), b = Int(snapshot.pixels[offset + 2])
                luminance += linearTable[r] * 0.2126 + linearTable[g] * 0.7152 + linearTable[b] * 0.0722
                red += r
                green += g
                blue += b
            }
        }
        return Sample(
            luminance: Float(luminance / 32),
            average: NSColor(srgbRed: CGFloat(red) / (32 * 255), green: CGFloat(green) / (32 * 255), blue: CGFloat(blue) / (32 * 255), alpha: 1)
        )
    }

    private func snapshot(for view: BackgroundView) -> Snapshot? {
        let key = SnapshotKey(mode: view.backgroundMode, width: view.bounds.width, height: view.bounds.height)
        let identifier = ObjectIdentifier(view)
        if let cached = snapshots[identifier], cached.view === view, cached.key == key {
            return cached
        }
        guard key.width > 0, key.height > 0 else {
            return nil
        }
        let width = max(1, Int((key.width * sampleScale).rounded()))
        let height = max(1, Int((key.height * sampleScale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else {
            return nil
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let source = bitmap.cgImage else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        let snapshot = Snapshot(view: view, key: key, pixels: pixels, width: width, height: height)
        snapshots[identifier] = snapshot
        snapshotOrder.removeAll(where: { $0 == identifier })
        snapshotOrder.append(identifier)
        while snapshotOrder.count > snapshotLimit {
            snapshots.removeValue(forKey: snapshotOrder.removeFirst())
        }
        return snapshot
    }
}
