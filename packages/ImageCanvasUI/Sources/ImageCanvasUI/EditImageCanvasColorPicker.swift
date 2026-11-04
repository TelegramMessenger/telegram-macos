import Cocoa
import TGUIKit
import ColorPalette
import Localization

private let paletteColors: [UInt32] = [
    0xffffff, 0xebebeb, 0xd6d6d6, 0xc2c2c2, 0xadadad, 0x999999, 0x858585, 0x707070, 0x5c5c5c, 0x474747, 0x333333, 0x000000,
    0x00374a, 0x011d57, 0x11053b, 0x2e063d, 0x3c071b, 0x5c0701, 0x5a1c00, 0x583300, 0x563d00, 0x666100, 0x4f5504, 0x263e0f,
    0x004d65, 0x012f7b, 0x1a0a52, 0x450d59, 0x551029, 0x831100, 0x7b2900, 0x7a4a00, 0x785800, 0x8d8602, 0x6f760a, 0x38571a,
    0x016e8f, 0x0042a9, 0x2c0977, 0x61187c, 0x791a3d, 0xb51a00, 0xad3e00, 0xa96800, 0xa67b01, 0xc4bc00, 0x9ba50e, 0x4e7a27,
    0x008cb4, 0x0056d6, 0x371a94, 0x7a219e, 0x99244f, 0xe22400, 0xda5100, 0xd38301, 0xd19d01, 0xf5ec00, 0xc3d117, 0x669d34,
    0x00a1d8, 0x0061fe, 0x4d22b2, 0x982abc, 0xb92d5d, 0xff4015, 0xff6a00, 0xffab01, 0xfdc700, 0xfefb41, 0xd9ec37, 0x76bb40,
    0x01c7fc, 0x3a87fe, 0x5e30eb, 0xbe38f3, 0xe63b7a, 0xff6250, 0xff8648, 0xfeb43f, 0xfecb3e, 0xfff76b, 0xe4ef65, 0x96d35f,
    0x52d6fc, 0x74a7ff, 0x864ffe, 0xd357fe, 0xee719e, 0xff8c82, 0xffa57d, 0xffc777, 0xffd977, 0xfff994, 0xeaf28f, 0xb1dd8b,
    0x93e3fd, 0xa7c6ff, 0xb18cfe, 0xe292fe, 0xf4a4c0, 0xffb5af, 0xffc5ab, 0xffd9a8, 0xfee4a8, 0xfffbb9, 0xf2f7b7, 0xcde8b5,
    0xcbf0ff, 0xd3e2ff, 0xd9c9fe, 0xefcaff, 0xf9d3e0, 0xffdbd8, 0xffe2d6, 0xffecd4, 0xfff2d5, 0xfefcdd, 0xf7fadb, 0xdfeed4
]

private let fixedColors: [UInt32] = [0x000000, 0x0161FD, 0x32C759, 0xFFCC02, 0xFF3A30]

func editImageCanvasSpectrumColor(x: CGFloat, y: CGFloat) -> EditImageCanvasColor {
    let hue = max(0, min(1, x))
    let y = max(0, min(1, y))
    let saturation: CGFloat
    let brightness: CGFloat
    if y < 0.5 {
        saturation = y * 2.0
        brightness = 1.0
    } else {
        saturation = 1.0
        brightness = 1.0 - (y - 0.5) * 2.0 * 0.9
    }
    return EditImageCanvasColor(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0))
}

func editImageCanvasSpectrumPosition(_ color: EditImageCanvasColor) -> CGPoint {
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0
    color.withAlpha(1.0).nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    if brightness >= 0.999 {
        return CGPoint(x: hue, y: saturation / 2.0)
    } else {
        return CGPoint(x: hue, y: 0.5 + (1.0 - brightness) / 1.8)
    }
}

func editImageCanvasSpectrumImage(size: NSSize) -> CGImage {
    let width = max(1, Int(size.width))
    let height = max(1, Int(size.height))
    return generateImage(NSMakeSize(CGFloat(width), CGFloat(height)), scale: 1.0, rotatedContext: { size, context in
        let step: CGFloat = 2
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let color = editImageCanvasSpectrumColor(x: x / size.width, y: y / size.height)
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: x, y: y, width: step, height: step))
                x += step
            }
            y += step
        }
    })!
}

private func drawCheckerboard(in rect: CGRect, context: CGContext, cell: CGFloat = 6) {
    context.saveGState()
    context.clip(to: rect)
    context.setFillColor(NSColor.white.cgColor)
    context.fill(rect)
    context.setFillColor(NSColor(white: 0.8, alpha: 1.0).cgColor)
    var row = 0
    var y = rect.minY
    while y < rect.maxY {
        var x = rect.minX + (row % 2 == 0 ? 0 : cell)
        while x < rect.maxX {
            context.fill(CGRect(x: x, y: y, width: cell, height: cell))
            x += cell * 2
        }
        y += cell
        row += 1
    }
    context.restoreGState()
}

private final class EditImageCanvasColorGridView: View {
    var color: EditImageCanvasColor = .white {
        didSet {
            needsDisplay = true
        }
    }
    var onChange: ((EditImageCanvasColor) -> Void)?

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let cellWidth = bounds.width / 12.0
        let cellHeight = bounds.height / 10.0
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.clip()
        var selectedRect: CGRect?
        for (i, value) in paletteColors.enumerated() {
            let column = i % 12
            let row = i / 12
            let rect = CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth + 0.5, height: cellHeight + 0.5)
            let cellColor = EditImageCanvasColor(rgb: value)
            ctx.setFillColor(cellColor.cgColor)
            ctx.fill(rect)
            if cellColor.isSameRGB(color) {
                selectedRect = rect
            }
        }
        ctx.restoreGState()
        if let rect = selectedRect {
            let isLight = color.lightness > 0.5
            ctx.setStrokeColor(isLight ? NSColor.black.cgColor : NSColor.white.cgColor)
            ctx.setLineWidth(3)
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.strokePath()
        }
    }

    private func pick(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let column = max(0, min(11, Int(point.x / (bounds.width / 12.0))))
        let row = max(0, min(9, Int(point.y / (bounds.height / 10.0))))
        let picked = EditImageCanvasColor(rgb: paletteColors[row * 12 + column], alpha: color.alpha)
        color = picked
        onChange?(picked)
    }

    override func mouseDown(with event: NSEvent) {
        pick(event)
    }

    override func mouseDragged(with event: NSEvent) {
        pick(event)
    }
}

private final class EditImageCanvasSpectrumView: View {
    private var image: CGImage?
    private var position: CGPoint?
    var color: EditImageCanvasColor = .white {
        didSet {
            if !isTracking {
                position = editImageCanvasSpectrumPosition(color)
            }
            needsDisplay = true
        }
    }
    var onChange: ((EditImageCanvasColor) -> Void)?
    private var isTracking = false

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        if image == nil || image?.width != Int(bounds.width) {
            image = editImageCanvasSpectrumImage(size: bounds.size)
        }
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.clip()
        if let image = image {
            editImageCanvasDrawUpright(image, in: bounds, context: ctx)
        }
        ctx.restoreGState()
        if let position = position {
            let center = CGPoint(x: position.x * bounds.width, y: position.y * bounds.height)
            let knob = CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: knob)
            ctx.setFillColor(color.withAlpha(1.0).cgColor)
            ctx.fillEllipse(in: knob.insetBy(dx: 4, dy: 4))
        }
    }

    private func pick(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let x = max(0, min(1, point.x / bounds.width))
        let y = max(0, min(1, point.y / bounds.height))
        position = CGPoint(x: x, y: y)
        let picked = editImageCanvasSpectrumColor(x: x, y: y).withAlpha(color.alpha)
        color = picked
        onChange?(picked)
    }

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        pick(event)
    }

    override func mouseDragged(with event: NSEvent) {
        pick(event)
    }

    override func mouseUp(with event: NSEvent) {
        pick(event)
        isTracking = false
    }
}

final class EditImageCanvasGradientSlider: View {
    var colors: [NSColor] = [.black, .white] {
        didSet {
            needsDisplay = true
        }
    }
    var checkerboard: Bool = false
    var value: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }
    var onChange: ((CGFloat) -> Void)?

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let track = bounds.insetBy(dx: 0, dy: 2)
        let radius = track.height / 2.0
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        if checkerboard {
            drawCheckerboard(in: track, context: ctx)
        }
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map { $0.cgColor } as CFArray, locations: nil) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: track.minX, y: track.midY), end: CGPoint(x: track.maxX, y: track.midY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
        let knobSize = track.height
        let x = radius + (track.width - radius * 2) * value
        let knob = CGRect(x: x - knobSize / 2, y: track.midY - knobSize / 2, width: knobSize, height: knobSize)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: knob.insetBy(dx: 2.5, dy: 2.5))
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: knob.insetBy(dx: 0.5, dy: 0.5))
    }

    private func pick(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let radius = bounds.height / 2.0
        let updated = max(0, min(1, (point.x - radius) / max(1, bounds.width - radius * 2)))
        value = updated
        onChange?(updated)
    }

    override func mouseDown(with event: NSEvent) {
        pick(event)
    }

    override func mouseDragged(with event: NSEvent) {
        pick(event)
    }
}

private final class EditImageCanvasSlidersView: View {
    private let red = EditImageCanvasGradientSlider(frame: .zero)
    private let green = EditImageCanvasGradientSlider(frame: .zero)
    private let blue = EditImageCanvasGradientSlider(frame: .zero)
    private let labels: [TextView] = [TextView(), TextView(), TextView()]
    private let values: [TextView] = [TextView(), TextView(), TextView()]
    private let hexTitle = TextView()
    private let hexField = NSTextField()
    var onChange: ((EditImageCanvasColor) -> Void)?
    var color: EditImageCanvasColor = .white {
        didSet {
            updateSliders()
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let titles = [strings().editImageCanvasColorPickerRed, strings().editImageCanvasColorPickerGreen, strings().editImageCanvasColorPickerBlue]
        for (i, slider) in [red, green, blue].enumerated() {
            addSubview(slider)
            let titleLayout = TextViewLayout(.initialize(string: titles[i], color: NSColor.white.withAlphaComponent(0.6), font: .medium(.small)))
            titleLayout.measure(width: .greatestFiniteMagnitude)
            labels[i].update(titleLayout)
            labels[i].userInteractionEnabled = false
            labels[i].isSelectable = false
            addSubview(labels[i])
            values[i].userInteractionEnabled = false
            values[i].isSelectable = false
            addSubview(values[i])
        }
        red.onChange = { [weak self] value in
            self?.apply { $0.red = value }
        }
        green.onChange = { [weak self] value in
            self?.apply { $0.green = value }
        }
        blue.onChange = { [weak self] value in
            self?.apply { $0.blue = value }
        }
        let hexLayout = TextViewLayout(.initialize(string: strings().editImageCanvasColorPickerHexColor, color: NSColor.white.withAlphaComponent(0.6), font: .medium(.small)))
        hexLayout.measure(width: .greatestFiniteMagnitude)
        hexTitle.update(hexLayout)
        hexTitle.userInteractionEnabled = false
        hexTitle.isSelectable = false
        addSubview(hexTitle)
        hexField.isBordered = false
        hexField.drawsBackground = true
        hexField.backgroundColor = NSColor.white.withAlphaComponent(0.1)
        hexField.textColor = .white
        hexField.font = .medium(.title)
        hexField.focusRingType = .none
        hexField.alignment = .center
        hexField.target = self
        hexField.action = #selector(hexChanged)
        addSubview(hexField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func hexChanged() {
        let string = hexField.stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard string.count == 6, let value = UInt32(string, radix: 16) else {
            updateSliders()
            return
        }
        let updated = EditImageCanvasColor(rgb: value, alpha: color.alpha)
        color = updated
        onChange?(updated)
    }

    private func apply(_ f: (inout EditImageCanvasColor) -> Void) {
        var updated = color
        f(&updated)
        color = updated
        onChange?(updated)
    }

    private func updateSliders() {
        let c = color.withAlpha(1.0)
        red.colors = [EditImageCanvasColor(red: 0, green: c.green, blue: c.blue).nsColor, EditImageCanvasColor(red: 1, green: c.green, blue: c.blue).nsColor]
        green.colors = [EditImageCanvasColor(red: c.red, green: 0, blue: c.blue).nsColor, EditImageCanvasColor(red: c.red, green: 1, blue: c.blue).nsColor]
        blue.colors = [EditImageCanvasColor(red: c.red, green: c.green, blue: 0).nsColor, EditImageCanvasColor(red: c.red, green: c.green, blue: 1).nsColor]
        red.value = c.red
        green.value = c.green
        blue.value = c.blue
        for (i, component) in [c.red, c.green, c.blue].enumerated() {
            let layout = TextViewLayout(.initialize(string: "\(Int((component * 255).rounded()))", color: .white, font: .medium(.text)))
            layout.measure(width: 60)
            values[i].update(layout)
        }
        if hexField.currentEditor() == nil {
            hexField.stringValue = c.hexString
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for (i, slider) in [red, green, blue].enumerated() {
            labels[i].setFrameOrigin(NSMakePoint(0, y))
            slider.frame = NSMakeRect(0, y + 16, frame.width - 56, 30)
            values[i].setFrameOrigin(NSMakePoint(frame.width - values[i].frame.width, y + 16 + (30 - values[i].frame.height) / 2))
            y += 56
        }
        hexTitle.setFrameOrigin(NSMakePoint(0, y + 6))
        hexField.frame = NSMakeRect(frame.width - 110, y, 110, 26)
    }
}

final class EditImageCanvasColorPickerView: View {
    private let close = ImageButton()
    private let eyedropper = ImageButton()
    private let title = TextView()
    private let segments: [TextButton]
    private let segmentsBackground = View()
    private let segmentSelection = View()
    private let grid = EditImageCanvasColorGridView(frame: .zero)
    private let spectrum = EditImageCanvasSpectrumView(frame: .zero)
    private let sliders = EditImageCanvasSlidersView(frame: .zero)
    private let opacityTitle = TextView()
    private let opacityValue = TextView()
    private let opacity = EditImageCanvasGradientSlider(frame: .zero)
    private let preview = View()
    private var fixed: [Control] = []
    private var selectedSegment: Int = 0

    private(set) var color: EditImageCanvasColor
    var onChange: ((EditImageCanvasColor) -> Void)?
    var onClose: (() -> Void)?
    var onEyedropper: (() -> Void)?

    private static let segmentKey = "editImageCanvasColorPickerSegment"

    init(color: EditImageCanvasColor) {
        self.color = color
        self.segments = [strings().editImageCanvasColorPickerGrid, strings().editImageCanvasColorPickerSpectrum, strings().editImageCanvasColorPickerSliders].map { title in
            let button = TextButton()
            button.autohighlight = false
            button.set(font: .medium(.text), for: .Normal)
            button.set(color: .white, for: .Normal)
            button.set(text: title, for: .Normal)
            return button
        }
        super.init(frame: NSMakeRect(0, 0, 320, 520))
        backgroundColor = NSColor(white: 0.11, alpha: 0.98)
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        close.autohighlight = false
        close.scaleOnClick = true
        close.set(image: EditImageCanvasGlyph.close(14), for: .Normal)
        _ = close.sizeToFit(.zero, NSMakeSize(32, 32), thatFit: true)
        addSubview(close)

        eyedropper.autohighlight = false
        eyedropper.scaleOnClick = true
        eyedropper.set(image: NSImage(resource: .iconEditImageEyedropper).precomposed(.white), for: .Normal)
        _ = eyedropper.sizeToFit(.zero, NSMakeSize(32, 32), thatFit: true)
        addSubview(eyedropper)

        let titleLayout = TextViewLayout(.initialize(string: strings().editImageCanvasColorPickerTitle, color: .white, font: .medium(.header)))
        titleLayout.measure(width: .greatestFiniteMagnitude)
        title.update(titleLayout)
        title.userInteractionEnabled = false
        title.isSelectable = false
        addSubview(title)

        segmentsBackground.backgroundColor = NSColor.white.withAlphaComponent(0.1)
        segmentsBackground.layer?.cornerRadius = 9
        segmentSelection.backgroundColor = NSColor.white.withAlphaComponent(0.25)
        segmentSelection.layer?.cornerRadius = 7
        segmentSelection.isEventLess = true
        addSubview(segmentsBackground)
        segmentsBackground.addSubview(segmentSelection)
        for (i, segment) in segments.enumerated() {
            segmentsBackground.addSubview(segment)
            segment.set(handler: { [weak self] _ in
                self?.select(segment: i)
            }, for: .Click)
        }

        addSubview(grid)
        addSubview(spectrum)
        addSubview(sliders)

        let opacityLayout = TextViewLayout(.initialize(string: strings().editImageCanvasColorPickerOpacity, color: NSColor.white.withAlphaComponent(0.6), font: .medium(.small)))
        opacityLayout.measure(width: .greatestFiniteMagnitude)
        opacityTitle.update(opacityLayout)
        opacityTitle.userInteractionEnabled = false
        opacityTitle.isSelectable = false
        addSubview(opacityTitle)
        opacityValue.userInteractionEnabled = false
        opacityValue.isSelectable = false
        addSubview(opacityValue)
        opacity.checkerboard = true
        addSubview(opacity)

        preview.layer?.cornerRadius = 12
        preview.layer?.masksToBounds = true
        addSubview(preview)

        for value in fixedColors {
            let swatch = Control(frame: NSMakeRect(0, 0, 32, 32))
            swatch.scaleOnClick = true
            let swatchColor = EditImageCanvasColor(rgb: value)
            swatch.layer?.contents = generateImage(NSMakeSize(32, 32), rotatedContext: { size, context in
                context.clear(size.bounds)
                context.setFillColor(swatchColor.cgColor)
                context.fillEllipse(in: size.bounds.insetBy(dx: 2, dy: 2))
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
                context.setLineWidth(1)
                context.strokeEllipse(in: size.bounds.insetBy(dx: 2.5, dy: 2.5))
            })
            swatch.set(handler: { [weak self] _ in
                self?.apply(swatchColor)
            }, for: .Click)
            swatch.setAccessibilityLabel("\(strings().voiceOverCommonColor) #\(swatchColor.hexString)")
            fixed.append(swatch)
            addSubview(swatch)
        }

        close.set(handler: { [weak self] _ in
            self?.onClose?()
        }, for: .Click)
        close.setAccessibilityLabel(strings().voiceOverCommonClose)
        eyedropper.set(handler: { [weak self] _ in
            self?.onEyedropper?()
        }, for: .Click)
        eyedropper.setAccessibilityLabel("Pick Color from Image") //TODOLANG

        grid.onChange = { [weak self] color in
            self?.apply(color)
        }
        spectrum.onChange = { [weak self] color in
            self?.apply(color)
        }
        sliders.onChange = { [weak self] color in
            self?.apply(color)
        }
        opacity.onChange = { [weak self] value in
            guard let self = self else {
                return
            }
            self.apply(self.color.withAlpha(value))
        }

        selectedSegment = UserDefaults.standard.integer(forKey: EditImageCanvasColorPickerView.segmentKey)
        updateColor(color)
        select(segment: selectedSegment)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func select(segment: Int) {
        selectedSegment = max(0, min(2, segment))
        UserDefaults.standard.set(selectedSegment, forKey: EditImageCanvasColorPickerView.segmentKey)
        grid.isHidden = selectedSegment != 0
        spectrum.isHidden = selectedSegment != 1
        sliders.isHidden = selectedSegment != 2
        needsLayout = true
    }

    private func apply(_ color: EditImageCanvasColor) {
        updateColor(color)
        onChange?(color)
    }

    func updateColor(_ color: EditImageCanvasColor) {
        self.color = color
        grid.color = color
        spectrum.color = color
        sliders.color = color
        opacity.colors = [color.withAlpha(0).nsColor, color.withAlpha(1).nsColor]
        opacity.value = color.alpha
        let layout = TextViewLayout(.initialize(string: "\(Int((color.alpha * 100).rounded()))%", color: .white, font: .medium(.text)))
        layout.measure(width: 60)
        opacityValue.update(layout)
        preview.layer?.contents = generateImage(NSMakeSize(64, 64), rotatedContext: { size, context in
            drawCheckerboard(in: size.bounds, context: context, cell: 8)
            context.setFillColor(color.cgColor)
            context.fill(size.bounds)
        })
        needsLayout = true
    }

    override func layout() {
        super.layout()
        close.setFrameOrigin(NSMakePoint(12, 12))
        eyedropper.setFrameOrigin(NSMakePoint(frame.width - eyedropper.frame.width - 12, 12))
        title.centerX(y: 12 + (32 - title.frame.height) / 2)

        segmentsBackground.frame = NSMakeRect(10, 56, frame.width - 20, 32)
        let segmentWidth = (segmentsBackground.frame.width - 4) / CGFloat(segments.count)
        for (i, segment) in segments.enumerated() {
            segment.frame = NSMakeRect(2 + segmentWidth * CGFloat(i), 2, segmentWidth, 28)
        }
        segmentSelection.frame = segments[selectedSegment].frame

        let content = NSMakeRect(10, 100, frame.width - 20, min(250, frame.height - 270))
        grid.frame = content
        spectrum.frame = content
        sliders.frame = content.insetBy(dx: 4, dy: 8)

        opacityTitle.setFrameOrigin(NSMakePoint(10, content.maxY + 16))
        opacity.frame = NSMakeRect(10, opacityTitle.frame.maxY + 6, frame.width - 76, 30)
        opacityValue.setFrameOrigin(NSMakePoint(frame.width - 10 - opacityValue.frame.width, opacity.frame.minY + (30 - opacityValue.frame.height) / 2))

        let bottomY = opacity.frame.maxY + 18
        preview.frame = NSMakeRect(10, bottomY, 64, 64)
        let left = preview.frame.maxX + 16
        let step = (frame.width - 10 - left) / CGFloat(max(1, fixed.count))
        for (i, swatch) in fixed.enumerated() {
            swatch.setFrameOrigin(NSMakePoint(floor(left + step * CGFloat(i) + (step - swatch.frame.width) / 2), bottomY + 16))
        }
    }
}

final class EditImageCanvasEyedropperView: View {
    private let sourceImage: CGImage
    private let pixels: [UInt8]
    private let pixelWidth: Int
    private let pixelHeight: Int
    private let contentRect: CGRect
    private var location: NSPoint?
    var onPick: ((EditImageCanvasColor?) -> Void)?

    init(frame frameRect: NSRect, snapshot: CGImage, contentRect: CGRect) {
        self.sourceImage = snapshot
        self.contentRect = contentRect
        self.pixelWidth = snapshot.width
        self.pixelHeight = snapshot.height
        var data = [UInt8](repeating: 0, count: snapshot.width * snapshot.height * 4)
        data.withUnsafeMutableBytes { buffer in
            if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: buffer.baseAddress, width: snapshot.width, height: snapshot.height, bitsPerComponent: 8, bytesPerRow: snapshot.width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(snapshot, in: CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
            }
        }
        self.pixels = data
        super.init(frame: frameRect)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    private func pixel(at point: NSPoint) -> (x: Int, y: Int)? {
        guard contentRect.contains(point) else {
            return nil
        }
        let x = Int((point.x - contentRect.minX) / contentRect.width * CGFloat(pixelWidth))
        let y = Int((point.y - contentRect.minY) / contentRect.height * CGFloat(pixelHeight))
        return (max(0, min(pixelWidth - 1, x)), max(0, min(pixelHeight - 1, y)))
    }

    func color(at point: NSPoint) -> EditImageCanvasColor? {
        guard let (x, y) = pixel(at: point) else {
            return nil
        }
        let offset = (y * pixelWidth + x) * 4
        let alpha = CGFloat(pixels[offset + 3]) / 255.0
        guard alpha > 0 else {
            return EditImageCanvasColor.black
        }
        return EditImageCanvasColor(red: CGFloat(pixels[offset]) / 255.0 / alpha, green: CGFloat(pixels[offset + 1]) / 255.0 / alpha, blue: CGFloat(pixels[offset + 2]) / 255.0 / alpha, alpha: 1.0)
    }

    override func mouseMoved(with event: NSEvent) {
        location = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        location = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPick?(color(at: point))
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        guard let location = location, let (px, py) = pixel(at: location), let color = color(at: location) else {
            return
        }
        let loupeSize: CGFloat = 148
        let zoom: CGFloat = 15
        let cells = Int(ceil(loupeSize / zoom))
        let half = cells / 2
        let cropRect = CGRect(x: px - half, y: py - half, width: cells, height: cells)
        let loupe = CGRect(x: location.x - loupeSize / 2, y: location.y - loupeSize / 2, width: loupeSize, height: loupeSize)
        ctx.saveGState()
        ctx.addEllipse(in: loupe)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(loupe)
        if let cropped = sourceImage.cropping(to: cropRect.intersection(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))) {
            let offsetX = CGFloat(max(0, -(px - half)))
            let offsetY = CGFloat(max(0, -(py - half)))
            let drawRect = CGRect(x: loupe.minX + offsetX * zoom, y: loupe.minY + offsetY * zoom, width: CGFloat(cropped.width) * zoom, height: CGFloat(cropped.height) * zoom)
            ctx.interpolationQuality = .none
            editImageCanvasDrawUpright(cropped, in: drawRect, context: ctx)
        }
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(1)
        var gx = loupe.minX
        while gx < loupe.maxX {
            ctx.move(to: CGPoint(x: gx, y: loupe.minY))
            ctx.addLine(to: CGPoint(x: gx, y: loupe.maxY))
            gx += zoom
        }
        var gy = loupe.minY
        while gy < loupe.maxY {
            ctx.move(to: CGPoint(x: loupe.minX, y: gy))
            ctx.addLine(to: CGPoint(x: loupe.maxX, y: gy))
            gy += zoom
        }
        ctx.strokePath()
        let center = CGRect(x: loupe.minX + CGFloat(half) * zoom, y: loupe.minY + CGFloat(half) * zoom, width: zoom, height: zoom)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(center)
        ctx.restoreGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(8)
        ctx.strokeEllipse(in: loupe.insetBy(dx: 4, dy: 4))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: loupe.insetBy(dx: 0.75, dy: 0.75))
    }
}
