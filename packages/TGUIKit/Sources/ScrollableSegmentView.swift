import AppKit
import ColorPalette
import SwiftSignalKit



public protocol _HasCustomUIEquatableRepresentation {
    func _toCustomUIEquatable() -> UIEquatable?
}

internal protocol _UIEquatableBox {
    var _typeID: ObjectIdentifier { get }
    func _unbox<T : Equatable>() -> T?
    
    func _isEqual(to: _UIEquatableBox) -> Bool?
    
    var _base: Any { get }
    func _downCastConditional<T>(into result: UnsafeMutablePointer<T>) -> Bool
}

internal struct _ConcreteEquatableBox<Base : Equatable> : _UIEquatableBox {
    internal var _baseEquatable: Base
    
    internal init(_ base: Base) {
        self._baseEquatable = base
    }
    
    
    internal var _typeID: ObjectIdentifier {
        return ObjectIdentifier(type(of: self))
    }
    
    internal func _unbox<T : Equatable>() -> T? {
        return (self as _UIEquatableBox as? _ConcreteEquatableBox<T>)?._baseEquatable
    }
    
    internal func _isEqual(to rhs: _UIEquatableBox) -> Bool? {
        if let rhs: Base = rhs._unbox() {
            return _baseEquatable == rhs
        }
        return nil
    }
    
    internal var _base: Any {
        return _baseEquatable
    }
    
    internal
    func _downCastConditional<T>(into result: UnsafeMutablePointer<T>) -> Bool {
        guard let value = _baseEquatable as? T else { return false }
        result.initialize(to: value)
        return true
    }
}


public struct UIEquatable {
    internal var _box: _UIEquatableBox
    internal var _usedCustomRepresentation: Bool
    
    
    public init<H : Equatable>(_ base: H) {
        if let customRepresentation =
            (base as? _HasCustomUIEquatableRepresentation)?._toCustomUIEquatable() {
            self = customRepresentation
            self._usedCustomRepresentation = true
            return
        }
        
        self._box = _ConcreteEquatableBox(base)
        self._usedCustomRepresentation = false
    }
    
    internal init<H : Equatable>(_usingDefaultRepresentationOf base: H) {
        self._box = _ConcreteEquatableBox(base)
        self._usedCustomRepresentation = false
    }
    
    public var base: Any {
        return _box._base
    }
    internal
    func _downCastConditional<T>(into result: UnsafeMutablePointer<T>) -> Bool {
        // Attempt the downcast.
        if _box._downCastConditional(into: result) { return true }
        
        
        
        return false
    }
}

extension UIEquatable : Equatable {
    public static func == (lhs: UIEquatable, rhs: UIEquatable) -> Bool {
        if let result = lhs._box._isEqual(to: rhs._box) { return result }
        
        return false
    }
}

extension UIEquatable : CustomStringConvertible {
    public var description: String {
        return String(describing: base)
    }
}

extension UIEquatable : CustomDebugStringConvertible {
    public var debugDescription: String {
        return "UIEquatable(" + String(reflecting: base) + ")"
    }
}

extension UIEquatable : CustomReflectable {
    public var customMirror: Mirror {
        return Mirror(
            self,
            children: ["value": base])
    }
}

public final class ScrollableSegmentItem : Equatable, Comparable, Identifiable {
    public let title: String
    public let selected: Bool
    let theme: ScrollableSegmentTheme
    let insets: NSEdgeInsets
    let icon: CGImage?
    fileprivate let iconProvider: (() -> CGImage?)?
    let equatable: UIEquatable?
    public let index: Int
    public let uniqueId: Int64
    fileprivate var customTextView: (()->NSView?)?
    public var accessibilityLabel: (()->String?)?
    
    public init(title: String, index: Int, uniqueId: Int64, selected: Bool, insets: NSEdgeInsets, icon: CGImage?, theme: ScrollableSegmentTheme, equatable: UIEquatable?, iconProvider: (() -> CGImage?)? = nil, customTextView: (()->NSView?)? = nil) {
        self.title = title
        self.index = index
        self.uniqueId = uniqueId
        self.selected = selected
        self.theme = theme
        self.insets = insets
        self.icon = icon
        self.iconProvider = iconProvider
        self.equatable = equatable
        self.customTextView = customTextView
    }
    
    public var stableId: Int64 {
        return uniqueId
    }
    public static func <(lhs: ScrollableSegmentItem, rhs: ScrollableSegmentItem) -> Bool {
        return lhs.index < rhs.index
    }
    public static func ==(lhs: ScrollableSegmentItem, rhs: ScrollableSegmentItem) -> Bool {
        return lhs.index == rhs.index && lhs.title == rhs.title && lhs.uniqueId == rhs.uniqueId && lhs.selected == rhs.selected && lhs.theme == rhs.theme && lhs.insets == rhs.insets && lhs.equatable == rhs.equatable
    }
    
    fileprivate weak var view:SegmentItemView?
}

private func buildText(for item: ScrollableSegmentItem, theme: ScrollableSegmentTheme) -> TextViewLayout {
    let layout = TextViewLayout.init(.initialize(string: item.title, color: item.selected ? theme.activeText : theme.inactiveText, font: item.theme.textFont))
    layout.measure(width: .greatestFiniteMagnitude)
    return layout
}

private final class SegmentItemView : Control {
    private(set) var item: ScrollableSegmentItem
    private var textLayout: TextViewLayout
    private var imageView: ImageView?
    private var textView: TextView?
    private var customTextView: NSView?
    private let callback: (ScrollableSegmentItem)->Void
    private let menuItems:(ScrollableSegmentItem)->Signal<[ContextMenuItem], NoError>
    private let startDraggingIfNeeded: (ScrollableSegmentItem, Control)->Void
    var pressBegan: ((SegmentItemView, NSPoint) -> Void)?
    var pressEnded: ((NSPoint) -> Void)?
    var shouldStartReorder: (() -> Bool)?
    init(item: ScrollableSegmentItem, theme: ScrollableSegmentTheme, callback: @escaping(ScrollableSegmentItem)->Void, startDraggingIfNeeded: @escaping(ScrollableSegmentItem, Control)->Void, menuItems:@escaping(ScrollableSegmentItem)->Signal<[ContextMenuItem], NoError>) {
        self.item = item
        self.callback = callback
        self.menuItems = menuItems
        self.textLayout = buildText(for: item, theme: theme)
        self.startDraggingIfNeeded = startDraggingIfNeeded
        super.init(frame: NSZeroRect)
        self.handleLongEvent = true
        self.updateItem(item, theme: theme, animated: false)
        
        /*
  
         */
        updateHandlers()
    }
    
    private func updateHandlers() {
        set(handler: { [weak self] _ in
            if self?.item.selected == false {
                self?.textView?.change(opacity: 0.8, animated: true)
                self?.customTextView?._change(opacity: 0.8, animated: true)
                self?.imageView?.change(opacity: 0.8, animated: true)
            }
        }, for: .Highlight)
        
        set(handler: { [weak self] _ in
            self?.textView?.change(opacity: 1.0, animated: true)
            self?.customTextView?._change(opacity: 1.0, animated: true)
            self?.imageView?.change(opacity: 1.0, animated: true)
        }, for: .Normal)
        
        set(handler: { [weak self] _ in
            self?.textView?.change(opacity: 1.0, animated: true)
            self?.customTextView?._change(opacity: 1.0, animated: true)
            self?.imageView?.change(opacity: 1.0, animated: true)
        }, for: .Hover)
        
        
        set(handler: { [weak self] _ in
            guard let `self` = self else {
                return
            }
            self.callback(self.item)
        }, for: .Click)

        set(handler: { [weak self] _ in
            guard let `self` = self, let event = NSApp.currentEvent else {
                return
            }
            self.pressBegan?(self, event.locationInWindow)
        }, for: .Down)

        set(handler: { [weak self] _ in
            guard let event = NSApp.currentEvent else {
                return
            }
            self?.pressEnded?(event.locationInWindow)
        }, for: .Up)
        
        set(handler: { [weak self] control in
            guard let `self` = self else {
                return
            }
            guard self.shouldStartReorder?() ?? true else {
                return
            }
            self.startDraggingIfNeeded(self.item, control)
        }, for: .LongMouseDown)
        
        set(handler: { [weak self] control in
            guard let `self` = self else {
                return
            }
            if let event = NSApp.currentEvent {
                _ = self.menuItems(self.item).start(next: { [weak control] items in
                    if let control = control {
                        ContextMenu.show(items: items, view: control, event: event)
                    }
                })
            }
            
        }, for: .RightDown)
    }
    
    override var accessibilityDefaultLabel: String? {
        return item.accessibilityLabel?() ?? item.title
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return TGUIKitAccessibility.isEnabled ? .radioButton : super.accessibilityRole()
    }

    override func accessibilityValue() -> Any? {
        return TGUIKitAccessibility.isEnabled ? NSNumber(value: item.selected) : super.accessibilityValue()
    }

    override func isAccessibilitySelected() -> Bool {
        return item.selected
    }

    override func accessibilityChildren() -> [Any]? {
        return TGUIKitAccessibility.isEnabled ? [] : super.accessibilityChildren()
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard TGUIKitAccessibility.isEnabled else {
            return false
        }
        let point = convert(NSMakePoint(bounds.midX, bounds.midY), to: nil)
        guard let window, let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) else {
            return false
        }
        _ = menuItems(item).start(next: { [weak self] items in
            if let self, !items.isEmpty {
                ContextMenu.show(items: items, view: self, event: event)
            }
        })
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }
    
    var size: NSSize {
        var width: CGFloat = item.insets.left + item.insets.right
        if let view = self.customTextView {
            width += view.frame.width
        } else {
            width += self.textLayout.layoutSize.width
        }
        if let imageView = imageView {
            width += 5 + imageView.frame.width
        }
        if self.textLayout.layoutSize.width == 0 {
            width -= (5 + (item.insets.left + item.insets.right) / 2)
        }
        
        return NSMakeSize(width, frame.height)
    }
    
    func updateItem(_ item: ScrollableSegmentItem, theme: ScrollableSegmentTheme, animated: Bool) {
        self.item = item
        self.textLayout = buildText(for: item, theme: theme)
        
        if let customTextView = item.customTextView?() {
            self.customTextView?.removeFromSuperview()
            self.customTextView = customTextView
            addSubview(customTextView)
            if let textView {
                performSubviewRemoval(textView, animated: animated)
                self.textView = nil
            }
        } else {
            if let customTextView {
                performSubviewRemoval(customTextView, animated: animated)
                self.customTextView = nil
            }
            let current: TextView
            if let view = self.textView {
                current = view
            } else {
                current = TextView()
                current.isAccessibilityDecorative = true
                self.textView = current
                self.addSubview(current)
                current.userInteractionEnabled = false
                current.isSelectable = false
                current.disableBackgroundDrawing = true
                current.isEventLess = true
            }
            current.update(textLayout)
        }
        
        let icon: CGImage?
        if let iconProvider = item.iconProvider {
            icon = iconProvider()
        } else {
            icon = item.icon
        }
        if let image = icon {
            if imageView == nil {
                imageView = ImageView()
                imageView?.isAccessibilityDecorative = true
                addSubview(imageView!)
                if animated {
                  //  imageView?.layer?.animateAlpha(from: 0, to: 1, duration: duration)
                }
            }
            imageView?.image = image
            imageView?.sizeToFit()
        } else {
            if animated, let imageView = imageView {
                self.imageView = nil
                imageView.removeFromSuperview()

//                imageView.layer?.animateAlpha(from: 1, to: 0, duration: duration, removeOnCompletion: false, completion: { [weak imageView] _ in
//                    imageView?.removeFromSuperview()
//                })
            } else {
                imageView?.removeFromSuperview()
                imageView = nil
            }
           
        }
        
        change(size: size, animated: animated, duration: duration)
        self.backgroundColor = .clear
        textView?.backgroundColor = .clear
        customTextView?.background = .clear
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        let textView = self.textView ?? self.customTextView
        guard let textView else {
            return
        }
        if textView.frame.width > 0 {
            textView.centerY(x: item.insets.left)
            textView.setFrameOrigin(NSMakePoint(textView.frame.minX, textView.frame.minY - item.insets.bottom + item.insets.top))
        } else {
            textView.centerY(x: 0)
        }
        if let imageView = imageView {
            if textView.frame.width > 0 {
                imageView.setFrameOrigin(NSMakePoint(textView.frame.maxX + 5, textView.frame.minY - 2))
            } else {
                imageView.center()
            }
         //   imageView.setFrameOrigin(NSMakePoint(imageView.frame.minX, imageView.frame.minY - (item.insets.bottom + item.insets.top) + 1))
        }
        
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(coder:) has not been implemented")
    }
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class SelectorView : View {
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .duringViewResize
    }
    var theme: ScrollableSegmentTheme? = nil {
        didSet {
            needsDisplay = true
        }
    }
    

    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.round(frame.size, 2.0)
        if let theme = self.theme {
            ctx.setFillColor(theme.selector.cgColor)
            ctx.fill(bounds)
        }
    }
}

public struct ScrollableSegmentTheme : Equatable {
    public let background: NSColor
    public let border: NSColor
    public let selector: NSColor
    public let inactiveText: NSColor
    public let activeText: NSColor
    public let textFont: NSFont
    public init(background: NSColor, border: NSColor, selector: NSColor, inactiveText: NSColor, activeText: NSColor, textFont: NSFont) {
        self.border = border
        self.selector = selector
        self.inactiveText = inactiveText
        self.activeText = activeText
        self.textFont = textFont
        self.background = background
    }
    
    public static func standard(_ colors: ColorPalette) -> ScrollableSegmentTheme {
        return ScrollableSegmentTheme(background: .clear, border: .clear, selector: colors.accent, inactiveText: colors.grayText, activeText: colors.text, textFont: .normal(.text))
    }
}

private let duration: Double = 0.2


private struct ResortData {
    let point: NSPoint
    let item: ScrollableSegmentItem
    let view: Control
    let viewPoint: NSPoint
}

public class ScrollableSegmentView: View {
    public let scrollView:ScrollView = HorizontalScrollView()
    
    private let selectorView: SelectorView = SelectorView(frame: NSZeroRect)
    private let borderView = View()
    
    private let documentView = View()
    private var boundsObserver: NSObjectProtocol?
    private var glassSettingObserver: NSObjectProtocol?
    private var displayOptionsObserver: NSObjectProtocol?
    private var items: [ScrollableSegmentItem] = []
    private var selected:Int = 0
    
    public var menuItems:((ScrollableSegmentItem)->Signal<[ContextMenuItem], NoError>)?

    
    public var fitToWidth: Bool = false

    public static let capsuleInset: CGFloat = 3
    private static let capsuleOverflow: CGFloat = 10
    private var capsuleGlass: LiquidGlassView?
    private var capsuleLens: LiquidGlassLensView?
    private var capsulePill: View?
    private let capsuleClip = CAShapeLayer()
    private let capsuleFade = CAGradientLayer()
    private var capsulePressed: (view: SegmentItemView, index: Int)?
    private var capsuleDisplayedIndex: Int?
    private var capsuleTravelling: Bool = false
    private var capsuleTravelGeneration: Int = 0
    private var capsulePending: (index: Int, time: CFTimeInterval)?
    private var capsuleEscapeMonitor: Any?
    private var capsuleResignObserver: NSObjectProtocol?

    public var capsule: Bool = false {
        didSet {
            if capsule != oldValue {
                updateCapsuleMode()
            }
        }
    }

    private var leadingInset: CGFloat {
        return capsule ? ScrollableSegmentView.capsuleInset : 0
    }

    private var verticalOverflow: CGFloat {
        return capsule ? ScrollableSegmentView.capsuleOverflow : 0
    }

    private var itemsHost: NSView {
        return capsuleLens?.contentView ?? documentView
    }
    
    public var didChangeSelectedItem:((ScrollableSegmentItem)->Void)?
    
    public var theme: ScrollableSegmentTheme = ScrollableSegmentTheme(background: presentation.colors.background, border: presentation.colors.border, selector: presentation.colors.accent, inactiveText: presentation.colors.grayText, activeText: presentation.colors.accent, textFont: .medium(.title))
    {
        didSet {
            if theme != oldValue {
                redraw()
            }
        }
    }
    
    public var resortRange: NSRange? = nil
    public var resortHandler: ((Int, Int)->Void)?
    private var skipNextAnimation: Bool = false
    public override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scrollView)
        addSubview(borderView)
        addSubview(selectorView)
        scrollView.documentView = documentView
        
        
        
//        scrollView.backgroundColor = .clear
//        scrollView.background = .clear
//
//        documentView.backgroundColor = .clear
//
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.clipView, queue: OperationQueue.main, using: { [weak self] notification  in
            self?.needsLayout = true
        })
        glassSettingObserver = NotificationCenter.default.addObserver(forName: systemLiquidGlassDidChange, object: nil, queue: .main) { [weak self] _ in
            if let self, self.capsule {
                self.updateCapsuleMode()
            }
        }
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            if let self, self.capsule {
                self.updateCapsuleMode()
            }
        }
        layout()
        redraw()
        
    }
    
    deinit {
        finishCapsuleGesture()
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        if let glassSettingObserver {
            NotificationCenter.default.removeObserver(glassSettingObserver)
        }
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            needsLayout = true
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        if fitToWidth, documentView.frame.width <= frame.width, mouseInside() {
            let insetBetween: CGFloat = self.insetBetween
            let point = documentView.convert(event.locationInWindow, from: nil)
            
            for item in self.items {
                if let view = item.view {
                    
                    if point.x >= view.frame.minX - (item == self.items.first ? insetBetween : insetBetween / 2) && point.x <= view.frame.maxX + (item == self.items.last ? insetBetween : insetBetween / 2) {
                        self.didChangeSelectedItem?(item)
                        return
                    }
                    
                }
            }
        }
        super.mouseUp(with: event)
    }
    
    public override func updateLocalizationAndTheme(theme presentation: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: presentation)
        self.theme = ScrollableSegmentTheme(background: presentation.colors.background, border: presentation.colors.border, selector: presentation.colors.accent, inactiveText: presentation.colors.grayText, activeText: presentation.colors.accent, textFont: .normal(.title))
    }
    
    private var selectorFrame: CGRect {
        
        let selectedItem = self.items.first(where: { $0.selected })
        
        var x: CGFloat = 0
        var width: CGFloat = frame.width
        if let selectedItem = selectedItem, let view = selectedItem.view {
            let point: NSPoint
            if scrollView.clipView.isAnimateScrolling {
                point = scrollView.documentOffset
            } else {
                point = scrollView.documentOffset
            }
            
            
            x = view.frame.minX + selectedItem.insets.left - point.x
            width = view.size.width - selectedItem.insets.left - selectedItem.insets.right
        }
        
        return CGRect(origin: NSMakePoint(x, frame.height - 6 / 2), size: CGSize(width: width, height: 6))
    }

    
    private func moveSelector(_ animated: Bool = false) {
        self.selectorView.change(pos: selectorFrame.origin, animated: animated)
        self.selectorView.change(size: selectorFrame.size, animated: animated)
        updateCapsuleSelection(animated: animated)
    }

    private func updateCapsuleMode() {
        finishCapsuleGesture()
        capsuleGlass?.removeFromSuperview()
        capsuleGlass = nil
        capsulePill?.removeFromSuperview()
        capsulePill = nil
        let views = items.compactMap { $0.view }
        if let lens = capsuleLens {
            lens.reset()
            for view in views {
                documentView.addSubview(view)
            }
            lens.removeFromSuperview()
            capsuleLens = nil
        }
        selectorView.isHidden = capsule
        borderView.isHidden = capsule
        layer?.masksToBounds = !capsule
        scrollView.layer?.mask = capsule ? capsuleClip : nil
        if capsule {
            capsuleClip.fillColor = NSColor.black.cgColor
            capsuleFade.startPoint = CGPoint(x: 0, y: 0.5)
            capsuleFade.endPoint = CGPoint(x: 1, y: 0.5)
            capsuleClip.mask = capsuleFade
            let glass = LiquidGlassView(frame: bounds, cornerRadius: bounds.height / 2)
            addSubview(glass, positioned: .below, relativeTo: scrollView)
            capsuleGlass = glass
            if System.liquidGlass, !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency, let lens = LiquidGlassLensView.make(frame: documentView.bounds) {
                documentView.addSubview(lens)
                for view in views {
                    lens.contentView.addSubview(view)
                }
                capsuleLens = lens
            } else {
                let pill = View()
                pill.isEventLess = true
                documentView.addSubview(pill, positioned: .below, relativeTo: nil)
                capsulePill = pill
            }
        }
        redraw()
        needsLayout = true
    }

    @objc func _shouldDescendantsContributeToScrollPocket() -> Bool {
        return !capsule
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let lens = capsuleLens, let superview, !isHiddenOrHasHiddenAncestor else {
            return super.hitTest(point)
        }
        guard bounds.contains(convert(point, from: superview)) else {
            return nil
        }
        let local = lens.contentView.convert(point, from: superview)
        for view in lens.contentView.subviews.reversed() where !view.isHidden && view.frame.contains(local) {
            if let hit = view.hitTest(local) {
                return hit
            }
        }
        return super.hitTest(point)
    }

    private var capsuleItemFrames: [NSRect] {
        return items.compactMap { $0.view?.frame.insetBy(dx: 0, dy: ScrollableSegmentView.capsuleInset) }
    }

    private var capsuleSelectedIndex: CGFloat {
        if let pressed = capsulePressed {
            return CGFloat(pressed.index)
        }
        if let pending = capsulePending, CACurrentMediaTime() - pending.time < 1, pending.index < items.count {
            return CGFloat(pending.index)
        }
        capsulePending = nil
        return CGFloat(items.firstIndex(where: { $0.selected }) ?? 0)
    }

    private func capsuleFrame(at position: CGFloat, lifted: Bool) -> NSRect {
        let frames = capsuleItemFrames
        guard !frames.isEmpty else {
            return .zero
        }
        let position = min(CGFloat(frames.count - 1), max(0, position))
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, frames.count - 1)
        let progress = position - CGFloat(lower)
        let first = frames[lower]
        let second = frames[upper]
        let frame = NSMakeRect(first.minX + (second.minX - first.minX) * progress, first.minY, first.width + (second.width - first.width) * progress, first.height)
        return lifted ? frame.insetBy(dx: -10, dy: -8) : frame
    }

    private func beginCapsuleGesture(_ view: SegmentItemView, at point: NSPoint) {
        guard capsuleLens != nil, let index = items.firstIndex(where: { $0.view === view }) else {
            return
        }
        finishCapsuleGesture()
        capsulePressed = (view, index)
        capsuleEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.capsulePressed != nil, event.window === self.window, event.keyCode == 53 else {
                return event
            }
            self.cancelCapsuleGesture()
            return nil
        }
        if let window {
            capsuleResignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.cancelCapsuleGesture()
            }
        }
        updateCapsuleSelection(animated: true)
    }

    private func endCapsuleGesture(at point: NSPoint) {
        guard let pressed = capsulePressed else {
            return
        }
        finishCapsuleGesture()
        if pressed.view.bounds.contains(pressed.view.convert(point, from: nil)), pressed.index < items.count {
            capsulePending = (pressed.index, CACurrentMediaTime())
            capsuleDisplayedIndex = pressed.index
        }
        updateCapsuleSelection(animated: true)
    }

    private func cancelCapsuleGesture() {
        guard capsulePressed != nil else {
            return
        }
        finishCapsuleGesture()
        updateCapsuleSelection(animated: true)
    }

    private func finishCapsuleGesture() {
        capsulePressed = nil
        if let capsuleEscapeMonitor {
            NSEvent.removeMonitor(capsuleEscapeMonitor)
            self.capsuleEscapeMonitor = nil
        }
        if let capsuleResignObserver {
            NotificationCenter.default.removeObserver(capsuleResignObserver)
            self.capsuleResignObserver = nil
        }
    }

    private func updateCapsuleClip(liftedFrame: CGRect? = nil, animation: LiquidGlassLensAnimation = .immediate) {
        let capsuleFrame = bounds.offsetBy(dx: 0, dy: verticalOverflow)
        let visibleBounds = scrollView.clipView.bounds
        let fade = min(6 / max(scrollView.frame.width, 1), 0.5)
        let opaque = NSColor.black.cgColor
        let clear = NSColor.clear.cgColor
        let path = CGMutablePath()
        path.addRoundedRect(in: capsuleFrame, cornerWidth: bounds.height / 2, cornerHeight: bounds.height / 2)
        let bubbleFrame = liftedFrame?.offsetBy(dx: -scrollView.clipView.bounds.minX, dy: -scrollView.clipView.bounds.minY) ?? capsuleFrame
        path.addRoundedRect(in: bubbleFrame, cornerWidth: bubbleFrame.height / 2, cornerHeight: bubbleFrame.height / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capsuleClip.frame = CGRect(origin: .zero, size: scrollView.frame.size)
        capsuleFade.frame = capsuleClip.bounds
        capsuleFade.colors = [visibleBounds.minX > 0 ? clear : opaque, opaque, opaque, visibleBounds.maxX < documentView.frame.width ? clear : opaque]
        capsuleFade.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        animation.update(capsuleClip, key: "path", value: path)
        CATransaction.commit()
    }

    private func updateCapsuleSelection(animated: Bool) {
        guard capsule else {
            return
        }
        let tint = presentation.colors.text.withAlphaComponent(presentation.colors.isDark ? 0.1 : 0.075)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let lens = capsuleLens {
            let position = capsuleSelectedIndex
            let index = Int(position.rounded())
            if capsulePressed == nil, let displayed = capsuleDisplayedIndex, displayed != index, animated, !reduceMotion {
                capsuleTravelling = true
                capsuleTravelGeneration += 1
                let generation = capsuleTravelGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, self.capsuleTravelGeneration == generation else {
                        return
                    }
                    self.capsuleTravelling = false
                    self.updateCapsuleSelection(animated: true)
                }
            }
            if capsulePressed == nil {
                capsuleDisplayedIndex = index
            }
            let lifted = (capsulePressed != nil || capsuleTravelling) && !reduceMotion
            let frame = capsuleFrame(at: position, lifted: lifted)
            let sources = items.compactMap { $0.view }.map { view in
                view.layoutSubtreeIfNeeded()
                return LiquidGlassLensContentSource(view: view)
            }
            let animation: LiquidGlassLensAnimation = animated && !reduceMotion ? .spring(duration: 0.4) : .immediate
            updateCapsuleClip(liftedFrame: lifted ? frame : nil, animation: animation)
            lens.update(lensFrame: frame, interactionProgress: lifted ? 1 : 0, appearance: presentation.appearance, backingScale: window?.backingScaleFactor ?? System.backingScale, animation: animation, restingBlurRadius: 16, restingTintColor: tint, contentSources: sources)
        } else {
            updateCapsuleClip()
            guard let pill = capsulePill else {
                return
            }
            guard !items.isEmpty else {
                pill.isHidden = true
                return
            }
            let target = capsuleFrame(at: capsuleSelectedIndex, lifted: false)
            let animated = animated && !pill.isHidden && pill.frame.height > 0
            pill.isHidden = false
            pill.backgroundColor = tint
            pill.layer?.cornerRadius = target.height / 2
            pill.change(pos: target.origin, animated: animated, duration: 0.35, timingFunction: .spring)
            pill.change(size: target.size, animated: animated, duration: 0.35, timingFunction: .spring)
        }
    }
    
    private var insetBetween: CGFloat {
        var insetBetween: CGFloat = 0
        
        if fitToWidth, items.count > 1 {
            let itemsWidth = items.reduce(CGFloat(0), { current, value in
                return current + (value.view?.size.width ?? 0)
            })
            if itemsWidth < frame.width {
                insetBetween = floor((frame.width - itemsWidth) / CGFloat(items.count + 1))
            }
        }
        return insetBetween
    }
    
    public override func layout() {
        super.layout()
        if let capsuleGlass {
            capsuleGlass.frame = bounds
            capsuleGlass.cornerRadius = bounds.height / 2
            capsuleGlass.updateLayout(size: bounds.size, transition: .immediate)
        }
        scrollView.frame = bounds.insetBy(dx: 0, dy: -verticalOverflow)
        borderView.frame = NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize)
        for item in self.items {
            if let view = item.view {
                view.setFrameSize(NSMakeSize(view.size.width, frame.height))
            }
        }
        
        let insetBetween: CGFloat = self.insetBetween

        
        var x: CGFloat = insetBetween + leadingInset
        
        for item in self.items {
            if let view = item.view {
                view.setFrameOrigin(NSMakePoint(x, verticalOverflow))
                x += view.size.width + insetBetween
            }
        }
        x += leadingInset
        documentView.frame = CGRect(origin: .zero, size: NSMakeSize(max(x, frame.width), frame.height + verticalOverflow * 2))
        capsuleLens?.frame = documentView.bounds
        selectorView.frame = selectorFrame
        updateCapsuleSelection(animated: false)
    }
    
    public func updateItems(_ items:[ScrollableSegmentItem], animated: Bool, autoscroll: Bool = true) -> Void {
        assertOnMainThread()
        
        let animated = animated && !self.skipNextAnimation
        
        self.skipNextAnimation = false
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.items, rightList: items)
        for rdx in deleteIndices.reversed() {
            self.removeItem(at: rdx, animated: animated)
        }
        for (idx, item, _) in indicesAndItems {
            self.insertItem(item, theme: self.theme, at: idx, animated: animated, callback: { [weak self] item in
                self?.didChangeSelectedItem?(item)
            }, menuItems: { [weak self] item in
                guard let menuItems = self?.menuItems else {
                    return .single([])
                }
                return menuItems(item)
            })
        }
        for (idx, item, _) in updateIndices {
            self.updateItem(item, theme: self.theme, at: idx, animated: animated)
        }
        if !deleteIndices.isEmpty || !indicesAndItems.isEmpty || !updateIndices.isEmpty {
            layoutItems(animated: animated)
        }
       
        
        if let selectedItem = items.first(where: { $0.selected }), let selectedView = selectedItem.view, autoscroll {
            let point = NSMakePoint(min(max(selectedView.frame.midX - frame.width / 2, 0), max(documentView.frame.width - frame.width, 0)), 0)
            if point != scrollView.documentOffset, frame != .zero {
                scrollView.clipView.scroll(to: point, animated: animated)
            }
        }
        moveSelector(animated)
    }
    
    private func removeItem(at index: Int, animated: Bool) {
        let view = self.items[index].view
        self.items[index].view = nil
        if animated, let view = view {
            view.layer?.animateAlpha(from: 1, to: 0, duration: duration, removeOnCompletion: false, completion: { [weak view] _ in
                view?.removeFromSuperview()
            })
        } else {
            view?.removeFromSuperview()
        }
        
        self.items.remove(at: index)
    }
    private func updateItem(_ item: ScrollableSegmentItem, theme: ScrollableSegmentTheme, at index: Int, animated: Bool) {
        item.view = self.items[index].view
        item.view?.updateItem(item, theme: theme, animated: animated)
        
        self.items[index] = item
    }
    private func insertItem(_ item: ScrollableSegmentItem, theme: ScrollableSegmentTheme, at index: Int, animated: Bool, callback: @escaping(ScrollableSegmentItem)->Void, menuItems: @escaping(ScrollableSegmentItem)->Signal<[ContextMenuItem], NoError>) {
        let view = SegmentItemView(item: item, theme: theme, callback: callback, startDraggingIfNeeded: { [weak self] item, view in
            self?.startDraggingIfNeeded(item, view)
        }, menuItems: menuItems)
        view.pressBegan = { [weak self] view, point in
            self?.beginCapsuleGesture(view, at: point)
        }
        view.pressEnded = { [weak self] point in
            self?.endCapsuleGesture(at: point)
        }
        view.shouldStartReorder = { [weak self] in
            self?.cancelCapsuleGesture()
            return true
        }
        view.setFrameSize(NSMakeSize(view.frame.width, frame.height))
        item.view = view
        
        let host = self.itemsHost
        var subviews = host.subviews
        
        subviews.insert(view, at: min(index + (host === documentView && capsulePill != nil ? 1 : 0), subviews.count))
        host.subviews = subviews
        self.items.insert(item, at: index)
        
        for (i, item) in self.items.enumerated() {
            if i == index - 1, let v = item.view {
                view.setFrameOrigin(NSMakePoint(v.frame.maxX, verticalOverflow))
            }
        }
    }
    
    private var initialResortData: ResortData?
    
    private func startDraggingIfNeeded(_ item: ScrollableSegmentItem, _ view: Control) {
        if let range = self.resortRange, let window = self.window {
            if range.indexIn(item.index) {
                initialResortData = ResortData(point: self.convert(window.mouseLocationOutsideOfEventStream, from: nil), item: item, view: view, viewPoint: view.frame.origin)
                
                view.set(handler: { [weak self] _ in
                    self?.applyLiveResort()
                }, for: .MouseDragging)
                
                view.set(handler: { [weak self] _ in
                    self?.applyResort()
                }, for: .LongMouseUp)
            }
        }
    }
    
    public func contains(_ id: Int32) -> Bool {
        return self.items.first(where: { $0.uniqueId == id }) != nil
    }
    
    public func index(_ id: Int32) -> Int? {
        return self.items.firstIndex(where: { $0.uniqueId == id }) 
    }
    
    private func applyResort() {
        if let data = initialResortData {
            _ = data.view.removeLastHandler()
            _ = data.view.removeLastHandler()
            layoutItems(animated: true, completion: { [weak self] in
                if let bestIndex = self?.bestIndex {
                    self?.items.move(at: data.item.index, to: bestIndex)
                    self?.resortHandler?(data.item.index, bestIndex)
                    self?.skipNextAnimation = false
                }
                self?.bestIndex = nil
                self?.initialResortData = nil
            })
        }
    }
    private var bestIndex: Int? = nil
    private func applyLiveResort() {
        if let data = initialResortData, let resortRange = resortRange, let window = self.window {
            let currentPoint = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let updatePoint = currentPoint.offsetBy(dx: -data.point.x, dy: -data.point.y)
            data.view.setFrameOrigin(data.viewPoint.offsetBy(dx: updatePoint.x.rounded(), dy: 0))
            selectorView.frame = selectorFrame
            updateCapsuleSelection(animated: false)
            
            var bestIndex: Int = items.count - 1
            let insetBetween: CGFloat = self.insetBetween

            var x: CGFloat = insetBetween
            for (i, item) in self.items.enumerated() {
                if let view = item.view {
                    x += view.frame.width + insetBetween
                }
                if x > currentPoint.x {
                    bestIndex = i
                    break
                }
            }
            
            bestIndex = min(max(resortRange.location, bestIndex), resortRange.max - 1)
            if bestIndex != self.bestIndex {
                self.bestIndex = bestIndex
                x = insetBetween
                for (i, item) in self.items.enumerated() {
                    if let view = item.view {
                        if i == bestIndex, bestIndex <= data.item.index {
                            x += data.view.frame.width + insetBetween
                        }
                        if item != data.item {
                            view.change(pos: NSMakePoint(x, view.frame.minY), animated: true)
                            x += view.frame.width + insetBetween
                        }
                        if i == bestIndex, bestIndex > data.item.index {
                            x += data.view.frame.width + insetBetween
                        }
                    }
                }
                selectorView.change(pos: selectorFrame.origin, animated: true)
                updateCapsuleSelection(animated: true)
            }
            if let event = NSApp.currentEvent {
                scrollView.contentView.autoscroll(with: event)
            }
        }
    }

    
    private func layoutItems(animated: Bool, completion: (()->Void)? = nil) {
        var x: CGFloat = 0
        var items = self.items
        if let data = initialResortData, let bestIndex = self.bestIndex, bestIndex != data.item.index {
            items.insert(items.remove(at: data.item.index), at: bestIndex)
        }
        
        let insetBetween: CGFloat = self.insetBetween
        
       
        x += insetBetween + leadingInset
        for (i, item) in items.enumerated() {
            if let view = item.view {
                view._change(pos: NSMakePoint(x, verticalOverflow), animated: animated, completion: { [weak self] completed in
                    if i == self?.bestIndex {
                        completion?()
                    }
                })
                x += view.size.width + insetBetween
            }
        }
        
        documentView.change(size: NSMakeSize(max(x + leadingInset, frame.width), frame.height + verticalOverflow * 2), animated: animated)
        capsuleLens?.frame = NSMakeRect(0, 0, max(x + leadingInset, frame.width), frame.height + verticalOverflow * 2)
        selectorView.change(pos: selectorFrame.origin, animated: animated)
        updateCapsuleSelection(animated: animated)
    }
    
    private func redraw() {
        selectorView.theme = self.theme
        borderView.backgroundColor = self.theme.border
        backgroundColor = capsule ? .clear : self.theme.background
        scrollView.background = capsule ? .clear : self.theme.background
        for item in self.items {
            item.view?.updateItem(item, theme: self.theme, animated: false)
        }
        updateCapsuleSelection(animated: false)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}
