import Cocoa
import TGUIKit
import ColorPalette

final class EditImageCanvasInteraction {
    let state: () -> EditImageCanvasState
    let update: (Bool, (inout EditImageCanvasState) -> Void) -> Void
    let pushUndo: () -> Void
    let commitStroke: (EditImageDrawTouch) -> Void
    let showEntityMenu: (Int64, NSEvent, NSView) -> Void
    let beginTextEditing: (Int64) -> Void
    let endTextEditing: (Bool) -> Void
    let textChanged: (String) -> Void
    let addImageSticker: (CGImage) -> Void
    let zoomChanged: () -> Void

    init(state: @escaping () -> EditImageCanvasState, update: @escaping (Bool, (inout EditImageCanvasState) -> Void) -> Void, pushUndo: @escaping () -> Void, commitStroke: @escaping (EditImageDrawTouch) -> Void, showEntityMenu: @escaping (Int64, NSEvent, NSView) -> Void, beginTextEditing: @escaping (Int64) -> Void, endTextEditing: @escaping (Bool) -> Void, textChanged: @escaping (String) -> Void, addImageSticker: @escaping (CGImage) -> Void, zoomChanged: @escaping () -> Void) {
        self.state = state
        self.update = update
        self.pushUndo = pushUndo
        self.commitStroke = commitStroke
        self.showEntityMenu = showEntityMenu
        self.beginTextEditing = beginTextEditing
        self.endTextEditing = endTextEditing
        self.textChanged = textChanged
        self.addImageSticker = addImageSticker
        self.zoomChanged = zoomChanged
    }
}

final class EditImageCanvasDrawView: View {
    private(set) var touches: [EditImageDrawTouch] = []
    private var cache: CGImage?
    private var cacheSize: NSSize = .zero
    var blurImage: CGImage? {
        didSet {
            if oldValue !== blurImage {
                rebuildCache()
            }
        }
    }
    var activeTouch: EditImageDrawTouch? {
        didSet {
            needsDisplay = true
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(touches: [EditImageDrawTouch]) {
        guard touches.count != self.touches.count || !zip(touches, self.touches).allSatisfy({ $0 === $1 }) else {
            return
        }
        self.touches = touches
        rebuildCache()
    }

    private func rebuildCache() {
        let size = frame.size
        cacheSize = size
        guard size.width > 0, size.height > 0, !touches.isEmpty else {
            cache = nil
            needsDisplay = true
            return
        }
        let touches = self.touches
        let blurImage = self.blurImage
        cache = generateImage(size, contextGenerator: { size, context in
            context.clear(size.bounds)
            applyPaints(touches, for: context, imageSize: size, blurImage: blurImage)
        })
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if cacheSize != frame.size {
            rebuildCache()
        }
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        if let cache = cache {
            ctx.draw(cache, in: bounds)
        }
        if let activeTouch = activeTouch {
            applyPaint(activeTouch, for: ctx, imageSize: bounds.size, blurImage: blurImage)
            ctx.setBlendMode(.normal)
        }
    }
}

final class EditImageCanvasEntitiesView: View {
    var entities: [EditImageCanvasEntity] = [] {
        didSet {
            if oldValue != entities {
                cache.prune(Set(entities.map { $0.id }))
                animator.update(entities: entities)
                needsDisplay = true
            }
        }
    }
    private let animator = EditImageCanvasStickerAnimator()
    private var stickerFrames: [Int64: CGImage] = [:]
    var excluding: Int64? {
        didSet {
            if oldValue != excluding {
                needsDisplay = true
            }
        }
    }
    let cache = EditImageCanvasTextLayoutCache()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        animator.updated = { [weak self] frames in
            self?.applyStickerFrames(frames)
        }
    }

    private func applyStickerFrames(_ frames: [Int64: CGImage]) {
        let ids = Set(frames.keys).union(stickerFrames.keys)
        stickerFrames = frames
        for entity in entities where ids.contains(entity.id) {
            guard let sticker = entity.sticker else {
                continue
            }
            let scale = bounds.width / max(1, entity.referenceSize.width)
            let rect = CGRect(x: -sticker.baseSize.width / 2.0, y: -sticker.baseSize.height / 2.0, width: sticker.baseSize.width, height: sticker.baseSize.height)
            layer?.setNeedsDisplay(rect.applying(entity.localTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))).insetBy(dx: -2, dy: -2))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        animator.isActive = window != nil
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        applyEntities(entities, for: ctx, size: bounds.size, excluding: excluding, cache: cache, stickerFrames: stickerFrames)
    }
}

enum EditImageCanvasHandle: Equatable {
    case scaleRotate
    case resize(Int, Int)
    case tail
    case vectorStart
    case vectorEnd
    case vectorMid
}

final class EditImageCanvasSelectionView: View {
    var entity: EditImageCanvasEntity? {
        didSet {
            needsDisplay = true
        }
    }
    var contentFrame: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }
    var snapX: Bool = false
    var snapY: Bool = false
    var rotationGuide: CGFloat?
    var textSize: (EditImageCanvasEntity.Text, CGSize) -> CGSize = { _, _ in .zero }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var viewScale: CGFloat {
        guard let entity = entity else {
            return 1
        }
        return contentFrame.width / max(1, entity.referenceSize.width)
    }

    func toCanvas(_ point: CGPoint) -> CGPoint {
        return CGPoint(x: contentFrame.minX + point.x * viewScale, y: contentFrame.minY + point.y * viewScale)
    }

    private func canvasTransform(_ entity: EditImageCanvasEntity) -> CGAffineTransform {
        let scale = viewScale
        var transform = CGAffineTransform(translationX: contentFrame.minX, y: contentFrame.minY)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: entity.position.x, y: entity.position.y)
        transform = transform.rotated(by: entity.rotation)
        transform = transform.scaledBy(x: entity.scale, y: entity.scale)
        return transform
    }

    func handles() -> [(EditImageCanvasHandle, CGPoint)] {
        guard let entity = entity else {
            return []
        }
        switch entity.content {
        case let .vector(vector):
            let mid = editImageCanvasVectorMidPoint(start: vector.start, end: vector.end, mid: vector.mid)
            return [(.vectorStart, toCanvas(vector.start)), (.vectorEnd, toCanvas(vector.end)), (.vectorMid, toCanvas(mid))]
        case .text, .sticker:
            let rect = selectionRect(entity)
            let transform = canvasTransform(entity)
            return [(.scaleRotate, CGPoint(x: rect.minX, y: rect.midY).applying(transform)), (.scaleRotate, CGPoint(x: rect.maxX, y: rect.midY).applying(transform))]
        case let .shape(shape):
            return resizeHandles(entity, size: shape.size)
        case let .bubble(bubble):
            var result = resizeHandles(entity, size: bubble.size)
            let tail = CGPoint(x: -bubble.size.width / 2.0 + bubble.tailPosition.x * bubble.size.width, y: bubble.size.height / 2.0 + bubble.tailPosition.y)
            result.append((.tail, tail.applying(canvasTransform(entity))))
            return result
        }
    }

    private func resizeHandles(_ entity: EditImageCanvasEntity, size: CGSize) -> [(EditImageCanvasHandle, CGPoint)] {
        let transform = canvasTransform(entity)
        var result: [(EditImageCanvasHandle, CGPoint)] = []
        for dy in -1 ... 1 {
            for dx in -1 ... 1 where dx != 0 || dy != 0 {
                let point = CGPoint(x: CGFloat(dx) * size.width / 2.0, y: CGFloat(dy) * size.height / 2.0)
                result.append((.resize(dx, dy), point.applying(transform)))
            }
        }
        return result
    }

    private func selectionRect(_ entity: EditImageCanvasEntity) -> CGRect {
        let rect = entity.selectionLocalRect(textSize: textSize)
        let inset: CGFloat
        switch entity.content {
        case .sticker:
            inset = 18
        case .text:
            inset = 15
        default:
            inset = 5.5
        }
        let localInset = inset / max(0.001, viewScale * entity.scale)
        return rect.insetBy(dx: -localInset, dy: -localInset)
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        if snapX || snapY {
            ctx.setStrokeColor(nightAccentPalette.accent.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1)
            if snapX {
                ctx.move(to: CGPoint(x: contentFrame.midX, y: contentFrame.minY))
                ctx.addLine(to: CGPoint(x: contentFrame.midX, y: contentFrame.maxY))
            }
            if snapY {
                ctx.move(to: CGPoint(x: contentFrame.minX, y: contentFrame.midY))
                ctx.addLine(to: CGPoint(x: contentFrame.maxX, y: contentFrame.midY))
            }
            ctx.strokePath()
        }
        guard let entity = entity else {
            return
        }
        if let angle = rotationGuide {
            let center = toCanvas(entity.position)
            let length = max(bounds.width, bounds.height)
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [12, 12])
            ctx.move(to: CGPoint(x: center.x - cos(angle) * length, y: center.y - sin(angle) * length))
            ctx.addLine(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
            ctx.strokePath()
            ctx.restoreGState()
        }
        switch entity.content {
        case .text, .sticker:
            let rect = selectionRect(entity)
            var transform = canvasTransform(entity)
            let path: CGPath
            let dashCount: CGFloat
            if case .sticker = entity.content {
                path = CGPath(ellipseIn: rect, transform: &transform)
                dashCount = 10
            } else {
                let radius = 12.0 / max(0.001, viewScale * entity.scale)
                path = CGPath(roundedRect: rect, cornerWidth: min(radius, rect.width / 2), cornerHeight: min(radius, rect.height / 2), transform: &transform)
                dashCount = 12
            }
            let bounding = path.boundingBoxOfPath
            let perimeter = (bounding.width + bounding.height) * 2.0
            let dash = perimeter / dashCount * 0.25
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [dash, dash])
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        default:
            break
        }
        for (handle, point) in handles() {
            let rect = CGRect(x: point.x - 5.5, y: point.y - 5.5, width: 11, height: 11)
            switch handle {
            case .tail, .vectorMid:
                ctx.setFillColor(nightAccentPalette.greenUI.cgColor)
            default:
                ctx.setFillColor(nightAccentPalette.accent.cgColor)
            }
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: rect)
        }
    }
}

final class EditImageCanvasTextEditor: NSTextView {
    var onChange: ((String) -> Void)?
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command) {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?(string)
    }
}

final class EditImageCanvasTextEditorBackground: View {
    weak var editor: EditImageCanvasTextEditor?
    var text: EditImageCanvasEntity.Text?
    var unit: CGFloat = 1

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        guard let editor = editor, let text = text, let frameColor = EditImageCanvasTextLayout.frameColor(for: text), !editor.string.isEmpty, let layoutManager = editor.layoutManager, let container = editor.textContainer, let storage = editor.textStorage else {
            return
        }
        let rects = EditImageCanvasTextLayout.makeBackgroundRects(layoutManager: layoutManager, storage: storage, container: container, alignment: text.alignment)
        let origin = editor.textContainerOrigin
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.setAlpha(frameColor.alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(frameColor.withAlpha(1.0).cgColor)
        ctx.setStrokeColor(frameColor.withAlpha(1.0).cgColor)
        ctx.setLineWidth(unit)
        for path in EditImageCanvasTextLayout.backgroundPaths(rects, unit: unit) {
            ctx.addPath(path)
            ctx.drawPath(using: .fillStroke)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}

private enum EditImageCanvasDragMode {
    case none
    case stroke
    case move(id: Int64, start: NSPoint, original: EditImageCanvasEntity, wasSelected: Bool)
    case handle(id: Int64, handle: EditImageCanvasHandle, start: NSPoint, original: EditImageCanvasEntity)
    case consumed
}

final class EditImageCanvasArea: View {
    let imageSize: CGSize
    private let contentView = View()
    private let imageView = ImageView()
    let drawView = EditImageCanvasDrawView(frame: .zero)
    let entitiesView = EditImageCanvasEntitiesView(frame: .zero)
    let selectionView = EditImageCanvasSelectionView(frame: .zero)
    private var editingOverlay: Control?
    private var editorBackground: EditImageCanvasTextEditorBackground?
    private(set) var textEditor: EditImageCanvasTextEditor?
    private var editorScale: CGFloat = 1
    private var editorAttributesKey: EditImageCanvasEntity.Text?
    var interaction: EditImageCanvasInteraction?

    private(set) var zoom: CGFloat = 1
    private var zoomOffset: CGPoint = .zero
    private var dragMode: EditImageCanvasDragMode = .none
    private var didDrag = false
    private var fillTimer: EditImageCanvasDelayTimer?
    private var gestureUndoPushed = false

    init(frame frameRect: NSRect, image: CGImage) {
        self.imageSize = image.size
        super.init(frame: frameRect)
        layer?.masksToBounds = true
        imageView.image = image
        imageView.background = .white
        contentView.addSubview(imageView)
        contentView.addSubview(drawView)
        contentView.addSubview(entitiesView)
        contentView.isEventLess = true
        addSubview(contentView)
        addSubview(selectionView)
        selectionView.textSize = { [weak self] text, referenceSize in
            return self?.entitiesView.cache.boxSize(for: text, referenceSize: referenceSize) ?? .zero
        }
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var baseContentFrame: CGRect {
        let fitted = imageSize.fitted(NSMakeSize(max(1, frame.width), max(1, frame.height)))
        return CGRect(x: floor((frame.width - fitted.width) / 2.0), y: floor((frame.height - fitted.height) / 2.0), width: fitted.width, height: fitted.height)
    }

    var contentFrame: CGRect {
        let base = baseContentFrame
        let size = NSMakeSize(base.width * zoom, base.height * zoom)
        var x = (frame.width - size.width) / 2.0 + zoomOffset.x
        var y = (frame.height - size.height) / 2.0 + zoomOffset.y
        if size.width > frame.width {
            x = min(0, max(frame.width - size.width, x))
        } else {
            x = (frame.width - size.width) / 2.0
        }
        if size.height > frame.height {
            y = min(0, max(frame.height - size.height, y))
        } else {
            y = (frame.height - size.height) / 2.0
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    var viewScale: CGFloat {
        return contentFrame.width / max(1, imageSize.width)
    }

    func toReference(_ point: NSPoint) -> CGPoint {
        let frame = contentFrame
        let scale = viewScale
        return CGPoint(x: (point.x - frame.minX) / scale, y: (point.y - frame.minY) / scale)
    }

    func toCanvas(_ point: CGPoint) -> NSPoint {
        let frame = contentFrame
        let scale = viewScale
        return NSPoint(x: frame.minX + point.x * scale, y: frame.minY + point.y * scale)
    }

    var visibleReferenceCenter: CGPoint {
        return toReference(NSMakePoint(frame.width / 2.0, frame.height / 2.0))
    }

    func setZoom(_ value: CGFloat, anchor: NSPoint?) {
        let anchor = anchor ?? NSMakePoint(frame.width / 2.0, frame.height / 2.0)
        let reference = toReference(anchor)
        zoom = max(1, min(3, value))
        let base = baseContentFrame
        let size = NSMakeSize(base.width * zoom, base.height * zoom)
        let scale = size.width / max(1, imageSize.width)
        zoomOffset = CGPoint(x: anchor.x - reference.x * scale - (frame.width - size.width) / 2.0, y: anchor.y - reference.y * scale - (frame.height - size.height) / 2.0)
        clampZoomOffset()
        layoutContent()
        interaction?.zoomChanged()
    }

    private func clampZoomOffset() {
        let current = contentFrame
        zoomOffset = CGPoint(x: current.minX - (frame.width - current.width) / 2.0, y: current.minY - (frame.height - current.height) / 2.0)
    }

    private func layoutContent() {
        let frame = contentFrame
        contentView.frame = frame
        imageView.frame = contentView.bounds
        drawView.frame = contentView.bounds
        entitiesView.frame = contentView.bounds
        selectionView.frame = bounds
        selectionView.contentFrame = frame
        editingOverlay?.frame = bounds
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    func update(state: EditImageCanvasState) {
        drawView.update(touches: state.touches)
        entitiesView.entities = state.entities
        entitiesView.excluding = state.editingEntityId
        if state.editingEntityId == nil {
            selectionView.entity = state.selectedEntity
        } else {
            selectionView.entity = nil
        }
        if let editingId = state.editingEntityId, let entity = state.entity(editingId), let text = entity.text {
            if textEditor == nil {
                startEditor(entity: entity, text: text)
            } else {
                applyEditor(entity: entity, text: text, resetString: false)
            }
        } else if textEditor != nil {
            stopEditor()
        }
    }

    private func startEditor(entity: EditImageCanvasEntity, text: EditImageCanvasEntity.Text) {
        let overlay = Control(frame: bounds)
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        overlay.set(handler: { [weak self] _ in
            self?.interaction?.endTextEditing(true)
        }, for: .Down)
        addSubview(overlay)
        editingOverlay = overlay

        let background = EditImageCanvasTextEditorBackground(frame: .zero)
        addSubview(background)
        editorBackground = background

        let editor = EditImageCanvasTextEditor(frame: NSMakeRect(0, 0, 100, 40))
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = false
        editor.focusRingType = .none
        editor.onChange = { [weak self] string in
            self?.interaction?.textChanged(string)
        }
        editor.onCommit = { [weak self] in
            self?.interaction?.endTextEditing(true)
        }
        addSubview(editor)
        background.editor = editor
        textEditor = editor

        let referenceScale = viewScale * entity.scale
        let layout = EditImageCanvasTextLayout(text: text, referenceSize: entity.referenceSize)
        let maxWidth = frame.width * 0.95
        editorScale = min(referenceScale, maxWidth / max(1, layout.boxSize.width))
        applyEditor(entity: entity, text: text, resetString: true)
        window?.makeFirstResponder(editor)
    }

    private func applyEditor(entity: EditImageCanvasEntity, text: EditImageCanvasEntity.Text, resetString: Bool) {
        guard let editor = textEditor, let background = editorBackground else {
            return
        }
        let unit = EditImageCanvasMetrics.unit(entity.referenceSize)
        let k = editorScale
        let fontSize = EditImageCanvasMetrics.fontSize(text.fontSize, referenceSize: entity.referenceSize)
        let font = text.font.font(size: fontSize * k)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = text.alignment.nsAlignment
        let textColor = EditImageCanvasTextLayout.textColor(for: text)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor.nsColor, .paragraphStyle: paragraph]
        if text.style == .regular {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowOffset = NSMakeSize(0, -4 * unit * k)
            shadow.shadowBlurRadius = 8 * unit * k
            attributes[.shadow] = shadow
        }
        var key = text
        key.string = ""
        if resetString || editorAttributesKey != key {
            editorAttributesKey = key
            let selection = editor.selectedRange()
            if resetString {
                editor.string = text.string
            }
            if let storage = editor.textStorage, storage.length > 0 {
                storage.setAttributes(attributes, range: NSMakeRange(0, storage.length))
            }
            editor.typingAttributes = attributes
            editor.alignment = text.alignment.nsAlignment
            editor.insertionPointColor = (text.style == .filled && text.color.lightness > 0.99) ? nightAccentPalette.accent : .white
            editor.textContainer?.lineFragmentPadding = floor(fontSize * 0.24) * k
            if !resetString {
                let length = (editor.string as NSString).length
                let location = min(selection.location, length)
                editor.setSelectedRange(NSMakeRange(location, min(selection.length, length - location)))
            }
        }

        let layout = EditImageCanvasTextLayout(text: text, referenceSize: entity.referenceSize)
        let size = NSMakeSize(ceil(layout.boxSize.width * k), ceil(layout.boxSize.height * k))
        editor.textContainer?.size = NSMakeSize(size.width, CGFloat.greatestFiniteMagnitude)
        let rect = CGRect(x: floor((frame.width - size.width) / 2.0), y: floor((frame.height - size.height) / 2.0), width: size.width, height: size.height)
        editor.frame = rect
        background.frame = rect
        background.text = text
        background.unit = unit * k
        background.needsDisplay = true
        editor.needsDisplay = true
    }

    private func stopEditor() {
        if let editor = textEditor, window?.firstResponder === editor {
            window?.makeFirstResponder(nil)
        }
        textEditor?.removeFromSuperview()
        textEditor = nil
        editorBackground?.removeFromSuperview()
        editorBackground = nil
        editingOverlay?.removeFromSuperview()
        editingOverlay = nil
        editorAttributesKey = nil
    }

    private func textSize(_ text: EditImageCanvasEntity.Text, _ referenceSize: CGSize) -> CGSize {
        return entitiesView.cache.boxSize(for: text, referenceSize: referenceSize)
    }

    private func hitEntity(at point: NSPoint, state: EditImageCanvasState) -> EditImageCanvasEntity? {
        let reference = toReference(point)
        let tolerance = 8.0 / max(0.0001, viewScale)
        for entity in state.entities.reversed() {
            if entity.contains(reference, tolerance: tolerance, textSize: textSize) {
                return entity
            }
        }
        return nil
    }

    private func hitHandle(at point: NSPoint) -> EditImageCanvasHandle? {
        for (handle, position) in selectionView.handles().reversed() {
            if hypot(position.x - point.x, position.y - point.y) <= 12 {
                return handle
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let interaction = interaction else {
            return
        }
        let state = interaction.state()
        let point = convert(event.locationInWindow, from: nil)
        didDrag = false
        gestureUndoPushed = false
        if state.editingEntityId != nil {
            interaction.endTextEditing(true)
            dragMode = .consumed
            return
        }
        if let selected = state.selectedEntity, let handle = hitHandle(at: point) {
            dragMode = .handle(id: selected.id, handle: handle, start: point, original: selected)
            return
        }
        if let entity = hitEntity(at: point, state: state) {
            if event.clickCount == 2, entity.isText {
                dragMode = .consumed
                interaction.beginTextEditing(entity.id)
                return
            }
            let wasSelected = state.selectedEntityId == entity.id
            if !wasSelected {
                interaction.update(false, { state in
                    state.selectedEntityId = entity.id
                })
            }
            dragMode = .move(id: entity.id, start: point, original: entity, wasSelected: wasSelected)
            return
        }
        if state.selectedEntityId != nil {
            interaction.update(false, { state in
                state.selectedEntityId = nil
            })
            dragMode = .consumed
            return
        }
        beginStroke(event: event, state: state)
    }

    private func beginStroke(event: NSEvent, state: EditImageCanvasState) {
        let tool = state.tool
        if tool == .eraser && state.touches.isEmpty {
            dragMode = .consumed
            return
        }
        guard let toolState = state.tools[tool] else {
            dragMode = .consumed
            return
        }
        let point = drawView.convert(event.locationInWindow, from: nil)
        let width = EditImageCanvasMetrics.strokeWidth(tool: tool, size: toolState.size / zoom, canvasSize: imageSize) * viewScale
        let color = tool.hasColor ? toolState.color : EditImageCanvasColor.white
        drawView.activeTouch = EditImageDrawTouch(action: tool.action, point: point, canvasSize: drawView.frame.size, color: color.nsColor, width: width)
        dragMode = .stroke

        let timer = EditImageCanvasDelayTimer(timeout: 0.7, action: { [weak self] in
            self?.fillCanvas()
        })
        fillTimer = timer
        timer.start()
    }

    private func fillCanvas() {
        fillTimer = nil
        guard case .stroke = dragMode, let touch = drawView.activeTouch, touch.lines.count == 1, let interaction = interaction else {
            return
        }
        let state = interaction.state()
        guard let toolState = state.tools[state.tool] else {
            return
        }
        let action: EditImageDrawTouch.Action
        var color = toolState.color
        switch state.tool {
        case .eraser:
            action = .eraseAll
        case .blur:
            action = .blurAll
        case .marker:
            action = .fill
            color = color.withAlpha(color.alpha * 0.7)
        default:
            action = .fill
        }
        let fill = EditImageDrawTouch(action: action, point: touch.lines[0], canvasSize: touch.canvasSize, color: color.nsColor, width: touch.width)
        drawView.activeTouch = nil
        dragMode = .consumed
        interaction.commitStroke(fill)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let interaction = interaction else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .none, .consumed:
            break
        case .stroke:
            guard let touch = drawView.activeTouch else {
                return
            }
            let drawPoint = drawView.convert(event.locationInWindow, from: nil)
            let state = interaction.state()
            if let last = touch.lines.last, hypot(last.x - drawPoint.x, last.y - drawPoint.y) < state.tool.filterDistance {
                return
            }
            fillTimer?.invalidate()
            fillTimer = nil
            touch.addPoint(drawPoint)
            drawView.needsDisplay = true
        case let .move(id, start, original, _):
            let delta = NSMakePoint(point.x - start.x, point.y - start.y)
            if !didDrag && hypot(delta.x, delta.y) < 2 {
                return
            }
            if !didDrag {
                didDrag = true
                interaction.pushUndo()
            }
            moveEntity(id: id, original: original, delta: delta)
        case let .handle(id, handle, start, original):
            let delta = NSMakePoint(point.x - start.x, point.y - start.y)
            if !didDrag {
                didDrag = true
                interaction.pushUndo()
            }
            dragHandle(id: id, handle: handle, original: original, start: start, point: point, delta: delta)
        }
    }

    private func moveEntity(id: Int64, original: EditImageCanvasEntity, delta: NSPoint) {
        let offset = CGPoint(x: delta.x / viewScale, y: delta.y / viewScale)
        if case var .vector(vector) = original.content {
            vector.start = CGPoint(x: vector.start.x + offset.x, y: vector.start.y + offset.y)
            vector.end = CGPoint(x: vector.end.x + offset.x, y: vector.end.y + offset.y)
            updateEntity(id, { entity in
                entity.content = .vector(vector)
            })
            return
        }
        let center = CGPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)
        let range = 0.02 * frame.width / viewScale
        var position = CGPoint(x: original.position.x + offset.x, y: original.position.y + offset.y)
        let snapX = abs(position.x - center.x) < range
        let snapY = abs(position.y - center.y) < range
        if (snapX && !selectionView.snapX) || (snapY && !selectionView.snapY) {
            performAlignmentFeedback()
        }
        selectionView.snapX = snapX
        selectionView.snapY = snapY
        if selectionView.snapX {
            position.x = center.x
        }
        if selectionView.snapY {
            position.y = center.y
        }
        updateEntity(id, { entity in
            entity.position = position
        })
        selectionView.needsDisplay = true
    }

    private func snapRotation(_ rotation: CGFloat) -> (CGFloat, Bool) {
        let step = CGFloat.pi / 4.0
        let nearest = (rotation / step).rounded() * step
        if abs(rotation - nearest) < 0.06 {
            return (nearest, true)
        }
        return (rotation, false)
    }

    private func dragHandle(id: Int64, handle: EditImageCanvasHandle, original: EditImageCanvasEntity, start: NSPoint, point: NSPoint, delta: NSPoint) {
        let referenceDelta = CGPoint(x: delta.x / viewScale, y: delta.y / viewScale)
        switch handle {
        case .scaleRotate:
            dragScaleRotate(id: id, original: original, start: start, point: point)
        case let .resize(dx, dy):
            dragResize(id: id, original: original, dx: CGFloat(dx), dy: CGFloat(dy), referenceDelta: referenceDelta)
        case .tail:
            dragTail(id: id, original: original, point: point)
        case .vectorStart, .vectorEnd, .vectorMid:
            dragVectorPoint(id: id, handle: handle, original: original, referenceDelta: referenceDelta)
        }
        selectionView.needsDisplay = true
    }

    private func performAlignmentFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func updateEntity(_ id: Int64, _ f: (inout EditImageCanvasEntity) -> Void) {
        interaction?.update(false, { state in
            state.updateEntity(id, f)
        })
    }

    private func dragScaleRotate(id: Int64, original: EditImageCanvasEntity, start: NSPoint, point: NSPoint) {
        let center = toCanvas(original.position)
        let from = CGPoint(x: start.x - center.x, y: start.y - center.y)
        let to = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let scale = max(0.05, original.scale * hypot(to.x, to.y) / max(1, hypot(from.x, from.y)))
        let (rotation, snapped) = snapRotation(original.rotation + atan2(to.y, to.x) - atan2(from.y, from.x))
        if snapped && selectionView.rotationGuide != rotation {
            performAlignmentFeedback()
        }
        selectionView.rotationGuide = snapped ? rotation : nil
        updateEntity(id, { entity in
            entity.scale = scale
            entity.rotation = rotation
        })
    }

    private func dragResize(id: Int64, original: EditImageCanvasEntity, dx: CGFloat, dy: CGFloat, referenceDelta: CGPoint) {
        let size: CGSize
        var keepAspect = false
        switch original.content {
        case let .shape(shape):
            size = shape.size
            keepAspect = shape.type == .star
        case let .bubble(bubble):
            size = bubble.size
        default:
            return
        }
        let unrotate = CGAffineTransform(rotationAngle: -original.rotation)
        let local = referenceDelta.applying(unrotate)
        let minimum = min(imageSize.width, imageSize.height) * 0.05
        var width = max(minimum, size.width + dx * local.x / original.scale)
        var height = max(minimum, size.height + dy * local.y / original.scale)
        if dx == 0 {
            width = size.width
        }
        if dy == 0 {
            height = size.height
        }
        if keepAspect {
            let side = dy == 0 ? width : (dx == 0 ? height : max(width, height))
            width = side
            height = side
        }
        let shift = CGPoint(x: dx * (width - size.width) / 2.0 * original.scale, y: dy * (height - size.height) / 2.0 * original.scale).applying(CGAffineTransform(rotationAngle: original.rotation))
        updateEntity(id, { entity in
            entity.position = CGPoint(x: original.position.x + shift.x, y: original.position.y + shift.y)
            switch entity.content {
            case var .shape(shape):
                shape.size = NSMakeSize(width, height)
                entity.content = .shape(shape)
            case var .bubble(bubble):
                bubble.size = NSMakeSize(width, height)
                bubble.tailPosition.y = min(bubble.tailPosition.y, height)
                entity.content = .bubble(bubble)
            default:
                break
            }
        })
    }

    private func dragTail(id: Int64, original: EditImageCanvasEntity, point: NSPoint) {
        let local = toReference(point).applying(original.localTransform.inverted())
        updateEntity(id, { entity in
            guard case var .bubble(bubble) = entity.content else {
                return
            }
            let x = (local.x + bubble.size.width / 2.0) / max(1, bubble.size.width)
            let y = local.y - bubble.size.height / 2.0
            bubble.tailPosition = CGPoint(x: max(0, min(1, x)), y: max(0, min(bubble.size.height, y)))
            entity.content = .bubble(bubble)
        })
    }

    private func dragVectorPoint(id: Int64, handle: EditImageCanvasHandle, original: EditImageCanvasEntity, referenceDelta: CGPoint) {
        guard case let .vector(originalVector) = original.content else {
            return
        }
        var vector = originalVector
        switch handle {
        case .vectorStart:
            vector.start = CGPoint(x: originalVector.start.x + referenceDelta.x, y: originalVector.start.y + referenceDelta.y)
        case .vectorEnd:
            vector.end = CGPoint(x: originalVector.end.x + referenceDelta.x, y: originalVector.end.y + referenceDelta.y)
        default:
            let mid = editImageCanvasVectorMidPoint(start: originalVector.start, end: originalVector.end, mid: originalVector.mid)
            vector.mid = editImageCanvasVectorMid(start: originalVector.start, end: originalVector.end, midPoint: CGPoint(x: mid.x + referenceDelta.x, y: mid.y + referenceDelta.y))
        }
        updateEntity(id, { entity in
            entity.content = .vector(vector)
        })
    }

    override func mouseUp(with event: NSEvent) {
        fillTimer?.invalidate()
        fillTimer = nil
        guard let interaction = interaction else {
            dragMode = .none
            return
        }
        switch dragMode {
        case .stroke:
            if let touch = drawView.activeTouch {
                drawView.activeTouch = nil
                if touch.action == .drawArrow {
                    let multiplier = imageSize.width / max(1, touch.canvasSize.width)
                    let points = touch.lines.map { CGPoint(x: $0.x * multiplier, y: $0.y * multiplier) }
                    if editImageCanvasArrowHead(points: points, lineWidth: touch.width * multiplier, canvasSize: imageSize) == nil {
                        break
                    }
                }
                interaction.commitStroke(touch)
            }
        case let .move(id, _, _, wasSelected):
            if !didDrag && wasSelected {
                interaction.showEntityMenu(id, event, self)
            }
        default:
            break
        }
        selectionView.snapX = false
        selectionView.snapY = false
        selectionView.rotationGuide = nil
        selectionView.needsDisplay = true
        dragMode = .none
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let interaction = interaction else {
            return
        }
        let state = interaction.state()
        guard state.editingEntityId == nil else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let entity = hitEntity(at: point, state: state) {
            interaction.update(false, { state in
                state.selectedEntityId = entity.id
            })
            interaction.showEntityMenu(entity.id, event, self)
        }
    }

    override func magnify(with event: NSEvent) {
        guard let interaction = interaction else {
            return
        }
        let state = interaction.state()
        guard state.editingEntityId == nil else {
            return
        }
        if event.phase == .began {
            gestureUndoPushed = false
        }
        let factor = 1.0 + event.magnification
        if let entity = state.selectedEntity, !entity.isVector {
            if !gestureUndoPushed {
                gestureUndoPushed = true
                interaction.pushUndo()
            }
            let minimum = min(imageSize.width, imageSize.height) * 0.05
            interaction.update(false, { state in
                state.updateEntity(entity.id, { entity in
                    switch entity.content {
                    case var .shape(shape):
                        shape.size = NSMakeSize(max(minimum, shape.size.width * factor), max(minimum, shape.size.height * factor))
                        entity.content = .shape(shape)
                    case var .bubble(bubble):
                        bubble.size = NSMakeSize(max(minimum, bubble.size.width * factor), max(minimum, bubble.size.height * factor))
                        bubble.tailPosition.y *= factor
                        entity.content = .bubble(bubble)
                    case .text:
                        entity.scale = max(0.1, entity.scale * factor)
                    default:
                        entity.scale = max(0.05, entity.scale * factor)
                    }
                })
            })
        } else if state.selectedEntity == nil {
            setZoom(zoom * factor, anchor: convert(event.locationInWindow, from: nil))
        }
    }

    override func rotate(with event: NSEvent) {
        guard let interaction = interaction else {
            return
        }
        let state = interaction.state()
        guard state.editingEntityId == nil, let entity = state.selectedEntity, !entity.isVector else {
            return
        }
        if event.phase == .began || !gestureUndoPushed {
            gestureUndoPushed = true
            interaction.pushUndo()
        }
        let delta = -CGFloat(event.rotation) * .pi / 180.0
        interaction.update(false, { state in
            state.updateEntity(entity.id, { entity in
                entity.rotation += delta
            })
        })
    }

    override func scrollWheel(with event: NSEvent) {
        guard zoom > 1 else {
            super.scrollWheel(with: event)
            return
        }
        zoomOffset = CGPoint(x: zoomOffset.x + event.scrollingDeltaX, y: zoomOffset.y + event.scrollingDeltaY)
        clampZoomOffset()
        layoutContent()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return NSImage.canInit(with: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let image = NSImage(pasteboard: sender.draggingPasteboard), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        interaction?.addImageSticker(cgImage)
        return true
    }

    func makeSnapshot(image: CGImage, state: EditImageCanvasState) -> CGImage? {
        let size = contentFrame.size
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let touches = state.touches
        let entities = state.entities
        let blurImage = drawView.blurImage
        let paints: CGImage? = touches.isEmpty ? nil : generateImage(size, contextGenerator: { size, context in
            context.clear(size.bounds)
            applyPaints(touches, for: context, imageSize: size, blurImage: blurImage)
        }, scale: 1.0)
        return generateImage(size, scale: 1.0, rotatedContext: { size, context in
            context.setFillColor(NSColor.black.cgColor)
            context.fill(size.bounds)
            editImageCanvasDrawUpright(image, in: size.bounds, context: context)
            if let paints = paints {
                context.draw(paints, in: size.bounds)
            }
            applyEntities(entities, for: context, size: size)
        })
    }
}

final class EditImageCanvasSizePreview: View {
    var diameter: CGFloat = 10 {
        didSet {
            needsDisplay = true
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let rect = bounds.focus(NSMakeSize(diameter, diameter))
        ctx.setShadow(offset: .zero, blur: 20, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(NSColor(white: 0.57, alpha: 1.0).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: rect)
    }
}

final class EditImageCanvasView: View {
    let canvas: EditImageCanvasArea
    let topBar = EditImageCanvasTopBar(frame: NSMakeRect(0, 0, 400, 40))
    let sizeSlider = EditImageCanvasSizeSlider(frame: NSMakeRect(0, 0, 30, 240))
    let toolsRow = EditImageCanvasToolsRow(frame: NSMakeRect(0, 0, 420, 96))
    let textSettingsRow = EditImageCanvasTextSettingsRow(frame: NSMakeRect(0, 0, 420, 44))
    let colorRow = EditImageCanvasColorRow(frame: NSMakeRect(0, 0, 420, 44))
    let modeRow = EditImageCanvasModeRow(frame: NSMakeRect(0, 0, 420, 40))
    let sizePreview = EditImageCanvasSizePreview(frame: NSMakeRect(0, 0, 300, 300))
    private var pickerOverlay: Control?
    private(set) var colorPicker: EditImageCanvasColorPickerView?
    private(set) var eyedropper: EditImageCanvasEyedropperView?

    var arguments: EditImageCanvasArguments? {
        didSet {
            topBar.arguments = arguments
            toolsRow.arguments = arguments
            textSettingsRow.arguments = arguments
            colorRow.arguments = arguments
            modeRow.arguments = arguments
            sizeSlider.onChange = { [weak self] value, final in
                self?.arguments?.updateSize(value, final)
            }
            sizeSlider.onPreview = { [weak self] value in
                self?.arguments?.previewSize(value)
            }
        }
    }

    init(frame frameRect: NSRect, image: CGImage) {
        self.canvas = EditImageCanvasArea(frame: frameRect, image: image)
        super.init(frame: frameRect)
        addSubview(canvas)
        addSubview(sizePreview)
        addSubview(toolsRow)
        addSubview(textSettingsRow)
        addSubview(colorRow)
        addSubview(modeRow)
        addSubview(topBar)
        addSubview(sizeSlider)
        sizePreview.isHidden = true
        textSettingsRow.isHidden = true
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ controls: EditImageCanvasControlsState, animated: Bool) {
        let state = controls.state
        canvas.update(state: state)
        topBar.update(controls)
        if let entity = state.selectedEntity, let text = entity.text {
            textSettingsRow.isHidden = false
            toolsRow.isHidden = true
            textSettingsRow.update(text: text)
        } else {
            textSettingsRow.isHidden = true
            toolsRow.isHidden = false
            toolsRow.update(state, animated: animated)
        }
        colorRow.update(color: state.currentColor)
        modeRow.update(mode: state.mode, stickersAvailable: controls.stickersAvailable, animated: animated)
        if let value = state.currentSizeValue {
            sizeSlider.isHidden = false
            sizeSlider.value = value
        } else {
            sizeSlider.isHidden = true
        }
        colorPicker?.updateColor(state.currentColor)
    }

    func showSizePreview(_ diameter: CGFloat?) {
        if let diameter = diameter {
            sizePreview.isHidden = false
            sizePreview.diameter = diameter
        } else {
            sizePreview.isHidden = true
        }
    }

    func showColorPicker(color: EditImageCanvasColor, onChange: @escaping (EditImageCanvasColor) -> Void, onEyedropper: @escaping () -> Void) {
        hideColorPicker()
        let overlay = Control(frame: bounds)
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        overlay.set(handler: { [weak self] _ in
            self?.hideColorPicker()
        }, for: .Click)
        addSubview(overlay)
        pickerOverlay = overlay

        let picker = EditImageCanvasColorPickerView(color: color)
        picker.onChange = onChange
        picker.onClose = { [weak self] in
            self?.hideColorPicker()
        }
        picker.onEyedropper = { [weak self] in
            self?.hideColorPicker()
            onEyedropper()
        }
        addSubview(picker)
        colorPicker = picker
        needsLayout = true
        picker.layer?.animateAlpha(from: 0, to: 1, duration: 0.15)
        picker.layer?.animateScaleSpring(from: 0.9, to: 1, duration: 0.3)
    }

    func hideColorPicker() {
        pickerOverlay?.removeFromSuperview()
        pickerOverlay = nil
        colorPicker?.removeFromSuperview()
        colorPicker = nil
    }

    func showEyedropper(snapshot: CGImage, onPick: @escaping (EditImageCanvasColor?) -> Void) {
        hideEyedropper()
        let view = EditImageCanvasEyedropperView(frame: canvas.frame, snapshot: snapshot, contentRect: canvas.contentFrame)
        view.onPick = { [weak self] color in
            self?.hideEyedropper()
            onPick(color)
        }
        addSubview(view)
        eyedropper = view
    }

    func hideEyedropper() {
        eyedropper?.removeFromSuperview()
        eyedropper = nil
        NSCursor.arrow.set()
    }

    override func layout() {
        super.layout()
        let expansion = min(1, max(0, (frame.height - 560) / 160))
        let inset = 8 + 8 * expansion
        let topInset = 24 - 8 * expansion
        let spacing = 8 + 4 * expansion
        let toolsHeight = 64 + 32 * expansion
        let width = min(frame.width - 32, 440)
        let x = floor((frame.width - width) / 2.0)
        topBar.frame = NSMakeRect(16, topInset, frame.width - 32, 40)
        modeRow.frame = NSMakeRect(x, frame.height - inset - 40, width, 40)
        colorRow.frame = NSMakeRect(x, modeRow.frame.minY - spacing - 44, width, 44)
        toolsRow.frame = NSMakeRect(x, colorRow.frame.minY - 4 - toolsHeight, width, toolsHeight)
        textSettingsRow.frame = NSMakeRect(x, colorRow.frame.minY - spacing - 44, width, 44)

        let canvasTop = topBar.frame.maxY + 8 + 20 * expansion
        let canvasBottom = toolsRow.frame.minY - 4
        canvas.frame = NSMakeRect(56, canvasTop, max(1, frame.width - 112), max(1, canvasBottom - canvasTop))
        sizeSlider.setFrameSize(NSMakeSize(30, min(240, canvas.frame.height)))
        sizeSlider.setFrameOrigin(NSMakePoint(14, floor(canvas.frame.midY - sizeSlider.frame.height / 2.0)))
        sizePreview.setFrameOrigin(NSMakePoint(floor(canvas.frame.midX - sizePreview.frame.width / 2.0), floor(canvas.frame.midY - sizePreview.frame.height / 2.0)))
        pickerOverlay?.frame = bounds
        if let picker = colorPicker {
            picker.setFrameSize(NSMakeSize(min(320, frame.width - 32), min(520, frame.height - 32)))
            picker.setFrameOrigin(NSMakePoint(floor((frame.width - picker.frame.width) / 2.0), max(16, floor((frame.height - picker.frame.height) / 2.0))))
        }
        eyedropper?.frame = canvas.frame
    }
}
