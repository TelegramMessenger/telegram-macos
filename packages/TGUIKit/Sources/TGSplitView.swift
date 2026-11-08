import Foundation
import SwiftSignalKit
import AppKit

fileprivate class SplitMinimisizeView : Control {

    private var startPoint:NSPoint = NSZeroPoint
    private var startDragging: NSPoint = .zero
    private var acceptAllDrags: Bool = false
    weak var splitView:SplitView?
    override init() {
        super.init()
        userInteractionEnabled = false
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    fileprivate override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        checkCursor()
    }


    func checkCursor() {
        if let splitView = splitView {
            if let minimisize = splitView.delegate?.splitViewIsCanMinimisize(), minimisize {
                if mouseInside() || (NSEvent.pressedMouseButtons & (1 << 0)) != 0  {
                    if let cursor = splitView.delegate?.splitResizeCursor(at: self.frame.origin.offsetBy(dx: 5, dy: 0)) {
                        cursor.set()
                    } else {
                        if splitView.state == .minimisize {
                            NSCursor.resizeRight.set()
                        } else {
                            NSCursor.resizeLeft.set()
                        }
                    }

                } else {
                    NSCursor.arrow.set()
                }
            }
        }
    }

    fileprivate override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        checkCursor()
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        checkCursor()
    }


    fileprivate override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        checkCursor()
    }

    fileprivate override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        if let splitView = splitView {
            if let minimisize = splitView.delegate?.splitViewIsCanMinimisize(), minimisize {
                checkCursor()

                let current = splitView.convert(event.locationInWindow, from: nil)

                if startDragging == .zero {
                    startDragging = current
                    acceptAllDrags = false
                }

                if abs(startDragging.x - current.x) > frame.width / 2 || abs(startDragging.y - current.y) > frame.width / 2 || acceptAllDrags {
                    acceptAllDrags = true
                    splitView.delegate?.splitViewShouldResize(at: current)

                    if current.x <= 100, splitView.state != .minimisize {
                        splitView.needMinimisize()
                        startPoint = current
                    } else if current.x >= 100, splitView.state == .minimisize {
                        splitView.needFullsize()
                        startPoint = current
                    } else {
                        splitView.resize(to: current)
                    }
                }
            }

        }
    }

    private func notifyTableEndResize(in view: NSView) {
        for view in view.subviews {
            if let view = view as? TableView {
                view.layoutItems()
            } else {
                notifyTableEndResize(in: view)
            }
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        super.rightMouseUp(with: event)
        startPoint = .zero
        startDragging = .zero
        acceptAllDrags = false
    }

    fileprivate override func mouseUp(with event: NSEvent) {
        startPoint = .zero
        startDragging = .zero
        acceptAllDrags = false
        if let splitView = splitView {
            notifyTableEndResize(in: splitView)
        }
    }

    fileprivate override func mouseDown(with event: NSEvent) {
        if let splitView = splitView {
            startPoint = splitView.convert(event.locationInWindow, from: nil)
        }
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
    }
}

public struct SplitProportion {
    public var min:CGFloat = 0;
    public var max:CGFloat = 0;

    public init(min:CGFloat, max:CGFloat) {
        self.min = min;
        self.max = max;
    }
}

public enum SplitViewState : Int {
    case none = -1;
    case single = 0;
    case dual = 1;
    case triple = 2;
    case minimisize = 3
}


public protocol SplitViewDelegate : AnyObject {
    func splitViewDidNeedSwapToLayout(state:SplitViewState) -> Void
    func splitViewDidNeedMinimisize(controller:ViewController) -> Void
    func splitViewDidNeedFullsize(controller:ViewController) -> Void
    func splitViewIsCanMinimisize() -> Bool
    func splitViewDrawBorder() -> Bool

    func splitViewShouldResize(at point: NSPoint) -> Void

    func splitResizeCursor(at point: NSPoint) -> NSCursor?
}


public class SplitView : View {

    private let minimisizeOverlay:SplitMinimisizeView = SplitMinimisizeView()
    private let container:View
    private var forceNotice:Bool = false
    public var state: SplitViewState = .none {
        didSet {
            let notify:Bool = state != oldValue;
            if(notify) {
                self.delegate?.splitViewDidNeedSwapToLayout(state: state);
            }
            if state == .dual || state == .minimisize {
                if minimisizeOverlay.superview == nil {
                    addSubview(minimisizeOverlay)
                }
            } else {
                minimisizeOverlay.removeFromSuperview()
            }
        }
    }

    public var mustMinimisize: Bool = false
    public private(set) var isAutoMinimisize: Bool = false

    public var collapseToSingle: Bool = false {
        didSet {
            if oldValue != collapseToSingle {
                needsLayout = true
            }
        }
    }

    public var canChangeState:Bool = true;
    public weak var delegate:SplitViewDelegate?


    private var _proportions:[Int:SplitProportion] = [:]
    private var _startSize:[Int:NSSize] = [Int:NSSize]()
    fileprivate var _controllers:[WeakReference<ViewController>] = []
    private var _layoutProportions:[SplitViewState:SplitProportion] = [:]
    private var _fixedControllerIds: Set<Int> = []
    private weak var trailingController: ViewController?
    private var trailingWidth: CGFloat = 0
    private var trailingMinimumLeadingWidth: CGFloat = 0
    private weak var trailingHiding: ViewController?
    private var lastPaneAvailableWidth: CGFloat = 0
    private var trailingTarget: CGFloat = 0
    private var trailingShown: CGFloat = 0
    private var trailingAnimator: DisplayLinkAnimator?
    private var trailingAnimatesChange = false

    public func setTrailing(controller: ViewController?, width: CGFloat, minimumLeadingWidth: CGFloat, animated: Bool = false) {
        if let current = trailingController, current !== controller {
            if controller == nil, current.isLoaded(), current.view.superview === container {
                if let hiding = trailingHiding, hiding !== current {
                    removeTrailing(hiding)
                }
                trailingHiding = current
                current.viewWillDisappear(true)
            } else {
                removeTrailing(current)
            }
        }
        if let controller, trailingHiding === controller {
            trailingHiding = nil
            controller.viewWillAppear(true)
            controller.viewDidAppear(true)
        } else if let hiding = trailingHiding, controller != nil {
            removeTrailing(hiding)
        }
        trailingController = controller
        if controller != nil {
            trailingWidth = width
            trailingMinimumLeadingWidth = minimumLeadingWidth
        }
        trailingAnimatesChange = animated && window != nil && !inLiveResize
        needsLayout = true
    }

    public func additionalWidthForTrailing(width: CGFloat, minimumLeadingWidth: CGFloat) -> CGFloat {
        return max(0, width + minimumLeadingWidth - lastPaneAvailableWidth)
    }

    public func canShowTrailing(width: CGFloat, minimumLeadingWidth: CGFloat) -> Bool {
        return lastPaneAvailableWidth - width >= minimumLeadingWidth
    }

    private func trailingReservedWidth(available: CGFloat) -> CGFloat {
        guard trailingController != nil, available - trailingWidth >= trailingMinimumLeadingWidth else {
            return 0
        }
        return trailingWidth
    }

    private func updateTrailingShown(target: CGFloat) {
        let animates = trailingAnimatesChange && !inLiveResize
        trailingAnimatesChange = false
        guard target != trailingTarget else {
            return
        }
        trailingTarget = target
        if animates {
            trailingAnimator = DisplayLinkAnimator(duration: 0.3, from: trailingShown, to: target, timingFunction: CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.25, 1.0), update: { [weak self] value in
                guard let self else {
                    return
                }
                self.trailingShown = value
                self.needsLayout = true
            }, completion: { [weak self] in
                guard let self else {
                    return
                }
                self.trailingAnimator = nil
                self.needsLayout = true
            })
        } else {
            trailingAnimator?.invalidate()
            trailingAnimator = nil
            trailingShown = target
        }
    }

    private func layoutTrailing(reserved: CGFloat) {
        guard let controller = trailingController ?? trailingHiding else {
            return
        }
        guard reserved > 0 else {
            removeTrailing(controller)
            return
        }
        let insets = controller.insets
        let rect = NSMakeRect(frame.width - reserved + insets.left, insets.top, max(0, trailingWidth - insets.left - insets.right), max(0, frame.height - insets.top - insets.bottom))
        if !controller.isLoaded() {
            controller._frameRect = rect
        }
        if controller.view.superview !== container {
            controller.view.frame = rect
            controller.viewWillAppear(false)
            container.addSubview(controller.view)
            controller.viewDidAppear(false)
        } else {
            if !NSEqualRects(rect, controller.view.frame) {
                controller.view.frame = rect
            }
            if container.subviews.last !== controller.view {
                container.addSubview(controller.view, positioned: .above, relativeTo: nil)
            }
        }
    }

    private func removeTrailing(_ controller: ViewController) {
        let wasHiding = trailingHiding === controller
        if wasHiding {
            trailingHiding = nil
        }
        guard controller.isLoaded(), controller.view.superview === container else {
            return
        }
        if !wasHiding {
            controller.viewWillDisappear(false)
        }
        controller.view.removeFromSuperview()
        controller.viewDidDisappear(wasHiding)
    }

    public func setFixed(controller: ViewController, fixed: Bool) {
        if fixed {
            _fixedControllerIds.insert(controller.internalId)
        } else {
            _fixedControllerIds.remove(controller.internalId)
        }
        needsLayout = true
    }

    public var fixedLeadingWidth: CGFloat {
        var w: CGFloat = 0
        for entry in _controllers {
            if let c = entry.value, _fixedControllerIds.contains(c.internalId), let prop = _proportions[c.internalId] {
                w += prop.min
            }
        }
        return w
    }


    required public init(frame frameRect: NSRect)  {
        container = View(frame: NSMakeRect(0,0,frameRect.width, frameRect.height))
        super.init(frame: frameRect);
        self.layer?.masksToBounds = false
        self.autoresizesSubviews = true
        self.autoresizingMask = [.width, .height]
        container.autoresizesSubviews = false
        container.autoresizingMask = [.width, .height]
        container.layer?.masksToBounds = false
        addSubview(container)
        minimisizeOverlay.splitView = self

    }

    public override var backgroundColor: NSColor {
        didSet {
            container.backgroundColor = backgroundColor
            minimisizeOverlay.needsDisplay = true
        }
    }

    deinit {
        var bp:Int = 0
        bp += 1
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    public func addController(controller:ViewController, proportion:SplitProportion) ->Void {
        controller._frameRect = NSMakeRect(0, 0, proportion.min, frame.height)
        container.addSubview(controller.view);
        controller.viewWillAppear(false)
        _controllers.append(WeakReference(value: controller));
        _startSize.updateValue(controller.view.frame.size, forKey: controller.internalId);
        _proportions.updateValue(proportion, forKey: controller.internalId)
        controller.viewDidAppear(false)
    }

    public func insertController(controller: ViewController, proportion: SplitProportion, at index: Int) -> Void {
        let insets = controller.insets
        let initialWidth = max(0, proportion.min - insets.left - insets.right)
        let initialHeight = max(0, frame.height - insets.top - insets.bottom)
        controller._frameRect = NSMakeRect(insets.left, insets.top, initialWidth, initialHeight)
        let clampedIndex = max(0, min(index, _controllers.count))
        if clampedIndex < container.subviews.count {
            container.addSubview(controller.view, positioned: .below, relativeTo: container.subviews[clampedIndex])
        } else {
            container.addSubview(controller.view)
        }
        controller.viewWillAppear(false)
        _controllers.insert(WeakReference(value: controller), at: clampedIndex)
        _startSize.updateValue(NSMakeSize(proportion.min, frame.height), forKey: controller.internalId)
        _proportions.updateValue(proportion, forKey: controller.internalId)
        controller.viewDidAppear(false)
        needsLayout = true
    }

    public func contains(controller: ViewController) -> Bool {
        return _controllers.contains(where: { $0.value == controller })
    }

    public var fixedControllerCount: Int {
        var count = 0
        for entry in _controllers {
            if let c = entry.value, _fixedControllerIds.contains(c.internalId) {
                count += 1
            }
        }
        return count
    }

    public func removeController(controller:ViewController) -> Void {
        controller.viewWillDisappear(false)
        let idx = _controllers.firstIndex(where: { $0.value == controller });
        if let idx = idx {
            controller.view.removeFromSuperview();
            _controllers.remove(at: idx);
            _startSize.removeValue(forKey: controller.internalId);
            _proportions.removeValue(forKey: controller.internalId);
        }
        controller.viewDidDisappear(false)
        needsLayout = true
    }

    public func setProportion(proportion:SplitProportion, state:SplitViewState) -> Void {
        _layoutProportions[state] = proportion;
    }

    public func updateStartSize(size:NSSize, controller:ViewController) -> Void {
        _startSize[controller.internalId] = size;
        _proportions[controller.internalId] = SplitProportion(min:size.width, max:size.height);
        needsLayout = true
    }

    public func update(_ forceNotice:Bool = false) -> Void {
        Queue.mainQueue().justDispatch {
            self.forceNotice = forceNotice
            self.needsLayout = true
        }
    }

    public var nextLayout: SplitViewState {

        let dual:SplitProportion! = _layoutProportions[.dual]
        let triple:SplitProportion! = _layoutProportions[.triple]

        let mainWidth = frame.width - fixedLeadingWidth
        let narrowState: SplitViewState = collapseToSingle ? .single : .minimisize

        if canChangeState && !mustMinimisize {
            if acceptLayout(prop: dual) {
                if mainWidth >= dual.min {
                    if acceptLayout(prop: triple) {
                        if mainWidth <= dual.max {
                            if state != .dual { return .dual }
                        } else if state != .triple {
                            return .triple
                        }
                    } else {
                        if state != .dual { return .dual }
                    }
                } else if state != narrowState {
                    return narrowState
                }
            }
        } else if mustMinimisize, self.state != .minimisize {
            return .minimisize
        }
        return self.state
    }

    public override func layout() {
        super.layout()

        let dual:SplitProportion! = _layoutProportions[.dual]
        let triple:SplitProportion! = _layoutProportions[.triple]

        let mainWidth = frame.width - fixedLeadingWidth
        let narrowState: SplitViewState = collapseToSingle ? .single : .minimisize

        if canChangeState && !mustMinimisize {
            if acceptLayout(prop: dual) {
                if mainWidth >= dual.min {
                    isAutoMinimisize = false
                    if acceptLayout(prop: triple) {
                        if mainWidth <= dual.max {
                            if state != .dual { state = .dual }
                        } else if state != .triple { state = .triple }
                    } else {
                        if state != .dual { state = .dual }
                    }
                } else if state != narrowState {
                    isAutoMinimisize = (narrowState == .minimisize)
                    state = narrowState
                }
            }
        } else if mustMinimisize, self.state != .minimisize {
            self.state = .minimisize
        }

        if forceNotice {
            forceNotice = false
            self.delegate?.splitViewDidNeedSwapToLayout(state: state)
        }

        let trailingView = [trailingHiding, trailingController].compactMap { $0 }.first(where: { $0.isLoaded() && $0.view.superview === container })?.view
        var previousControllerView: NSView? = nil
        for entry in _controllers {
            guard let view = entry.value?.view, view.superview === container else { continue }
            if let previousControllerView = previousControllerView {
                container.addSubview(view, positioned: .below, relativeTo: previousControllerView)
            } else if let trailingView {
                container.addSubview(view, positioned: .below, relativeTo: trailingView)
            } else {
                container.addSubview(view, positioned: .above, relativeTo: nil)
            }
            previousControllerView = view
        }

        var x:CGFloat = 0;
        var trailingReserved: CGFloat = 0

        for (index, obj) in _controllers.enumerated() {
            if let obj = obj.value {
                guard let proportion = _proportions[obj.internalId], let startSize = _startSize[obj.internalId] else { continue }
                var size:NSSize = NSMakeSize(x, frame.height);
                var _min:CGFloat  = startSize.width;
                _min = proportion.min;
                if(proportion.max == CGFloat.greatestFiniteMagnitude && index != _controllers.count-1) {
                    var m2:CGFloat = 0;
                    for i:Int in index + 1 ..< _controllers.count - index  {
                        let split:ViewController? = _controllers[i].value;
                        if let split = split {
                            let proportion:SplitProportion = _proportions[split.internalId]!;
                            m2+=proportion.min;
                        }
                    }
                    _min = frame.width - x - m2;
                }
                if index < _controllers.count - 1, state != .minimisize {
                    _min = min(_min, frame.width - 350)
                }
                if(index == _controllers.count - 1) {
                    lastPaneAvailableWidth = frame.width - x
                    updateTrailingShown(target: trailingReservedWidth(available: lastPaneAvailableWidth))
                    trailingReserved = trailingShown
                    _min = frame.width - x - trailingReserved;
                }

                size = NSMakeSize(x + _min > frame.width ? (frame.width - x) : _min, frame.height);
                let paneRect = NSMakeRect(x, 0, size.width, size.height)
                let insets = obj.insets

                let isLast = index == _controllers.count - 1
                let rect: NSRect
                if isLast {
                    obj.slotLeadingInset = paneRect.minX
                    obj.slotTrailingInset = trailingReserved
                    rect = NSMakeRect(0, paneRect.minY + insets.top, frame.width, max(0, paneRect.height - insets.top - insets.bottom))
                } else {
                    obj.slotLeadingInset = 0
                    obj.slotTrailingInset = 0
                    rect = NSMakeRect(paneRect.minX + insets.left, paneRect.minY + insets.top, max(0, paneRect.width - insets.left - insets.right), max(0, paneRect.height - insets.top - insets.bottom))
                }

                if(!NSEqualRects(rect, obj.view.frame)) {
                    obj.view.frame = rect;
                }

                x += paneRect.width;
            }
        }

        layoutTrailing(reserved: trailingReserved)

        if state != .none {
            if state == .dual || state == .minimisize {
                if let firstResizable = _controllers.first(where: { entry in
                    guard let c = entry.value else { return false }
                    return !_fixedControllerIds.contains(c.internalId)
                })?.value {
                    minimisizeOverlay.frame = NSMakeRect(firstResizable.view.frame.maxX - 5, 0, 10, frame.height)
                }

            }
        }
    }



    public func needFullsize() {
        self.mustMinimisize = false
        self.isAutoMinimisize = false
        self.state = self.nextLayout
        self.forceNotice = true
        self.needsLayout = true
    }

    public func needMinimisize() {
        self.mustMinimisize = true
        self.isAutoMinimisize = false
        self.state = .minimisize
        self.forceNotice = true
        self.needsLayout = true
    }

    func resize(to point: NSPoint) {
        //NSLog("\(point)")
    }


    func acceptLayout(prop:SplitProportion!) -> Bool {
        return prop != nil && (prop!.min != 0 || prop!.max != 0);
    }
}
