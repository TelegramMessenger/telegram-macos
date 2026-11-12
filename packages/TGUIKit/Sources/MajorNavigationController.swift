import Cocoa
import SwiftSignalKit



open class MajorNavigationController: NavigationViewController {

    public var alwaysAnimate: Bool = false
    private var majorClass:AnyClass
    private var defaultEmpty:ViewController
    private var listeners:[WeakReference<ViewController>] = []

    deinit {
        var bp:Int = 0
        bp += 1
    }

    public init(_ majorClass:AnyClass, _ empty:ViewController, _ window: Window) {
        self.majorClass = majorClass
        self.defaultEmpty = empty
        assert(majorClass is ViewController.Type)

        super.init(empty, window)
    }

    open override func currentControllerDidChange() {
        if let view = view as? DraggingView {
            view.controller = controller
        }
        for listener in listeners {
            listener.value?.navigationWillChangeController()
        }
    }

    open override func viewClass() ->AnyClass {
        return DraggingView.self
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        if let view = view as? DraggingView {
            view.controller = controller
        }
    }

    open override func push(_ controller: ViewController, _ animated: Bool = true, style: ViewControllerStyle? = nil, clearStack: Bool = false) {

        assertOnMainThread()

        if controller.abolishWhenNavigationSame, controller.className == self.controller.className {
            return
        }

        controller.navigationController = self

        var offset: CGFloat = 0
        if let header = header, header.isShown {
            offset += header.height
        }
        if let header = callHeader, header.isShown {
            offset += header.height
        }
        let bounds = self.bounds
        let frame = NSMakeRect(0, offset, bounds.width - slotLeadingInset - slotTrailingInset, bounds.height - offset)
        controller.loadViewIfNeeded(frame)
        self.controller.readyToDetach()
        
        self.controller.ableToNextController(controller, { [weak self] controller, result in
            if result {
                self?.pushDisposable.set((controller.ready.get() |> deliverOnMainQueue |> take(1)).start(next: {[weak self] _ in
                    if let strongSelf = self {

                        let isMajorController = controller.className == NSStringFromClass(strongSelf.majorClass)
                        let shouldClearStack = clearStack || isMajorController
                        let removeAnimateFlag = strongSelf.stackCount == 2 && shouldClearStack && !strongSelf.alwaysAnimate

                        if let index = strongSelf.stack.firstIndex(of: controller) {
                            strongSelf.stack.remove(at: index)
                        }

                        strongSelf.stack.append(controller)

                        let anim = animated && (!shouldClearStack || strongSelf.controller != strongSelf.defaultEmpty) && !removeAnimateFlag

                        let newStyle:ViewControllerStyle
                        if let style = style {
                            newStyle = style
                        } else {
                            newStyle = anim ? .push : .none
                        }

                        

                        if shouldClearStack {
                            let empty = strongSelf.empty
                            let keepSet: Set<ObjectIdentifier> = [ObjectIdentifier(empty), ObjectIdentifier(controller)]
                            let staleControllers = strongSelf.stack.filter { !keepSet.contains(ObjectIdentifier($0)) }
                            strongSelf.stack = [empty, controller]
                            for stale in staleControllers {
                                if stale === strongSelf.controller, newStyle == .none {
                                    strongSelf.discardContainerAfterCommit(for: stale)
                                } else {
                                    strongSelf.discardContainer(for: stale)
                                }
                                stale.didRemovedFromStack()
                            }
                        }
                        
                        strongSelf.show(controller, newStyle)
                    }
                }))
            }
        })


    }


    override open func invokeBack(animated:Bool = true, forceAnimated: Bool = false, animationStyle: ViewControllerStyle = .pop, checkLock: Bool = true) {
        if  !isLocked, let last = stack.last, !checkLock || last.invokeNavigationBack() {
            if stackCount > 1 {
                let ncontroller = stack[stackCount - 2]
                let removeAnimateFlag = ((ncontroller == defaultEmpty || !animated) && !alwaysAnimate) && !forceAnimated
                stack.removeLast()
                last.didRemovedFromStack()
                show(ncontroller, removeAnimateFlag ? .none : animationStyle)
            } else {
                doSomethingOnEmptyBack?()
            }
        }
    }

    open override func back(animated:Bool = true, forceAnimated: Bool = false, animationStyle: ViewControllerStyle = .pop) -> Void {
        self.invokeBack(animated: animated, forceAnimated: forceAnimated, animationStyle: animationStyle, checkLock: true)
    }





    open override var responderPriority: HandlerPriority {
        return empty.responderPriority
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.window?.set(handler: { [weak self] _ in
            if let strongSelf = self {
                return strongSelf.escapeKeyAction()
            }
            return .rejected
        }, with: self, for: .Escape, priority: self.responderPriority)

        self.window?.set(handler: { [weak self] _ in
            if let strongSelf = self {
                return strongSelf.returnKeyAction()
            }
            return .rejected
        }, with: self, for: .Return, priority: self.responderPriority)


        self.window?.set(handler: { [weak self] _ in
            if let strongSelf = self {
                return strongSelf.backKeyAction()
            }
            return .rejected
        }, with: self, for: .LeftArrow, priority: self.responderPriority)

        self.window?.set(handler: { [weak self] _ in
            if let strongSelf = self {
                return strongSelf.nextKeyAction()
            }
            return .rejected
        }, with: self, for: .RightArrow, priority: self.responderPriority)



    }


    open override var canSwipeBack: Bool {
        return self.stackCount > 1
    }



    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.window?.removeAllHandlers(for: self)
        self.window?.removeAllHandlers(for: self.containerView)
    }

    open override func backKeyAction() -> KeyHandlerResult {
        let status:KeyHandlerResult = stackCount > 1 ? .invoked : .rejected
        if isLocked {
            return .invoked
        }
        if let window = window, hasModals(window) {
            return .invokeNext
        }
        let cInvoke = self.controller.backKeyAction()

        if cInvoke == .invokeNext {
            return .invokeNext
        } else if cInvoke == .invoked {
            return .invoked
        }
        self.back()
        return status
    }

    open override func nextKeyAction() -> KeyHandlerResult {
        if isLocked {
            return .invoked
        }
        if let window = window, hasModals(window) {
            return .invokeNext
        }
        return self.controller.nextKeyAction()
    }


    open override func escapeKeyAction() -> KeyHandlerResult {
        let status:KeyHandlerResult = stackCount > 1 ? .invoked : .rejected
        if isLocked {
            return .invoked
        }
        let cInvoke = self.controller.escapeKeyAction()

        if cInvoke == .invokeNext {
            return .invokeNext
        } else if cInvoke == .invoked {
            return .invoked
        }
        self.back()
        return status
    }

    open override func returnKeyAction() -> KeyHandlerResult {
        let status:KeyHandlerResult = .rejected

        let cInvoke = self.controller.returnKeyAction()

        if cInvoke == .invokeNext {
            return .invokeNext
        } else if cInvoke == .invoked {
            return .invoked
        }
        return status
    }

    public func add(listener:WeakReference<ViewController>) -> Void {
        listeners.removeAll(where: { $0.value == nil })
        let index = listeners.firstIndex(where: { (weakView) -> Bool in
            return listener.value == weakView.value
        })
        if index == nil {
            listeners.append(listener)
        }
    }

    public func remove(listener:WeakReference<ViewController>) -> Void {

        let index = listeners.firstIndex(where: { (weakView) -> Bool in
            return listener.value == weakView.value
        })

        if let index = index {
            listeners.remove(at: index)
        }
    }

}
