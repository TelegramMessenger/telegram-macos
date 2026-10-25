import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
#if SHARE
import TelegramThemeShare
import TelegramContextShare
import TelegramUtilsShare
import GeneralRowsShare
import AvatarUIShare
#else
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import AvatarUI
import PremiumStatusUI
#endif

public final class SelectPeerPresentation : Equatable {
    
    public struct Comment : Equatable {
        public let string: String
        public let range: NSRange
        public init(string: String, range: NSRange) {
            self.string = string
            self.range = range
        }
    }
    public let premiumRequired:Set<PeerId>
    public let selected:Set<PeerId>
    public let peers:[PeerId: Peer]
    public let limit:Int32
    public let inputQueryResult: ChatPresentationInputQueryResult?
    public let comment: Comment
    public let multipleSelection: Bool
    private let someFlagsAsNotice: Bool
    public static func ==(lhs:SelectPeerPresentation, rhs:SelectPeerPresentation) -> Bool {
        return lhs.selected == rhs.selected && lhs.limit == rhs.limit && lhs.someFlagsAsNotice == rhs.someFlagsAsNotice && lhs.inputQueryResult == rhs.inputQueryResult && lhs.comment == rhs.comment && lhs.multipleSelection == rhs.multipleSelection && lhs.premiumRequired == rhs.premiumRequired
    }
    
    public init(_ selected:Set<PeerId> = Set(), peers:[PeerId: Peer] = [:], limit: Int32 = 0, someFlagsAsNotice:Bool = false, inputQueryResult: ChatPresentationInputQueryResult? = nil, comment: Comment = Comment(string: "", range: NSMakeRange(0, 0)), multipleSelection: Bool = true, premiumRequired: Set<PeerId> = Set()) {
        self.selected = selected
        self.peers = peers
        self.limit = limit
        self.someFlagsAsNotice = someFlagsAsNotice
        self.inputQueryResult = inputQueryResult
        self.comment = comment
        self.multipleSelection = multipleSelection
        self.premiumRequired = premiumRequired
    }
    
    public func deselect(peerId:PeerId) -> SelectPeerPresentation {
        var selectedIds:Set<PeerId> = Set<PeerId>()
        var peers:[PeerId: Peer] = self.peers
        selectedIds.formUnion(selected)
        let _ = selectedIds.remove(peerId)
        peers.removeValue(forKey: peerId)
        return SelectPeerPresentation(selectedIds, peers: peers, limit: limit, someFlagsAsNotice: someFlagsAsNotice, inputQueryResult: inputQueryResult, comment: comment, multipleSelection: self.multipleSelection, premiumRequired: premiumRequired)
    }
    
    public var isLimitReached: Bool {
        return limit > 0 && limit == selected.count
    }
    
    public func withUpdateLimit(_ limit: Int32) -> SelectPeerPresentation {
        return SelectPeerPresentation(selected, peers: peers, limit: limit, someFlagsAsNotice: someFlagsAsNotice, inputQueryResult: inputQueryResult, comment: comment, multipleSelection: multipleSelection, premiumRequired: premiumRequired)
    }
    public func withUpdatedMultipleSelection(_ multipleSelection: Bool) -> SelectPeerPresentation {
        return SelectPeerPresentation(selected, peers: peers, limit: limit, someFlagsAsNotice: someFlagsAsNotice, inputQueryResult: inputQueryResult, comment: comment, multipleSelection: multipleSelection, premiumRequired: premiumRequired)
    }
    
    public func updatedInputQueryResult(_ f: (ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?) -> SelectPeerPresentation {
        return SelectPeerPresentation(selected, peers: peers, limit: limit, someFlagsAsNotice: someFlagsAsNotice, inputQueryResult: f(inputQueryResult), comment: comment, multipleSelection: multipleSelection, premiumRequired: premiumRequired)
    }
    
    public func withUpdatedComment(_ comment: Comment) -> SelectPeerPresentation {
        return SelectPeerPresentation(selected, peers: peers, limit: limit, someFlagsAsNotice: someFlagsAsNotice, inputQueryResult: inputQueryResult, comment: comment, multipleSelection: multipleSelection, premiumRequired: premiumRequired)
    }
    
    public func withUpdatedPremiumRequired(_ premiumRequired: Set<PeerId>) -> SelectPeerPresentation {
        return SelectPeerPresentation(selected, peers: peers, limit: limit, someFlagsAsNotice: someFlagsAsNotice, inputQueryResult: inputQueryResult, comment: comment, multipleSelection: multipleSelection, premiumRequired: premiumRequired)
    }
    
    public func withToggledSelected(_ peerId: PeerId, peer:Peer, toggle: Bool? = nil) -> SelectPeerPresentation {
        var someFlagsAsNotice: Bool = self.someFlagsAsNotice
        var selectedIds:Set<PeerId> = Set<PeerId>()
        var peers:[PeerId: Peer] = self.peers
        selectedIds.formUnion(selected)
        if selectedIds.contains(peerId), toggle == nil || toggle == false {
            let _ = selectedIds.remove(peerId)
            peers.removeValue(forKey: peerId)
        } else if !selectedIds.contains(peerId), toggle == nil || toggle == true {
            if limit == 0 || selected.count < limit {
                selectedIds.insert(peerId)
                peers[peerId] = peer
            } else {
                someFlagsAsNotice = !someFlagsAsNotice
            }
        }
        return SelectPeerPresentation(selectedIds, peers: peers, limit: limit, someFlagsAsNotice: someFlagsAsNotice, inputQueryResult: inputQueryResult, comment: comment, multipleSelection: multipleSelection, premiumRequired: premiumRequired)
    }
    
}

public final class SelectPeerInteraction : InterfaceObserver {
    public private(set) var presentation:SelectPeerPresentation = SelectPeerPresentation()
    public var close: ()->Void = {}
    public var action:(PeerId, Int64?)->Void = { _, _ in }
    public var openForum:(PeerId, Bool)->Bool = { _, _ in return false }
    public var openCommunity:(PeerId)->Bool = { _ in return false }
    public var isPeerSelected:(PeerId, Peer, SelectPeerPresentation)->Bool = { peerId, _, presentation in
        return presentation.selected.contains(peerId)
    }
    public var singleUpdater:((SelectPeerPresentation)->Void)? = nil
    
    public var updateFolder:((ChatListFilter)->Void)? = nil
    public var premiumRequiredAction:((PeerId)->Void)? = nil
    
    public func update(animated:Bool = true, _ f:(SelectPeerPresentation)->SelectPeerPresentation)->Void {
        let oldValue = self.presentation
        presentation = f(presentation)
        
        if oldValue != presentation {
            notifyObservers(value: presentation, oldValue:oldValue, animated:animated)
        }
        self.singleUpdater?(presentation)
    }

    public func refreshSelection(animated: Bool) {
        notifyObservers(value: presentation, oldValue: presentation, animated: animated)
    }
    
    public func toggleSelection( _ peer: Peer) {
        if peer.isCommunity, self.openCommunity(peer.id) {
            return
        }
        if presentation.premiumRequired.contains(peer.id) {
            self.premiumRequiredAction?(peer.id)
            return
        }
        self.update(animated: true, {
            $0.withToggledSelected(peer.id, peer: peer)
                .withUpdatedMultipleSelection(true)
        })
    }
    public func activateSelection(_ peer: Peer) {
        let isForum = TelegramUtilsHooks.shared.peerIsForum(peer) || (peer.groupAccess.canManageDirect && peer.isMonoForum)
        if isForum, !presentation.selected.contains(peer.id), self.openForum(peer.id, peer.isMonoForum) {
            return
        }
        self.toggleSelection(peer)
    }
    public func toggleSelection( _ peerId: PeerId) {
        if let peer = self.presentation.peers[peerId] {
            self.toggleSelection(peer)
        }
    }
}

public struct ShortPeerDeleting  : Equatable {
    public let editable:Bool
    public static func ==(lhs:ShortPeerDeleting, rhs:ShortPeerDeleting) -> Bool {
        return lhs.editable == rhs.editable
    }
    public init(editable: Bool) {
        self.editable = editable
    }
}

public enum ShortPeerItemInteractionType {
    public enum Side {
        case left
        case right
    }
    case plain
    case deletable(onRemove:(PeerId)->Void, deletable:Bool)
    case selectable(SelectPeerInteraction, side: Side)
    case interactable(SelectPeerInteraction)
}





open class ShortPeerRowItem: GeneralRowItem {
    public let peer:Peer
    public let context: (any AccountContextProtocol)?
    public let account: Account
    public let interactionType:ShortPeerItemInteractionType
    public let drawSeparatorIgnoringInset:Bool
    
    public struct RightActions : Equatable {
        public static func == (lhs: ShortPeerRowItem.RightActions, rhs: ShortPeerRowItem.RightActions) -> Bool {
            return lhs.actions == rhs.actions
        }
        
        public struct RightAction : Equatable {
            public var icon: CGImage
            public var index: Int
            public var accessibilityLabel: String?
            public init(icon: CGImage, index: Int, accessibilityLabel: String? = nil) {
                self.icon = icon
                self.index = index
                self.accessibilityLabel = accessibilityLabel
            }
        }
        public var actions: [RightAction] = []
        public var callback:(PeerId, Int)->Void = { _, _ in }
        public init(actions: [RightAction] = [], callback: @escaping (PeerId, Int)->Void = { _, _ in }) {
            self.actions = actions
            self.callback = callback
        }
    }
    
    open func textInset(_ status: Bool) -> CGFloat {
        switch viewType {
        case .legacy:
            var width = inset.left + photoSize.width + 10.0 + (leftImage != nil ? leftImage!.backingSize.width + 5 : 0)
            
            #if !SHARE
            if self.highlightVerified, (!self.isLookSavedMessage || self.peerId != self.account.peerId) {
                if let size = PremiumStatusControl.controlSize(self.monoforumPeer ?? self.peer, false, left: true), !status {
                    width += size.width + 2
                }
            }
            if status, let statusImage {
                width += statusImage.backingSize.width + 4
            }

            #endif
            return width
        case let .modern(_, insets):
            var width = photoSize.width + min(10, insets.left) + (leftImage != nil ? leftImage!.backingSize.width + 5 : 0)
            
            #if !SHARE
            if self.highlightVerified, (!self.isLookSavedMessage || self.peerId != self.account.peerId) {
                if let size = PremiumStatusControl.controlSize(self.monoforumPeer ?? self.peer, false, left: true), !status {
                    width += size.width + 2
                }
            }
            if status, let statusImage {
                width += statusImage.backingSize.width + 4
            }
            #endif
            return width
        }
    }
    public let badgeNode: ShortPeerBadgeNode?
    public let deleteInset:CGFloat
    
    public let photoSize:NSSize
    
    public let monoforumPeer: Peer?
    
    
    public private(set) var title:(TextNodeLayout, TextNode)?
    public private(set) var status:(TextNodeLayout, TextNode)?
    
    private var selectedTitleLayout: (TextNodeLayout, TextNode)?
    private var selectedStatusLayout: (TextNodeLayout, TextNode)?

    public var titleSelected: (TextNodeLayout, TextNode)? {
        if selectedTitleLayout == nil, let titleAttr, let textLayoutWidths {
            selectedTitleLayout = TextNode.layoutText(maybeNode: nil, titleAttr, nil, 1, .end, NSMakeSize(textLayoutWidths.title, 20), nil, true, .left)
        }
        return selectedTitleLayout
    }

    public var statusSelected: (TextNodeLayout, TextNode)? {
        if selectedStatusLayout == nil, let statusAttr, let textLayoutWidths {
            selectedStatusLayout = TextNode.layoutText(maybeNode: nil, statusAttr, nil, 1, .end, NSMakeSize(textLayoutWidths.selectedStatus, 20), nil, true, .left)
        }
        return selectedStatusLayout
    }
    
    public let leftImage:CGImage?
    
    public private(set) var photo:Signal<(CGImage?, Bool), NoError>?

    public let isLookSavedMessage: Bool
    public let titleStyle:ControlStyle
    public let statusStyle:ControlStyle
    
    private var textLayoutWidths: (title: CGFloat, status: CGFloat, selectedStatus: CGFloat)?
    private var contextTextWidth: (text: String, width: CGFloat)?

    private var titleAttr:NSAttributedString?
    private var statusAttr:NSAttributedString?
    public let inputActivity: PeerInputActivity?
    public let drawLastSeparator:Bool
    public let highlightVerified: Bool
    public let highlightOnHover: Bool
    public let alwaysHighlight: Bool
    public let drawPhotoOuter: Bool
    public let photoBadge: CGImage?
    private let contextMenuItems:()->Signal<[ContextMenuItem], NoError>
    fileprivate let _peerId: PeerId?
    public let disabledAction: (()->Void)?
    
    
    public let story: EngineStorySubscriptions.Item?
    
    public let avatarStoryIndicator: AvatarStoryIndicatorComponent?

    public let openStory:(StoryInitialIndex?)->Void
    public let menuOnAction: Bool
    
    public let customActionText: TextViewLayout?
    public let customActionTextSelected: TextViewLayout?
    
    public let customAction: CustomAction?
    
    public struct CustomAction {
        public var title: String
        public var callback:()->Void
        public init(title: String, callback: @escaping ()->Void) {
            self.title = title
            self.callback = callback
        }
    }
    
    public let makeAvatarRound: Bool
    public let drawStarsPaid: StarsAmount?
    public let statusImage: CGImage?
    
    public let passLeftAction: Bool
    
    public let rightActions: RightActions
    
    public let monoforumMessages: TextViewLayout?
    public let monoforumMessagesSelected: TextViewLayout?

    private let _menuPresentation: AppMenu.Presentation?
    public let badgeAction: ((NSView)->Void)?
    public var avatarRemoveAction: (() -> Void)?

    public init(_ initialSize:NSSize, peer: Peer, account: Account, context: (any AccountContextProtocol)?, peerId: PeerId? = nil, stableId:AnyHashable? = nil, enabled: Bool = true, height:CGFloat = 50, photoSize:NSSize = NSMakeSize(36, 36), titleStyle:ControlStyle = ControlStyle(font: .medium(.title), foregroundColor: theme.colors.text, highlightColor: .white), titleAddition:String? = nil, leftImage:CGImage? = nil, statusStyle:ControlStyle = ControlStyle(font:.normal(.text), foregroundColor: theme.colors.grayText, highlightColor:.white), status:String? = nil, borderType:BorderType = [], drawCustomSeparator:Bool = true, isLookSavedMessage: Bool = false, deleteInset:CGFloat? = nil, drawLastSeparator:Bool = false, inset:NSEdgeInsets = NSEdgeInsets(left:10.0), drawSeparatorIgnoringInset: Bool = false, interactionType:ShortPeerItemInteractionType = .plain, generalType:GeneralInteractedType = .none, viewType: GeneralViewType = .legacy, action:@escaping ()->Void = {}, contextMenuItems:@escaping()->Signal<[ContextMenuItem], NoError> = { .single([]) }, inputActivity: PeerInputActivity? = nil, highlightOnHover: Bool = false, alwaysHighlight: Bool = false, badgeNode: ShortPeerBadgeNode? = nil, compactText: Bool = false, highlightVerified: Bool = false, customTheme: GeneralRowItem.Theme? = nil, drawPhotoOuter: Bool = false, disabledAction:(()->Void)? = nil, story: EngineStorySubscriptions.Item? = nil, openStory: @escaping(StoryInitialIndex?)->Void = { _ in }, menuOnAction: Bool = false, photoBadge: CGImage? = nil, customAction: CustomAction? = nil, makeAvatarRound: Bool = false, drawStarsPaid: StarsAmount? = nil, statusImage: CGImage? = nil, passLeftAction: Bool = false, rightActions: RightActions = .init(), monoforumPeer: Peer? = nil, fullSize: Bool = false, _menuPresentation: AppMenu.Presentation? = nil, badgeAction: ((NSView)->Void)? = nil) {
        self.peer = peer
        self.badgeAction = badgeAction
        self.drawPhotoOuter = drawPhotoOuter
        self.contextMenuItems = contextMenuItems
        self.context = context
        self.account = account
        self._peerId = peerId
        self._menuPresentation = _menuPresentation
        self.passLeftAction = passLeftAction
        self.story = story
        self.drawStarsPaid = drawStarsPaid
        self.openStory = openStory
        self.photoSize = photoSize
        self.leftImage = leftImage
        self.photoBadge = photoBadge
        self.disabledAction = disabledAction
        self.inputActivity = inputActivity
        self.menuOnAction = menuOnAction
        self.customAction = customAction
        
        self.statusImage = statusImage

        
        self.makeAvatarRound = makeAvatarRound
        self.rightActions = rightActions
        if let deleteInset = deleteInset {
            self.deleteInset = deleteInset
        } else {
            switch viewType {
            case .legacy:
                self.deleteInset = inset.left
            case let .modern(_, insets):
                self.deleteInset = insets.left
            }
        }
        
        if let customAction {
            self.customActionText = .init(.initialize(string: customAction.title, color: theme.colors.underSelectedColor, font: .medium(.text)), alignment: .center)
            self.customActionText?.measure(width: .greatestFiniteMagnitude)
            
            self.customActionTextSelected = .init(.initialize(string: customAction.title, color: theme.colors.accent, font: .medium(.text)), alignment: .center)
            self.customActionTextSelected?.measure(width: .greatestFiniteMagnitude)
        } else {
            self.customActionText = nil
            self.customActionTextSelected = nil
        }
        
        self.badgeNode = badgeNode
        self.badgeNode?.customLayout = true
        self.alwaysHighlight = alwaysHighlight
        self.highlightOnHover = highlightOnHover
        self.interactionType = interactionType
        self.drawLastSeparator = drawLastSeparator
        self.drawSeparatorIgnoringInset = drawSeparatorIgnoringInset
        self.titleStyle = titleStyle
        self.statusStyle = statusStyle
        self.isLookSavedMessage = isLookSavedMessage
        self.highlightVerified = highlightVerified
        self.monoforumPeer = monoforumPeer
        
        if let _ = monoforumPeer, peer.isMonoForum {
            self.monoforumMessages = .init(.initialize(string: strings().chatListMonoforumHolder, color: theme.colors.grayText, font: .normal(.small)), alignment: .center)
            self.monoforumMessagesSelected = .init(.initialize(string: strings().chatListMonoforumHolder, color: theme.colors.accentSelect, font: .normal(.small)), alignment: .center)
            
            self.monoforumMessages?.measure(width: .greatestFiniteMagnitude)
            self.monoforumMessagesSelected?.measure(width: .greatestFiniteMagnitude)

        } else {
            self.monoforumMessages = nil
            self.monoforumMessagesSelected = nil
        }

        if let story = story {
            self.avatarStoryIndicator = .init(story: story, presentation: theme)
        } else {
            self.avatarStoryIndicator = nil
        }
        
        
        let tAttr:NSMutableAttributedString = NSMutableAttributedString()
        if isLookSavedMessage && peer.id.isAnonymousSavedMessages {
            let icon = theme.icons.chat_hidden_author
            photo = generateEmptyPhoto(photoSize, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photoSize.width - 5, photoSize.height - 5)), cornerRadius: nil), bubble: false) |> map {($0, false)}
        } else if isLookSavedMessage && account.peerId == peer.id {
            let icon = theme.icons.searchSaved
            photo = generateEmptyPhoto(photoSize, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photoSize.width - 15, photoSize.height - 15)), cornerRadius: nil), bubble: false) |> map {($0, false)}
        } else if isLookSavedMessage && peer.id == repliesPeerId {
            let icon = theme.icons.chat_replies_avatar
            photo = generateEmptyPhoto(photoSize, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photoSize.width - 17, photoSize.height - 17)), cornerRadius: nil), bubble: false) |> map {($0, false)}

        }
        
        if let emptyAvatar = peer.emptyAvatar {
            self.photo = generateEmptyPhoto(photoSize, type: emptyAvatar, bubble: false) |> map {($0, false)}
        }
        
        if let monoforumPeer, peer.isMonoForum {
            let _ = tAttr.append(string: monoforumPeer.displayTitle, color: enabled ? titleStyle.foregroundColor : customTheme?.grayTextColor ?? theme.colors.grayText, font: self.titleStyle.font)
        } else {
            let _ = tAttr.append(string: isLookSavedMessage && account.peerId == peer.id ? strings().peerSavedMessages : (compactText ? peer.compactDisplayTitle + (account.testingEnvironment ? " [🤖]" : "") : peer.displayTitle), color: enabled ? titleStyle.foregroundColor : customTheme?.grayTextColor ?? theme.colors.grayText, font: self.titleStyle.font)
        }
        
        
        if let titleAddition = titleAddition {
            _ = tAttr.append(string: titleAddition, color: enabled ? titleStyle.foregroundColor : customTheme?.grayTextColor ?? theme.colors.grayText, font: self.titleStyle.font)
        }
        
        tAttr.addAttribute(.selectedColor, value: customTheme?.underSelectedColor ?? theme.colors.underSelectedColor, range: tAttr.range)

        
        titleAttr = tAttr.copy() as? NSAttributedString
        
        
        if let status = status {
            let sAttr:NSMutableAttributedString = NSMutableAttributedString()
            let _ = sAttr.append(string: status, color: enabled ? self.statusStyle.foregroundColor : customTheme?.grayTextColor ?? theme.colors.grayText, font: self.statusStyle.font)
            sAttr.addAttribute(.selectedColor, value: customTheme?.underSelectedColor ?? theme.colors.underSelectedColor, range: sAttr.range)
            statusAttr = sAttr.copy() as? NSAttributedString
        }
        
        super.init(initialSize, height: height, stableId: stableId ?? AnyHashable(peerId ?? peer.id), type:generalType, viewType: viewType, action:action, drawCustomSeparator:drawCustomSeparator, border:borderType,inset:inset, enabled: enabled, customTheme: customTheme, fullSize: fullSize)
        
    }
    
    open func openPeerStory() {
        let table = self.table
        self.openStory(.init(peerId: peerId, id: nil, messageId: nil, takeControl: { [weak table] peerId, _, storyId in
            var view: NSView?
            table?.enumerateItems(with: { item in
                if let item = item as? ShortPeerRowItem, item.peerId == peerId {
                    view = item.takeStoryControl()
                }
                return view == nil
            })
            return view
        }, setProgress: { [weak self] value in
            self?.setOpenProgress(value)
        }))
    }
    
    private func takeStoryControl() -> NSView? {
        (self.view as? ShortPeerRowView)?.takeStoryControl()
    }
    
    open func setOpenProgress(_ signal:Signal<Never, NoError>) {
        (self.view as? ShortPeerRowView)?.setOpenProgress(signal)
    }
    
    
    open var peerId: PeerId {
        return _peerId ?? peer.id
    }
    
    open override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return contextMenuItems()
    }
    
    open override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        prepare(self.isSelected)
        return result
    }
    
    open var textAdditionInset:CGFloat {
        return 0
    }
    
    open override var menuPresentation: AppMenu.Presentation {
        return self._menuPresentation ?? super.menuPresentation
    }

    
    open override func prepare(_ selected:Bool) {
        defer {
            if selected {
                _ = titleSelected
                _ = statusSelected
            }
        }
        
        var addition:CGFloat = 0
        var additionStatus: CGFloat = 0
        switch interactionType {
        case .selectable:
            addition += 30
        case .deletable:
            addition += 24 + 12
        default:
            break
        }
        
        switch type {
        case .switchable:
            addition += 48
        case .selectable:
            addition += 20
        case let .context(text), let .contextColored(text, _), let .nextContext(text):
            if contextTextWidth?.text != text {
                let attr = NSAttributedString.initialize(string: text, color: .text, font: statusStyle.font)
                contextTextWidth = (text, attr.size().width)
            }
            addition += (contextTextWidth?.width ?? 0) + 10
        default:
            break
        }
        
        if let _ = badgeNode {
            addition += 40
        }
        
        if let monoforumMessagesSelected {
            addition += monoforumMessagesSelected.layoutSize.width + 4
        }
        
        if self.peer.isScam {
            addition += 20
        }
        if self.peer.isFake {
            addition += 20
        }
        
        if let statusImage {
            additionStatus += statusImage.backingSize.width + 4
        }
        
        if !rightActions.actions.isEmpty {
            addition += rightActions.actions.reduce(0) { width, action in
                width + action.icon.backingSize.width
            }
            addition += CGFloat(rightActions.actions.count - 1) * 10
        }
        
        
        if let customActionText {
            addition += customActionText.layoutSize.width + 10
        }
        
        if self.highlightVerified  {
            if peer.isPremium || peer.isVerified || peer.isScam || peer.isFake {
                addition += 25
            }
        }
        let titleWidth: CGFloat
        let statusWidth: CGFloat
        let selectedStatusWidth: CGFloat
        switch viewType {
        case .legacy:
            titleWidth = self.size.width - textInset(false) - inset.right - addition - textAdditionInset - 10
            statusWidth = self.size.width - textInset(true) - inset.right - addition - textAdditionInset - 10
            selectedStatusWidth = self.size.width - textInset(true) - inset.right - addition - additionStatus - textAdditionInset - 10
        case let .modern(_, insets):
            titleWidth = self.width - textInset(false) - insets.left - insets.right - inset.left - inset.right - addition - additionStatus - textAdditionInset
            statusWidth = titleWidth
            selectedStatusWidth = titleWidth
        }
        if let textLayoutWidths, textLayoutWidths.title == titleWidth, textLayoutWidths.status == statusWidth, textLayoutWidths.selectedStatus == selectedStatusWidth {
            return
        }
        if let titleAttr {
            title = TextNode.layoutText(maybeNode: nil, titleAttr, nil, 1, .end, NSMakeSize(titleWidth, 20), nil, false, .left)
        }
        if let statusAttr {
            status = TextNode.layoutText(maybeNode: nil, statusAttr, nil, 1, .end, NSMakeSize(statusWidth, 20), nil, false, .left)
        }
        selectedTitleLayout = nil
        selectedStatusLayout = nil
        textLayoutWidths = (titleWidth, statusWidth, selectedStatusWidth)
    }

    open var ctxMonoforumMessages: TextViewLayout? {
        if isSelected {
            return monoforumMessagesSelected
        }
        return monoforumMessages
    }
   
    open var ctxTitle:(TextNodeLayout, TextNode)? {
        return isSelected ? titleSelected : title
    }
    open var ctxStatus:(TextNodeLayout, TextNode)? {
        return isSelected ? statusSelected : status
    }
    open override func viewClass() -> AnyClass {
        return ShortPeerRowView.self
    }
    
    open override var instantlyResize: Bool {
        return true
    }

    open override var accessibilityLabel: String? {
        guard let title = titleAttr?.string, !title.isEmpty else {
            return peer.displayTitle
        }
        return title
    }

    open override var accessibilityValue: String? {
        var values: [String] = []
        if let status = statusAttr?.string, !status.isEmpty {
            values.append(status)
        }
        switch type {
        case let .context(value), let .contextColored(value, _), let .nextContext(value):
            if !value.isEmpty {
                values.append(value)
            }
        default:
            break
        }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    open override var accessibilityRole: NSAccessibility.Role? {
        if case .selectable = interactionType {
            return .checkBox
        }
        switch type {
        case .switchable:
            return .checkBox
        case .selectable:
            return .radioButton
        default:
            return .button
        }
    }

    open override var accessibilityToggleState: Bool? {
        if case let .selectable(interaction, _) = interactionType {
            return interaction.isPeerSelected(peerId, peer, interaction.presentation)
        }
        switch type {
        case let .switchable(value), let .selectable(value):
            return value
        default:
            return nil
        }
    }

    open override var accessibilityIsEnabled: Bool {
        return enabled
    }

    open override var accessibilityIncludesChildren: Bool {
        return !rightActions.actions.isEmpty
    }

    open override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if case let .deletable(onRemove, deletable) = interactionType, deletable, enabled {
            let peerId = self.peerId
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonRemove, handler: {
                onRemove(peerId)
                return true
            }))
        }
        if let customAction = customAction {
            actions.append(NSAccessibilityCustomAction(name: customAction.title, handler: {
                customAction.callback()
                return true
            }))
        }
        if story != nil {
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonStory, handler: { [weak self] in
                self?.openPeerStory()
                return true
            }))
        }
        if enabled, case let .selectable(interaction, .left) = interactionType, !passLeftAction {
            let peerId = self.peerId
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonOpen, handler: {
                interaction.action(peerId, nil)
                return true
            }))
        }
        if badgeAction != nil, let label = accessibilityContextLabelText {
            actions.append(NSAccessibilityCustomAction(name: label, handler: { [weak self] in
                return (self?.view as? ShortPeerRowView)?.accessibilityPressContextLabel() ?? false
            }))
        }
        return actions.isEmpty ? nil : actions
    }

    private var accessibilityContextLabelText: String? {
        switch type {
        case let .context(value), let .contextColored(value, _), let .nextContext(value):
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    private var accessibilityPressShowsMenu: Bool {
        switch interactionType {
        case .selectable, .deletable(_, true):
            return false
        default:
            if menuOnAction {
                return true
            }
            if case .nextContext = type {
                return true
            }
            return false
        }
    }

    open override func accessibilityPerformPress() -> Bool {
        guard let view = view as? ShortPeerRowView else {
            return super.accessibilityPerformPress()
        }
        if enabled {
            _ = super.accessibilityPerformPress()
            if case let .selectable(interaction, .left) = interactionType, !passLeftAction {
                interaction.activateSelection(peer)
            } else if accessibilityPressShowsMenu {
                _ = view.accessibilityPerformShowMenu()
            } else {
                view.invokeAction(self, clickCount: 1)
            }
        } else {
            disabledAction?()
        }
        return true
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
}
