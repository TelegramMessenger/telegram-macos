import Foundation
import Cocoa
import TGUIKit
import GeneralRows

protocol StorageUsageBlockControlling: ViewController {
    var mediaView: View { get }
    var mainTable: TableView? { get }
    var currentMainTableView: ((TableView?, Bool, Bool) -> Void)? { get set }
    var unableToHide: Bool { get }
}

final class StorageUsageTableView: TableView {
    var prepareForResize: (() -> (() -> Void))?
    private(set) var isResizing = false

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize != frame.size, newSize.width > 0, newSize.height > 0, !isResizing else {
            super.setFrameSize(newSize)
            return
        }
        let visible = visibleItems()
        isResizing = true
        defer { isResizing = false }
        let restore = prepareForResize?()
        let resizedBothDimensions = newSize.width != frame.width && newSize.height != frame.height
        super.setFrameSize(newSize)
        if resizedBothDimensions {
            enumerateItems { item in
                if item.reloadOnTableHeightChanged {
                    self.noteHeightOfRow(item.index, false)
                }
                return true
            }
        }
        saveScrollState(visible)
        restore?()
    }
}

class StorageUsageBlockItem: GeneralRowItem {

    static var topInset: CGFloat {
        return 64
    }

    fileprivate let listener: TableScrollListener
    fileprivate let controller: any StorageUsageBlockControlling
    fileprivate let isMediaVisible: Bool
    init(_ initialSize: NSSize, stableId: AnyHashable, controller: any StorageUsageBlockControlling, isVisible: Bool, viewType: GeneralViewType) {
        self.controller = controller
        self.isMediaVisible = isVisible
        self.listener = TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { _ in })
        super.init(initialSize, height: initialSize.height, stableId: stableId, viewType: viewType, inset: NSEdgeInsets())
    }

    deinit {
        self.table?.removeScroll(listener: self.listener)
    }

    override var instantlyResize: Bool {
        return true
    }

    override var reloadOnTableHeightChanged: Bool {
        return true
    }

    override var accessibilityIsSpacer: Bool {
        return true
    }

    override var height: CGFloat {
        if !isMediaVisible {
            return 1
        } else {
            return max(1, (table?.frame.height ?? initialSize.height) - Self.topInset)
        }
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        return true
    }
    
    override func viewClass() -> AnyClass {
        return StorageUsageBlockItemView.self
    }
}


private final class StorageUsageBlockItemView : TableRowView {

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    private func updateOrigin() {
        guard let item = item as? StorageUsageBlockItem, let table = item.table, table.item(stableId: item.stableId) === item else {
            return
        }
        item.controller.view.frame = NSMakeRect(0, max(0, table.rectOf(item: item).minY), self.frame.width, item.height)
    }

    override func layout() {
        super.layout()
        updateOrigin()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        updateOrigin()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()

        guard superview != nil, let item = item as? StorageUsageBlockItem, item.table?.item(stableId: item.stableId) === item else {
            return
        }

        if item.controller.view != item.table?.documentView?.subviews.last {
            item.controller.view.removeFromSuperview()
            item.table?.documentView?.addSubview(item.controller.view)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let item = item as? StorageUsageBlockItem else {
            super.scrollWheel(with: event)
            return
        }
        item.controller.view.enclosingScrollView?.scrollWheel(with: event)
    }

    private var scrollInner = false

    override func set(item: TableRowItem, animated: Bool = false) {
        guard let item = item as? StorageUsageBlockItem, item.table?.item(stableId: item.stableId) === item else {
            return
        }
        let previousItem = self.item
        if previousItem !== item, let previousItem = previousItem as? StorageUsageBlockItem {
            previousItem.table?.removeScroll(listener: previousItem.listener)
        }
        super.set(item: item, animated: animated)

        if previousItem === item {
            updateOrigin()
            return
        }

        let stableId = item.stableId
        let listener = item.listener
        item.table?.updatedItems = { [weak self, weak table = item.table, weak controller = item.controller] items in
            guard items.contains(where: { $0.stableId == stableId && $0 is StorageUsageBlockItem }) else {
                table?.removeScroll(listener: listener)
                table?._scrollWillStartLiveScrolling = nil
                (table as? StorageUsageTableView)?.prepareForResize = nil
                table?.updatedItems = nil
                controller?.currentMainTableView = nil
                if let controller, controller.isLoaded() {
                    controller.mainTable?.applyExternalScroll = nil
                    if controller.mediaView.superview != nil {
                        controller.viewWillDisappear(false)
                        controller.mediaView.removeFromSuperview()
                        controller.viewDidDisappear(false)
                    }
                }
                return
            }
            self?.updateOrigin()
        }

        item.controller.bar = .init(height: 0)
        item.controller._frameRect = bounds

        var scrollingInMediaTable: Bool = false


        if item.isMediaVisible {

            var previousY = (item.table?.liveDocumentOffset.y ?? 0) + StorageUsageBlockItem.topInset

            (item.table as? StorageUsageTableView)?.prepareForResize = { [weak self, weak item] in
                guard let self, let item, let table = item.table, table.item(stableId: item.stableId) === item else {
                    return {}
                }
                let topInset = StorageUsageBlockItem.topInset
                let wasPinned = table.liveDocumentOffset.y + topInset >= table.rectOf(item: item).minY
                let mediaTable = item.controller.mainTable
                let mediaOffset = mediaTable?.liveDocumentOffset ?? .zero
                return { [weak self, weak item, weak table, weak mediaTable] in
                    guard let self, let item, let table, table.item(stableId: item.stableId) === item else {
                        return
                    }
                    if wasPinned {
                        let offset = table.rectOf(item: item).minY - topInset
                        table.clipView.scroll(to: NSMakePoint(0, offset), animated: false)
                        table.reflectScrolledClipView(table.clipView)
                    }
                    mediaTable?.clipView.scroll(to: mediaOffset)
                    if let mediaTable {
                        mediaTable.reflectScrolledClipView(mediaTable.clipView)
                    }
                    scrollingInMediaTable = (mediaTable?.liveDocumentOffset.y ?? 0) > 0
                    self.scrollInner = wasPinned || scrollingInMediaTable
                    previousY = table.liveDocumentOffset.y + topInset
                    self.updateOrigin()
                }
            }

            item.listener.handler = { [weak self, weak item] _ in
                guard let `self` = self, let table = item?.table, let item = item else {
                    return
                }

                guard let item = table.item(stableId: item.stableId) as? StorageUsageBlockItem else {
                    return
                }

                if (table as? StorageUsageTableView)?.isResizing == true {
                    return
                }

                let topInset = StorageUsageBlockItem.topInset
                let itemY = table.rectOf(item: item).minY
                scrollInner = table.documentOffset.y + topInset >= itemY
                let mediaTable = item.controller.mainTable
                if let mediaTable = mediaTable {

                    let offset = table.documentOffset.y + topInset - itemY
                    var updated = max(0, offset)
                    if mediaTable.documentSize.height <= item.height, updated > 0 {
                        updated = max(updated, 0)
                    }
                    if !scrollingInMediaTable, updated != mediaTable.documentOffset.y {
                        mediaTable.clipView.scroll(to: NSMakePoint(0, updated))
                        mediaTable.reflectScrolledClipView(mediaTable.clipView)
                    }
                    if scrollInner {

                    } else {
                        if mediaTable.documentOffset.y > 0 {
                            scrollInner = true
                        }
                    }
                    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: mediaTable.clipView)

                    item.controller.view.frame = NSMakeRect(0, max(0, itemY), self.frame.width, item.height)

                    let point = item.controller.view.frame.origin

                    let currentY = table.documentOffset.y + topInset
                    if previousY != currentY {
                        if currentY >= point.y {
                            item.controller.viewWillAppear(false)
                            item.controller.viewDidAppear(false)
                        } else if previousY == point.y {
                            item.controller.viewWillDisappear(false)
                            item.controller.viewDidDisappear(false)
                        }
                    }

                    previousY = table.documentOffset.y + topInset

                }
            }

            item.table?.addScroll(listener: item.listener)

            item.table?.hasVerticalScroller = false

            item.table?._scrollWillStartLiveScrolling = {
                scrollingInMediaTable = false
            }
            item.controller.mainTable?.reloadData()
        } else {
            needsLayout = true
        }

        if item.controller.view != item.table?.documentView?.subviews.last {
            item.controller.view.removeFromSuperview()
            item.table?.documentView?.addSubview(item.controller.view)
        }
        if let table = item.table {
            item.controller.mediaView.change(pos: NSMakePoint(0, max(0, table.rectOf(item: item).minY)), animated: animated)
        }

        if item.isMediaVisible {
            item.controller.mediaView.isHidden = false
        }

        item.controller.mediaView.change(opacity: item.isMediaVisible ? 1 : 0, animated: animated, completion: { [weak item] _ in
            guard let item = item else {
                return
            }
            item.controller.mediaView.isHidden = !item.isMediaVisible
        })

        if item.isMediaVisible {
            item.controller.currentMainTableView = { [weak item, weak self] mainTable, animated, updated in
                guard let item, let table = item.table, table.item(stableId: item.stableId) === item else {
                    return
                }

                mainTable?.verticalScrollElasticity = .none

                let topInset = StorageUsageBlockItem.topInset
                if animated {
                    let frame = table.rectOf(item: item)
                    if table.liveDocumentOffset.y + topInset >= frame.minY {
                        if !updated {
                            mainTable?.scroll(to: .up(true))
                        }
                    } else if updated {
                        DispatchQueue.main.async {
                            guard let table = item.table, table.item(stableId: item.stableId) === item else {
                                return
                            }
                            table.scroll(to: .top(id: item.stableId, innerId: nil, animated: animated, focus: .init(focus: false), inset: topInset))
                        }
                    }
                }

                mainTable?.applyExternalScroll = { [weak self, weak item] event in
                    guard let `self` = self, let item = item, item.table?.item(stableId: item.stableId) === item else {
                        return false
                    }
                    if scrollInner {
                        if event.scrollingDeltaY > 0 {
                            if let tableView = item.controller.mainTable, tableView.documentOffset.y <= 0 {
                                if !item.controller.unableToHide {
                                    scrollInner = false
                                    item.table?.clipView.scroll(to: NSMakePoint(0, self.frame.minY - topInset))
                                    item.table?.scrollWheel(with: event)
                                    scrollingInMediaTable = false
                                    return true
                                }

                            }
                        }
                        scrollingInMediaTable = true
                        return false
                    } else {
                        scrollingInMediaTable = false
                        item.table?.scrollWheel(with: event)
                        return true
                    }
                }
            }
        } else {
            item.controller.currentMainTableView = nil
        }

        updateOrigin()
    }

    deinit {
    }
}
