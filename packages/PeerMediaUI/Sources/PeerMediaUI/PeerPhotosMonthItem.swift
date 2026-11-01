import Cocoa
import TelegramCore
import TelegramMediaPlayer
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramMedia
import ChatUI
import ChatModeTypes
import GalleryUI
import GeneralRows
import InlineMediaGrid
import LocalAnimations
import Localization
import MessageUtils
import TelegramContext
import TelegramTheme
import TelegramMediaUtils

public class PeerPhotosMonthItem: GeneralRowItem {
    public let items:[Message]
    fileprivate let context: any AccountContextProtocol
    private var contentHeight: CGFloat = 0
    
    fileprivate private(set) var layoutItems:[MediaCellLayoutItem] = []
    fileprivate private(set) var itemSize: NSSize = NSZeroSize
    fileprivate let chatInteraction: ChatInteraction
    fileprivate let galleryType: GalleryAppearType
    fileprivate let gallery: (Message, GalleryAppearType)->Void
    private let gap: Int
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, context: any AccountContextProtocol, chatInteraction: ChatInteraction, items: [Message], gap: Int = 0, galleryType: GalleryAppearType, gallery: @escaping(Message, GalleryAppearType)->Void) {
        self.items = items
        self.gap = gap
        self.context = context
        self.chatInteraction = chatInteraction
        self.galleryType = galleryType
        self.gallery = gallery
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: NSEdgeInsets(), fullSize: true)
    }
    
    public override var canBeAnchor: Bool {
        return true
    }
    
    public static func rowCount(blockWidth: CGFloat, viewType: GeneralViewType) -> (Int, CGFloat) {
        var rowCount:Int = 7
        var perWidth: CGFloat = 0
        while true {
            let maximum = blockWidth - viewType.innerInset.left - viewType.innerInset.right - CGFloat(rowCount * 2)
            perWidth = maximum / CGFloat(rowCount)
            if perWidth >= 90 {
                break
            } else {
                rowCount -= 1
            }
        }
        return (rowCount, perWidth)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        
        if !items.isEmpty {
            var t: time_t = time_t(TimeInterval(items[0].timestamp))
            var timeinfo: tm = tm()
            localtime_r(&t, &timeinfo)
            
            if timeinfo.tm_mon == 2 {
                var bp:Int = 0
                bp += 1
            }
            
        }
        
        let (rowCount, perWidth) = PeerPhotosMonthItem.rowCount(blockWidth: self.blockWidth, viewType: self.viewType)
        
        assert(rowCount >= 1)
                
        let itemSize = NSMakeSize(ceil(perWidth) + 2, ceil(perWidth) + 2)
        
        layoutItems.removeAll()
        let gap = min(self.gap, rowCount - 1)
        var point: CGPoint = CGPoint(x: self.viewType.innerInset.left + CGFloat(gap) * itemSize.width, y: self.viewType.innerInset.top + itemSize.height)
        for (i, message) in self.items.enumerated() {
            let viewType: MediaCell.Type
            if let file = message.anyMedia as? TelegramMediaFile {
                if file.isAnimated && file.isVideo {
                    viewType = MediaGifCell.self
                } else {
                    viewType = MediaVideoCell.self
                }
            } else {
                viewType = MediaPhotoCell.self
            }
            
            var topLeft: ImageCorner = .Corner(0)
            var topRight: ImageCorner = .Corner(0)
            var bottomLeft: ImageCorner = .Corner(0)
            var bottomRight: ImageCorner = .Corner(0)
            
            if self.viewType.position != .first && self.viewType.position != .inner {
                if self.items.count < rowCount {
                    if message == self.items.first {
                        if self.viewType.position != .last {
                            topLeft = .Corner(.cornerRadius)
                        }
                        bottomLeft = .Corner(.cornerRadius)
                    }
                } else if self.items.count == rowCount {
                    if message == self.items.first {
                        if self.viewType.position != .last {
                            topLeft = .Corner(.cornerRadius)
                        }
                        bottomLeft = .Corner(.cornerRadius)
                    } else if message == self.items.last {
                        if message == self.items.last {
                            if self.viewType.position != .last {
                                topRight = .Corner(.cornerRadius)
                            }
                            bottomRight = .Corner(.cornerRadius)
                        }
                    }
                } else {
                    let i = i + 1
                    let firstLine = i <= rowCount
                    let div = (items.count % rowCount) == 0 ? rowCount : (items.count % rowCount)
                    let lastLine = i > (items.count - div)
                    
                    if firstLine {
                        if self.viewType.position != .last {
                            if i % rowCount == 1 {
                                topLeft = .Corner(.cornerRadius)
                            } else if i % rowCount == 0 {
                                topRight = .Corner(.cornerRadius)
                            }
                        }
                    } else if lastLine {
                        if i % rowCount == 1 {
                            bottomLeft = .Corner(.cornerRadius)
                        } else if i % rowCount == 0 {
                            bottomRight = .Corner(.cornerRadius)
                        }
                    }
                }
            }
            let corners = ImageCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
            self.layoutItems.append(MediaCellLayoutItem(message: message, frame: CGRect(origin: point.offsetBy(dx: 0, dy: -itemSize.height), size: itemSize), viewType: viewType, corners: corners, context: context))
            point.x += itemSize.width
            if (self.layoutItems.count + gap) % rowCount == 0, message != self.items.last {
                point.y += itemSize.height
                point.x = self.viewType.innerInset.left
            }
        }
        self.itemSize = itemSize
        self.contentHeight = point.y - self.viewType.innerInset.top
        return true
    }
    
    public func contains(_ id: MessageId) -> Bool {
        return layoutItems.contains(where: { $0.message.id == id})
    }
    
    public override var height: CGFloat {
        return self.contentHeight + self.viewType.innerInset.top + self.viewType.innerInset.bottom + 1
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    deinit {

    }
    
    public override func viewClass() -> AnyClass {
        return PeerPhotosMonthView.self
    }

    private func accessibilityName(for message: Message) -> String {
        if let file = message.anyMedia as? TelegramMediaFile, file.isVideo {
            return strings().voiceOverCommonVideo
        }
        return strings().voiceOverCommonPhoto
    }

    public override var accessibilityLabel: String? {
        return items.map { accessibilityName(for: $0) }.joined(separator: ", ")
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return items.enumerated().map { index, message in
            NSAccessibilityCustomAction(name: "\(accessibilityName(for: message)) \(index + 1)", handler: { [weak self] in
                guard let self = self else {
                    return false
                }
                self.gallery(message, self.galleryType)
                return true
            })
        }
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items:[ContextMenuItem] = []
        let layoutItem = layoutItems.first(where: { NSPointInRect(location, $0.frame) })
        if let layoutItem = layoutItem {
            let message = layoutItem.message
            if canForwardMessage(message, chatInteraction: chatInteraction) {
                items.append(ContextMenuItem(strings().messageContextForward, handler: { [weak self] in
                    self?.chatInteraction.forwardMessages([message])
                }, itemImage: MenuAnimation.menu_forward.value))
            }
            
            items.append(ContextMenuItem(strings().messageContextGoto, handler: { [weak self] in
                self?.chatInteraction.focusMessageId(nil, .init(messageId: message.id, string: nil), .center(id: 0, innerId: nil, animated: false, focus: .init(focus: true), inset: 0))
            }, itemImage: MenuAnimation.menu_show_message.value))

            let isCopyProtected = message.isCopyProtected() || message.peers[message.id.peerId]?.isCopyProtected(cachedData: self.chatInteraction.presentation.cachedData) == true
            if !isCopyProtected, message.pendingProcessingAttribute == nil {
                if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile {
                    items.append(messageFileSaveMenuItem(file: file, context: self.context, message: message, title: strings().contextSaveMedia))
                } else if let image = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage {
                    items.append(ContextMenuItem(strings().contextSaveMedia, handler: { [weak self] in
                        guard let self else { return }
                        saveImageAs(image, context: self.context, message: message)
                    }, itemImage: MenuAnimation.menu_save_as.value))
                }
            }
            
            if canDeleteMessage(message, account: context.account, chatLocation: self.chatInteraction.chatLocation, mode: .history) {
                items.append(ContextSeparatorItem())
                items.append(ContextMenuItem(strings().messageContextDelete, handler: { [weak self] in
                   self?.chatInteraction.deleteMessages([message.id], nil)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
        }
        return .single(items)
    }
}



private final class PeerPhotosMonthView : TableRowView, Notifable {
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private var contentViews:[Optional<MediaCell>] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        #if DEBUG
        PeerMediaGridDebug.rowViewsCreated += 1
        #endif
        self.addSubview(self.containerView)
        
        containerView.set(handler: { [weak self] _ in
            self?.action(event: .Down)
        }, for: .Down)
        
        containerView.set(handler: { [weak self] _ in
            self?.action(event: .MouseDragging)
        }, for: .MouseDragging)
        
        containerView.set(handler: { [weak self] _ in
            self?.action(event: .Click)
        }, for: .Click)
    }
    
    private var haveToSelectOnDrag: Bool = false
    
    
    private weak var currentMouseCell: MediaCell?
    
    @objc func _updateMouse() {
        super.updateMouse(animated: true)
        guard let window = self.window else {
            return
        }
        let point = self.containerView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let mediaCell = self.contentViews.first(where: {
            return $0 != nil && NSPointInRect(point, $0!.frame)
        })?.map { $0 }
        
        if currentMouseCell != mediaCell {
            currentMouseCell?.updateMouse(false)
        }
        currentMouseCell = mediaCell
        mediaCell?.updateMouse(window.isKeyWindow)
        
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        _updateMouse()
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        _updateMouse()
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        _updateMouse()
    }
    
    private func action(event: ControlEvent) {
        guard let item = self.item as? PeerPhotosMonthItem, let window = window else {
            return
        }
        let point = containerView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if let layoutItem = item.layoutItems.first(where: { NSPointInRect(point, $0.frame) }) {
            if item.chatInteraction.presentation.state == .selecting {
                switch event {
                case .MouseDragging:
                    item.chatInteraction.update { current in
                        if !haveToSelectOnDrag {
                            return current.withRemovedSelectedMessage(layoutItem.message.id)
                        } else {
                            return current.withUpdatedSelectedMessage(layoutItem.message.id)
                        }
                    }
                case .Down:
                    item.chatInteraction.update { $0.withToggledSelectedMessage(layoutItem.message.id) }
                    haveToSelectOnDrag = item.chatInteraction.presentation.isSelectedMessageId(layoutItem.message.id)
                default:
                    break
                }
            } else {
                switch event {
                case .Click:
                    let view = self.contentViews.compactMap { $0 }.first(where: { $0.layoutItem?.isEqual(to: layoutItem) == true })
                    if let view = view {
                        switch view.innerAction() {
                        case .gallery:
                            item.gallery(layoutItem.message, item.galleryType)
                        case .nothing:
                            break
                        }
                    }
                default:
                    break
                }
            }
        }
    }
    
    func notify(with value: Any, oldValue:Any, animated:Bool) {
        if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
            let views = contentViews.compactMap { $0 }
            for view in views {
                if let item = view.layoutItem {
                    if (value.state == .selecting) != (oldValue.state == .selecting) || value.isSelectedMessageId(item.id) != oldValue.isSelectedMessageId(item.id) {
                        view.updateSelectionState(animated: animated, selected: value.state == .selecting ? value.isSelectedMessageId(item.id) : nil)
                    }
                }
            }
        }
    }
    
    func isEqual(to other: Notifable) -> Bool {
        if let other = other as? PeerPhotosMonthView {
            return other == self
        }
        return false
    }
       
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    override func updateColors() {
        guard let item = item as? PeerPhotosMonthItem else {
            return
        }
        self.backgroundColor = item.viewType.rowBackground
        containerView.set(background: self.backdorColor, for: .Normal)
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateVisibleItems()
        
        if let item = self.item as? PeerPhotosMonthItem {
            if superview == nil {
                item.chatInteraction.remove(observer: self)
            } else {
                item.chatInteraction.add(observer: self)
            }
        }
    }
    
    @objc private func updateVisibleItems() {
        
    }
    
    private var previousRange: (Int, Int) = (0, 0)
    private func layoutVisibleItems(animated: Bool) {
        guard let item = item as? PeerPhotosMonthItem else {
            return
        }
                
        CATransaction.begin()
        let presentation = item.chatInteraction.presentation
        for (i, layout) in item.layoutItems.enumerated() {
            var view: MediaCell
            if self.contentViews[i] == nil || !self.contentViews[i]!.isKind(of: layout.viewType) {
                #if DEBUG
                PeerMediaGridDebug.cellsCreated += 1
                #endif
                view = layout.viewType.init(frame: layout.frame)
                self.contentViews[i] = view
            } else {
                view = self.contentViews[i]!
            }
            view.update(layout: layout, selected: presentation.state == .selecting ? presentation.isSelectedMessageId(layout.message.id) : nil, context: item.context, table: item.table, animated: animated)

            view.frame = layout.frame
        }
        
        containerView.subviews = self.contentViews.compactMap { $0 }

        CATransaction.commit()
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidMoveToWindow() {
         if window == nil {
             NotificationCenter.default.removeObserver(self)
         } else {
             NotificationCenter.default.addObserver(self, selector: #selector(updateVisibleItems), name: NSView.boundsDidChangeNotification, object: self.enclosingScrollView?.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(_updateMouse), name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(_updateMouse), name: NSWindow.didResignKeyNotification, object: nil)
         }
         updateVisibleItems()
     }
    
    override func layout() {
        super.layout()
        guard let item = item as? PeerPhotosMonthItem else {
            return
        }
        self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
        self.containerView.setCorners(item.viewType.corners)
        
        updateVisibleItems()
    }
    
    override func interactionContentView(for innerId: AnyHashable, animateIn: Bool) -> NSView {
        return mediaCellInteractionContentView(contentViews, for: innerId, fallback: self)
    }
    
    override func addAccesoryOnCopiedView(innerId: AnyHashable, view: NSView) {
        addMediaCellAccesoryOnCopiedView(contentViews, innerId: innerId, view: view)
    }
    
    override func convertWindowPointToContent(_ point: NSPoint) -> NSPoint {
        return containerView.convert(point, from: nil)
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        
        super.set(item: item, animated: animated)
        
        guard let item = item as? PeerPhotosMonthItem else {
            return
        }
        #if DEBUG
        PeerMediaGridDebug.rowsSet += 1
        #endif
        
        item.chatInteraction.add(observer: self)
        
        self.previousRange = (0, 0)
        
        while self.contentViews.count > item.layoutItems.count {
            self.contentViews.removeLast()
        }
        while self.contentViews.count < item.layoutItems.count {
            self.contentViews.append(nil)
        }
        
        
        layoutVisibleItems(animated: animated)
    }
}


public func addPeerPhotosAccesoryOnCopiedView(for stableId: AnyHashable, view: NSView, tableView: TableView?) {
    if let stableId = stableId.base as? ChatHistoryEntryId, let tableView = tableView {
        switch stableId {
        case let .message(message):
            tableView.enumerateItems { item -> Bool in
                if let item = item as? PeerPhotosMonthItem {
                    if item.contains(message.id) {
                        item.view?.addAccesoryOnCopiedView(innerId: message.id, view: view)
                        return false
                    }
                }
                return true
            }
        default:
            break
        }
    }
}
