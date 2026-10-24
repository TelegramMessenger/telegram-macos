import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import LocalAnimations
import InlineStickerLayer
import InputDataUI

public struct StickerPackPanelAddTile {
    public enum Position {
        case leading
        case trailing
    }
    public let position: Position
    public let accessibilityLabel: String
    public let action: (Control) -> Void

    public init(position: Position, accessibilityLabel: String, action: @escaping (Control) -> Void) {
        self.position = position
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}

public struct StickerPackPanelEditing {
    public let isEditing: Bool
    public let menuItems: (TelegramMediaFile) -> [ContextMenuItem]
    public let reorder: (TelegramMediaFile, Int) -> Void

    public init(isEditing: Bool, menuItems: @escaping (TelegramMediaFile) -> [ContextMenuItem], reorder: @escaping (TelegramMediaFile, Int) -> Void) {
        self.isEditing = isEditing
        self.menuItems = menuItems
        self.reorder = reorder
    }
}

private func stickerEditBadgeColor(_ image: CGImage) -> NSColor? {
    let side = 16
    let size = CGFloat(side)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data else {
        return nil
    }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.draw(image, in: CGRect(x: -size / 2, y: -size / 2, width: size * 1.8, height: size * 1.8))

    let pixels = data.assumingMemoryBound(to: UInt8.self)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    for i in 0 ..< side * side {
        r += CGFloat(pixels[i * 4])
        g += CGFloat(pixels[i * 4 + 1])
        b += CGFloat(pixels[i * 4 + 2])
    }
    let total = CGFloat(side * side) * 255
    r /= total
    g /= total
    b /= total

    let saturation: CGFloat = 1.7
    let rw = (1 - saturation) * 0.3086
    let gw = (1 - saturation) * 0.6094
    let bw = (1 - saturation) * 0.0820
    let clamp: (CGFloat) -> CGFloat = { min(1, max(0, $0)) }
    let red = clamp((rw + saturation) * r + gw * g + bw * b) * 0.9 + 0.1
    let green = clamp(rw * r + (gw + saturation) * g + bw * b) * 0.9 + 0.1
    let blue = clamp(rw * r + gw * g + (bw + saturation) * b) * 0.9 + 0.1

    var color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    if color.lightness > 0.8 {
        color = color.withMultipliedBrightnessBy(0.8)
    }
    return color
}

private func stickerEditBadgeImage(_ color: NSColor) -> CGImage? {
    return generateImage(NSMakeSize(20, 20), rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: size.bounds)
        ctx.setFillColor(NSColor.white.cgColor)
        let dot: CGFloat = 2.2
        for i in 0 ..< 3 {
            ctx.fillEllipse(in: NSMakeRect(5.4 + CGFloat(i) * 3.5, (size.height - dot) / 2, dot, dot))
        }
    })
}

public class StickerPackPanelRowItem: TableRowItem {
    public private(set) var files: [(TelegramMediaFile, NSPoint)] = []
    public let packNameLayout: TextViewLayout?
    
    public let context: any AccountContextProtocol
    public let arguments: StickerPanelArguments
    public let namePoint: NSPoint
    public let packInfo: StickerPackInfo
    public let collectionId: StickerPackCollectionId
    public let _files:[TelegramMediaFile]
    
    
    
    private var _height: CGFloat = 0
    public override var stableId: AnyHashable {
        return collectionId
    }
    public let packReference: StickerPackReference?
        
    private let preloadFeaturedDisposable = MetaDisposable()
    public let canSend: Bool
    public let playOnHover: Bool
    public let isPreview: Bool
    public let canSchedule: Bool
    public let addTile: StickerPackPanelAddTile?
    public let editing: StickerPackPanelEditing?
    public private(set) var addTileRect: NSRect?
    public private(set) var slots: [NSPoint] = []
    public init(_ initialSize: NSSize, context: any AccountContextProtocol, arguments: StickerPanelArguments, files:[TelegramMediaFile], packInfo: StickerPackInfo, collectionId: StickerPackCollectionId, canSend: Bool, playOnHover: Bool = false, isPreview: Bool = false, addTile: StickerPackPanelAddTile? = nil, editing: StickerPackPanelEditing? = nil) {
        
        
        let files = files.sorted(by: { lhs, rhs in
            if lhs.isPremiumSticker && !rhs.isPremiumSticker {
                if lhs.isPremiumSticker {
                    return false
                } else {
                    return true
                }
            } else if !lhs.isPremiumSticker && rhs.isPremiumSticker {
                if lhs.isPremiumSticker {
                    return false
                } else {
                    return true
                }
            }
            return false
        })
        
        self.context = context
        self.arguments = arguments
        self.canSend = canSend
        self._files = files
        self.playOnHover = playOnHover
        self.isPreview = isPreview
        self.addTile = addTile
        self.editing = editing
        self.canSchedule = arguments.canSchedule()
        let title: String?
        var count: Int32 = 0
        switch packInfo {
        case let .pack(info, _, _):
            title = info?.title ?? info?.shortName ?? ""
            count = info?.count ?? 0
            if let info = info {
                self.packReference = .id(id: info.id.id, accessHash: info.accessHash)
            } else {
                self.packReference = nil
            }
        case .recent:
            title = strings().stickersRecent
            self.packReference = nil
        case .premium:
            title = strings().stickersPremium
            self.packReference = nil
        case .saved:
            title = nil
            self.packReference = nil
        case .emojiRelated:
            title = nil
            self.packReference = nil
        case let .speficicPack(info):
            title = info?.title ?? info?.shortName ?? ""
            if let info = info {
                self.packReference = .id(id: info.id.id, accessHash: info.accessHash)
            } else {
                self.packReference = nil
            }
        }
        
        if let title = title {
            let attributed = NSMutableAttributedString()
            if packInfo.featured {
                _ = attributed.append(string: title.uppercased(), color: theme.colors.text, font: .medium(14))
                _ = attributed.append(string: "\n")
                _ = attributed.append(string: strings().stickersCountOther(Int(count)), color: theme.colors.grayText, font: .normal(12))
            } else {
                _ = attributed.append(string: title.uppercased(), color: theme.colors.grayText, font: .medium(.text))
            }
            let layout = TextViewLayout(attributed, alwaysStaticItems: true)
            layout.measure(width: 260)
            self.packNameLayout = layout
            
            self.namePoint = NSMakePoint(10, floorToScreenPixels(System.backingScale, ((packInfo.featured ? 50 : 30) - layout.layoutSize.height) / 2))
        } else {
            namePoint = NSZeroPoint
            self.packNameLayout = nil
        }
        
        self.packInfo = packInfo
        self.collectionId = collectionId
        
        
       
        
        if packInfo.featured, let id = collectionId.itemCollectionId {
            preloadFeaturedDisposable.set(preloadedFeaturedStickerSet(network: context.account.network, postbox: context.account.postbox, id: id).start())
        }

        
        super.init(initialSize)
        
        _ = makeSize(initialSize.width, oldWidth: 0)
        
    }
    
    public override func makeSize(_ width: CGFloat = CGFloat.greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        let width = max(width, 350)
        
        let size: NSSize = NSMakeSize(60, 60)

        var point: NSPoint = NSMakePoint(5, packNameLayout == nil ? 5 : !packInfo.featured ? 35 : 55)
        var slots: [NSPoint] = []
                
        for _ in 0 ..< _files.count + (addTile != nil ? 1 : 0) {
            slots.append(point)

            point.x += size.width + 10
            if point.x + size.width >= width {
                point.y += size.height + 5
                point.x = 5
            }
        }
        
        self.addTileRect = nil
        if let addTile = addTile, let slot = addTile.position == .leading ? slots.first : slots.last {
            self.addTileRect = CGRect(origin: slot, size: size)
            switch addTile.position {
            case .leading:
                slots.removeFirst()
            case .trailing:
                slots.removeLast()
            }
        }
        
        self.slots = slots
        self.files = zip(_files, slots).map { file, slot in
            return (file, self.filePoint(file, slot: slot))
        }


        if point.x == 5 {
            _height = point.y
        } else {
            _height = point.y + size.height + 5
        }
        

        
        return true
    }
    
    public func filePoint(_ file: TelegramMediaFile, slot: NSPoint) -> NSPoint {
        let size: NSSize = NSMakeSize(60, 60)
        let fileSize = file.dimensions?.size.aspectFitted(size) ?? size
        return NSMakePoint(slot.x + (size.width - fileSize.width) / 2, slot.y + (size.height - fileSize.height) / 2)
    }
    
    public func slotIndex(at point: NSPoint) -> Int? {
        var nearest: (index: Int, distance: CGFloat)?
        for (index, slot) in slots.enumerated() {
            let dx = point.x - (slot.x + 30)
            let dy = point.y - (slot.y + 30)
            let distance = dx * dx + dy * dy
            if nearest == nil || distance < nearest!.distance {
                nearest = (index, distance)
            }
        }
        return nearest?.index
    }
        
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        let context = self.context
        if arguments.mode != .common {
            return .single([])
        }
        let files = self.files
        let packInfo = self.packInfo
        let canSend = self.canSend
        
        let _savedStickersData: Signal<(count: Int, savedIds: Set<MediaId>), NoError> = context.account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudSavedStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: nil, count: 100) |> take(1) |> map { view in
            let items = view.orderedItemListsViews[0].items
            let ids = Set(items.compactMap { ($0.contents.get(SavedStickerItem.self))?.file.fileId })
            return (items.count, ids)
        } |> deliverOnMainQueue

        return _savedStickersData |> map { [weak self] savedStickersData in
            let savedStickersCount = savedStickersData.count
            let savedIds = savedStickersData.savedIds
            var items:[ContextMenuItem] = []

            for file in files {
                let rect = NSMakeRect(file.1.x, file.1.y, 60, 60)
                let file = file.0
                if NSPointInRect(location, rect) {

                    if file.isPremiumSticker && !context.isPremium {
                        return []
                    }

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

                    inner: switch packInfo {
                    case .saved, .recent:
                        if let reference = file.stickerReference {
                            items.append(ContextMenuItem(strings().contextViewStickerSet, handler: { [weak self] in
                                self?.arguments.showPack(reference)
                            }, itemImage: MenuAnimation.menu_view_sticker_set.value))
                        }
                    default:
                        break inner
                    }
                    let isSaved = savedIds.contains(file.fileId) || packInfo == .saved
                    if packInfo != .saved, packInfo.installed || packInfo == .recent {
                        if !isSaved {
                            items.append(ContextMenuItem(strings().chatContextAddFavoriteSticker, handler: {
                                let limit = context.isPremium ? context.premiumLimits.stickers_faved_limit_premium : context.premiumLimits.stickers_faved_limit_default
                                if limit >= savedStickersCount, !context.isPremium {
                                    showModalText(for: context.window, text: strings().chatContextFavoriteStickersLimitInfo("\(context.premiumLimits.stickers_faved_limit_premium)"), title: strings().chatContextFavoriteStickersLimitTitle, callback: { value in
                                        FeatureNavigationHooks.shared.showPremiumLimit(context, .faveStickers)
                                    })
                                } else {
                                    showModalText(for: context.window, text: strings().chatContextStickerAddedToFavorites)
                                }
                                _ = addSavedSticker(postbox: context.account.postbox, network: context.account.network, file: file).start()
                            }, itemImage: MenuAnimation.menu_add_to_favorites.value))
                        } else {
                            items.append(ContextMenuItem(strings().chatContextRemoveFavoriteSticker, handler: {
                                showModalText(for: context.window, text: strings().chatContextStickerRemovedFromFavorites)
                                _ = removeSavedSticker(postbox: context.account.postbox, mediaId: file.fileId).start()
                            }, itemImage: MenuAnimation.menu_remove_from_favorites.value))
                        }
                    }

                    if canSend {
                        items.append(ContextMenuItem(strings().chatSendWithoutSound, handler: { [weak self] in
                            guard let `self` = self else {
                                return
                            }

                            if let contentView = self.view {
                                self.arguments.sendMedia(file, contentView, true, false, self.collectionId.itemCollectionId)
                            }
                        }, itemImage: MenuAnimation.menu_mute.value))


                        if self?.canSchedule == true {
                            items.append(ContextMenuItem(strings().chatSendScheduledMessage, handler: { [weak self] in
                                guard let `self` = self else {
                                    return
                                }

                                if let contentView = self.view {
                                    self.arguments.sendMedia(file, contentView, false, true, self.collectionId.itemCollectionId)
                                }
                            }, itemImage: MenuAnimation.menu_schedule_message.value))
                        }
                    }
                    if packInfo == .recent {
                        items.append(ContextMenuItem(strings().searchRemoveFromRecent, handler: {
                            context.engine.stickers.removeRecentlyUsedSticker(fileReference: .recentSticker(media: file))
                        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                    } else if packInfo == .saved {
                        if let mediaId = file.id {
                            items.append(ContextMenuItem(strings().contextRemoveFaveSticker, handler: {
                                showModalText(for: context.window, text: strings().chatContextStickerRemovedFromFavorites)
                                _ = removeSavedSticker(postbox: context.account.postbox, mediaId: mediaId).start()
                            }, itemMode: .destruct, itemImage: MenuAnimation.menu_remove_from_favorites.value))
                        }
                    }
                    if let editing = self?.editing {
                        items.append(contentsOf: editing.menuItems(file))
                    }
                    break
                }
            }
            return items
        }
        
    }
    
    deinit {
        preloadFeaturedDisposable.dispose()
    }
    
    public override var height: CGFloat {
        return _height
    }
    
    public override func viewClass() -> AnyClass {
        return StickerPackPanelRowView.self
    }
    
    public override var accessibilityLabel: String? {
        switch packInfo {
        case let .pack(info, _, _):
            return info?.title ?? info?.shortName ?? strings().voiceOverStickers
        case let .speficicPack(info):
            return info?.title ?? info?.shortName ?? strings().voiceOverStickers
        case .recent:
            return strings().stickersRecent
        case .premium:
            return strings().stickersPremium
        case .saved:
            return strings().stickersFavorite
        case .emojiRelated:
            return strings().voiceOverStickers
        }
    }
}



private final class StickerPackPanelRowView : TableRowView, ModalPreviewRowViewProtocol {
    
    private struct ReorderState {
        let file: TelegramMediaFile
        let layer: InlineStickerItemLayer
        let start: NSPoint
        let origin: NSPoint
        var order: [TelegramMediaFile]
        var isDragging: Bool
    }
    
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineStickerItemLayer] = [:]
    private var editBadges: [InlineStickerItemLayer.Key: SimpleLayer] = [:]
    private var reorderState: ReorderState?
    private var addTileView: ImageButton?
    private var previewAnchor: NSView?
    
    private func previewAnchor(for layer: InlineStickerItemLayer) -> NSView {
        let anchor: NSView
        if let current = self.previewAnchor {
            anchor = current
        } else {
            anchor = NSView()
            anchor.isHidden = true
            contentView.addSubview(anchor)
            self.previewAnchor = anchor
        }
        anchor.frame = layer.frame
        return anchor
    }
    
    func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        
        if let (layer, file) = itemUnderMouse {
            let view = previewAnchor(for: layer)
            let reference = file.stickerReference != nil ? FileMediaReference.stickerPack(stickerPack: file.stickerReference!, media: file) : FileMediaReference.standalone(media: file)
            if file.isVideoSticker && !file.isWebm {
                return (.file(reference, EntertainmentUIHooks.shared.previewViewType(.gif)), view)
            } else if file.isAnimatedSticker || file.isWebm {
                return (.file(reference, EntertainmentUIHooks.shared.previewViewType(.animatedSticker)), view)
            } else if file.isStaticSticker {
                return (.file(reference, EntertainmentUIHooks.shared.previewViewType(.sticker)), view)
            }

        }

        return nil
    }
    
    private let contentView = EntertainmentGridControl()
    
    private let packNameView = TextView()
    private var clearRecentButton: ImageButton?
    private var addButton:TextButton?
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(contentView)
        addSubview(packNameView)
        packNameView.userInteractionEnabled = false
        packNameView.isSelectable = false
        
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
            self?.updateAnimatableContent()
        }, for: .Other)
        
        contentView.set(handler: { [weak self] _ in
            let item = self?.item as? StickerPackPanelRowItem
            let table = item?.table
            let window = self?.window as? Window
            if let item = item, let table = table, let window = window, item.editing?.isEditing != true {
                startModalPreviewHandle(table, window: window, context: item.context)
            }
        }, for: .LongMouseDown)
    }
    
    private var isEditing: Bool {
        return (item as? StickerPackPanelRowItem)?.editing?.isEditing == true
    }
    
    private var currentDownItem: (InlineStickerItemLayer, TelegramMediaFile, Bool)?
    private func updateDown() {
        if isEditing {
            if let (layer, file) = itemUnderMouse, let item = item as? StickerPackPanelRowItem, let window = window {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                reorderState = ReorderState(file: file, layer: layer, start: point, origin: layer.position, order: item.files.map { $0.0 }, isDragging: false)
            }
            return
        }
        if let item = itemUnderMouse {
            self.currentDownItem = (item.0, item.1, true)
        }
        if let itemUnderMouse = self.currentDownItem {
            itemUnderMouse.0.animateScale(from: 1, to: 0.95, duration: 0.2, removeOnCompletion: false)
        }
    }
    private func updateDragging() {
        if reorderState != nil {
            updateReorder()
            return
        }
        if let current = self.currentDownItem {
            if self.itemUnderMouse?.1 != current.1, current.2  {
                current.0.animateScale(from: 0.95, to: 1, duration: 0.2, removeOnCompletion: true)
                self.currentDownItem?.2 = false
            } else if !current.2, self.itemUnderMouse?.1 == current.1 {
                current.0.animateScale(from: 1, to: 0.95, duration: 0.2, removeOnCompletion: false)
                self.currentDownItem?.2 = true
            }
        }
            
    }
    private func updateUp() {
        if let state = reorderState {
            reorderState = nil
            endReorder(state)
            return
        }
        if let itemUnderMouse = self.currentDownItem {
            itemUnderMouse.0.animateScale(from: 0.95, to: 1, duration: 0.2, removeOnCompletion: true)
            if itemUnderMouse.1 == self.itemUnderMouse?.1 {
                self.click()
            }
        }
        self.currentDownItem = nil
    }
    
    private func slotPosition(_ file: TelegramMediaFile, index: Int, item: StickerPackPanelRowItem) -> NSPoint? {
        guard index < item.slots.count else {
            return nil
        }
        let origin = item.filePoint(file, slot: item.slots[index])
        return NSMakePoint(origin.x + 30, origin.y + 30)
    }
    
    private func move(_ layer: CALayer, to position: NSPoint, completion: ((Bool) -> Void)? = nil) {
        guard layer.position != position else {
            completion?(true)
            return
        }
        layer.animatePosition(from: layer.presentation()?.position ?? layer.position, to: position, duration: 0.2, completion: completion)
        layer.position = position
    }
    
    private func updateReorder() {
        guard var state = reorderState, let item = item as? StickerPackPanelRowItem, let window = window else {
            return
        }
        let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if !state.isDragging {
            guard abs(point.x - state.start.x) > 4 || abs(point.y - state.start.y) > 4 else {
                return
            }
            state.isDragging = true
            state.layer.zPosition = 1
        }
        state.layer.removeAnimation(forKey: "position")
        state.layer.position = NSMakePoint(state.origin.x + point.x - state.start.x, state.origin.y + point.y - state.start.y)
        
        if let target = item.slotIndex(at: point), let current = state.order.firstIndex(where: { $0.fileId == state.file.fileId }), target != current {
            state.order.insert(state.order.remove(at: current), at: target)
            for (index, file) in state.order.enumerated() where file.fileId != state.file.fileId {
                if let layer = inlineStickerItemViews[InlineStickerItemLayer.Key(id: file.fileId.id, index: 0)], let position = slotPosition(file, index: index, item: item) {
                    move(layer, to: position)
                }
            }
        }
        reorderState = state
    }
    
    private func endReorder(_ state: ReorderState) {
        guard let item = item as? StickerPackPanelRowItem else {
            return
        }
        guard state.isDragging else {
            showEditingMenu(state.file)
            return
        }
        guard let index = state.order.firstIndex(where: { $0.fileId == state.file.fileId }), let position = slotPosition(state.file, index: index, item: item) else {
            state.layer.zPosition = 0
            return
        }
        let layer = state.layer
        move(layer, to: position, completion: { _ in
            layer.zPosition = 0
        })
        if let previous = item.files.firstIndex(where: { $0.0.fileId == state.file.fileId }), previous != index {
            item.editing?.reorder(state.file, index)
        }
    }
    
    private func showEditingMenu(_ file: TelegramMediaFile) {
        guard let item = item as? StickerPackPanelRowItem, let event = NSApp.currentEvent, let point = item.files.first(where: { $0.0.fileId == file.fileId })?.1 else {
            return
        }
        _ = (item.menuItems(in: NSMakePoint(point.x + 1, point.y + 1)) |> deliverOnMainQueue).start(next: { [weak self] items in
            guard let self = self, !items.isEmpty else {
                return
            }
            ContextMenu.show(items: items, view: self.contentView, event: event)
        })
    }
    
    private func startShaking(_ layer: CALayer) {
        guard layer.animation(forKey: "shaking_rotation") == nil else {
            return
        }
        let angle = CGFloat.pi * 2.0 / 180.0
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [-angle, angle, -angle]
        animation.duration = 0.4
        animation.repeatCount = .infinity
        animation.timeOffset = Double.random(in: 0 ... 0.4)
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "shaking_rotation")
    }
    
    private func updateEditBadge(_ layer: InlineStickerItemLayer, key: InlineStickerItemLayer.Key, visible: Bool, animated: Bool) {
        if visible {
            guard editBadges[key] == nil else {
                return
            }
            let badge = SimpleLayer()
            badge.zPosition = 1
            badge.frame = NSMakeRect(3, 3, 20, 20)
            layer.addSublayer(badge)
            editBadges[key] = badge

            let apply: (CGImage) -> Bool = { [weak badge] image in
                guard let badge = badge, let color = stickerEditBadgeColor(image) else {
                    return false
                }
                badge.contents = stickerEditBadgeImage(color)
                return true
            }
            if let contents = layer.contents, apply(contents as! CGImage) {
                if animated {
                    badge.animateScale(from: 0.01, to: 1, duration: 0.2)
                }
            } else {
                layer.contentDidUpdate = { [weak layer] image in
                    if apply(image) {
                        layer?.contentDidUpdate = nil
                    }
                }
            }
        } else if let badge = editBadges.removeValue(forKey: key) {
            layer.contentDidUpdate = nil
            performSublayerRemoval(badge, animated: animated, scale: true)
        }
    }
    
    private func accessibilityCells() -> [EntertainmentAccessibilityCell] {
        guard let item = self.item as? StickerPackPanelRowItem else {
            return []
        }
        return item.files.enumerated().map { index, value in
            let file = value.0
            let size = file.dimensions?.size.aspectFitted(NSMakeSize(60, 60)) ?? NSMakeSize(60, 60)
            return EntertainmentAccessibilityCell(id: AnyHashable(index), label: file.stickerText ?? strings().voiceOverCommonSticker, frame: CGRect(origin: value.1, size: size), press: { [weak self, weak item] in
                guard let self = self, let item = item else {
                    return
                }
                if let reference = item.packReference, item.packInfo.featured {
                    item.arguments.showPack(reference)
                } else {
                    item.arguments.sendMedia(file, self.contentView, false, false, item.collectionId.itemCollectionId)
                }
            })
        }
    }
    
    private func click() {
        if let item = self.item as? StickerPackPanelRowItem {
            if self.packNameView.mouseInside() {
                if let reference = item.packReference {
                    item.arguments.showPack(reference)
                }
            } else {
                if let reference = item.packReference, item.packInfo.featured {
                    item.arguments.showPack(reference)
                } else if let current = self.currentDownItem {
                    item.arguments.sendMedia(current.1, contentView, false, false, item.collectionId.itemCollectionId)
                }
            }
        }

    }
    
    private var itemUnderMouse: (InlineStickerItemLayer, TelegramMediaFile)? {
        guard let window = self.window, let item = self.item as? StickerPackPanelRowItem else {
            return nil
        }
        let point = self.contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        
        let firstItem = item.files.first(where: {
            return NSPointInRect(point, CGRect.init(origin: $0.1, size: NSMakeSize(60, 60)))
        })?.0
        let firstLayer = self.inlineStickerItemViews.first(where: { layer in
            return NSPointInRect(point, layer.1.frame)
        })?.value
        
        if let firstItem = firstItem, let firstLayer = firstLayer {
            return (firstLayer, firstItem)
        }
        
        return nil
    }
    

    override func updateAnimatableContent() -> Void {
        var isKeyWindow: Bool = false
        if let window = self.window {
            if !window.canBecomeKey {
                isKeyWindow = true
            } else {
                isKeyWindow = window.isKeyWindow
            }
        }
        let visibleRect = contentView.visibleRect
        for (_, layer) in self.inlineStickerItemViews {
            layer.isPlayable = isKeyWindow && NSIntersectsRect(layer.frame, visibleRect)
        }
    }
    
    override var isEmojiLite: Bool {
        if let item = item as? StickerPackPanelRowItem {
            return item.context.isLite(.stickers)
        }
        return super.isEmojiLite
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func layout() {
        super.layout()
        
        guard let item = item as? StickerPackPanelRowItem else {
            return
        }
        self.packNameView.setFrameOrigin(item.namePoint)
        self.clearRecentButton?.setFrameOrigin(frame.width - 34, item.namePoint.y - 10)
        
        self.contentView.frame = bounds
        if let rect = item.addTileRect {
            self.addTileView?.frame = rect
        }

    }

    override var backdorColor: NSColor {
        return .clear
    }
    

    func updateInlineStickers(context: any AccountContextProtocol, contentView: NSView, items: [(TelegramMediaFile, NSPoint)], animated: Bool, editing: StickerPackPanelEditing?) {
        var validIds: [InlineStickerItemLayer.Key] = []
        var index: Int = 0

        for item in items {
            let id = InlineStickerItemLayer.Key(id: item.0.fileId.id, index: editing != nil ? 0 : index)
            validIds.append(id)

            let rect = CGRect(origin: item.1, size: NSMakeSize(60, 60))

            let view: InlineStickerItemLayer
            if let current = self.inlineStickerItemViews[id], current.frame.size == rect.size {
                view = current
            } else {
                if let layer = self.inlineStickerItemViews[id] {
                    performSublayerRemoval(layer, animated: animated, scale: true)
                }
                view = InlineStickerItemLayer(account: context.account, file: item.0, size: rect.size)
                view.masksToBounds = true
                view.superview = contentView
                self.inlineStickerItemViews[id] = view
                contentView.layer?.addSublayer(view)
                if animated {
                    view.animateScale(from: 0.1, to: 1, duration: 0.2)
                }
            }
            index += 1

            view.frame = rect
            
            if editing?.isEditing == true {
                startShaking(view)
            } else {
                view.removeAnimation(forKey: "shaking_rotation")
            }
            updateEditBadge(view, key: id, visible: editing?.isEditing == true, animated: animated)
        }

        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                performSublayerRemoval(itemLayer, animated: animated, scale: true)
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
            self.editBadges.removeValue(forKey: key)
        }
        self.updateAnimatableContent()
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StickerPackPanelRowItem else {
            return
        }
        
        packNameView.update(item.packNameLayout)
        
        
        if item.arguments.mode == .common {
            switch item.packInfo {
            case .recent:
                if self.clearRecentButton == nil {
                    self.clearRecentButton = ImageButton()
                    self.clearRecentButton?.setAccessibilityLabel(strings().voiceOverCommonClear)
                    addSubview(self.clearRecentButton!)
                }
                self.clearRecentButton?.set(image: theme.icons.wallpaper_color_close, for: .Normal)
                _ = self.clearRecentButton?.sizeToFit(NSMakeSize(5, 5), thatFit: false)
                
                self.clearRecentButton?.removeAllHandlers()
                
                self.clearRecentButton?.set(handler: { [weak item] _ in
                    item?.arguments.clearRecent()
                }, for: .Click)
            default:
                self.clearRecentButton?.removeFromSuperview()
                self.clearRecentButton = nil
            }
        } else {
            self.clearRecentButton?.removeFromSuperview()
            self.clearRecentButton = nil
        }
       
               
        self.addButton?.removeFromSuperview()
        self.addButton = nil
        
        if let reference = item.packReference, item.packInfo.featured {
            if !item.packInfo.installed {
                self.addButton = TextButton()
                self.addButton!.set(background: theme.colors.accentSelect, for: .Normal)
                self.addButton!.set(background: theme.colors.accentSelect.withAlphaComponent(0.8), for: .Highlight)
                self.addButton!.set(font: .medium(.text), for: .Normal)
                self.addButton!.set(color: theme.colors.underSelectedColor, for: .Normal)
                self.addButton!.set(text: strings().stickersSearchAdd, for: .Normal)
                self.addButton?.setAccessibilityLabel(strings().stickersSearchAdd)
                _ = self.addButton!.sizeToFit(NSMakeSize(14, 8), thatFit: true)
                self.addButton!.layer?.cornerRadius = .cornerRadius
                self.addButton!.setFrameOrigin(frame.width - self.addButton!.frame.width - 10, 13)
                
                self.addButton!.set(handler: { [weak item] _ in
                    item?.arguments.addPack(reference)
                }, for: .Click)
            } else {
                self.addButton = TextButton()
                self.addButton!.set(background: theme.colors.grayForeground, for: .Normal)
                self.addButton!.set(background: theme.colors.grayForeground.withAlphaComponent(0.8), for: .Highlight)
                self.addButton!.set(font: .medium(.text), for: .Normal)
                self.addButton!.set(color: theme.colors.underSelectedColor, for: .Normal)
                self.addButton!.set(text: strings().stickersSearchAdded, for: .Normal)
                self.addButton?.setAccessibilityLabel(strings().stickersSearchAdded)
                _ = self.addButton!.sizeToFit(NSMakeSize(14, 8), thatFit: true)
                self.addButton!.layer?.cornerRadius = .cornerRadius
                self.addButton!.setFrameOrigin(frame.width - self.addButton!.frame.width - 10, 13)
                
                self.addButton!.set(handler: { [weak item] _ in
                    if let item = item {
                        item.arguments.removePack(item.collectionId)
                    }
                },  for: .Click)
            }
            addSubview(addButton!)
        }
        
        if let addTile = item.addTile {
            let current: ImageButton
            if let view = self.addTileView {
                current = view
            } else {
                current = ImageButton()
                current.autohighlight = false
                current.scaleOnClick = true
                current.layer?.cornerRadius = 10
                addSubview(current)
                self.addTileView = current
            }
            if let image = generateImage(NSMakeSize(24, 24), rotatedContext: { size, ctx in
                ctx.clear(size.bounds)
                ctx.setStrokeColor(theme.colors.accent.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineCap(.round)
                ctx.move(to: NSMakePoint(size.width / 2, 4))
                ctx.addLine(to: NSMakePoint(size.width / 2, size.height - 4))
                ctx.move(to: NSMakePoint(4, size.height / 2))
                ctx.addLine(to: NSMakePoint(size.width - 4, size.height / 2))
                ctx.strokePath()
            }) {
                current.set(image: image, for: .Normal)
            }
            current.set(background: theme.colors.grayBackground, for: .Normal)
            current.setAccessibilityLabel(addTile.accessibilityLabel)
            current.toolTip = addTile.accessibilityLabel
            current.removeAllHandlers()
            current.set(handler: { control in
                addTile.action(control)
            }, for: .Click)
        } else {
            self.addTileView?.removeFromSuperview()
            self.addTileView = nil
        }
        
        if item.editing?.isEditing != true {
            self.reorderState = nil
        }
        
        self.layout()
        
        self.updateInlineStickers(context: item.context, contentView: contentView, items: item.files, animated: animated, editing: item.editing)
        
    }
    
}
