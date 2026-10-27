import Cocoa
import TGUIKit
import SwiftSignalKit
import ColorPalette
import Localization
import TelegramContext
import TextRecognizing
import TelegramMedia

public final class EditImageDrawTouch : Equatable {

    public enum Action : Hashable {
        case draw
        case drawArrow
        case clear
        case marker
        case neon
        case blur
        case fill
        case eraseAll
        case blurAll
    }

    public static func == (lhs: EditImageDrawTouch, rhs: EditImageDrawTouch) -> Bool {
        return lhs.lines == rhs.lines &&
            lhs.color.argb == rhs.color.argb &&
            lhs.width == rhs.width &&
            lhs.action == rhs.action &&
            lhs.canvasSize == rhs.canvasSize
    }
    public private(set) var lines:[NSPoint]
    public let color: NSColor
    public let width: CGFloat
    public let action: Action
    public let canvasSize: NSSize
    public init(action: Action, point: NSPoint, canvasSize: NSSize, color: NSColor, width: CGFloat) {
        self.action = action
        self.lines = [point]
        self.color = color
        self.width = width
        self.canvasSize = canvasSize
    }
    public init(action: Action, lines: [NSPoint], canvasSize: NSSize, color: NSColor, width: CGFloat) {
        self.action = action
        self.lines = lines
        self.color = color
        self.width = width
        self.canvasSize = canvasSize
    }
    func addPoint(_ point: NSPoint) {
        self.lines.append(point)
    }
}

enum EditImageCanvasMode {
    case drawing
    case sticker
    case text
}

struct EditImageCanvasSnapshot {
    let touches: [EditImageDrawTouch]
    let entities: [EditImageCanvasEntity]
}

struct EditImageCanvasState {
    var tool: EditImageCanvasTool
    var tools: [EditImageCanvasTool: EditImageCanvasToolState]
    var touches: [EditImageDrawTouch]
    var entities: [EditImageCanvasEntity]
    var selectedEntityId: Int64?
    var editingEntityId: Int64?
    var isStickerPickerShown = false
    var undo: [EditImageCanvasSnapshot] = []
    var redo: [EditImageCanvasSnapshot] = []

    func entity(_ id: Int64) -> EditImageCanvasEntity? {
        return entities.first(where: { $0.id == id })
    }

    var selectedEntity: EditImageCanvasEntity? {
        guard let id = editingEntityId ?? selectedEntityId else {
            return nil
        }
        return entity(id)
    }

    mutating func updateEntity(_ id: Int64, _ f: (inout EditImageCanvasEntity) -> Void) {
        if let index = entities.firstIndex(where: { $0.id == id }) {
            f(&entities[index])
        }
    }

    var mode: EditImageCanvasMode {
        if isStickerPickerShown {
            return .sticker
        }
        guard let entity = selectedEntity else {
            return .drawing
        }
        switch entity.content {
        case .sticker:
            return .sticker
        case .text:
            return .text
        default:
            return .drawing
        }
    }

    var toolState: EditImageCanvasToolState {
        return tools[tool] ?? EditImageCanvasToolSettings.defaults()[tool]!
    }

    var drawingColor: EditImageCanvasColor {
        if tool.hasColor {
            return toolState.color
        }
        return tools[.pen]?.color ?? .white
    }

    var currentColor: EditImageCanvasColor {
        return selectedEntity?.color ?? drawingColor
    }

    var currentSizeValue: CGFloat? {
        if let entity = selectedEntity {
            return entity.sizeValue
        }
        return toolState.size
    }

    var canUndo: Bool {
        return !undo.isEmpty
    }

    var canRedo: Bool {
        return !redo.isEmpty
    }

    var canClear: Bool {
        return !touches.isEmpty || !entities.isEmpty
    }

    var snapshot: EditImageCanvasSnapshot {
        return EditImageCanvasSnapshot(touches: touches, entities: entities)
    }
}

public final class EditImageCanvasController : ModalViewController {
    private let image: CGImage
    private let initialTouches: [EditImageDrawTouch]
    private let initialEntities: [EditImageCanvasEntity]
    private let updatedImage: ([EditImageDrawTouch], [EditImageCanvasEntity])->Void
    private let closeHandler: ()->Void
    public var onCancelled: (() -> Void)?
    private let alone: Bool
    private let context: (any AccountContextProtocol)?
    private lazy var stickerPicker: EditImageCanvasStickerPicker? = {
        guard let context = self.context else {
            return nil
        }
        let picker = ImageCanvasUIHooks.shared.makeStickerPicker(context)
        picker?.visibilityChanged = { [weak self] isShown in
            if !isShown, NSEvent.pressedMouseButtons & 1 != 0 {
                self?.cancelStickerDrag()
            }
            self?.updateState(false, { state in
                state.isStickerPickerShown = isShown
            })
        }
        return picker
    }()
    private var state: EditImageCanvasState
    private var isContinuousChange = false
    private var isClosing = false
    private let cutoutDisposable = MetaDisposable()

    public init(image: CGImage, actions: [EditImageDrawTouch], entities: [EditImageCanvasEntity] = [], context: (any AccountContextProtocol)? = nil, updatedImage: @escaping([EditImageDrawTouch], [EditImageCanvasEntity])->Void, closeHandler: @escaping() -> Void, alone: Bool = false) {
        let settings = EditImageCanvasToolSettings.load()
        self.state = EditImageCanvasState(tool: settings.selected, tools: settings.tools, touches: actions, entities: entities)
        self.image = image
        self.alone = alone
        self.context = context
        self.initialTouches = actions
        self.initialEntities = entities
        self.updatedImage = updatedImage
        self.closeHandler = closeHandler
        super.init()
        bar = .init(height: 0)
    }

    deinit {
        cutoutDisposable.dispose()
        stickerDragPlayerDisposable.dispose()
        stickerDragView?.removeFromSuperview()
    }

    public override var containerBackground: NSColor {
        return .clear
    }

    public override var isVisualEffectBackground: Bool {
        return alone
    }

    public override var background: NSColor {
        return .clear
    }

    public override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        super.close(animationType: animationType)
        self.closeHandler()
    }

    public override func measure(size: NSSize) {
        updateSize(false)
    }

    func updateSize(_ animated: Bool) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            let inset = min(40, max(16, (contentSize.height - 600) / 2))
            self.modal?.resize(with: NSMakeSize(contentSize.width - inset * 2, contentSize.height - inset * 2), animated: animated)
        }
    }

    public override var dynamicSize: Bool {
        return true
    }

    public override func viewClass() -> AnyClass {
        return EditImageCanvasView.self
    }

    private var genericView: EditImageCanvasView {
        return self.view as! EditImageCanvasView
    }

    public override func initializer() -> NSView {
        return EditImageCanvasView(frame: NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - bar.height), image: image)
    }

    private var hasChanges: Bool {
        let sameTouches = state.touches.count == initialTouches.count && zip(state.touches, initialTouches).allSatisfy { $0 === $1 }
        return !sameTouches || state.entities != initialEntities
    }

    private var isTextInputActive: Bool {
        return window?.firstResponder is NSText
    }

    private func updateView(animated: Bool = true) {
        guard isLoaded() else {
            return
        }
        genericView.update(EditImageCanvasControlsState(state: state, isZoomed: genericView.canvas.zoom > 1, stickersAvailable: stickerPicker != nil), animated: animated)
    }

    private func pushUndo() {
        state.undo.append(state.snapshot)
        if state.undo.count > 100 {
            state.undo.removeFirst(state.undo.count - 100)
        }
        state.redo.removeAll()
    }

    private func updateState(_ undoable: Bool, animated: Bool = true, _ f: (inout EditImageCanvasState) -> Void) {
        if undoable {
            pushUndo()
        }
        f(&state)
        if let id = state.selectedEntityId, state.entity(id) == nil {
            state.selectedEntityId = nil
        }
        updateView(animated: animated)
    }

    private func updateContinuously(final: Bool, _ f: (inout EditImageCanvasState) -> Void) {
        updateState(!isContinuousChange && state.editingEntityId == nil, f)
        isContinuousChange = !final
    }

    private func saveToolSettings() {
        EditImageCanvasToolSettings.save(state.tools, selected: state.tool)
    }

    private func ensureBlurImage() {
        if genericView.canvas.drawView.blurImage == nil {
            genericView.canvas.drawView.blurImage = editImageCanvasBlurredImage(image)
        }
    }

    private func undo() {
        guard state.editingEntityId == nil, let last = state.undo.popLast() else {
            NSSound.beep()
            return
        }
        state.redo.append(state.snapshot)
        if last.touches.contains(where: { $0.action == .blur || $0.action == .blurAll }) {
            ensureBlurImage()
        }
        updateState(false, { state in
            state.touches = last.touches
            state.entities = last.entities
        })
    }

    private func redo() {
        guard state.editingEntityId == nil, let last = state.redo.popLast() else {
            NSSound.beep()
            return
        }
        state.undo.append(state.snapshot)
        if last.touches.contains(where: { $0.action == .blur || $0.action == .blurAll }) {
            ensureBlurImage()
        }
        updateState(false, { state in
            state.touches = last.touches
            state.entities = last.entities
        })
    }

    private func newEntityPosition(verticalOnly: Bool) -> CGPoint {
        let reference = image.size
        var position = genericView.canvas.visibleReferenceCenter
        if state.entities.contains(where: { hypot($0.position.x - position.x, $0.position.y - position.y) < reference.width * 0.05 }) {
            position.y += reference.width * 0.1
            if !verticalOnly {
                position.x += reference.width * 0.1
            }
        }
        return position
    }

    private func addEntity(_ entity: EditImageCanvasEntity) {
        if state.editingEntityId != nil {
            finishTextEditing(commit: true)
        }
        updateState(true, { state in
            state.entities.append(entity)
            state.selectedEntityId = entity.id
        })
    }

    private var stickerBaseSide: CGFloat {
        let reference = self.image.size
        return max(10.0, min(reference.width, reference.height) * 0.25)
    }

    private func addSticker(_ image: CGImage, fileId: Int64?, animation: EditImageCanvasStickerAnimation? = nil, position: CGPoint? = nil) {
        let reference = self.image.size
        let side = stickerBaseSide
        let baseSize = image.size.aspectFitted(NSMakeSize(side, side))
        let sticker = EditImageCanvasEntity.Sticker(image: image, baseSize: baseSize, fileId: fileId, animation: animation)
        let entity = EditImageCanvasEntity(content: .sticker(sticker), position: position ?? newEntityPosition(verticalOnly: false), scale: 1.0 / genericView.canvas.zoom, referenceSize: reference)
        addEntity(entity)
    }

    private var stickerDragView: ImageView?
    private var stickerDragAnimator: EditImageCanvasStickerAnimator?
    private var stickerDragPlayer: LottiePlayerView?
    private var stickerDragImageSize: CGSize?
    private let stickerDragPlayerDisposable = MetaDisposable()
    private var isStickerDragCancelled = false

    private func cancelStickerDrag() {
        guard stickerDragView != nil else {
            return
        }
        isStickerDragCancelled = true
        updateStickerDrag(.ended)
    }

    private func stickerDropPosition(_ point: NSPoint) -> CGPoint? {
        let canvas = genericView.canvas
        let local = canvas.convert(point, from: nil)
        guard let contentView = canvas.window?.contentView, let hit = contentView.hitTest(contentView.superview?.convert(point, from: nil) ?? point), hit.isDescendant(of: canvas), canvas.contentFrame.contains(local) else {
            return nil
        }
        return canvas.toReference(local)
    }

    private func updateStickerDrag(_ drag: EditImageCanvasStickerDrag) {
        switch drag {
        case let .moved(image, point):
            guard !isStickerDragCancelled, let contentView = genericView.window?.contentView else {
                return
            }
            let view: ImageView
            if let current = stickerDragView {
                view = current
            } else {
                view = ImageView()
                view.isEventLess = true
                contentView.addSubview(view)
                stickerDragView = view
            }
            if let image = image, stickerDragPlayer == nil, stickerDragAnimator == nil {
                view.image = image
                stickerDragImageSize = image.size
            }
            let canvas = genericView.canvas
            let side = stickerBaseSide * canvas.viewScale / canvas.zoom
            let size = (stickerDragImageSize ?? NSMakeSize(side, side)).aspectFitted(NSMakeSize(side, side))
            let location = contentView.convert(point, from: nil)
            view.frame = CGRect(x: location.x - size.width / 2.0, y: location.y - size.height / 2.0, width: size.width, height: size.height)
            view.layer?.opacity = stickerDropPosition(point) != nil ? 1.0 : 0.5
        case let .preview(pick):
            guard let view = stickerDragView else {
                return
            }
            view.image = pick.image
            stickerDragImageSize = pick.image.size
            stickerDragAnimator = nil
            stickerDragPlayerDisposable.set(nil)
            stickerDragPlayer?.removeFromSuperview()
            stickerDragPlayer = nil
            guard let animation = pick.animation else {
                return
            }
            if animation.kind != .video {
                let data = animation.kind == .webm ? animation.path.data(using: .utf8) : try? Data(contentsOf: URL(fileURLWithPath: animation.path))
                guard let data = data else {
                    return
                }
                let canvas = genericView.canvas
                let side = stickerBaseSide * canvas.viewScale / canvas.zoom
                let size = pick.image.size.aspectFitted(NSMakeSize(side, side))
                let player = LottiePlayerView(frame: view.bounds)
                player.autoresizingMask = [.width, .height]
                view.addSubview(player)
                stickerDragPlayer = player
                stickerDragPlayerDisposable.set((player.state |> deliverOnMainQueue).start(next: { [weak view] state in
                    if state == .playing {
                        view?.image = nil
                    }
                }))
                player.set(LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .bundle("edit_canvas_drag_\(animation.path)"), size: size), type: animation.kind == .webm ? .webm : .lottie, cachePurpose: .none))
                return
            }
            let sticker = EditImageCanvasEntity.Sticker(image: pick.image, baseSize: pick.image.size, fileId: pick.fileId, animation: animation)
            let animator = EditImageCanvasStickerAnimator()
            animator.updated = { [weak view] images in
                if let image = images.values.first {
                    view?.image = image
                }
            }
            animator.update(entities: [EditImageCanvasEntity(content: .sticker(sticker), position: .zero, referenceSize: pick.image.size)])
            animator.isActive = true
            stickerDragAnimator = animator
        case .ended:
            stickerDragAnimator = nil
            stickerDragPlayerDisposable.set(nil)
            stickerDragPlayer = nil
            stickerDragImageSize = nil
            stickerDragView?.removeFromSuperview()
            stickerDragView = nil
        case let .dropped(pick, point):
            guard !isStickerDragCancelled, !isClosing, let position = stickerDropPosition(point) else {
                return
            }
            if state.editingEntityId != nil {
                finishTextEditing(commit: true)
            }
            addSticker(pick.image, fileId: pick.fileId, animation: pick.animation, position: position)
            stickerPicker?.close()
        }
    }

    private enum ShapeKind {
        case rectangle
        case ellipse
        case bubble
        case star
        case arrow
    }

    private func addShape(_ kind: ShapeKind) {
        let reference = image.size
        let zoom = genericView.canvas.zoom
        let width = round(reference.width * 0.5) / zoom
        let color = state.drawingColor
        let position = newEntityPosition(verticalOnly: false)
        let content: EditImageCanvasEntity.Content
        switch kind {
        case .rectangle:
            content = .shape(.init(type: .rectangle, drawType: .stroke, color: color, lineWidth: 0.15, size: NSMakeSize(width, round(width * 0.75))))
        case .ellipse:
            content = .shape(.init(type: .ellipse, drawType: .stroke, color: color, lineWidth: 0.15, size: NSMakeSize(width, round(width * 0.75))))
        case .star:
            content = .shape(.init(type: .star, drawType: .stroke, color: color, lineWidth: 0.15, size: NSMakeSize(width, width)))
        case .bubble:
            let height = round(width * 0.7)
            content = .bubble(.init(drawType: .stroke, color: color, lineWidth: 0.15, size: NSMakeSize(width, height), tailPosition: CGPoint(x: 0.16, y: height * 0.18)))
        case .arrow:
            let half = reference.width * 0.25 / zoom
            content = .vector(.init(type: .oneSidedArrow, color: color, lineWidth: 0.3, start: CGPoint(x: position.x - half, y: position.y), end: CGPoint(x: position.x + half, y: position.y), mid: CGPoint(x: 0.5, y: 0)))
        }
        addEntity(EditImageCanvasEntity(content: content, position: position, referenceSize: reference))
    }

    private func addText() {
        stickerPicker?.close()
        if state.editingEntityId != nil {
            finishTextEditing(commit: true)
        }
        let reference = image.size
        let text = EditImageCanvasEntity.Text(string: "", style: .filled, font: .sanFrancisco, alignment: .center, color: .white, fontSize: 0.08, width: floor(reference.width * 0.9))
        let entity = EditImageCanvasEntity(content: .text(text), position: newEntityPosition(verticalOnly: true), scale: 1.0 / genericView.canvas.zoom, referenceSize: reference)
        updateState(true, { state in
            state.entities.append(entity)
            state.selectedEntityId = entity.id
            state.editingEntityId = entity.id
        })
    }

    private func beginTextEditing(_ id: Int64) {
        guard state.editingEntityId == nil, state.entity(id)?.isText == true else {
            return
        }
        updateState(true, { state in
            state.selectedEntityId = id
            state.editingEntityId = id
        })
    }

    private func finishTextEditing(commit: Bool) {
        guard let id = state.editingEntityId else {
            return
        }
        if !commit, let before = state.undo.popLast() {
            state.entities = before.entities
        }
        if state.entity(id)?.text?.string.isEmpty == true {
            state.entities.removeAll(where: { $0.id == id })
        }
        if commit, let before = state.undo.last, before.entities == state.entities {
            state.undo.removeLast()
        }
        updateState(false, { state in
            state.editingEntityId = nil
            state.selectedEntityId = state.entity(id) == nil ? nil : id
        })
        window?.makeFirstResponder(nil)
    }

    private func updateSelectedText(_ f: @escaping (inout EditImageCanvasEntity.Text) -> Void) {
        guard let entity = state.selectedEntity, entity.isText else {
            return
        }
        let undoable = state.editingEntityId == nil
        updateState(undoable, { state in
            state.updateEntity(entity.id, { entity in
                if case var .text(text) = entity.content {
                    f(&text)
                    entity.content = .text(text)
                }
            })
        })
    }

    private func selectColor(_ color: EditImageCanvasColor, final: Bool) {
        if let entity = state.selectedEntity, entity.color != nil {
            updateContinuously(final: final, { state in
                state.updateEntity(entity.id, { entity in
                    entity.setColor(color)
                })
            })
        } else {
            updateState(false, { state in
                state.selectedEntityId = nil
                if !state.tool.hasColor {
                    state.tool = .pen
                }
                state.tools[state.tool]?.color = color
            })
            if final {
                saveToolSettings()
            }
        }
    }

    private func showStickers(_ control: Control) {
        if state.editingEntityId != nil {
            finishTextEditing(commit: true)
        }
        isStickerDragCancelled = false
        stickerPicker?.show(for: control, select: { [weak self] pick in
            self?.addSticker(pick.image, fileId: pick.fileId, animation: pick.animation)
        }, drag: { [weak self] drag in
            self?.updateStickerDrag(drag)
        })
    }

    private func showShapesMenu(_ control: Control) {
        guard let event = NSApp.currentEvent else {
            return
        }
        let menu = ContextMenu(presentation: .current(nightAccentPalette))
        let items: [(String, NSImage, ShapeKind)] = [
            (strings().editImageCanvasControllerShapeRectangle, NSImage(resource: .iconEditImageShapeRectangle), .rectangle),
            (strings().editImageCanvasControllerShapeEllipse, NSImage(resource: .iconEditImageShapeEllipse), .ellipse),
            (strings().editImageCanvasControllerShapeBubble, NSImage(resource: .iconEditImageShapeBubble), .bubble),
            (strings().editImageCanvasControllerShapeStar, NSImage(resource: .iconEditImageShapeStar), .star),
            (strings().editImageCanvasControllerShapeArrow, NSImage(resource: .iconEditImageShapeArrow), .arrow)
        ]
        for (title, image, kind) in items {
            menu.addItem(ContextMenuItem(title, handler: { [weak self] in
                self?.addShape(kind)
            }, image: image))
        }
        AppMenu(menu: menu).show(event: event, view: control)
    }

    private func showFontsMenu(_ control: Control) {
        guard let event = NSApp.currentEvent else {
            return
        }
        let menu = ContextMenu(presentation: .current(nightAccentPalette))
        for font in EditImageCanvasEntity.TextFont.allCases {
            let title = NSAttributedString(string: font.title, attributes: [.font: font.font(size: 15), .foregroundColor: NSColor.white])
            menu.addItem(ContextMenuItem(font.title, handler: { [weak self] in
                self?.updateSelectedText { text in
                    text.font = font
                }
            }, attributedTitle: title))
        }
        AppMenu(menu: menu).show(event: event, view: control)
    }

    private func confirm(_ information: String, ok: String, action: @escaping () -> Void) {
        if let window = self.window, let confirm = ImageCanvasUIHooks.shared.confirm {
            confirm(window, information, ok, action)
        } else {
            action()
        }
    }

    private func clearAll() {
        guard state.canClear else {
            return
        }
        confirm(strings().editImageCanvasControllerClearAllConfirm, ok: strings().editImageCanvasControllerClearAll, action: { [weak self] in
            self?.updateState(true, { state in
                state.touches = []
                state.entities = []
                state.selectedEntityId = nil
            })
        })
    }

    private func deleteEntity(_ id: Int64) {
        updateState(true, { state in
            state.entities.removeAll(where: { $0.id == id })
            if state.selectedEntityId == id {
                state.selectedEntityId = nil
            }
        })
    }

    private func flipEntity(_ id: Int64) {
        updateState(true, { state in
            state.updateEntity(id, { entity in
                switch entity.content {
                case .sticker:
                    entity.mirrored.toggle()
                case var .bubble(bubble):
                    bubble.tailPosition.x = 1.0 - bubble.tailPosition.x
                    entity.content = .bubble(bubble)
                default:
                    break
                }
            })
        })
    }

    private func showEntityMenu(_ id: Int64, event: NSEvent, view: NSView) {
        guard let entity = state.entity(id) else {
            return
        }
        let menu = ContextMenu(presentation: .current(nightAccentPalette))
        menu.addItem(ContextMenuItem(strings().messageContextDelete, handler: { [weak self] in
            self?.deleteEntity(id)
        }, itemMode: .destruct))
        switch entity.content {
        case .text:
            menu.addItem(ContextMenuItem(strings().messageContextEdit, handler: { [weak self] in
                self?.beginTextEditing(id)
            }))
        case .sticker, .bubble:
            menu.addItem(ContextMenuItem(strings().editImageCanvasControllerFlip, handler: { [weak self] in
                self?.flipEntity(id)
            }))
        default:
            break
        }
        if #available(macOS 14.0, *), case let .sticker(sticker) = entity.content, sticker.fileId == nil {
            menu.addItem(ContextMenuItem(strings().editImageCanvasControllerCutOut, handler: { [weak self] in
                self?.cutOutEntity(id)
            }))
        }
        if state.entities.last?.id != id {
            menu.addItem(ContextMenuItem(strings().editImageCanvasControllerMoveForward, handler: { [weak self] in
                self?.updateState(true, { state in
                    if let index = state.entities.firstIndex(where: { $0.id == id }) {
                        let entity = state.entities.remove(at: index)
                        state.entities.append(entity)
                    }
                })
            }))
        }
        menu.addItem(ContextMenuItem(strings().editImageCanvasControllerDuplicate, handler: { [weak self] in
            guard let self = self, let entity = self.state.entity(id) else {
                return
            }
            let copy = entity.duplicate()
            self.updateState(true, { state in
                state.entities.append(copy)
                state.selectedEntityId = copy.id
            })
        }))
        AppMenu(menu: menu).show(event: event, view: view)
    }

    @available(macOS 14.0, *)
    private func cutOutEntity(_ id: Int64) {
        guard let entity = state.entity(id), case let .sticker(sticker) = entity.content else {
            return
        }
        let signal = TextRecognizing.liftSubject(sticker.image, at: nil)
        |> map { subject -> CGImage? in
            return subject.flatMap(editImageCanvasCutoutImage)
        }
        |> deliverOnMainQueue
        cutoutDisposable.set(signal.start(next: { [weak self] image in
            guard let self = self else {
                return
            }
            guard let image = image else {
                if let window = self.window {
                    showModalText(for: window, text: strings().gallerySubjectNotFound)
                }
                return
            }
            self.updateState(true, { state in
                state.updateEntity(id, { entity in
                    if case var .sticker(sticker) = entity.content {
                        sticker.image = image
                        entity.content = .sticker(sticker)
                    }
                })
            })
        }))
    }

    private func showColorPicker() {
        isContinuousChange = false
        genericView.showColorPicker(color: state.currentColor, onChange: { [weak self] color in
            self?.selectColor(color, final: false)
        }, onEyedropper: { [weak self] in
            self?.showEyedropper()
        })
    }

    private func showEyedropper() {
        isContinuousChange = false
        guard let snapshot = genericView.canvas.makeSnapshot(image: image, state: state) else {
            return
        }
        let alpha = state.currentColor.alpha
        genericView.showEyedropper(snapshot: snapshot, onPick: { [weak self] color in
            if let color = color {
                self?.selectColor(color.withAlpha(alpha), final: true)
            }
        })
    }

    private func done() {
        guard !isClosing else {
            return
        }
        if state.editingEntityId != nil {
            finishTextEditing(commit: true)
        }
        isClosing = true
        saveToolSettings()
        updatedImage(state.touches, state.entities)
        close()
    }

    private func cancel() {
        guard !isClosing else {
            return
        }
        if state.editingEntityId != nil {
            finishTextEditing(commit: false)
        }
        saveToolSettings()
        let close: () -> Void = { [weak self] in
            let onCancelled = self?.isClosing == false ? self?.onCancelled : nil
            self?.isClosing = true
            self?.onCancelled = nil
            onCancelled?()
            self?.close()
        }
        if hasChanges {
            confirm(strings().editImageControlConfirmDiscard, ok: strings().alertDiscard, action: close)
        } else {
            close()
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let arguments = EditImageCanvasArguments(selectTool: { [weak self] tool in
            guard let self = self else {
                return
            }
            self.stickerPicker?.close()
            if self.state.editingEntityId != nil {
                self.finishTextEditing(commit: true)
            }
            if tool == .blur {
                self.ensureBlurImage()
            }
            self.updateState(false, { state in
                state.tool = tool
                state.selectedEntityId = nil
            })
            self.saveToolSettings()
        }, updateSize: { [weak self] value, final in
            guard let self = self else {
                return
            }
            if let entity = self.state.selectedEntity {
                self.updateContinuously(final: final, { state in
                    state.updateEntity(entity.id, { entity in
                        entity.setSizeValue(value)
                    })
                })
            } else {
                self.updateState(false, { state in
                    state.tools[state.tool]?.size = value
                })
                if final {
                    self.saveToolSettings()
                }
            }
        }, previewSize: { [weak self] value in
            guard let self = self else {
                return
            }
            if let value = value, self.state.selectedEntity == nil {
                let canvas = self.genericView.canvas
                let diameter = EditImageCanvasMetrics.strokeWidth(tool: self.state.tool, size: value / canvas.zoom, canvasSize: self.image.size) * canvas.viewScale
                self.genericView.showSizePreview(max(4, diameter))
            } else {
                self.genericView.showSizePreview(nil)
            }
        }, selectColor: { [weak self] color, final in
            self?.selectColor(color, final: final)
        }, showColorPicker: { [weak self] in
            self?.showColorPicker()
        }, plus: { [weak self] control in
            guard let self = self else {
                return
            }
            switch self.state.mode {
            case .drawing:
                self.showShapesMenu(control)
            case .sticker:
                self.showStickers(control)
            case .text:
                self.addText()
            }
        }, undo: { [weak self] in
            self?.undo()
        }, redo: { [weak self] in
            self?.redo()
        }, clearAll: { [weak self] _ in
            self?.clearAll()
        }, toggleDrawType: { [weak self] in
            guard let self = self, let entity = self.state.selectedEntity else {
                return
            }
            self.updateState(true, { state in
                state.updateEntity(entity.id, { entity in
                    switch entity.content {
                    case var .shape(shape):
                        shape.drawType = shape.drawType == .fill ? .stroke : .fill
                        entity.content = .shape(shape)
                    case var .bubble(bubble):
                        bubble.drawType = bubble.drawType == .fill ? .stroke : .fill
                        entity.content = .bubble(bubble)
                    default:
                        break
                    }
                })
            })
        }, cycleVectorType: { [weak self] in
            guard let self = self, let entity = self.state.selectedEntity else {
                return
            }
            self.updateState(true, { state in
                state.updateEntity(entity.id, { entity in
                    if case var .vector(vector) = entity.content {
                        vector.type = vector.type.next
                        entity.content = .vector(vector)
                    }
                })
            })
        }, flip: { [weak self] in
            guard let self = self, let entity = self.state.selectedEntity else {
                return
            }
            self.flipEntity(entity.id)
        }, zoomOut: { [weak self] in
            self?.genericView.canvas.setZoom(1, anchor: nil)
        }, cycleTextStyle: { [weak self] in
            self?.updateSelectedText { text in
                text.style = text.style.next
            }
        }, cycleTextAlignment: { [weak self] in
            self?.updateSelectedText { text in
                text.alignment = text.alignment.next
            }
        }, selectFont: { [weak self] control in
            self?.showFontsMenu(control)
        }, modeDraw: { [weak self] in
            guard let self = self else {
                return
            }
            self.stickerPicker?.close()
            if self.state.editingEntityId != nil {
                self.finishTextEditing(commit: true)
            }
            self.updateState(false, { state in
                state.selectedEntityId = nil
            })
        }, modeSticker: { [weak self] control in
            self?.showStickers(control)
        }, modeText: { [weak self] in
            self?.addText()
        }, endTextEditing: { [weak self] commit in
            self?.finishTextEditing(commit: commit)
        }, done: { [weak self] in
            self?.done()
        }, cancel: { [weak self] in
            self?.cancel()
        })

        genericView.arguments = arguments

        genericView.canvas.interaction = EditImageCanvasInteraction(state: { [weak self] in
            return self?.state ?? EditImageCanvasState(tool: .pen, tools: EditImageCanvasToolSettings.defaults(), touches: [], entities: [])
        }, update: { [weak self] undoable, f in
            self?.updateState(undoable, f)
        }, pushUndo: { [weak self] in
            self?.pushUndo()
            self?.updateView()
        }, commitStroke: { [weak self] touch in
            self?.updateState(true, { state in
                state.touches.append(touch)
            })
        }, showEntityMenu: { [weak self] id, event, view in
            self?.showEntityMenu(id, event: event, view: view)
        }, beginTextEditing: { [weak self] id in
            self?.beginTextEditing(id)
        }, endTextEditing: { [weak self] commit in
            self?.finishTextEditing(commit: commit)
        }, textChanged: { [weak self] string in
            guard let self = self, let id = self.state.editingEntityId else {
                return
            }
            self.updateState(false, animated: false, { state in
                state.updateEntity(id, { entity in
                    if case var .text(text) = entity.content {
                        text.string = string
                        entity.content = .text(text)
                    }
                })
            })
        }, addImageSticker: { [weak self] image in
            self?.addSticker(image, fileId: nil)
        }, zoomChanged: { [weak self] in
            self?.updateView(animated: false)
        })

        if state.tool == .blur || state.touches.contains(where: { $0.action == .blur || $0.action == .blurAll }) {
            ensureBlurImage()
        }

        updateView(animated: false)
        readyOnce()
    }

    public override func firstResponder() -> NSResponder? {
        guard isLoaded() else {
            return nil
        }
        if let editor = genericView.canvas.textEditor {
            return editor
        }
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: genericView) {
            return responder
        }
        return genericView
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.eyedropper != nil {
            genericView.hideEyedropper()
            return .invoked
        }
        if genericView.colorPicker != nil {
            genericView.hideColorPicker()
            return .invoked
        }
        if state.editingEntityId != nil {
            finishTextEditing(commit: true)
            return .invoked
        }
        if state.selectedEntityId != nil {
            updateState(false, { state in
                state.selectedEntityId = nil
            })
            return .invoked
        }
        cancel()
        return .invoked
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        if isTextInputActive || state.editingEntityId != nil {
            return .invokeNext
        }
        done()
        return .invoked
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let self = self, !self.isTextInputActive else {
                return .invokeNext
            }
            self.undo()
            return .invoked
        }, with: self, for: .Z, priority: .modal, modifierFlags: [.command])

        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let self = self, !self.isTextInputActive else {
                return .invokeNext
            }
            self.redo()
            return .invoked
        }, with: self, for: .Z, priority: .modal, modifierFlags: [.command, .shift])

        let deleteHandler: (NSEvent) -> KeyHandlerResult = { [weak self] _ in
            guard let self = self, !self.isTextInputActive, self.state.editingEntityId == nil, let id = self.state.selectedEntityId else {
                return .invokeNext
            }
            self.deleteEntity(id)
            return .invoked
        }
        window?.set(handler: deleteHandler, with: self, for: .Delete, priority: .modal)
        window?.set(handler: deleteHandler, with: self, for: .ForwardDelete, priority: .modal)

        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let self = self, !self.isTextInputActive else {
                return .invokeNext
            }
            let pasteboard = NSPasteboard.general
            if NSImage.canInit(with: pasteboard), let image = NSImage(pasteboard: pasteboard), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                self.addSticker(cgImage, fileId: nil)
                return .invoked
            }
            return .invokeNext
        }, with: self, for: .V, priority: .modal, modifierFlags: [.command])

        let toolHandler: (EditImageCanvasTool) -> (NSEvent) -> KeyHandlerResult = { [weak self] tool in
            return { _ in
                guard let self = self, !self.isTextInputActive, self.state.editingEntityId == nil else {
                    return .invokeNext
                }
                self.genericView.arguments?.selectTool(tool)
                return .invoked
            }
        }
        window?.set(handler: toolHandler(.pen), with: self, for: .L, priority: .modal)
        window?.set(handler: toolHandler(.arrow), with: self, for: .A, priority: .modal)
        window?.set(handler: toolHandler(.eraser), with: self, for: .E, priority: .modal)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelStickerDrag()
        stickerPicker?.close()
        window?.removeAllHandlers(for: self)
    }
}
