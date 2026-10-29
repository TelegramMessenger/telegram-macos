import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramMedia
import SwiftSignalKit
import AVFoundation
import AvatarUI
import Localization
import PremiumStatusUI
import ShortPeerRow
import TelegramTheme
import TelegramUtils
import InlineStickerLayer


private final class RightActionsCluster: Control {
    let doneFill: View = View()
    let callButton: ChatAccessibleImageButton = ChatAccessibleImageButton()
    let searchButton: ChatAccessibleImageButton = ChatAccessibleImageButton()
    let menuButton: ChatAccessibleImageButton = ChatAccessibleImageButton()

    var onCallClick: (() -> Void)?
    var onSearchClick: (() -> Void)?
    var onMenuClick: (() -> Void)?

    private static let iconMorphDuration: Double = 0.2
    private static let iconMorphScale: CGFloat = 0.2

    override init() {
        super.init(frame: .zero)
        self.layer?.masksToBounds = false
        self.backgroundColor = .clear
        doneFill.isEventLess = true
        doneFill.layer?.opacity = 0
        addSubview(doneFill)
        for btn in [callButton, searchButton, menuButton] {
            btn.userInteractionEnabled = false
            btn.autohighlight = false
            btn.layer?.masksToBounds = false
            addSubview(btn)
        }
        self.interactiveGlassView = self

        self.set(handler: { [weak self] _ in
            self?.dispatchClick()
        }, for: .Click)

        callButton.accessibilityPress = { [weak self] in self?.onCallClick?() }
        searchButton.accessibilityPress = { [weak self] in self?.onSearchClick?() }
        searchButton.setAccessibilityLabel(strings().voiceOverCommonSearch)
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private func dispatchClick() {
        guard let event = NSApp.currentEvent else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard NSPointInRect(point, bounds) else { return }
        let visible = visibleButtons
        guard !visible.isEmpty else { return }
        let segWidth = bounds.width / CGFloat(visible.count)
        let idx = max(0, min(visible.count - 1, Int(point.x / segWidth)))
        let target = visible[idx]
        if target === callButton { onCallClick?() }
        else if target === searchButton { onSearchClick?() }
        else if target === menuButton { onMenuClick?() }
    }

    var visibleButtons: [ImageButton] {
        return [callButton, searchButton, menuButton].filter { !$0.isHidden }
    }

    var visibleButtonCount: Int { return visibleButtons.count }

    static let insidePadding: CGFloat = 4

    func desiredWidth(buttonSize: CGFloat) -> CGFloat {
        return Self.desiredWidth(buttonSize: buttonSize, count: visibleButtonCount)
    }

    static func desiredWidth(buttonSize: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let padding = count > 1 ? 2 * Self.insidePadding : 0
        return CGFloat(count) * buttonSize + padding
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        doneFill.layer?.cornerRadius = size.height / 2
        transition.updateFrame(view: doneFill, frame: NSRect(origin: .zero, size: size))
        let visible = visibleButtons
        guard !visible.isEmpty else { return }
        let buttonSize = size.height
        let totalIconsWidth = CGFloat(visible.count) * buttonSize
        let pad = max(0, (size.width - totalIconsWidth) / 2)
        for (i, btn) in visible.enumerated() {
            transition.updateFrame(view: btn, frame: NSRect(x: pad + CGFloat(i) * buttonSize, y: 0, width: buttonSize, height: buttonSize))
        }
    }

    func animateVisibilityChange(from previous: [ImageButton]) {
        let visible = visibleButtons
        for button in previous where !visible.contains(button) {
            if let image = button.imageView.image, let layer = self.layer {
                addOutgoingIcon(image, frame: convert(button.imageView.frame, from: button), to: layer)
            }
        }
        for button in visible where !previous.contains(button) {
            animateIconIn(of: button)
        }
    }

    func animateMenuIconChange(from previous: CGImage) {
        guard let layer = menuButton.layer else {
            return
        }
        menuButton.imageView.layer?.removeAnimation(forKey: "contents")
        addOutgoingIcon(previous, frame: menuButton.imageView.frame, to: layer)
        animateIconIn(of: menuButton)
    }

    private func animateIconIn(of button: ImageButton) {
        guard let layer = button.imageView.layer else {
            return
        }
        layer.animateAlpha(from: 0, to: 1, duration: Self.iconMorphDuration, timingFunction: .easeInEaseOut)
        layer.animateScaleCenter(from: Self.iconMorphScale, to: 1, duration: Self.iconMorphDuration)
    }

    private func addOutgoingIcon(_ image: CGImage, frame: NSRect, to host: CALayer) {
        let outgoing = CALayer()
        outgoing.contents = image
        outgoing.contentsGravity = .resizeAspect
        outgoing.contentsScale = System.backingScale
        outgoing.frame = frame
        outgoing.opacity = 0
        host.addSublayer(outgoing)

        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = Self.iconMorphScale
        shrink.duration = Self.iconMorphDuration
        shrink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        outgoing.add(shrink, forKey: "iconMorphScale")
        outgoing.animateAlpha(from: 1, to: 0, duration: Self.iconMorphDuration, timingFunction: .easeInEaseOut, completion: { [weak outgoing] _ in
            outgoing?.removeFromSuperlayer()
        })
    }
}


private final class TitlePillView: Control {

    var avatarRect: NSRect = .zero
    var avatarTapHandler: (() -> Void)?
    var titleTapHandler: (() -> Void)?
    var accessibilityTitleProvider: (() -> String?)?
    var accessibilityStatusProvider: (() -> String?)?
    var accessibilityAvatarActionProvider: (() -> String?)?

    override var accessibilityDefaultLabel: String? {
        return accessibilityTitleProvider?()
    }

    override func accessibilityValue() -> Any? {
        return accessibilityStatusProvider?()
    }

    override func accessibilityChildren() -> [Any]? {
        return []
    }

    override func accessibilityPerformPress() -> Bool {
        guard let titleTapHandler else {
            return false
        }
        titleTapHandler()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard avatarTapHandler != nil, let name = accessibilityAvatarActionProvider?() else {
            return nil
        }
        return [NSAccessibilityCustomAction(name: name, handler: { [weak self] in
            self?.avatarTapHandler?()
            return true
        })]
    }

    override init() {
        super.init(frame: .zero)
        self.layer?.masksToBounds = true
        self.backgroundColor = .clear
        self.scaleOnClick = true
        
        set(handler: { [weak self] control in
            guard let self, let event = NSApp.currentEvent else {
                return
            }
            let point = self.convert(event.locationInWindow, from: nil)
            guard NSPointInRect(point, bounds) else { return }
            if NSPointInRect(point, self.avatarRect) {
                self.avatarTapHandler?()
            } else {
                self.titleTapHandler?()
            }
        }, for: .SingleClick)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

}


final class ChatHeaderBubblesView: View, InteractionContentViewProtocol {

    static let bubbleHeight: CGFloat = 40
    static let topInset: CGFloat = 12
    static let bottomInset: CGFloat = 10
    static let sideInset: CGFloat = 12
    static let interBubbleSpacing: CGFloat = 10

    private static let menuModeTransition: ContainedViewLayoutTransition = .animated(duration: ChatInputSendButton.fieldMotionDuration, curve: .easeOut)

    var leftSideInset: CGFloat = sideInset

    static var totalHeight: CGFloat {
        return bubbleHeight + topInset + bottomInset
    }


    private let chatInteraction: ChatInteraction

    private let centerBubble: TitlePillView

    private let backButton: ImageButton
    private let leftEdgeHandle: Control = Control()
    private let rightCluster: RightActionsCluster

    private let glassWrapper: GlassContainerView
    private let backGhost: LiquidGlassView
    private let centerGhost: LiquidGlassView
    private let rightGhost: LiquidGlassView

    /// Same shared glass surface, exposed as the wrapper itself so callers
    /// can register their `LiquidGlassView` as a ghost (`addGhost`) and
    /// update its frame via `setGhostFrame` — the proper API path that
    /// reparents `appearanceContainer` + `effectView` for lockstep
    /// horizontal/vertical animations.
    public var sharedGlassWrapper: GlassContainerView? { return glassWrapper }

    /// Extra vertical height the container should cover beyond
    /// `bubbleBarHeight`. Used to extend the merged glass region down to
    /// cover the chat-header (pinned messages etc.) area.
    public var extendedContentHeight: CGFloat = 0 {
        didSet {
            if oldValue != extendedContentHeight {
                needsLayout = true
            }
        }
    }

    private var callButton: ChatAccessibleImageButton { return rightCluster.callButton }
    private var searchButton: ChatAccessibleImageButton { return rightCluster.searchButton }
    private var menuButton: ChatAccessibleImageButton { return rightCluster.menuButton }

    private let avatarControl: AvatarStoryControl = AvatarStoryControl(font: .avatar(12), size: NSMakeSize(32, 32))
    private let titleView: TextView = TextView()
    private let statusView: TextView = TextView()
    private let activities: ChatActivitiesModel = ChatActivitiesModel()

    private var titleImageView: ImageView?

    private var statusControl: PremiumStatusControl?
    private var leftStatusControl: PremiumStatusControl?
    private var liveStreamView: ImageView?
    private var inlineTopicPhotoLayer: InlineStickerItemLayer?

    private var presenceManager: PeerPresenceStatusManager?

    private var searchHidden: Bool = false
    var displaysInlineHeader: Bool = false
    private var previousInlineHeaderFrame: NSRect?
    private var callHidden: Bool = true
    private var showActivities: Bool = false

    var avatarStoryControl: AvatarStoryControl {
        return avatarControl
    }

    var hasStories: Bool {
        if let storyState = story, !storyState.items.isEmpty {
            return true
        }
        return false
    }

    func contentInteractionView(for stableId: AnyHashable, animateIn: Bool) -> NSView? {
        if chatInteraction.presentation.mainPeer?.largeProfileImage?.resource.id.stringRepresentation == stableId.base as? String {
            return avatarControl.avatar
        }
        return nil
    }
    func interactionControllerDidFinishAnimation(interactive: Bool, for stableId: AnyHashable) {
    }
    func addAccesoryOnCopiedView(for stableId: AnyHashable, view: NSView) {
    }
    func videoTimebase(for stableId: AnyHashable) -> CMTimebase? {
        return nil
    }
    func applyTimebase(for stableId: AnyHashable, timebase: CMTimebase?) {
    }

    private var peerView: PeerView?
    private var story: PeerExpiringStoryListContext.State?
    private var counters: ChatTitleCounters = .init()

    var connectionStatus: ConnectionStatus = .online(proxyAddress: nil) {
        didSet {
            if connectionStatus != oldValue {
                updateStatusText(presentation: chatInteraction.presentation)
            }
        }
    }

    var inputActivities: (PeerId, [(Peer, PeerInputActivity)])? {
        didSet {
            updateInputActivities()
        }
    }

    private var inputActivitiesWidth: CGFloat?

    private func updateInputActivities() {
        if let inputActivities, self.chatInteraction.mode != .scheduled && self.chatInteraction.mode != .pinned {
            let width = max(centerBubble.frame.width - 60, 160)
            inputActivitiesWidth = width
            let textColor = theme.colors.accent
            activities.update(with: inputActivities, for: width, theme: theme.activity(key: 4, foregroundColor: textColor, backgroundColor: .clear), layout: { [weak self] show in
                guard let self else { return }
                self.showActivities = show
                if let view = self.activities.view {
                    view.layer?.opacity = 1
                    view.layer?.removeAllAnimations()
                    self.updateActivitiesAttachment(view, show: show)
                }
                self.statusView.isHidden = show || self.statusView.textLayout == nil
                self.needsLayout = true
            })
        } else {
            inputActivitiesWidth = nil
            activities.clean()
            showActivities = false
            if let view = self.activities.view {
                updateActivitiesAttachment(view, show: false)
            }
            self.statusView.isHidden = self.statusView.textLayout == nil
            self.needsLayout = true
        }
    }

    private func updateActivitiesAttachment(_ view: NSView, show: Bool) {
        if show {
            if view.superview !== centerBubble {
                centerBubble.addSubview(view, positioned: .above, relativeTo: statusView)
            }
        } else {
            view.removeFromSuperview()
        }
    }

    var hasBackButton: Bool = true {
        didSet {
            if oldValue != hasBackButton {
                updateBackButtonIcon()
                needsLayout = true
            }
        }
    }

    var isCloseButton: Bool = false {
        didSet {
            if oldValue != isCloseButton {
                updateBackButtonIcon()
            }
        }
    }

    private func updateBackButtonIcon() {
        self.backButton.isHidden = !hasBackButton
        self.backGhost.isHidden = !hasBackButton
        let icon = isCloseButton ? theme.icons.chat_header_close : theme.icons.chat_header_back
        backButton.set(image: icon, for: .Normal)
        backButton.setAccessibilityLabel(isCloseButton ? strings().voiceOverCommonClose : strings().voiceOverCommonBack)
    }

    var backHandler: (() -> Void)?
    var avatarHandler: (() -> Void)?
    var avatarAccessibilityActionName: (() -> String?)?
    var titleHandler: (() -> Void)?
    var searchHandler: (() -> Void)?
    var callHandler: (() -> Void)?
    var doneHandler: (() -> Void)?
    var menuContextMenu: (() -> ContextMenu?)?

    private var menuMode: MenuMode = .menu

    /// Most-recent chat theme used to render this view. Stored so helpers
    /// like `applyMenuMode` — which may be called outside the scope of
    /// `updateLocalizationAndTheme` (e.g. from `setMenuMode`) — can resolve
    /// tints/icons against the chat's palette instead of falling through
    /// to the global app `theme` singleton, which is wrong for chats on a
    /// custom palette or wallpaper.
    private var currentChatTheme: TelegramPresentationTheme?

    enum MenuMode {
        case menu
        case done
    }

    init(frame frameRect: NSRect, chatInteraction: ChatInteraction) {
        self.chatInteraction = chatInteraction

        self.centerBubble = TitlePillView()

        self.backButton = ImageButton()
        self.rightCluster = RightActionsCluster()
        self.glassWrapper = GlassContainerView(frame: frameRect, flipped: true, spacing: 5)

        let cornerRadius = ChatHeaderBubblesView.bubbleHeight / 2
        
        self.backGhost = LiquidGlassView(frame: .zero, cornerRadius: cornerRadius, hasShadow: true, hasBorder: true, tintAlpha: 0.4)
        self.centerGhost = LiquidGlassView(frame: .zero, cornerRadius: cornerRadius, hasShadow: true, hasBorder: true, tintAlpha: 0.4)
        self.rightGhost = LiquidGlassView(frame: .zero, cornerRadius: cornerRadius, hasShadow: true, hasBorder: true, tintAlpha: 0.4)

        super.init(frame: frameRect)

        self.backgroundColor = .clear
        self.isEventLess = true
        self.layer?.masksToBounds = false

        glassWrapper.glassContent.backgroundColor = .clear
        addSubview(glassWrapper)

        glassWrapper.addGhost(rightGhost)
        glassWrapper.addGhost(centerGhost)
        glassWrapper.addGhost(backGhost)

        rightCluster.additionalGlassEffectView = rightGhost

        addSubview(centerBubble)
        addSubview(backButton)
        addSubview(leftEdgeHandle)
        addSubview(rightCluster)

        leftEdgeHandle.set(handler: { [weak self] _ in
            self?.backHandler?()
        }, for: .Click)
        leftEdgeHandle.isAccessibilityDecorative = true

        centerBubble.addSubview(avatarControl)
        avatarControl.userInteractionEnabled = false
        centerBubble.addSubview(titleView)
        centerBubble.addSubview(statusView)
        if let activitiesView = activities.view {
            activitiesView.isEventLess = true
        }

        centerBubble.avatarTapHandler = { [weak self] in
            self?.avatarHandler?()
        }
        centerBubble.titleTapHandler = { [weak self] in
            self?.titleHandler?()
        }
        centerBubble.accessibilityAvatarActionProvider = { [weak self] in
            return self?.avatarAccessibilityActionName?()
        }
        centerBubble.accessibilityTitleProvider = { [weak self] in
            return self?.titleView.textLayout?.attributedString.string
        }
        centerBubble.accessibilityStatusProvider = { [weak self] in
            guard let self else { return nil }
            if self.showActivities, let text = self.activities.view?.subviews.compactMap({ ($0 as? TextView)?.textLayout?.attributedString.string }).first {
                return text
            }
            return self.statusView.textLayout?.attributedString.string
        }

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        titleView.isEventLess = true
        statusView.userInteractionEnabled = false
        statusView.isSelectable = false
        statusView.isEventLess = true

        backButton.autohighlight = false
        backButton.scaleOnClick = true
        backButton.set(handler: { [weak self] _ in
            self?.backHandler?()
        }, for: .Click)

        callButton.isHidden = true

        rightCluster.onCallClick = { [weak self] in self?.callHandler?() }
        rightCluster.onSearchClick = { [weak self] in self?.searchHandler?() }
        rightCluster.onMenuClick = { [weak self] in self?.handleMenuClick() }

        callButton.accessibilityLabelProvider = { [weak self] in
            guard let self else { return nil }
            if let peer = self.peerView.flatMap({ peerViewMainPeer($0) }), peer.isGroup || peer.isSupergroup || peer.isChannel {
                return strings().peerInfoActionVoiceChat
            }
            return strings().voiceOverCommonCall
        }
        menuButton.accessibilityLabelProvider = { [weak self] in
            return self?.menuMode == .done ? strings().voiceOverCommonDone : strings().voiceOverCommonMore
        }
        menuButton.accessibilityPress = { [weak self] in
            self?.handleAccessibilityMenuPress()
        }

        self.presenceManager = PeerPresenceStatusManager(update: { [weak self] in
            guard let self else { return }
            self.updateStatusText(presentation: self.chatInteraction.presentation)
        })

        updateLocalizationAndTheme(theme: theme)

        backButton.setGlassEffectHidden(true)
        backButton.additionalGlassEffectView = backGhost
        centerBubble.interactiveGlassView = centerBubble
        centerBubble.additionalGlassEffectView = centerGhost
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        self.currentChatTheme = theme
        let buttonSize = NSMakeSize(Self.bubbleHeight, Self.bubbleHeight)

        updateBackButtonIcon()
        backButton.setGlassEffect(size: buttonSize)
        backButton.sizeToFit(NSZeroSize, buttonSize, thatFit: true)

        searchButton.set(image: theme.icons.chat_header_search, for: .Normal)
        searchButton.sizeToFit(NSZeroSize, buttonSize, thatFit: true)

        menuButton.sizeToFit(NSZeroSize, buttonSize, thatFit: true)

        applyCallButtonImage()
        callButton.sizeToFit(NSZeroSize, buttonSize, thatFit: true)

        backGhost.updateLocalizationAndTheme(theme: theme)
        centerGhost.updateLocalizationAndTheme(theme: theme)
        rightGhost.updateLocalizationAndTheme(theme: theme)

        let chatGlassTint = theme.colors.background.withAlphaComponent(0.4)
        backGhost.customTint = chatGlassTint
        centerGhost.customTint = chatGlassTint
        rightGhost.customTint = chatGlassTint
        applyMenuMode()

        updateStatusText(presentation: chatInteraction.presentation)
        needsLayout = true
    }

    private func applyCallButtonImage() {
        let mainPeer = peerView.flatMap { peerViewMainPeer($0) }
        if let peer = mainPeer, peer.isGroup || peer.isSupergroup || peer.isChannel {
            callButton.set(image: theme.icons.chat_header_voice_call, for: .Normal)
        } else {
            callButton.set(image: theme.icons.chat_header_call, for: .Normal)
        }
    }

    func update(_ peerView: PeerView?, story: PeerExpiringStoryListContext.State?, counters: ChatTitleCounters, animated: Bool) {
        self.counters = counters
        self.peerView = peerView
        self.story = story
        updateAvatar(animated: animated)
        updateStoryRing(story, animated: animated)
        updateLiveStream(story, animated: animated)
        updateStatusText(presentation: chatInteraction.presentation)
        updatePeerExtras(presentation: chatInteraction.presentation, animated: animated)
        applyCallButtonImage()
        needsLayout = true
    }

    func updatePresentation(_ presentation: ChatPresentationInterfaceState, force: Bool = false) {
        updateStatusText(presentation: presentation, force: force)
        updatePeerExtras(presentation: presentation, animated: false)
        applyCallButtonImage()
        needsLayout = true
    }


    func updateSearchButton(hidden: Bool, animated: Bool) {
        if searchHidden != hidden {
            searchHidden = hidden
            searchButton.isHidden = hidden
            needsLayout = true
        }
    }

    func setMenuMode(_ mode: MenuMode) {
        if menuMode != mode {
            menuMode = mode
            backButton.resetGlassTouchTracking()
            centerBubble.resetGlassTouchTracking()
            rightCluster.resetGlassTouchTracking()
            let visibleButtons = rightCluster.visibleButtons
            let menuIcon = menuButton.imageView.image
            self.applyMenuMode(animated: true)
            self.updateLayout(size: self.frame.size, transition: Self.menuModeTransition)
            rightCluster.animateVisibilityChange(from: visibleButtons)
            if let menuIcon, menuIcon != menuButton.imageView.image {
                rightCluster.animateMenuIconChange(from: menuIcon)
            }
        }
    }

    private func applyMenuMode(animated: Bool = false) {
        let activeTheme = currentChatTheme ?? theme
        switch menuMode {
        case .menu:
            menuButton.set(image: activeTheme.icons.chat_header_actions, for: .Normal)
        case .done:
            menuButton.set(image: activeTheme.icons.chat_header_done, for: .Normal)
        }
        rightCluster.doneFill.backgroundColor = activeTheme.colors.accent
        rightCluster.doneFill.change(opacity: menuMode == .done ? 1 : 0, animated: animated, duration: Self.menuModeTransition.duration)
    }

    private func handleAccessibilityMenuPress() {
        switch menuMode {
        case .menu:
            guard let menu = menuContextMenu?(), let window = window else { return }
            let point = menuButton.convert(NSMakePoint(menuButton.bounds.midX, menuButton.bounds.midY), to: nil)
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            AppMenu.show(menu: menu, event: event, for: rightCluster)
        case .done:
            doneHandler?()
        }
    }

    private func handleMenuClick() {
        switch menuMode {
        case .menu:
            guard let menu = menuContextMenu?(), let event = NSApp.currentEvent else { return }
            AppMenu.show(menu: menu, event: event, for: rightCluster)
        case .done:
            doneHandler?()
        }
    }

    private func updateAvatar(animated: Bool) {
        guard let peerView = peerView else { return }
        let context = chatInteraction.interactionContext

        if let peer = peerViewMainPeer(peerView) {
            if peer.id == repliesPeerId {
                let icon = theme.icons.chat_replies_avatar
                avatarControl.setSignal(generateEmptyPhoto(avatarControl.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(avatarControl.frame.size.width - 14, avatarControl.frame.size.height - 14)), cornerRadius: nil), bubble: false) |> map { ($0, false) })
            } else if peer.id == context.peerId, chatInteraction.mode.isSavedMessagesThread {
                let icon = theme.icons.chat_my_notes
                avatarControl.setSignal(generateEmptyPhoto(avatarControl.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(avatarControl.frame.size.width - 4, avatarControl.frame.size.height - 4)), cornerRadius: nil), bubble: false) |> map { ($0, false) })
            } else if peer.id == context.peerId {
                let icon = theme.icons.searchSaved
                avatarControl.setSignal(generateEmptyPhoto(avatarControl.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(avatarControl.frame.size.width - 12, avatarControl.frame.size.height - 12)), cornerRadius: nil), bubble: false) |> map { ($0, false) })
            } else {
                if peer.isMonoForum, let mainForumPeer = peerViewMonoforumMainPeer(peerView) {
                    avatarControl.setState(account: context.account, state: .PeerAvatar(peer, TelegramUtilsHooks.shared.peerLetters(mainForumPeer), mainForumPeer.smallProfileImage, mainForumPeer.namePeerColor, nil, nil, mainForumPeer.groupAccess.canManageDirect, nil))
                } else {
                    avatarControl.setPeer(account: context.account, peer: peer, disableForum: true)
                }
            }
        }
    }

    private func updateStoryRing(_ story: PeerExpiringStoryListContext.State?, animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        if let storyState = story, !storyState.items.isEmpty {
            let component = AvatarStoryIndicatorComponent(state: storyState, presentation: theme, isRoundedRect: false)
            avatarControl.update(component: component, availableSize: NSMakeSize(26, 26), transition: transition)
        } else {
            avatarControl.update(component: nil, availableSize: NSMakeSize(32, 32), transition: transition)
        }
    }

    private func updateLiveStream(_ story: PeerExpiringStoryListContext.State?, animated: Bool) {
        if let story = story, story.hasLiveItems {
            let current: ImageView
            if let view = liveStreamView {
                current = view
            } else {
                current = ImageView()
                current.isEventLess = true
                current.isAccessibilityDecorative = true
                self.liveStreamView = current
                centerBubble.addSubview(current)
            }
            current.image = ChatUIHooks.shared.generateLiveStreamBadge(7, theme.colors.background)
            current.sizeToFit()
        } else if let view = liveStreamView {
            performSubviewRemoval(view, animated: animated)
            self.liveStreamView = nil
        }
    }

    private func updatePeerExtras(presentation: ChatPresentationInterfaceState, animated: Bool) {
        guard let peerView else {
            removePremiumControls()
            removeTopicLayer(animated: animated)
            titleImageView?.removeFromSuperview()
            titleImageView = nil
            return
        }

        let context = chatInteraction.interactionContext

        if peerView.peers[peerView.peerId] is TelegramSecretChat {
            let current: ImageView
            if let view = titleImageView {
                current = view
            } else {
                current = ImageView()
                current.isEventLess = true
                current.isAccessibilityDecorative = true
                centerBubble.addSubview(current, positioned: .above, relativeTo: avatarControl)
                titleImageView = current
            }
            current.image = theme.icons.chat_header_secret_lock
            current.sizeToFit()
        } else {
            titleImageView?.removeFromSuperview()
            titleImageView = nil
        }

        var newStatusControl: PremiumStatusControl?
        var newLeftStatusControl: PremiumStatusControl?

        if let peer = peerViewMainPeer(peerView), chatInteraction.mode == .history || chatInteraction.mode.isSavedMessagesThread {
            if let displayPeer = (peerViewMonoforumMainPeer(peerView) ?? peerViewMainPeer(peerView)) {
                if chatInteraction.interactionContext.peerId != chatInteraction.peerId || chatInteraction.mode.isSavedMessagesThread, presentation.reportMode == nil {
                    newStatusControl = PremiumStatusControl.control(displayPeer, account: context.account, inlinePacksContext: context.inlinePacksContext, left: false, isSelected: false, cached: self.statusControl, animated: animated)
                    newLeftStatusControl = PremiumStatusControl.control(displayPeer, account: context.account, inlinePacksContext: context.inlinePacksContext, left: true, isSelected: false, cached: self.leftStatusControl, animated: animated)
                }
                _ = peer
            }
        }

        if let control = newStatusControl {
            self.statusControl = control
            centerBubble.addSubview(control)
        } else if let view = self.statusControl {
            performSubviewRemoval(view, animated: animated)
            self.statusControl = nil
        }
        if let control = newLeftStatusControl {
            self.leftStatusControl = control
            centerBubble.addSubview(control)
        } else if let view = self.leftStatusControl {
            performSubviewRemoval(view, animated: animated)
            self.leftStatusControl = nil
        }

        if let threadInfo = presentation.threadInfo, isTopicMode(presentation) {
            let size = NSMakeSize(30, 30)
            let info = threadInfo.info
            let fallbackFile = TelegramUtilsHooks.shared.topicFile!(info.title, info.iconColor, presentation.chatLocation.threadId == 1)
            let targetFileId: Int64 = info.icon ?? fallbackFile.fileId.id
            let current: InlineStickerItemLayer
            if let layer = self.inlineTopicPhotoLayer, layer.file?.fileId.id == targetFileId {
                current = layer
            } else {
                if let layer = inlineTopicPhotoLayer {
                    performSublayerRemoval(layer, animated: animated)
                    self.inlineTopicPhotoLayer = nil
                }
                if let fileId = info.icon {
                    current = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: size, playPolicy: .playCount(2))
                } else {
                    current = .init(account: context.account, file: fallbackFile, size: size, playPolicy: .playCount(2))
                }
                current.superview = centerBubble
                centerBubble.layer?.addSublayer(current)
                self.inlineTopicPhotoLayer = current
            }
            avatarControl.isHidden = true
        } else {
            removeTopicLayer(animated: animated)
            avatarControl.isHidden = false
        }

        var callVisible = false
        switch chatInteraction.mode {
        case .history:
            if let peer = peerViewMainPeer(peerView) {
                if peer.isGroup || peer.isSupergroup || peer.isChannel {
                    if let groupCall = presentation.groupCall {
                        if let data = groupCall.data, data.participantCount == 0 && groupCall.activeCall.scheduleTimestamp == nil {
                            callVisible = presentation.reportMode == nil
                        } else {
                            callVisible = false
                        }
                    } else {
                        callVisible = false
                    }
                } else {
                    callVisible = peer.canCall && chatInteraction.peerId != chatInteraction.interactionContext.peerId && presentation.reportMode == nil && !chatInteraction.isMonoforum
                }
            }
        default:
            callVisible = false
        }
        callHidden = !callVisible
        callButton.isHidden = !callVisible
    }

    private func removePremiumControls() {
        if let view = self.statusControl {
            view.removeFromSuperview()
            self.statusControl = nil
        }
        if let view = self.leftStatusControl {
            view.removeFromSuperview()
            self.leftStatusControl = nil
        }
    }

    private func removeTopicLayer(animated: Bool) {
        if let layer = inlineTopicPhotoLayer {
            performSublayerRemoval(layer, animated: animated)
            self.inlineTopicPhotoLayer = nil
        }
    }

    private func computeTitleStatus(presentation: ChatPresentationInterfaceState) -> PeerStatusStringResult? {
        guard let peerView = peerView, let peer = peerViewMainPeer(peerView) else { return nil }

        var result = stringStatus(for: peerView, context: chatInteraction.interactionContext, theme: PeerStatusStringTheme(titleFont: .medium(.title), statusColor: theme.colors.grayText, highlightColor: theme.colors.accent), onlineMemberCount: counters.online, ignoreActivity: presentation.chatMode.isSavedMessagesThread || presentation.chatMode.customChatLink != nil || presentation.isMonoforum)

        if presentation.isMonoforum {
            if !presentation.monoforumTopics.isEmpty, presentation.chatLocation.threadId == nil {
                result = result.withUpdatedStatus(strings().chatTitleChatsOther(presentation.monoforumTopics.count))
            } else {
                result = result.withUpdatedStatus(strings().chatTitleTopicOther(Int(counters.replies ?? 0)))
            }
        } else if let customLinkContents = chatInteraction.mode.customChatLink {
            result = result.withUpdatedTitle(customLinkContents.name.isEmpty ? customLinkContents.link : customLinkContents.name).withUpdatedStatus(customLinkContents.name.isEmpty ? "" : customLinkContents.link)
        } else if let customChatContents = chatInteraction.mode.customChatContents {
            result = result.withUpdatedTitle(customChatContents.kind.text).withUpdatedStatus("")
        } else if chatInteraction.mode == .pinned {
            result = result.withUpdatedTitle(strings().chatTitlePinnedMessagesOther(presentation.pinnedMessageId?.totalCount ?? 0)).withUpdatedStatus("")
        } else if chatInteraction.mode == .scheduled {
            result = result.withUpdatedTitle(strings().chatTitleScheduledMessages).withUpdatedStatus("")
        } else if let threadInfo = presentation.threadInfo, isTopicMode(presentation) {
            if let count = counters.replies, count > 0 {
                result = result.withUpdatedTitle(threadInfo.info.title).withUpdatedStatus(strings().chatTitleTopicOther(Int(count)))
            } else {
                result = result.withUpdatedTitle(threadInfo.info.title).withUpdatedStatus(strings().peerInfoTopicStatusIn(peer.displayTitle))
            }
        } else if case let .thread(mode) = chatInteraction.mode, case let .thread(data) = chatInteraction.chatLocation {
            switch mode {
            case .comments:
                result = result.withUpdatedTitle(strings().chatTitleDiscussion).withUpdatedStatus(strings().chatTitleCommentsOther(Int(counters.replies ?? 0)))
            case .replies:
                result = result.withUpdatedTitle(strings().chatTitleDiscussion).withUpdatedStatus(strings().chatTitleRepliesOther(Int(counters.replies ?? 0)))
            case .topic:
                if let count = counters.replies, count > 0 {
                    result = result.withUpdatedTitle(presentation.threadInfo?.info.title ?? "").withUpdatedStatus(strings().chatTitleTopicOther(Int(count)))
                } else {
                    result = result.withUpdatedTitle(presentation.threadInfo?.info.title ?? "").withUpdatedStatus(strings().peerInfoTopicStatusIn(peer.displayTitle))
                }
            case .savedMessages:
                if let count = counters.replies, count > 0 {
                    result = result.withUpdatedTitle(peer.displayTitle).withUpdatedStatus(strings().chatTitleTopicOther(Int(count)))
                } else {
                    result = result.withUpdatedTitle(presentation.threadInfo?.info.title ?? "").withUpdatedStatus(strings().peerInfoTopicStatusIn(peer.displayTitle))
                }
                if PeerId(data.threadId) == chatInteraction.interactionContext.peerId {
                    result = result.withUpdatedTitle(strings().peerMyNotes)
                }
            case .saved:
                break
            }
        } else if chatInteraction.interactionContext.peerId == peerView.peerId {
            if chatInteraction.mode == .scheduled {
                result = result.withUpdatedTitle(strings().chatTitleReminder).withUpdatedStatus("")
            } else {
                result = result.withUpdatedTitle(strings().peerSavedMessages).withUpdatedStatus("")
            }
        }

        switch connectionStatus {
        case let .connecting(proxy, _):
            result = result.withUpdatedStatus((proxy != nil ? strings().chatConnectingStatusConnectingToProxy : strings().chatConnectingStatusConnecting).lowercased())
        case .updating:
            result = result.withUpdatedStatus(strings().chatConnectingStatusUpdating.lowercased())
        case .waitingForNetwork:
            result = result.withUpdatedStatus(strings().chatConnectingStatusWaitingNetwork.lowercased())
        case .online:
            break
        }

        return result
    }

    private func updateStatusText(presentation: ChatPresentationInterfaceState, force: Bool = false) {
        guard let result = computeTitleStatus(presentation: presentation) else {
            titleView.update(nil)
            statusView.update(nil)
            return
        }

        let titleString = NSMutableAttributedString()
        titleString.append(result.title)
        titleString.addAttribute(.foregroundColor, value: theme.colors.text, range: titleString.range)
        titleString.addAttribute(.font, value: NSFont.medium(.text), range: titleString.range)

        let statusString = NSMutableAttributedString()
        statusString.append(result.status)
        statusString.addAttribute(.font, value: NSFont.normal(.small), range: statusString.range)

        let titleLayout = TextViewLayout(titleString, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
        titleLayout.measure(width: max(60, frame.width - sideInsetForCenterContent()))
        titleView.update(titleLayout)

        if statusString.length > 0 {
            let statusLayout = TextViewLayout(statusString, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
            statusLayout.measure(width: max(60, frame.width - sideInsetForCenterContent()))
            statusView.update(statusLayout)
            statusView.isHidden = showActivities
        } else {
            statusView.update(nil)
            statusView.isHidden = true
        }

        if let presence = result.presence {
            self.presenceManager?.reset(presence: presence, timeDifference: Int32(chatInteraction.interactionContext.timeDifference))
        }
    }

    private func isTopicMode(_ presentation: ChatPresentationInterfaceState) -> Bool {
        return presentation.isTopicMode || (chatInteraction.mode == .preview && presentation.chatLocation.threadId != nil)
    }

    private func sideInsetForCenterContent() -> CGFloat {
        if chatInteraction.mode == .preview {
            return Self.sideInset * 2 + Self.bubbleHeight + Self.interBubbleSpacing + 32 + 24
        }
        return Self.sideInset * 2 + Self.bubbleHeight * 4 + Self.interBubbleSpacing * 4 + 32 + 24
    }

    private func syncGhost(_ ghost: LiquidGlassView?, frame: NSRect, hidden: Bool, transition: ContainedViewLayoutTransition) {
        guard let ghost = ghost else { return }
        ghost.isHidden = hidden
        glassWrapper.setGhostFrame(ghost, frame: frame, transition: transition)
    }

    func inlineHeaderFrame(for width: CGFloat) -> NSRect? {
        let inDoneMode = menuMode == .done
        let count = (callHidden || inDoneMode ? 0 : 1)
            + (searchHidden || inDoneMode ? 0 : 1)
            + (chatInteraction.mode == .preview ? 0 : 1)
        let clusterWidth = RightActionsCluster.desiredWidth(buttonSize: Self.bubbleHeight, count: count)
        let left = leftSideInset + (hasBackButton ? Self.bubbleHeight + Self.interBubbleSpacing : 0)
        let right = width - Self.sideInset - clusterWidth - (count > 0 ? Self.interBubbleSpacing : 0)
        let titleWidth = (titleView.textLayout?.attributedString.size().width ?? 0)
            + (statusControl?.frame.width ?? 0) + (leftStatusControl?.frame.width ?? 0)
            + (titleImageView?.image?.backingSize.width ?? 0)
        let statusWidth = statusView.textLayout?.attributedString.size().width ?? 0
        let preferredWidth = max(titleWidth, statusWidth) + max(32, avatarControl.frame.width) + 30
        let available = NSMakeRect(left, Self.topInset, max(0, right - left), Self.bubbleHeight)
        return ChatHeaderInlineLayout.accessoryFrame(in: available, preferredTitleWidth: preferredWidth, spacing: Self.interBubbleSpacing)
    }


    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let bubbleHeight = Self.bubbleHeight
        let bubbleY = Self.topInset
        let spacing = Self.interBubbleSpacing
        let inlineFrame = inlineHeaderFrame(for: size.width)
        if previousInlineHeaderFrame != inlineFrame {
            previousInlineHeaderFrame = inlineFrame
            superview?.needsLayout = true
        }

        let totalHeight = size.height + extendedContentHeight
        let wrapperFrame = NSRect(x: 0, y: 0, width: size.width, height: totalHeight)
        transition.updateFrame(view: glassWrapper, frame: wrapperFrame)
        glassWrapper.updateLayout(size: wrapperFrame.size, transition: transition)

        var leftX: CGFloat = leftSideInset
        if hasBackButton {
            let backFrame = NSRect(x: leftX, y: bubbleY, width: bubbleHeight, height: bubbleHeight)
            transition.updateFrame(view: backButton, frame: backFrame)
            syncGhost(backGhost, frame: backFrame, hidden: false, transition: transition)
            leftX += bubbleHeight + spacing
            leftEdgeHandle.isHidden = true
        } else {
            backGhost.isHidden = true
            let handleFrame = NSRect(x: 0, y: bubbleY, width: leftSideInset, height: bubbleHeight)
            transition.updateFrame(view: leftEdgeHandle, frame: handleFrame)
            leftEdgeHandle.isHidden = false
        }

        let inDoneMode = (menuMode == .done)
        callButton.isHidden = callHidden || inDoneMode
        searchButton.isHidden = searchHidden || inDoneMode
        menuButton.isHidden = chatInteraction.mode == .preview

        let clusterCount = rightCluster.visibleButtonCount
        let clusterWidth = rightCluster.desiredWidth(buttonSize: bubbleHeight)
        let clusterX = size.width - Self.sideInset - clusterWidth
        let clusterFrame = NSRect(x: clusterX, y: bubbleY, width: clusterWidth, height: bubbleHeight)
        transition.updateFrame(view: rightCluster, frame: clusterFrame)
        rightCluster.updateLayout(size: clusterFrame.size, transition: transition)
        rightCluster.isHidden = clusterCount == 0
        syncGhost(rightGhost, frame: clusterFrame, hidden: clusterCount == 0, transition: transition)
        let rightX: CGFloat = clusterX - (clusterCount > 0 ? spacing : 0)

        let centerAvailableMinX = leftX
        let centerAvailableMaxX = rightX
        let centerWidth = max(0, centerAvailableMaxX - centerAvailableMinX)

        let avatarSize: CGFloat = max(32, avatarControl.frame.width)
        let horizontalContentPadding: CGFloat = 4
        let avatarTextSpacing: CGFloat = 8
        let textRightPadding: CGFloat = 14

        var centerRect = NSRect(x: centerAvailableMinX, y: bubbleY, width: centerWidth, height: bubbleHeight)
        if displaysInlineHeader, let inlineFrame {
            centerRect.size.width = inlineFrame.minX - spacing - centerRect.minX
        }
        transition.updateFrame(view: centerBubble, frame: centerRect)
        syncGhost(centerGhost, frame: centerRect, hidden: centerWidth <= 0, transition: transition)
        if inputActivities != nil, chatInteraction.mode != .scheduled, chatInteraction.mode != .pinned,
           inputActivitiesWidth != max(centerRect.width - 60, 160) {
            updateInputActivities()
        }

        let centerContentBounds = NSRect(origin: .zero, size: centerRect.size)

        let avatarOriginX = horizontalContentPadding
        let avatarOriginY = (centerContentBounds.height - avatarSize) / 2
        let avatarRect = NSRect(x: avatarOriginX, y: avatarOriginY, width: avatarSize, height: avatarSize)
        transition.updateFrame(view: avatarControl, frame: avatarRect)
        centerBubble.avatarRect = avatarRect

        if let liveStreamView {
            liveStreamView.setFrameOrigin(NSMakePoint(avatarRect.minX + (avatarSize - liveStreamView.frame.width) / 2, avatarRect.maxY - liveStreamView.frame.height))
        }

        let statusControlWidth = (statusControl?.frame.width ?? 0) + (statusControl != nil ? 4 : 0)

        if let layer = inlineTopicPhotoLayer {
            let size: NSSize = NSMakeSize(30, 30)
            layer.frame = NSRect(x: avatarOriginX + 1, y: floorToScreenPixels(backingScaleFactor, (centerContentBounds.height - size.height) / 2), width: size.width, height: size.height)
        }

        let baseTextOriginX = avatarOriginX + avatarSize + avatarTextSpacing
        var titleOriginX = baseTextOriginX

        let leftStatusInset: CGFloat = (leftStatusControl?.frame.width ?? 0) + (leftStatusControl != nil ? 4 : 0)
        let titleImageInset: CGFloat = titleImageView != nil ? ((titleImageView?.image?.backingSize.width ?? 0) + 4) : 0
        titleOriginX += leftStatusInset + titleImageInset

        let titleWidthAvailable = max(0, centerContentBounds.width - titleOriginX - textRightPadding - statusControlWidth)
        let statusWidthAvailable = max(0, centerContentBounds.width - baseTextOriginX - textRightPadding)

        if let layout = titleView.textLayout, titleWidthAvailable == 0 || layout.constrainedWidth != titleWidthAvailable {
            layout.measure(width: titleWidthAvailable)
            titleView.update(layout)
        }
        if !statusView.isHidden, let layout = statusView.textLayout, statusWidthAvailable == 0 || layout.constrainedWidth != statusWidthAvailable {
            layout.measure(width: statusWidthAvailable)
            statusView.update(layout)
        }

        let titleSize = titleView.frame.size
        let statusVisible = !showActivities && !statusView.isHidden
        let activitiesVisible = showActivities && (activities.view != nil)
        let secondLineSize: NSSize
        if activitiesVisible, let view = activities.view {
            secondLineSize = view.frame.size
        } else if statusVisible {
            secondLineSize = statusView.frame.size
        } else {
            secondLineSize = .zero
        }
        let textBlockHeight: CGFloat
        if secondLineSize.height == 0 {
            textBlockHeight = titleSize.height
        } else {
            textBlockHeight = titleSize.height + 14
        }
        let textOriginY = floorToScreenPixels(backingScaleFactor, (centerContentBounds.height - textBlockHeight) / 2)

        let titleRect = NSRect(x: titleOriginX, y: textOriginY, width: titleSize.width, height: titleSize.height)
        transition.updateFrame(view: titleView, frame: titleRect)

        if let leftStatusControl {
            let y = floorToScreenPixels(backingScaleFactor, titleRect.minY + (titleSize.height - leftStatusControl.frame.height) / 2)
            transition.updateFrame(view: leftStatusControl, frame: CGRect(x: baseTextOriginX, y: y, width: leftStatusControl.frame.width, height: leftStatusControl.frame.height))
        }

        if let titleImageView, let image = titleImageView.image {
            let imgSize = image.backingSize
            let y = floorToScreenPixels(backingScaleFactor, titleRect.minY + (titleSize.height - imgSize.height) / 2 + 1)
            transition.updateFrame(view: titleImageView, frame: NSRect(x: titleRect.minX - imgSize.width - 4, y: y, width: imgSize.width, height: imgSize.height))
        }

        if let statusControl {
            transition.updateFrame(view: statusControl, frame: CGRect(x: titleRect.maxX + 2, y: titleRect.minY + 1, width: statusControl.frame.width, height: statusControl.frame.height))
        }

        if statusVisible {
            transition.updateFrame(view: statusView, frame: NSRect(x: baseTextOriginX, y: textOriginY + titleSize.height + 1, width: secondLineSize.width, height: secondLineSize.height))
        }
        if let view = activities.view {
            if activitiesVisible {
                transition.updateFrame(view: view, frame: NSRect(x: baseTextOriginX, y: textOriginY + titleSize.height - 1, width: secondLineSize.width, height: secondLineSize.height))
            }
        }
    }
}
