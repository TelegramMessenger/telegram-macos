import Cocoa
import SwiftSignalKit
import AVFoundation
import AppKit

public enum TableSeparator {
    case bottom;
    case top;
    case right;
    case left;
    case none;
}

struct RevealAction {
    
    
}

private let duration: Double = 0.2

public class RowAnimateView: View {
    public var stableId:AnyHashable?
}

public final class RevealTableItemController : ViewController  {
    public let item: TableRowItem
    public init(item: TableRowItem)  {
        self.item = item
        super.init()
    }
}

public protocol RevealTableView {
    var additionalRevealDelta: CGFloat { get }
    var containerX: CGFloat { get }
    var rightRevealWidth: CGFloat { get }
    var leftRevealWidth: CGFloat { get }
    var endRevealState:SwipeDirection? { get set }
    
    var width: CGFloat { get }
    
    func initRevealState()
    
    func moveReveal(delta: CGFloat)
    func completeReveal(direction: SwipeDirection)
}

public enum TableBackgroundMode: Equatable {
    case plain
    case color(color: NSColor)
    case gradient(colors: [NSColor], rotation: Int32?)
    case background(image: NSImage, intensity: Int32?, colors: [NSColor]?, rotation: Int32?, metadata: SVG_SlotsMetadata?)
    case tiled(image: NSImage)
    public var hasWallpaper: Bool {
        switch self {
        case .plain:
            return false
        case .color:
            return false
        default:
            return true
        }
    }
}

public class TableResortController {
    fileprivate let startTimeout: Double
    public var completeDelay: Double = 0.4
    public fileprivate(set) var resortRow: Int?
    internal fileprivate(set) var resortView: TableRowView? {
        didSet {
            if resortView == nil {
                oldValue?.isResorting = false
            } else {
                resortView?.isResorting = true
            }
        }
    }
    fileprivate var startLocation: NSPoint = NSZeroPoint
    fileprivate var startRowLocation: NSPoint = NSZeroPoint
    
    public fileprivate(set) var currentHoleIndex: Int?
    fileprivate var prevHoleIndex: Int?
    
    public var resortRange: NSRange
    fileprivate let start:(Int)->Void
    fileprivate let resort:(Int)->Void
    fileprivate let complete:(Int, Int)->Void
    fileprivate let updateItems:(TableRowView?, [TableRowItem])->Void
    public init(resortRange: NSRange, startTimeout: Double = 0.3, start:@escaping(Int)->Void, resort:@escaping(Int)->Void, complete:@escaping(Int, Int)->Void, updateItems:@escaping(TableRowView?, [TableRowItem])->Void = { _, _ in }) {
        self.resortRange = resortRange
        self.startTimeout = startTimeout
        self.start = start
        self.resort = resort
        self.complete = complete
        self.updateItems = updateItems
    }
    
    func clear() {
        resortView = nil
        resortRow = nil
        startLocation = NSZeroPoint
        startRowLocation = NSZeroPoint
    }
    
    var isResorting: Bool {
        return resortView != nil
    }
    
    func canResort(_ row: Int) -> Bool {
        return resortRange.indexIn(row)
    }
}



public class UpdateTransition<T> {
    public let inserted:[(Int,T)]
    public let updated:[(Int,T)]
    public let deleted:[Int]
    public let animateVisibleOnly: Bool
    public init(deleted:[Int], inserted:[(Int,T)], updated:[(Int,T)], animateVisibleOnly: Bool = true) {
        self.inserted = inserted
        self.updated = updated
        self.deleted = deleted
        self.animateVisibleOnly = animateVisibleOnly
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    public var isEmpty:Bool {
        return inserted.isEmpty && updated.isEmpty && deleted.isEmpty
    }
    
    public var description: String {
        return "inserted: \(inserted.count), updated:\(updated.count), deleted:\(deleted.count)"
    }
}
public struct TableSearchVisibleData {
    let cancelImage: CGImage?
    let cancel:()->Void
    let updateState: (SearchState?)->Void
    public init(cancelImage: CGImage? = nil, cancel: @escaping()->Void, updateState: @escaping(SearchState?)->Void) {
        self.cancelImage = cancelImage
        self.cancel = cancel
        self.updateState = updateState
    }
}

public enum TableSearchViewState : Equatable {
    case none((SearchState?)->Void)
    case visible(TableSearchVisibleData)
    
    public static func ==(lhs: TableSearchViewState, rhs: TableSearchViewState) -> Bool {
        switch lhs {
        case .none:
            if case .none = rhs {
                return true
            } else {
                return false
            }
        case .visible:
            if case .visible = rhs {
                return true
            } else {
                return false
            }
        }
    }
}

public class TableUpdateTransition : UpdateTransition<TableRowItem> {
    public let state:TableScrollState
    public let animated:Bool
    public let grouping:Bool
    public let searchState: TableSearchViewState?
    public let isPartOfTransition: Bool
    public let isOnMainQueue: Bool
    fileprivate let uniqueId = arc4random64()
    public let groupInOne: Bool
    public init(deleted:[Int], inserted:[(Int,TableRowItem)], updated:[(Int,TableRowItem)], animated:Bool = false, state:TableScrollState = .none(nil), grouping:Bool = true, animateVisibleOnly: Bool = false, searchState: TableSearchViewState? = nil, isPartOfTransition: Bool = false, groupInOne: Bool = false) {
        self.animated = animated
        self.state = state
        self.grouping = grouping
        self.searchState = searchState
        self.isPartOfTransition = isPartOfTransition
        self.isOnMainQueue = Queue.mainQueue().isCurrent()
        self.groupInOne = groupInOne
        super.init(deleted: deleted, inserted: inserted, updated: updated, animateVisibleOnly: animateVisibleOnly)
    }
    public override var description: String {
        return "inserted: \(inserted.count), updated:\(updated.count), deleted:\(deleted.count), state: \(state), animated: \(animated)"
    }
    
    public func withUpdatedState(_ state: TableScrollState) -> TableUpdateTransition {
        return .init(deleted: self.deleted, inserted: self.inserted, updated: self.updated, animated: self.animated, state: state, grouping: self.grouping, animateVisibleOnly: self.animateVisibleOnly, searchState: self.searchState)
    }
    
    public static var Empty: TableUpdateTransition {
        return .init(deleted: [], inserted: [], updated: [])
    }
    deinit {
        var bp:Int = 0
        bp += 1
    }
}

public final class TableEntriesTransition<T> : TableUpdateTransition {
    public let entries:T
    public init(deleted:[Int], inserted:[(Int,TableRowItem)], updated:[(Int,TableRowItem)], entries:T, animated:Bool = false, state:TableScrollState = .none(nil), grouping:Bool = true) {
        self.entries = entries
        super.init(deleted: deleted, inserted: inserted, updated: updated, animated:animated, state: state, grouping:grouping)
    }
}

public protocol TableViewDelegate : AnyObject {
    
    func selectionDidChange(row:Int, item:TableRowItem, byClick:Bool, isNew:Bool) -> Void;
    func selectionWillChange(row:Int, item:TableRowItem, byClick:Bool) -> Bool;
    func isSelectable(row:Int, item:TableRowItem) -> Bool;
    
    func findGroupStableId(for stableId: AnyHashable) -> AnyHashable?
    
    func longSelect(row:Int, item:TableRowItem) -> Void
}

public extension TableViewDelegate {
    func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }
    func longSelect(row:Int, item:TableRowItem) -> Void {
        
    }
}

public enum TableSavingSide : Equatable {
    case lower
    case upper
    case aroundIndex(AnyHashable)
}

public func ==(lhs: TableSavingSide, rhs: TableSavingSide) -> Bool {
    switch lhs {
    case .lower:
        if case .lower = rhs {
            return true
        } else {
            return false
        }
    case .upper:
        if case .upper = rhs {
            return true
        } else {
            return false
        }
    case let .aroundIndex(id):
        if case .aroundIndex(id) = rhs {
            return true
        } else {
            return false
        }
    }
}

public struct TableScrollFocus : Equatable {
    public static func == (lhs: TableScrollFocus, rhs: TableScrollFocus) -> Bool {
        return lhs.focus == rhs.focus
    }
    let focus:Bool
    let string: String?
    let range: NSRange?
    let innerId: AnyHashable?
    let action:((NSView)->Void)?
    public var isWholeRow: Bool {
        return innerId == nil && string == nil
    }
    public init(focus: Bool, string: String? = nil, range: NSRange? = nil, innerId: AnyHashable? = nil, action: ((NSView)->Void)? = nil) {
        self.focus = focus
        self.action = action
        self.string = string
        self.range = range
        self.innerId = innerId
    }
    
    
}

public enum TableScrollState :Equatable {
    case top(id: AnyHashable, innerId: AnyHashable?, animated: Bool, focus: TableScrollFocus, inset: CGFloat); // stableId, animated, focus, inset
    case bottom(id: AnyHashable, innerId: AnyHashable?, animated: Bool, focus: TableScrollFocus, inset: CGFloat); //  stableId, animated, focus, inset
    case center(id: AnyHashable, innerId: AnyHashable?, animated: Bool, focus: TableScrollFocus, inset: CGFloat); //  stableId, animated, focus, inset
    case saveVisible(TableSavingSide, Bool)
    case none(TableAnimationInterface?);
    case down(Bool);
    case up(Bool);
    case upOffset(Bool, CGFloat);
    case animate
    
    public static var CenterEmpty: TableScrollState {
        return .center(id: 0, innerId: nil, animated: true, focus: .init(focus: true), inset: 0)
    }
    public static func CenterActionEmpty(_ f:@escaping(NSView)->Void) -> TableScrollState {
        return .center(id: 0, innerId: nil, animated: true, focus: .init(focus: true, action: f), inset: 0)
    }
}

public extension TableScrollState {
    
    func swap(to stableId:AnyHashable, innerId: AnyHashable? = nil) -> TableScrollState {
        switch self {
        case let .top(_, _, animated, focus, inset):
            return .top(id: stableId, innerId: innerId, animated: animated, focus: focus, inset: inset)
        case let .bottom(_, _, animated, focus, inset):
            return .bottom(id: stableId, innerId: innerId, animated: animated, focus: focus, inset: inset)
        case let .center(_, _, animated, focus, inset):
            return .center(id: stableId, innerId: innerId, animated: animated, focus: focus, inset: inset)
        default:
            return self
        }
    }
    
    func focus(action: @escaping(NSView)->Void) -> TableScrollState {
        switch self {
        case let .top(id, innerId, animated, focus, inset):
            return .top(id: id, innerId: innerId, animated: animated, focus: .init(focus: focus.focus, string: focus.string, range: focus.range, innerId: focus.innerId, action: action), inset: inset)
        case let .bottom(id, innerId, animated, focus, inset):
            return .bottom(id: id, innerId: innerId, animated: animated, focus: .init(focus: focus.focus, string: focus.string, range: focus.range, innerId: focus.innerId, action: action), inset: inset)
        case let .center(id, innerId, animated, focus, inset):
            return .center(id: id, innerId: innerId, animated: animated, focus: .init(focus: focus.focus, string: focus.string, range: focus.range, innerId: focus.innerId, action: action), inset: inset)
        default:
            return self
        }
    }
    
    var action: ((NSView)->Void)? {
        switch self {
        case let .top(_, _, _, focus, _):
            return focus.action
        case let .bottom(_, _, _, focus, _):
            return focus.action
        case let .center(_, _, _, focus, _):
            return focus.action
        default:
            return nil
        }
    }
    
    func text(string: String?, range: NSRange? = nil, innerId _innerId: AnyHashable?) -> TableScrollState {
        switch self {
        case let .top(stableId, innerId, animated, focus, inset):
            return .top(id: stableId, innerId: innerId, animated: animated, focus: .init(focus: focus.focus, string: string, range: range, innerId: _innerId, action: focus.action), inset: inset)
        case let .bottom(stableId, innerId, animated, focus, inset):
            return .bottom(id: stableId, innerId: innerId, animated: animated, focus: .init(focus: focus.focus, string: string, range: range, innerId: _innerId, action: focus.action), inset: inset)
        case let .center(stableId, innerId, animated, focus, inset):
            return .center(id: stableId, innerId: innerId, animated: animated, focus: .init(focus: focus.focus, string: string, range: range, innerId: _innerId, action: focus.action), inset: inset)
        default:
            return self
        }
    }
    
    func offset(_ inset: CGFloat) -> TableScrollState {
        switch self {
        case let .top(stableId, innerId, animated, focus, v):
            return .top(id: stableId, innerId: innerId, animated: animated, focus: focus, inset: v + inset)
        case let .bottom(stableId, innerId, animated, focus, v):
            return .bottom(id: stableId, innerId: innerId, animated: animated, focus: focus, inset: v + inset)
        case let .center(stableId, innerId, animated, focus, v):
            return .center(id: stableId, innerId: innerId, animated: animated, focus: focus, inset: v + inset)
        default:
            return self
        }
    }
    
    var isNone: Bool {
        switch self {
        case let .none(animation):
            return animation != nil
        case .animate:
            return true
        case let .saveVisible(_, value):
            return value
        default:
            return false
        }
    }
    
    var animated: Bool {
        switch self {
        case let .top(_, _, animated, _, _):
            return animated
        case let .bottom(_, _, animated, _, _):
            return animated
        case let .center(_, _, animated, _, _):
            return animated
        case .down(let animated):
            return animated
        case .up(let animated):
            return animated
        case let .upOffset(animated, _):
            return animated
        case .animate:
            return true
        case let .saveVisible(_, animated):
            return animated
        case .none:
            return true
        }
    }
}


protocol SelectDelegate : AnyObject {
    func selectRow(index:Int) -> Void;
    func longAction(index:Int) -> Void;
}

private final class TableSearchView : View {
    let searchView = SearchView(frame: NSZeroRect)
    private var cancelButton:ImageButton?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(searchView)
        background = presentation.colors.background
        border = [.Bottom]
        searchView.frame = NSMakeRect(10, 10, frame.width - 20, frame.height - 20)
    }
    
    func applySearchResponder() {
        // _ = window?.makeFirstResponder(searchView.input)
        searchView.layout()
        _ = window?.makeFirstResponder(searchView.input)
        searchView.change(state: .Focus, false)
    }
    
    func updateDatas(_ datas: TableSearchVisibleData) {
        if let cancelImage = datas.cancelImage {
            if self.cancelButton == nil {
                self.cancelButton = ImageButton()
                self.addSubview(cancelButton!)
            }
            cancelButton!.removeAllHandlers()
            cancelButton!.set(image: cancelImage, for: .Normal)
            cancelButton!.set(handler: { _ in
                datas.cancel()
            }, for: .Click)
            _ = cancelButton!.sizeToFit()
        } else {
            cancelButton?.removeFromSuperview()
            cancelButton = nil
        }
       
        
        searchView.searchInteractions = SearchInteractions({ state, _ in
            datas.updateState(state)
        }, { state in
            datas.updateState(state)
        })
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        if let cancelButton = self.cancelButton {
            cancelButton.centerY(x: frame.width - 10 - cancelButton.frame.width)
            searchView.frame = NSMakeRect(10, 10, frame.width - cancelButton.frame.width - 30, frame.height - 20)
        } else {
            searchView.frame = NSMakeRect(10, 10, frame.width - 20, frame.height - 20)
        }
    }
    
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TGFlipableTableView : NSTableView, CALayerDelegate {
    
    var bottomInset:CGFloat = 0
    private let longDisposable = MetaDisposable()
    public var flip:Bool = true
    
    public weak var sdelegate:SelectDelegate?
    weak var table:TableView?
    var border:BorderType?
    
    
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundColor = .clear
        self.autoresizesSubviews = false
        usesAlternatingRowBackgroundColors = false
        layerContentsRedrawPolicy = .never
        usesAutomaticRowHeights = false
    }
    
    override func becomeFirstResponder() -> Bool {
        return false
    }
    
    override func rect(ofRow row: Int) -> NSRect {
        return super.rect(ofRow: row)
    }
    override func row(at point: NSPoint) -> Int {
        return super.row(at: point)
    }
    override func rows(in rect: NSRect) -> NSRange {
        return super.rows(in: rect)
    }
    
    var realVisibleRect: NSRect {
        return super.visibleRect
    }
    
    override var visibleRect: NSRect {
        let rect = super.visibleRect
        var result = rect
        if let animatingContentRect = self.table?.clipView.animatingContentRect {
            result = result.union(animatingContentRect)
        }
        if let keep = self.table?.resizeKeepRect {
            result = result.union(keep)
        }
        return result == rect ? rect : result.intersection(self.bounds)
    }
    
    override func isAccessibilityElement() -> Bool {
        return TGUIKitAccessibility.isEnabled
    }
    override func accessibilityParent() -> Any? {
        return TGUIKitAccessibility.parent(of: self, default: { super.accessibilityParent() })
    }
    override func accessibilityRole() -> NSAccessibility.Role? {
        return TGUIKitAccessibility.isEnabled ? .list : super.accessibilityRole()
    }
    override func accessibilityChildren() -> [Any]? {
        return TGUIKitAccessibility.isEnabled ? accessibilityRowElements() : nil
    }
    override func accessibilityRows() -> [any NSAccessibilityRow]? {
        return TGUIKitAccessibility.isEnabled ? accessibilityRowElements().compactMap { $0 as? NSAccessibilityRow } : nil
    }
    override func accessibilityVisibleRows() -> [any NSAccessibilityRow]? {
        return accessibilityRows()
    }
    override func accessibilitySelectedRows() -> [any NSAccessibilityRow]? {
        return []
    }
    override func accessibilityRowCount() -> Int {
        return accessibilityRowViews().count
    }
    override func accessibilityColumns() -> [Any]? {
        return []
    }
    override func accessibilityVisibleColumns() -> [Any]? {
        return []
    }
    override func accessibilitySelectedColumns() -> [Any]? {
        return []
    }
    override func accessibilityColumnCount() -> Int {
        return 0
    }
    override func accessibilityVisibleCells() -> [Any]? {
        return []
    }
    override func accessibilitySelectedCells() -> [Any]? {
        return []
    }
    override func accessibilityCell(forColumn column: Int, row: Int) -> Any? {
        return nil
    }
    override func accessibilityHeader() -> Any? {
        return nil
    }
    override func accessibilityColumnHeaderUIElements() -> [Any]? {
        return []
    }

    private var accessibilityProxies: [AnyHashable: TableRowAccessibilityElement] = [:]
    static let accessibilityRowWindow = 100

    func accessibilityRowElements() -> [Any] {
        guard let table = table, numberOfRows > 0 else {
            return []
        }
        let visible = rows(in: visibleRect)
        let center = visible.location == NSNotFound ? 0 : visible.location
        let lower = max(0, center - TGFlipableTableView.accessibilityRowWindow)
        let upper = min(numberOfRows, table.count, center + max(visible.length, 0) + TGFlipableTableView.accessibilityRowWindow)
        var result: [Any] = []
        var alive: Set<AnyHashable> = []
        guard lower < upper else {
            return []
        }
        for row in lower ..< upper {
            if NSLocationInRange(row, visible), let view = rowView(atRow: row, makeIfNecessary: false) as? TableRowView, !view.isHidden {
                if view.isAccessibilityElement() {
                    result.append(view)
                } else {
                    result.append(contentsOf: NSAccessibility.unignoredChildren(from: [view]))
                }
                continue
            }
            let item = table.item(at: row)
            guard item.accessibilityHasContent, !item.accessibilityIsSpacer else {
                continue
            }
            alive.insert(item.stableId)
            let proxy: TableRowAccessibilityElement
            if let current = accessibilityProxies[item.stableId] {
                proxy = current
            } else {
                proxy = TableRowAccessibilityElement(table: self, item: item)
                accessibilityProxies[item.stableId] = proxy
            }
            proxy.item = item
            result.append(proxy)
        }
        accessibilityProxies = accessibilityProxies.filter { alive.contains($0.key) }
        return result
    }

    func accessibilityRowViews() -> [TableRowView] {
        let range = rows(in: visibleRect)
        guard range.location != NSNotFound, range.length > 0 else {
            return []
        }
        var result: [TableRowView] = []
        for row in range.location ..< range.location + range.length {
            if let view = rowView(atRow: row, makeIfNecessary: false) as? TableRowView, !view.isHidden {
                result.append(view)
            }
        }
        return result
    }
    
    override public static var isCompatibleWithResponsiveScrolling: Bool {
        return true
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var _mouseDownCanMoveWindow: Bool = false
    override var mouseDownCanMoveWindow: Bool {
        return _mouseDownCanMoveWindow
    }
    
    override var isFlipped: Bool {
        return flip
    }
    
//    override func draw(_ dirtyRect: NSRect) {
//
//    }

    // NSTableView draws its background in draw(_:), which makes AppKit keep a
    // tiled bitmap backing store for the whole visible document (1600px tiles,
    // ~10 MB each at 2x). Rows are separate layers and the background is clear,
    // so nothing needs to be drawn here; the updateLayer path skips the store.
    override var wantsUpdateLayer: Bool {
        return true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override var isOpaque: Bool {
        return false
    }

    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point)
    }
    
    var keepsAboveRows: ((NSView) -> Bool)?
    private var isPositioningSubview: Bool = false
    
    override func addSubview(_ view: NSView) {
        if !self.isPositioningSubview, let keepsAboveRows = self.keepsAboveRows, !keepsAboveRows(view), let anchor = self.subviews.first(where: keepsAboveRows) {
            self.isPositioningSubview = true
            super.addSubview(view, positioned: .below, relativeTo: anchor)
            self.isPositioningSubview = false
        } else {
            super.addSubview(view)
        }
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    
    func draw(_ layer: CALayer, in ctx: CGContext) {

        
       
        if let border = border {
            
            ctx.setFillColor(presentation.colors.border.cgColor)
            
            if border.contains(.Top) {
                ctx.fill(NSMakeRect(0, NSHeight(self.frame) - .borderSize, NSWidth(self.frame), .borderSize))
            }
            if border.contains(.Bottom) {
                ctx.fill(NSMakeRect(0, 0, NSWidth(self.frame), .borderSize))
            }
            if border.contains(.Left) {
                ctx.fill(NSMakeRect(0, 0, .borderSize, NSHeight(self.frame)))
            }
            if border.contains(.Right) {
                ctx.fill(NSMakeRect(NSWidth(self.frame) - .borderSize, 0, .borderSize, NSHeight(self.frame)))
            }
            
        }
    }

    private var beforeRange: NSRange = NSMakeRange(NSNotFound, 0)
    private var offsetOfStartItem: NSPoint = .zero
    private var mouseDown: Bool = false
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        
        if let resortController = table?.resortController, beforeRange.length > 0, mouseDown {
            if resortController.resortRange.indexIn(beforeRange.location) {
                let point = self.convert(event.locationInWindow, from: nil)
                let afterRange = self.rows(in: NSMakeRect(point.x, point.y, 1, 1))
                if afterRange != beforeRange {
                    self.table?.startResorting(beforeRange, point.offsetBy(dx: -offsetOfStartItem.x, dy: -offsetOfStartItem.y))
                }
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            mouseDown = true
            let point = self.convert(event.locationInWindow, from: nil)
            let beforeRange = self.rows(in: NSMakeRect(point.x, point.y, 1, 1))
            self.beforeRange = beforeRange
            if beforeRange.length > 0 {
                if let resortController = table?.resortController{
                    if resortController.resortRange.indexIn(beforeRange.location) {
                        self.offsetOfStartItem = point
                    } else if let table = table, !table.alwaysOpenRowsOnMouseUp {
                        sdelegate?.selectRow(index: beforeRange.location)
                    }
                } else if let table = table, !table.alwaysOpenRowsOnMouseUp {
                    sdelegate?.selectRow(index: beforeRange.location)
                }
                
                let signal: Signal<Void, NoError> = .complete() |> delay(0.5, queue: .mainQueue())
                longDisposable.set(signal.start(completed: { [weak self] in
                    guard let `self` = self, let window = self.window else {
                        return
                    }
                    let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    let afterRange = self.rows(in: NSMakeRect(point.x, point.y, 1, 1))
                    
                    if afterRange == beforeRange {
                        self.sdelegate?.longAction(index: afterRange.location)
                    }
                }))
                
            }
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        longDisposable.set(nil)
        let point = self.convert(event.locationInWindow, from: nil)
        let range = self.rows(in: NSMakeRect(point.x, point.y, 1, 1));
        if range.length > 0, let table = table, mouseDown {
            mouseDown = false
            if let controller = self.table?.resortController {
                if !controller.resortRange.indexIn(range.location) {
                    if controller.resortRow == nil, beforeRange.location == range.location && table.alwaysOpenRowsOnMouseUp {
                        sdelegate?.selectRow(index: range.location)
                    }
                    return
                }
                if range.length > 0, beforeRange.location == range.location {
                    sdelegate?.selectRow(index: range.location)
                }
            } else if table.alwaysOpenRowsOnMouseUp, beforeRange.location == range.location {
                sdelegate?.selectRow(index: range.location)
            }
        }
        mouseDown = false
    }
    
    
    deinit {
        longDisposable.dispose()
    }
    
    
    
    var liveWidth:CGFloat = 0
    
    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        liveWidth = frame.width
    }
    
    
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        if liveWidth != frame.width {
            liveWidth = frame.width
            table?.layoutItems()
        }
    }
    
    override func layout() {
        super.layout()
    }
    
    
   

}

public protocol InteractionContentViewProtocol : AnyObject {
    func contentInteractionView(for stableId: AnyHashable, animateIn: Bool) -> NSView?
    func interactionControllerDidFinishAnimation(interactive: Bool, for stableId: AnyHashable)
    func addAccesoryOnCopiedView(for stableId: AnyHashable, view: NSView)
    func videoTimebase(for stableId: AnyHashable) -> CMTimebase?
    func applyTimebase(for stableId: AnyHashable, timebase: CMTimebase?)

}

public class TableScrollListener : NSObject {
    fileprivate let uniqueId:UInt32 = arc4random()
    public var handler:(ScrollPosition)->Void
    fileprivate let dispatchWhenVisibleRangeUpdated: Bool
    fileprivate var first: Bool = true
    fileprivate var dispatchRange: NSRange = NSMakeRange(NSNotFound, 0)
    public init(dispatchWhenVisibleRangeUpdated: Bool = true, _ handler:@escaping(ScrollPosition)->Void) {
        self.dispatchWhenVisibleRangeUpdated = dispatchWhenVisibleRangeUpdated
        self.handler = handler
    }
    
}

public struct TableAutohide {
    public private(set) weak var item: TableRowItem?
    let hideUntilOverscroll: Bool
    let hideHandler:(Bool)->Void
    public init(item: TableRowItem?, hideUntilOverscroll: Bool = false, hideHandler:@escaping(Bool)->Void = { _ in }) {
        self.item = item
        self.hideUntilOverscroll = hideUntilOverscroll
        self.hideHandler = hideHandler
    }
}

open class TableView: ScrollView, NSTableViewDelegate,NSTableViewDataSource,SelectDelegate,InteractionContentViewProtocol, AppearanceViewProtocol {
    
    private var searchView: TableSearchView?
    private var rightBorder: View? = nil
    public var separator:TableSeparator = .none
    
    
    public var getBackgroundColor:()->NSColor = { presentation.colors.background } {
        didSet {
            if super.layer?.backgroundColor != .clear {
                super.layer?.backgroundColor = self.getBackgroundColor().cgColor
            }
            self.needsDisplay = true

        }
    }
    
    public var supplyment: InteractionContentViewProtocol? = nil

    var list:[TableRowItem] = [TableRowItem]() {
        didSet {
            stickRowsVersion &+= 1
            primaryStickRows = nil
            secondaryStickRows = nil
        }
    }
    private var stickRowsVersion: UInt = 0
    private var primaryStickRows: [Int]?
    private var secondaryStickRows: [Int]?

    private func stickRows(_ cls: AnyClass, primary: Bool) -> [Int] {
        if primary, let rows = primaryStickRows {
            return rows
        }
        if !primary, let rows = secondaryStickRows {
            return rows
        }
        var rows: [Int] = []
        for (i, item) in list.enumerated() where item.isKind(of: cls) {
            rows.append(i)
        }
        if primary {
            primaryStickRows = rows
        } else {
            secondaryStickRows = rows
        }
        return rows
    }

    private static func firstRow(_ rows: [Int], atLeast value: Int) -> Int? {
        var lo = 0, hi = rows.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if rows[mid] < value { lo = mid + 1 } else { hi = mid }
        }
        return lo < rows.count ? rows[lo] : nil
    }

    private static func lastRow(_ rows: [Int], atMost value: Int) -> Int? {
        var lo = 0, hi = rows.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if rows[mid] <= value { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? rows[lo - 1] : nil
    }

    private func findStick(_ cls: AnyClass, primary: Bool, range: NSRange, flipped: Bool) -> (TableRowItem?, Int) {
        let rows = stickRows(cls, primary: primary)
        var index:Int = flipped ? range.location : range.location + range.length - 1
        var item: TableRowItem? = nil
        if index >= 0 && index < count {
            if flipped {
                if let s = TableView.lastRow(rows, atMost: index) {
                    item = list[s]
                    index = s
                } else {
                    index = -1
                }
            } else {
                if let s = TableView.firstRow(rows, atLeast: index) {
                    item = list[s]
                    index = s
                } else {
                    index = count
                }
            }
        }
        if item == nil && !flipped {
            index = range.location + range.length
            if index < count {
                if let s = TableView.firstRow(rows, atLeast: index) {
                    item = list[s]
                    index = s + 1
                } else {
                    index = count
                }
            }
        }
        return (item, index)
    }

    private func adjacentStick(_ cls: AnyClass, primary: Bool, from itemIndex: Int, flipped: Bool) -> TableStickItem? {
        let rows = stickRows(cls, primary: primary)
        if !flipped {
            if itemIndex - 1 < 0 {
                return nil
            }
            return TableView.lastRow(rows, atMost: itemIndex - 1).flatMap { list[$0] as? TableStickItem }
        } else {
            return TableView.firstRow(rows, atLeast: itemIndex + 1).flatMap { list[$0] as? TableStickItem }
        }
    }

    public func enumerateExistingItemViews(with callback:(TableRowItem, TableRowView)->Void) {
        if resortController?.resortView != nil {
            for item in list {
                if let view = viewNecessary(at: item.index) {
                    callback(item, view)
                }
            }
            return
        }
        let count = self.count
        var pairs: [(TableRowItem, TableRowView)] = []
        var hasStaleIndex = false
        self.tableView.enumerateAvailableRowViews({ rowView, row in
            if row >= 0 && row < count, let view = rowView as? TableRowView {
                let item = self.list[row]
                if item.index == row {
                    pairs.append((item, view))
                } else {
                    hasStaleIndex = true
                }
            }
        })
        if hasStaleIndex {
            for item in list {
                if let view = viewNecessary(at: item.index) {
                    callback(item, view)
                }
            }
        } else {
            for (item, view) in pairs {
                callback(item, view)
            }
        }
    }

    private func enumerateExistingViews(with callback:(TableRowView)->Void) {
        if resortController?.resortView != nil {
            self.enumerateViews(with: { view in
                callback(view)
                return true
            })
            return
        }
        let count = self.count
        self.tableView.enumerateAvailableRowViews({ rowView, row in
            if row >= 0 && row < count, let view = rowView as? TableRowView {
                callback(view)
            }
        })
    }
    var tableView:TGFlipableTableView
    
    public var allItems:[TableRowItem] {
        return list
    }
    
    public var view: NSTableView {
        return tableView
    }
    
    
    weak public var delegate:TableViewDelegate?
    private var listhash:[AnyHashable:TableRowItem] = [AnyHashable:TableRowItem]();
    
    private let mergePromise:Promise<TableUpdateTransition> = Promise()
    private let mergeDisposable:MetaDisposable = MetaDisposable()
    
    private var unresortedList: [TableRowItem]?
    private var unresortedListCarried: Bool = false

    public var resortController: TableResortController? {
        didSet {
            if oldValue != nil {
//                resortController?.resortView = oldValue.resortView
//                resortController?.resortRow = oldValue.resortRow
//                
//                resortController?.startLocation = oldValue.startLocation
//                resortController?.startRowLocation = oldValue.startRowLocation
//                
//                resortController?.currentHoleIndex = oldValue.currentHoleIndex
//                resortController?.prevHoleIndex = oldValue.prevHoleIndex
            }
          
        }
    }
   
    public var selectedhash:AnyHashable? = nil
    public var highlitedHash:AnyHashable? = nil

    public var isUpdating: Bool {
        return self.updating
    }
    private var updating:Bool = false
    
    private var previousScroll:ScrollPosition?
    public var needUpdateVisibleAfterScroll:Bool = false
    private var scrollHandler:(_ scrollPosition:ScrollPosition) ->Void = {_ in}
    
    private var scrollListeners:[TableScrollListener] = []
    
    public var alwaysOpenRowsOnMouseUp: Bool = true
    
    public var autohide: TableAutohide?
    
    public var emptyChecker: (([TableRowItem]) -> Bool)? = nil
    
    public var updatedItems:(([TableRowItem])->Void)? {
        didSet {
            updatedItems?(self.list)
        }
    }
    
    public var beforeSetupItem:((TableRowView, TableRowItem)->Void)?
    public var afterSetupItem:((TableRowView, TableRowItem)->Void)?
    
    private var nextScrollEventIsAnimated: Bool = false

    public var emptyItem:TableRowItem? {
        didSet {
            emptyItem?.table = self
            updateEmpties()
        }
    }
    private var emptyView:TableRowView?
    
    public func addScroll(listener:TableScrollListener) {
        var found: Bool = false
        for enumerate in scrollListeners {
            if enumerate.uniqueId == listener.uniqueId {
                found = true
                break
            }
        }
        if !found {
            scrollListeners.append(listener)
        }
    }
    
    
    public var bottomInset:CGFloat = 0 {
        didSet {
            tableView.bottomInset = bottomInset
        }
    }
    
    open override func viewDidChangeBackingProperties() {
        
    }
    
    open func updateLocalizationAndTheme(theme: PresentationTheme) {
        if super.layer?.backgroundColor != .clear {
            super.layer?.backgroundColor = self.getBackgroundColor().cgColor
        }
        stickView?.updateColors()
        rightBorder?.backgroundColor = theme.colors.border
        //tableView.background = .clear
      //  super.layer?.backgroundColor = .clear
        self.needsDisplay = true
      //  tableView.needsDisplay = true
      //  clipView.needsDisplay = true
    }
    
    
    public func removeScroll(listener:TableScrollListener) {
        var index:Int = 0
        var found:Bool = false
        for enumerate in scrollListeners {
            if enumerate.uniqueId == listener.uniqueId {
                found = true
                break
            }
            index += 1
        }
        
        if found {
            scrollListeners.remove(at: index)
        }
        
    }
    
    public var count:Int {
        get {
            return self.list.count
        }
    }
    
//    open override func setNeedsDisplay(_ invalidRect: NSRect) {
//
//    }

    open override var isFlipped: Bool {
        return true
    }
    
    public override init(frame frameRect: NSRect) {
        self.tableView = TGFlipableTableView(frame: frameRect.size.bounds)
        self.tableView.wantsLayer = true
        self.tableView.autoresizesSubviews = false
        super.init(frame: frameRect)
        self.autoresizingMask = []
        updateAfterInitialize(isFlipped:true, drawBorder: false)
    }
    
    public init(frame frameRect: NSRect, isFlipped:Bool = true, bottomInset:CGFloat = 0, drawBorder: Bool = false) {
        self.tableView = TGFlipableTableView(frame: frameRect.size.bounds)
        self.tableView.wantsLayer = true
        self.tableView.autoresizesSubviews = false
        super.init(frame: frameRect)
        self.autoresizingMask = []
        updateAfterInitialize(isFlipped: isFlipped, drawBorder: drawBorder)
    }

    public convenience init() {
        self.init(frame: NSZeroRect)
    }
    
    public var border:BorderType? {
        didSet {
            self.clipView.border = border
            self.tableView.border = border
            
            if border == [.Right] {
                if rightBorder == nil {
                    rightBorder = View()
                    rightBorder?.backgroundColor = presentation.colors.border
                    addSubview(rightBorder!)
                    needsLayout = true
                }
            } else {
                rightBorder?.removeFromSuperview()
                rightBorder = nil
            }
        }
    }
    
    open override var backgroundColor: NSColor {
        didSet {
//            documentView?.background = backgroundColor
//            contentView.background = backgroundColor
//            self.clipView.backgroundColor = backgroundColor
//            self.clipView.needsDisplay = true
//            documentView?.needsDisplay = true
        }
    }
    
    public func setIsFlipped(_ flipped: Bool)  {
        self.tableView.flip = flipped
    }
    
    public func updateAfterInitialize(isFlipped:Bool = true, bottomInset:CGFloat = 0, drawBorder: Bool = false) {

//        self.tableView.setFrameSize(NSMakeSize(frame.width, self.tableView.frame.height))
        
        self.tableView.flip = isFlipped
        if #available(macOS 11.0, *) {
            self.tableView.style = .fullWidth
        }
        self.automaticallyAdjustsContentInsets = false
       // tableView.translatesAutoresizingMaskIntoConstraints = false

        clipView.autoresizingMask = []
        clipView.autoresizesSubviews = false
        
        self.tableView.autoresizingMask = []
        self.tableView.rowSizeStyle = .custom

        
        self.clipView.scrollDidComplete = { [weak self] _ in
            self?.enqueueAwaitingIfNeeded()
        }
        
       // self.scrollsDynamically = true
       // self.verticalLineScroll = 0
        //self.verticalScrollElasticity = .none
        self.autoresizesSubviews = false

        self.tableView.table = self
        
        self.bottomInset = bottomInset
        self.tableView.bottomInset = bottomInset
        
        if drawBorder {
            self.clipView.border = BorderType([.Right])
            self.tableView.border = BorderType([.Right])
        }
     
        self.hasVerticalScroller = true;

        self.documentView = self.tableView;
//        self.tableView.autoresizingMask = [.height]
//        self.autoresizingMask = [.width, .height]
        

        
        self.tableView.delegate = self;
        self.tableView.dataSource = self;
        self.tableView.sdelegate = self
        self.tableView.allowsColumnReordering = false
        self.tableView.headerView = nil;
        self.tableView.intercellSpacing = NSMakeSize(0, 0)
        self.tableView.columnAutoresizingStyle = .noColumnAutoresizing
//        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "column"))
//        tableColumn.width = frame.width

//        self.tableView.addTableColumn(tableColumn)
       
        
        mergeDisposable.set(mergePromise.get().start(next: { [weak self] (transition) in
            self?.merge(with: transition)
        }))
        
    }
    
    private func findBackgroundControllerView(view: NSView) -> BackgroundView? {
        if let superview = view.superview {
            for subview in superview.subviews {
                if let subview = subview as? BackgroundView {
                    return subview
                } else {
                    if let superview = subview.superview {
                        if let result = findBackgroundControllerView(view: superview) {
                            return result
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private var findBackgroundControllerView: BackgroundView? {
        return self.findBackgroundControllerView(view: self)
    }
    
    
    
    
    open override func layout() {
        super.layout()
        
        let primaryStickRows = self.primaryStickRows
        let secondaryStickRows = self.secondaryStickRows
        let stickRowsVersion = self.stickRowsVersion
        self.beginTableUpdates()
        let item = TableRowItem(.zero, stableId: arc4random64())
        let _ = self.addItem(item: item)
        self.remove(at: self.count - 1)
        self.endTableUpdates()
        if self.stickRowsVersion == stickRowsVersion &+ 2 {
            if let primaryStickRows {
                self.primaryStickRows = primaryStickRows
            }
            if let secondaryStickRows {
                self.secondaryStickRows = secondaryStickRows
            }
        }
        
        if let emptyView = emptyView, let superview = superview {
            emptyView.frame = bounds
            emptyView.centerX(y: superview.frame.height - emptyView.frame.height)
        }
        if let searchView = searchView {
            searchView.setFrameSize(NSMakeSize(frame.width, searchView.frame.height))
        }
       
        if needsLayouItemsOnNextTransition {
            layoutItems()
        }
        if let rightBorder = rightBorder {
            rightBorder.frame = NSMakeRect(frame.width - .borderSize, 0, .borderSize, frame.height)
        }
        
        if let stickView = stickView {
            stickView.frame = NSMakeRect(stickView.frame.minX, stickView.frame.minY, frame.width, stickView.frame.height)
        }
    }
    
    
    func layoutIfNeeded(with range:NSRange, oldWidth:CGFloat) {
        
        
        let visibleItems = self.visibleItems()
        beginTableUpdates()
        for i in range.min ..< range.max {
            let item = self.item(at: i)
            let before = item.heightValue
            let updated = item.makeSize(frame.width, oldWidth: oldWidth)
            let after = item.heightValue
            if (before != after && updated) || item.instantlyResize || inLiveResize {
                reloadData(row: i, animated: false)
                noteHeightOfRow(i, false)
            }
        }
        endTableUpdates()
        if !tableView.inLiveResize && oldWidth != 0 {
            saveScrollState(visibleItems)
        }
        
        for listener in scrollListeners {
            listener.handler(self.scrollPosition().current)
        }
    }
    
    private var liveScrollStartPosition: NSPoint?
    
    
    public var _scrollWillStartLiveScrolling:(()->Void)?
    public var _scrollDidLiveScrolling:(()->Void)?
    public var _scrollDidEndLiveScrolling:(()->Void)?
    
    public private(set) var liveScrolling: Bool = false

    open func scrollWillStartLiveScrolling() {
        self.clipView.cancelScrolling()
        liveScrollStartPosition = documentOffset
        _scrollWillStartLiveScrolling?()
        liveScrolling = true
    }
    private var liveScrollMaxOffset: CGFloat?
    open func scrollDidLiveScrolling() {
        
        liveScrollMaxOffset = max(liveScrollMaxOffset ?? documentOffset.y, documentOffset.y)
        if documentOffset.y < -10, let liveScrollStartPosition = liveScrollStartPosition, let autohide = self.autohide, let item = autohide.item {
           
            if liveScrollStartPosition.y <= 0 && liveScrollMaxOffset ?? 0 <= item.height / 2 {
                if item.isAutohidden {
                    item.unhideItem(animated: true)
                    autohide.hideHandler(false)
                    liveScrollMaxOffset = nil
                }
            }
        }
        _scrollDidLiveScrolling?()
    }
    
    
    public var updateScrollPoint:((NSPoint)->NSPoint)? = nil
    private var beginPendingTime:CFAbsoluteTime?
    private var dispatchRange: NSRange = NSMakeRange(NSNotFound, 0)
    
    public var scrollDidUpdate: ((ScrollPosition)->Void)? = nil
    
    public var documentSubviewKeptAboveRows: ((NSView) -> Bool)? {
        get {
            return self.tableView.keepsAboveRows
        }
        set {
            self.tableView.keepsAboveRows = newValue
        }
    }

    
    private var scrollUpdateScheduled: Bool = false

    private func updateScroll() {


        self.scrollDidChangedBounds()

        if self.updating == true {
            return
        }
        var isNextCallLocked: Bool {
            if let beginPendingTime = beginPendingTime {
                if CFAbsoluteTimeGetCurrent() - beginPendingTime < 0.05 {
                    return true
                }
            }
            beginPendingTime = CFAbsoluteTimeGetCurrent()
            return false
        }
        
        let reqCount = self.count / 6
        
        self.updateStickAfterScroll(self.nextScrollEventIsAnimated)
        self.nextScrollEventIsAnimated = false
        let scroll = self.scrollPosition(self.visibleRows())
        
        if (!self.updating && !self.clipView.isAnimateScrolling) {
            
            let range = scroll.current.visibleRows
            
            if range.location == NSNotFound {
                return;
            }
            
            if(scroll.current.rect != self.previousScroll?.rect) {

                switch(scroll.current.direction) {
                case .top:
                    if(range.location  <= reqCount) {
                        if !isNextCallLocked {
                            self.scrollHandler(scroll.current)
                        }
                        self.previousScroll = scroll.current
                    }
                case .bottom:
                    if(self.count - (range.location + range.length) <= reqCount) {
                        if !isNextCallLocked {
                            self.scrollHandler(scroll.current)
                        }
                        self.previousScroll = scroll.current
                    }
                case .none:
                    if !isNextCallLocked {
                        self.scrollHandler(scroll.current)
                    }
                    self.previousScroll = scroll.current
                }
            }
            
        }
        
        for listener in self.scrollListeners {
            if !listener.dispatchWhenVisibleRangeUpdated || listener.first || !NSEqualRanges(scroll.current.visibleRows, listener.dispatchRange) {
                listener.handler(scroll.current)
                listener.first = false
                listener.dispatchRange = scroll.current.visibleRows
            }
        }
        
        if self.needUpdateVisibleAfterScroll {
            let range = self.visibleRows()
            for i in range.location ..< range.location + range.length {
                if let view = self.viewNecessary(at: i) {
                    view.updateMouse(animated: false)
                }
            }
        }
    }
    
    open func scrollDidChangedBounds() {
        
        if let autohide = autohide, let item = autohide.item, autohide.hideUntilOverscroll, let _ = liveScrollStartPosition {
            let rect = self.rectOf(item: item)
            
            if !item.isAutohidden, documentOffset.y >= rect.maxY {
                item.hideItem(animated: false, reload: false)
                
                liveScrollStartPosition = nil
                liveScrollMaxOffset = nil
                self.merge(with: TableUpdateTransition(deleted: [item.index], inserted: [(item.index, item)], updated: [], animated: false, state: .saveVisible(.upper, false)))
                
                autohide.hideHandler(true)
            }
        }
        
        self.scrollDidLiveScrolling()
        
        
        var point = self.clipView.bounds.origin
        if let updateScrollPoint = updateScrollPoint {
            point = updateScrollPoint(point)
        }
        if self.scrollDidUpdate != nil {
            let documentRect = contentView.documentRect
            let position = ScrollPosition(NSMakeRect(point.x, point.y, documentRect.width, documentRect.height), .none, NSMakeRange(0, 0))
            self.scrollDidUpdate?(position)
        }

    }
    
    open func scrollDidEndLiveScrolling() {
        liveScrolling = false
        if let autohide = self.autohide {
            if let autohideItem = autohide.item {
                let rect = self.rectOf(item: autohideItem)
                if (documentOffset.y > (rect.minY + (rect.height / 2))) && documentOffset.y < rect.maxY {
//                    scroll(to: .top(id: autohideItem.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: autohideItem.height), completion: { [weak self] _ in
//                        self?.liveScrollStartPosition = nil
//                    })
                } else if documentOffset.y > 0 && documentOffset.y < rect.maxY {
//                    scroll(to: .top(id: autohideItem.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0), completion: { [weak self] _ in
//                        self?.liveScrollStartPosition = nil
//                    })
                } else {
                    liveScrollStartPosition = nil
                }
            } else {
                liveScrollStartPosition = nil
            }
        } else {
            liveScrollStartPosition = nil
        }
        liveScrollMaxOffset = nil
        _scrollDidEndLiveScrolling?()
    }
    
    private var scrollObservers: [NSObjectProtocol] = []
    
    private func removeScrollObservers() {
        for observer in scrollObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        scrollObservers.removeAll()
    }
    
    open override func viewDidMoveToSuperview() {
        removeScrollObservers()
        if superview != nil {
            let clipView = self.contentView
            
            scrollObservers.append(NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: self, queue: nil, using: { [weak self] _ in
                self?.scrollDidEndLiveScrolling()
            }))
            
            scrollObservers.append(NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: nil, using: { [weak self] _ in
                self?.scrollWillStartLiveScrolling()
            }))
            
            scrollObservers.append(NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification, object: self, queue: nil, using: { [weak self] _ in
                self?.scrollDidLiveScrolling()
            }))
            

            scrollObservers.append(NotificationCenter.default.addObserver(forName: NSScrollView.boundsDidChangeNotification, object: clipView, queue: nil, using: { [weak self] _ in
                guard let self = self, self.superview != nil else {
                    return
                }
                // Coalesce a burst of bounds changes (a trackpad fling fires these
                // at up to 120 Hz) into a single `updateScroll` per runloop turn.
                // `updateScroll` reads the clip view's live position at execution
                // time, so the collapsed call still observes the latest offset and
                // never misses the final resting position.
                if self.scrollUpdateScheduled {
                    return
                }
                self.scrollUpdateScheduled = true
                DispatchQueue.main.async {
                    self.scrollUpdateScheduled = false
                    self.updateScroll()
                }
            }))
            
        } else {
           NotificationCenter.default.removeObserver(self)
        }
    }
    
    
    // Primary stick item properties
    private var stickClass:AnyClass? {
        didSet {
            self.stickClassName = self.stickClass.flatMap(NSStringFromClass)
        }
    }
    private var stickClassName: String?
    private var stickView:TableStickView?
    
    private var stickItem:TableStickItem? {
        didSet {
            if stickItem != oldValue {
                if let stickHandler = stickHandler {
                    stickHandler(stickItem)
                }
            }
        }
    }
    private var stickHandler:((TableStickItem?)->Void)?
    private var firstTime: Bool = false
    
    // Secondary stick item properties
    private var secondaryStickClass:AnyClass? {
        didSet {
            self.secondaryStickClassName = self.secondaryStickClass.flatMap(NSStringFromClass)
        }
    }
    private var secondaryStickClassName: String?
    private var secondaryStickView:TableStickView?
    
    private var secondaryStickItem:TableStickItem? {
        didSet {
            if secondaryStickItem != oldValue {
                if let secondaryStickHandler = secondaryStickHandler {
                    secondaryStickHandler(secondaryStickItem)
                }
            }
        }
    }
    private var secondaryStickHandler:((TableStickItem?)->Void)?
    private var secondaryFirstTime: Bool = false
    
    // Primary stick item setup
    public func set(stickClass:AnyClass?, visible: Bool = true, handler:@escaping(TableStickItem?)->Void) {
        self.stickClass = stickClass
        self.primaryStickRows = nil
        self.stickRowsVersion &+= 1
        self.stickHandler = handler
        self.firstTime = true
        if let stickClass = stickClass as? TableStickItem.Type {
            if stickView == nil {
                let stickItem:TableStickItem = stickClass.init(frame.size)
                stickItem.table = self
                self.stickItem = stickItem
                if visible {
                    let vz = stickItem.viewClass() as! TableStickView.Type
                    stickView = vz.init(frame:NSMakeRect(0, 0, NSWidth(self.frame), stickItem.heightValue))
                    stickView!.header = true
                    stickView!.set(item: stickItem, animated: false)
                    stickView!.updateLayout(size: stickView!.frame.size, transition: .immediate)
                }
            }
            
            updateStickAfterScroll(false)
            
        } else {
            stickView?.removeFromSuperview()
            stickView = nil
            stickItem = nil
        }
    }
    
    // Secondary stick item setup
    public func setSecondary(stickClass:AnyClass?, visible: Bool = true, handler:@escaping(TableStickItem?)->Void) {
        self.secondaryStickClass = stickClass
        self.secondaryStickRows = nil
        self.stickRowsVersion &+= 1
        self.secondaryStickHandler = handler
        self.secondaryFirstTime = true
        if let stickClass = stickClass as? TableStickItem.Type {
            if secondaryStickView == nil {
                let stickItem:TableStickItem = stickClass.init(frame.size)
                stickItem.table = self
                self.secondaryStickItem = stickItem
                if visible {
                    let vz = stickItem.viewClass() as! TableStickView.Type
                    secondaryStickView = vz.init(frame:NSMakeRect(0, 0, NSWidth(self.frame), stickItem.heightValue))
                    secondaryStickView!.header = true
                    secondaryStickView!.set(item: stickItem, animated: false)
                    secondaryStickView!.updateLayout(size: secondaryStickView!.frame.size, transition: .immediate)
                }
            }
            
            updateStickAfterScroll(false)
            
        } else {
            secondaryStickView?.removeFromSuperview()
            secondaryStickView = nil
            secondaryStickItem = nil
        }
    }
    
    public func updateStickAfterScroll(_ animated: Bool) -> Void {
        updateSecondaryStickAfterScroll(animated: animated)
        updatePrimaryStickAfterScroll(animated: animated)
    }
    
    private func updatePrimaryStickAfterScroll(animated: Bool) {
        if let stickClass = stickClass, !updating {
            let visibleRect = self.tableView.realVisibleRect

            var secondaryOffset: CGFloat = 0
            if let secondaryStickView = secondaryStickView, !secondaryStickView.isHidden {
                secondaryOffset = secondaryStickView.frame.height
            }


            let range = stickRange(visibleRect, bottomOffset: secondaryOffset)


            let flipped = tableView.isFlipped
            
            let scrollInset = stickScrollInset
            let (item, index) = findStick(stickClass, primary: true, range: range, flipped: flipped)
            let stickClassName = self.stickClassName ?? NSStringFromClass(stickClass)
            
            if let someItem = item as? TableStickItem {
                var currentStick:TableStickItem? = adjacentStick(stickClass, primary: true, from: someItem.index, flipped: flipped)
                
                if someItem.singletonItem {
                    currentStick = someItem
                }
                
                if stickView?.item != item {
                    stickView?.set(item: someItem, animated: animated)
                    stickView?.updateIsVisible(!firstTime, animated: animated)
                }
                
                if let item = stickItem {
                    if let view = (viewNecessary(at: item.index) as? TableStickView) {
                        view.updateIsVisible((!firstTime || !view.header), animated: animated)
                    }
                }
                
                stickItem = currentStick ?? someItem
                
             
                
                stickView?.setFrameSize(frame.width, someItem.heightValue)
                let itemRect:NSRect = someItem.view?.visibleRect ?? NSZeroRect
                
                
                
                if let item = stickItem, item.isKind(of: stickClass), let stickView = stickView {
                    let rect:NSRect = self.rectOf(item: item)
                    let dif:CGFloat
                    if currentStick != nil {
                        dif = min(scrollInset - rect.maxY, item.heightValue)
                    } else {
                        dif = item.heightValue
                    }
                    var yTopOffset:CGFloat
                    if !flipped {
                        yTopOffset = min((scrollInset - rect.maxY - secondaryOffset) - rect.height, 0)
                    } else {
                        yTopOffset = min(-(rect.height + (scrollInset - rect.minY - secondaryOffset)), 0)
                    }
                    if yTopOffset <= -rect.height || item.isFixed {
                        yTopOffset = 0
                    }
                    if scrollInset <= 0, item.singletonItem {
                        yTopOffset = abs(scrollInset)
                    }
                                        
                    let updatedPoint = NSMakePoint(0, yTopOffset + stickTopInset + secondaryOffset)
                    
                    
                    var maybeAnimated: Bool = someItem.index == list.count - 1 && updatedPoint.y == secondaryOffset && stickView.frame.minY == 0
                     
                    if someItem.index == list.count - 1, secondaryOffset == 0 {
                        maybeAnimated = true
                    }
                    
                    do {
                        let maybeIndex: Int?
                        
                        if maybeAnimated {
                            maybeIndex = nil
                        } else {
                            let secondaryViewClassName = secondaryStickView?.className
                            maybeIndex = subviews.firstIndex(where: { $0.className == secondaryViewClassName })
                        }

                        let secondaryClassName = self.secondaryStickClassName
                        let scrollerIndex = maybeIndex ?? subviews.firstIndex(where: { $0 is NSScroller || $0.className == secondaryClassName })
                        
                        let stickViewIndex = subviews.firstIndex(where: { $0.className == stickClassName })
                        if let scrollerIndex = scrollerIndex, stickViewIndex == nil || stickViewIndex! > scrollerIndex {
                            addSubview(stickView, positioned: .below, relativeTo: subviews[scrollerIndex])
                        }
                    }

                    if stickView.frame.origin != updatedPoint {
                        stickView._change(pos: updatedPoint, animated: animated || maybeAnimated)
                    }
                    stickView.header = abs(dif) <= item.heightValue
                    
                    if !firstTime {
                        let rows:[Int] = [tableView.row(at: NSMakePoint(0, min(scrollInset - stickView.frame.height, documentSize.height - stickView.frame.height))), tableView.row(at: NSMakePoint(0, scrollInset))]
                        var applied: Bool = false
                        for row in rows {
                            let row = min(max(0, row), list.count - 1)
                            if let dateItem = self.item(at: row) as? TableStickItem, let view = dateItem.view as? TableStickView, dateItem.className == stickClassName {
                                if documentOffset.y > (documentSize.height - frame.height) && !tableView.isFlipped {
                                    yTopOffset = -1
                                }
                                view.updateIsVisible(yTopOffset < 0 , animated: false)
                                applied = true
                            }
                        }
                        if !applied {
                            let stickViewClassName = stickView.className
                            self.enumerateVisibleViews(with: { view in
                                if stickViewClassName == view.className {
                                    (view as? TableStickView)?.updateIsVisible(true, animated: false)
                                }
                            })
                        }
                        
                    }
                    
                    if previousStickMinY == nil {
                        previousStickMinY = documentOffset.y
                    }
                    
                    if previousStickMinY != documentOffset.y {
                        stickView.isHidden = false
                        previousStickMinY = documentOffset.y
                        if !animated || stickView.layer?.opacity != 0 {
                            stickView.updateIsVisible(true, animated: true)
                            firstTime = false
                        }
                    }
                    if tableView.isFlipped {
                        stickView.isHidden = (documentOffset.y + stickTopInset <= 0 && !item.singletonItem)
                    } else {
                        stickView.isHidden = documentSize.height <= frame.height || documentOffset.y > (documentSize.height - frame.height)
                    }
                    
                    scheduleStickTimeout({ [weak stickView] in
                        if itemRect.height == 0, let stickView = stickView {
                            stickView.updateIsVisible(false, animated: true)
                        }
                    })
                    
                }
                
            } else {
                if index == -1 {
                    if animated, let stickView = self.stickView {
                        stickView._change(pos: NSMakePoint(0, -stickView.frame.height), animated: animated, removeOnCompletion: false, completion: { [weak stickView] _ in
                            stickView?.removeFromSuperview()
                        })
                    } else {
                        stickView?.removeFromSuperview()
                    }
                } else {
                    stickView?.setFrameOrigin(0, 0)
                    stickView?.header = true
                    stickView?.isHidden = true
                }
                
                let stickViewClassName = stickView?.className
                self.enumerateExistingViews(with: { view in
                    if stickViewClassName == view.className {
                        (view as? TableStickView)?.updateIsVisible(true, animated: false)
                    }
                })
            }
        }
    }
    
    private func updateSecondaryStickAfterScroll(animated: Bool) {
        if let secondaryStickClass = secondaryStickClass, !updating {
            let visibleRect = self.tableView.realVisibleRect
            let range = stickRange(visibleRect, bottomOffset: 0)

            let flipped = tableView.isFlipped
            
            let scrollInset = stickScrollInset
            let (item, index) = findStick(secondaryStickClass, primary: false, range: range, flipped: flipped)
            let secondaryClassName = self.secondaryStickClassName ?? NSStringFromClass(secondaryStickClass)
            
            if let someItem = item as? TableStickItem {
                var currentStick:TableStickItem? = adjacentStick(secondaryStickClass, primary: false, from: someItem.index, flipped: flipped)
                
                if someItem.singletonItem {
                    currentStick = someItem
                }
                
                if secondaryStickView?.item != item {
                    secondaryStickView?.set(item: someItem, animated: animated)
                    secondaryStickView?.updateIsVisible(!secondaryFirstTime, animated: animated)
                }
                
                if let item = secondaryStickItem {
                    if let view = (viewNecessary(at: item.index) as? TableStickView) {
                        view.updateIsVisible((!secondaryFirstTime || !view.header), animated: animated)
                    }
                }
                
                secondaryStickItem = currentStick ?? someItem
                
                if let secondaryStickView = secondaryStickView {
                    let scrollerIndex = subviews.firstIndex(where: { $0 is NSScroller })
                    let stickViewIndex = subviews.firstIndex(where: { $0.className == secondaryClassName })
                    if let scrollerIndex = scrollerIndex, stickViewIndex == nil || stickViewIndex! > scrollerIndex {
                        addSubview(secondaryStickView, positioned: .below, relativeTo: subviews[scrollerIndex])
                    }
                }
                
                secondaryStickView?.setFrameSize(frame.width, someItem.heightValue)
                let _:NSRect = someItem.view?.visibleRect ?? NSZeroRect
                
                if let item = secondaryStickItem, item.isKind(of: secondaryStickClass), let secondaryStickView = secondaryStickView {
                    let rect:NSRect = self.rectOf(item: item)
                    let dif:CGFloat
                    if currentStick != nil {
                        dif = min(scrollInset - rect.maxY, item.heightValue)
                    } else {
                        dif = item.heightValue
                    }
                    var yTopOffset:CGFloat
                    if !flipped {
                        yTopOffset = min((scrollInset - rect.maxY) - rect.height, 0)
                    } else {
                        yTopOffset = min(-(rect.height + (scrollInset - rect.minY)), 0)
                    }
                    if yTopOffset <= -rect.height {
                        yTopOffset = 0
                    }
                    if scrollInset <= 0, item.singletonItem {
                        yTopOffset = abs(scrollInset)
                    }
                                        
                    // Position secondary stick view at the top
                    let updatedPoint = NSMakePoint(0, yTopOffset + stickTopInset)
                    if secondaryStickView.frame.origin != updatedPoint {
                        secondaryStickView._change(pos: updatedPoint, animated: animated)
                    }
                    secondaryStickView.header = abs(dif) <= item.heightValue
                    
                    if !secondaryFirstTime {
                        let rows:[Int] = [tableView.row(at: NSMakePoint(0, min(scrollInset - secondaryStickView.frame.height, documentSize.height - secondaryStickView.frame.height))), tableView.row(at: NSMakePoint(0, scrollInset))]
                        var applied: Bool = false
                        for row in rows {
                            let row = min(max(0, row), list.count - 1)
                            if let dateItem = self.item(at: row) as? TableStickItem, let view = dateItem.view as? TableStickView, dateItem.className == secondaryClassName {
                                if documentOffset.y > (documentSize.height - frame.height) && !tableView.isFlipped {
                                    yTopOffset = -1
                                }
                                view.updateIsVisible(yTopOffset < 0 , animated: false)
                                applied = true
                            }
                        }
                        if !applied {
                            let secondaryViewClassName = secondaryStickView.className
                            self.enumerateVisibleViews(with: { view in
                                if secondaryViewClassName == view.className {
                                    (view as? TableStickView)?.updateIsVisible(true, animated: false)
                                }
                            })
                        }
                    }
                    
                    if secondaryPreviousStickMinY == nil {
                        secondaryPreviousStickMinY = documentOffset.y
                    }
                                        
                    if secondaryPreviousStickMinY != documentOffset.y {
                        secondaryStickView.isHidden = false
                        secondaryPreviousStickMinY = documentOffset.y
                        if !animated || secondaryStickView.layer?.opacity != 0 {
                            secondaryStickView.updateIsVisible(true, animated: true)
                            secondaryFirstTime = false
                        }
                    }
                    if tableView.isFlipped {
                        secondaryStickView.isHidden = (documentOffset.y + stickTopInset <= 0 && !item.singletonItem)
                    } else {
                        secondaryStickView.isHidden = documentSize.height <= frame.height || documentOffset.y > (documentSize.height - frame.height)
                    }
                    
                    // Ensure primary stick is always positioned below secondary
                    if let stickView = stickView, !stickView.isHidden {
                        let primaryYPos = stickView.frame.origin.y
                        let secondaryYMaxPos = secondaryStickView.frame.origin.y + secondaryStickView.frame.height
                        
                        if primaryYPos < secondaryYMaxPos {
                          //  stickView._change(pos: NSMakePoint(0, secondaryYMaxPos), animated: animated)
                        }
                    }
                    
//                    // Set timeout for secondary stick
//                    secondaryStickTimeoutDisposable.set((Signal<Void, NoError>.single(Void()) |> delay(2.0, queue: Queue.mainQueue())).start(next: { [weak secondaryStickView] in
//                        if itemRect.height == 0, let secondaryStickView = secondaryStickView {
//                            secondaryStickView.updateIsVisible(false, animated: true)
//                        }
//                    }))
                }
                
            } else {
                if index == -1 {
                    if animated, let secondaryStickView = self.secondaryStickView {
                        secondaryStickView._change(pos: NSMakePoint(0, -secondaryStickView.frame.height), animated: animated, removeOnCompletion: false, completion: { [weak secondaryStickView] _ in
                            secondaryStickView?.removeFromSuperview()
                        })
                    } else {
                        secondaryStickView?.removeFromSuperview()
                    }
                } else {
                    secondaryStickView?.setFrameOrigin(0, 0)
                    secondaryStickView?.header = true
                    secondaryStickView?.isHidden = true
                }
                
                let secondaryViewClassName = secondaryStickView?.className
                self.enumerateExistingViews(with: { view in
                    if secondaryViewClassName == view.className {
                        (view as? TableStickView)?.updateIsVisible(true, animated: false)
                    }
                })
            }
        }
    }
    
    private let stickTimeoutDisposable = MetaDisposable()
    private var stickTimeoutDeadline: CFTimeInterval = 0
    private var stickTimeoutAction: (() -> Void)?
    private var stickTimeoutTimer: SwiftSignalKit.Timer?

    private func scheduleStickTimeout(_ action: @escaping () -> Void) {
        stickTimeoutAction = action
        stickTimeoutDeadline = CACurrentMediaTime() + 2.0
        if stickTimeoutTimer == nil {
            armStickTimeout(2.0)
        }
    }

    private func armStickTimeout(_ timeout: Double) {
        let timer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
            guard let self = self else {
                return
            }
            self.stickTimeoutTimer = nil
            let remaining = self.stickTimeoutDeadline - CACurrentMediaTime()
            if remaining > 0 {
                self.armStickTimeout(remaining)
            } else {
                let action = self.stickTimeoutAction
                self.stickTimeoutAction = nil
                action?()
            }
        }, queue: Queue.mainQueue())
        stickTimeoutTimer = timer
        timer.start()
    }
    private var secondaryStickTimeoutDisposable = MetaDisposable()
    
    private var previousStickMinY: CGFloat? = nil
    private var secondaryPreviousStickMinY: CGFloat? = nil
    
    private var stickTopInset: CGFloat = 0
    public func updateStickInset(_ inset: CGFloat, animated: Bool) {
        if stickTopInset != inset {
            stickTopInset = inset
            updateStickAfterScroll(animated)
        }
    }

    private var stickScrollInset: CGFloat {
        if tableView.isFlipped {
            return documentOffset.y + stickTopInset
        } else {
            return documentOffset.y - stickTopInset + frame.height
        }
    }

    private func stickRange(_ visibleRect: NSRect, bottomOffset: CGFloat) -> NSRange {
        if tableView.isFlipped, stickTopInset > 0 {
            let minY = max(visibleRect.minY, liveDocumentOffset.y + stickTopInset)
            return self.tableView.rows(in: NSMakeRect(visibleRect.minX, minY, visibleRect.width, visibleRect.maxY - minY - bottomOffset))
        } else {
            return self.tableView.rows(in: NSMakeRect(visibleRect.minX, visibleRect.minY, visibleRect.width, visibleRect.height - stickTopInset - bottomOffset))
        }
    }
    
    
    // Add a disposable for the secondary stick view timeout
    

    
    @inline(__always)
    public func optionalItem(at: Int) -> TableRowItem? {
        guard at >= 0 else { return nil }
        let items = list
        return at < items.count ? items[at] : nil
    }
    
    private var needsLayouItemsOnNextTransition:Bool = false
   
    public func layoutItems() {

        let visibleItems = self.visibleItems()
        
        self.beginTableUpdates()
        self.enumerateItems { item in
            _ = item.makeSize(frame.width, oldWidth: item.width)
            reloadData(row: item.index, animated: false)
            return true
        }
        self.endTableUpdates()
        
        
        self.saveScrollState(visibleItems)
        
        self.needsLayouItemsOnNextTransition = false
    }
    
    public override var _mouseDownCanMoveWindow: Bool {
        didSet {
            clipView._mouseDownCanMoveWindow = _mouseDownCanMoveWindow
            tableView._mouseDownCanMoveWindow = _mouseDownCanMoveWindow
        }
    }
    
    open override var mouseDownCanMoveWindow: Bool {
        return _mouseDownCanMoveWindow
    }
    
    public func saveScrollState(_ visibleItems: [(TableRowItem,CGFloat,CGFloat)]) -> Void {
        //
        if !visibleItems.isEmpty {
            var nrect:NSRect = NSZeroRect
            
            let strideTo:StrideTo<Int> = stride(from: visibleItems.count - 1, to: -1, by: -1)
            
            for i in strideTo {
                let visible = visibleItems[i]
                if let item = self.item(stableId: visible.0.stableId) {
                    
                    nrect = rectOf(item: item)
                    
                    if let view = viewNecessary(at: i) {
                        if view.isInsertionAnimated {
                            break
                        }
                    }
                    
                    let y:CGFloat
                    if !tableView.isFlipped {
                        y = nrect.minY - (frame.height - visible.1) + nrect.height
                    } else {
                        y = nrect.minY - visible.1
                    }
                    
                    self.clipView.updateBounds(to: NSMakePoint(0, y))
                   // reflectScrolledClipView(clipView)
                   // flashScrollers()
                    break
                }
            }
        }
    }
    
    
  
    
    
    public func resetScrollNotifies() ->Void {
        self.previousScroll = nil
        resetScroll()
    }
    
    public func scrollUp(offset: CGFloat = 30.0) {
        let baseY = clipView.destination?.y ?? clipView.bounds.minY
        self.clipView.scroll(to: NSMakePoint(0, min(baseY + offset, clipView.bounds.maxY)), animated: true, timingFunction: .linear, duration: 0.35)
        self.reflectScrolledClipView(clipView)
    }


    public func scrollDown(offset: CGFloat = 30.0) {
        let baseY = clipView.destination?.y ?? clipView.bounds.minY
        self.clipView.scroll(to: NSMakePoint(0, max(baseY - offset, 0)), animated: true, timingFunction: .linear, duration: 0.35)
        self.reflectScrolledClipView(clipView)
    }
    
    public func notifyScrollHandlers() -> Void {
        let scroll = scrollPosition(visibleRows()).current
        for listener in scrollListeners {
            listener.handler(scroll)
        }
    }

    public var topVisibleRow:Int? {
        let visible = visibleItems()
        if !isFlipped {
            return visible.first?.0.index
        } else {
            return visible.last?.0.index
        }
    }
    
    public var bottomVisibleRow:Int? {
        let visible = visibleItems()
        if isFlipped {
            return visible.first?.0.index
        } else {
            return visible.last?.0.index
        }
    }
    
    open override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin);
        self.updateTrackingAreas();
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func selectedItem() -> TableRowItem? {
        
        let hash = selectedhash
        if let hash = hash {
            return self.item(stableId:hash)
        }
        return nil
    }
    
    public func isSelected(_ item:TableRowItem) ->Bool {
        return selectedhash == item.stableId
    }
    
    public func highlightedItem() -> TableRowItem? {
        
        let hash = highlitedHash
        if let hash = hash {
            return self.item(stableId: hash)
        }
        return nil
    }
    
    public func isHighlighted(_ item:TableRowItem) ->Bool {
        return highlitedHash == item.stableId
    }
    
    public func item(stableId:AnyHashable) -> TableRowItem? {
        return self.listhash[stableId];
    }
    
    public func index(of:TableRowItem) -> Int? {
        if let it = self.listhash[of.stableId] {
            return self.list.firstIndex(of: it)
        }
        return nil
    }
    
    public func index(hash:AnyHashable) -> Int? {
        
        if let it = self.listhash[hash] {
            return it.index
        }
        
        return nil
    }
    
    fileprivate func startResorting(_ range: NSRange, _ offset: CGPoint) {
        guard let window = _window else {return}
        
        let point = tableView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if range.length > 0, let controller = resortController, controller.canResort(range.location), let view = viewNecessary(at: range.location) {
            controller.resortRow = range.location
            controller.currentHoleIndex = range.location
            controller.resortView = view
            controller.startLocation = NSMakePoint(round(point.y), round(point.y))
            controller.startRowLocation = view.frame.origin.offsetBy(dx: 0, dy: round(offset.y))
            controller.start(range.location)
   
            view.frame = convert(view.frame, from: view.superview)
            
            
            
            addSubview(view)
            view.isHidden = false
            window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
                guard let controller = self?.resortController, controller.isResorting else {return .rejected}
                self?.stopResorting()
                return .invoked
            }, with: self, for: .leftMouseUp, priority: .modal)
            
            var first: Bool = true
            
            window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
                if let controller = self?.resortController, let view = controller.resortView, let `self` = self {
                    
                    self.contentView.autoscroll(with: event)
                    
                    var point = self.tableView.convert(event.locationInWindow, from: nil)
                    point.x = 0
                    let difference = (controller.startLocation.y - point.y)
                
                    
                    if view.superview != self {
                        view.frame = self.convert(view.frame, from: view.superview)
                        let item = self.item(at: range.location)
                        view.set(item: item, animated: false)
                        view.updateLayout(size: view.frame.size, transition: .immediate)
                        controller.resortView = view
                        self.addSubview(view)
                    }
                    view.isHidden = false
                    
                    var newPoint = NSMakePoint(view.frame.minX, max(controller.startRowLocation.y - difference, 0))
                    newPoint.y -= self.documentOffset.y //self.convert(newPoint, from: self.tableView)
                    newPoint = NSMakePoint(round(newPoint.x), round(newPoint.y))
                    if first {
                        view.layer?.animatePosition(from: NSMakePoint(0, view.frame.minY - newPoint.y), to: .zero, duration: duration, timingFunction: .spring, removeOnCompletion: true, additive: true)
                    }
                    view.setFrameOrigin(newPoint)
                    first = false
                    self.updateMovableItem(point)
                    return .invoked
                } else {
                    return .rejected
                }
            }, with: self, for: .leftMouseDragged, priority: .modal)
            
            
        }
    }
    
    
    fileprivate func stopResorting() {
        if let controller = resortController, let current = controller.currentHoleIndex, let start = controller.resortRow {
            
            
            NSAnimationContext.runAnimationGroup({ ctx in
                if self.isResortRangeValid(controller) {
                    var y: CGFloat = 0
                    for i in 0 ..< controller.resortRange.location {
                        y += self.list[i].heightValue
                    }
                    for i in controller.resortRange.location ..< controller.resortRange.max  {
                        if let resortView = controller.resortView {
                            if i == current {
                                if current > start {
                                    y -= (resortView.frame.height - item(at: i).heightValue)
                                }
                                y -= self.documentOffset.y
                                let point = NSMakePoint(resortView.frame.minX, y)
                                //convert(, from: tableView)
                                resortView.animator().setFrameOrigin(point)
                                y = 0
                                break
                            }
                            y += item(at: i).heightValue
                        }
                    }
                }
            }, completionHandler: {
                
                CATransaction.begin()
                
                let view = controller.resortView
                controller.clear()
                if let view = view {
                    view.frame = self.tableView.convert(view.frame, from: view.superview)
                    self.tableView.addSubview(view)
                }
                
                let isValidDrop = controller.canResort(start) && controller.canResort(current) && start < self.list.count && current < self.list.count

                self.beginTableUpdates()

                if isValidDrop {
                    if start != current, self.unresortedList == nil || self.unresortedListCarried {
                        self.unresortedList = self.list
                        self.unresortedListCarried = false
                    }
                    self.moveItem(from: start, to: current, redraw: false, animation: .none)
                    self.tableView.removeRows(at: IndexSet(integer: start), withAnimation: .none)
                    self.tableView.insertRows(at: IndexSet(integer: current), withAnimation: .none)
                } else {
                    view?.removeFromSuperview()
                    if let item = view?.item, let index = self.list.firstIndex(where: { $0 === item }) {
                        self.tableView.removeRows(at: IndexSet(integer: index), withAnimation: .none)
                        self.tableView.insertRows(at: IndexSet(integer: index), withAnimation: .none)
                    }
                }
                self.endTableUpdates()

                CATransaction.commit()

                if isValidDrop {
                    if controller.completeDelay > 0 {
                        delay(controller.completeDelay, closure: {
                            controller.complete(start, current)
                        })
                    } else {
                        controller.complete(start, current)
                    }
                }
                
            })
            
            
            _window?.remove(object: self, for: .leftMouseUp)
            _window?.remove(object: self, for: .leftMouseDragged)
        }
    }
    

    

    private func isResortRangeValid(_ controller: TableResortController) -> Bool {
        return controller.resortRange.location != NSNotFound && controller.resortRange.max <= self.list.count
    }

    private func listAfterMerge(_ items: [TableRowItem], deleted: [Int], inserted: [(Int, TableRowItem)], updated: [(Int, TableRowItem)]) -> [TableRowItem]? {
        guard Set(updated.map { $0.0 }).count == updated.count else {
            return nil
        }
        var items = items
        for index in deleted.reversed() {
            guard index >= 0 else {
                return nil
            }
            if index < items.count {
                items.remove(at: index)
            }
        }
        for (index, item) in inserted {
            guard index >= 0 else {
                return nil
            }
            items.insert(item, at: min(index, items.count))
        }
        for (index, item) in updated {
            guard index >= 0 else {
                return nil
            }
            if index < items.count {
                items[index] = item
            }
        }
        return items
    }

    private func hasUniqueStableIds(_ items: [TableRowItem]) -> Bool {
        return Set(items.map { $0.stableId }).count == items.count
    }

    private func hasSameRows(_ lhs: [TableRowItem], _ rhs: [TableRowItem]) -> Bool {
        let lhsIds = Set(lhs.map { ObjectIdentifier($0) })
        return lhs.count == rhs.count && lhsIds.count == lhs.count && lhsIds == Set(rhs.map { ObjectIdentifier($0) })
    }

    private func adjustedForResort(_ transition: TableUpdateTransition) -> (deleted: [Int], updated: [(Int, TableRowItem)], settlesResort: Bool) {
        let unchanged = (transition.deleted, transition.updated, false)
        guard let unresorted = self.unresortedList else {
            return unchanged
        }
        self.unresortedList = nil
        self.unresortedListCarried = false

        guard hasSameRows(unresorted, self.list) else {
            return unchanged
        }
        guard let expected = listAfterMerge(unresorted, deleted: transition.deleted, inserted: transition.inserted, updated: transition.updated), let current = listAfterMerge(self.list, deleted: transition.deleted, inserted: transition.inserted, updated: transition.updated) else {
            return unchanged
        }
        if current.elementsEqual(expected, by: { $0 === $1 }) {
            return (transition.deleted, transition.updated, true)
        }
        if hasUniqueStableIds(current) {
            if hasSameRows(current, expected) {
                self.unresortedList = expected
                self.unresortedListCarried = true
            }
            return unchanged
        }

        var listIndices: [ObjectIdentifier: Int] = [:]
        for (index, item) in self.list.enumerated() {
            listIndices[ObjectIdentifier(item)] = index
        }
        var deleted: [Int] = []
        for index in transition.deleted {
            guard index >= 0, index < unresorted.count, let listIndex = listIndices[ObjectIdentifier(unresorted[index])] else {
                return unchanged
            }
            deleted.append(listIndex)
        }
        deleted.sort()

        guard let expectedBeforeUpdates = listAfterMerge(unresorted, deleted: transition.deleted, inserted: transition.inserted, updated: []), let currentBeforeUpdates = listAfterMerge(self.list, deleted: deleted, inserted: transition.inserted, updated: []) else {
            return unchanged
        }
        var currentIndices: [ObjectIdentifier: Int] = [:]
        for (index, item) in currentBeforeUpdates.enumerated() {
            currentIndices[ObjectIdentifier(item)] = index
        }
        var updated: [(Int, TableRowItem)] = []
        for (index, item) in transition.updated {
            guard index >= 0, index < expectedBeforeUpdates.count, let currentIndex = currentIndices[ObjectIdentifier(expectedBeforeUpdates[index])] else {
                return unchanged
            }
            updated.append((currentIndex, item))
        }

        guard let adjusted = listAfterMerge(self.list, deleted: deleted, inserted: transition.inserted, updated: updated), hasUniqueStableIds(adjusted), hasSameRows(adjusted, expected) else {
            return unchanged
        }
        if adjusted.elementsEqual(expected, by: { $0 === $1 }) {
            return (deleted, updated, true)
        }
        self.unresortedList = expected
        self.unresortedListCarried = true
        return (deleted, updated, false)
    }

    private var maxResortHeight: CGFloat {
        guard let controller = resortController else {return 0}
        var height: CGFloat = 0
        for i in 0 ..< controller.resortRange.max {
            height += item(at: i).heightValue
        }
        return height
    }
    
    
    private func moveHole(at fromIndex: Int, to toIndex: Int, animated: Bool) {
        var y: CGFloat = 0
                
        guard let controller = resortController, let resortRow = controller.resortRow, let resortView = controller.resortView else {return}
        if !isResortRangeValid(controller) {
            self.stopResorting()
            return
        }
        for i in 0 ..< controller.resortRange.location {
            y += self.list[i].heightValue
        }
        
        if toIndex > resortRow {
            
            y = maxResortHeight
            
            for i in stride(from: controller.resortRange.max - 1, to: -1, by: -1) {
                let view = viewNecessary(at: i, makeIfNecessary: false)
                if i == toIndex {
                    y -= resortView.frame.height// view.frame.height
                }
                if view != controller.resortView {
                    y -= self.item(at: i).heightValue
                    view?.animator().setFrameOrigin(0, y)
                }
            }
        } else {
            for i in controller.resortRange.location ..< controller.resortRange.max {
                let view = viewNecessary(at: i, makeIfNecessary: false)
                if i == toIndex {
                    y += resortView.frame.height
                }
                if view != controller.resortView {
                    view?.animator().setFrameOrigin(0, y)
                    y += self.item(at: i).heightValue
                }
            }
        }
        
        
    }
    
    private func updateMovableItem(_ point: NSPoint) {
        
        
        guard let controller = resortController else {return}
        
        let row = tableView.row(at: point)
        if row != -1 {
            let row = min(max(tableView.row(at: point), controller.resortRange.location), controller.resortRange.max - 1)
            controller.prevHoleIndex = controller.currentHoleIndex
            controller.currentHoleIndex = row
            if controller.prevHoleIndex != controller.currentHoleIndex {
                moveHole(at: controller.prevHoleIndex!, to: controller.currentHoleIndex!, animated: true)
                controller.updateItems(controller.resortView, self.list.filter { controller.canResort($0.index) })
            }
        }
    }


    private var _window:Window? {
        return window as? Window
    }
    
    public func insert(item:TableRowItem, at:Int = 0, redraw:Bool = true, animation:NSTableView.AnimationOptions = .none) -> Bool {
       // assert(self.item(stableId:item.stableId) == nil, "inserting existing row inTable: \(self.item(stableId:item.stableId)!.className), new: \(item.className), stableId: \(item.stableId)")
        self.listhash[item.stableId] = item;
        let at = min(at, list.count)
        self.list.insert(item, at: at);
        item.table = self;
        item._index = at
        if frame.width > 0 {
            if item.premeasuredWidth != frame.width {
                _ = item.makeSize(frame.width, oldWidth: item.oldWidth)
            }
            item.premeasuredWidth = nil
        }
        let animation = animation != .none ? item.animatable ? animation : .none : .none
        
        NSAnimationContext.current.duration = animation != .none ? duration : 0.0
        NSAnimationContext.current.timingFunction = animation == .none ? nil : CAMediaTimingFunction(name: .easeOut)
        if(redraw) {
            self.tableView.insertRows(at: IndexSet(integer: at), withAnimation: animation)
          //  self.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: at))
        }
        
        return true;
        
    }
    
    public func addItem(item:TableRowItem, redraw:Bool = true, animation:NSTableView.AnimationOptions = .none) -> Bool {
        return self.insert(item: item, at: self.count, redraw: redraw, animation:animation)
    }
    
    public func insert(items:[TableRowItem], at:Int = 0, redraw:Bool = true, animation:NSTableView.AnimationOptions = .none) -> Void {
        
        
        var current:Int = 0;
        for item in items {
            
            if(self.insert(item: item, at: at + current, redraw: false)) {
                current += 1;
            }
            
        }
        
        if(current != 0 && redraw) {
            self.tableView.insertRows(at: IndexSet(integersIn: at ..< current + at), withAnimation: animation)
            self.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: at ..< current + at))

        }
        
    }
    
    
    public var firstItem:TableRowItem? {
        return self.list.first
    }
    
    public var lastItem:TableRowItem? {
        return self.list.last
    }
    
    public func noteHeightOfRow(_ row:Int, _ animated:Bool = true) {
        guard row >= 0 && row < self.count else {
            return
        }
        if !animated {
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.timingFunction = nil
        }
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        let item = self.item(at: row)
        let height = item.heightValue
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: duration, curve: .easeOut) : .immediate
        if let view = item.view {
            view.set(item: item, animated: animated)
            view.updateLayout(size: NSMakeSize(frame.width, height), transition: transition)
            transition.updateFrame(view: view, frame: CGRect(origin: view.frame.origin, size: NSMakeSize(frame.width, height)))
        }
    }
    
    
    
    public func reloadData(row:Int, animated:Bool = false, options: NSTableView.AnimationOptions = .effectFade, presentAsNew: Bool = false) -> Void {
        if let view = self.viewNecessary(at: row) {
            let item = self.item(at: row)
            
            if view.isKind(of: item.viewClass()) && !presentAsNew {
                
                let height:CGFloat = item.heightValue
                let width:CGFloat = self is HorizontalTableView ? item.width : frame.width

                let rect = CGRect(origin: view.frame.origin, size: CGSize(width: width, height: height))
                
                let animated = (animated || view.layer?.animation(forKey: "position") != nil) && view.canAnimateUpdate(item)

                
                let transition: ContainedViewLayoutTransition = animated ? .animated(duration: duration, curve: .easeOut) : .immediate
                
                
                view.set(item: item, animated: animated)
                view.updateLayout(size: rect.size, transition: transition)
                transition.updateFrame(view: view, frame: rect)
                NSAnimationContext.current.duration = animated ? duration : 0.0
                NSAnimationContext.current.timingFunction = animated ? CAMediaTimingFunction(name: .easeOut) : nil
                self.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
                
                return
            }
        }
        if let item = self.optionalItem(at: row) {
            let animated = visibleRows().contains(row) && item.view != nil && animated
            NSAnimationContext.current.duration = animated ? duration : 0.0
            NSAnimationContext.current.timingFunction = animated ? CAMediaTimingFunction(name: .easeOut) : nil
            self.tableView.beginUpdates()
            self.tableView.removeRows(at: IndexSet(integer: row), withAnimation: animated ? options : [.none])
            self.tableView.insertRows(at: IndexSet(integer: row), withAnimation: animated ? options : [.none])
            self.tableView.endUpdates()
        }

    }
    
    fileprivate func reloadHeightItems() {
        beginTableUpdates()
        self.enumerateItems { item -> Bool in
            if item.reloadOnTableHeightChanged {
                self.reloadData(row: item.index)
            }
            return true
        }
        endTableUpdates()
    }
    
    public func fitToSize() {
    }
    
    
    public func moveItem(from:Int, to:Int, changeItem:TableRowItem? = nil, redraw:Bool = true, animation:NSTableView.AnimationOptions = .none) -> Void {
        
        
        var item:TableRowItem = self.item(at:from);
        let animation: NSTableView.AnimationOptions = animation != .none ? item.animatable ? animation : .none : .none
        NSAnimationContext.current.duration = animation != .none ? duration : 0.0
        NSAnimationContext.current.timingFunction = animation != .none ? CAMediaTimingFunction(name: .easeOut) : nil

        if let change = changeItem {
            assert(change.stableId == item.stableId)
            change.table = self
            self.listhash.removeValue(forKey: item.stableId)
            self.listhash[change.stableId] = change
            item = change
        }
        
        self.list.remove(at: from);
        
        self.list.insert(item, at: to);
        
        item._index = to
        
        if(redraw) {
            self.reloadData(row: to)
        }
        
    }
    
    public func beginUpdates() -> Void {
        updating = true
        resetScroll(visibleRows())
        self.previousScroll = nil
    }
    
    public func endUpdates() -> Void {
        updating = false
        resetScroll(visibleRows())
        self.previousScroll = nil
    }
    
    public func rectOf(item:TableRowItem) -> NSRect {
        let index = item.index
        if index >= 0, index < self.list.count, self.list[index] === item {
            let rect = self.tableView.rect(ofRow: index)
            return CGRect(origin: CGPoint(x: round(rect.minX), y: round(rect.minY)), size: rect.size)
        }
        guard let item = self.item(stableId: item.stableId) else {
            return .zero
        }
        let rect = self.tableView.rect(ofRow: item.index)

        return CGRect(origin: CGPoint(x: round(rect.minX), y: round(rect.minY)), size: rect.size)
    }
    
    public func rectOf(index:Int) -> NSRect {
        if index >= 0 && index < list.count {
            return self.tableView.rect(ofRow: index)
        }
        return .zero
    }
    
    public func remove(at:Int, redraw:Bool = true, animation:NSTableView.AnimationOptions = .none) -> Void {
        if at < count {
            
            viewNecessary(at: at)?.onRemove(animation)
            
            let item = self.list.remove(at: at);
            self.listhash.removeValue(forKey: item.stableId)
            
                        
            item._index = nil

            let animation: NSTableView.AnimationOptions = animation != .none ? item.animatable ? animation : .none : .none
            NSAnimationContext.current.duration = animation == .none ? 0.0 : duration
            NSAnimationContext.current.timingFunction = animation == .none ? nil : CAMediaTimingFunction(name: .easeOut)

            if(redraw) {
                self.tableView.removeRows(at: IndexSet(integer:at), withAnimation: animation)
            }
        }
    }
    
    public func remove(range:Range<Int>, redraw:Bool = true, animation:NSTableView.AnimationOptions = .none) -> Void {
        
        for i in range.lowerBound ..< range.upperBound {
            remove(at: i, redraw: false)
        }
        
        if(redraw) {
            self.tableView.removeRows(at: IndexSet(integersIn:range), withAnimation:  animation != .none ? .effectFade : .none)
        }
    }
    

    
    public func removeAll(redraw:Bool = true, animation:NSTableView.AnimationOptions = .none) -> Void {
        let count:Int = self.count;
       
        self.beginTableUpdates()
        if(redraw) {
            self.tableView.removeRows(at: IndexSet(integersIn: 0 ..< count), withAnimation:  animation != .none ? .effectFade : .none)
        }
        self.list.removeAll()
        self.listhash.removeAll()
        self.endTableUpdates()
        
        var bp = 0
        bp += 1
        //self.tableView.removeAllSubviews()
    }
    
    public func selectNext(_ scroll:Bool = true, _ animated:Bool = false, turnDirection: Bool = true) -> Void {
        if let hash = selectedhash {
            let selectedItem = self.item(stableId: hash)
            if let selectedItem = selectedItem {
                var selectedIndex = self.index(of: selectedItem)!
                selectedIndex += 1
                
                if selectedIndex == count  {
                    if turnDirection {
                        selectedIndex = 0
                    } else {
                        selectedIndex = count - 1
                    }
                }
                if let delegate = delegate {
                    let sIndex = selectedIndex
                    for i in sIndex ..< list.count {
                        if delegate.selectionWillChange(row: i, item: item(at: i), byClick: false) {
                            selectedIndex = i
                            break
                        }
                    }
                }
                
                
                 _ = select(item: item(at: selectedIndex))
            }
            
            
        } else {
            if let delegate = delegate {
                for item in list {
                    if delegate.selectionWillChange(row: item.index, item: item, byClick: false) {
                        _ = self.select(item: item)
                        break
                    }
                }
            }
            
        }
        if let hash = selectedhash, scroll {
            self.scroll(to: .top(id: hash, innerId: nil, animated: animated, focus: .init(focus: false), inset: 0), inset: NSEdgeInsets(), toVisible: true)
        }
    }
    
    public func selectPrev(_ scroll:Bool = true, _ animated:Bool = false, turnDirection: Bool = true) -> Void {
        if let hash = selectedhash {
            let selectedItem = self.item(stableId: hash)
            if let selectedItem = selectedItem {

                var selectedIndex = self.index(of: selectedItem)!
                selectedIndex -= 1
                
                if selectedIndex == -1  {
                    if turnDirection {
                        selectedIndex = count - 1
                    } else {
                        selectedIndex = 0
                    }
                }
                
                if let delegate = delegate {
                    let sIndex = selectedIndex
                    for i in stride(from: sIndex, to: -1, by: -1) {
                        if delegate.selectionWillChange(row: i, item: item(at: i), byClick: false) {
                            selectedIndex = i
                            break
                        }
                    }
                }

                
                _ = select(item: item(at: selectedIndex))
            }
            
            
        } else {
            if let delegate = delegate {
                for i in stride(from: list.count - 1, to: -1, by: -1) {
                    if delegate.selectionWillChange(row: i, item: item(at: i), byClick: false) {
                        _ = self.select(item: item(at: i))
                        break
                    }
                }
            }

        }
        
        if let hash = selectedhash, scroll {
            self.scroll(to: .bottom(id: hash, innerId: nil, animated: animated, focus: .init(focus: false), inset: 0), inset: NSEdgeInsets(), toVisible: true)
        }
    }
    
    public func highlightNext(_ scroll:Bool = true, _ animated:Bool = false, turnDirection: Bool = true) -> Void {
        var previousInset: CGFloat = 0
        if let hash = highlitedHash {
            let highlighteditem = self.item(stableId: hash)

            if let highlighteditem = highlighteditem {
                previousInset = -highlighteditem.heightValue
                var selectedIndex = self.index(of: highlighteditem)!
                selectedIndex += 1
                
                if selectedIndex == count  {
                    if turnDirection {
                        selectedIndex = 0
                    } else {
                        selectedIndex = count - 1
                    }
                }
                if let delegate = delegate {
                    let sIndex = selectedIndex
                    for i in sIndex ..< list.count {
                        if delegate.selectionWillChange(row: i, item: item(at: i), byClick: false), selectedItem()?.index != i {
                            selectedIndex = i
                            break
                        }
                    }
                }
            
                _ = highlight(item: item(at: selectedIndex))
            }
            
            
        } else {
            if let delegate = delegate {
                for item in list {
                    if delegate.selectionWillChange(row: item.index, item: item, byClick: false), selectedItem()?.index != item.index {
                        _ = self.highlight(item: item)
                        break
                    }
                }
            }
            
        }
        if let hash = highlitedHash, scroll {
            self.scroll(to: .top(id: hash, innerId: nil, animated: animated, focus: .init(focus: false), inset: previousInset), inset: NSEdgeInsets(), toVisible: true)
        }
    }
    
    public func highlightPrev(_ scroll:Bool = true, _ animated:Bool = false, turnDirection: Bool = true) -> Void {
        var previousInset: CGFloat = 0

        if let hash = highlitedHash {
            let highlightedItem = self.item(stableId: hash)
            if let highlightedItem = highlightedItem {
                previousInset = highlightedItem.heightValue
                var selectedIndex = self.index(of: highlightedItem)!
                selectedIndex -= 1
                
                if selectedIndex == -1  {
                    if turnDirection {
                        selectedIndex = count - 1
                    } else {
                        selectedIndex = 0
                    }
                }
                
                if let delegate = delegate {
                    let sIndex = selectedIndex
                    for i in stride(from: sIndex, to: -1, by: -1) {
                        if delegate.selectionWillChange(row: i, item: item(at: i), byClick: false), selectedItem()?.index != i {
                            selectedIndex = i
                            break
                        }
                    }
                }
                
                _ = highlight(item: item(at: selectedIndex))
            }
            
            
        } else {
            if let delegate = delegate {
                for i in stride(from: list.count - 1, to: -1, by: -1) {
                    if delegate.selectionWillChange(row: i, item: item(at: i), byClick: false), selectedItem()?.index != i {
                        _ = self.highlight(item: item(at: i))
                        break
                    }
                }
            }
            
        }
        
        if let hash = highlitedHash, scroll {
            self.scroll(to: .bottom(id: hash, innerId: nil, animated: animated, focus: .init(focus: false), inset: previousInset), inset: NSEdgeInsets(), toVisible: true)
        }
    }
    
    
    public var isEmpty:Bool {
        
        if let emptyChecker = emptyChecker {
            return emptyChecker(self.list)
        }
        
        return self.list.isEmpty || (!tableView.isFlipped && list.count == 1)
    }
    
    public func reloadData(width: CGFloat? = nil) -> Void {
        self.beginTableUpdates()
        self.enumerateItems { item -> Bool in
            _ = item.makeSize(width ?? frame.width)
            self.reloadData(row: item.index)
            return true
        }
        self.endTableUpdates()
    }
    
    public func reloadHeight() {
        self.beginTableUpdates()
        for index in 0 ..< list.count {
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.timingFunction = nil
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: index))
        }
        self.endTableUpdates()
//        self.tableView.tile()
    }
    
    public func item(at:Int) -> TableRowItem {
        return self.list[at]
    }
    
    public func nextItem(after index:Int) -> TableRowItem? {
        if index < list.count - 1, index >= 0 {
            return self.list[index + 1]
        } else {
            return nil
        }
    }
    
    public func visibleRows(_ insetHeight:CGFloat = 0) -> NSRange {
        //self.tableView.visibleRect
        let visibleRect = self.tableView.realVisibleRect
        var rect = NSMakeRect(0, documentOffset.y, visibleRect.width, visibleRect.height).insetBy(dx: 0, dy: -insetHeight)
        if insetHeight == 0, contentInsets.top > 0 {
            rect.size.height -= contentInsets.top
        }
        let range = self.tableView.rows(in: rect)
        return range
    }
    
    public var listHeight:CGFloat {
        var height:CGFloat = 0
        for item in list {
            height += item.heightValue
        }
        return height
    }
    
    public func row(at point:NSPoint) -> Int {
        return tableView.row(at: NSMakePoint(point.x, point.y - bottomInset))
    }
    
    public func viewNecessary(at row:Int, makeIfNecessary: Bool = false) -> TableRowView? {
        if row < 0 || row >= count {
            if row == -1000 {
                return emptyView
            }
            return nil
        }
        if let resortView = self.resortController?.resortView {
            if resortView.item?.stableId == self.item(at: row).stableId {
                return resortView
            }
        }
        return self.tableView.rowView(atRow: row, makeIfNecessary: makeIfNecessary) as? TableRowView
    }
    
    public func selectAt(_ index: Int) {
        guard index >= 0 && index < list.count else {
            return
        }
        let item = self.item(at: index)
        _ = self.select(item: item)
        
    }
    
    
    public func select(item:TableRowItem, notify:Bool = true, byClick:Bool = false) -> Bool {

        if let delegate = delegate, delegate.isSelectable(row: item.index, item: item) {
            if(self.item(stableId:item.stableId) != nil) {
                if !notify || delegate.selectionWillChange(row: item.index, item: item, byClick: byClick) {
                    let new = item.stableId != selectedhash
                    if new {
                        self.cancelSelection();
                    }
                    self.selectedhash = item.stableId
                    self.cancelHighlight()
                    item.prepare(true)
                    self.reloadData(row:item.index, animated: true)
                    self.reloadAdjacent(row: item.index, animated: true)
                    if notify {
                        delegate.selectionDidChange(row: item.index, item: item, byClick:byClick, isNew:new)
                    }
                    return true;
                }
            }
        }
        return false;

    }

    private func reloadAdjacent(row: Int, animated: Bool) {
        if row > 0 {
            self.reloadData(row: row - 1, animated: animated)
        }
        if row < self.list.count - 1 {
            self.reloadData(row: row + 1, animated: animated)
        }
    }
    
    public func highlight(item:TableRowItem, notify:Bool = true, byClick:Bool = false) -> Bool {

        if let delegate = delegate, delegate.isSelectable(row: item.index, item: item) {
            if(self.item(stableId:item.stableId) != nil) {
                if !notify || delegate.selectionWillChange(row: item.index, item: item, byClick: byClick) {
                    let new = item.stableId != selectedhash
                    if new {
                        self.cancelHighlight();
                    }
                    highlitedHash = item.stableId
                    item.prepare(true)
                    self.reloadData(row:item.index, animated: true)
                    self.reloadAdjacent(row: item.index, animated: true)
                    return true;
                }
            }
        }
        return false;

    }
    
    public func changeSelection(stableId:AnyHashable?) {
        if let stableId = stableId {
            if let item = self.item(stableId: stableId) {
                _ = self.select(item:item, notify:false)
            } else {
                cancelSelection()
                self.selectedhash = stableId
            }
        } else {
            cancelSelection()
        }
    }
    
    public func cancelSelection() -> Void {
        if let hash = selectedhash {
            if let item = self.item(stableId: hash) {
                item.prepare(false)
                selectedhash = nil
                self.reloadData(row:item.index, animated: true)
                self.reloadAdjacent(row: item.index, animated: true)
            } else {
                selectedhash = nil
            }
        }

    }
    
    public func cancelHighlight() -> Void {
        if let hash = highlitedHash {
            if let item = self.item(stableId: hash) {
                item.prepare(false)
                highlitedHash = nil
                self.reloadData(row: item.index, animated: true)
                self.reloadAdjacent(row: item.index, animated: true)
            } else {
                highlitedHash = nil
            }
        }

    }
    
    
    func rowView(item:TableRowItem) -> TableRowView {
        let identifier:String = item.identifier
        
        if let resortView = self.resortController?.resortView {
            if resortView.item?.stableId == item.stableId {
                return resortView
            }
        }
        
        var view: NSView? = item.isUniqueView ? nil : self.tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: identifier), owner: self.tableView)

        if(view == nil) {
            if let item = item as? TableStickItem, item.singletonItem {
                view = TableRowView(frame: NSMakeRect(0, 0, frame.width, item.heightValue))
            } else {
                view = makeView(for: item)
            }
            view?.identifier = NSUserInterfaceItemIdentifier(rawValue: identifier)
        }
        if view!.frame.height != item.heightValue {
            view?.setFrameSize(NSMakeSize(frame.width, item.heightValue))
        }
        return view as! TableRowView;
    }
    
    private func makeView(at index: Int) -> TableRowView {
        let item = self.item(at: index)
        let vz = item.viewClass() as! TableRowView.Type
        let view = vz.init(frame:NSMakeRect(0, 0, frame.width, item.heightValue))
        return view
    }
    private func makeView(for item: TableRowItem) -> TableRowView {
        let vz = item.viewClass() as! TableRowView.Type
        let view = vz.init(frame:NSMakeRect(0, 0, frame.width, item.heightValue))
        return view
    }
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return self.count;
    }
    
    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return max(self.item(at: row).heightValue, 1)
    }
    
    public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        return false;
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        return nil
    }
    

  
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let item: TableRowItem = self.item(at: row);
        
        let view: TableRowView = self.rowView(item: item);
        
        self.beforeSetupItem?(view, item)
        let size = NSMakeSize(item.width, item.height)
        
        if view.frame.size != size {
            view.setFrameSize(size)
        }
        view.set(item: item, animated: false)
        view.updateLayout(size: NSMakeSize(item.width, item.height), transition: .immediate)
        self.afterSetupItem?(view, item)

        
        return view
    }

    
    public func visibleItems() -> [(TableRowItem,CGFloat,CGFloat)]  { // item, top offset, bottom offset
        
        var list:[(TableRowItem,CGFloat,CGFloat)] = []
        
        let visible = visibleRows()
        
        for i in visible.min ..< visible.max {
            let item = self.item(at: i)
            let rect = rectOf(index: i)
            if !tableView.isFlipped {
                let top = frame.height - (rect.minY - documentOffset.y) - rect.height
                let bottom = (rect.minY - documentOffset.y)
                list.append((item,top,bottom))
            } else {
                let top = rect.minY - documentOffset.y
                let bottom = frame.height - (rect.minY - documentOffset.y) - rect.height
                list.append((item,top,bottom))
                //fatalError("not supported")
            }
            
           // list.append(item,)
        }
        
        
        return list;

    }
    
    func itemRects() -> [(TableRowItem, NSRect, Int)] {
        var ilist:[(TableRowItem,NSRect,Int)] = [(TableRowItem,NSRect,Int)]()
        
        for i in 0 ..< self.list.count {
            ilist.append((item(at: i),self.rectOf(index: i), i))
            
        }
        
        return ilist;
        
    }
    
    public func beginTableUpdates() {
        self.tableView.beginUpdates()
    }
    
    public func endTableUpdates() {
        self.tableView.endUpdates()
    }
    
    public func stopMerge() {
        mergeDisposable.set(nil)
        mergePromise.set(.single(TableUpdateTransition(deleted: [], inserted: [], updated: [])))
    }
    
    public func merge(with transition:Signal<TableUpdateTransition, NoError>) {
        mergePromise.set(transition |> deliverOnMainQueue)
    }
    
    private var first:Bool = true
    
   
    
    @discardableResult public func merge(with transition:TableUpdateTransition, appearAnimated: Bool = false) -> Bool {
        return self.merge(with: transition, forceApply: false, appearAnimated: appearAnimated)
    }
    
//    private var awaitingTransitions: [TableUpdateTransition] = []
    
    private var processedIds: [Int64] = []
    public var mergesSaveVisibleInOneGroup: Bool = false
    private var pendingAnimatedScrollListener: TableScrollListener?
    private var firstSearchAppear = true
    private var currentSearchState: SearchState?
    
    private func enqueueAwaitingIfNeeded() {
//        while !awaitingTransitions.isEmpty && !self.clipView.isAnimateScrolling {
//            self.merge(with: awaitingTransitions.remove(at: 0), forceApply: true, appearAnimated: false)
//        }
    }
    
    private var lastAppliedScroll: TableScrollState?
    
    @discardableResult private func merge(with transition:TableUpdateTransition, forceApply: Bool, appearAnimated: Bool) -> Bool {
        
        
        if processedIds.contains(transition.uniqueId)  {
            return false
        }
        self.processedIds.append(transition.uniqueId)
        if self.processedIds.count > 32 {
            self.processedIds.removeFirst(self.processedIds.count - 32)
        }
        
        if transition.isEmpty, lastAppliedScroll == transition.state {
            return false
        }
            
        self.lastAppliedScroll = transition.state
        
        assertOnMainThread()
        assert(!updating)

        let (deleted, updated, settlesResort) = self.adjustedForResort(transition)

        var groupInOne = transition.groupInOne
        var groupedListHeight: CGFloat?
        if !groupInOne, mergesSaveVisibleInOneGroup, !appearAnimated, !transition.animated, case let .saveVisible(side, false) = transition.state {
            switch side {
            case .aroundIndex:
                break
            case .lower, .upper:
                let rows = tableView.numberOfRows
                let current = rows > 0 ? tableView.rect(ofRow: 0).union(tableView.rect(ofRow: rows - 1)).height : 0
                let removed = deleted.reduce(CGFloat(0)) { $0 + ($1 < list.count ? list[$1].heightValue : 0) }
                let added = transition.inserted.reduce(CGFloat(0)) { $0 + $1.1.heightValue }
                let next = current - removed + added
                let clipHeight = clipView.bounds.height
                if tableView.frame.height == current, current > clipHeight, next > clipHeight {
                    groupInOne = true
                    groupedListHeight = next
                }
            }
        }
        
        if case .saveVisible = transition.state {
            clipView.cancelScrolling()
        }
        
        resetScrollNotifies()

        
        let oldEmpty = self.isEmpty
        
        self.beginUpdates()
        
        let documentOffset = self.documentOffset
        
        
        let visibleItems = self.visibleItems()
        let visibleRange = self.visibleRows()
        let resizeAnchor = self.resizeAnchor(for: transition)

        for (_, item) in list.enumerated() {
            item._index = nil
        }
        
        

        var inserted:[(TableRowItem, NSTableView.AnimationOptions)] = []
        var removed:[(Int, TableRowItem)] = []
        
        if groupInOne {
            self.tableView.beginUpdates()
        }
        
                
        if transition.grouping && !transition.isEmpty, !transition.state.isNone, !groupInOne {
            self.tableView.beginUpdates()
        }
        
        for rdx in deleted.reversed() {
            let effect:NSTableView.AnimationOptions
            if settlesResort {
                effect = .none
            } else if case let .none(interface) = transition.state, interface != nil {
                effect = (visibleRange.indexIn(rdx) || !transition.animateVisibleOnly) ? .effectFade : .none
            } else {
                effect = transition.animated && (visibleRange.indexIn(rdx) || !transition.animateVisibleOnly) ? .effectFade : .none
            }
            if rdx < visibleRange.location {
                removed.append((rdx, item(at: rdx)))
            }
            self.remove(at: rdx, redraw: true, animation:effect)
        }
        
        for (i, item) in list.enumerated() {
            item._index = i
        }
        
        if transition.grouping && !transition.isEmpty, !transition.state.isNone, !groupInOne {
            self.tableView.endUpdates()
        }
                

        if transition.grouping && !transition.isEmpty, !transition.state.isNone, !groupInOne {
            self.tableView.beginUpdates()
        }
        
        for (idx, item) in transition.inserted {
            let effect:NSTableView.AnimationOptions
            if settlesResort {
                effect = .none
            } else if case let .none(interface) = transition.state, interface != nil {
                effect = .none
            } else {
                effect = transition.animated && (visibleRange.indexIn(idx) || visibleRange.isNone || !transition.animateVisibleOnly) ? .effectFade : .none
            }
            _ = self.insert(item: item, at:idx, redraw: true, animation: effect)

            if item.animatable {
                inserted.append((item, effect))
            }
        }
        if groupInOne, !transition.inserted.isEmpty {
            self.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(transition.inserted.map { $0.0 }))
        }
        if let groupedListHeight, tableView.frame.height != groupedListHeight {
            self.tableView.setFrameSize(NSSize(width: tableView.frame.width, height: groupedListHeight))
        }
        
        for (i, item) in list.enumerated() {
            item._index = i
        }
        
        if transition.grouping && !transition.isEmpty, !transition.state.isNone, !groupInOne {
            self.tableView.endUpdates()
        }
        
        
        for inserted in inserted {
            var accept: Bool = true
            let index = inserted.0.index
            
            let item: TableRowItem?
            
            if let current = removed.first(where: { $0.0 == index })?.1 {
                item = current
            } else if let current = updated.first(where: { $0.0 == index })?.1 {
                item = current
            } else {
                item = nil
            }
            
            if let item = item {
                if object_getClassName(item) == object_getClassName(inserted.0) {
                    accept = false
                }
            }
            if case let .none(interface) = transition.state, interface != nil {
                accept = false
            }
            inserted.0.view?.onInsert(inserted.1, appearAnimated: appearAnimated && accept && !settlesResort && !deleted.contains(inserted.0.index))
        }
        
                
        let state: TableScrollState
        
        if case .none = transition.state, !transition.deleted.isEmpty || !transition.inserted.isEmpty {
            state = transition.state
        } else {
            state = transition.state
        }
        
        
        func saveVisible(_ side: TableSavingSide) {

            self.clipView.cancelScrolling()
            var nrect:NSRect = NSZeroRect
            
            let strideTo:StrideTo<Int>
            
            var aroundIndex: AnyHashable?
            
            if !tableView.isFlipped {
                switch side {
                case .lower:
                    strideTo = stride(from: 0, to: visibleItems.count, by: 1)
                case .upper:
                    strideTo = stride(from: visibleItems.count - 1, to: -1, by: -1)
                case .aroundIndex(let index):
                    aroundIndex = index
                    strideTo = stride(from: 0, to: visibleItems.count, by: 1)
                }
            } else {
                switch side {
                case .upper:
                    strideTo = stride(from: visibleItems.count - 1, to: -1, by: -1)
                case .lower:
                    strideTo = stride(from: 0, to: visibleItems.count, by: 1)
                case .aroundIndex(let index):
                    aroundIndex = index
                    strideTo = stride(from: 0, to: visibleItems.count, by: 1)
                }
            }
                        
            for i in strideTo {
                let visible = visibleItems[i]
                
                if let aroundIndex = aroundIndex {
                    if aroundIndex != visible.0.stableId {
                        continue
                    }
                }
                
                var item = self.item(stableId: visible.0.stableId)
                if item == nil {
                    if let groupStableId = delegate?.findGroupStableId(for: visible.0.stableId) {
                        item = self.item(stableId: groupStableId)
                    }
                }
                if let item = item {
                    
                    if !item.canBeAnchor {
                        continue
                    }
                    

                    
                    nrect = rectOf(item: item)
                    
                    if let view = viewNecessary(at: i) {
                        if view.isInsertionAnimated {
                            break
                        }
                    }
                    
                    let y:CGFloat
                    
                    if !tableView.isFlipped {
                        y = nrect.minY - (frame.height - visible.1) + nrect.height
                    } else {
                        y = nrect.minY - visible.1
                    }
                    self.clipView.updateBounds(to: NSMakePoint(0, y), cancel: true)
                    break
                }
            }
        }
        switch state {
        case .none:
            break
        case .bottom, .top, .center:
            self.scroll(to: transition.state, previousDocumentOffset: documentOffset)
        case .up, .down, .upOffset:
            self.scroll(to: transition.state, previousDocumentOffset: documentOffset)
        case let .saveVisible(side, animated):
            if case .aroundIndex = side, !animated {
                break
            }
            saveVisible(side)
        case .animate:
            break
        }
              
        var nonAnimatedItems: [(Int, TableRowItem)] = []
        var animatedItems: [(Int, TableRowItem)] = []
        var anchoredItem: (Int, TableRowItem)?

//        var animated: Bool = transition.animated
//        if case let .none(interface) = transition.state, interface != nil {
//            animated = true
//        }
        for (index,item) in updated {
            var animated: Bool
            animated = (visibleRange.indexIn(index) || !transition.animateVisibleOnly)
            if case .saveVisible = state {
                animated = transition.animated
            } else if case .none(nil) = state {
                animated = transition.animated
            }
            if settlesResort {
                animated = false
            }
            if let resizeAnchor = resizeAnchor, resizeAnchor.stableId == item.stableId {
                if resizeAnchor.animated {
                    anchoredItem = (index, item)
                    continue
                }
                animated = false
            }
            if animated {
                animatedItems.append((index, item))
            } else {
                nonAnimatedItems.append((index, item))
            }
        }
        
        listhash.removeAll(keepingCapacity: true)
        for item in list {
            listhash[item.stableId] = item
        }
        
        let visible = self.visibleItems()

        if !groupInOne {
            self.beginTableUpdates()
        }
        for (index, item) in nonAnimatedItems {
            replace(item: item, at: index, animated: false)
        }
        if let (index, item) = anchoredItem {
            replaceAnchored(item: item, at: index)
        }
        if !groupInOne {
            self.endTableUpdates()
        }
        if !tableView.isFlipped, !nonAnimatedItems.isEmpty {
            switch transition.state {
            case .none, .top:
                saveScrollState(visible)
            default:
                break
            }
        }

       // self.beginTableUpdates()
        for (index, item) in animatedItems {
            replace(item: item, at: index, animated: true)
        }
       
        if groupInOne {
            self.tableView.endUpdates()
        }
        
        self.endUpdates()

        if case let .none(animation) = state, !oldEmpty {
            let result = animation?.animate(table: self, documentOffset: documentOffset, added: inserted.map { $0.0 }, removed: removed.map { $0.1 }, previousRange: visibleRange)
            if let result, result.isEmpty, !transition.isEmpty, contentView.bounds.minY > 0 {
                saveVisible(.lower)
            }
        }

        if case let .saveVisible(side, animated) = state, case .aroundIndex = side, !animated {
            saveVisible(side)
        }

        if let resizeAnchor = resizeAnchor {
            apply(resizeAnchor)
        }
        
        
        self.updatedItems?(self.list)
        
//        self.reflectScrolledClipView(self.clipView)
//        self.tableView.tile()

        if oldEmpty != isEmpty || first {
            updateEmpties(animated: !first)
        }
        
        if let searchState = transition.searchState {
            
//            if let scrollView = self.enclosingScrollView {
//                scrollView.tile()
//                scrollView.reflectScrolledClipView(scrollView.contentView)
//            }
//
            if self.searchView == nil {
                self.searchView = TableSearchView(frame: NSMakeRect(0, -50, frame.width, 50))
                addSubview(self.searchView!)
            }
            guard let searchView = self.searchView else {
                return true
            }
            switch searchState {
            case let .none(updateState):
                searchView.change(pos: NSMakePoint(0, -searchView.frame.height), animated: true)
                searchView.searchView.cancel(true)
                
                searchView.searchView.searchInteractions = SearchInteractions({ state, _ in
                    updateState(state)
                }, { state in
                    updateState(state)
                })
                updateState(nil)
                currentSearchState = nil
                firstSearchAppear = true
            case let .visible(data):
                searchView.change(pos: NSZeroPoint, animated: true)
                if firstSearchAppear {
                    searchView.applySearchResponder()
                }
                firstSearchAppear = false
                searchView.updateDatas(data)
                
                searchView.searchView.searchInteractions = SearchInteractions({ state, _ in
                    data.updateState(state)
                }, { state in
                    data.updateState(state)
                })
                
                let searchState: SearchState = .init(state: searchView.searchView.state, request: searchView.searchView.query)
                
                if searchState != self.currentSearchState {
                    self.currentSearchState = searchState
                    data.updateState(searchState)
                }
            }
        } else {
            self.searchView?.removeFromSuperview()
            self.searchView = nil
        }
        
        first = false
        performScrollEvent(transition.animated)
        updateStickAfterScroll(transition.animated || (transition.state.animated || transition.state.isNone))
        return true
    }
    
    private struct PendingResizeAnchor {
        let stableId: AnyHashable
        let anchor: TableRowResizeAnchor
        let oldRect: NSRect
        let offset: CGFloat
        let animated: Bool
        let presented: [AnyHashable: CGFloat]
        let presentedHeight: CGFloat?
    }

    private static let resizeAnimationKey = "tableRowResize.position"
    fileprivate var resizeKeepRect: NSRect?
    private var resizeKeepToken = 0

    private static let resizeBoundsKey = "tableRowResize.bounds"

    private func presentedEdge(_ view: NSView, top: Bool) -> CGFloat {
        var frame = view.layer?.presentation()?.frame ?? view.frame
        if let layer = view.layer, let animation = layer.animation(forKey: TableView.resizeAnimationKey), layer.animationKeys()?.count == 1 {
            frame = view.frame.offsetBy(dx: 0, dy: TableRowResizeAnchor.inflightOffset(animation, now: layer.convertTime(CACurrentMediaTime(), from: nil)))
        }
        let clip = clipView.layer?.presentation()?.bounds.minY ?? clipView.bounds.minY
        return (top != tableView.isFlipped ? frame.maxY : frame.minY) - clip
    }

    private func resizeAnchor(for transition: TableUpdateTransition) -> PendingResizeAnchor? {
        switch transition.state {
        case let .none(interface):
            if interface != nil, !transition.inserted.isEmpty || !transition.deleted.isEmpty {
                return nil
            }
        case let .saveVisible(side, _):
            if case .aroundIndex = side {
                return nil
            }
        default:
            return nil
        }
        for (_, item) in transition.updated {
            guard let previous = self.item(stableId: item.stableId), let anchor = item.resizeAnchor(previous: previous) else {
                continue
            }
            let oldRect = rectOf(item: previous)
            guard oldRect.height > 0 else {
                continue
            }
            var animated = transition.animated
            if case let .none(interface) = transition.state, interface != nil {
                animated = true
            }
            if animated {
                if let view = viewNecessary(at: previous.index), view.isKind(of: item.viewClass()) {
                    animated = view.canAnimateUpdate(item)
                } else {
                    animated = false
                }
            }
            var presented: [AnyHashable: CGFloat] = [:]
            var presentedHeight: CGFloat?
            if animated {
                let range = tableView.rows(in: tableView.visibleRect)
                for index in range.location ..< range.location + range.length {
                    if let view = viewNecessary(at: index), let row = self.optionalItem(at: index) {
                        presented[row.stableId] = presentedEdge(view, top: row.stableId == item.stableId ? tableView.isFlipped : false)
                        if row.stableId == item.stableId {
                            presentedHeight = view.layer?.presentation()?.bounds.height ?? view.frame.height
                        }
                    }
                }
            }
            let offset = clipView.destination?.y ?? clipView.bounds.minY
            return PendingResizeAnchor(stableId: item.stableId, anchor: anchor, oldRect: oldRect, offset: offset, animated: animated, presented: presented, presentedHeight: presentedHeight)
        }
        return nil
    }

    private func replaceAnchored(item: TableRowItem, at index: Int) {
        guard index < count else {
            return
        }
        let prev = list[index]
        listhash.removeValue(forKey: prev.stableId)
        list[index] = item
        listhash[item.stableId] = item
        item.table = self
        item._index = index
        if frame.width > 0 {
            if item.premeasuredWidth != frame.width {
                _ = item.makeSize(frame.width, oldWidth: prev.oldWidth)
            }
            item.premeasuredWidth = nil
        }
        guard let view = viewNecessary(at: index), view.isKind(of: item.viewClass()) else {
            reloadData(row: index, animated: false)
            return
        }
        view.set(item: item, animated: true)
        view.updateLayout(size: NSMakeSize(frame.width, item.heightValue), transition: .animated(duration: duration, curve: .easeOut))
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.timingFunction = nil
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: index))
    }

    private func apply(_ pending: PendingResizeAnchor) {
        guard let item = self.item(stableId: pending.stableId) else {
            return
        }
        let newRect = rectOf(item: item)
        let height = clipView.bounds.height
        let minimum: CGFloat = tableView.isFlipped ? -contentInsets.top : 0
        let maximum = max(minimum, documentSize.height - height)
        let target = TableRowResizeAnchor.offset(anchor: pending.anchor, oldRect: pending.oldRect, newRect: newRect, offset: pending.offset, viewport: height, flipped: tableView.isFlipped, range: minimum ... maximum)
        let transition: ContainedViewLayoutTransition = pending.animated ? .animated(duration: duration, curve: .easeOut) : .immediate
        item.view?.applyResizeAnchor(pending.anchor, transition: transition)
        let current = clipView.destination?.y ?? clipView.bounds.minY
        if abs(target - current) > 0.25 || clipView.isAnimateScrolling {
            clipView.updateBounds(to: NSMakePoint(0, target), cancel: pending.animated)
        }
        guard pending.animated else {
            return
        }
        resizeKeepToken &+= 1
        let token = resizeKeepToken
        let afterShift = newRect.maxY - pending.oldRect.maxY
        let visibleNow = NSMakeRect(0, target, frame.width, height)
        let visibleBefore = NSMakeRect(0, pending.offset, frame.width, height)
        resizeKeepRect = visibleNow.union(visibleBefore).union(visibleBefore.offsetBy(dx: 0, dy: afterShift))
        let rows = tableView.rows(in: resizeKeepRect!)
        CATransaction.begin()
        for index in rows.location ..< rows.location + rows.length {
            guard let row = optionalItem(at: index), let view = viewNecessary(at: index, makeIfNecessary: true), let layer = view.layer else {
                continue
            }
            let isAnchored = row.stableId == pending.stableId
            let model = rectOf(index: index)
            let edge = isAnchored || !tableView.isFlipped ? model.minY : model.maxY
            let now = edge - target
            let old: CGFloat
            if let presented = pending.presented[row.stableId] {
                old = presented
            } else {
                old = edge - (index > item.index ? afterShift : 0) - pending.offset
            }
            let delta = old - now
            layer.removeAnimation(forKey: TableView.resizeAnimationKey)
            if isAnchored {
                layer.removeAnimation(forKey: TableView.resizeBoundsKey)
                let from = pending.presentedHeight ?? pending.oldRect.height
                if abs(from - layer.bounds.height) > 0.25 {
                    let bounds = CABasicAnimation(keyPath: "bounds")
                    bounds.fromValue = NSValue(rect: NSMakeRect(layer.bounds.minX, layer.bounds.minY, layer.bounds.width, from))
                    bounds.toValue = NSValue(rect: layer.bounds)
                    bounds.duration = duration
                    bounds.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    bounds.isRemovedOnCompletion = true
                    layer.add(bounds, forKey: TableView.resizeBoundsKey)
                }
            }
            guard abs(delta) > 0.25 else {
                continue
            }
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: NSMakePoint(0, delta))
            animation.toValue = NSValue(point: .zero)
            animation.isAdditive = true
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation.isRemovedOnCompletion = true
            layer.add(animation, forKey: TableView.resizeAnimationKey)
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self = self, self.resizeKeepToken == token else {
                return
            }
            self.resizeKeepRect = nil
            self.tableView.needsLayout = true
        }
    }

    public func updateEmpties(animated: Bool = false) {
        if let emptyItem = emptyItem {
            if isEmpty {
                if let empt = emptyView, !empt.isKind(of: emptyItem.viewClass()) || empt.item != emptyItem {
                    emptyView?.removeFromSuperview()
                    emptyView = nil
                }
                if emptyView == nil {
                    let vz = emptyItem.viewClass() as! TableRowView.Type
                    emptyView = vz.init(frame:bounds)
                    emptyView?.identifier = identifier
                    if animated, let emptyView = emptyView {
                        emptyView.layer?.animateAlpha(from: 0, to: 1, duration: duration)
                    }
                }
                
                if emptyView?.superview == nil {
                    addSubview(emptyView!)
                }
                
                if let emptyView = emptyView, let superview = superview {
                    emptyView.frame = bounds
                    emptyView.centerX(y: superview.frame.height - emptyView.frame.height)
                    
                    if animated {
                        emptyView.layer?.animatePosition(from: emptyView.frame.origin.offsetBy(dx: 0, dy: 25), to: emptyView.frame.origin)
                    }
                }
               
                
                emptyView?.set(item: emptyItem)
                emptyView?.needsLayout = true
                
                tableView._change(opacity: 0, animated: animated)
            } else {
                if let emptyView = emptyView {
                    self.emptyView = nil
                    if animated {
                        emptyView.layer?.animateAlpha(from: 1, to: 0, duration: duration, removeOnCompletion: false, completion: { [weak emptyView] completed in
                            emptyView?.removeFromSuperview()
                        })
                        if animated {
                            emptyView.layer?.animatePosition(from: emptyView.frame.origin, to: emptyView.frame.origin.offsetBy(dx: 0, dy: 25), removeOnCompletion: false)
                        }
                    } else {
                        emptyView.removeFromSuperview()
                    }
                }
                tableView._change(opacity: 1, animated: animated)
            }
        }
        
    }
    
    
    public func replace(item:TableRowItem, at index:Int, animated:Bool) {
        if index < count {
            let prev = list[index]
            listhash.removeValue(forKey: list[index].stableId)
            list[index] = item
            listhash[item.stableId] = item
            item.table = self
            item._index = index
            if frame.width > 0 {
                if item.premeasuredWidth != frame.width {
                    _ = item.makeSize(frame.width, oldWidth: prev.oldWidth)
                }
                item.premeasuredWidth = nil
            }
            reloadData(row: index, animated: animated, presentAsNew: false)
        }
    }

    public func contentInteractionView(for stableId: AnyHashable, animateIn: Bool) -> NSView? {
        
        if let supplyment = supplyment {
            return supplyment.contentInteractionView(for: stableId, animateIn: animateIn)
        }
        var item = self.item(stableId: stableId)
        if item == nil {
            if let groupStableId = delegate?.findGroupStableId(for: stableId) {
                item = self.item(stableId: groupStableId)
            }
        }
        
        if let item = item {
            let view = viewNecessary(at:item.index)
            if let view = view, !NSIsEmptyRect(view.visibleRect) {
                return view.interactionContentView(for: stableId, animateIn: animateIn)
            }
        }
        return nil
    }
    
    public func interactionControllerDidFinishAnimation(interactive: Bool, for stableId: AnyHashable) {
        
        if let supplyment = supplyment {
            return supplyment.interactionControllerDidFinishAnimation(interactive: interactive, for: stableId)
        }
        
        var item = self.item(stableId: stableId)
        
        if item == nil {
            if let groupStableId = delegate?.findGroupStableId(for: stableId) {
                item = self.item(stableId: groupStableId)
            }
        }
        
        if let item = item {
            let view = viewNecessary(at:item.index)
            if let view = view, !NSIsEmptyRect(view.visibleRect) {
                view.interactionControllerDidFinishAnimation(interactive: interactive, innerId: stableId)
            }
        }
    }
    
    public func addAccesoryOnCopiedView(for stableId: AnyHashable, view: NSView) {
        
        if let supplyment = supplyment {
            return supplyment.addAccesoryOnCopiedView(for: stableId, view: view)
        }
        
        var item = self.item(stableId: stableId)

        if item == nil {
            if let groupStableId = delegate?.findGroupStableId(for: stableId) {
                item = self.item(stableId: groupStableId)
            }
        }
        
        if let item = item {
            let rowView = viewNecessary(at:item.index)
            if let rowView = rowView, !NSIsEmptyRect(view.visibleRect) {
                rowView.addAccesoryOnCopiedView(innerId: stableId, view: view)
            }
        }
    }
    
    public func videoTimebase(for stableId: AnyHashable) -> CMTimebase? {
        var item = self.item(stableId: stableId)
        
        if item == nil {
            if let groupStableId = delegate?.findGroupStableId(for: stableId) {
                item = self.item(stableId: groupStableId)
            }
        }
        
        if let item = item {
            let view = viewNecessary(at:item.index)
            if let view = view, !NSIsEmptyRect(view.visibleRect) {
                return view.videoTimebase(for: stableId)
            }
            
        }
        
        return nil
    }
    
    public func applyTimebase(for stableId: AnyHashable, timebase: CMTimebase?) {
        
        if let supplyment = supplyment {
            return supplyment.applyTimebase(for: stableId, timebase: timebase)
        }
        
        var item = self.item(stableId: stableId)
        
        if item == nil {
            if let groupStableId = delegate?.findGroupStableId(for: stableId) {
                item = self.item(stableId: groupStableId)
            }
        }
        
        if let item = item {
            let view = viewNecessary(at:item.index)
            if let view = view, !NSIsEmptyRect(view.visibleRect) {
                view.applyTimebase(for: stableId, timebase: timebase)
            }
        }
        
    }

    func selectRow(index: Int) {
        if self.count > index {
            _ = self.select(item: self.item(at: index), byClick:true)
        }
    }
    
    func longAction(index: Int) {
        if self.count > index {
            _ = self.delegate?.longSelect(row: index, item: self.list[index])
        }
    }
    
    public override func change(size: NSSize, animated: Bool, _ save:Bool = true, removeOnCompletion: Bool = true, duration:Double = 0.2, timingFunction: CAMediaTimingFunctionName = CAMediaTimingFunctionName.easeOut, completion:((Bool)->Void)? = nil) {
        
        
        if animated {

            if !tableView.isFlipped {
                
                if self.frame.size != size {
                    let bounds = self.layer?.presentation()?.bounds ?? self.bounds
                    let y = (size.height - bounds.height)

                    self.layer?.animateBoundsOriginYAdditive(from: -y, to: 0, duration: duration)

                    
                    if let layer = contentView.layer {
                        let animation = layer.makeAnimation(from: NSNumber(value: -y), to: NSNumber(value: 0), keyPath: "bounds.size.height", timingFunction: timingFunction, duration: duration, additive: true)
                        layer.add(animation, forKey: "height")
                    }
                }
                                
                self.updateStickAfterScroll(animated)
                return
            }
        }
        
        super.change(size: size, animated: animated, removeOnCompletion: removeOnCompletion, duration: duration, timingFunction: timingFunction, completion: completion)
        self.updateStickAfterScroll(animated)
    }
        
    public func scroll(to state:TableScrollState, inset:NSEdgeInsets = NSEdgeInsets(), timingFunction: CAMediaTimingFunctionName = .spring, toVisible:Bool = false, ignoreLayerAnimation: Bool = false, previousDocumentOffset: CGPoint? = nil, completion: @escaping(Bool)->Void = { _ in }) {
        
        var rowRect:NSRect = bounds
        let documentOffset = previousDocumentOffset
        
        let findItem:(AnyHashable)->TableRowItem? = { [weak self] stableId in
            var item: TableRowItem? = self?.item(stableId: stableId)
            if item == nil {
                if let groupStableId = self?.delegate?.findGroupStableId(for: stableId) {
                    item = self?.item(stableId: groupStableId)
                }
            }
            return item
        }
        
        var item:TableRowItem?
        var targetStableId: AnyHashable?
        var animate:Bool = false
        var focus: TableScrollFocus = .init(focus: false)
        var relativeInset: CGFloat = 0
        var innerId: AnyHashable? = nil
        var addition: CGFloat = 0
        switch state {
        case let .center(stableId, _innerId, _animate, _focus, _inset):
            item = findItem(stableId)
            targetStableId = stableId
            animate = _animate
            relativeInset = _inset
            focus = _focus
            innerId = _innerId
        case let .bottom(stableId, _innerId, _animate, _focus, _inset):
            item = findItem(stableId)
            targetStableId = stableId
            animate = _animate
            relativeInset = _inset
            focus = _focus
            innerId = _innerId
        case let .top(stableId, _innerId, _animate, _focus, _inset):
            item = findItem(stableId)
            targetStableId = stableId
            animate = _animate
            relativeInset = _inset
            focus = _focus
            innerId = _innerId
            addition = -contentInsets.top
        case let .down(_animate):
            animate = _animate
            if !tableView.isFlipped {
                rowRect.origin = NSZeroPoint
            } else {
                rowRect.origin = NSMakePoint(0, max(0, documentSize.height - frame.height + (self is HorizontalTableView ? 0 : contentInsets.bottom)))
            }
        case let .up(_animate):
            animate = _animate
            if !tableView.isFlipped {
                rowRect.origin = NSMakePoint(0, max(documentSize.height,frame.height))
            } else {
               rowRect.origin = NSZeroPoint
            }
        case let .upOffset(_animate, offset):
            animate = _animate
            if !tableView.isFlipped {
                rowRect.origin = NSMakePoint(0, max(documentSize.height,frame.height))
            } else {
                rowRect.origin = NSMakePoint(0,  -contentInsets.top)
            }
            relativeInset = offset
        default:
            fatalError("for scroll to item, you can use only .top, center, .bottom enumeration")
        }
        
        innerId = innerId ?? focus.innerId.flatMap(AnyHashable.init)
        
        let bottomInset = self.bottomInset != 0 ? (self.bottomInset) : 0
        let contentBottomInset: CGFloat = tableView.isFlipped && !(self is HorizontalTableView) ? contentInsets.bottom : 0
        let height:CGFloat = self is HorizontalTableView ? frame.width : max(0, frame.height - contentBottomInset)

        let documentHeight = documentSize.height
        
        if documentHeight < height {
            if focus.focus, let targetStableId = targetStableId {
                DispatchQueue.main.async { [weak self] in
                    if let item = findItem(targetStableId), let view = self?.viewNecessary(at: item.index, makeIfNecessary: true) {
                        view.focusAnimation(innerId, text: focus.string, range: focus.range)
                        focus.action?(view.interactableView)
                    }
                }
            }
            completion(item != nil)
            return
        }
        
        if let item = item {
            rowRect = self.rectOf(item: item)
            var state = state
            if case let .center(id, innerId, animated, focus, inset) = state, rowRect.height > height {
                state = .top(id: id, innerId: innerId, animated: animated, focus: focus, inset: inset)
            }
            switch state {
            case .bottom:
                if tableView.isFlipped {
                    rowRect.origin.y -= (height - rowRect.height) - bottomInset
                }
            case .top:
               // break
                if !tableView.isFlipped {
                    rowRect.origin.y -= (height - rowRect.height) - bottomInset - contentInsets.top
                }
            case .center:
                if !tableView.isFlipped {
                    rowRect.origin.y -= floorToScreenPixels(backingScaleFactor, (height - rowRect.height) / 2.0) - bottomInset
                } else {
                    
                    if rowRect.maxY > height/2.0 {
                        rowRect.origin.y -= floorToScreenPixels(backingScaleFactor, (height - rowRect.height) / 2.0) - bottomInset
                    } else {
                        rowRect.origin.y = 0
                    }
                    

                   // fatalError("not implemented")
                }
    
            default:
                fatalError("not implemented")
            }
            
            if toVisible  {
                let view = self.viewNecessary(at: item.index)
                if let view = view, view.visibleRect.height == item.heightValue, contentBottomInset == 0 || self.rectOf(item: item).maxY <= clipView.bounds.maxY - contentBottomInset {
                    if focus.focus {
                        DispatchQueue.main.async {
                            view.focusAnimation(innerId, text: focus.string, range: focus.range)
                            focus.action?(view.interactableView)
                        }
                    }
                    completion(true)
                    return
                }
            }
        }
        
        rowRect.origin.y = round(min(max(rowRect.minY + relativeInset, (!tableView.isFlipped ? 0 : -contentInsets.top)), documentSize.height - height) + inset.top)
        
      
        
        if self.tableView.isFlipped {
            rowRect.origin.y = min(rowRect.origin.y, documentSize.height - clipView.bounds.height + contentBottomInset)
        }
        
        if let string = focus.string, let item {
            let inset = item.inset(for: string, range: focus.range)
            rowRect.origin.y -= inset
        }
        
        if clipView.bounds.minY != rowRect.minY {
            
            var applied = false
            let scrollListener = TableScrollListener({ [weak self, weak item] position in
                if let item = item, !applied {
                    DispatchQueue.main.async {
                        if let view = self?.viewNecessary(at: item.index), view.visibleRect.height > 10 {
                            applied = true
                            if focus.focus {
                                view.focusAnimation(innerId, text: focus.string, range: focus.range)
                            }
                        }
                    }
                }
            })
            
            if let pending = pendingAnimatedScrollListener {
                removeScroll(listener: pending)
                pendingAnimatedScrollListener = nil
            }
            addScroll(listener: scrollListener)
            
            let bounds = NSMakeRect(0, rowRect.minY + addition, clipView.bounds.width, clipView.bounds.height)
                        
            if animate {
                pendingAnimatedScrollListener = scrollListener
                clipView.scroll(to: bounds.origin, animated: animate, completion: { [weak self, weak item] completed in
                    if let `self` = self {
                        if completed {
                            scrollListener.handler(self.scrollPosition().current)
                        }
                        self.removeScroll(listener: scrollListener)
                        if self.pendingAnimatedScrollListener?.uniqueId == scrollListener.uniqueId {
                            self.pendingAnimatedScrollListener = nil
                        }
                        completion(completed)
                        self.scrollDidChangedBounds()
                        if completed {
                            self.notifyScrollHandlers()
                        }
                        if completed, let action = focus.action, let view = (item ?? targetStableId.flatMap(findItem))?.view?.interactableView {
                            action(view)
                        }
                    }
                })
            } else {
                self.clipView.updateBounds(to: bounds.origin)
                removeScroll(listener: scrollListener)
                scrollListener.handler(self.scrollPosition().current)
            }
        } else {
            if let targetStableId = targetStableId, item != nil {
                if focus.focus {
                    DispatchQueue.main.async { [weak self] in
                        if let item = findItem(targetStableId), let view = self?.viewNecessary(at: item.index, makeIfNecessary: true) {
                            view.focusAnimation(innerId, text: focus.string, range: focus.range)
                            focus.action?(view.interactableView)
                        }
                    }
                }
                completion(true)
            } else {
                if let documentOffset = documentOffset, documentOffset != clipView.documentOffset {
                    clipView.scroll(to: documentOffset, animated: false)
                    clipView.scroll(to: rowRect.origin, animated: animate)
                }
            }
        }
        
    }
    
    open override func accessibilityParent() -> Any? {
        return TGUIKitAccessibility.parent(of: self, default: { super.accessibilityParent() })
    }
    
    open override func setFrameSize(_ newSize: NSSize) {
        let visible = visibleItems()
        let oldWidth = frame.width
        let oldHeight = frame.height
        super.setFrameSize(newSize)
       
        if newSize.width > 0 || newSize.height > 0 {
            if oldWidth != frame.width, newSize.width > 0 && newSize.height > 0 {
                self.layoutIfNeeded(with: self.visibleRows(), oldWidth: oldWidth)
            } else if oldHeight != frame.height {
                self.reloadHeightItems()
            }
        }
        
        //updateStickAfterScroll(false)
        if oldWidth != newSize.width, !inLiveResize && newSize.width > 0 && newSize.height > 0 {
            saveScrollState(visible)
        }
    }
    
    public func setScrollHandler(_ handler: @escaping (_ scrollPosition:ScrollPosition) ->Void) -> Void {
        
        scrollHandler = handler
        
    }
    
    
    public func enumerateItems(with callback:(TableRowItem)->Bool) {
        for item in list {
            if !callback(item) {
                break
            }
        }
    }
    
    public func enumerateItems(reversed: Bool = false, with callback:(TableRowItem)->Bool) {
        if reversed {
            for item in list.reversed() {
                if !callback(item) {
                    break
                }
            }
        } else {
            for item in list {
                if !callback(item) {
                    break
                }
            }
        }
    }
    
    public func enumerateVisibleItems(reversed: Bool = false, inset: CGFloat = 0, with callback: (TableRowItem) -> Bool) {
        let visible = visibleRows(inset)
        guard visible.length > 0, visible.location >= 0 else { return }
        let (sum, overflow) = visible.location.addingReportingOverflow(visible.length)
        let end = overflow ? Int.max : sum
        if reversed {
            let count = list.count
            guard visible.location < count else { return }
            for index in (visible.location..<min(end, count)).reversed() {
                guard let item = optionalItem(at: index), callback(item) else { break }
            }
        } else {
            for index in visible.location..<end {
                guard let item = optionalItem(at: index), callback(item) else { break }
            }
        }
    }

    public func enumerateViews(with callback:(TableRowView)->Bool) {
        for index in 0 ..< list.count {
            if let view = viewNecessary(at: index) {
                if !callback(view) {
                    break
                }
            }
        }
    }
    
    public func enumerateVisibleViews(with callback:(TableRowView)->Void, force: Bool = false) {
        let visibleRows = self.visibleRows()
        for index in visibleRows.location ..< visibleRows.location + visibleRows.length {
            if let view = viewNecessary(at: index, makeIfNecessary: force) {
                callback(view)
            }
        }
    }
    
    public func performScrollEvent(_ animated: Bool = false) -> Void {
        self.nextScrollEventIsAnimated = animated
        self.resetScroll(visibleRows())
        //NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: self.contentView)
    }
    
    deinit {
        mergeDisposable.dispose()
        stickTimeoutDisposable.dispose()
        stickTimeoutTimer?.invalidate()
        secondaryStickTimeoutDisposable.dispose()
        removeScrollObservers()
    }
    
    
}

final class TableRowAccessibilityElement: NSAccessibilityElement {
    private weak var tableView: TGFlipableTableView?
    weak var item: TableRowItem?

    init(table: TGFlipableTableView, item: TableRowItem) {
        self.tableView = table
        self.item = item
        super.init()
    }

    private var row: Int? {
        guard let item = item, let tableView = tableView, let table = tableView.table else {
            return nil
        }
        let index = table.index(of: item)
        return index
    }

    override func isAccessibilityElement() -> Bool {
        return item?.accessibilityHasContent == true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return item?.accessibilityRole ?? .group
    }

    override func accessibilityLabel() -> String? {
        return item?.accessibilityLabel
    }

    override func accessibilityValue() -> Any? {
        guard let item = item else {
            return nil
        }
        if let value = item.accessibilityValue {
            return value
        }
        if let toggle = item.accessibilityToggleState {
            return NSNumber(value: toggle ? 1 : 0)
        }
        return item.accessibilityRole == .staticText ? item.accessibilityLabel : nil
    }

    override func accessibilityHelp() -> String? {
        return item?.accessibilityHelp
    }

    override func isAccessibilityEnabled() -> Bool {
        return item?.accessibilityIsEnabled ?? false
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        return item?.accessibilityCustomActions
    }

    override func accessibilityParent() -> Any? {
        return tableView
    }

    override func accessibilityIndex() -> Int {
        return row ?? 0
    }

    override func accessibilityFrame() -> NSRect {
        guard let tableView = tableView, let row = row, let window = tableView.window else {
            return .zero
        }
        let rect = tableView.convert(tableView.rect(ofRow: row), to: nil)
        return window.convertToScreen(rect)
    }

    override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        if accessibilityFocused {
            scrollToVisible()
        }
        super.setAccessibilityFocused(accessibilityFocused)
    }

    override func accessibilityPerformPress() -> Bool {
        scrollToVisible()
        return item?.accessibilityPerformPress() ?? false
    }

    override func accessibilityActionNames() -> [NSAccessibility.Action] {
        return [.press, .showMenu, NSAccessibility.Action(rawValue: "AXScrollToVisible")]
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let tableView = tableView, let row = row else {
            return false
        }
        tableView.scrollRowToVisible(row)
        tableView.layoutSubtreeIfNeeded()
        guard let view = tableView.rowView(atRow: row, makeIfNecessary: false) as? TableRowView else {
            return false
        }
        return view.accessibilityPerformShowMenu()
    }

    override func accessibilityPerformAction(_ action: NSAccessibility.Action) {
        if action.rawValue == "AXScrollToVisible" {
            scrollToVisible()
        } else if action == .press {
            _ = accessibilityPerformPress()
        } else if action == .showMenu {
            _ = accessibilityPerformShowMenu()
        }
    }

    private func scrollToVisible() {
        guard let tableView = tableView, let row = row else {
            return
        }
        tableView.scrollRowToVisible(row)
    }
}
