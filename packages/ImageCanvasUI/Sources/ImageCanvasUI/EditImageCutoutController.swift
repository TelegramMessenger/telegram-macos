import Cocoa
import TGUIKit
import SwiftSignalKit
import ColorPalette
import Localization
import TextRecognizing

@available(macOS 14.0, *)
func editImageCanvasCutoutImage(_ subject: TextRecognizing.Subject) -> CGImage? {
    let rect = subject.rect
    guard rect.width > 0, rect.height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }
    let width = max(1, Int((CGFloat(subject.image.width) / rect.width).rounded()))
    let height = max(1, Int((CGFloat(subject.image.height) / rect.height).rounded()))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.draw(subject.image, in: CGRect(x: rect.minX * CGFloat(width), y: rect.minY * CGFloat(height), width: CGFloat(subject.image.width), height: CGFloat(subject.image.height)))
    return context.makeImage()
}

private final class EditImageCutoutCheckerboard: View {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)
        let columns = 40
        let cell = bounds.width / CGFloat(columns)
        guard cell > 0 else {
            return
        }
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.17).cgColor)
        let rows = Int(ceil(bounds.height / cell))
        for row in 0 ..< rows {
            for column in 0 ..< columns where (row + column).isMultiple(of: 2) {
                ctx.fill(NSMakeRect(CGFloat(column) * cell, CGFloat(row) * cell, cell, cell))
            }
        }
    }
}

@available(macOS 14.0, *)
private final class EditImageCutoutView: View {
    private let imageSize: CGSize
    private let photoView = ImageView()
    private let checkerboard = EditImageCutoutCheckerboard(frame: .zero)
    private let subjectView = View()
    private let subjectLayer = SimpleLayer()
    private var progress: ProgressIndicator?
    private var subjectImage: CGImage?
    private let hint: TextButton
    let photoControl = Control()
    let undo: ImageButton
    let outline: TextButton
    let cancel = ImageButton(frame: NSMakeRect(0, 0, 40, 40))
    let done = ImageButton(frame: NSMakeRect(0, 0, 40, 40))
    var allowsWholeImage = false

    init(frame frameRect: NSRect, image: CGImage) {
        self.imageSize = image.size
        self.hint = makeGlassTextButton(strings().editImageCutoutControllerHint)
        self.undo = makeGlassIconButton(NSImage(resource: .iconEditImageUndo).precomposed(.white), label: strings().voiceOverCommonUndo)
        self.outline = makeGlassTextButton(strings().editImageCutoutControllerAddOutline)
        super.init(frame: frameRect)

        photoView.image = image
        photoView.isAccessibilityDecorative = true

        checkerboard.alphaValue = 0
        checkerboard.layer?.masksToBounds = true

        subjectLayer.contentsGravity = .resize
        subjectLayer.shadowColor = NSColor.white.cgColor
        subjectLayer.shadowRadius = 10
        subjectLayer.shadowOffset = .zero
        subjectLayer.shadowOpacity = 0
        subjectView.isEventLess = true
        subjectView.layer?.addSublayer(subjectLayer)

        photoControl.set(cursor: NSCursor.pointingHand, for: .Hover)
        photoControl.set(cursor: NSCursor.pointingHand, for: .Highlight)
        photoControl.setAccessibilityLabel(strings().editImageCutoutControllerCutOutObject)

        hint.isEventLess = true

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

        addSubview(checkerboard)
        addSubview(photoView)
        addSubview(photoControl)
        addSubview(subjectView)
        addSubview(hint)
        addSubview(undo)
        addSubview(outline)
        addSubview(cancel)
        addSubview(done)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(cut: Bool, outline isOutlined: Bool) {
        hint.isHidden = cut
        undo.isHidden = !cut
        outline.isHidden = !cut
        photoControl.isHidden = cut
        done.isEnabled = cut || allowsWholeImage
        done.alphaValue = cut || allowsWholeImage ? 1.0 : 0.4
        outline.set(text: isOutlined ? strings().editImageCutoutControllerRemoveOutline : strings().editImageCutoutControllerAddOutline, for: .Normal)
        _ = outline.sizeToFit(NSMakeSize(32, 0), NSMakeSize(300, 40), thatFit: false)
        needsLayout = true
    }

    func setProcessing(_ processing: Bool) {
        if processing {
            if progress == nil {
                let progress = ProgressIndicator(frame: NSMakeRect(0, 0, 32, 32))
                progress.progressColor = .white
                addSubview(progress)
                self.progress = progress
            }
        } else {
            progress?.removeFromSuperview()
            progress = nil
        }
        photoView.change(opacity: processing ? 0.6 : 1.0, animated: true)
        needsLayout = true
    }

    func showSubject(_ image: CGImage, from rect: CGRect) {
        let photo = photoView.frame
        let start = NSMakeRect(photo.minX + rect.minX * photo.width, photo.minY + (1 - rect.maxY) * photo.height, rect.width * photo.width, rect.height * photo.height)
        let target = subjectFrame(for: image)
        subjectImage = image
        subjectLayer.contents = image
        subjectLayer.opacity = 1
        subjectLayer.frame = target
        subjectLayer.animateFrame(from: start, to: target, duration: 0.45, timingFunction: .spring)

        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [0, 0.9, 0]
        glow.keyTimes = [0, 0.4, 1]
        glow.duration = 0.8
        subjectLayer.add(glow, forKey: "glow")

        photoView.change(opacity: 0, animated: true, duration: 0.25)
        checkerboard.change(opacity: 1, animated: true, duration: 0.25)
    }

    func setSubjectImage(_ image: CGImage) {
        subjectImage = image
        subjectLayer.contents = image
        subjectLayer.frame = subjectFrame(for: image)
        subjectLayer.animateScaleSpring(from: 0.94, to: 1, duration: 0.35, center: false)
    }

    func hideSubject() {
        subjectImage = nil
        subjectLayer.opacity = 0
        subjectLayer.animateAlpha(from: 1, to: 0, duration: 0.2)
        photoView.change(opacity: 1, animated: true, duration: 0.25)
        checkerboard.change(opacity: 0, animated: true, duration: 0.25)
    }

    private func subjectFrame(for image: CGImage) -> NSRect {
        let box = checkerboard.frame.insetBy(dx: floor(checkerboard.frame.width * 0.08), dy: floor(checkerboard.frame.height * 0.08))
        let size = image.size.aspectFitted(box.size)
        return NSMakeRect(floor(box.midX - size.width / 2.0), floor(box.midY - size.height / 2.0), size.width, size.height)
    }

    override func layout() {
        super.layout()
        undo.setFrameOrigin(NSMakePoint(16, 16))
        hint.setFrameOrigin(NSMakePoint(floor((frame.width - hint.frame.width) / 2.0), 16))

        let rowWidth = min(frame.width - 32, 440)
        let rowX = floor((frame.width - rowWidth) / 2.0)
        let rowY = frame.height - 16 - 40
        cancel.setFrameOrigin(NSMakePoint(rowX, rowY))
        done.setFrameOrigin(NSMakePoint(rowX + rowWidth - done.frame.width, rowY))
        outline.setFrameOrigin(NSMakePoint(floor((frame.width - outline.frame.width) / 2.0), rowY))

        let top: CGFloat = 16 + 40 + 28
        let area = NSMakeRect(56, top, max(1, frame.width - 112), max(1, rowY - 28 - top))
        let fitted = imageSize.fitted(area.size)
        photoView.frame = NSMakeRect(floor(area.midX - fitted.width / 2.0), floor(area.midY - fitted.height / 2.0), fitted.width, fitted.height)
        photoControl.frame = photoView.frame

        let side = floor(min(area.width, area.height))
        checkerboard.frame = NSMakeRect(floor(area.midX - side / 2.0), floor(area.midY - side / 2.0), side, side)
        checkerboard.layer?.cornerRadius = side / 8.0

        if let progress = progress {
            progress.setFrameOrigin(NSMakePoint(floor(photoView.frame.midX - progress.frame.width / 2.0), floor(photoView.frame.midY - progress.frame.height / 2.0)))
        }
        subjectView.frame = bounds
        if let image = subjectImage {
            subjectLayer.frame = subjectFrame(for: image)
        }
    }
}

@available(macOS 14.0, *)
public final class EditImageCutoutController: ModalViewController {
    public var onPresented: (() -> Void)?
    public var onCancelled: (() -> Void)?
    public var onOutputPrepared: ((Bool) -> Void)?
    public var onPreparationFailed: (() -> Void)?
    private let image: CGImage
    private let allowsWholeImage: Bool
    private let doneMenu: ((URL, @escaping () -> Void) -> [ContextMenuItem])?
    private let completion: (URL) -> Void
    private let closeHandler: () -> Void
    private let disposable = MetaDisposable()
    private var subject: TextRecognizing.Subject?
    private var images: (plain: CGImage, outlined: CGImage)?
    private var outline = false
    private var isProcessing = false
    private var isClosing = false

    public init(image: CGImage, allowsWholeImage: Bool = false, doneMenu: ((URL, @escaping () -> Void) -> [ContextMenuItem])? = nil, completion: @escaping (URL) -> Void, closeHandler: @escaping () -> Void) {
        self.image = image
        self.allowsWholeImage = allowsWholeImage
        self.doneMenu = doneMenu
        self.completion = completion
        self.closeHandler = closeHandler
        super.init()
        bar = .init(height: 0)
    }

    deinit {
        disposable.dispose()
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

    public override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        super.close(animationType: animationType)
        self.closeHandler()
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
        return EditImageCutoutView.self
    }

    private var genericView: EditImageCutoutView {
        return self.view as! EditImageCutoutView
    }

    public override func initializer() -> NSView {
        return EditImageCutoutView(frame: NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - bar.height), image: image)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        genericView.photoControl.set(handler: { [weak self] control in
            guard let self = self, let event = NSApp.currentEvent else {
                return
            }
            let point = control.convert(event.locationInWindow, from: nil)
            let size = control.frame.size
            guard size.width > 0, size.height > 0, NSPointInRect(point, control.bounds) else {
                return
            }
            self.cut(at: CGPoint(x: point.x / size.width, y: 1.0 - point.y / size.height))
        }, for: .Click)
        genericView.undo.set(handler: { [weak self] _ in
            self?.undo()
        }, for: .Click)
        genericView.outline.set(handler: { [weak self] _ in
            self?.toggleOutline()
        }, for: .Click)
        genericView.cancel.set(handler: { [weak self] _ in
            self?.cancelExplicitly()
        }, for: .Click)
        genericView.done.set(handler: { [weak self] _ in
            self?.done()
        }, for: .Click)

        genericView.allowsWholeImage = allowsWholeImage
        genericView.update(cut: false, outline: outline)
        readyOnce()
    }

    private func cut(at point: CGPoint) {
        guard !isProcessing, !isClosing, subject == nil else {
            return
        }
        isProcessing = true
        genericView.setProcessing(true)

        let signal = TextRecognizing.liftSubject(image, at: point)
        |> map { subject -> (TextRecognizing.Subject, CGImage, CGImage)? in
            guard let subject = subject, let plain = subject.stickerImage(outline: false), let outlined = subject.stickerImage(outline: true) else {
                return nil
            }
            return (subject, plain, outlined)
        }
        |> deliverOnMainQueue

        disposable.set(signal.start(next: { [weak self] result in
            guard let self = self else {
                return
            }
            self.isProcessing = false
            self.genericView.setProcessing(false)
            guard let result = result else {
                if let window = self.window {
                    showModalText(for: window, text: strings().gallerySubjectNotFound)
                }
                return
            }
            let (subject, plain, outlined) = result
            self.subject = subject
            self.images = (plain: plain, outlined: outlined)
            self.genericView.showSubject(self.outline ? outlined : plain, from: subject.rect)
            self.genericView.update(cut: true, outline: self.outline)
        }))
    }

    private func undo() {
        guard subject != nil, !isClosing else {
            NSSound.beep()
            return
        }
        subject = nil
        images = nil
        genericView.hideSubject()
        genericView.update(cut: false, outline: outline)
    }

    private func toggleOutline() {
        guard let images = images, !isClosing else {
            return
        }
        outline.toggle()
        genericView.setSubjectImage(outline ? images.outlined : images.plain)
        genericView.update(cut: true, outline: outline)
    }

    private func cancel() {
        guard !isClosing else {
            return
        }
        isClosing = true
        disposable.set(nil)
        close()
    }

    private func cancelExplicitly() {
        guard !isClosing else { return }
        onCancelled?()
        cancel()
    }

    private func done() {
        guard subject != nil || allowsWholeImage, !isClosing else {
            return
        }
        isClosing = true
        let subject = self.subject
        let image = self.image
        let outline = self.outline
        let signal: Signal<URL?, NoError> = Signal { subscriber in
            var url: URL?
            let data: Data?
            if let subject = subject {
                data = subject.stickerData(outline: outline)
            } else {
                data = stickerWebP(from: image)?.data
            }
            if let data = data {
                let path = NSTemporaryDirectory() + "sticker_\(Int64.random(in: 0 ... Int64.max)).webp"
                if (try? data.write(to: URL(fileURLWithPath: path))) != nil {
                    url = URL(fileURLWithPath: path)
                }
            }
            subscriber.putNext(url)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(.concurrentDefaultQueue())
        |> deliverOnMainQueue

        disposable.set(signal.start(next: { [weak self] url in
            guard let self = self else {
                return
            }
            if let url = url {
                self.onOutputPrepared?(subject != nil)
                if let doneMenu = self.doneMenu {
                    self.isClosing = false
                    self.showDoneMenu(doneMenu(url, { [weak self] in
                        self?.cancel()
                    }))
                } else {
                    self.completion(url)
                    self.close()
                }
            } else {
                self.isClosing = false
                self.onPreparationFailed?()
                NSSound.beep()
            }
        }))
    }

    private func showDoneMenu(_ items: [ContextMenuItem]) {
        let button = genericView.done
        guard let window = button.window, !items.isEmpty else {
            return
        }
        let location = button.convert(NSMakePoint(button.frame.width / 2.0, button.frame.height / 2.0), to: nil)
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
            return
        }
        ContextMenu.show(items: items, view: button, event: event)
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        done()
        return .invoked
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        cancelExplicitly()
        return .invoked
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onPresented?()
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.undo()
            return .invoked
        }, with: self, for: .Z, priority: .modal, modifierFlags: [.command])
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
}
