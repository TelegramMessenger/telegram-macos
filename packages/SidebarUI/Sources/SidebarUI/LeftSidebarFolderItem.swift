import Cocoa
import LocalAnimations
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI

import TGUIKit
import TelegramCore
import SwiftSignalKit
import AppAnalytics

private func sidebarFolderIcon(_ icon: CGImage, badge: CGImage?) -> CGImage {
    guard let badge else { return icon }
    return generateImage(icon.systemSize, contextGenerator: { size, ctx in
        let rect = NSRect(origin: .zero, size: size)
        ctx.clear(rect)
        ctx.draw(icon, in: rect.focus(icon.systemSize))
        ctx.clip(to: NSMakeRect(rect.width - floorToScreenPixels(badge.systemSize.width / 2) - 6, rect.height - badge.systemSize.height + 3, badge.systemSize.width + 4, badge.systemSize.height + 4), mask: badge)
        ctx.clear(rect)
    })!
}

class LeftSidebarFolderItem: TableRowItem {

    fileprivate let folder: ChatListFilter
    let selected: Bool
    fileprivate let callback: (ChatListFilter)->Void
    fileprivate let menuItems: (ChatListFilter, Int?, Bool?)-> [ContextMenuItem]
    fileprivate let context: any AccountContextProtocol
    let icon: CGImage
    private let environment: SidebarUIEnvironment
    fileprivate lazy var dropIcons: (CGImage, CGImage, CGImage) = {
        let folderIcon = FolderIcon(self.folder)
        let hovered = self.environment.folderImage(folderIcon.emoticon.iconName).precomposed(theme.colors.text.withAlphaComponent(0.95))
        return (sidebarFolderIcon(folderIcon.icon(for: .sidebar, image: self.environment.folderImage), badge: self.badge), sidebarFolderIcon(folderIcon.icon(for: .sidebarActive, image: self.environment.folderImage), badge: self.badge), sidebarFolderIcon(hovered, badge: self.badge))
    }()
    let badge: CGImage?
    let nameLayout: TextViewLayout
    let unreadCount: Int


    init(_ initialSize: NSSize, context: any AccountContextProtocol, environment: SidebarUIEnvironment, folder: ChatListFilter, selected: Bool, unreadCount: Int, hasUnmutedUnread: Bool, callback: @escaping(ChatListFilter)->Void, menuItems: @escaping(ChatListFilter, Int?, Bool?) -> [ContextMenuItem]) {
        self.folder = folder
        self.environment = environment
        self.context = context
        self.selected = selected
        self.callback = callback
        self.unreadCount = unreadCount
        self.menuItems = menuItems
        var folderIcon = FolderIcon(folder).icon(for: selected ? .sidebarActive : .sidebar, image: environment.folderImage)

        let attr = NSMutableAttributedString()
        attr.append(string: folder.title, color: selected ? theme.colors.accent : theme.colors.text, font: .medium(10))
        environment.applyInlineStickers(to: attr, entities: folder.entities, isPremium: context.isPremium, animated: folder.enableAnimations)

        nameLayout = TextViewLayout(attr, alignment: .center)


        nameLayout.measure(width: initialSize.width - 10)



        let generateIcon:()->CGImage? = {
            let icon: CGImage?
            if unreadCount > 0 {

                let textColor: NSColor = theme.colors.underSelectedColor

                let attributedString = NSAttributedString.initialize(string: "\(unreadCount.prettyNumber)", color: textColor, font: .medium(.short))
                let textLayout = TextNode.layoutText(maybeNode: nil,  attributedString, nil, 1, .start, NSMakeSize(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude), nil, false, .center)
                var size = NSMakeSize(textLayout.0.size.width + 8, textLayout.0.size.height + 5)
                size = NSMakeSize(max(size.height,size.width), size.height)

                let badge = generateImage(size, rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    if selected || hasUnmutedUnread {
                        ctx.setFillColor(theme.colors.accent.cgColor)
                    } else {
                        ctx.setFillColor(theme.colors.grayIcon.cgColor)
                    }
                    ctx.round(size, floorToScreenPixels(size.height/2.0))
                    ctx.fill(rect)

//                    ctx.setBlendMode(.clear)

                    let focus = rect.focus(textLayout.0.size)
                    textLayout.1.draw(focus.offsetBy(dx: 0, dy: -1), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .white)

                })!

                folderIcon = sidebarFolderIcon(folderIcon, badge: badge)

                icon = badge

            } else {
                icon = nil
            }
            return icon
        }
        self.badge = generateIcon()
        self.icon = folderIcon
        super.init(initialSize)
    }

    var folderDropId: Int32 {
        return folder.sidebarId
    }

    override var stableId: AnyHashable {
        return folder.sidebarId
    }

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {

        let id = self.folder.sidebarId
        let folder = self.folder
        let unreadCount = self.unreadCount
        let context = self.context

        let filterPeersAreMuted: Signal<Bool, NoError> = context.engine.peers.currentChatListFilters()
        |> take(1)
        |> mapToSignal { filters -> Signal<Bool, NoError> in
            guard let filter = filters.first(where: { $0.sidebarId == id }) else {
                return .single(false)
            }
            guard case let .filter(_, _, _, data) = filter else {
                return .single(false)
            }
            return context.engine.data.get(
                EngineDataList(data.includePeers.peers.map(TelegramEngine.EngineData.Item.Peer.NotificationSettings.init(id:)))
            )
            |> map { list -> Bool in
                for item in list {
                    switch item.muteState {
                    case .default, .unmuted:
                        return false
                    default:
                        break
                    }
                }
                return true
            }
        } |> deliverOnMainQueue

        return filterPeersAreMuted |> map { [weak self] allMuted in
            return self?.menuItems(folder, unreadCount, allMuted) ?? []
        }
    }

    override var height: CGFloat {
        return 32 + 8 + 8 + nameLayout.layoutSize.height + 4
    }

    override func viewClass() -> AnyClass {
        return LeftSidebarFolderView.self
    }

    override var accessibilityLabel: String? {
        if unreadCount > 0 {
            return folder.title + "\n" + strings().voiceOverChatUnreadMessagesOther(unreadCount)
        }
        return folder.title
    }

    override var accessibilityValue: String? {
        return selected ? strings().voiceOverCommonSelected : nil
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    fileprivate func trackSelect(via: AnalyticsValues.Via) {
        if !selected {
            Analytics.shared.send(AnalyticsEvents.chatListFolderSelect(folderKind: folder == .allChats ? .allChats : .custom, via: via))
        }
    }

    override func accessibilityPerformPress() -> Bool {
        trackSelect(via: .other)
        callback(folder)
        return true
    }

}


final class LeftSidebarFolderView : TableRowView {
    var folderDropTarget: (ChatListFilter, NSView)? {
        guard let item = item as? LeftSidebarFolderItem, !isResorting else { return nil }
        return (item.folder, self)
    }

    var folderDropContentViews: [NSView] {
        return [imageView, badgeView, textView]
    }

    private var dropImages: [(CGImage?, CGImage?, CGImage?)]?
    private var dropAppearanceSize = NSSize.zero

    var folderDropAppearance: SidebarFolderDropAppearance? {
        guard let item = item as? LeftSidebarFolderItem else { return nil }
        return (item, item.selected, { [weak self] in self?.folderDropImages ?? [] })
    }

    private var folderDropImages: [(CGImage?, CGImage?, CGImage?)] {
        guard let item = item as? LeftSidebarFolderItem else { return [] }
        if let dropImages, dropAppearanceSize == textView.bounds.size {
            return dropImages
        }
        let image = textView.snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let attributedString = NSMutableAttributedString(attributedString: item.nameLayout.attributedString)
        let color = item.selected ? theme.colors.text : theme.colors.accent
        attributedString.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributedString.length)) { value, range, _ in
            if let value = value as? NSColor, value.alphaComponent > 0 {
                attributedString.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
        let layout = TextViewLayout(attributedString, alignment: .center)
        layout.measure(width: item.nameLayout.constrainedWidth)
        let textLayer = TextViewLayer()
        textLayer.contentsScale = window?.backingScaleFactor ?? System.backingScale
        textLayer.frame = textView.bounds
        textLayer.update(layout, size: textView.bounds.size)
        let alternate = generateImage(textView.bounds.size, scale: textLayer.contentsScale, rotatedContext: { size, ctx in
            let rect = NSRect(origin: .zero, size: size)
            ctx.clear(rect)
            textLayer.draw(in: ctx)
            if let image {
                for embedded in item.nameLayout.embeddedItems {
                    ctx.saveGState()
                    ctx.clip(to: embedded.rect.offsetBy(dx: self.textView.textView.frame.minX, dy: self.textView.textView.frame.minY))
                    ctx.translateBy(x: 0, y: size.height)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.draw(image, in: rect)
                    ctx.restoreGState()
                }
            }
        })
        let icons = item.dropIcons
        let images: [(CGImage?, CGImage?, CGImage?)] = [(icons.0, icons.1, icons.2), (item.badge, item.badge, item.badge), item.selected ? (alternate, image, alternate) : (image, alternate, image)]
        dropImages = images
        dropAppearanceSize = textView.bounds.size
        return images
    }

    private let imageView = ImageView(frame: NSMakeRect(0, 0, 32, 32))
    private let badgeView = ImageView()
    private let textView = InteractiveTextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        addSubview(badgeView)
        textView.userInteractionEnabled = false
        textView.textView.isSelectable = false
        textView.isEventLess = true
        badgeView.isEventLess = true
        imageView.isEventLess = true
        imageView.isAccessibilityDecorative = true
        badgeView.isAccessibilityDecorative = true
    }

    override func updateIsResorting() {
        updateHighlight(animated: true)
    }

    func updateHighlight(animated: Bool = true) {
        guard item is LeftSidebarFolderItem else {
            return
        }
        self.imageView.change(opacity: 1.0, animated: animated)
        self.textView.change(opacity: 1.0, animated: animated)
    }


    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHighlight()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHighlight()
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateHighlight()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        updateHighlight()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        updateHighlight()

        if mouseInside() {
            guard let item = item as? LeftSidebarFolderItem else {
                return
            }
            item.trackSelect(via: .click)
            item.callback(item.folder)
        }
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        dropImages = nil

        guard let item = item as? LeftSidebarFolderItem else {
            return
        }
     //   imageView.animates = animated
        imageView.image = item.icon
        imageView.sizeToFit()
        textView.set(text: item.nameLayout, context: item.context)


      //  badgeView.animates = animated
        badgeView.image = item.badge
        badgeView.sizeToFit()

        updateHighlight(animated: animated)

        needsLayout = true
    }

    override func layout() {
        super.layout()

        imageView.centerX(y: 8)
        textView.centerX(y: imageView.frame.maxY + 4)
        badgeView.setFrameOrigin(NSMakePoint(imageView.frame.maxX - floorToScreenPixels(badgeView.frame.width / 2) - 4, imageView.frame.minY - 4))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
