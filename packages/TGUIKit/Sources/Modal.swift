import Cocoa
import SwiftSignalKit
import AppKit

public enum ModalHeaderActiveState {
    case normal
    case active
}

private class ModalBackground : Control {
    var isOverlay: Bool = false
    var canRedirectScroll: Bool = false
    
    override var sendRightMouseAnyway: Bool {
        return false
    }
    
    fileprivate override func scrollWheel(with event: NSEvent) {
        if canRedirectScroll {
            super.scrollWheel(with: event)
        }
    }
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    override func mouseMoved(with event: NSEvent) {
        
    }
    
    override func mouseEntered(with event: NSEvent) {
        
    }
    override func mouseExited(with event: NSEvent) {
        
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return false
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
}

final class ModalOverlayPresentation {
    private final class OverlayWindow: Window {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    static func resolve(for requestedWindow: Window) -> ModalOverlayPresentation? {
        if let existing = requestedWindow.modalOverlayPresentation {
            return existing
        }
        let sourceWindow: Window?
        let mainWindow: Window
        if let parent = requestedWindow.modalPresentationParent {
            sourceWindow = requestedWindow
            mainWindow = parent
        } else {
            mainWindow = requestedWindow
            let keyWindow = NSApp.keyWindow as? Window
            sourceWindow = keyWindow?.modalPresentationParent === requestedWindow ? keyWindow : nil
        }
        if let existing = mainWindow.modalOverlayPresentation,
           sourceWindow == nil || existing.sourceWindow === sourceWindow {
            return existing
        }
        guard let sourceWindow, sourceWindow.isVisible else { return nil }
        return ModalOverlayPresentation(mainWindow: mainWindow, sourceWindow: sourceWindow)
    }

    let window: Window
    fileprivate weak var sourceWindow: Window?
    private weak var mainWindow: Window?
    private var observers: [NSObjectProtocol] = []

    init(mainWindow: Window, sourceWindow: Window) {
        self.mainWindow = mainWindow
        self.sourceWindow = sourceWindow
        self.window = OverlayWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.level = sourceWindow.level
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.appearance = mainWindow.appearance
        window.contentView?.wantsLayer = true
        updateFrame()
        sourceWindow.addChildWindow(window, ordered: .above)
        mainWindow.modalOverlayPresentation = self
        window.modalOverlayPresentation = self
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: mainWindow, queue: .main) { [weak self] _ in
                self?.updateFrame()
            })
        }
    }

    func contains(_ window: Window) -> Bool {
        return self.window === window || mainWindow === window || sourceWindow === window
    }

    private func updateFrame() {
        guard let mainWindow, let view = mainWindow.contentView else { return }
        window.setFrame(mainWindow.convertToScreen(view.convert(view.bounds, to: nil)), display: true)
    }

    deinit {
        let wasKey = window.isKeyWindow
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if wasKey, let sourceWindow, sourceWindow.isVisible {
            sourceWindow.makeKey()
        }
    }

}

private var activeModals:[WeakReference<Modal>] = []

public enum ModalCancelButtonStyle {
    case glass
    case filled
}

public class ModalInteractions {
    let accept:(()->Void)?
    let cancel:(()->Void)?
    public var acceptTitle:String
    let cancelTitle:String?
    let drawBorder:Bool
    public fileprivate(set) var height:CGFloat
    var enables:((Bool)->Void)? = nil
    let alignCancelLeft: Bool
    
    var doneUpdatable:(((TextButton)->Void)->Void)? = nil
    var cancelUpdatable:(((TextButton)->Void)->Void)? = nil
    
    var bottomTextUpdate:(()->Void)? = nil
    var extraActionUpdatable:(((ImageButton)->Void)->Void)? = nil

    public let extraActionImage: CGImage?
    public let extraAction: (()->Void)?

    let singleButton: Bool
    let inset: CGFloat
    public var contentFlowsBehind: Bool = true
    public var shadowAsContentMask: Bool = true
    public var showsShadow: Bool = true
    /// When true, clicks on the empty area of the interactions bar pass through
    /// to the content flowing behind it; only the actual buttons stay clickable.
    /// Useful when the bar has no accept/cancel buttons and would otherwise
    /// block taps on the content below it.
    public var isEventless: Bool = false
    public var glassButtons: Bool = false
    public var cancelButtonStyle: ModalCancelButtonStyle = .glass
    fileprivate var customTheme: ()->ModalViewController.Theme

    public var bottomText: TextViewLayout? {
        didSet {
            bottomTextUpdate?()
        }
    }
    
    public init(acceptTitle:String, accept:(()->Void)? = nil, cancelTitle:String? = nil, cancel:(()->Void)? = nil, drawBorder:Bool = false, height:CGFloat = 60, inset: CGFloat = 0, alignCancelLeft: Bool = false, singleButton: Bool = false, bottomText: TextViewLayout? = nil, extraActionImage: CGImage? = nil, extraAction: (()->Void)? = nil, customTheme: @escaping() -> ModalViewController.Theme = { .init() })  {
        self.drawBorder = drawBorder
        self.accept = accept
        self.cancel = cancel
        self.acceptTitle = acceptTitle
        self.cancelTitle = cancelTitle
        self.height = height
        self.inset = inset
        self.alignCancelLeft = alignCancelLeft
        self.singleButton = singleButton
        self.customTheme = customTheme
        self.bottomText = bottomText
        self.extraActionImage = extraActionImage
        self.extraAction = extraAction
    }
    
    public func updateEnables(_ enable:Bool) -> Void {
        if let enables = enables {
            enables(enable)
        }
    }
    
    public func updateDone(_ f:@escaping (TextButton) -> Void) -> Void {
        doneUpdatable?(f)
    }
    public func updateCancel(_ f:@escaping(TextButton) -> Void) -> Void {
        cancelUpdatable?(f)
    }
    public func updateBottomText(_ text: TextViewLayout?) -> Void {
        self.bottomText = text
    }
    public func updateExtraAction(_ f:@escaping (ImageButton) -> Void) -> Void {
        extraActionUpdatable?(f)
    }
}

private class ModalInteractionsContainer : View {
    let acceptView:TextButton
    let cancelView:TextButton?
    let extraActionView:ImageButton?
    let interactions:ModalInteractions
    let borderView:View?

    private var bottomTextView:TextView?

    private let backgroundView = View()
    private let shadowEdgeView = EdgeEffectView()
    private var shadowEdgeColor: NSColor = .clear
    
    override func mouseUp(with event: NSEvent) {
        
    }
    override func mouseDown(with event: NSEvent) {
        
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        
        let pres = interactions.customTheme()
        
        if let cancelView = cancelView {
            cancelView.set(background: .clear, for: .Normal)
            cancelView.set(font: .medium(.text), for: .Normal)
            if interactions.glassButtons {
                switch interactions.cancelButtonStyle {
                case .glass:
                    let appearance: LiquidGlassAppearance = pres.listBackground.lightness < 0.5 ? .forceDark : .forceLight
                    cancelView.setGlassEffect(forceAppearance: appearance)
                case .filled:
                    cancelView.set(background: pres.text.withAlphaComponent(0.1), for: .Normal)
                    cancelView.set(background: pres.text.withAlphaComponent(0.16), for: .Highlight)
                }
                cancelView.set(color: pres.text, for: .Normal)
            } else {
                cancelView.set(color: pres.accent, for: .Normal)
            }
        }
        
        borderView?.backgroundColor = pres.border

        let shadowColor = interactions.singleButton ? pres.listBackground : pres.background
        if interactions.contentFlowsBehind {
            backgroundColor = .clear
        } else {
            backgroundColor = pres.background
        }
        shadowEdgeColor = shadowColor

        if interactions.singleButton {
            acceptView.set(background: .clear, for: .Normal)
            acceptView.set(background: .clear, for: .Highlight)
            // `setGlassEffect` only constructs the inner LiquidGlassView once
            // (guarded by `_glassView == nil`). Writing `glassTintColor` after
            // is what actually re-applies the tint on subsequent theme passes.
            acceptView.setGlassEffect(tintColor: pres.accent)
            acceptView.glassTintColor = pres.accent
            let textColor = pres.accent.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
            acceptView.set(color: textColor, for: .Normal)

            if let extraActionView = extraActionView {
                let buttonSize: CGFloat = 40
                extraActionView.set(background: .clear, for: .Normal)
                extraActionView.setGlassEffect(size: NSMakeSize(buttonSize, buttonSize), tintColor: pres.accent)
                extraActionView.glassTintColor = pres.accent
            }
        } else if interactions.glassButtons {
            acceptView.set(background: .clear, for: .Normal)
            acceptView.setGlassEffect(tintColor: pres.accent)
            acceptView.glassTintColor = pres.accent
            let textColor = pres.accent.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
            acceptView.set(color: textColor, for: .Normal)
        } else {
            acceptView.set(background: .clear, for: .Normal)
            acceptView.set(color: pres.accent, for: .Normal)
            acceptView.layer?.cornerRadius = 0
        }
        
        acceptView.animates = false
        cancelView?.animates = false

        
        acceptView.set(font: .medium(.text), for: .Normal)
        updateDone(layout: false)
        updateCancel(layout: false)
        updateBottomText(layout: false)

        needsLayout = true
    }
    
    init(interactions:ModalInteractions, modal:Modal) {
        self.interactions = interactions
        acceptView = TextButton()
        acceptView.disableActions()
        acceptView.scaleOnClick = true

        if let cancelTitle = interactions.cancelTitle {
            let cancelView = TextButton()
            self.cancelView = cancelView
            cancelView.set(font: .medium(.text), for: .Normal)
            cancelView.set(text: cancelTitle, for: .Normal)
            _ = cancelView.sizeToFit(NSZeroSize, NSMakeSize(0, interactions.height - 10), thatFit: true)
            cancelView.scaleOnClick = true
        } else {
            cancelView = nil
        }
        

        
        if let image = interactions.extraActionImage {
            let button = ImageButton()
            button.set(image: image, for: .Normal)
            button.scaleOnClick = true
            button.autohighlight = false
            button.sizeToFit()
            self.extraActionView = button
        } else {
            self.extraActionView = nil
        }

        if interactions.drawBorder {
            borderView = View()
            borderView?.backgroundColor = interactions.customTheme().border
        } else {
            borderView = nil
        }

        super.init()
        self.backgroundColor = interactions.contentFlowsBehind ? .clear : interactions.customTheme().background
        if let cancel = interactions.cancel {
            cancelView?.set(handler: { _ in
                cancel()
            }, for: .Click)
        } else {
            cancelView?.set(handler: { [weak modal] _ in
                modal?.controller?.close()
            }, for: .Click)
        }
        
        if let accept = interactions.accept {
            acceptView.set(handler: { _ in
                accept()
            }, for: .Click)
        } else {
            acceptView.set(handler: { [weak modal] _ in
                modal?.controller?.close()
            }, for: .Click)

        }
        
        self.layer?.masksToBounds = false

        shadowEdgeView.isEventLess = true
        shadowEdgeView.isHidden = !interactions.showsShadow
        addSubview(shadowEdgeView)

        backgroundView.backgroundColor = interactions.contentFlowsBehind ? .clear : interactions.customTheme().listBackground


        if interactions.singleButton {
            addSubview(backgroundView)
        }

        // singleButton mode: each button renders its own glass via
        // `setGlassEffect(...)` — no merged-glass container / ghost
        // bookkeeping. They stand alone.
        addSubview(acceptView)
        if let cancelView = cancelView {
            addSubview(cancelView)
        }
        if let extraActionView = extraActionView {
            addSubview(extraActionView)
            if let action = interactions.extraAction {
                extraActionView.set(handler: { _ in
                    action()
                }, for: .Click)
            }
        }
        if let borderView = borderView {
            addSubview(borderView)
        }
        
        interactions.enables = { [weak self] enable in
            self?.acceptView.isEnabled = enable
            self?.acceptView.apply(state: .Normal)
        }
        
        interactions.doneUpdatable = { [weak self] f in
            if let strongSelf = self {
                f(strongSelf.acceptView)
            }
            self?.updateDone()
        }
        interactions.cancelUpdatable = { [weak self] f in
            if let strongSelf = self, let cancelView = strongSelf.cancelView {
                f(cancelView)
            }
            self?.updateCancel()
        }
        interactions.bottomTextUpdate = { [weak self] in
            self?.updateBottomText()
        }
        interactions.extraActionUpdatable = { [weak self] f in
            if let button = self?.extraActionView {
                f(button)
            }
        }
        
        
        acceptView.set(text: interactions.acceptTitle, for: .Normal)
        
        updateLocalizationAndTheme(theme: presentation)
    }
    
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }
    
    public func updateDone(layout: Bool = true) {
        if interactions.singleButton {
            let extraWidth: CGFloat = extraActionView != nil ? (max(extraActionView!.frame.width, 40) + 8) : 0
            _ = acceptView.sizeToFit(NSZeroSize, NSMakeSize(frame.width - 40 - extraWidth, 40), thatFit: true)
        } else {
            if cancelView == nil {
                _ = acceptView.sizeToFit(NSZeroSize, frame.size, thatFit: true)
            } else {
                _ = acceptView.sizeToFit(NSZeroSize, NSMakeSize(0, interactions.height - 10), thatFit: true)
            }
        }
        if layout {
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
    }
    
    public func updateCancel(layout: Bool = true) {
        _ = cancelView?.sizeToFit(NSZeroSize, NSMakeSize(0, interactions.height - 10), thatFit: true)
        if layout {
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
    }
    
    public func updateBottomText(layout: Bool = true) {
        if let bottomLayout = interactions.bottomText {
            let current: TextView
            var isNew: Bool = false
            if let view = self.bottomTextView {
                current = view
            } else {
                current = TextView()
                current.isSelectable = false
                self.bottomTextView = current
                addSubview(current)
                isNew = true
            }
            current.update(bottomLayout)
            if isNew {
                current.centerX(y: frame.height - current.frame.height - 15)
            }
        } else if let view = self.bottomTextView {
            performSubviewRemoval(view, animated: false)
            self.bottomTextView = nil
        }
        if layout {
            self.updateLayout(size: self.frame.size, transition: .animated(duration: 0.2, curve: .easeOut))
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func layout() {
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        guard interactions.isEventless else {
            return result
        }
        // Pass everything through to the content behind, except hits that land
        // on an actual button (accept / cancel / extra). The full-bounds
        // backgroundView and the border would otherwise swallow the tap.
        var view = result
        while let current = view, current !== self {
            if current === acceptView || current === cancelView || current === extraActionView {
                return result
            }
            view = current.superview
        }
        return nil
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        updateDone(layout: false)
        updateCancel(layout: false)
        updateBottomText(layout: false)
        
        let boundsRect = NSMakeRect(0, 0, size.width, size.height)
        

        if self.interactions.singleButton {
            transition.updateFrame(view: backgroundView, frame: boundsRect)

            let extraWidth: CGFloat
            if let extraActionView = extraActionView {
                let buttonSize = max(extraActionView.frame.width, 40)
                extraWidth = buttonSize + 8
                let extraRect = NSMakeRect(
                    size.width - 20 - buttonSize,
                    self.interactions.inset + (40 - buttonSize) / 2,
                    buttonSize,
                    buttonSize
                )
                transition.updateFrame(view: extraActionView, frame: extraRect)
            } else {
                extraWidth = 0
            }

            let acceptRect = NSMakeRect(
                20,
                self.interactions.inset,
                size.width - 40 - extraWidth,
                40
            )
            acceptView.layer?.cornerRadius = acceptRect.height / 2
            transition.updateFrame(view: acceptView, frame: acceptRect)
        } else if interactions.glassButtons, let cancelView = cancelView {
            transition.updateFrame(view: backgroundView, frame: boundsRect)
            let sideInset: CGFloat = 20
            let gap: CGFloat = 10
            let buttonH: CGFloat = 40
            let buttonW = floor((size.width - sideInset * 2 - gap) / 2)
            let by = floor((size.height - buttonH) / 2)
            cancelView.layer?.cornerRadius = buttonH / 2
            acceptView.layer?.cornerRadius = buttonH / 2
            transition.updateFrame(view: cancelView, frame: NSMakeRect(sideInset, by, buttonW, buttonH))
            transition.updateFrame(view: acceptView, frame: NSMakeRect(sideInset + buttonW + gap, by, buttonW, buttonH))
        } else {
            transition.updateFrame(view: backgroundView, frame: boundsRect)

            if cancelView == nil {
                transition.updateFrame(view: acceptView, frame: boundsRect)
            } else {
                transition.updateFrame(
                    view: acceptView,
                    frame: acceptView.centerFrameY(x: size.width - acceptView.frame.width - 30)
                )
            }

            if let cancelView = cancelView {
                cancelView.layer?.cornerRadius = cancelView.frame.height / 2
                if interactions.alignCancelLeft {
                    transition.updateFrame(
                        view: cancelView,
                        frame: cancelView.centerFrameY(x: 20)
                    )
                } else {
                    transition.updateFrame(
                        view: cancelView,
                        frame: cancelView.centerFrameY(x: acceptView.frame.minX - cancelView.frame.width - 30)
                    )
                }
            }
        }

        if let borderView = borderView {
            borderView.isHidden = interactions.contentFlowsBehind
            transition.updateFrame(view: borderView, frame: NSMakeRect(0, 0, size.width, .borderSize))
        }
        
        if let bottomTextView {
            transition.updateFrame(view: bottomTextView, frame: bottomTextView.centerFrameX(y: size.height - bottomTextView.frame.height - 15))
        }

        if interactions.contentFlowsBehind {
            let gradientTop = acceptView.frame.minY - 10
            let edgeRect = CGRect(x: 0, y: gradientTop, width: size.width, height: size.height - gradientTop)
            transition.updateFrame(view: shadowEdgeView, frame: edgeRect)
            shadowEdgeView.update(color: shadowEdgeColor, alpha: 0.6, edge: .top, edgeSize: max(1, edgeRect.height * 0.6), rect: edgeRect, transition: transition)
        } else {
            let shadowHeight: CGFloat = 20
            let edgeRect = CGRect(x: 0, y: -shadowHeight, width: size.width, height: shadowHeight)
            transition.updateFrame(view: shadowEdgeView, frame: edgeRect)
            shadowEdgeView.update(color: shadowEdgeColor, alpha: 0.6, edge: .top, edgeSize: max(1, edgeRect.height * 0.6), rect: edgeRect, transition: transition)
        }
    }

    fileprivate func setShadowGradientHidden(_ hidden: Bool) {
        shadowEdgeView.isHidden = hidden || !interactions.showsShadow
    }
}


private final class ModalHeaderView: View {


    let titleView: TextView = TextView()
    private var  subtitleView: TextView?
    var leftButton: ImageButton?
    var rightButton: ImageButton?
    weak var controller:ModalViewController?
    fileprivate var customTheme: ()->ModalViewController.Theme
    let shadowEdgeView = BlurEdgeView()
    let contentBlurView = EdgeEffectView()
    required init(frame frameRect: NSRect, data: (left: ModalHeaderData?, center: ModalHeaderData?, right: ModalHeaderData?), customTheme: @escaping()->ModalViewController.Theme) {
        self.customTheme = customTheme
        super.init(frame: frameRect)

        self.customTheme = customTheme

        self.layer?.masksToBounds = false

        shadowEdgeView.isEventLess = true
        shadowEdgeView.bgColor = customTheme().listBackground.withAlphaComponent(0.7)

        contentBlurView.isEventLess = true
        contentBlurView.isHidden = true


        titleView.update(makeTitleLayout(data.center, alignment: .left))
        titleView.userInteractionEnabled = data.center?.titleLinkHandler != nil
        titleView.isSelectable = false
        
        backgroundColor = .clear
        borderColor = customTheme().border
        border = [.Bottom]
        
        updateSubtitle(data.center?.subtitle)
        updateButtons(left: data.left, right: data.right)
        addSubview(titleView)
    }

    private enum Side {
        case left
        case right
    }

    private func headerData(_ side: Side) -> ModalHeaderData? {
        switch side {
        case .left:
            return controller?.modalHeader?.left
        case .right:
            return controller?.modalHeader?.right
        }
    }

    private func updateButtons(left: ModalHeaderData?, right: ModalHeaderData?) {
        leftButton = updatedButton(leftButton, data: left, side: .left)
        rightButton = updatedButton(rightButton, data: right, side: .right)
    }

    private func updatedButton(_ current: ImageButton?, data: ModalHeaderData?, side: Side) -> ImageButton? {
        guard let data else {
            current?.removeFromSuperview()
            return nil
        }
        let isText = data.image == nil && data.title != nil && !(side == .left && data.isCloseButton)
        let button: ImageButton
        if let current, (current.contextMenu != nil) == (data.contextMenu != nil), (current is TextButton) == isText {
            button = current
        } else {
            current?.removeFromSuperview()
            button = makeButton(hasContextMenu: data.contextMenu != nil, isText: isText, side: side)
        }
        applyImage(data, to: button, side: side)
        return button
    }

    private func makeButton(hasContextMenu: Bool, isText: Bool, side: Side) -> ImageButton {
        let button: ImageButton = isText ? TextButton() : ImageButton()
        if hasContextMenu {
            button.contextMenu = { [weak self] in
                guard let items = self?.headerData(side)?.contextMenu?() else {
                    return nil
                }
                let menu = ContextMenu()
                for item in items {
                    menu.addItem(item)
                }
                return menu
            }
        } else {
            button.set(handler: { [weak self] _ in
                self?.headerData(side)?.handler?()
            }, for: .Click)
        }
        button.autohighlight = false
        button.scaleOnClick = true
        button.opticalCentering = true
        button.disableActions()
        addSubview(button)
        return button
    }

    private func applyImage(_ data: ModalHeaderData, to button: ImageButton, side: Side) {
        let pres = customTheme()
        if let button = button as? TextButton, let title = data.title {
            applyTitle(title, to: button)
            return
        }
        switch (side, data.isCloseButton, data.image) {
        case (.left, true, _):
            applyChrome(NSImage(named: "Icon_Pip_Close")!.precomposed(pres.text), to: button)
        case (.left, false, let image?), (.right, true, let image?):
            applyChrome(NSImage(cgImage: image, size: image.backingSize).precomposed(pres.text), to: button)
        case (.right, false, let image?):
            button.set(image: image, for: .Normal)
            button.sizeToFit()
        default:
            button.sizeToFit()
        }
    }

    private func applyTitle(_ title: String, to button: TextButton) {
        let glassAppearance: LiquidGlassAppearance = customTheme().listBackground.lightness < 0.5 ? .forceDark : .forceLight
        button.set(font: .medium(.text), for: .Normal)
        button.set(color: customTheme().text, for: .Normal)
        button.set(text: title, for: .Normal)
        button.setGlassEffect(forceAppearance: glassAppearance)
        button.sizeToFit()
        button.setFrameSize(NSMakeSize(button.frame.width + 28, 36))
        button.layer?.masksToBounds = false
        button.setAccessibilityLabel(title)
    }

    private func applyChrome(_ image: CGImage, to button: ImageButton) {
        let glassAppearance: LiquidGlassAppearance = customTheme().listBackground.lightness < 0.5 ? .forceDark : .forceLight
        button.set(image: image, for: .Normal)
        button.setGlassEffect(size: NSMakeSize(36, 36), forceAppearance: glassAppearance)
        button.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        button.layer?.masksToBounds = false
    }

    private func updateSubtitle(_ subtitle: String?) {
        guard let subtitle else {
            subtitleView?.removeFromSuperview()
            subtitleView = nil
            return
        }
        let view: TextView
        if let current = subtitleView {
            view = current
        } else {
            view = TextView()
            view.userInteractionEnabled = false
            view.isSelectable = false
            addSubview(view)
            subtitleView = view
        }
        view.update(TextViewLayout(.initialize(string: subtitle, color: customTheme().grayText, font: .normal(.text)), maximumNumberOfLines: 1))
    }

    private func makeTitleLayout(_ center: ModalHeaderData?, alignment: NSTextAlignment) -> TextViewLayout {
        let layout: TextViewLayout
        if let attributedTitle = center?.attributedTitle {
            layout = TextViewLayout(attributedTitle, maximumNumberOfLines: 2, alignment: alignment)
        } else {
            layout = TextViewLayout(.initialize(string: center?.title, color: customTheme().text, font: .medium(.title)), maximumNumberOfLines: 2, alignment: alignment)
        }
        if let titleLinkHandler = center?.titleLinkHandler {
            layout.interactions = TextViewInteractions(processURL: titleLinkHandler)
        }
        return layout
    }

    func update(header: (left: ModalHeaderData?, center: ModalHeaderData?, right: ModalHeaderData?)?, animated: Bool) {
        titleView.update(makeTitleLayout(header?.center, alignment: .center))
        titleView.userInteractionEnabled = header?.center?.titleLinkHandler != nil
        updateSubtitle(header?.center?.subtitle)
        updateButtons(left: header?.left, right: header?.right)
        needsLayout = true
        if animated {
            titleView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            subtitleView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        }
    }
    
    override func layout() {
        super.layout()
        var additionalSize: CGFloat = 0
        if let rightButton = rightButton {
            additionalSize += rightButton.frame.width * 2
            rightButton.centerY(x: frame.width - rightButton.frame.width - 10)
        }
        
        if let leftButton = leftButton {
            additionalSize += leftButton.frame.width * 2
            leftButton.centerY(x: 10)
        }
        
        titleView.textLayout?.measure(width: frame.width - 40 - additionalSize)
        titleView.update(titleView.textLayout)
        
        subtitleView?.textLayout?.measure(width: frame.width - 40 - additionalSize)
        subtitleView?.update(subtitleView?.textLayout)
        
        if let subtitleView = subtitleView {
            let center = frame.midY
            titleView.centerX(y: center - titleView.frame.height - 1)
            subtitleView.centerX(y: center + 1)
        } else {
            titleView.center()
        }
    }

    func updateShadowFrame(in targetSuperview: NSView, transition: ContainedViewLayoutTransition = .immediate) {
        let blurExtension: CGFloat = 0
        let edgeRect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + blurExtension)
        transition.updateFrame(view: shadowEdgeView, frame: edgeRect)
        shadowEdgeView.update(edge: .bottom, edgeSize: blurExtension, rect: edgeRect, transition: transition)

        let fadeSize = max(1, edgeRect.height * 0.6)
        let blur = System.blurEnabled ? EdgeEffectView.Blur(rect: edgeRect, edgeSize: fadeSize) : nil
        transition.updateFrame(view: contentBlurView, frame: edgeRect)
        contentBlurView.update(color: .clear, blur: blur, alpha: 0, edge: .bottom, edgeSize: fadeSize, rect: edgeRect, transition: transition)
    }
    
    private func updateBackground(animated: Bool) {
        background = .clear
        borderColor = .clear
        if customTheme().hideUnactiveText {
            self.titleView.change(opacity: state == .normal ? 0 : 1, animated: animated)
        } else {
            self.titleView.change(opacity: 1, animated: animated)
        }
        let edgeOpacity: CGFloat = isEdgeHidden ? 0 : 1
        shadowEdgeView.change(opacity: edgeOpacity, animated: animated)
        contentBlurView.change(opacity: edgeOpacity, animated: animated)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        guard let controller = controller else {
            return
        }
        
        shadowEdgeView.bgColor = customTheme().listBackground.withAlphaComponent(0.7)

        self.updateBackground(animated: false)
        update(header: controller.modalHeader, animated: false)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    private var state: ModalHeaderActiveState = .normal

    var isEdgeHidden: Bool {
        return customTheme().hideUnactiveText && state == .normal
    }

    func makeHeaderState(state: ModalHeaderActiveState,  animated: Bool) {
        self.state = state
        self.updateBackground(animated: animated)
    }

    fileprivate func setShadowGradientHidden(_ hidden: Bool) {
        shadowEdgeView.isHidden = hidden
    }

    fileprivate func setContentBlurHidden(_ hidden: Bool) {
        contentBlurView.isHidden = hidden
    }
}

private class ModalContainerView: View {
    
    let container: View
    let borderView = View()
    required init(frame frameRect: NSRect) {
        container = View(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        super.addSubview(borderView)
        super.addSubview(container)
        borderView.layer?.borderWidth = System.pixel
        container.layer?.masksToBounds = true
    }
    
    override func addSubview(_ view: NSView) {
        container.addSubview(view)
    }

    fileprivate func contentFrame(for size: NSSize) -> NSRect {
        return borderView.isHidden ? size.bounds : size.bounds.insetBy(dx: 1, dy: 1)
    }

    fileprivate func reattachContent(_ view: NSView) {
        view.frame = contentFrame(for: self.bounds.size)
        super.addSubview(view)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseMoved(with event: NSEvent) {
        
    }
    
    override func mouseEntered(with event: NSEvent) {
        
    }
    override func mouseExited(with event: NSEvent) {
        
    }
    fileprivate override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    fileprivate override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
    }
    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        NSCursor.arrow.set()
    }
    
    
    override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if container.superview === self {
            transition.updateFrame(view: container, frame: contentFrame(for: size))
        }
        transition.updateFrame(view: borderView, frame: size.bounds)
    }
}

extension Modal : ObservableViewDelegate {
    
}

// A control (or its container) whose visible corner radius is drawn by a mask/sublayer rather than its
// own `layer.cornerRadius` — e.g. a GeneralRowContainerView, which rounds via a CAShapeLayer mask — can
// report it here so the morph matches its shape.
public let morphAllCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]

public protocol MorphCornerProviding: AnyObject {
    var morphCornerRadius: CGFloat { get }
    var morphCorners: CACornerMask { get }
}

public extension MorphCornerProviding {
    var morphCorners: CACornerMask {
        return morphAllCorners
    }
}

public protocol MorphHoldObserving: AnyObject {
    func morphHoldDidChange(_ isHeld: Bool)
}

// The control's effective visual corner radius and rounded-corner set for the morph: the largest corner
// radius on the control or any control-sized descendant (a circular glass background, a masked row
// container, …), clamped to a full circle, with the corner mask from that same source. A genuinely square
// control reads 0 with all four corners, so every all-four source keeps the uniform-radius morph path.
func morphControlShape(_ view: NSView) -> (radius: CGFloat, corners: CACornerMask) {
    let circle = min(view.bounds.width, view.bounds.height) / 2
    guard circle > 0 else {
        return (0, morphAllCorners)
    }
    let threshold = min(view.bounds.width, view.bounds.height) * 0.7
    func scan(_ v: NSView) -> (CGFloat, CACornerMask) {
        if let glass = v as? LiquidGlassView {
            return (max(0, min(glass.cornerRadius, min(glass.bounds.width, glass.bounds.height) / 2)), morphAllCorners)
        }
        if let provider = v as? MorphCornerProviding {
            return (provider.morphCornerRadius, provider.morphCorners)
        }
        var radius = v.layer?.cornerRadius ?? 0
        var corners = morphAllCorners
        for sub in v.subviews where min(sub.bounds.width, sub.bounds.height) >= threshold {
            let hit = scan(sub)
            if hit.0 > radius {
                radius = hit.0
                corners = hit.1
            }
        }
        return (radius, corners)
    }
    let hit = scan(view)
    return (min(circle, hit.0), hit.1)
}

// A one-shot source for morphing a modal out of the context-menu item that triggered it. A menu item has no
// persistent control (the menu dismisses before/with the modal), so `AppMenuRowItem.invokeClick` registers the
// clicked item's on-screen snapshot + rect just before running its action; a modal opened right after (no
// explicit morphSource) consumes it for an OPEN-ONLY morph, then closes normally (nothing to morph back to).
public enum ModalMorphContextSource {
    public struct Snapshot {
        let image: CGImage
        let screenRect: CGRect
    }

    public private(set) static var current: (() -> NSView?)?

    public static func withSource<Result>(_ source: (() -> NSView?)?, perform action: () throws -> Result) rethrows -> Result {
        let previous = current
        current = source
        defer { current = previous }
        return try action()
    }

    private static var pendingImage: CGImage?
    private static var pendingScreenRect: CGRect = .zero
    private static var pendingTime: CFAbsoluteTime = 0
    private static var generation: Int = 0
    // The modal must open in the same run of events as the click; a stale source is never used.
    private static let maxAge: CFAbsoluteTime = 0.4

    public static func register(image: CGImage, screenRect: CGRect) {
        pendingImage = image
        pendingScreenRect = screenRect
        pendingTime = CFAbsoluteTimeGetCurrent()
        generation += 1
        let gen = generation
        // Don't keep the snapshot in memory past its window: if nothing consumes it, drop it. A newer
        // register (generation bump) or a consume (nils the image) makes this a harmless no-op.
        DispatchQueue.main.asyncAfter(deadline: .now() + maxAge + 0.05) {
            if generation == gen {
                pendingImage = nil
            }
        }
    }
    public static func clear() {
        pendingImage = nil
    }

    public static func captureSnapshot() -> Snapshot? {
        guard let pending = consume() else {
            return nil
        }
        return Snapshot(image: pending.image, screenRect: pending.screenRect)
    }

    static func consume() -> (image: CGImage, screenRect: CGRect)? {
        defer { pendingImage = nil }
        guard let image = pendingImage, CFAbsoluteTimeGetCurrent() - pendingTime < maxAge, pendingScreenRect.width >= 1, pendingScreenRect.height >= 1 else {
            return nil
        }
        return (image, pendingScreenRect)
    }

    // The persistent control a context menu is anchored to (a glass/action button, e.g. the "…" more
    // button in a modal header). A modal opened from one of that menu's items morphs FROM this button and
    // back to it — a LIVE source (open + close), unlike the transient menu-item snapshot above. Registered
    // when the menu opens, cleared when it closes, consumed by the first `showModal` that has no explicit
    // morphSource (the menu's item handler).
    private static weak var pendingOwner: NSView?
    private static var pendingOwnerTime: CFAbsoluteTime = 0
    private static let ownerMaxAge: CFAbsoluteTime = 60

    public static func registerOwner(_ view: NSView) {
        guard view is Control, !viewIsInsideTableRow(view) else {
            pendingOwner = nil
            return
        }
        pendingOwner = view
        pendingOwnerTime = CFAbsoluteTimeGetCurrent()
    }
    private static func viewIsInsideTableRow(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate is TableRowView {
                return true
            }
            current = candidate.superview
        }
        return false
    }
    public static func clearOwner(_ view: NSView) {
        if pendingOwner === view {
            pendingOwner = nil
        }
    }
    static func consumeOwner() -> NSView? {
        defer { pendingOwner = nil }
        guard let view = pendingOwner, CFAbsoluteTimeGetCurrent() - pendingOwnerTime < ownerMaxAge,
              view.window != nil, view.bounds.width >= 1, view.bounds.height >= 1 else {
            return nil
        }
        return view
    }
}

public class Modal: NSObject {
    private let visualEffectView: NSVisualEffectView?
    fileprivate let background:ModalBackground
    fileprivate func isPresented(in window: Window) -> Bool {
        return self.window === window || overlayPresentation?.contains(window) == true
    }

    fileprivate var overlayPresentation: ModalOverlayPresentation?
    fileprivate var controller:ModalViewController? {
        didSet {
            if controller == nil {
                overlayPresentation = nil
            }
        }
    }
    private var container:ModalContainerView!
    public let window:Window
    private let disposable:MetaDisposable = MetaDisposable()
    private var interactionsView:ModalInteractionsContainer?
    private var headerView:ModalHeaderView?

    public func updateHeader(animated: Bool) {
        guard let controller = self.controller, let headerView = self.headerView else {
            return
        }
        headerView.update(header: controller.modalHeader, animated: animated)
    }

    public let interactions:ModalInteractions?
    fileprivate let animated: Bool
    private let isOverlay: Bool
    private let animationType: ModalAnimationType
    private let parentView: NSView?
    private let morphSource: (() -> NSView?)?
    private let morphSnapshot: ModalMorphContextSource.Snapshot?
    private var morph: ModalMorphTransition?
    private weak var heldSource: NSView?
    private var heldSourceWasHidden: Bool = false
    private weak var heldGhost: NSView?
    private var heldGhostWasHidden: Bool = false
    private var heldViaOpacity: Bool = false
    private var heldSourceOpacity: Float = 1
    private var sourceImage: CGImage?
    private var closeMorphRect: NSRect?
    private var closeMorphCorner: CGFloat = 0
    private var closeMorphCorners: CACornerMask = morphAllCorners

    private func holdSource(_ view: NSView) {
        self.heldSource = view
        self.heldSourceWasHidden = view.isHidden
        if let ghost = (view as? Control)?.additionalGlassEffectView {
            self.heldGhost = ghost
            self.heldGhostWasHidden = ghost.isHidden
            ghost.isHidden = true
            view.isHidden = true
        } else if hostsVisualEffect(view) {
            view.isHidden = true
        } else {
            self.heldViaOpacity = true
            self.heldSourceOpacity = view.layer?.opacity ?? 1
            view.layer?.opacity = 0
        }
        (view as? MorphHoldObserving)?.morphHoldDidChange(true)
    }

    private func hostsVisualEffect(_ view: NSView) -> Bool {
        if view is NSVisualEffectView { return true }
        for sub in view.subviews where hostsVisualEffect(sub) { return true }
        return false
    }

    private func releaseSource(animated: Bool, duration: Double) {
        if let ghost = self.heldGhost {
            ghost.isHidden = self.heldGhostWasHidden
            self.heldGhost = nil
        }
        guard let view = self.heldSource else {
            self.heldViaOpacity = false
            return
        }
        self.heldSource = nil
        if self.heldViaOpacity {
            view.layer?.opacity = self.heldSourceOpacity
            self.heldViaOpacity = false
        } else {
            view.isHidden = self.heldSourceWasHidden
        }
        (view as? MorphHoldObserving)?.morphHoldDidChange(false)
    }

    public init(controller:ModalViewController, for window:Window, animated: Bool = true, isOverlay: Bool, animationType: ModalAnimationType, parentView: NSView? = nil, morphSource: (() -> NSView?)? = nil, morphSnapshot: ModalMorphContextSource.Snapshot? = nil) {
        self.parentView = parentView
        self.animationType = animationType
        self.morphSource = morphSource
        self.morphSnapshot = morphSnapshot
        self.controller = controller
        self.window = window
        self.animated = animated
        self.isOverlay = isOverlay
        background = ModalBackground()
        background.isOverlay = isOverlay
        background.canRedirectScroll = controller.redirectMouseAfterClosing
        background.backgroundColor = controller.background
        background.layer?.disableActions()
        
        
        
        
        self.interactions = controller.modalInteractions
        if controller.isVisualEffectBackground {
            self.visualEffectView = NSVisualEffectView(frame: NSZeroRect)
            self.visualEffectView!.material = .ultraDark
            self.visualEffectView!.blendingMode = .withinWindow
            self.visualEffectView!.state = .active
            self.visualEffectView?.wantsLayer = true
        } else {
            self.visualEffectView = nil
        }
        super.init()
        controller.modal = self
        if let interactions = interactions {
            interactionsView = ModalInteractionsContainer(interactions: interactions, modal:self)
            interactionsView?.frame = NSMakeRect(0, controller.bounds.height + controller.bar.height, controller.bounds.width, interactions.height)
        }
        if let header = controller.modalHeader {
            headerView = ModalHeaderView(frame: NSMakeRect(0, 0, controller.bounds.width, 56), data: header, customTheme: { [weak controller] in
                return controller?.modalTheme ?? ModalViewController.Theme()
            })
            headerView?.controller = controller
        }
       
        if controller.isFullScreen {
            controller._frameRect = topView.bounds
        }
        
        let noBorder = controller.contentBelowBackground || controller.containerBackground == .clear || controller.isFullScreen || !controller.hasBorder
        
        container = ModalContainerView(frame: noBorder ? containerRect : containerRect.insetBy(dx: -1, dy: -1))
        container.layer?.cornerRadius = controller.cornerRadius
        container.background = controller.containerBackground
                
        
        self.container.layer?.shouldRasterize = true
        self.container.layer?.rasterizationScale = CGFloat(System.backingScale)
        self.container.layer?.isOpaque = false

        
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 20
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSMakeSize(0, 0)
        
        self.container.shadow = shadow
        
        container.layer?.masksToBounds = false
        container.container.layer?.masksToBounds = true
        container.container.layer?.cornerRadius = controller.cornerRadius
        container.borderView.layer?.borderColor = controller.modalTheme.grayText.withAlphaComponent(0.1).cgColor
        container.borderView.layer?.cornerRadius = controller.cornerRadius
        
        container.borderView.isHidden = noBorder
        
        controller._window = window

        if !controller.contentBelowBackground {
            container.addSubview(controller.view)
        } else {
            controller.loadViewIfNeeded()
        }

        if let headerView = headerView {
            container.addSubview(headerView.contentBlurView)
            container.addSubview(headerView.shadowEdgeView)
            container.addSubview(headerView)
            headerView.updateShadowFrame(in: container)
        }

        if let interactionsView = interactionsView {
            container.addSubview(interactionsView)
        }
        

        background.addSubview(container)
        
        background.userInteractionEnabled = controller.handleEvents
        
        if controller.handleEvents {
            window.set(responder: { [weak controller] () -> NSResponder? in
                return controller?.firstResponder()
            }, with: self, priority: controller.responderPriority)
            
            if controller.handleAllEvents {
                window.set(handler: { [weak controller] _ -> KeyHandlerResult in
                    if let controller = controller, controller.redirectMouseAfterClosing {
                        controller.close()
                        return .rejected
                    }
                    return .rejected
                }, with: self, for: .All, priority: controller.responderPriority)
            }
            
            window.set(escape: { [weak self] _ -> KeyHandlerResult in
                if self?.controller?.escapeKeyAction() == .rejected {
                    if self?.controller?.closable == true {
                        self?.controller?.close()
                    }
                }
                return .invoked
            }, with: self, priority: controller.responderPriority)
            
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                if let controller = self?.controller {
                    return controller.returnKeyAction()
                }
                return .invokeNext
            }, with: self, for: .Return, priority: controller.responderPriority)
            
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                if let controller = self?.controller {
                    return controller.returnKeyAction()
                }
                return .invokeNext
            }, with: self, for: .KeypadEnter, priority: controller.responderPriority)
        }
        
        if controller.redirectMouseAfterClosing {
            window.set(mouseHandler: { [weak self] _ in
                self?.controller?.close()
                return .rejected
            }, with: self, for: .leftMouseDown, priority: controller.responderPriority)
        }
        
        var isDown: Bool = false
        background.isEventLess = controller.redirectMouseAfterClosing
        background.set(handler: { [weak self] control in
            guard let controller = self?.controller, let `self` = self else { return }
            
            if control.mouseInside() && !controller.view._mouseInside() && !self.container._mouseInside() {
                isDown = true
            }
            
            if controller.redirectMouseAfterClosing, let event = NSApp.currentEvent {
                control.performSuperMouseDown(event)
            }
        }, for: .Down)
        
        background.set(handler: { [weak self] control in
            guard let controller = self?.controller, let `self` = self else { return }
            if controller.closable, !controller.view._mouseInside() && !self.container._mouseInside(), isDown {
                controller.close()
            }
            if controller.redirectMouseAfterClosing, let event = NSApp.currentEvent {
                control.performSuperMouseUp(event)
            }
            
            isDown = false

        }, for: .Up)
        
        if controller.dynamicSize {
            background.customHandler.size = { [weak self] (size) in
                self?.controller?.measure(size: size)
            }
        } else if controller.isFullScreen {
            background.customHandler.size = { [weak self] (size) in
                self?.resize(with: size)
            }
        }
        
        activeModals.append(WeakReference(value: self))
    }
    

    private var topView: NSView {
        if let parentView = self.parentView {
            return parentView
        } else {
            return self.window.contentView!
        }
    }
    
    public var containerView: NSView {
        return self.container
    }

    fileprivate var dimColor: NSColor? {
        guard let controller = controller, !controller.isFullScreen, visualEffectView == nil, background.superview != nil else {
            return nil
        }
        let alpha = controller.background.alphaComponent
        return alpha > 0 && alpha < 1 ? controller.background : nil
    }

    fileprivate func setDim(visible: Bool, against other: Modal, duration: Double) {
        guard let color = dimColor else {
            return
        }
        background.backgroundColor = visible ? color : .clear
        guard duration > 0, let otherAlpha = other.dimColor?.alphaComponent else {
            return
        }
        let progress = (0...10).map { CGFloat($0) / 10 }
        let animation = CAKeyframeAnimation(keyPath: "backgroundColor")
        animation.values = progress.map { value -> CGColor in
            let otherOpacity = visible ? 1 - value : value
            let alpha = max(0, 1 - (1 - color.alphaComponent) / (1 - otherAlpha * otherOpacity))
            return color.withAlphaComponent(alpha).cgColor
        }
        animation.keyTimes = progress.map { NSNumber(value: Double($0)) }
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        background.layer?.add(animation, forKey: "backgroundColor")
    }
    
    func observableView(_ view: NSView, didAddSubview: NSView) {
        if isOverlay {
            var subviews = self.window.contentView!.subviews
            if let index = subviews.firstIndex(of: self.background) {
                subviews.remove(at: index)
                subviews.append(self.background)
            }
            self.window.contentView?.subviews = subviews
        }
    }
    
    func observableview(_ view: NSView, willRemoveSubview: NSView) {
        
    }
    
    public func setInteractionHeight(height: CGFloat = 60, animated: Bool) {
        self.controller?.modalInteractions?.height = height
      //  self.resize(with: controller.frame.size, animated: animated, ignoreContainer: true)
    }
    
    public func resize(with size:NSSize, animated:Bool = true, ignoreContainer: Bool = false) {
        var focus:NSRect
        
        let morphing = self.morph?.isOpening == true
        let animated = animated && !morphing
        let size = NSMakeSize(max(size.width, 2), max(size.height, 2))
        
        var headerOffset: CGFloat = 0
        if let headerView = headerView {
            headerOffset += headerView.frame.height
            headerView.setFrameSize(size.width, headerView.frame.height)
            headerView.updateShadowFrame(in: container)
        }
        
        if let interactions = controller?.modalInteractions {
            focus = background.focus(NSMakeSize(size.width, size.height + interactions.height + headerOffset))
            interactionsView?.change(pos: NSMakePoint(0, size.height + headerOffset), animated: animated)
            interactionsView?.setFrameSize(NSMakeSize(size.width, interactions.height))
        } else {
            focus = background.focus(NSMakeSize(size.width, size.height + headerOffset))
        }
        
        if controller?.hasBorder == true {
            focus = focus.insetBy(dx: -1, dy: -1)
        }


        if focus != container.frame {
            let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate

            transition.updateFrame(view: container, frame: focus)
            container.updateLayout(size: focus.size, transition: transition)
            if morphing {
                self.morph?.retarget(to: focus, contentSize: container.contentFrame(for: focus.size).size)
            }
            
            if !ignoreContainer {
                var controllerSize = size
                if let interactions = controller?.modalInteractions, interactions.contentFlowsBehind {
                    controllerSize.height += interactions.height
                }
                controllerSize.height += headerOffset
                let frame = CGRect(origin: .zero, size: controllerSize)
                controller?.updateFrame(frame, transition: transition)
            }
        }
        controller?.didResizeView(size, animated: animated)
        updateContentMask()
    }

    private var contentMaskLayer: CAGradientLayer?

    private func updateContentMask(animated: Bool = false) {
        guard let controller = controller, !controller.contentBelowBackground else { return }

        let useMask = (interactions?.shadowAsContentMask ?? true) && (interactions?.contentFlowsBehind ?? true)

        if !useMask {
            if controller.view.layer?.mask === contentMaskLayer {
                controller.view.layer?.mask = nil
            }
            contentMaskLayer = nil
            headerView?.setShadowGradientHidden(false)
            headerView?.setContentBlurHidden(true)
            interactionsView?.setShadowGradientHidden(false)
            return
        }

        let contentSize = controller.view.bounds.size
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let headerOffset: CGFloat = headerView.map { $0.isEdgeHidden ? 0 : $0.frame.height } ?? 0
        let interactionsHeight: CGFloat = interactions?.height ?? 0

        let mask = contentMaskLayer ?? CAGradientLayer()
        mask.frame = CGRect(origin: .zero, size: contentSize)
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)

        let headerFadeEnd = min(1, headerOffset / contentSize.height)
        let interactionsFadeStart = max(0, 1 - interactionsHeight / contentSize.height)

        mask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor
        ]
        let locations: [NSNumber] = [0, NSNumber(value: Float(headerFadeEnd)), NSNumber(value: Float(interactionsFadeStart)), 1]
        if animated, mask.locations != locations, let from = mask.presentation()?.locations ?? mask.locations {
            mask.animate(from: from as NSArray, to: locations as NSArray, keyPath: "locations", timingFunction: .easeOut, duration: 0.2)
        }
        mask.locations = locations
        mask.disableActions()

        if contentMaskLayer !== mask {
            contentMaskLayer = mask
            controller.view.layer?.mask = mask
        }

        headerView?.setShadowGradientHidden(true)
        headerView?.setContentBlurHidden(false)
        interactionsView?.setShadowGradientHidden(true)
    }
    
    public func updateLocalizationAndTheme(theme: PresentationTheme) {
        self.interactionsView?.updateLocalizationAndTheme(theme: theme)
        self.headerView?.updateLocalizationAndTheme(theme: theme)
    }
    
    private var containerRect:NSRect {
        if let controller = controller {
            var containerRect = controller.bounds
            if let interactions = controller.modalInteractions {
                containerRect.size.height += interactions.height
            }
            if let headerView = headerView {
                containerRect.size.height += headerView.frame.height
            }
            return containerRect
        }
       return NSZeroRect
    }
    
    private var markedAsClosed: Bool = false
    
    public func close(_ callAcceptInteraction:Bool = false, animationType: ModalAnimationCloseBehaviour = .common) ->Void {
        
        if markedAsClosed {
            return
        }
        
        markedAsClosed = true
        disposable.dispose()
        
        window.removeAllHandlers(for: self)
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            window.set(mouseHandler: { [weak self] _ in
                self?.finishClosing()
                return .rejected
            }, with: self, for: type, priority: .supreme)
        }
        controller?.viewWillDisappear(true)
        
        let wasDimOwner = lastDimModal(in: window) === self

        for i in stride(from: activeModals.count - 1, to: -1, by: -1) {
            if activeModals[i].value == self {
                activeModals.remove(at: i)
                break
            }
        }

        if wasDimOwner {
            let duration: Double
            if case .noneDelayed = animationType {
                duration = 0
            } else {
                duration = 0.25
            }
            lastDimModal(in: window)?.setDim(visible: true, against: self, duration: duration)
        }
        
        let animateBackground = !unhideModalIfNeeded() || self.controller?.containerBackground == .clear || animationType == .animateBackground
        
        if callAcceptInteraction, let interactionsView = interactionsView {
            interactionsView.interactions.accept?()
        }
        let background: NSView
        if let visualEffectView = self.visualEffectView {
            background = visualEffectView
        } else {
            background = self.background
        }
        var closeMorphSourceRect: NSRect? = nil
        var closeMorphControlCorner: CGFloat = 0
        var closeMorphControlCorners: CACornerMask = morphAllCorners
        if animationType == .common, self.morphSource != nil {
            if let morphSourceView = self.morphCandidate() {
                closeMorphSourceRect = self.background.convert(morphSourceView.bounds, from: morphSourceView)
                let shape = morphControlShape(morphSourceView)
                closeMorphControlCorner = shape.radius
                closeMorphControlCorners = shape.corners
            } else if let stored = self.closeMorphRect, self.sourceImage != nil {
                // The live source can't be re-resolved at close (e.g. the originating row is behind this
                // modal and was replaced by a table reload, so it is no longer the held view and sits under
                // a covered ancestor). Fall back to the rect we morphed FROM on open so the close stays a
                // symmetric morph instead of a plain fade.
                closeMorphSourceRect = stored
                closeMorphControlCorner = self.closeMorphCorner
                closeMorphControlCorners = self.closeMorphCorners
            }
        }
        if let sourceRect = closeMorphSourceRect {
            // Fade only the dim backdrop's COLOR, not the layer opacity: the morphing
            // container is a child of `background`, so fading the layer's opacity would
            // make the sheet vanish before the morph finishes.
            if let dimLayer = self.background.layer {
                let fromColor = dimLayer.backgroundColor
                dimLayer.backgroundColor = NSColor.clear.cgColor
                let dim = CABasicAnimation(keyPath: "backgroundColor")
                dim.fromValue = fromColor
                dim.toValue = NSColor.clear.cgColor
                dim.duration = 0.4
                dim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                dim.isRemovedOnCompletion = false
                dim.fillMode = .forwards
                dimLayer.add(dim, forKey: "modalMorph.dim")
            }
            let morphBackground = self.controller?.containerBackground.cgColor
            let hasMorphBorder = !self.container.borderView.isHidden
            let morphBorderWidth = hasMorphBorder ? (self.container.borderView.layer?.borderWidth ?? 0) : 0
            let morphBorderColor = hasMorphBorder ? self.container.borderView.layer?.borderColor : nil
            // Reuse the open-time window snapshot for the close. It is a full composite of the real,
            // on-screen control (CGWindowListCreateImage) — every content kind: a delegate-drawn row icon,
            // the label, a NEW/afterNameImage badge, glass. An off-screen re-render can't match that for a
            // held (hidden) control whose layer backing was discarded, and dropped the row's icon + badge.
            // The control's position is still re-resolved live (`sourceRect` above), so a table reload moves
            // the morph target correctly; only truly dynamic pixels (an animating card) read as the open
            // frame, which is a far smaller artefact than losing the icons.
            let closeControlImage = self.sourceImage
            self.morph?.cancel()
            let contentHolder = self.container.container
            self.morph = ModalMorphTransition.close(host: self.background, realView: self.container, liveContent: contentHolder, restoreLiveContent: { [weak self] view in self?.container.reattachContent(view) }, controlImage: closeControlImage, modalImage: nil, backgroundColor: morphBackground, borderWidth: morphBorderWidth, borderColor: morphBorderColor, cornerRadius: self.controller?.cornerRadius ?? 10, controlCornerRadius: closeMorphControlCorner, controlCorners: closeMorphControlCorners, to: sourceRect, from: self.container.frame, completion: { [weak self, weak background] in
                guard let self = self else {
                    background?.removeFromSuperview()
                    return
                }
                self.morph = nil
                self.releaseSource(animated: false, duration: 0)
                background?.layer?.animateAlpha(from: 1, to: 0, duration: 0.15, removeOnCompletion: false, completion: { [weak background] _ in
                    background?.removeFromSuperview()
                })
                self.controller?.view.removeFromSuperview()
                self.controller?.viewDidDisappear(true)
                self.controller?.modal = nil
                self.controller = nil
            })
            return
        }
        self.releaseSource(animated: false, duration: 0)
        switch animationType {
        case let .noneDelayed(duration):
            delay(duration, closure: { [weak self, weak background] in
                background?.removeFromSuperview()
                self?.controller?.view.removeFromSuperview()
                self?.controller?.view.removeFromSuperview()
                self?.controller?.viewDidDisappear(true)
                self?.controller?.modal = nil
                self?.controller = nil
            })
        default:
            if let controller = controller, controller.contentBelowBackground, !animateBackground {
                controller.view._change(opacity: 0, animated: true, removeOnCompletion: false, duration: 0.25, timingFunction: .spring, completion: { [weak self, weak background] _ in
                    background?.removeFromSuperview()
                    self?.controller?.view.removeFromSuperview()
                    self?.controller?.view.removeFromSuperview()
                    self?.controller?.viewDidDisappear(true)
                    self?.controller?.modal = nil
                    self?.controller = nil
                })

            } else if animateBackground {
                background.layer?.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: {[weak self, weak background] complete in
                    if let stongSelf = self {
                        background?.removeFromSuperview()
                        stongSelf.controller?.view.removeFromSuperview()
                        stongSelf.controller?.viewDidDisappear(true)
                        stongSelf.controller?.modal = nil
                        stongSelf.controller = nil
                    }
                })
            } else if let lastActive = activeModals.last?.value {
                background.removeFromSuperview()
                self.controller?.view.removeFromSuperview()
                self.controller?.viewDidDisappear(true)
                self.controller?.modal = nil
                self.controller = nil
                lastActive.containerView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        }
        
       
       
       
        switch animationType {
        case .common, .noMorph, .noneDelayed, .animateBackground:
            break
        case let .scaleToRect(newRect, contentView):
            let oldRect = contentView.convert(contentView.bounds, to: background)
            background.addSubview(contentView)
            contentView.layer?.animatePosition(from: oldRect.origin, to: newRect.origin, duration: 0.25, timingFunction: .spring, removeOnCompletion: false)
            contentView.layer?.animateScaleX(from: 1, to: newRect.width / oldRect.width, duration: 0.25, timingFunction: .spring, removeOnCompletion: false)
            contentView.layer?.animateScaleY(from: 1, to: newRect.height / oldRect.height, duration: 0.25, timingFunction: .spring, removeOnCompletion: false)
        }
    }
    
    private func finishClosing() {
        window.removeAllHandlers(for: self)
        morph = nil
        releaseSource(animated: false, duration: 0)
        visualEffectView?.removeFromSuperview()
        background.removeFromSuperview()
        controller?.view.removeFromSuperview()
        controller?.viewDidDisappear(true)
        controller?.modal = nil
        controller = nil
    }
    
    private var subview: NSView?
    
    public func addSubview(_ view: NSView, animated: Bool) {
        if let subview = self.subview {
            if animated {
                subview.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak subview] _ in
                    subview?.removeFromSuperview()
                })
            } else {
                subview.removeFromSuperview()
            }
        }
        
        view.frame = container.bounds
        self.container.addSubview(view)
        if animated {
            view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        }
        self.subview = view
    }
    
    public func makeHeaderState(state: ModalHeaderActiveState,  animated: Bool) {
        self.headerView?.makeHeaderState(state: state, animated: animated)
        updateContentMask(animated: animated)
    }
    
    deinit {
        releaseSource(animated: false, duration: 0)
        disposable.dispose()
        (window.contentView as? ObervableView)?.remove(listener: self)
        for i in stride(from: activeModals.count - 1, to: -1, by: -1) {
            if activeModals[i].value == self {
                activeModals.remove(at: i)
                break
            }
        }

    }
    
    private func morphCandidate() -> NSView? {
        guard self.animated, self.morphSource != nil, let controller = self.controller else {
            return nil
        }
        guard !ModalMorphTransition.reduceMotion(), !controller.isFullScreen, !controller.contentBelowBackground else {
            return nil
        }
        // Accept the source even while it is hidden if it is the one we are already holding for this
        // modal (close morphs back onto a control we hid on open).
        guard let source = self.morphSource?(), source.window === self.window, (source === self.heldSource || !source.isHiddenOrHasHiddenAncestor), source.bounds.width >= 1, source.bounds.height >= 1 else {
            return nil
        }
        return source
    }

    public func show() -> Void {
        if let controller = controller {
            disposable.set((controller.ready.get() |> take(1)).start(next: { [weak self, weak controller] ready in
                NSCursor.arrow.set()
                
                
                if let strongSelf = self, let controller = controller {
                    let view = strongSelf.topView
                    if controller.contentBelowBackground, !strongSelf.isOverlay {
                        let revealContent = prepareLayerAnimation([controller.view]) {
                            view.addSubview(controller.view)
                            controller.view.center()
                        }
                        if strongSelf.animated {
                            controller.view.layer?.animateAlpha(from: 0.1, to: 1, duration: 0.4, timingFunction: .spring)
                        }
                        revealContent()
                    }
                    let bounds = view.bounds.insetBy(dx: strongSelf.window.modalInset, dy: strongSelf.window.modalInset)

                    strongSelf.background.layer?.cornerRadius = strongSelf.window.modalInset

                    
                    strongSelf.controller?.viewWillAppear(true)
                    strongSelf.visualEffectView?.frame = bounds
                    strongSelf.background.frame = bounds
                    if controller.isFullScreen {
                        strongSelf.container.frame = bounds
                    } else {
                        strongSelf.container.center()
                    }
                    strongSelf.background.background = controller.isFullScreen ? controller.containerBackground : controller.background
                    let morphSourceView = strongSelf.morphCandidate()
                    // Context-menu morph: no explicit source was given, but a menu item was just clicked — morph
                    // the modal out of that item's snapshot (open only; the menu is gone, so the close is normal).
                    var morphStaticSource: (image: CGImage, rect: CGRect)? = nil
                    if morphSourceView == nil, strongSelf.morphSource == nil, strongSelf.animated, case .bottomToCenter = strongSelf.animationType, !controller.isFullScreen, !controller.contentBelowBackground, !ModalMorphTransition.reduceMotion(), let pending = strongSelf.morphSnapshot ?? ModalMorphContextSource.captureSnapshot() {
                        morphStaticSource = (pending.image, pending.screenRect)
                    }
                    strongSelf.visualEffectView?.autoresizingMask = [.width,.height]
                    strongSelf.background.autoresizingMask = [.width,.height]
                    strongSelf.background.customHandler.layout = { [weak strongSelf] view in
                        strongSelf?.container.center()
                    }
                    
                    if controller.isFullScreen {
                        
                        strongSelf.background.customHandler.size = { [weak strongSelf] size in
                            strongSelf?.resize(with: size, animated: false)
                        }
                    }
                    
                    var belowView: NSView?
                    
                    if !strongSelf.isOverlay {
                        for subview in view.subviews.reversed() {
                            if let subview = subview as? ModalBackground {
                                if subview.isOverlay {
                                    belowView = subview
                                }
                            }
                        }
                    }
                    
                    let background: NSView
                    if let visualEffectView = strongSelf.visualEffectView {
                        background = visualEffectView
                        visualEffectView.addSubview(strongSelf.background)
                    } else {
                        background = strongSelf.background
                    }
                    
                    let revealBackground = prepareLayerAnimation([background]) {
                        if let belowView = belowView {
                            view.addSubview(background, positioned: .below, relativeTo: belowView)
                        } else {
                            view.addSubview(background)
                        }
                    }
                    if controller.isFullScreen, case .animateBackground = strongSelf.animationType {
                        strongSelf.visualEffectView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                    if strongSelf.animated, morphSourceView == nil, morphStaticSource == nil {
                        if case .alpha = strongSelf.animationType {
                        } else if case .animateBackground = strongSelf.animationType {
                        } else {
                            strongSelf.container.layer?.animateAlpha(from: 0.1, to: 1.0, duration: 0.25, timingFunction: .spring)
                        }
                        if !controller.isFullScreen {
                            switch strongSelf.animationType {
                            case .bottomToCenter:
                                let origin = strongSelf.container.frame.origin
                                strongSelf.container.layer?.animatePosition(from: NSMakePoint(origin.x, origin.y + 100), to: origin, timingFunction: .spring)
                            case .scaleCenter:
                                strongSelf.container.layer?.animateScaleSpring(from: 0.5, to: 1.0, duration: 0.35, bounce: true)
                            case let .scaleFrom(oldRect):
                                let view = strongSelf.container!
                                let newRect = view.frame
                                view.layer?.animateAlpha(from: 0.1, to: 1.0, duration: 0.15, timingFunction: .spring)
                                view.layer?.animatePosition(from: oldRect.origin, to: newRect.origin, duration: 0.3, timingFunction: .spring)
                                view.layer?.animateScaleX(from: oldRect.width / newRect.width, to: 1, duration: 0.3, timingFunction: .spring)
                                view.layer?.animateScaleY(from: oldRect.height / newRect.height, to: 1, duration: 0.3, timingFunction: .spring)
                            case .alpha:
                                view.layer?.animateAlpha(from: 1.0, to: 1.0, duration: 0.15, timingFunction: .spring)
                            case .animateBackground:
                                strongSelf.visualEffectView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                            case .none:
                                break
                            }
                        }
                    }
                    if let morphSourceView = morphSourceView {
                        let sourceRect = strongSelf.background.convert(morphSourceView.bounds, from: morphSourceView)
                        let displayedRect = strongSelf.background.convert(ModalMorphTransition.displayedBounds(morphSourceView), from: morphSourceView)
                        strongSelf.sourceImage = ModalMorphTransition.controlImage(morphSourceView)
                        let shape = morphControlShape(morphSourceView)
                        let controlCornerRadius = shape.radius
                        let morphBackground = controller.containerBackground.cgColor
                        let hasMorphBorder = !strongSelf.container.borderView.isHidden
                        let morphBorderWidth = hasMorphBorder ? (strongSelf.container.borderView.layer?.borderWidth ?? 0) : 0
                        let morphBorderColor = hasMorphBorder ? strongSelf.container.borderView.layer?.borderColor : nil
                        strongSelf.closeMorphRect = sourceRect
                        strongSelf.closeMorphCorner = controlCornerRadius
                        strongSelf.closeMorphCorners = shape.corners
                        let contentHolder = strongSelf.container.container
                        strongSelf.morph = ModalMorphTransition.open(host: strongSelf.background, realView: strongSelf.container, liveContent: contentHolder, restoreLiveContent: { [weak strongSelf] view in strongSelf?.container.reattachContent(view) }, controlImage: strongSelf.sourceImage, modalImage: nil, backgroundColor: morphBackground, borderWidth: morphBorderWidth, borderColor: morphBorderColor, cornerRadius: controller.cornerRadius, controlCornerRadius: controlCornerRadius, controlCorners: shape.corners, from: displayedRect, to: strongSelf.container.frame, completion: { [weak strongSelf] in
                            strongSelf?.morph = nil
                        })
                    } else if let morphStaticSource = morphStaticSource {
                        let windowRect = strongSelf.window.convertFromScreen(morphStaticSource.rect)
                        let sourceRect = strongSelf.background.convert(windowRect, from: nil)
                        strongSelf.sourceImage = morphStaticSource.image
                        let morphBackground = controller.containerBackground.cgColor
                        let hasMorphBorder = !strongSelf.container.borderView.isHidden
                        let morphBorderWidth = hasMorphBorder ? (strongSelf.container.borderView.layer?.borderWidth ?? 0) : 0
                        let morphBorderColor = hasMorphBorder ? strongSelf.container.borderView.layer?.borderColor : nil
                        let contentHolder = strongSelf.container.container
                        strongSelf.morph = ModalMorphTransition.open(host: strongSelf.background, realView: strongSelf.container, liveContent: contentHolder, restoreLiveContent: { [weak strongSelf] view in strongSelf?.container.reattachContent(view) }, controlImage: strongSelf.sourceImage, modalImage: nil, backgroundColor: morphBackground, borderWidth: morphBorderWidth, borderColor: morphBorderColor, cornerRadius: controller.cornerRadius, controlCornerRadius: 0, from: sourceRect, to: strongSelf.container.frame, completion: { [weak strongSelf] in
                            strongSelf?.morph = nil
                        })
                    }
                    if controller.contentBelowBackground, strongSelf.isOverlay {
                        let revealContent = prepareLayerAnimation([controller.view]) {
                            view.addSubview(controller.view)
                            controller.view.center()
                        }
                        if strongSelf.animated {
                            controller.view.layer?.animateAlpha(from: 0.1, to: 1, duration: 0.4, timingFunction: .spring)
                        }
                        revealContent()
                    }
                    if let value = strongSelf.controller?.becomeFirstResponder() {
                        if value {
                            _ = strongSelf.window.makeFirstResponder(strongSelf.controller?.firstResponder())
                        } else {
                            _ = strongSelf.window.makeFirstResponder(nil)
                        }
                    }
                    let animatedBackground = strongSelf.animated && !hideBelowModalsIfNeeded(except: strongSelf)
                    if strongSelf.dimColor != nil {
                        lastDimModal(in: strongSelf.window, except: strongSelf)?.setDim(visible: false, against: strongSelf, duration: animatedBackground ? 0.15 : 0)
                    }
                    
                    if animatedBackground {
                        strongSelf.background.layer?.animateAlpha(from: 0, to: 1, duration: 0.15, completion:{[weak strongSelf] (completed) in
                            strongSelf?.controller?.viewDidAppear(true)
                        })
                    } else {
                        strongSelf.controller?.viewDidAppear(false)
                    }
                    revealBackground()
                    if strongSelf.morph != nil, let morphSourceView {
                        strongSelf.holdSource(morphSourceView)
                    }
                }
            }))
        }
        
    }
    
}


public func hasModals() -> Bool {
    
    for i in stride(from: activeModals.count - 1, to: -1, by: -1) {
        if activeModals[i].value == nil {
            activeModals.remove(at: i)
        }
    }
    
    return !activeModals.isEmpty
}

public func hasModals(_ window: Window) -> Bool {
    
    for i in stride(from: activeModals.count - 1, to: -1, by: -1) {
        if activeModals[i].value == nil {
            activeModals.remove(at: i)
        }
    }
    
    return activeModals.contains { $0.value?.isPresented(in: window) == true }
}


public func closeAllModals(window: Window? = nil) {
    for modal in activeModals {
        if let controller = modal.value?.controller, controller.closable {
            if let window = window, modal.value?.isPresented(in: window) == true {
                modal.value?.close()
            } else if window == nil {
                modal.value?.close()
            }
        }
    }
}

public func findModal<T>(_ t: T.Type, isAboveTo: ModalViewController? = nil) -> T? where T:ModalViewController {
    let index = activeModals.firstIndex(where: {
        $0.value?.controller === isAboveTo
    })
    for (i, modal) in activeModals.enumerated() {
        if let controller = modal.value?.controller, type(of: controller) == t {
            if let index = index {
                if index >= i {
                    continue
                }
            }
            return controller as? T
        }
    }
    return nil
}

public enum ModalAnimationType {
    case bottomToCenter
    case scaleCenter
    case scaleFrom(NSRect)
    case alpha
    case none
    case animateBackground
}
public enum ModalAnimationCloseBehaviour : Equatable {
    case common
    // A plain close that never morphs back to the source — for a modal dismissed because its action
    // completed (a message sent, a form confirmed), where morphing back onto the trigger reads as a cancel.
    case noMorph
    case noneDelayed(duration: CGFloat)
    case animateBackground
    case scaleToRect(NSRect, NSView)
}

public func showModal(with controller:ModalViewController, for window:Window, isOverlay: Bool = false, animated: Bool = true, animationType: ModalAnimationType = .bottomToCenter, morphSource: (() -> NSView?)? = nil, morphSnapshot: ModalMorphContextSource.Snapshot? = nil) -> Void {
    assert(controller.modal == nil)
    var morphSource = morphSource ?? (morphSnapshot == nil ? ModalMorphContextSource.current : nil)
    // A modal opened straight from a button's context menu (no explicit morphSource) morphs from that
    // owning button and back, like the attach menu — see ModalMorphContextSource.consumeOwner.
    if morphSource == nil, morphSnapshot == nil, let owner = ModalMorphContextSource.consumeOwner() {
        morphSource = { [weak owner] in owner }
    }
    let overlayPresentation = ModalOverlayPresentation.resolve(for: window)
    let window = overlayPresentation?.window ?? window
    for weakModal in activeModals {
        if overlayPresentation == nil, weakModal.value?.overlayPresentation == nil, weakModal.value?.controller?.className == controller.className, weakModal.value?.controller?.shouldCloseAllTheSameModals == true {
            weakModal.value?.close()
        }
    }

    controller.modal = Modal(controller: controller, for: window, animated: animated, isOverlay: isOverlay, animationType: animationType, morphSource: morphSource, morphSnapshot: morphSnapshot)
    controller.modal?.overlayPresentation = overlayPresentation
    window.makeKeyAndOrderFront(nil)
    controller.modal?.show()
}

public func closeModal(_ type: ModalViewController.Type) -> Void {
    for i in stride(from: activeModals.count - 1, to: -1 , by: -1) {
        let weakModal = activeModals[i]
        if let controller = weakModal.value?.controller, controller.isKind(of: type) {
            weakModal.value?.close()
        }
    }
}

public func showModal(with controller: NavigationViewController, for window:Window, isOverlay: Bool = false, animated: Bool = true, animationType: ModalAnimationType = .bottomToCenter, morphSource: (() -> NSView?)? = nil) -> Void {
    assert(controller.modal == nil)
    var morphSource = morphSource ?? ModalMorphContextSource.current
    if morphSource == nil, let owner = ModalMorphContextSource.consumeOwner() {
        morphSource = { [weak owner] in owner }
    }
    let overlayPresentation = ModalOverlayPresentation.resolve(for: window)
    let window = overlayPresentation?.window ?? window
    for weakModal in activeModals {
        if overlayPresentation == nil, weakModal.value?.overlayPresentation == nil, weakModal.value?.controller?.className == controller.className {
            weakModal.value?.close()
        }
    }

    controller.modal = Modal(controller: ModalController(controller), for: window, animated: animated, isOverlay: isOverlay, animationType: animationType, morphSource: morphSource)
    controller.modal?.overlayPresentation = overlayPresentation
    if overlayPresentation != nil {
        window.makeKeyAndOrderFront(nil)
    }
    controller.modal?.show()

}


private func lastDimModal(in window: Window, except: Modal? = nil) -> Modal? {
    return activeModals.compactMap { $0.value }.last(where: { $0 !== except && $0.window === window && $0.dimColor != nil })
}

private func hideBelowModalsIfNeeded(except: Modal) -> Bool {
//    var hided: Bool = false
//    if let exceptController = except.controller, exceptController.containerBackground != .clear {
//        for modal in activeModals {
//            if modal.value != except, let controller = modal.value?.controller, !controller.isFullScreen {
//                modal.value?.background.isHidden = true
//                hided = true
//            }
//        }
//    }
//
//    return hided
    return false
}

private func unhideModalIfNeeded() -> Bool {
//    activeModals.last?.value?.background.isHidden = false
    return false
}
