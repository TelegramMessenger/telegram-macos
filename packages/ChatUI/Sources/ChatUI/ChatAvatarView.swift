import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMedia
import AvatarUI
import TelegramContext
import TelegramTheme
import TelegramUtils
import ChatModeTypes

public final class ChatAvatarView : Control {
    private let avatar: AvatarStoryControl = AvatarStoryControl(font: .avatar(.title), size: NSMakeSize(36, 36))
    
    private var photoVideoView: MediaPlayerView?
    private var photoVideoPlayer: MediaPlayer?

    private let disposable = MetaDisposable()
    private var storyComponent: AvatarStoryIndicatorComponent?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.userInteractionEnabled = false
        avatar.setFrameSize(frameRect.size)
        addSubview(avatar)
        
        self.scaleOnClick = true
    }
    private var peer: Peer?

    struct ChatPeerMenuContext: Equatable {
        let id: PeerId
        let isGroup: Bool
        let isChannel: Bool
        let isMonoforum: Bool
        let participationStatus: TelegramChannelParticipationStatus?
        let isCreator: Bool
        let canBanMembers: Bool
        let canAddAdmins: Bool
        let canManageRanks: Bool

        init(_ peer: Peer) {
            let channel = peer as? TelegramChannel
            self.id = peer.id
            self.isGroup = peer.isGroup || peer.isSupergroup
            self.isChannel = peer.isChannel
            self.isMonoforum = peer.isMonoForum
            self.participationStatus = channel?.participationStatus
            self.isCreator = channel?.flags.contains(.isCreator) == true
            self.canBanMembers = channel?.hasPermission(.banMembers) == true
            self.canAddAdmins = channel?.hasPermission(.addAdmins) == true
            self.canManageRanks = channel?.hasPermission(.manageRanks) == true
        }
    }

    struct MenuContext: Equatable {
        let account: ObjectIdentifier
        let interaction: ObjectIdentifier
        let chatPeerId: PeerId
        let threadId: Int64?
        let mode: ChatMode
        let rowId: AnyHashable
        let messageId: MessageId?
        let peer: Peer
        let chatPeer: ChatPeerMenuContext?
        let hasStories: Bool

        static func == (lhs: MenuContext, rhs: MenuContext) -> Bool {
            return lhs.account == rhs.account && lhs.interaction == rhs.interaction
                && lhs.chatPeerId == rhs.chatPeerId && lhs.threadId == rhs.threadId && lhs.mode == rhs.mode
                && lhs.rowId == rhs.rowId && lhs.messageId == rhs.messageId
                && lhs.peer.isEqual(rhs.peer) && lhs.chatPeer == rhs.chatPeer && lhs.hasStories == rhs.hasStories
        }
    }

    private static func menuContext(_ item: ChatRowItem, peer: Peer) -> MenuContext {
        let interaction = item.chatInteraction
        return MenuContext(account: ObjectIdentifier(interaction.interactionContext.account), interaction: ObjectIdentifier(interaction), chatPeerId: interaction.peerId, threadId: interaction.chatLocation.threadId, mode: interaction.mode, rowId: item.stableId, messageId: item.message?.id, peer: peer, chatPeer: interaction.peer.map(ChatPeerMenuContext.init), hasStories: item.entry.additionalData.authorStoryStats != nil)
    }

    private var menuBinding = UUID()
    private var menuContext: MenuContext?
    private var isMenuContextCurrent: () -> Bool = { false }

    func updateContextMenu(_ factory: (() -> ContextMenu?)?, context: MenuContext? = nil, isCurrent: @escaping () -> Bool = { true }) {
        if factory == nil || context == nil || menuContext != context {
            menuBinding = UUID()
        }
        menuContext = context
        isMenuContextCurrent = isCurrent
        let binding = menuBinding
        guard let factory else {
            contextMenu = nil
            return
        }
        contextMenu = { [weak self] in
            guard let self, self.menuBinding == binding, self.isMenuContextCurrent(), let menu = factory() else { return nil }
            func guardActions(_ menu: NSMenu) {
                for case let item as ContextMenuItem in menu.items {
                    if let action = item.handler {
                        item.handler = { [weak self] in
                            guard let self, self.menuBinding == binding, self.isMenuContextCurrent() else { return }
                            action()
                        }
                    }
                    if let submenu = item.submenu {
                        guardActions(submenu)
                    }
                }
            }
            guardActions(menu)
            return menu
        }
    }
    
    public func setPeer(item: ChatRowItem, peer: Peer, storyStats: PeerStoryStats? = nil, message: Message? = nil, size: NSSize? = nil, force: Bool = false, disableForum: Bool = false) {
        
        let context = item.chatInteraction.interactionContext
        
        let animated: Bool = self.peer != nil
        
        if let storyStats = storyStats, peer.id != item.context.peerId, message?.id.peerId.namespace == Namespaces.Peer.CloudChannel || message?.id.peerId.namespace == Namespaces.Peer.CloudGroup {
            self.storyComponent = .init(stats: storyStats, presentation: theme)
        } else {
            self.storyComponent = nil
        }
        self.peer = peer
        if peer.id.id._internalGetInt64Value() != 0 {
            let menuContext = Self.menuContext(item, peer: peer)
            self.updateContextMenu(ChatRowView.photoContextMenu(item, peer: peer, setOpenProgress: { [weak self] signal in
                self?.setOpenProgress(signal)
            }), context: menuContext, isCurrent: { [weak item] in
                guard let item else { return false }
                return Self.menuContext(item, peer: peer) == menuContext
            })
        } else {
            self.updateContextMenu(nil)
        }
        
        self.avatar.setPeer(account: context.account, peer: peer, message: message, size: size, disableForum: disableForum)
        if peer.isPremium || force, peer.hasVideo, !TelegramUtilsHooks.shared.isLite(.animations) {
            let signal = peerPhotos(context: context, peerId: peer.id) |> deliverOnMainQueue
            var first = true
            self.disposable.set(signal.start(next: { [weak self] photos in
                self?.updatePhotos(photos.map { $0.value }, context: context, peer: peer, animated: !first)
                first = false
            }))
        } else {
            self.updatePhotos([], context: context, peer: peer, animated: animated)
            self.disposable.set(nil)
        }
        
        self.removeAllHandlers()
        self.set(handler: { [weak item, weak self] control in
            if storyStats != nil, let id = message?.id {
                item?.chatInteraction.openChatPeerStories(id, peer.id, { [weak self] signal in
                    self?.setOpenProgress(signal)
                })
            } else if item?.chatInteraction.presentation.state == .selecting {
                item?.chatInteraction.toggleUnderMouseMessage()
            } else {
                item?.openInfo()
            }
        }, for: .Click)
        
        self.toolTip = item.nameHide
    }
    
    public func setOpenProgress(_ signal:Signal<Never, NoError>) {
        SetOpenStoryDisposable(self.avatar.pushLoadingStatus(signal: signal))
    }
    
    private var videoRepresentation: TelegramMediaImage.VideoRepresentation?
    
    private func updatePhotos(_ photos: [TelegramPeerPhoto], context: any AccountContextProtocol, peer: Peer, animated: Bool) {
        
        if let first = photos.first, let video = first.image.videoRepresentations.first {
            let equal = videoRepresentation?.resource.id == video.resource.id
            
            if !equal {
                
                self.photoVideoView?.removeFromSuperview()
                self.photoVideoView = nil
                
                self.photoVideoView = MediaPlayerView(backgroundThread: true)
                self.photoVideoView!.layer?.cornerRadius = self.avatar.frame.height / 2
                
                self.addSubview(self.photoVideoView!, positioned: .above, relativeTo: self.avatar)

                self.photoVideoView!.isEventLess = true
                
                self.photoVideoView!.frame = self.avatar.frame

                
                let file = TelegramMediaFile(fileId: MediaId(namespace: 0, id: 0), partialReference: nil, resource: video.resource, previewRepresentations: first.image.representations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: video.resource.size, attributes: [], alternativeRepresentations: [])
                
                
                let reference: MediaResourceReference
                
                if let peerReference = PeerReference(peer) {
                    reference = MediaResourceReference.avatar(peer: peerReference, resource: file.resource)
                } else {
                    reference = MediaResourceReference.standalone(resource: file.resource)
                }
                
                let mediaPlayer = MediaPlayer(postbox: context.account.postbox, userLocation: .peer(peer.id), userContentType: .avatar, reference: reference, streamable: true, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: true)
                
                mediaPlayer.actionAtEnd = .loop(nil)
                
                self.photoVideoPlayer = mediaPlayer
                
                if let seekTo = video.startTimestamp {
                    mediaPlayer.seek(timestamp: seekTo)
                }
                mediaPlayer.attachPlayerView(self.photoVideoView!)
                self.videoRepresentation = video
            }
        } else {
            self.photoVideoPlayer = nil
            self.photoVideoView?.removeFromSuperview()
            self.photoVideoView = nil
            self.videoRepresentation = nil
        }
        
        let transition: ContainedViewLayoutTransition = animated  ? .animated(duration: 0.2, curve: .easeOut) : .immediate

        if let storyComponent = storyComponent {
            avatar.update(component: storyComponent, availableSize: bounds.insetBy(dx: 3, dy: 3).size, transition: transition)
            if let view = self.photoVideoView {
                transition.updateFrame(view: view, frame: bounds.insetBy(dx: 3, dy: 3))
                view.layer?.cornerRadius = self.avatar.radius
            }
        } else {
            avatar.update(component: nil, availableSize: bounds.size, transition: transition)
            if let view = self.photoVideoView {
                transition.updateFrame(view: view, frame: bounds)
                view.layer?.cornerRadius = self.avatar.radius
            }
        }
        updatePlayerIfNeeded()
    }
    
    public var storyControl: NSView {
        return avatar
    }
    
    @objc public func updatePlayerIfNeeded() {
        let accept = window != nil && window!.isKeyWindow && !NSIsEmptyRect(visibleRect)
        if let photoVideoPlayer = photoVideoPlayer {
            if accept {
                photoVideoPlayer.play()
            } else {
                photoVideoPlayer.pause()
            }
        }
    }
    
    public override func viewDidUpdatedDynamicContent() {
        super.viewDidUpdatedDynamicContent()
        updatePlayerIfNeeded()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    private let animatableContentObserver = AnimatableContentObserver()

    public func updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(updatePlayerIfNeeded), options: [.contentBounds])
    }
    
    public func removeNotificationListeners() {
        NotificationCenter.default.removeObserver(self)
    }
    deinit {
        disposable.set(nil)
        NotificationCenter.default.removeObserver(self)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
    
    public override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }
}
