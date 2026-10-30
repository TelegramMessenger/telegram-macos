import Cocoa
import TGUIKit
import SwiftSignalKit
import ColorPalette
import Localization

final class EditVideoCropView: View {
    let imageView = ImageView()
    let selection = SelectionRectView(frame: NSMakeRect(0, 0, 100, 100))
    let cancel = makeEditVideoCancelButton()
    let done = makeEditVideoDoneButton()
    let rotate: ImageButton
    let mirror: ImageButton
    let aspect: ImageButton
    let reset = TextButton()
    var imageSize: NSSize = NSMakeSize(16, 9)

    required init(frame frameRect: NSRect) {
        self.rotate = makeGlassIconButton(NSImage(resource: .iconEditVideoRotate).precomposed(.white), label: strings().voiceOverCommonRotate)
        self.mirror = makeGlassIconButton(NSImage(resource: .iconEditVideoFlip).precomposed(.white), label: strings().voiceOverCommonFlip)
        self.aspect = makeGlassIconButton(NSImage(resource: .iconEditVideoAspect).precomposed(.white), label: strings().voiceOverCommonAspectRatio)
        super.init(frame: frameRect)
        imageView.isAccessibilityDecorative = true
        addSubview(imageView)
        imageView.addSubview(selection)
        rotate.appTooltip = "⌘R"
        for view in [cancel, done, rotate, mirror, aspect] as [NSView] {
            addSubview(view)
        }
        reset.set(font: .medium(.title), for: .Normal)
        reset.set(color: .white, for: .Normal)
        reset.set(text: strings().editImageControlReset, for: .Normal)
        reset.autohighlight = false
        reset.scaleOnClick = true
        _ = reset.sizeToFit()
        addSubview(reset)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(mirrored: Bool, hasAspect: Bool) {
        mirror.set(image: NSImage(resource: .iconEditVideoFlip).precomposed(mirrored ? nightAccentPalette.accent : .white), for: .Normal)
        aspect.set(image: NSImage(resource: .iconEditVideoAspect).precomposed(hasAspect ? nightAccentPalette.accent : .white), for: .Normal)
    }

    override func layout() {
        super.layout()
        let rowY = frame.height - 16 - 40
        layoutEditVideoRow(in: self, y: rowY, cancel: cancel, done: done, center: [rotate, mirror, aspect])
        reset.setFrameOrigin(NSMakePoint(floor((frame.width - reset.frame.width) / 2.0), rowY - 16 - reset.frame.height))
        let area = NSMakeRect(24, 24, max(1, frame.width - 48), max(1, reset.frame.minY - 16 - 24))
        let fitted = imageSize.aspectFitted(area.size)
        imageView.frame = NSMakeRect(floor(area.midX - fitted.width / 2.0), floor(area.midY - fitted.height / 2.0), fitted.width, fitted.height)
        selection.frame = imageView.bounds
    }
}

public final class EditVideoCropController: ModalViewController {
    private let still: CGImage
    private var orientation: EditVideoOrientation
    private var crop: CGRect?
    private var dimensions: SelectionRectDimensions = .none
    private let initialOrientation: EditVideoOrientation
    private let initialCrop: CGRect?
    private let completion: (EditVideoOrientation, CGRect?) -> Void
    private let rectDisposable = MetaDisposable()
    private var isClosing = false

    public init(still: CGImage, orientation: EditVideoOrientation, crop: CGRect?, completion: @escaping (EditVideoOrientation, CGRect?) -> Void) {
        self.still = still
        self.orientation = orientation
        self.crop = crop
        self.initialOrientation = orientation
        self.initialCrop = crop
        self.completion = completion
        super.init()
        bar = .init(height: 0)
    }

    deinit {
        rectDisposable.dispose()
    }

    public override var containerBackground: NSColor {
        return .clear
    }

    public override var isVisualEffectBackground: Bool {
        return true
    }

    public override var background: NSColor {
        return .clear
    }

    public override func measure(size: NSSize) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            self.modal?.resize(with: NSMakeSize(contentSize.width - 80, contentSize.height - 80), animated: false)
        }
    }

    public override var dynamicSize: Bool {
        return true
    }

    public override func viewClass() -> AnyClass {
        return EditVideoCropView.self
    }

    private var genericView: EditVideoCropView {
        return self.view as! EditVideoCropView
    }

    private func normalizedSelection() -> CGRect? {
        let bounds = genericView.imageView.bounds
        guard bounds.width > 0, bounds.height > 0, !genericView.selection.isWholeSelected else {
            return nil
        }
        let rect = genericView.selection.selectedRect
        return CGRect(x: rect.minX / bounds.width, y: rect.minY / bounds.height, width: rect.width / bounds.width, height: rect.height / bounds.height)
    }

    private func applyState() {
        let oriented = EditVideoRenderer.orient(CIImage(cgImage: still), orientation)
        if let image = EditVideoRenderer.context.createCGImage(oriented, from: oriented.extent) {
            genericView.imageView.image = image
            genericView.imageSize = image.size
        }
        genericView.layout()
        let bounds = genericView.imageView.bounds
        let rect: NSRect
        if let crop = crop {
            rect = NSMakeRect(crop.minX * bounds.width, crop.minY * bounds.height, crop.width * bounds.width, crop.height * bounds.height)
        } else {
            rect = bounds
        }
        genericView.selection.applyRect(rect, force: true, dimensions: dimensions)
        genericView.update(mirrored: orientation.mirrored, hasAspect: dimensions != .none)
    }

    private func rotate() {
        crop = normalizedSelection()
        var degrees = orientation.degrees + (orientation.mirrored ? -90 : 90)
        if degrees > 180 {
            degrees -= 360
        }
        if degrees <= -180 {
            degrees += 360
        }
        orientation.degrees = degrees
        if let current = crop {
            crop = CGRect(x: current.minY, y: 1.0 - current.minX - current.width, width: current.height, height: current.width)
        }
        dimensions = .none
        applyState()
    }

    private func mirror() {
        crop = normalizedSelection()
        orientation.mirrored.toggle()
        if let current = crop {
            crop = CGRect(x: 1.0 - current.minX - current.width, y: current.minY, width: current.width, height: current.height)
        }
        applyState()
    }

    private func showAspectMenu(_ control: Control) {
        guard let event = NSApp.currentEvent else {
            return
        }
        if dimensions != .none {
            dimensions = .none
            crop = normalizedSelection()
            applyState()
            return
        }
        let menu = ContextMenu(presentation: .current(nightAccentPalette))
        for value in SelectionRectDimensions.all {
            menu.addItem(ContextMenuItem(value.description, handler: { [weak self] in
                guard let self = self else {
                    return
                }
                self.dimensions = value
                self.crop = self.normalizedSelection()
                self.applyState()
            }))
        }
        AppMenu(menu: menu).show(event: event, view: control)
    }

    private func reset() {
        orientation = .up
        crop = nil
        dimensions = .none
        applyState()
    }

    private func done() {
        guard !isClosing else {
            return
        }
        isClosing = true
        completion(orientation, normalizedSelection())
        close()
    }

    private func cancel() {
        guard !isClosing else {
            return
        }
        isClosing = true
        close()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let genericView = self.genericView
        genericView.cancel.set(handler: { [weak self] _ in
            self?.cancel()
        }, for: .Click)
        genericView.done.set(handler: { [weak self] _ in
            self?.done()
        }, for: .Click)
        genericView.rotate.set(handler: { [weak self] _ in
            self?.rotate()
        }, for: .Click)
        genericView.mirror.set(handler: { [weak self] _ in
            self?.mirror()
        }, for: .Click)
        genericView.aspect.set(handler: { [weak self] control in
            self?.showAspectMenu(control)
        }, for: .Click)
        genericView.reset.set(handler: { [weak self] _ in
            self?.reset()
        }, for: .Click)
        rectDisposable.set(genericView.selection.updatedRect.start(next: { [weak self] rect in
            guard let self = self else {
                return
            }
            self.genericView.selection.applyRect(rect, force: true, dimensions: self.dimensions)
        }))
        applyState()
        readyOnce()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyState()
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.rotate()
            return .invoked
        }, with: self, for: .R, priority: .modal, modifierFlags: [.command])
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        done()
        return .invoked
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        cancel()
        return .invoked
    }
}
