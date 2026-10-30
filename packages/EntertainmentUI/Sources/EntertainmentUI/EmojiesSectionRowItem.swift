import Foundation
import TGUIKit
import TelegramCore
import AppKit
import SwiftSignalKit
import Postbox
import ObjcUtils
import Accelerate
import TelegramMedia
import InAppSettings
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import LocalAnimations
import GeneralRows
import PremiumStatusUI
import InputView
import InlineStickerLayer

private let largeReactionHoldDuration: Double = 0.8

private func isSameEmojiEntry(_ lhs: EmojiesSectionRowItem.Item?, _ rhs: EmojiesSectionRowItem.Item?) -> Bool {
    guard let lhs, let rhs, lhs.rect == rhs.rect else {
        return false
    }
    switch (lhs, rhs) {
    case let (.item(_, lhsItem, _, _), .item(_, rhsItem, _, _)):
        return lhsItem.file.fileId == rhsItem.file.fileId
    case (.more, .more):
        return true
    default:
        return false
    }
}

public final class EmojiesSectionRowItem : GeneralRowItem {
    
    public enum Item : Equatable {
        case item(rect: NSRect, item: StickerPackItem, lock: Bool, selected: SelectedItem.Selection?)
        case more(rect: NSRect, count: Int)
        
        public var rect: NSRect {
            switch self {
            case let .item(rect, _, _, _):
                return rect
            case let .more(rect, _):
                return rect
            }
        }
        
        public var lock: Bool {
            switch self {
            case let .item(_, _, lock, _):
                return lock
            default:
                return false
            }
        }
        
        public var selection: SelectedItem.Selection? {
            switch self {
            case let .item(_, _, _, selection):
                return selection
            default:
                return nil
            }
        }
        
        public var item: StickerPackItem? {
            switch self {
            case let .item(_, item, _, _):
                return item
            default:
                return nil
            }
        }
    }
    
    public struct SelectedItem : Equatable {
        public enum Selection : Equatable {
            case normal
            case transparent
        }
        public enum Source : Equatable {
            case builtin(String)
            case custom(Int64)
        }
        public let source : Source
        public let type: Selection
        public let index: Int?
        public init(source: Source, type: Selection, index: Int? = nil) {
            self.source = source
            self.type = type
            self.index = index
        }
        
        public func isEqual(to file: TelegramMediaFile) -> Bool {
            switch self.source {
            case let .custom(fileId):
                return file.fileId.id == fileId
            case let .builtin(emoji):
                return file.stickerText == emoji
            }
        }
    }
    
    public private(set) var items: [Item] = []
    private let _items: [StickerPackItem]
    public internal(set) var selectedItems: [SelectedItem]
    public let stickerItems: [StickerPackItem]
    public let context: any AccountContextProtocol
    public let callback:(StickerPackItem, StickerPackCollectionInfo?, Int32?, NSRect?)->Void
    public let largeCallback: (() -> ((StickerPackItem, NSRect?) -> Void)?)?
    public let drag: ((StickerPackItem, EntertainmentStickerDrag) -> Bool)?
    public let itemSize: NSSize
    public let info: StickerPackCollectionInfo?
    public let viewSet: ((StickerPackCollectionInfo)->Void)?
    
    public let nameLayout: TextViewLayout?
    public private(set) var sectionLayout: TextViewLayout?

    public let isPremium: Bool
    public let revealed: Bool
    public let showAllItems:(()->Void)?
    
    public let installed: Bool
    
    public let unlockText: (String, Bool, Bool)?
    
    public let openPremium:(()->Void)?
    public let installPack:((StickerPackCollectionInfo, [StickerPackItem])->Void)?

    public enum Mode {
        case panel
        case preview
        case reactions
        case statuses
        case topic
        case backgroundIcon
        case channelReactions
        case channelStatus
        case defaultTags
        case messageEffects
    }
    public let mode: Mode
    public let color: NSColor?
    public let uniqueGifts: [StarGift.UniqueGift]
    public let removeRecent: ((MediaId) -> Void)?
    private let emojiStatusAction = EmojiStatusMenuAction()
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, revealed: Bool, installed: Bool, info: StickerPackCollectionInfo?, items: [StickerPackItem], isBig: Bool = false, groupEmojiPack: Bool = false, mode: Mode = .panel, selectedItems:[SelectedItem] = [], color: NSColor? = nil, callback:@escaping(StickerPackItem, StickerPackCollectionInfo?, Int32?, NSRect?)->Void, largeCallback: (() -> ((StickerPackItem, NSRect?) -> Void)?)? = nil, drag: ((StickerPackItem, EntertainmentStickerDrag) -> Bool)? = nil, viewSet:((StickerPackCollectionInfo)->Void)? = nil, showAllItems:(()->Void)? = nil, openPremium:(()->Void)? = nil, installPack:((StickerPackCollectionInfo, [StickerPackItem])->Void)? = nil, ignorePremium: Bool = false, uniqueGifts: [StarGift.UniqueGift] = [], removeRecent: ((MediaId) -> Void)? = nil) {
        self.itemSize = isBig ? NSMakeSize(66, 60) : NSMakeSize(40, 34)
        self.info = info
        self.mode = mode
        self.color = color
        self.uniqueGifts = uniqueGifts
        self.removeRecent = removeRecent
        self._items = items
        self.viewSet = viewSet
        self.installed = installed
        self.revealed = revealed
        self.selectedItems = selectedItems
        self.stickerItems = items
        self.showAllItems = showAllItems
        self.openPremium = openPremium
        self.installPack = installPack
        self.isPremium = items.contains(where: { $0.file.isPremiumEmoji }) && stableId != AnyHashable(0) && mode != .channelReactions && !groupEmojiPack && !ignorePremium
       
        
        self.context = context
        self.callback = callback
        self.largeCallback = largeCallback
        self.drag = drag
        
        if !uniqueGifts.isEmpty {
            let layout = TextViewLayout(.initialize(string: strings().emojiCollectibles, color: theme.colors.grayText, font: .normal(12)), maximumNumberOfLines: 1, alwaysStaticItems: true)
            self.nameLayout = layout
        } else if stableId != AnyHashable(0), let info = info, !info.title.isEmpty {
            let text = info.title.uppercased()
            if groupEmojiPack {
                sectionLayout = .init(.initialize(string: strings().emojiSectionGroupEmoji, color: theme.colors.grayText, font: .normal(12)), maximumNumberOfLines: 1, alignment: .center, alwaysStaticItems: true)
            }
            let layout = TextViewLayout(.initialize(string: text, color: theme.colors.grayText, font: .normal(12)), maximumNumberOfLines: 1, alwaysStaticItems: true)
            self.nameLayout = layout
        } else {
            self.nameLayout = nil
        }
        
        if let _ = info {
            switch mode {
            case .panel, .reactions, .statuses, .topic, .backgroundIcon, .defaultTags:
                if isPremium && !context.isPremium {
                    if installed {
                        self.unlockText = (strings().emojiPackRestore, true, true)
                    } else {
                        self.unlockText = (strings().emojiPackUnlock, true, true)
                    }
                } else if !installed {
                    self.unlockText = (strings().emojiPackAdd, false, true)
                } else {
                    self.unlockText = nil
                }
            case .channelReactions, .channelStatus, .messageEffects:
                self.unlockText = nil
            case .preview:
                if stableId != AnyHashable(0) {
                    if installed {
                        self.unlockText = (strings().emojiPackAdded, false, false)
                    } else {
                        self.unlockText = (strings().emojiPackAdd, false, true)
                    }
                } else {
                    self.unlockText = nil
                }
            }
            
        } else {
            self.unlockText = nil
        }
        

        
        
        super.init(initialSize, stableId: stableId)
        
        _ = makeSize(initialSize.width)
    }
    
    public override func viewClass() -> AnyClass {
        return EmojiesSectionRowView.self
    }
    
    public override var accessibilityLabel: String? {
        if !uniqueGifts.isEmpty {
            return strings().emojiCollectibles
        }
        if let title = info?.title, !title.isEmpty {
            return title
        }
        return strings().voiceOverCommonEmoji
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        
        let perline: Int = Int(floor(max(300, width - 20) / itemSize.width))
        
        var mapped: [Item] = []
        var point = NSMakePoint(10, 0)
        
        var optimized = (isPremium && !context.isPremium || !installed) && !revealed && _items.count > 3 * perline ? Array(_items.prefix(3 * perline - 1)) : _items
        if mode == .statuses, info == nil, !revealed {
            optimized = Array(_items.prefix(min(_items.count, perline * 5 - 1)))
        }
        for item in optimized {
            
            let isLocked = mode == .reactions && !context.isPremium && info == nil && item.file._parse().stickerText == nil && item.getStringRepresentationsOfIndexKeys().isEmpty
            
            let selected = selectedItems.first(where: { $0.isEqual(to: item.file._parse()) })?.type
            
            let inset: NSPoint
            if selected != nil {
                inset = NSMakePoint(8, 5)
            } else {
                inset = NSMakePoint(2, 2)
            }
            mapped.append(.item(rect: CGRect(origin: point, size: itemSize).insetBy(dx: inset.x, dy: inset.y), item: item, lock: isLocked, selected: selected))
            point.x += itemSize.width
            if mapped.count % perline == 0 {
                point.y += itemSize.height
                point.x = 10
            }
        }
        
        if optimized.count != _items.count {
            mapped.append(.more(rect: CGRect(origin: point, size: itemSize).insetBy(dx: -5, dy: 0), count: _items.count - optimized.count))
        }
        
        self.items = mapped
        
        sectionLayout?.measure(width: unlockText != nil ? 200 : 300)

        var name_w: CGFloat = (unlockText != nil ? 200 : 300)
        if let sectionLayout {
            name_w -= (sectionLayout.layoutSize.width + 10)
        }
        nameLayout?.measure(width: name_w)
        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        
        if let nameLayout = nameLayout {
            height += nameLayout.layoutSize.height + (unlockText != nil ? 15 : 5)
        }
        
        let perline: CGFloat = floor(max(300, width - 20) / itemSize.width)

        
        height += self.itemSize.height * CGFloat(ceil(CGFloat(items.count) / perline))
        
        if let _ = nameLayout {
            height += 7
        }

        
        return height
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items: [ContextMenuItem] = []
        
        let info = self.info
        let context = self.context
        
        var copyItem: ContextMenuItem?
        var setStatus: ContextMenuItem?
        if let view = self.view as? EmojiesSectionRowView, let file = view.itemUnderMouse?.0.file {
            let input: ChatTextInputState
            if let bundle = file.stickerText {
                input = .init(inputText: bundle, selectionRange: 0..<bundle.length, attributes: [])
            } else {
                let text = file.customEmojiText ?? file.stickerText ?? ""
                input = .init(inputText: text, selectionRange: 0..<text.length, attributes: [.animated(0..<text.length, text, file.fileId.id, file, info?.id)])
            }
            copyItem = ContextMenuItem(strings().contextCopy, handler: {
                copyToClipboard(input)
            }, itemImage: MenuAnimation.menu_copy.value)
            
            
        }
        
        if context.isPremium {
            if let view = self.view as? EmojiesSectionRowView, let file = view.itemUnderMouse?.0.file, file.isCustomEmoji {
                switch mode {
                case .panel:
                    setStatus = .init(strings().emojiContextSetStatus, handler: { [weak self] in
                        guard let self else { return }
                        let window = self.context.window
                        self.emojiStatusAction.perform(context: self.context, file: file, window: window, canPresent: { [weak self, weak window] in
                            guard let self, let window else { return false }
                            return self.context.window === window
                        })
                    }, itemImage: MenuAnimation.menu_smile.value)
                default:
                    setStatus = nil
                }
                
            }
        }
        
        if let view = self.view as? EmojiesSectionRowView, let file = view.itemUnderMouse?.0.file {
            if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
                if file.isAnimatedSticker, let data = try? Data(contentsOf: URL(fileURLWithPath: context.account.postbox.mediaBox.resourcePath(file.resource))) {
                    items.append(ContextMenuItem("Copy thumbnail (Dev.)", handler: {
                    _ = getAnimatedStickerThumb(data: data).start(next: { path in
                            if let path = path {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.writeObjects([NSURL(fileURLWithPath: path)])
                            }
                        })
                    }, itemImage: MenuAnimation.menu_copy_media.value))
                }
            }
        }
        
        switch mode {
        case .reactions:
            if let view = self.view as? EmojiesSectionRowView, let file = view.itemUnderMouse?.0.file {
                
                let value: MessageReaction.Reaction
                if let bundle = file.stickerText {
                    value = .builtin(bundle)
                } else {
                    value = .custom(file.fileId.id)
                }
                items.append(ContextMenuItem(strings().chatContextReactionQuick, handler: {
                    context.reactions.updateQuick(value)
                }, itemImage: MenuAnimation.menu_add_to_favorites.value))
                
                if let copyItem = copyItem {
                    items.append(copyItem)
                }
                if let setStatus = setStatus {
                    items.append(setStatus)
                }
            }
            return .single(items)
        case .statuses:
            if let view = self.view as? EmojiesSectionRowView, let item = view.itemUnderMouse {
                if let sticker = item.1.item, let window = view.window {
                    if !sticker.file._parse().mimeType.hasPrefix("bundle") {
                        let hours: [Int32] = [60 * 60,
                                              60 * 60 * 2,
                                              60 * 60 * 8,
                                              60 * 60 * 24 * 1,
                                              60 * 60 * 24 * 2]

                        let wrect = view.contentView.convert(item.1.rect, to: nil)
                        let srect = window.convertToScreen(wrect)
                        
                        let lrect = context.window.convertFromScreen(srect)
                        
                        
                        for hour in hours {
                            items.append(ContextMenuItem(strings().customStatusMenuTimer(timeIntervalString(Int(hour))), handler: { [weak self] in
                                self?.callback(sticker, self?.info, hour, lrect)
                            }))
                        }
                        #if DEBUG
                        if #available(macOS 13, *) {
                            items.append(ContextSeparatorItem())
                            //TODO LANG
                            items.append(ContextMenuItem("Apply for Focus Filter", handler: {
                                _ = updateSomeSettingsInteractively(postbox: context.account.postbox, { current in
                                    var current = current
                                    current.focusIntentStatusActive = sticker.file.fileId.id
                                    return current
                                }).startStandalone()
                                showModalText(for: context.window, text: "This emoji will be used for system Focus Mode")
                            }))
                        }
                        #endif
                    }
                }
            }
            
            return .single(items)
        case .preview:
            if let copyItem = copyItem {
                items.append(copyItem)
            }
            if let setStatus = setStatus {
                items.append(setStatus)
            }
            return .single(items)
        default:
            break
        }
        
        
        
        if let setStatus = setStatus {
            items.append(setStatus)
        }
        
        if let removeRecent = removeRecent, let view = self.view as? EmojiesSectionRowView, let file = view.item(at: location)?.file {
            items.append(ContextMenuItem(strings().searchRemoveFromRecent, handler: {
                removeRecent(file.fileId)
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
        }

        if stableId == AnyHashable(0) || self.viewSet == nil {
            return .single(items)
        }
        
        
        if let info = info, mode == .panel {
            items.append(ContextMenuItem(strings().contextViewEmojiSet, handler: { [weak self] in
                self?.viewSet?(info)
            }, itemImage: MenuAnimation.menu_view_sticker_set.value))
            
            if let copyItem = copyItem {
                items.append(copyItem)
            }
        }
       
      
        
        
//        items.append(ContextMenuItem(strings().emojiContextRemove, handler: {
//            _ = context.engine.stickers.removeStickerPackInteractively(id: info.id, option: .delete).start()
//        }, itemImage: MenuAnimation.menu_delete.value))
//
        return .single(items)
    }
    
    public func animateAppearance(delay: Double, duration: Double, initialPlayers: [Int: LottiePlayerView]) {
        (self.view as? EmojiesSectionRowView)?.animateAppearance(delay: delay, duration: duration, initialPlayers: initialPlayers)
    }
    
    public func invokeLockAction() {
        if let info = info {
            switch mode {
            case .panel, .reactions, .statuses, .topic, .backgroundIcon:
                if isPremium && !context.isPremium {
                    self.openPremium?()
                } else if !installed {
                    self.installPack?(info, self.stickerItems)
                }
            case .channelReactions:
                self.installPack?(info, self.stickerItems)
            case .defaultTags:
                self.installPack?(info, self.stickerItems)
            case .preview:
                self.installPack?(info, self.stickerItems)
            case .channelStatus:
                self.installPack?(info, self.stickerItems)
            case .messageEffects:
                break
            }
            
        }
    }
}



private final class EmojiesSectionRowView : TableRowView, ModalPreviewRowViewProtocol {
    

    
    func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        if let item = itemUnderMouse?.1, let file = item.item?.file {
            let emojiReference = file._parse().emojiReference ?? file._parse().stickerReference
            if let emojiReference = emojiReference {
                let reference = FileMediaReference.stickerPack(stickerPack: emojiReference, media: file._parse())
                if file.isVideoSticker && !file._parse().isWebm {
                    return (.file(reference, EntertainmentUIHooks.shared.previewViewType(.gif)), nil)
                } else if file.isAnimatedSticker || file._parse().isWebm || file.isCustomEmoji {
                    return (.file(reference, EntertainmentUIHooks.shared.previewViewType(.animatedSticker)), nil)
                } else if file.isStaticSticker  {
                    return (.file(reference, EntertainmentUIHooks.shared.previewViewType(.sticker)), nil)
                }
            }
        }
        return nil
    }
    
    
    fileprivate final class UnlockView : Control {
        private let gradient: PremiumGradientView = PremiumGradientView(frame: .zero)
        private let textView = TextView()
        private let container = View()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(gradient)
            container.addSubview(textView)
            addSubview(container)
            scaleOnClick = true
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        
        override func layout() {
            super.layout()
            gradient.frame = bounds
            container.center()
            textView.centerY(x: 0)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(name: String, width: CGFloat, context: any AccountContextProtocol, table: TableView?) -> NSSize {
            let layout = TextViewLayout(.initialize(string: name, color: NSColor.white, font: .medium(12)))
            layout.measure(width: .greatestFiniteMagnitude)
            textView.update(layout)
            
            container.setFrameSize(NSMakeSize(layout.layoutSize.width, layout.layoutSize.height))
            let size = NSMakeSize(container.frame.width + 20, layout.layoutSize.height + 10)
            

            needsLayout = true
            
            return size
        }
    }
    

    fileprivate var unlock: Control?

    
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineStickerItemLayer] = [:]
    private var locks:[InlineStickerItemLayer.Key : InlineStickerLockLayer] = [:]
    private var selectedLayers:[InlineStickerItemLayer.Key : SimpleLayer] = [:]
    private var orderBadgeLayers:[InlineStickerItemLayer.Key : SimpleLayer] = [:]
    
    private var starsLayer: [InlineStickerItemLayer.Key: StarsEffectLayer] = [:]

    
    fileprivate let contentView = EntertainmentGridControl()
    
    private var nameView: TextView?
    private var sectionTextView: TextView?

    private var lockView: ImageView?
    private let container = View()
    
    private var reveal: TextButton?
    
    private var appearanceViews:[WeakReference<NSView>] = []
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(container)
        addSubview(contentView)
        
        container.layer?.masksToBounds = false
        
        contentView.accessibilityCells = { [weak self] in
            return self?.accessibilityCells() ?? []
        }
        
        contentView.set(handler: { [weak self] _ in
            self?.updateDown()
        }, for: .Down)
        
        contentView.set(handler: { [weak self] _ in
            self?.updateDragging()
        }, for: .MouseDragging)
        
        contentView.set(handler: { [weak self] _ in
            self?.updateUp()
        }, for: .Up)
        
        contentView.set(handler: { [weak self] _ in
            if self?.largeHoldTimer != nil || self?.largeInvoked == true {
                return
            }
            let item = self?.item as? EmojiesSectionRowItem
            let table = item?.table
            let window = self?.window as? Window
            if let item = item, let table = table, let window = window {
                startModalPreviewHandle(table, window: window, context: item.context)
            }
        }, for: .LongMouseDown)
        
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    private var currentDownItem: (InlineStickerItemLayer, EmojiesSectionRowItem.Item, Bool)?
    private var largeHoldTimer: SwiftSignalKit.Timer?
    private var largeInvoked: Bool = false

    private func startLargeHold(_ current: (InlineStickerItemLayer, EmojiesSectionRowItem.Item, Bool), send: @escaping(StickerPackItem, NSRect?)->Void) {
        let layer = current.0
        layer.zPosition = 1
        layer.animateScale(from: layer.transform.m11, to: layer.transform.m11 * 1.5, duration: largeReactionHoldDuration, removeOnCompletion: false)
        largeHoldTimer = SwiftSignalKit.Timer(timeout: largeReactionHoldDuration, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.largeHoldTimer = nil
            if isSameEmojiEntry(self.itemUnderMouse?.1, current.1), let sticker = current.1.item, let window = self.window, let item = self.item as? EmojiesSectionRowItem {
                self.largeInvoked = true
                let wrect = self.contentView.convert(current.1.rect, to: nil)
                let srect = window.convertToScreen(wrect)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                send(sticker, item.context.window.convertFromScreen(srect))
            } else {
                self.cancelLargeHold()
            }
        }, queue: .mainQueue())
        largeHoldTimer?.start()
    }

    private func cancelLargeHold() {
        largeHoldTimer?.invalidate()
        largeHoldTimer = nil
        if let layer = currentDownItem?.0 {
            layer.animateScale(from: layer.presentation()?.transform.m11 ?? layer.transform.m11, to: layer.transform.m11, duration: 0.18, removeOnCompletion: true)
            layer.zPosition = 0
        }
    }

    private let dragTracker = EntertainmentDragTracker()
    private func updateDown() {
        largeInvoked = false
        if let item = itemUnderMouse {
            self.currentDownItem = (item.0, item.1, true)
            self.dragTracker.down(in: window)
        }
        if let current = self.currentDownItem, current.1.item != nil, let send = (self.item as? EmojiesSectionRowItem)?.largeCallback?() {
            startLargeHold(current, send: send)
        } else if let itemUnderMouse = self.currentDownItem {
            itemUnderMouse.0.animateScale(from: itemUnderMouse.0.presentation()?.transform.m11 ?? itemUnderMouse.0.transform.m11, to: itemUnderMouse.0.transform.m11 * 0.85, duration: 0.12, removeOnCompletion: false)
        }
    }
    private func updateDragging() {
        if largeHoldTimer != nil {
            if !isSameEmojiEntry(self.itemUnderMouse?.1, self.currentDownItem?.1) {
                cancelLargeHold()
                self.currentDownItem = nil
            }
            return
        }
        if let current = self.currentDownItem, let item = item as? EmojiesSectionRowItem, let drag = item.drag, let stickerItem = current.1.item, dragTracker.dragged(in: window, begin: { point in
            guard drag(stickerItem, .moved(point)) else {
                return false
            }
            if current.2 {
                current.0.animateScale(from: current.0.presentation()?.transform.m11 ?? current.0.transform.m11 * 0.85, to: current.0.transform.m11, duration: 0.18, removeOnCompletion: true)
                self.currentDownItem?.2 = false
            }
            return true
        }, move: { point in
            _ = drag(stickerItem, .moved(point))
        }) {
            return
        }
        if let current = self.currentDownItem {
            if self.itemUnderMouse?.1 != current.1, current.2  {
                current.0.animateScale(from: current.0.presentation()?.transform.m11 ?? current.0.transform.m11 * 0.85, to: current.0.transform.m11, duration: 0.18, removeOnCompletion: true)
                self.currentDownItem?.2 = false
            } else if !current.2, self.itemUnderMouse?.1 == current.1 {
                current.0.animateScale(from: current.0.presentation()?.transform.m11 ?? current.0.transform.m11, to: current.0.transform.m11 * 0.85, duration: 0.12, removeOnCompletion: false)
                self.currentDownItem?.2 = true
            }
        }
            
    }
    private func updateUp() {
        if largeInvoked {
            self.currentDownItem = nil
            return
        }
        if largeHoldTimer != nil {
            cancelLargeHold()
            if isSameEmojiEntry(self.currentDownItem?.1, self.itemUnderMouse?.1) {
                self.click()
            }
            self.currentDownItem = nil
            return
        }
        if let current = self.currentDownItem, let item = item as? EmojiesSectionRowItem, let stickerItem = current.1.item, dragTracker.up(in: window, end: { point in
            _ = item.drag?(stickerItem, .ended(point))
        }) {
            self.currentDownItem = nil
            return
        }
        if let itemUnderMouse = self.currentDownItem {
            if itemUnderMouse.1 == self.itemUnderMouse?.1 {
                itemUnderMouse.0.animateScale(from: itemUnderMouse.0.presentation()?.transform.m11 ?? itemUnderMouse.0.transform.m11 * 0.85, to: itemUnderMouse.0.transform.m11, duration: 0.18, removeOnCompletion: true)
                self.click()
            }
        }
        self.currentDownItem = nil
    }
    
    override func layout() {
        super.layout()
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        var containerSize = NSZeroSize
        if let nameView = self.nameView {
            containerSize = NSMakeSize(nameView.frame.width, nameView.frame.height)
        }
        if let lockView = lockView, let nameView = nameView {
            containerSize.width += lockView.frame.width
            containerSize.height = max(nameView.frame.height, lockView.frame.height)
        }

        transition.updateFrame(view: container, frame: CGRect(origin: NSMakePoint(20, 5), size: containerSize))
        
        
        if let lockView = lockView {
            transition.updateFrame(view: lockView, frame: lockView.centerFrameY(x: 0))
            if let nameView = nameView {
                transition.updateFrame(view: nameView, frame: nameView.centerFrameY(x: lockView.frame.maxX))
            }
        } else {
            if let nameView = nameView {
                transition.updateFrame(view: nameView, frame: nameView.centerFrame())
            }
        }
        if let sectionTextView = sectionTextView {
            transition.updateFrame(view: sectionTextView, frame: sectionTextView.centerFrameY(x: (nameView?.frame.maxX ?? 0) + 4))
        }
        
        var contentRect = bounds
        if let nameView = nameView {
            contentRect = contentRect.offsetBy(dx: 0, dy: nameView.frame.height + (unlock != nil ? 15 : 7))
        }
        transition.updateFrame(view: contentView, frame: contentRect)
        
        if let unlock = unlock {
            transition.updateFrame(view: unlock, frame: CGRect(origin: CGPoint(x: size.width - unlock.frame.width - 15, y: 0), size: unlock.frame.size))
        }
    }
    
    fileprivate func item(at point: NSPoint) -> StickerPackItem? {
        let point = contentView.convert(point, from: self)
        guard contentView.bounds.contains(point), let item = self.item as? EmojiesSectionRowItem else {
            return nil
        }
        return item.items.first(where: { $0.rect.contains(point) })?.item
    }

    fileprivate var itemUnderMouse: (InlineStickerItemLayer, EmojiesSectionRowItem.Item)? {
        guard let window = self.window, let item = self.item as? EmojiesSectionRowItem else {
            return nil
        }
        let point = self.contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        
        let firstItem = item.items.first(where: {
            return NSPointInRect(point, $0.rect)
        })
        let firstLayer = self.inlineStickerItemViews.first(where: { layer in
            return NSPointInRect(point, layer.1.frame)
        })?.value
        
        if let firstItem = firstItem, let firstLayer = firstLayer {
            return (firstLayer, firstItem)
        }
        
        return nil
    }
    
    private func accessibilityCells() -> [EntertainmentAccessibilityCell] {
        guard let item = self.item as? EmojiesSectionRowItem else {
            return []
        }
        var cells: [EntertainmentAccessibilityCell] = []
        for (index, entry) in item.items.enumerated() {
            guard let current = entry.item else {
                continue
            }
            let file = current.file._parse()
            let label = file.customEmojiText ?? file.stickerText ?? strings().voiceOverCommonEmoji
            cells.append(EntertainmentAccessibilityCell(id: AnyHashable(index), label: label, frame: entry.rect, isSelected: entry.selection != nil, press: { [weak self, weak item] in
                guard let self = self, let item = item, let window = self.window else {
                    return
                }
                let wrect = self.contentView.convert(entry.rect, to: nil)
                let srect = window.convertToScreen(wrect)
                item.callback(current, item.info, nil, item.context.window.convertFromScreen(srect))
            }))
        }
        return cells
    }
    
    private func click() {
        
        guard let item = self.item as? EmojiesSectionRowItem else {
            return
        }
        if let first = currentDownItem, let current = first.1.item, let window = self.window {
            let wrect = self.contentView.convert(first.1.rect, to: nil)
            let srect = window.convertToScreen(wrect)
            
            item.callback(current, item.info, nil, item.context.window.convertFromScreen(srect))
        }
    }
    
    func animateAppearance(delay delay_t: Double, duration: Double, initialPlayers: [Int: LottiePlayerView]) {
        var delay_t = delay_t
        let itemDelay = duration / Double(inlineStickerItemViews.count)
        for (key, value) in inlineStickerItemViews {
            if initialPlayers[key.index] == nil {
                value.animateScale(from: 0.1, to: 1, duration: duration, timingFunction: .spring, delay: itemDelay)
                locks[key]?.animateScale(from: 0.1, to: 1, duration: duration, timingFunction: .spring, delay: itemDelay)
                selectedLayers[key]?.animateScale(from: 0.1, to: 1, duration: duration, timingFunction: .spring, delay: itemDelay)
                delay_t += itemDelay
            } else if let selected = selectedLayers[key] {
                selected.animate(from: NSNumber(value: selected.frame.height / 2), to: NSNumber(value: 10), keyPath: "cornerRadius", timingFunction: .easeOut, duration: 0.2, forKey: "cornerRadius")
            }
            if let view = initialPlayers[key.index], view.currentState == .playing {
                view.frame = value.frame
                value.superview?.addSubview(view)
                value.stopped = true
                value.reset()
                value.opacity = 0
                appearanceViews.append(.init(value: view))
                view.contextAnimation?.triggerOn = (.last, { [weak view, weak value] in
                    if let value = value {
                        value.triggerNextState = { [weak value] _ in
                            view?.removeFromSuperview()
                            value?.opacity = 1
                        }
                        value.stopped = false
                        value.apply()
                    } else {
                        view?.removeFromSuperview()
                    }
                }, {})
            }
        }
    }

    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? EmojiesSectionRowItem else {
            return
        }
        
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        
        if !item.context.isPremium && item.isPremium {
            let current: ImageView
            if let view = self.lockView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.lockView = current
                container.addSubview(current)
            }
            current.image = theme.icons.premium_emoji_lock
            current.sizeToFit()
        } else if let view = self.lockView {
            performSubviewRemoval(view, animated: animated)
            self.lockView = nil
        }
        
        if let layout = item.nameLayout {
            let current: TextView
            if let view = self.nameView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                current.isAccessibilityDecorative = true
                self.nameView = current
                container.addSubview(current)
            }
            current.update(layout)
        } else if let view = self.nameView {
            performSubviewRemoval(view, animated: animated)
            self.nameView = nil
        }
        
        if let layout = item.sectionLayout {
            let current: TextView
            if let view = self.sectionTextView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                self.sectionTextView = current
                container.addSubview(current)
            }
            current.update(layout)
            current.backgroundColor = theme.colors.grayIcon.withAlphaComponent(0.2)
            current.setFrameSize(NSMakeSize(layout.layoutSize.width + 12, layout.layoutSize.height + 2))
            current.layer?.cornerRadius = current.frame.height * 0.5
        } else if let view = self.sectionTextView {
            performSubviewRemoval(view, animated: animated)
            self.sectionTextView = nil
        }
        
        
        if case let .more(rect, count) = item.items.last {
            let current: TextButton
            if let view = self.reveal {
                current = view
            } else {
                current = TextButton()
                self.reveal = current
                contentView.addSubview(current)
            }
            current.set(font: .avatar(12), for: .Normal)
            current.set(color: theme.colors.accent, for: .Normal)
            current.set(background: theme.colors.accent.withAlphaComponent(0.1), for: .Normal)
            current.set(text: "+\(count)", for: .Normal)
            current.sizeToFit(.zero, NSMakeSize(rect.width - 10, 25), thatFit: true)
            current.autoSizeToFit = false
            current.scaleOnClick = true
            current.layer?.cornerRadius = current.frame.height / 2
            current.setFrameOrigin(rect.origin.offsetBy(dx: 2, dy: 4))
            
            current.removeAllHandlers()
            current.set(handler: { [weak item] _ in
                item?.showAllItems?()
            }, for: .Click)
        } else if let view = self.reveal {
            performSubviewRemoval(view, animated: animated)
            self.reveal = nil
        }
        
        
        if let unlockText = item.unlockText {
            if unlockText.1 {
                let isNew: Bool
                let current: UnlockView
                if let view = self.unlock as? UnlockView {
                    current = view
                    isNew = false
                } else {
                    if let view = unlock {
                        performSubviewRemoval(view, animated: animated)
                    }
                    current = UnlockView(frame: rect)
                    current.layer?.cornerRadius = 10
                    self.unlock = current
                    self.addSubview(current)
                    isNew = true
                }
                let size = current.update(name: unlockText.0, width: frame.width - 30, context: item.context, table: item.table)
                current.setAccessibilityLabel(unlockText.0)
                let rect = CGRect(origin: NSMakePoint(frame.width - size.width - 15, 0), size: size)
                if isNew {
                    current.frame = rect
                } else {
                    transition.updateFrame(view: current, frame: rect)
                }
                current.removeAllHandlers()
                current.set(handler: { [weak item] _ in
                    item?.invokeLockAction()
                }, for: .Click)
            } else {
                let current: TextButton
                let isNew: Bool
                if let view = self.unlock as? TextButton {
                    current = view
                    isNew = false
                } else {
                    if let view = unlock {
                        performSubviewRemoval(view, animated: animated)
                    }
                    current = TextButton(frame: .zero)
                    current.autohighlight = false
                    current.scaleOnClick = true
                    current.layer?.cornerRadius = 10
                    self.unlock = current
                    self.addSubview(current)
                    isNew = true
                }
                let primaryColor = item.color ?? theme.colors.accent
                
                current.set(background: unlockText.2 ? primaryColor : primaryColor.withAlphaComponent(0.6), for: .Normal)
                current.set(font: .medium(12), for: .Normal)
                current.set(color: theme.colors.underSelectedColor, for: .Normal)
                current.set(text: unlockText.0, for: .Normal)
                current.sizeToFit(NSMakeSize(10, 10), .zero, thatFit: false)
                current.userInteractionEnabled = unlockText.2
                                
                let rect = CGRect(origin: NSMakePoint(frame.width - current.frame.size.width - 15, 0), size: current.frame.size)
                if isNew {
                    current.frame = rect
                } else {
                    transition.updateFrame(view: current, frame: rect)
                }
                
                current.removeAllHandlers()
                current.set(handler: { [weak item] _ in
                    item?.invokeLockAction()
                }, for: .Click)
            }
            
        } else if let view = self.unlock {
            performSubviewRemoval(view, animated: animated)
            self.unlock = nil
        }
        
        if let unlock = unlock {
            unlock.layer?.cornerRadius = unlock.frame.height / 2
        }
        
        self.updateLayout(size: frame.size, transition: transition)
        
        let color: NSColor
        if let c = item.color {
            color = c
        } else {
            let isPanel = item.mode == .panel || item.mode == .preview
            color = isPanel ? theme.colors.text : theme.colors.accent
        }
        
        self.updateInlineStickers(context: item.context, color: color, contentView: contentView, items: item.items, selected: item.selectedItems, animated: animated, uniqueGifts: item.uniqueGifts)

        while !appearanceViews.isEmpty {
            appearanceViews.removeLast().value?.removeFromSuperview()
        }
    }
    
   
    
    override func updateAnimatableContent() -> Void {
        for (_, value) in self.inlineStickerItemViews {
            if let superview = value.superview {
                var isKeyWindow: Bool = false
                if let window = self.window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                let isVisible = NSIntersectsRect(value.frame, superview.visibleRect)
                value.isVisibleForFetching = isVisible
                value.isPlayable = isVisible && isKeyWindow
            }
        }
    }
    
    private var previousColor: NSColor? = nil
    
    func updateInlineStickers(context: any AccountContextProtocol, color: NSColor, contentView: NSView, items: [EmojiesSectionRowItem.Item], selected: [EmojiesSectionRowItem.SelectedItem], animated: Bool, uniqueGifts: [StarGift.UniqueGift]) {
        var validIds = Set<InlineStickerItemLayer.Key>()
        var validLockIds = Set<InlineStickerItemLayer.Key>()
        var validSelectedIds = Set<InlineStickerItemLayer.Key>()
        
        var index: Int = 0
        
        let animated = animated && previousColor == color

        for item in items {
            if let current = item.item {
                let id = InlineStickerItemLayer.Key(id: current.file.fileId.id, index: index, color: color)
                validIds.insert(id)

                let rect = item.rect
                
                if let selection = item.selection {
                    let order = selected.first(where: { $0.isEqual(to: current.file._parse()) })?.index
                    let current: SimpleLayer
                    if let view = self.selectedLayers[id] {
                        current = view
                    } else {
                        current = SimpleLayer()
                        current.masksToBounds = true
                        current.frame = NSMakeRect(rect.minX - floorToScreenPixels(4.5), rect.minY - floorToScreenPixels(4.5), 34, 33)
                        current.cornerRadius = 10
                        if #available(macOS 10.15, *) {
                            current.cornerCurve = .continuous
                        }
                        contentView.layer?.addSublayer(current)
                        self.selectedLayers[id] = current
                    }
                    
                    
                    
                    switch selection {
                    case .normal:
                        current.backgroundColor = color.withAlphaComponent(0.2).cgColor
                    case .transparent:
                        current.backgroundColor = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1).cgColor
                    }
                    
                    if let order {
                        current.frame = NSMakeRect(rect.midX - emojiSelectionOrderCircleSide / 2, rect.midY - emojiSelectionOrderCircleSide / 2, emojiSelectionOrderCircleSide, emojiSelectionOrderCircleSide)
                        current.cornerRadius = emojiSelectionOrderCircleSide / 2
                        let badge: SimpleLayer
                        if let view = self.orderBadgeLayers[id] {
                            badge = view
                        } else {
                            badge = SimpleLayer()
                            badge.zPosition = 10
                            contentView.layer?.addSublayer(badge)
                            self.orderBadgeLayers[id] = badge
                        }
                        badge.contents = emojiSelectionOrderBadge(order, color: theme.colors.accent)
                        badge.frame = emojiSelectionOrderBadgeFrame(selection: current.frame)
                    } else {
                        current.frame = NSMakeRect(rect.minX - floorToScreenPixels(4.5), rect.minY - floorToScreenPixels(4.5), 34, 33)
                        current.cornerRadius = 10
                        if let badge = self.orderBadgeLayers.removeValue(forKey: id) {
                            badge.removeFromSuperlayer()
                        }
                    }
                    
                    validSelectedIds.insert(id)
                                        
                } else {
                    if let layer = self.selectedLayers[id] {
                        performSublayerRemoval(layer, animated: animated)
                        self.selectedLayers.removeValue(forKey: id)
                    }
                    if let badge = self.orderBadgeLayers.removeValue(forKey: id) {
                        badge.removeFromSuperlayer()
                    }
                }

                let cellSize = (self.item as? EmojiesSectionRowItem)?.itemSize ?? rect.size
                let renderSize = CGSize(width: cellSize.width - 4, height: cellSize.height - 4)
                let view: InlineStickerItemLayer
                if let current = self.inlineStickerItemViews[id], current.bounds.size == renderSize {
                    view = current
                } else {
                    if let layer = self.inlineStickerItemViews[id] {
                        performSublayerRemoval(layer, animated: animated, scale: true)
                    }
                    
                    let uniqueStarAnimation: NSColor? = uniqueGifts.first(where: {
                        $0.file?.fileId == current.file.fileId
                    })?.backdrop?.first
                    
                    let fetchMode: InlineStickerItemLayer.FetchMode
                    #if DEBUG
                    fetchMode = EmojiPanelLab.fetchMode
                    #else
                    fetchMode = .whileVisible
                    #endif
                    view = InlineStickerItemLayer(account: context.account, file: current.file._parse(), size: renderSize, playPolicy: isEmojiLite ? .framesCount(1) : .loop, textColor: color, uniqueStarAnimation: uniqueStarAnimation, fetchMode: fetchMode)
                    self.inlineStickerItemViews[id] = view
                    view.superview = contentView
                    
                    
                    if let uniqueStarAnimation {
                        let starsLayer: StarsEffectLayer
                        if let current = self.starsLayer[id] {
                            starsLayer = current
                        } else {
                            starsLayer = StarsEffectLayer()
                            contentView.layer?.insertSublayer(starsLayer, at: 0)
                            self.starsLayer[id] = starsLayer
                        }
                        let availableSize = rect.size
                        let side = floor(availableSize.width * 1.25)
                        let starsFrame = rect.focus(CGSize(width: side, height: side))
                        starsLayer.frame = rect
                        starsLayer.update(color: uniqueStarAnimation, size: starsFrame.size)
                    } else if let starsLayer = self.starsLayer[id] {
                        self.starsLayer.removeValue(forKey: id)
                        starsLayer.removeFromSuperlayer()
                    }
                    
                    contentView.layer?.addSublayer(view)
                    
                    if animated {
                        view.animateScale(from: 0.1, to: 1, duration: 0.3, timingFunction: .spring)
                        view.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }
                
                if #available(macOS 10.15, *) {
                    view.cornerCurve = .continuous
                }
                view.masksToBounds = true
                view.cornerRadius = item.selection != nil ? 4 : 0
                
                if item.lock {
                    let current: InlineStickerLockLayer
                    if let view = self.locks[id] {
                        current = view
                    } else {
                        current = InlineStickerLockLayer(frame: CGRect(origin: rect.origin.offsetBy(dx: rect.width - 15, dy: rect.height - 15), size: NSMakeSize(15, 15)))
                        contentView.layer?.addSublayer(current)
                        self.locks[id] = current
                    }
                    validLockIds.insert(id)
                    
                    current.tieToLayer(view)
                    
                } else {
                    if let lockView = self.locks[id] {
                        performSublayerRemoval(lockView, animated: animated)
                        self.locks.removeValue(forKey: id)
                    }
                }
                
               
                
                index += 1
                let scale: CGFloat = item.selection == nil ? 1.0 : 0.8
                let previousScale = view.presentation()?.transform.m11 ?? view.transform.m11
                let scaleChanged = view.transform.m11 != scale
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                view.bounds = CGRect(origin: .zero, size: renderSize)
                view.position = CGPoint(x: rect.midX, y: rect.midY)
                view.transform = CATransform3DMakeScale(scale, scale, 1)
                CATransaction.commit()
                if animated, scaleChanged {
                    view.animateScale(from: previousScale, to: scale, duration: 0.18, timingFunction: .easeOut)
                }
            }
        }

        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                if previousColor != color {
                    delay(0.1, closure: {
                        performSublayerRemoval(itemLayer, animated: animated, scale: true)
                    })
                } else {
                    performSublayerRemoval(itemLayer, animated: animated, scale: true)
                }
                
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
            self.starsLayer.removeValue(forKey: key)
        }
        
        var removeLockKeys: [InlineStickerItemLayer.Key] = []
        for (key, view) in self.locks {
            if !validLockIds.contains(key) {
                removeLockKeys.append(key)
                performSublayerRemoval(view, animated: animated)
            }
        }
        for key in removeLockKeys {
            self.locks.removeValue(forKey: key)
        }
        
        var removeSelectionKeys: [InlineStickerItemLayer.Key] = []
        for (key, view) in self.selectedLayers {
            if !validSelectedIds.contains(key) {
                removeSelectionKeys.append(key)
                performSublayerRemoval(view, animated: animated)
            }
        }
        for key in removeSelectionKeys {
            self.selectedLayers.removeValue(forKey: key)
            if let badge = self.orderBadgeLayers.removeValue(forKey: key) {
                badge.removeFromSuperlayer()
            }
        }
        self.previousColor = color
        self.updateAnimatableContent()
    }
    
    override var isEmojiLite: Bool {
        if let item = item as? EmojiesSectionRowItem {
            if item.mode == .topic || item.mode == .backgroundIcon {
                return true
            }
            return item.context.isLite(.emoji)
        }
        
        return super.isEmojiLite
    }
    
    deinit {
        var bp = 0
        bp += 1
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
