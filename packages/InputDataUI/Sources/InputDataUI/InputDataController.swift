import ColorPalette
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import ObjcUtils

open class InputDataModalController : ModalViewController {
    private let controller: InputDataController
    private let _modalInteractions: ModalInteractions?
    private let closeHandler: (@escaping()-> Void) -> Void
    private let themeDisposable = MetaDisposable()
    
    private var _stake:[InputDataController] = []
    
    private let isMain: Bool
    public var fixedHeight: CGFloat? = nil
    public var horizontalInset: CGFloat = 0

    public var alwaysActiveHeader: Bool = false
    public var allowsVerticalScrollElasticity: Bool = true

    public init(_ controller: InputDataController, modalInteractions: ModalInteractions? = nil, closeHandler: @escaping(@escaping()-> Void) -> Void = { $0() }, size: NSSize = NSMakeSize(340, 300), presentation: TelegramPresentationTheme = theme, isMain: Bool = true) {
        controller.isModal = true
        self.controller = controller
        self._modalInteractions = modalInteractions
        self.controller._frameRect = NSMakeRect(0, 0, max(size.width, 280), size.height)
        self.controller.prepareAllItems = true
        self.closeHandler = closeHandler
        self.isMain = isMain
        super.init(frame: controller._frameRect)
        
        self.getModalTheme = {
            return .init(text: presentation.colors.text, grayText: presentation.colors.grayText, background: .clear, border: .clear, accent: presentation.colors.accent, grayForeground: presentation.colors.grayBackground, activeBackground: presentation.colors.background, activeBorder: presentation.colors.border)
        }
    }
    
    // Borderless by default: the 1px modal border has no shadow/corner value the morph can match exactly,
    // so it caused sub-pixel shifts/shrinks at the morph seam. Removed for now across all these modals.
    open var _hasBorder: Bool = false
    open override var hasBorder: Bool {
        return _hasBorder
    }
    
    open var getHeaderColor: (()->NSColor)? = nil
    open override var headerBackground: NSColor {
        return getHeaderColor?() ?? super.headerBackground
    }
    open var getHeaderBorderColor: (()->NSColor)? = nil
    open override var headerBorderColor: NSColor {
        return getHeaderBorderColor?() ?? super.headerBackground
    }
    open var getModalTheme: (()->ModalViewController.Theme)? = nil
    open override var modalTheme: ModalViewController.Theme {
        return getModalTheme?() ?? super.modalTheme
    }

    open func push(_ controller: InputDataController, animated: Bool) {
        let previous = self.current
        self._stake.append(controller)
        controller.modal = self.modal
        controller.makeFirstFast = false
        controller.isModal = true
        controller.prepareAllItems = true

        controller.view.frame = NSMakeRect(frame.width, 0, frame.width, self.view.frame.height)
        controller.view.autoresizingMask = [.width, .height]
        self.view.addSubview(controller.view)
        self.updateInsets()

        controller.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScroll(position)
        }))

        let appear: () -> Void = { [weak self, weak controller, weak previous] in
            guard let self, let controller, self.current === controller else {
                return
            }
            let width = self.frame.width
            controller.view.frame = NSMakeRect(0, 0, width, self.view.frame.height)
            if animated {
                controller.view.layer?.animatePosition(from: NSMakePoint(width / 3 * 2, 0), to: NSZeroPoint, duration: 0.35, timingFunction: .spring)
                if let tableView = previous?.tableView {
                    tableView.layer?.animatePosition(from: tableView.frame.origin, to: NSMakePoint(tableView.frame.minX - width / 3, tableView.frame.minY), duration: 0.35, timingFunction: .spring)
                }
            }

            controller.modalTransitionHandler = { [weak self] _ in
                if self?.dynamicSize == true {
                    self?.updateSize(animated)
                }
                self?.updateInsets()
            }

            self.updateSize(animated)
            self.modal?.updateHeader(animated: animated)
            self.updateLocalizationAndTheme(theme: theme)
            self.modal?.updateLocalizationAndTheme(theme: theme)
            self.updateScroll(controller.tableView.scrollPosition().current)

            delay(0.25, closure: { [weak self] in
                self?.updateSize(false)
            })
        }

        _ = (controller.ready.get()
        |> filter { $0 }
        |> take(1)
        |> timeout(0.5, queue: .mainQueue(), alternate: .single(true))
        |> deliverOnMainQueue).start(next: { _ in
            appear()
        })
    }

    open var didPopController: ((InputDataController) -> Void)? = nil

    open func pop(animated: Bool) {
        if !_stake.isEmpty {
            var controller: InputDataController? = _stake.removeLast()
            if let popped = controller {
                self.didPopController?(popped)
            }
            let view = controller!.genericView
            let width = frame.width

            if view.frame.minX >= width {
                view.removeFromSuperview()
                controller = nil
            } else {
                view.frame = NSMakeRect(0, 0, width, self.view.frame.height)
                view.updateLayout(size: view.frame.size, transition: .immediate)

                let transition = animated ? ContainedViewLayoutTransition.animated(duration: 0.35, curve: .spring) : .immediate
                let rect = NSMakeRect(width, 0, width, self.view.frame.height)
                transition.updateFrame(view: view, frame: rect, completion: { [weak view] _ in
                    view?.removeFromSuperview()
                    controller = nil
                })
                view.updateLayout(size: rect.size, transition: transition)

                if animated {
                    let tableView = self.current.tableView
                    tableView.layer?.animatePosition(from: NSMakePoint(tableView.frame.minX - width / 3, tableView.frame.minY), to: tableView.frame.origin, duration: 0.35, timingFunction: .spring)
                }
            }

            self.updateSize(animated)
            self.modal?.updateHeader(animated: animated)
            self.updateLocalizationAndTheme(theme: theme)
            self.modal?.updateLocalizationAndTheme(theme: theme)

            delay(0.25, closure: { [weak self] in
                self?.updateSize(false)
            })

            self.updateScroll(self.controller.tableView.scrollPosition().current)

        }
    }
    
    open var isFullScreenImpl: (()->Bool)? = nil
    
    open override var isFullScreen: Bool {
        return self.isFullScreenImpl?() ?? super.isFullScreen
    }
    open var closableImpl: (()->Bool)? = nil

    open override var closable: Bool {
        return closableImpl?() ?? super.closable
    }
    
    open override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        closeHandler({ [weak self] in
            self?.closeModal()
        })
    }
    open override var shouldCloseAllTheSameModals: Bool {
        return false
    }
    
    open override var isVisualEffectContainer: Bool {
        return true
    }
    
    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        modal?.updateLocalizationAndTheme(theme: theme)
    }
    
    open override var containerBackground: NSColor {
        return controller.getBackgroundColor()
    }
    
    private func closeModal() {
        super.close()
    }
    
    open var current: InputDataController {
        return self._stake.last ?? self.controller
    }
    
    open override var modalHeader: (left: ModalHeaderData?, center: ModalHeaderData?, right: ModalHeaderData?)? {
        if current.defaultBarTitle.isEmpty {
            return nil
        }
        return (left: self.current.leftModalHeader, center: current.centerModalHeader ?? ModalHeaderData(title: current.defaultBarTitle), right: current.rightModalHeader)
    }
    
    
    open override var modalInteractions: ModalInteractions? {
        return _modalInteractions
    }
    
    open override var handleEvents: Bool {
        return true
    }
    
    open override func becomeFirstResponder() -> Bool? {
        return current.becomeFirstResponder()
    }
    
    open override func firstResponder() -> NSResponder? {
        return current.firstResponder()
    }
    
    open override func returnKeyAction() -> KeyHandlerResult {
        let result = current.returnKeyAction()
        return result
    }
    
    open override var hasNextResponder: Bool {
        return current.hasNextResponder
    }
    
    open override func nextResponder() -> NSResponder? {
        return current.nextResponder()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        current.viewWillAppear(animated)
    }
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        current.viewDidAppear(animated)
        current.tableView.notifyScrollHandlers()
    }
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        current.viewWillDisappear(animated)
    }
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        current.viewDidDisappear(animated)
        current.didRemovedFromStack()
    }
    
    open override func escapeKeyAction() -> KeyHandlerResult {
        if self._stake.isEmpty {
            return super.escapeKeyAction()
        } else {
            self.pop(animated: true)
            return .invoked
        }
    }
    
    
    @objc private func rootControllerFrameChanged(_ notification:Notification) {
        viewDidResized(frame.size)
    }
    
    private var first: Bool = true
    open override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        if isMain {
            updateSize(!first)
        }
    }
    
    open var dynamicSizeImpl:(()->Bool)? = nil
    
    override open var dynamicSize: Bool {
        return self.dynamicSizeImpl?() ?? true
    }
    
    open var height: CGFloat {
        let topHeight = current.genericView.topView?.frame.height ?? 0
        let wh = window?.frame.height ?? 0
        return min(min(wh - 100, 700), current.tableView.listHeight + topHeight)
    }
    
    open var fullSizeList: Bool = false
    open var listHeight: CGFloat {
        if fullSizeList {
            return window?.frame.height ?? current.tableView.listHeight
        } else {
            return current.tableView.listHeight
        }
    }
    
    private var reservedHeight: CGFloat {
        return 130 + (modalInteractions?.height ?? 0)
    }

    override open func measure(size: NSSize) {
        let topHeight = current.genericView.topView?.frame.height ?? 0
        let height: CGFloat
        if let fixedHeight = fixedHeight {
            height = min(size.height - reservedHeight, fixedHeight)
        } else {
            height = min(min(size.height - reservedHeight, 900), listHeight + topHeight)
        }
        let minWidth: CGFloat = horizontalInset > 0 ? 280 : 330
        self.modal?.resize(with:NSMakeSize(max(280, min(self.current._frameRect.width, max(size.width - horizontalInset, minWidth))), height), animated: false)
    }

    open func updateSize(_ animated: Bool) {
        if current !== controller, current.view.frame.minX >= frame.width {
            return
        }
        let topHeight = current.genericView.topView?.frame.height ?? 0
        if let contentSize = self.modal?.window.contentView?.frame.size {
            let height: CGFloat
            if let fixedHeight = fixedHeight {
                height = min(contentSize.height - reservedHeight, fixedHeight)
            } else {
                height = min(min(contentSize.height - reservedHeight, 900), listHeight + topHeight)
            }
            let minWidth: CGFloat = horizontalInset > 0 ? 280 : 330
            self.modal?.resize(with:NSMakeSize(max(280, min(self.current._frameRect.width, max(contentSize.width - horizontalInset, minWidth))), height), animated: animated)
        }
    }
    
    open override func viewClass() -> AnyClass {
        fatalError()
    }
    
    open override func loadView() {
        viewDidLoad()
    }
    
    open override var view: NSView {
        if !controller.isLoaded() {
            loadView()
        }
        return controller.view
    }
    
    
    open override func viewDidLoad() {
        controller.loadView()
        super.viewDidLoad()
        
        ready.set(controller.ready.get())
        
        themeDisposable.set(appearanceSignal.start(next: { [weak self] appearance in
            self?.modal?.updateLocalizationAndTheme(theme: appearance.presentation)
            self?.controller.updateLocalizationAndTheme(theme: appearance.presentation)
        }))
        var first = true
        controller.modalTransitionHandler = { [weak self] animated in
            if self?.dynamicSize == true {
                self?.updateSize(animated && (!first || self?.view.superview is InputDataView))
                first = false
            }
        }
        

        
        controller.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScroll(position)
        }))

        updateInsets()

    }
    
    public var hidesInteractionsBottomInset: Bool = false {
        didSet {
            if oldValue != hidesInteractionsBottomInset, controller.isLoaded() {
                updateInsets()
            }
        }
    }

    private func updateInsets() {
        var topInset: CGFloat = 0
        var bottomInset: CGFloat = 0
        if let _ = self.modalHeader {
            topInset = 56
        }
        if !hidesInteractionsBottomInset, let interactions = _modalInteractions, interactions.contentFlowsBehind {
            bottomInset = interactions.height
        }
        controller.tableView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        if current != controller {
            current.tableView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        }
    }
    
    private func updateScroll(_ position: ScrollPosition) {
        let insets = self.current.tableView.contentInsets
        let effectiveHeight = self.current.tableView.frame.height - insets.bottom - insets.top
        if allowsVerticalScrollElasticity && self.current.tableView.documentSize.height > effectiveHeight {
            self.current.tableView.verticalScrollElasticity = .automatic
        } else {
            self.current.tableView.verticalScrollElasticity = .none
        }
        if position.rect.minY - self.current.tableView.frame.height > 0 || alwaysActiveHeader {
            self.modal?.makeHeaderState(state: .active, animated: true)
        } else {
            self.modal?.makeHeaderState(state: .normal, animated: true)
        }
    }
    
    open override func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        if current != controller {
            controller.genericView.change(size: frame.size, animated: transition.isAnimated)
            controller.genericView.change(pos: frame.origin, animated: transition.isAnimated)
            controller.genericView.updateLayout(size: frame.size, transition: transition)
            current.genericView.change(size: frame.size, animated: transition.isAnimated)
            current.genericView.change(pos: NSMakePoint(0, 0), animated: transition.isAnimated)
            current.genericView.updateLayout(size: frame.size, transition: transition)
        } else {
            current.genericView.change(size: frame.size, animated: transition.isAnimated)
            current.genericView.change(pos: frame.origin, animated: transition.isAnimated)
            current.genericView.updateLayout(size: frame.size, transition: transition)
        }
    }
    
    deinit {
        themeDisposable.dispose()
    }
}




public final class InputDataArguments {
    public let select:((InputDataIdentifier, InputDataValue))->Void
    public let dataUpdated:()->Void
    public init(select: @escaping((InputDataIdentifier, InputDataValue))->Void, dataUpdated:@escaping()->Void) {
        self.select = select
        self.dataUpdated = dataUpdated
    }
}

public func prepareInputDataTransition(left:[AppearanceWrapperEntry<InputDataEntry>], right: [AppearanceWrapperEntry<InputDataEntry>], animated: Bool, searchState: TableSearchViewState?, initialSize:NSSize, arguments: InputDataArguments, onMainQueue: Bool, animateEverything: Bool = false, grouping: Bool = true, makeFirstFast: Bool = false) -> Signal<TableUpdateTransition, NoError> {
    return Signal { subscriber in
        
        func makeItem(_ entry: InputDataEntry) -> TableRowItem {
            return entry.item(arguments: arguments, initialSize: initialSize)
        }
        
        let applyQueue = prepareQueue
        
        let cancelled: Atomic<Bool> = Atomic(value: false)
        
        if Thread.isMainThread && makeFirstFast, left.isEmpty {
            var initialIndex:Int = 0
            var height:CGFloat = 0
            var firstInsertion:[(Int, TableRowItem)] = []
            let entries = Array(right)
            
            let index:Int = 0
            
            for i in index ..< entries.count {
                let item = makeItem(entries[i].entry)
                height += item.height
                firstInsertion.append((i, item))
                if initialSize.height < height {
                    break
                }
            }
            initialIndex = firstInsertion.count
            subscriber.putNext(TableUpdateTransition(deleted: [], inserted: firstInsertion, updated: [], state: .none(nil), searchState: searchState))
            
            applyQueue.async {
                if !cancelled.with({ $0 }) {
                    var insertions:[(Int, TableRowItem)] = []
                    
                    for i in initialIndex ..< entries.count {
                        let item:TableRowItem
                        item = makeItem(entries[i].entry)
                        insertions.append((i, item))
                        if cancelled.with({ $0 }) {
                            break
                        }
                    }
                    if !cancelled.with({ $0 }) {
                        subscriber.putNext(TableUpdateTransition(deleted: [], inserted: insertions, updated: [], state: .none(nil), animateVisibleOnly: !animateEverything, searchState: searchState))
                        subscriber.putCompletion()
                    }
                }
            }
        } else {
            let (deleted,inserted,updated) = proccessEntriesWithoutReverse(left, right: right, { entry -> TableRowItem in
                if !cancelled.with({ $0 }) {
                    return makeItem(entry.entry)
                } else {
                    return TableRowItem(.zero)
                }
            })
            if !cancelled.with({ $0 }) {
                subscriber.putNext(TableUpdateTransition(deleted: deleted, inserted: inserted, updated:updated, animated:animated, state: .none(nil), grouping: true, animateVisibleOnly: !animateEverything, searchState: searchState))
                subscriber.putCompletion()
            }
        }
        
        return ActionDisposable {
            _ = cancelled.swap(true)
        }
    } |> runOn(onMainQueue ? .mainQueue() : prepareQueue)
    
}


public enum InputDataReturnResult {
    case `default`
    case nextResponder
    case invokeEvent
    case nothing
}

public enum InputDataDeleteResult {
    case `default`
    case invoked
}

public struct InputDataSignalValue {
    public let entries: [InputDataEntry]
    public let animated: Bool
    public let searchState: TableSearchViewState?
    public let grouping: Bool
    public let animateEverything: Bool
    public init(entries: [InputDataEntry], animated: Bool = true, searchState: TableSearchViewState? = nil, grouping: Bool = true, animateEverything: Bool = false) {
        self.entries = entries
        self.animated = animated
        self.searchState = searchState
        self.grouping = grouping
        self.animateEverything = animateEverything
    }
}

public final class InputDataView : BackgroundView {
    public let tableView: TableView
    var contentBottomInset: CGFloat = 0

    fileprivate var topView: NSView?
    public fileprivate(set) var bottomView: NSView?
    
    fileprivate var willMove: ((NSWindow?)->Void)? = nil
    
    public init(frame frameRect: NSRect, isFlipped: Bool) {
        tableView = TableView(frame: frameRect.size.bounds, isFlipped: isFlipped)
        super.init(frame: frameRect)
        addSubview(tableView)
    }
    
    deinit {
        var bp = 0
        bp += 1
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        tableView.updateLocalizationAndTheme(theme: theme)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    
    public func set(_ topView: NSView?) {
        if let topView = self.topView {
            topView.removeFromSuperview()
        }
        self.topView = topView
        if let topView = topView {
            addSubview(topView)
        }
        self.needsLayout = true
    }

    public func setBottom(_ bottomView: NSView?) {
        if let bottomView = self.bottomView {
            bottomView.removeFromSuperview()
        }
        self.bottomView = bottomView
        if let bottomView = bottomView {
            addSubview(bottomView)
        }
        self.needsLayout = true
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        let topHeight: CGFloat
        if let view = self.topView {
            transition.updateFrame(view: view, frame: NSMakeRect(0, 0, size.width, view.frame.height))
            topHeight = view.frame.height
        } else {
            topHeight = 0
        }
        if let view = self.bottomView {
            transition.updateFrame(view: view, frame: NSMakeRect(0, size.height - contentBottomInset - view.frame.height, size.width, view.frame.height))
        }
        let tableRect = NSMakeRect(0, topHeight, size.width, size.height - topHeight)

//        transition.updateFrame(view: tableView.contentView, frame: tableRect.size.bounds)
        transition.updateFrame(view: tableView, frame: tableRect)
//        transition.updateFrame(view: tableView.documentView!, frame: tableView.documentSize.bounds)

    }
    
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        
        self.willMove?(newWindow)
    }
}


public final class InputDataMediaSearchContext {
    public let searchState:Promise<SearchState> = Promise()
    public let mediaSearchState:ValuePromise<MediaSearchState> = ValuePromise(ignoreRepeated: true)
    public var inSearch: Bool = false

    public init() {
    }
}

extension InputDataController : PeerMediaSearchable {
    public func toggleSearch() {
        guard let context = self.searchContext else {
            return
        }
        context.inSearch = !context.inSearch
        if context.inSearch {
            context.searchState.set(.single(.init(state: .Focus, request: nil)))
        } else {
            context.searchState.set(.single(.init(state: .None, request: nil)))
        }
    }
    
    fileprivate var searchContext: InputDataMediaSearchContext? {
        return self.contextObject as? InputDataMediaSearchContext
    }
    
    public func setSearchValue(_ value: Signal<SearchState, NoError>) {
        self.searchContext?.searchState.set(value)
    }
    
    public func setExternalSearch(_ value: Signal<ExternalSearchMessages?, NoError>, _ loadMore: @escaping () -> Void) {
        
    }
    
    public var mediaSearchValue: Signal<MediaSearchState, NoError> {
        if let context = self.searchContext {
            return context.mediaSearchState.get()
        }
        return .complete()
    }
    
}

public class InputDataController: GenericViewController<InputDataView> {

    private var appliedContainerBottomInset: CGFloat = 0

    public override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        super.updateContainerContentInsets(insets, transition: transition)
        guard isLoaded() else {
            return
        }
        var contentInsets = tableView.contentInsets
        contentInsets.bottom = max(0, contentInsets.bottom - appliedContainerBottomInset) + insets.bottom
        tableView.contentInsets = contentInsets
        tableView.scrollerInsets.bottom = contentInsets.bottom
        appliedContainerBottomInset = insets.bottom
        genericView.contentBottomInset = insets.bottom
        genericView.updateLayout(size: bounds.size, transition: transition)
    }

    fileprivate var modalTransitionHandler:((Bool)->Void)? = nil
    public var prepareAllItems: Bool = false
    
    private let values: Promise<InputDataSignalValue> = Promise()
    private let disposable = MetaDisposable()
    private let appearanceDisposablet = MetaDisposable()
    private let title: String
    public var validateData:([InputDataIdentifier : InputDataValue]) -> InputDataValidation
    public var afterDisappear: ()->Void
    public var updateDatas:([InputDataIdentifier : InputDataValue]) -> InputDataValidation
    public var didLoad:(InputDataController, [InputDataIdentifier : InputDataValue]) -> Void
    private let _removeAfterDisappear: Bool
    private let hasDone: Bool
    public var updateDoneValue:([InputDataIdentifier : InputDataValue])->((InputDoneValue)->Void)->Void
    public var customRightButton:((ViewController)->BarView?)?
    public var updateRightBarView:((BarView)->Void)?
    public var afterTransaction: (InputDataController)->Void
    public var beforeTransaction: (InputDataController)->Void
    public var backInvocation: ([InputDataIdentifier : InputDataValue], @escaping(Bool)->Void)->Void
    public var returnKeyInvocation:(InputDataIdentifier?, NSEvent) -> InputDataReturnResult
    public var deleteKeyInvocation:(InputDataIdentifier?) -> InputDataDeleteResult
    public var tabKeyInvocation:(InputDataIdentifier?) -> InputDataDeleteResult
    public var rightModalHeader: ModalHeaderData? = nil
    public var leftModalHeader: ModalHeaderData? = nil
    public var centerModalHeader: ModalHeaderData? = nil
    public var keyWindowUpdate:(Bool, InputDataController) -> Void = { _, _ in }
    public var hasBackSwipe:()->Bool = { return true }
    public var searchKeyInvocation:() -> InputDataDeleteResult
    public var getBackgroundColor: ()->NSColor
    public let identifier: String
    public var ignoreRightBarHandler: Bool = false

    public var inputLimitReached:(Int)->Void = { _ in }
    public var _externalFirstResponder:(()->NSResponder?)? = nil
    public var _becomeFirstResponder:(()->Bool)?
    public var contextObject: Any?
    public var contextObject_second: Any?
    public var contextObject_third: Any?
    public var didAppear: ((InputDataController)->Void)?
    public var didDisappear: ((InputDataController)->Void)?
    public var didResize: ((InputDataController)->Void)?

    public var _menuItems:()->[ContextMenuItem] = { return [] }


    public var afterViewDidLoad:(()->Void)?
    
    public var makeFirstResponder: Bool = true
    
    public var _abolishWhenNavigationSame: Bool = false

    public var getTitle:(()->String)? = nil
    public var getStatus:(()->String?)? = nil
    public var doneString: ()->String
    
    public var autoInputAction: Bool = false
    
    public var willDisappear:((InputDataController)->Void)? = nil
    public var willAppear:((InputDataController)->Void)? = nil
    
    public var willMove: ((NSWindow?)->Void)? = nil
    
    public var _getCenterBarViewOnce:((ViewController)->TitledBarView)? = nil


    public var makeFirstFast: Bool = true
    
    public let isFlipped: Bool
    fileprivate var isModal: Bool = false
    
    private var ignoreOnAppear: Bool = false
    
    public init(dataSignal:Signal<InputDataSignalValue, NoError>, title: String, validateData:@escaping([InputDataIdentifier : InputDataValue]) -> InputDataValidation = {_ in return .fail(.none)}, updateDatas: @escaping([InputDataIdentifier : InputDataValue]) -> InputDataValidation = {_ in return .fail(.none)}, afterDisappear: @escaping() -> Void = {}, didLoad: @escaping(InputDataController, [InputDataIdentifier : InputDataValue]) -> Void = { _, _ in}, updateDoneValue:@escaping([InputDataIdentifier : InputDataValue])->((InputDoneValue)->Void)->Void  = { _ in return {_ in}}, removeAfterDisappear: Bool = true, hasDone: Bool = true, identifier: String = "", customRightButton: ((ViewController)->BarView?)? = nil, beforeTransaction: @escaping(InputDataController)->Void = { _ in }, afterTransaction: @escaping(InputDataController)->Void = { _ in }, backInvocation: @escaping([InputDataIdentifier : InputDataValue], @escaping(Bool)->Void)->Void = { $1(true) }, returnKeyInvocation: @escaping(InputDataIdentifier?, NSEvent) -> InputDataReturnResult = {_, _ in return .default }, deleteKeyInvocation: @escaping(InputDataIdentifier?) -> InputDataDeleteResult = {_ in return .default }, tabKeyInvocation: @escaping(InputDataIdentifier?) -> InputDataDeleteResult = {_ in return .default }, searchKeyInvocation: @escaping() -> InputDataDeleteResult = { return .default }, getBackgroundColor: @escaping()->NSColor = { theme.colors.listBackground }, doneString: @escaping()->String = { strings().navigationDone }, isFlipped: Bool = true) {
        self.title = title
        self.validateData = validateData
        self.afterDisappear = afterDisappear
        self.updateDatas = updateDatas
        self.doneString = doneString
        self.didLoad = didLoad
        self.identifier = identifier
        self._removeAfterDisappear = removeAfterDisappear
        self.hasDone = hasDone
        self.updateDoneValue = updateDoneValue
        self.customRightButton = customRightButton
        self.afterTransaction = afterTransaction
        self.beforeTransaction = beforeTransaction
        self.backInvocation = backInvocation
        self.returnKeyInvocation = returnKeyInvocation
        self.deleteKeyInvocation = deleteKeyInvocation
        self.tabKeyInvocation = tabKeyInvocation
        self.searchKeyInvocation = searchKeyInvocation
        self.getBackgroundColor = getBackgroundColor
        self.isFlipped = isFlipped
        super.init()
        values.set(dataSignal)
    }
    
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)

        self.genericView.updateLocalizationAndTheme(theme: theme)
        requestUpdateBackBar()
        requestUpdateCenterBar()
        requestUpdateRightBar()
    }
    
    public override func requestUpdateRightBar() {
        super.requestUpdateRightBar()
        self.updateRightBarView?(self.rightBarView)
    }

    public override var defaultBarTitle: String {
        return getTitle?() ?? title
    }
    public override var defaultBarStatus: String? {
        return getStatus?()
    }
    
    
    public override func getRightBarViewOnce() -> BarView {
        return customRightButton?(self) ?? (hasDone ? TextButtonBarView(controller: self, text: doneString(), style: navigationButtonStyle) : super.getRightBarViewOnce())
    }
    
    private var doneView: TextButtonBarView {
        return rightBarView as! TextButtonBarView
    }
    
    public override var responderPriority: HandlerPriority {
        return .medium
    }
    public var tableView: TableView {
        return self.genericView.tableView
    }
    
    public override func menuItems() -> [ContextMenuItem] {
        return _menuItems()
    }
    
    public func fetchData() -> [InputDataIdentifier : InputDataValue] {
        var values:[InputDataIdentifier : InputDataValue] = [:]
        tableView.enumerateItems { item -> Bool in
            if let identifier = (item.stableId.base as? InputDataEntryId)?.identifier {
                if let item = item as? InputDataRowDataValue {
                    values[identifier] = item.value
                }
            }
            return true
        }
        return values
    }
    
    private func findItem(for identifier: InputDataIdentifier) -> TableRowItem? {
        var item: TableRowItem?
        tableView.enumerateItems { current -> Bool in
            if let stableId = current.stableId.base as? InputDataEntryId {
                if  stableId.identifier == identifier {
                    item = current
                }
            }
            return item == nil
        }
        return item
    }
    
    public func makeFirstResponderIfPossible(for identifier: InputDataIdentifier, focusIdentifier: InputDataIdentifier? = nil, scrollDown: Bool = false, scrollIfNeeded: Bool = true) {
        if let item = findItem(for: identifier) {
            _ = window?.makeFirstResponder(findItem(for: identifier)?.view?.firstResponder)
            
            ignoreOnAppear = true
            
            if let focusIdentifier = focusIdentifier {
                if let item = findItem(for: focusIdentifier) {
                    tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0), inset: NSEdgeInsets(), toVisible: true)
                }
            } else if scrollIfNeeded {
                if !scrollDown  {
                    tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0), inset: NSEdgeInsets(), toVisible: true)
                } else {
                    tableView.scroll(to: .down(true))
                }
            }
        }
    }
    
    public func proccessValidation(_ validation: InputDataValidation) {
        var scrollFirstItem: TableRowItem? = nil
        switch validation {
        case let .fail(fail):
            switch fail {
            case let .alert(text):
                if let window = _window {
                    InputDataUIHooks.shared.showAlert(window, text)
                }
            case let .fields(fields):
                for (identifier, action) in fields {
                    switch action {
                    case .shake:
                        let item = findItem(for: identifier)
                        item?.view?.shakeView()
                        if scrollFirstItem == nil {
                            var invoked: Bool = false
                            scrollFirstItem = item
                            if let item = item, !invoked {
                                tableView.scroll(to: .top(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0), inset: NSEdgeInsets(), timingFunction: .linear, toVisible: true)
                                invoked = true
                            }
                        }
                    case let .shakeWithData(data):
                        let item = findItem(for: identifier)
                        item?.view?.shakeViewWithData(data)
                    }
                }
            case let .doSomething(next):
                next { [weak self] validation in
                    self?.proccessValidation(validation)
                }
            default:
                break
            }
        case let .success(behaviour):
            switch behaviour {
            case .navigationBack:
                navigationController?.back()
            case .navigationBackWithPushAnimation:
                 navigationController?.back(animationStyle: .push)
            case let .custom(action):
                action()
            }
        case .none:
            break
        }
    }
    
    public func validateInputValues() {
        self.proccessValidation(self.validateData(self.fetchData()))
    }
    
    public func updateInputValues() {
        self.proccessValidation(self.updateDatas(self.fetchData()))
        self.modalTransitionHandler?(true)
    }
    
    private func validateInput(data: [InputDataIdentifier : InputDataValue]) {
        
        var values:[InputDataIdentifier : Int] = [:]
        tableView.enumerateItems { item -> Bool in
            if let identifier = (item.stableId.base as? InputDataEntryId)?.identifier {
                if let item = item as? InputDataRowItem {
                    if let data = data[identifier] {
                        let length = (data.stringValue?.length ?? 0)
                        if item.limit < length {
                            values[identifier] = length - Int(item.limit)
                        }
                    }
                }
            }
            return true
        }
        if !values.isEmpty {
            for (key, _) in values {
                let item = findItem(for: key)
                item?.view?.shakeView()
            }
            let first = values.first!.value
            self.inputLimitReached(first)
        } else {
            proccessValidation(self.validateData(data))
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        if !isModal, bar.height > 0 {
            genericView.tableView.contentInsets = NavigationBarView.contentTopInset
        }
        updateContainerContentInsets(containerContentInsets, transition: .immediate)
        
        
        self.afterViewDidLoad?()
        
        self.genericView.willMove = { [weak self] window in
            self?.willMove?(window)
        }
        
        genericView.tableView.getBackgroundColor = self.getBackgroundColor
        
        let makeFirstFast = self.makeFirstFast
        
        appearanceDisposablet.set(appearanceSignal.start(next: { [weak self] _ in
            self?.updateLocalizationAndTheme(theme: theme)
        }))
        
        let arguments = InputDataArguments(select: { [weak self] (identifier, value) in
            guard let `self` = self else {return}
            self.validateInput(data: [identifier : value])
        }, dataUpdated: { [weak self] in
            guard let `self` = self else {return}
            self.proccessValidation(self.updateDatas(self.fetchData()))
        })
        
        self.rightBarView.set(handler:{ [weak self] _ in
            guard let `self` = self else {return}
            if !self.ignoreRightBarHandler {
                self.validateInput(data: self.fetchData())
            }
        }, for: .Click)
        
        let previous: Atomic<[AppearanceWrapperEntry<InputDataEntry>]> = Atomic(value: [])
        let initialSize = self.atomicSize
        
        let onMainQueue: Atomic<Bool> = Atomic(value: !prepareAllItems)
        
        let signal: Signal<TableUpdateTransition, NoError> = combineLatest(queue: .mainQueue(), appearanceSignal, values.get()) |> mapToQueue { appearance, state in
            let entries = state.entries.map({AppearanceWrapperEntry(entry: $0, appearance: appearance)})
            return prepareInputDataTransition(left: previous.swap(entries), right: entries, animated: state.animated, searchState: state.searchState, initialSize: initialSize.modify{$0}, arguments: arguments, onMainQueue: onMainQueue.swap(false), animateEverything: state.animateEverything, grouping: state.grouping, makeFirstFast: makeFirstFast)
        } |> deliverOnMainQueue |> afterDisposed {
            previous.swap([])
        }
        
        disposable.set(signal.start(next: { [weak self] transition in
            guard let `self` = self else {return}
            self.beforeTransaction(self)
            self.tableView.merge(with: transition)
            
            
            let result = self.updateDoneValue(self.fetchData())
            result { [weak self] value in
                guard let `self` = self else {return}
                switch value {
                case let .disabled(text):
                    self.doneView.isHidden = false
                    self.doneView.isLoading = false
                    self.doneView.isEnabled = false
                    self.doneView.set(text: text, for: .Normal)
                case let .enabled(text):
                    self.doneView.isHidden = false
                    self.doneView.isLoading = false
                    self.doneView.isEnabled = true
                    self.doneView.set(text: text, for: .Normal)
                case .loading:
                    self.doneView.isHidden = false
                    self.doneView.isLoading = true
                case .invisible:
                    self.doneView.isHidden = true
                }
                
            }
            
            self.afterTransaction(self)
            self.modalTransitionHandler?(transition.animated)
            
            
            let wasReady: Bool = self.didSetReady
            self.readyOnce()
            if !wasReady {
                self.didLoad(self, self.fetchData())
            }
        }))
    }
    
    public override func returnKeyAction() -> KeyHandlerResult {
        if let event = NSApp.currentEvent {
            switch returnKeyInvocation(self.currentFirstResponderIdentifier, event) {
            case .default:
                if event.type != .keyDown || InputDataUIHooks.shared.checkSendingAbility(event) {
                    self.validateInput(data: self.fetchData())
                } else {
                    
                    let containsString = fetchData().compactMap {
                        $0.value.stringValue
                    }
                    if event.type == .keyDown, containsString.isEmpty || autoInputAction {
                        self.validateInput(data: self.fetchData())
                    } else {
                        return .invokeNext
                    }
                }
                return .invoked
            case .nextResponder:
                _ = window?.makeFirstResponder(self.nextResponder())
                return .invoked
            case .nothing:
                return .invoked
            case .invokeEvent:
                return .invokeNext
            }
        }
        return .invokeNext
    }
    
    public func jumpNext() {
        if hasNextResponder {
            _ = window?.makeFirstResponder(self.nextResponder())
        }
    }
    
    public override func becomeFirstResponder() -> Bool? {
        if let value = _becomeFirstResponder?() {
            return value
        }
        return true
    }
    
    public override var canBecomeResponder: Bool {
        return true
    }
    
    public override func didRemovedFromStack() {
        super.didRemovedFromStack()
        afterDisappear()
    }
    private var firstTake: Bool = true
    
    public override func firstResponder() -> NSResponder? {
        
        if let responder = _externalFirstResponder?() {
            return responder
        }
        let responder = window?.firstResponder as? NSView
        
        var responderInController: Bool = false
        var superview = responder?.superview
        while superview != nil {
            if superview == self.genericView {
                responderInController = true
                break
            } else {
                superview = superview?.superview
            }
        }
        
        if self.window?.firstResponder == self.window || self.window?.firstResponder == tableView.documentView || !responderInController {
            var first: NSResponder? = nil
            tableView.enumerateViews { view -> Bool in
                first = view.firstResponder
                if first != nil, self.firstTake {
                    if let item = view.item as? InputDataRowDataValue {
                        switch item.value {
                        case let .string(value):
                            let value = value ?? ""
                            if !value.isEmpty {
                                return true
                            }
                        default:
                            break
                        }
                    }
                }
                return first == nil
            }
            self.firstTake = false
            return first
        }
        return window?.firstResponder
    }

    public override func backSettings() -> (String, CGImage?) {
        
        return super.backSettings()
    }
    
    public override var enableBack: Bool {
        return true
    }
   // private var canInvokeBack: Bool = false
    public override func invokeNavigationBack() -> Bool {
       return true
    }
    
    public override func executeReturn() {
        backInvocation(fetchData(), { [weak self] result in
            if result {
                self?.navigationController?.back()
            }
        })
    }
    
    public override func getLeftBarViewOnce() -> BarView {
        if let navigation = navigationController {
            return navigation.empty === self ? BarView(controller: self) : super.getLeftBarViewOnce()
        }
        return BarView(controller: self)
    }
    
    public override var hasNextResponder: Bool {
        return true
    }
    
    public override var abolishWhenNavigationSame: Bool {
        return _abolishWhenNavigationSame
    }
    
    public override func backKeyAction() -> KeyHandlerResult {
        return .invokeNext
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.didDisappear?(self)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        if makeFirstResponder, ignoreOnAppear {
            _ = self.window?.makeFirstResponder(firstResponder())
        }
        super.viewDidAppear(animated)
        
        didAppear?(self)
        
        window?.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            
            let index = self.tableView.row(at: self.tableView.documentView!.convert(event.locationInWindow, from: nil))
            
            if index > -1, let view = self.tableView.item(at: index).view {
                if view.mouseInsideField {
                    if self.window?.firstResponder != view.firstResponder {
                        _ = self.window?.makeFirstResponder(view.firstResponder)
                        return .invoked
                    }
                }
            }
            
            return .invokeNext
        }, with: self, for: .leftMouseUp, priority: self.responderPriority)
        
        
        window?.set(handler: { [weak self] _ in
            guard let `self` = self else {return .rejected}
            
            switch self.deleteKeyInvocation(self.currentFirstResponderIdentifier) {
            case .default:
                return .rejected
            case .invoked:
                return .invoked
            }
            
        }, with: self, for: .Delete, priority: self.responderPriority, modifierFlags: nil)
        
        
        window?.set(handler: { [weak self] _ in
            guard let `self` = self else {return .rejected}
            
            switch self.searchKeyInvocation() {
            case .default:
                return .rejected
            case .invoked:
                return .invoked
            }
            
        }, with: self, for: .F, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            InputDataTextFormattingAction.bold.apply(to: self?.findReponsderView)
            return .invoked
        }, with: self, for: .B, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            InputDataTextFormattingAction.link.apply(to: self?.findReponsderView)
            return .invoked
        }, with: self, for: .U, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            InputDataTextFormattingAction.italic.apply(to: self?.findReponsderView)
            return .invoked
        }, with: self, for: .I, priority: self.responderPriority, modifierFlags: [.command])
        
        
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            InputDataTextFormattingAction.monospace.apply(to: self?.findReponsderView)
            return .invoked
        }, with: self, for: .K, priority: responderPriority, modifierFlags: [.command, .shift])
        
    }
    
    
    
    public var findReponsderView: TableRowView? {
        if let view = self.firstResponder() as? NSView {
            var superview: NSView? = view
            while superview != nil {
                if let current = superview as? TableRowView {
                    return current
                } else {
                    superview = superview?.superview
                }
            }
        }
        return nil
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
        willDisappear?(self)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        willAppear?(self)
    }
    
    
    public var currentFirstResponderIdentifier: InputDataIdentifier? {
        var identifier: InputDataIdentifier? = nil
        
        tableView.enumerateViews { view -> Bool in
            if view.hasFirstResponder() {
                if view.firstResponder == view.window?.firstResponder {
                    identifier = (view.item?.stableId.base as? InputDataEntryId)?.identifier
                }
                
            }
            return identifier == nil
        }
        return identifier
    }
    
    public override var supportSwipes: Bool {
        let horizontal = ObjcUtils.findElements(byClass: "TGUIKit.HorizontalTableView", in: genericView.tableView).first as? HorizontalTableView
        if let horizontal = horizontal {
            return !horizontal._mouseInside()
        }
        return self.hasBackSwipe()
    }
    
    public override func nextResponder() -> NSResponder? {
        var next: NSResponder?
        let current = self.window?.firstResponder
        

        
        var selectNext: Bool = false
        
        var first: NSResponder? = nil

        
        tableView.enumerateViews { view -> Bool in
            if view.hasFirstResponder() {
                first = view.firstResponder
            }
            return first == nil
        }
        
        tableView.enumerateViews { view -> Bool in
            if view.hasFirstResponder() {
                if selectNext {
                    next = view.firstResponder
                } else if view.firstResponder == current || view.firstResponder == (current as? NSView)?.superview?.superview {
                    if let nextInner = view.nextResponder() {
                        next = nextInner
                        return false
                    }
                    selectNext = true
                    return true
                }
            }
            return next == nil
        }
        
        
        return next ?? first
    }
    
    public override var removeAfterDisapper: Bool {
        return _removeAfterDisappear
    }
    
    public override func windowDidBecomeKey() {
        self.keyWindowUpdate(true, self)
    }
   
    public override func windowDidResignKey() {
        self.keyWindowUpdate(false, self)
    }
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        self.didResize?(self)
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        self.executeReturn()
        return .invoked
    }

    deinit {
        disposable.dispose()
        appearanceDisposablet.dispose()
    }
    
    public override func initializer() -> InputDataView {
        return InputDataView(frame: initializationRect, isFlipped: isFlipped)
    }
    
    public override func getCenterBarViewOnce() -> TitledBarView {
        return _getCenterBarViewOnce?(self) ?? super.getCenterBarViewOnce()
    }
    
}
