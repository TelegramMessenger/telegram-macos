import Cocoa
import TGUIKit
import ColorPalette
import Localization

enum EditImageCanvasGlyph {
    static func close(_ size: CGFloat = 16, color: NSColor = .white) -> CGImage {
        return generateImage(NSMakeSize(size, size), rotatedContext: { size, context in
            context.clear(size.bounds)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 2, y: 2))
            context.addLine(to: CGPoint(x: size.width - 2, y: size.height - 2))
            context.move(to: CGPoint(x: size.width - 2, y: 2))
            context.addLine(to: CGPoint(x: 2, y: size.height - 2))
            context.strokePath()
        })!
    }

    static func check(_ size: CGFloat = 18, color: NSColor = .white) -> CGImage {
        return generateImage(NSMakeSize(size, size), rotatedContext: { size, context in
            context.clear(size.bounds)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2.2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.52))
            context.addLine(to: CGPoint(x: size.width * 0.4, y: size.height * 0.76))
            context.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.26))
            context.strokePath()
        })!
    }

    static func alignment(_ alignment: EditImageCanvasEntity.TextAlignment, color: NSColor = .white) -> CGImage {
        return generateImage(NSMakeSize(24, 24), rotatedContext: { size, context in
            context.clear(size.bounds)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            let widths: [CGFloat] = [16, 10, 16, 10]
            for (i, width) in widths.enumerated() {
                let y = 6.0 + CGFloat(i) * 4.0
                let x: CGFloat
                switch alignment {
                case .left:
                    x = 4
                case .center:
                    x = (size.width - width) / 2.0
                case .right:
                    x = size.width - 4 - width
                }
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x + width, y: y))
            }
            context.strokePath()
        })!
    }

    static func vector(_ type: EditImageCanvasEntity.VectorType, color: NSColor = .white) -> CGImage {
        return generateImage(NSMakeSize(24, 24), rotatedContext: { size, context in
            context.clear(size.bounds)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: 4, y: 12))
            context.addLine(to: CGPoint(x: 20, y: 12))
            if type != .line {
                context.move(to: CGPoint(x: 15, y: 7))
                context.addLine(to: CGPoint(x: 20, y: 12))
                context.addLine(to: CGPoint(x: 15, y: 17))
            }
            if type == .twoSidedArrow {
                context.move(to: CGPoint(x: 9, y: 7))
                context.addLine(to: CGPoint(x: 4, y: 12))
                context.addLine(to: CGPoint(x: 9, y: 17))
            }
            context.strokePath()
        })!
    }
}

final class EditImageCanvasArguments {
    let selectTool: (EditImageCanvasTool) -> Void
    let updateSize: (CGFloat, Bool) -> Void
    let previewSize: (CGFloat?) -> Void
    let selectColor: (EditImageCanvasColor, Bool) -> Void
    let showColorPicker: () -> Void
    let plus: (Control) -> Void
    let undo: () -> Void
    let redo: () -> Void
    let clearAll: (Control) -> Void
    let toggleDrawType: () -> Void
    let cycleVectorType: () -> Void
    let flip: () -> Void
    let zoomOut: () -> Void
    let cycleTextStyle: () -> Void
    let cycleTextAlignment: () -> Void
    let selectFont: (Control) -> Void
    let modeDraw: () -> Void
    let modeSticker: (Control) -> Void
    let modeText: () -> Void
    let endTextEditing: (Bool) -> Void
    let done: () -> Void
    let cancel: () -> Void

    init(selectTool: @escaping (EditImageCanvasTool) -> Void, updateSize: @escaping (CGFloat, Bool) -> Void, previewSize: @escaping (CGFloat?) -> Void, selectColor: @escaping (EditImageCanvasColor, Bool) -> Void, showColorPicker: @escaping () -> Void, plus: @escaping (Control) -> Void, undo: @escaping () -> Void, redo: @escaping () -> Void, clearAll: @escaping (Control) -> Void, toggleDrawType: @escaping () -> Void, cycleVectorType: @escaping () -> Void, flip: @escaping () -> Void, zoomOut: @escaping () -> Void, cycleTextStyle: @escaping () -> Void, cycleTextAlignment: @escaping () -> Void, selectFont: @escaping (Control) -> Void, modeDraw: @escaping () -> Void, modeSticker: @escaping (Control) -> Void, modeText: @escaping () -> Void, endTextEditing: @escaping (Bool) -> Void, done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.selectTool = selectTool
        self.updateSize = updateSize
        self.previewSize = previewSize
        self.selectColor = selectColor
        self.showColorPicker = showColorPicker
        self.plus = plus
        self.undo = undo
        self.redo = redo
        self.clearAll = clearAll
        self.toggleDrawType = toggleDrawType
        self.cycleVectorType = cycleVectorType
        self.flip = flip
        self.zoomOut = zoomOut
        self.cycleTextStyle = cycleTextStyle
        self.cycleTextAlignment = cycleTextAlignment
        self.selectFont = selectFont
        self.modeDraw = modeDraw
        self.modeSticker = modeSticker
        self.modeText = modeText
        self.endTextEditing = endTextEditing
        self.done = done
        self.cancel = cancel
    }
}

struct EditImageCanvasControlsState {
    let state: EditImageCanvasState
    let isZoomed: Bool
    let stickersAvailable: Bool
}

private func makeTextButton(_ text: String, color: NSColor = .white, font: NSFont = .medium(.title)) -> TextButton {
    let button = TextButton()
    button.autohighlight = false
    button.scaleOnClick = true
    button.set(font: font, for: .Normal)
    button.set(color: color, for: .Normal)
    button.set(text: text, for: .Normal)
    _ = button.sizeToFit(NSMakeSize(16, 0), NSMakeSize(0, 32), thatFit: false)
    return button
}

func applyGlass(_ button: ImageButton) {
    button.scaleOnClick = true
    button.autohighlight = false
    button.animates = false
    button.disableActions()
    button.setGlassEffect(forceAppearance: .forceDark)
}

func makeGlassIconButton(_ image: CGImage, label: String) -> ImageButton {
    let button = ImageButton()
    button.set(image: image, for: .Normal)
    button.setAccessibilityLabel(label)
    applyGlass(button)
    _ = button.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
    return button
}

func makeGlassTextButton(_ text: String, color: NSColor = .white, image: CGImage? = nil) -> TextButton {
    let button = TextButton()
    button.autoSizeToFit = false
    button.set(font: .medium(.title), for: .Normal)
    button.set(color: color, for: .Normal)
    button.set(text: text, for: .Normal)
    if let image = image {
        button.set(image: image, for: .Normal)
    }
    applyGlass(button)
    _ = button.sizeToFit(NSMakeSize(image == nil ? 32 : 28, 0), NSMakeSize(300, 40), thatFit: false)
    return button
}

final class EditImageCanvasTopBar: View {
    private let undo: ImageButton
    private let redo: ImageButton
    private let clearAll: TextButton
    private let cancelText: TextButton
    private let doneText: TextButton
    private var centerButtons: [Control] = []
    private var centerKey: CenterKey?
    var arguments: EditImageCanvasArguments?

    private enum CenterKey: Equatable {
        case none
        case shape(EditImageCanvasEntity.DrawType)
        case bubble(EditImageCanvasEntity.DrawType)
        case vector(EditImageCanvasEntity.VectorType)
        case sticker
        case zoom
    }

    required init(frame frameRect: NSRect) {
        let undoImage = NSImage(resource: .iconEditImageUndo)
        self.undo = makeGlassIconButton(undoImage.precomposed(.white), label: strings().voiceOverCommonUndo)
        self.redo = makeGlassIconButton(undoImage.precomposed(.white, flipHorizontal: true), label: strings().voiceOverCommonRedo)
        self.clearAll = makeGlassTextButton(strings().editImageCanvasControlsClearAll)
        self.cancelText = makeGlassTextButton(strings().modalCancel)
        self.doneText = makeGlassTextButton(strings().navigationDone, color: nightAccentPalette.accent)
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        addSubview(undo)
        addSubview(redo)
        addSubview(clearAll)
        addSubview(cancelText)
        addSubview(doneText)

        undo.set(handler: { [weak self] _ in
            self?.arguments?.undo()
        }, for: .Click)
        redo.set(handler: { [weak self] _ in
            self?.arguments?.redo()
        }, for: .Click)
        clearAll.set(handler: { [weak self] control in
            self?.arguments?.clearAll(control)
        }, for: .Click)
        cancelText.set(handler: { [weak self] _ in
            self?.arguments?.endTextEditing(false)
        }, for: .Click)
        doneText.set(handler: { [weak self] _ in
            self?.arguments?.endTextEditing(true)
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ controls: EditImageCanvasControlsState) {
        let state = controls.state
        let editing = state.editingEntityId != nil
        undo.isHidden = editing
        redo.isHidden = editing || !state.canRedo
        undo.isEnabled = state.canUndo
        undo.alphaValue = state.canUndo ? 1.0 : 0.4
        clearAll.isHidden = editing
        clearAll.isEnabled = state.canClear
        clearAll.alphaValue = state.canClear ? 1.0 : 0.4
        cancelText.isHidden = !editing
        doneText.isHidden = !editing

        var key: CenterKey = .none
        if !editing {
            if let entity = state.selectedEntity {
                switch entity.content {
                case let .shape(shape):
                    key = .shape(shape.drawType)
                case let .bubble(bubble):
                    key = .bubble(bubble.drawType)
                case let .vector(vector):
                    key = .vector(vector.type)
                case .sticker:
                    key = .sticker
                case .text:
                    key = .none
                }
            } else if controls.isZoomed {
                key = .zoom
            }
        }
        guard key != centerKey else {
            return
        }
        centerKey = key

        for button in centerButtons {
            button.removeFromSuperview()
        }
        centerButtons.removeAll()

        switch key {
        case .none:
            break
        case let .shape(drawType):
            centerButtons.append(drawTypeButton(drawType))
        case let .bubble(drawType):
            centerButtons.append(drawTypeButton(drawType))
            centerButtons.append(flipButton())
        case let .vector(type):
            let label: String
            switch type.next {
            case .oneSidedArrow:
                label = "Switch to One-Sided Arrow" //TODOLANG
            case .twoSidedArrow:
                label = "Switch to Two-Sided Arrow" //TODOLANG
            case .line:
                label = "Switch to Line" //TODOLANG
            }
            let button = makeGlassIconButton(EditImageCanvasGlyph.vector(type), label: label)
            button.set(handler: { [weak self] _ in
                self?.arguments?.cycleVectorType()
            }, for: .Click)
            centerButtons.append(button)
        case .sticker:
            centerButtons.append(flipButton())
        case .zoom:
            let button = makeGlassTextButton(strings().editImageCanvasControlsZoomOut, image: NSImage(resource: .iconEditImageZoomOut).precomposed(.white))
            button.set(handler: { [weak self] _ in
                self?.arguments?.zoomOut()
            }, for: .Click)
            centerButtons.append(button)
        }
        for button in centerButtons {
            addSubview(button)
        }
        needsLayout = true
    }

    private func drawTypeButton(_ drawType: EditImageCanvasEntity.DrawType) -> Control {
        let image = drawType == .fill ? NSImage(resource: .iconEditImageShapeFill) : NSImage(resource: .iconEditImageShapeStroke)
        let label = drawType == .fill ? "Switch to Outline" : "Switch to Fill" //TODOLANG
        let button = makeGlassIconButton(image.precomposed(.white), label: label)
        button.set(handler: { [weak self] _ in
            self?.arguments?.toggleDrawType()
        }, for: .Click)
        return button
    }

    private func flipButton() -> Control {
        let button = makeGlassIconButton(NSImage(resource: .iconEditImageEntityFlip).precomposed(.white), label: strings().voiceOverCommonFlip)
        button.set(handler: { [weak self] _ in
            self?.arguments?.flip()
        }, for: .Click)
        return button
    }

    override func layout() {
        super.layout()
        undo.centerY(x: 0)
        redo.centerY(x: undo.frame.maxX + 8)
        cancelText.centerY(x: 0)
        clearAll.centerY(x: frame.width - clearAll.frame.width)
        doneText.centerY(x: frame.width - doneText.frame.width)
        let totalWidth = centerButtons.reduce(0, { $0 + $1.frame.width }) + CGFloat(max(0, centerButtons.count - 1)) * 8
        var x = floor((frame.width - totalWidth) / 2.0)
        for button in centerButtons {
            button.centerY(x: x)
            x += button.frame.width + 8
        }
    }
}

final class EditImageCanvasSizeSlider: View {
    var value: CGFloat = 0.5 {
        didSet {
            needsDisplay = true
        }
    }
    var onChange: ((CGFloat, Bool) -> Void)?
    var onPreview: ((CGFloat?) -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var trackRect: CGRect {
        return NSMakeRect(0, 12, frame.width, frame.height - 24)
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let track = trackRect
        let path = CGMutablePath()
        path.move(to: CGPoint(x: track.midX - 9, y: track.minY))
        path.addLine(to: CGPoint(x: track.midX + 9, y: track.minY))
        path.addLine(to: CGPoint(x: track.midX + 2, y: track.maxY))
        path.addLine(to: CGPoint(x: track.midX - 2, y: track.maxY))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.fillPath()

        let knobSize: CGFloat = 24
        let y = track.minY + (1 - value) * track.height
        let knob = NSMakeRect(track.midX - knobSize / 2, y - knobSize / 2, knobSize, knobSize)
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: knob)
    }

    private func updateValue(with event: NSEvent, final: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let track = trackRect
        let updated = 1.0 - max(0, min(1, (point.y - track.minY) / track.height))
        value = updated
        onChange?(updated, final)
        onPreview?(final ? nil : updated)
    }

    override func mouseDown(with event: NSEvent) {
        updateValue(with: event, final: false)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(with: event, final: false)
    }

    override func mouseUp(with event: NSEvent) {
        updateValue(with: event, final: true)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 300.0 : 30.0)
        value = max(0, min(1, value + delta))
        onChange?(value, true)
    }
}

private final class EditImageCanvasToolView: View {
    let tool: EditImageCanvasTool
    private let shadowLayer = CALayer()
    private let backgroundLayer = CALayer()
    private let tipLayer = CALayer()
    private let bandLayer = CAGradientLayer()
    private var tipImage: NSImage?
    private var currentColor: EditImageCanvasColor?
    private var currentSize: CGFloat = 0.5
    private var hasBand: Bool = true

    static let size = NSMakeSize(20, 88)

    var onClick: ((EditImageCanvasTool) -> Void)?
    var onResize: ((EditImageCanvasTool, CGFloat, Bool) -> Void)?
    var isSelected: Bool = false
    private var dragStart: NSPoint?
    private var dragSize: CGFloat = 0
    private var dragged = false

    init(tool: EditImageCanvasTool) {
        self.tool = tool
        super.init(frame: EditImageCanvasToolView.size.bounds)
        let background: NSImage
        let shadow: NSImage
        var tipAbove = true
        switch tool {
        case .pen:
            background = NSImage(resource: .iconEditImageToolPen)
            tipImage = NSImage(resource: .iconEditImageToolPenTip)
            shadow = NSImage(resource: .iconEditImageToolPenShadow)
        case .arrow:
            background = NSImage(resource: .iconEditImageToolArrow)
            tipImage = NSImage(resource: .iconEditImageToolArrowTip)
            shadow = NSImage(resource: .iconEditImageToolArrowShadow)
        case .marker:
            background = NSImage(resource: .iconEditImageToolMarker)
            tipImage = NSImage(resource: .iconEditImageToolMarkerTip)
            shadow = NSImage(resource: .iconEditImageToolMarkerShadow)
            tipAbove = false
        case .neon:
            background = NSImage(resource: .iconEditImageToolNeon)
            tipImage = NSImage(resource: .iconEditImageToolNeonTip)
            shadow = NSImage(resource: .iconEditImageToolNeonShadow)
            tipAbove = false
        case .blur:
            background = NSImage(resource: .iconEditImageToolBlur)
            tipImage = nil
            shadow = NSImage(resource: .iconEditImageToolBlurShadow)
            tipAbove = false
            hasBand = false
        case .eraser:
            background = NSImage(resource: .iconEditImageToolEraser)
            tipImage = nil
            shadow = NSImage(resource: .iconEditImageToolEraserShadow)
            hasBand = false
        }
        shadowLayer.contents = shadow.precomposed()
        backgroundLayer.contents = background.precomposed()
        if tool == .blur {
            tipLayer.contents = NSImage(resource: .iconEditImageToolBlurTip).precomposed()
        }
        for item in [shadowLayer, backgroundLayer, tipLayer] {
            item.contentsGravity = .resize
            item.contentsScale = System.backingScale
        }
        bandLayer.cornerRadius = 1.0
        bandLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        bandLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        bandLayer.masksToBounds = true

        layer?.addSublayer(shadowLayer)
        if tipAbove {
            layer?.addSublayer(backgroundLayer)
            layer?.addSublayer(tipLayer)
        } else {
            layer?.addSublayer(tipLayer)
            layer?.addSublayer(backgroundLayer)
        }
        if hasBand {
            layer?.addSublayer(bandLayer)
        }
        layer?.masksToBounds = false
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: EditImageCanvasToolState) {
        currentSize = state.size
        if let tipImage = tipImage, currentColor != state.color {
            currentColor = state.color
            tipLayer.contents = tipImage.precomposed(state.color.withAlpha(1.0).nsColor)
            let color = state.color.withAlpha(1.0)
            let dark = color.multipliedBrightness(0.7)
            bandLayer.colors = [dark.cgColor, color.cgColor, color.cgColor, dark.cgColor]
            bandLayer.locations = [0.0, 0.15, 0.85, 1.0]
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds.insetBy(dx: -2, dy: 0)
        backgroundLayer.frame = bounds
        tipLayer.frame = bounds
        let bandHeight = (bounds.width - 8) * (0.08 + 0.92 * currentSize)
        bandLayer.frame = NSMakeRect(1.5, 32, bounds.width - 3, bandHeight)
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragSize = currentSize
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelected, let start = dragStart else {
            return
        }
        let dy = event.locationInWindow.y - start.y
        if abs(dy) > 2 {
            dragged = true
        }
        if dragged {
            onResize?(tool, max(0, min(1, dragSize + dy / 200.0)), false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragged {
            let dy = event.locationInWindow.y - (dragStart?.y ?? event.locationInWindow.y)
            onResize?(tool, max(0, min(1, dragSize + dy / 200.0)), true)
        } else {
            onClick?(tool)
        }
        dragStart = nil
        dragged = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard isSelected else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 300.0 : 30.0)
        onResize?(tool, max(0, min(1, currentSize + delta)), true)
    }
}

final class EditImageCanvasToolsRow: View {
    private var toolViews: [EditImageCanvasToolView] = []
    private let maskLayer = CAGradientLayer()
    private var selected: EditImageCanvasTool = .pen
    var arguments: EditImageCanvasArguments?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for tool in EditImageCanvasTool.allCases {
            let view = EditImageCanvasToolView(tool: tool)
            view.onClick = { [weak self] tool in
                self?.arguments?.selectTool(tool)
            }
            view.onResize = { [weak self] _, size, final in
                self?.arguments?.updateSize(size, final)
                self?.arguments?.previewSize(final ? nil : size)
            }
            toolViews.append(view)
            addSubview(view)
        }
        maskLayer.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        maskLayer.locations = [0.0, 0.8, 1.0]
        maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
        maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.mask = maskLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: EditImageCanvasState, animated: Bool) {
        let changed = selected != state.tool
        selected = state.tool
        for view in toolViews {
            view.isSelected = view.tool == state.tool
            if let toolState = state.tools[view.tool] {
                view.update(state: toolState)
            }
        }
        layoutTools(animated: animated && changed)
    }

    private func layoutTools(animated: Bool) {
        let spacing: CGFloat = 44
        let totalWidth = spacing * CGFloat(toolViews.count - 1)
        let left = (frame.width - totalWidth) / 2.0
        for (i, view) in toolViews.enumerated() {
            let x = left + spacing * CGFloat(i) - EditImageCanvasToolView.size.width / 2.0
            let y: CGFloat = view.isSelected ? 10 : 24
            let rect = NSMakeRect(floor(x), y, EditImageCanvasToolView.size.width, EditImageCanvasToolView.size.height)
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    view.animator().frame = rect
                }, completionHandler: nil)
            } else {
                view.frame = rect
            }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        CATransaction.commit()
        layoutTools(animated: false)
    }
}

final class EditImageCanvasTextSettingsRow: View {
    private let style = ImageButton()
    private let alignment = ImageButton()
    private let font = TextButton()
    var arguments: EditImageCanvasArguments?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for button in [style, alignment] {
            button.autohighlight = false
            button.scaleOnClick = true
            addSubview(button)
        }
        style.setAccessibilityLabel("Text Style") //TODOLANG
        alignment.setAccessibilityLabel("Text Alignment") //TODOLANG
        font.autohighlight = false
        font.scaleOnClick = true
        font.set(color: .white, for: .Normal)
        font.set(background: NSColor.white.withAlphaComponent(0.12), for: .Normal)
        font.layer?.cornerRadius = 8
        addSubview(font)

        style.set(handler: { [weak self] _ in
            self?.arguments?.cycleTextStyle()
        }, for: .Click)
        alignment.set(handler: { [weak self] _ in
            self?.arguments?.cycleTextAlignment()
        }, for: .Click)
        font.set(handler: { [weak self] control in
            self?.arguments?.selectFont(control)
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: EditImageCanvasEntity.Text) {
        let styleImage: NSImage
        switch text.style {
        case .regular:
            styleImage = NSImage(resource: .iconEditImageTextDefault)
        case .filled:
            styleImage = NSImage(resource: .iconEditImageTextFilled)
        case .semi:
            styleImage = NSImage(resource: .iconEditImageTextSemi)
        }
        style.set(image: styleImage.precomposed(), for: .Normal)
        _ = style.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        alignment.set(image: EditImageCanvasGlyph.alignment(text.alignment), for: .Normal)
        _ = alignment.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)

        font.set(font: text.font.font(size: 15), for: .Normal)
        font.set(text: text.font.title, for: .Normal)
        font.direction = .right
        font.set(image: NSImage(resource: .iconEditImageFontArrow).precomposed(.white), for: .Normal)
        _ = font.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, 32), thatFit: false)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let total = style.frame.width + alignment.frame.width + font.frame.width + 16
        var x = floor((frame.width - total) / 2.0)
        style.centerY(x: x)
        x += style.frame.width + 8
        alignment.centerY(x: x)
        x += alignment.frame.width + 8
        font.centerY(x: x)
    }
}

private final class EditImageCanvasColorButton: View {
    var color: EditImageCanvasColor = .white {
        didSet {
            needsDisplay = true
        }
    }
    var onClick: (() -> Void)?
    var onQuickColor: ((EditImageCanvasColor, Bool) -> Void)?
    private let spectrum = NSImage(resource: .iconEditImageRoundSpectrum)
    private var longPressTimer: EditImageCanvasDelayTimer?
    private var quickPicker: EditImageCanvasQuickSpectrumView?
    private var didLongPress = false

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let isPreset = color.alpha >= 1.0 && EditImageCanvasToolSettings.presets.contains(where: { $0.isSameRGB(color) })
        let rect = bounds.focus(NSMakeSize(30, 30))
        if isPreset, let image = spectrum.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            editImageCanvasDrawUpright(image, in: rect, context: ctx)
        } else {
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 4, dy: 4))
        }
    }

    override func mouseDown(with event: NSEvent) {
        didLongPress = false
        let timer = EditImageCanvasDelayTimer(timeout: 0.4, action: { [weak self] in
            self?.beginQuickColor()
        })
        longPressTimer = timer
        timer.start()
    }

    override func mouseDragged(with event: NSEvent) {
        guard didLongPress, let picker = quickPicker else {
            return
        }
        if let color = picker.color(at: picker.convert(event.locationInWindow, from: nil)) {
            onQuickColor?(color, false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        longPressTimer?.invalidate()
        longPressTimer = nil
        if didLongPress, let picker = quickPicker {
            if let color = picker.color(at: picker.convert(event.locationInWindow, from: nil)) {
                onQuickColor?(color, true)
            }
            picker.removeFromSuperview()
            quickPicker = nil
        } else {
            onClick?()
        }
        didLongPress = false
    }

    private func beginQuickColor() {
        guard let container = window?.contentView else {
            return
        }
        didLongPress = true
        let picker = EditImageCanvasQuickSpectrumView(frame: NSMakeRect(0, 0, 300, 220))
        let origin = convert(NSMakePoint(0, 0), to: container)
        let containerFlipped = container.isFlipped
        let y = containerFlipped ? origin.y - picker.frame.height - 10 : origin.y + frame.height + 10
        picker.setFrameOrigin(NSMakePoint(max(10, origin.x - 20), y))
        container.addSubview(picker)
        quickPicker = picker
    }
}

final class EditImageCanvasDelayTimer {
    private var timer: Timer?
    private let timeout: Double
    private let action: () -> Void

    init(timeout: Double, action: @escaping () -> Void) {
        self.timeout = timeout
        self.action = action
    }

    func start() {
        let action = self.action
        let timer = Timer(timeInterval: timeout, repeats: false, block: { _ in
            action()
        })
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

final class EditImageCanvasQuickSpectrumView: View {
    private let image: CGImage

    required init(frame frameRect: NSRect) {
        self.image = editImageCanvasSpectrumImage(size: frameRect.size)
        super.init(frame: frameRect)
        layer?.cornerRadius = 17
        layer?.masksToBounds = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        editImageCanvasDrawUpright(image, in: bounds, context: ctx)
    }

    func color(at point: NSPoint) -> EditImageCanvasColor? {
        let x = max(0, min(1, point.x / frame.width))
        let y = max(0, min(1, point.y / frame.height))
        return editImageCanvasSpectrumColor(x: x, y: y)
    }
}

final class EditImageCanvasColorRow: View {
    private let colorButton = EditImageCanvasColorButton(frame: NSMakeRect(0, 0, 44, 44))
    private var swatches: [Control] = []
    private let plus = ImageButton(frame: NSMakeRect(0, 0, 44, 44))
    private var currentColor: EditImageCanvasColor = .white
    var arguments: EditImageCanvasArguments? {
        didSet {
            colorButton.onClick = { [weak self] in
                self?.arguments?.showColorPicker()
            }
            colorButton.onQuickColor = { [weak self] color, final in
                self?.arguments?.selectColor(color, final)
            }
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(colorButton)
        for color in EditImageCanvasToolSettings.presets {
            let swatch = Control(frame: NSMakeRect(0, 0, 30, 30))
            swatch.scaleOnClick = true
            swatch.set(handler: { [weak self] _ in
                self?.arguments?.selectColor(color, true)
            }, for: .Click)
            swatch.setAccessibilityLabel("\(strings().voiceOverCommonColor) #\(color.hexString)")
            swatches.append(swatch)
            addSubview(swatch)
        }
        plus.autohighlight = false
        plus.scaleOnClick = true
        plus.set(image: NSImage(resource: .iconEditImageAdd).precomposed(.white), for: .Normal)
        plus.set(background: NSColor.white.withAlphaComponent(0.15), for: .Normal)
        plus.layer?.cornerRadius = 12
        addSubview(plus)
        plus.setAccessibilityLabel(strings().voiceOverCommonAdd)
        plus.set(handler: { [weak self] control in
            self?.arguments?.plus(control)
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(color: EditImageCanvasColor) {
        currentColor = color
        colorButton.color = color
        for (i, swatch) in swatches.enumerated() {
            let preset = EditImageCanvasToolSettings.presets[i]
            let selected = color.alpha >= 1.0 && preset.isSameRGB(color)
            swatch.layer?.contents = EditImageCanvasColorRow.swatchImage(preset, selected: selected)
        }
    }

    private static func swatchImage(_ color: EditImageCanvasColor, selected: Bool) -> CGImage {
        return generateImage(NSMakeSize(30, 30), rotatedContext: { size, context in
            context.clear(size.bounds)
            let rect = size.bounds.insetBy(dx: 3, dy: 3)
            if selected {
                context.setStrokeColor(NSColor.white.cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: size.bounds.insetBy(dx: 1, dy: 1))
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
            } else {
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: rect)
            }
        })!
    }

    override func layout() {
        super.layout()
        colorButton.centerY(x: 0)
        plus.centerY(x: frame.width - plus.frame.width)
        let left = colorButton.frame.maxX + 8
        let right = plus.frame.minX - 8
        let count = CGFloat(swatches.count)
        let available = right - left
        let step = available / count
        let side = min(30, floor(step - 2))
        for (i, swatch) in swatches.enumerated() {
            swatch.setFrameSize(NSMakeSize(side, side))
            let x = left + step * CGFloat(i) + (step - swatch.frame.width) / 2.0
            swatch.centerY(x: floor(x))
        }
    }
}

final class EditImageCanvasModeRow: View {
    private let cancel = ImageButton(frame: NSMakeRect(0, 0, 40, 40))
    private let done = ImageButton(frame: NSMakeRect(0, 0, 40, 40))
    private let pill = View()
    private let selection = View()
    private let draw: TextButton
    private let sticker: TextButton
    private let text: TextButton
    private var mode: EditImageCanvasMode = .drawing
    private var stickersAvailable = true
    var arguments: EditImageCanvasArguments?

    required init(frame frameRect: NSRect) {
        self.draw = makeTextButton(strings().editImageCanvasControlsDraw, font: .medium(.text))
        self.sticker = makeTextButton(strings().editImageCanvasControlsSticker, font: .medium(.text))
        self.text = makeTextButton(strings().editImageCanvasControlsText, font: .medium(.text))
        super.init(frame: frameRect)

        cancel.autohighlight = false
        cancel.scaleOnClick = true
        cancel.set(image: EditImageCanvasGlyph.close(), for: .Normal)
        cancel.set(background: NSColor.white.withAlphaComponent(0.15), for: .Normal)
        cancel.layer?.cornerRadius = 20
        cancel.setAccessibilityLabel(strings().voiceOverCommonCancel)

        done.autohighlight = false
        done.scaleOnClick = true
        done.set(image: EditImageCanvasGlyph.check(), for: .Normal)
        done.set(background: nightAccentPalette.accent, for: .Normal)
        done.layer?.cornerRadius = 20
        done.setAccessibilityLabel(strings().voiceOverCommonDone)

        pill.backgroundColor = NSColor.white.withAlphaComponent(0.15)
        pill.layer?.cornerRadius = 20
        selection.backgroundColor = NSColor.white.withAlphaComponent(0.25)
        selection.layer?.cornerRadius = 16
        selection.isEventLess = true

        addSubview(cancel)
        addSubview(done)
        addSubview(pill)
        pill.addSubview(selection)
        pill.addSubview(draw)
        pill.addSubview(sticker)
        pill.addSubview(text)

        cancel.set(handler: { [weak self] _ in
            self?.arguments?.cancel()
        }, for: .Click)
        done.set(handler: { [weak self] _ in
            self?.arguments?.done()
        }, for: .Click)
        draw.set(handler: { [weak self] _ in
            self?.arguments?.modeDraw()
        }, for: .Click)
        sticker.set(handler: { [weak self] control in
            self?.arguments?.modeSticker(control)
        }, for: .Click)
        text.set(handler: { [weak self] _ in
            self?.arguments?.modeText()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(mode: EditImageCanvasMode, stickersAvailable: Bool, animated: Bool) {
        let changed = self.mode != mode
        self.mode = mode
        self.stickersAvailable = stickersAvailable
        sticker.isHidden = !stickersAvailable
        layoutPill(animated: animated && changed)
    }

    private var segments: [TextButton] {
        return stickersAvailable ? [draw, sticker, text] : [draw, text]
    }

    private func layoutPill(animated: Bool) {
        let items = segments
        let available = frame.width - cancel.frame.width - done.frame.width - 32
        let segmentWidth = min(82, available / CGFloat(items.count))
        pill.setFrameSize(NSMakeSize(segmentWidth * CGFloat(items.count) + 8, 40))
        pill.center()
        for (i, item) in items.enumerated() {
            item.setFrameSize(NSMakeSize(segmentWidth, 32))
            item.setFrameOrigin(NSMakePoint(4 + segmentWidth * CGFloat(i), 4))
        }
        let selectedItem: TextButton
        switch mode {
        case .drawing:
            selectedItem = draw
        case .sticker:
            selectedItem = stickersAvailable ? sticker : draw
        case .text:
            selectedItem = text
        }
        let rect = selectedItem.frame
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                selection.animator().frame = rect
            }, completionHandler: nil)
        } else {
            selection.frame = rect
        }
    }

    override func layout() {
        super.layout()
        cancel.centerY(x: 0)
        done.centerY(x: frame.width - done.frame.width)
        layoutPill(animated: false)
    }
}
