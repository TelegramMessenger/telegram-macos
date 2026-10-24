import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
import ChatUI
import GalleryUI
import GeneralRows
import LocalAnimations
import Localization
import MessageUtils
import TelegramContext
import TelegramMediaUtils
import TelegramTheme


public class PeerMediaRowItem: GeneralRowItem {
    
    
    public var contentInset:NSEdgeInsets = NSEdgeInsets(left: 50.0, right: 0, top: 0, bottom: 0)
    
    public var contentSize:NSSize = NSMakeSize(0, 40)
    
    public override var height: CGFloat {
        return contentSize.height + viewType.innerInset.top + viewType.innerInset.bottom + inset.top + inset.bottom
    }
    
    private var entry:PeerMediaSharedEntry
    public let message:Message
    public let interface:ChatInteraction
    public let automaticDownload: AutomaticMediaDownloadSettings
    public let context: any AccountContextProtocol
    public let galleryType: GalleryAppearType
    public let gallery: (Message, GalleryAppearType)->Void
    public init(_ initialSize:NSSize, _ interface:ChatInteraction, _ object: PeerMediaSharedEntry, galleryType: GalleryAppearType = .history, gallery: @escaping(Message, GalleryAppearType)->Void, viewType: GeneralViewType = .legacy, inset: NSEdgeInsets = NSEdgeInsetsZero, customTheme: GeneralRowItem.Theme? = nil) {
        self.entry = object
        self.interface = interface
        self.galleryType = galleryType
        self.gallery = gallery
        self.context = interface.interactionContext
        if case let .messageEntry(message, _, automaticDownload, _) = object {
            self.message = message
            self.automaticDownload = automaticDownload
        } else {
            fatalError("entry haven't message")
        }

        super.init(initialSize, stableId: object.stableId, viewType: viewType, inset: inset, customTheme: customTheme, fullSize: true)
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {

        var resourceData: Signal<(TelegramMediaFile, MediaResourceData)?, NoError> = .single(nil)
        
        let context = self.interface.interactionContext
        if let file = self.message.anyMedia as? TelegramMediaFile {
            resourceData = context.account.postbox.mediaBox.resourceData(file.resource) |> map {
                (file, $0)
            }
        }
        
        let message = self.message
        let interface = self.interface
        let messageId = self.message.id
        let mode = self.galleryType
                
        return resourceData
        |> take(1)
        |> deliverOnMainQueue
        |> map { resourceData in
            
            var items:[ContextMenuItem] = []
            
            
            var firstBlock:[ContextMenuItem] = []
            var secondBlock: [ContextMenuItem] = []
            var thirdBlock: [ContextMenuItem] = []
            
            
            

            let isCopyProtected = message.isCopyProtected() || message.peers[message.id.peerId]?.isCopyProtected(cachedData: interface.presentation.cachedData) == true
            if let resourceData = resourceData, !isCopyProtected {
                firstBlock.append(ContextMenuItem(strings().contextSaveMedia, handler: {
                    saveAs(resourceData.0, account: context.account, context: context, message: message)
                }, itemImage: MenuAnimation.menu_save_as.value))
                if resourceData.1.complete {
                    firstBlock.append(ContextMenuItem(strings().contextShowInFinder, handler: {
                        showInFinder(resourceData.0, account: context.account)
                    }, itemImage: MenuAnimation.menu_show_in_finder.value))
                }
            }
            
       
            secondBlock.append(ContextMenuItem(strings().messageContextSelect, handler: {
                interface.update({$0.withToggledSelectedMessage(message.id)})
            }, itemImage: MenuAnimation.menu_select_messages.value))
            
            if canForwardMessage(message, chatInteraction: interface) {
                secondBlock.append(ContextMenuItem(strings().messageContextForward, handler: {
                    interface.forwardMessages([message])
                }, itemImage: MenuAnimation.menu_forward.value))
            }
            
            
            secondBlock.append(ContextMenuItem(strings().messageContextGoto, handler: {
                interface.focusMessageId(nil, .init(messageId: messageId, string: nil), .center(id: 0, innerId: nil, animated: false, focus: .init(focus: false), inset: 0))
            }, itemImage: MenuAnimation.menu_show_message.value))
            
            if canDeleteMessage(message, account: interface.interactionContext.account, chatLocation: interface.chatLocation, mode: .history) || mode == .recentDownloaded {
                thirdBlock.append(ContextMenuItem(strings().messageContextDelete, handler: {
                    interface.deleteMessages([messageId], nil)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
            
            let blocks:[[ContextMenuItem]] = [firstBlock,
                                              secondBlock,
                                              thirdBlock].filter { !$0.isEmpty }
            
            for (i, block) in blocks.enumerated() {
                if i != 0 {
                    items.append(ContextSeparatorItem())
                }
                items.append(contentsOf: block)
            }
            
            return items
            
        }
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return PeerMediaRowView.self
    }

    public override var accessibilityLabel: String? {
        return message.text.isEmpty ? strings().voiceOverChatMessage : message.text
    }
    
    public var separatorOffset: CGFloat {
        return 10 + 40 + viewType.innerInset.left
    }
}

public class PeerMediaRowView : GeneralContainableRowView, Notifable {
    public var contentView: View = View()
    private var selectingControl: SelectingControl?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView.addSubview(contentView)

        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? PeerMediaRowItem {
                if item.interface.presentation.state == .selecting {
                    item.interface.update({$0.withToggledSelectedMessage(item.message.id)})
                }
            }
        }, for: .Click)
    }

    public override var backdorColor: NSColor {
        guard let item = item as? GeneralRowItem else {
            return super.backdorColor
        }
        return item.customTheme?.backgroundColor ?? super.backdorColor
    }

    public override func updateColors() {
        super.updateColors()
        guard let item = item as? PeerMediaRowItem else {
            return
        }
        if backdorColor == .clear {
            self.backgroundColor = backdorColor
        } else {
            self.backgroundColor = item.viewType.rowBackground
        }
        self.containerView.backgroundColor = backdorColor
        self.borderView.backgroundColor = theme.colors.border.cgColor
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = item as? PeerMediaRowItem else {
            return
        }

        let selecting = item.interface.presentation.state == .selecting
        let contentX = selecting ? item.viewType.innerInset.left + 22 + item.viewType.innerInset.left : item.viewType.innerInset.left
        let contentSize = NSMakeSize(containerView.frame.width - item.viewType.innerInset.left - item.viewType.innerInset.right, containerView.frame.height - item.viewType.innerInset.bottom - item.viewType.innerInset.top)
        let contentY = floorToScreenPixels(backingScaleFactor, (containerView.frame.height - contentSize.height) / 2)
        transition.updateFrame(view: contentView, frame: CGRect(origin: NSMakePoint(contentX, contentY), size: contentSize))

        transition.updateFrame(layer: borderView, frame: NSMakeRect(item.separatorOffset + (selecting ? 22 + item.viewType.innerInset.left : 0), containerView.frame.height - .borderSize, containerView.frame.width - item.separatorOffset, .borderSize))

        if let selectingControl = selectingControl {
            let x = selecting ? item.viewType.innerInset.left : -22
            let y = floorToScreenPixels(backingScaleFactor, (containerView.frame.height - selectingControl.frame.height) / 2)
            transition.updateFrame(view: selectingControl, frame: CGRect(origin: NSMakePoint(x, y), size: selectingControl.frame.size))
        }
    }

    public func notify(with value: Any, oldValue:Any, animated:Bool) {
        if let item = item as? PeerMediaRowItem {
            if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
                if (value.state == .selecting) != (oldValue.state == .selecting) || value.isSelectedMessageId(item.message.id) != oldValue.isSelectedMessageId(item.message.id) {
                    updateSelectingMode(with: value.state == .selecting, animated: !NSIsEmptyRect(visibleRect))
                }
            }
        }
    }

    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? PeerMediaRowView {
            return other == self
        }
        return false
    }

    public override func set(item: TableRowItem, animated: Bool) {
        if let item = self.item as? PeerMediaRowItem {
            item.interface.remove(observer: self)
        }
        super.set(item: item, animated: animated)

        if let item = self.item as? PeerMediaRowItem {
            item.interface.add(observer: self)
            updateSelectingMode(with: item.interface.presentation.state == .selecting, animated: animated)

            borderView.isHidden = !item.viewType.hasBorder
        }
        if let nextItem = item.table?.nextItem(after: item.index) {
            borderView.isHidden = borderView.isHidden || !(nextItem is PeerMediaRowItem)
        }

        needsLayout = true
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let item = self.item as? PeerMediaRowItem {
            if superview == nil {
                item.interface.remove(observer: self)
            } else {
                item.interface.add(observer: self)
                updateSelectingMode(with: item.interface.presentation.state == .selecting, animated: !NSIsEmptyRect(visibleRect))
            }
        }
    }

    public func updateSelectingMode(with selectingMode:Bool, animated:Bool = false) {
        if let item = item as? PeerMediaRowItem {
            containerView.userInteractionEnabled = selectingMode

            let to:NSPoint
            if selectingMode {
                to = NSMakePoint(item.viewType.innerInset.left + 22 + item.viewType.innerInset.left, self.contentView.frame.minY)
            } else {
                to = NSMakePoint(item.viewType.innerInset.left, self.contentView.frame.minY)
            }

            let borderOrigin = NSMakePoint(item.separatorOffset + (selectingMode ? 22 + item.viewType.innerInset.left : 0), self.containerView.frame.height - .borderSize)
            if borderOrigin != self.borderView.frame.origin {
                if animated {
                    var present = self.borderView.frame.origin
                    if let presentation = self.borderView.presentation(), self.borderView.animation(forKey: "position") != nil {
                        present = presentation.frame.origin
                    }
                    self.borderView.animatePosition(from: present, to: borderOrigin)
                } else {
                    self.borderView.removeAnimation(forKey: "position")
                }
                self.borderView.frame.origin = borderOrigin
            }
            contentView.change(pos: to, animated: animated)

            if selectingMode {
                if selectingControl == nil {
                    selectingControl = SelectingControl(unselectedImage: theme.icons.chatToggleUnselected, selectedImage: theme.icons.chatToggleSelected)
                    containerView.addSubview(selectingControl!)
                    selectingControl!.centerY(x: -22)
                    selectingControl?.change(pos: NSMakePoint(item.viewType.innerInset.left, selectingControl!.frame.minY), animated: animated)
                }
            } else {
                if let selectingControl = selectingControl {
                    let point = NSMakePoint(-22, selectingControl.frame.minY)
                    self.selectingControl = nil
                    selectingControl.change(pos: point, animated: animated, completion: { [weak selectingControl] _ in
                        selectingControl?.removeFromSuperview()
                    })
                }
            }
            selectingControl?.set(selected: item.interface.presentation.isSelectedMessageId(item.message.id), animated: animated)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func addSubview(_ view: NSView) {
        contentView.addSubview(view)
    }

    deinit {
        contentView.removeAllSubviews()
    }
}
