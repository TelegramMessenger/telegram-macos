import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore

import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel



public class MessageActionsPanelView: Control, Notifable {

    private let deleteButton: ImageButton = ImageButton()
    private let forwardButton: ImageButton = ImageButton()
    private let countTitle: TextView = TextView()
    private let countContainer: Control = Control()

    private var glassContainer: (NSView & GlassEffectContainer)?
    private var glassContent: View?
    private var deleteGhost: LiquidGlassView?
    private var countGhost: LiquidGlassView?
    private var forwardGhost: LiquidGlassView?

    /// Most-recent chat theme passed in via `updateLocalizationAndTheme`.
    /// Stored so `updateUI` — which fires on every selection change from
    /// the `Notifable` observer — can re-render against the chat palette
    /// instead of the global app `theme`. Without this, selecting messages
    /// in a chat with a custom palette would render counts/icons against
    /// the app theme colours.
    private var currentChatTheme: TelegramPresentationTheme?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.countTitle.userInteractionEnabled = false
        self.countTitle.isSelectable = false

        self.layer?.masksToBounds = false

        deleteButton.disableActions()
        forwardButton.disableActions()
        forwardButton.controlOpacityEventIgnored = true

        deleteButton.scaleOnClick = true
        forwardButton.scaleOnClick = true
        deleteButton.autohighlight = false
        forwardButton.autohighlight = false

        countContainer.layer?.cornerRadius = 20
        countContainer.layer?.masksToBounds = true
        countContainer.isAccessibilityDecorative = true
        deleteButton.setAccessibilityLabel(strings().voiceOverMessageContextDelete)
        forwardButton.setAccessibilityLabel(strings().voiceOverMessageContextForward)

        let container = makeGlassEffectContainer(frame: bounds, flipped: true, spacing: 0)
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        let content = GlassContentView(frame: bounds)
        content.backgroundColor = .clear
        content.layer?.masksToBounds = false
        container.contentView = content
        self.glassContainer = container
        self.glassContent = content
        addSubview(container)

        let deleteGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        let countGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        let forwardGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        self.deleteGhost = deleteGhost
        self.countGhost = countGhost
        self.forwardGhost = forwardGhost
        content.addSubview(deleteGhost)
        content.addSubview(countGhost)
        content.addSubview(forwardGhost)

        countContainer.interactiveGlassView = countContainer
        countContainer.additionalGlassEffectView = countGhost

        countContainer.addSubview(countTitle)

        addSubview(deleteButton)
        addSubview(forwardButton)
        addSubview(countContainer)

        updateLocalizationAndTheme(theme: theme)
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let edge: CGFloat = 12
        let gap: CGFloat = 10
        let contentHeight = size.height - ChatInputView.inputBottomInset

        let deleteFrame = NSMakeRect(edge, 0, deleteButton.frame.width, deleteButton.frame.height)
        let forwardFrame = NSMakeRect(size.width - edge - forwardButton.frame.width, 0, forwardButton.frame.width, forwardButton.frame.height)

        transition.updateFrame(view: deleteButton, frame: deleteFrame)
        transition.updateFrame(view: forwardButton, frame: forwardFrame)

        let maxTextWidth = forwardButton.frame.minX - gap - deleteButton.frame.maxX - gap - 20
        countTitle.resize(maxTextWidth)
        let containerWidth = countTitle.frame.width + 20
        let containerX = (size.width - containerWidth) / 2
        let containerFrame = NSMakeRect(containerX, 0, containerWidth, contentHeight)

        transition.updateFrame(view: countContainer, frame: containerFrame)
        countTitle.center()

        if let container = glassContainer, let content = glassContent {
            transition.updateFrame(view: container, frame: bounds)
            transition.updateFrame(view: content, frame: bounds)
            syncMessageActionsGhost(deleteGhost, frame: deleteFrame, transition: transition)
            syncMessageActionsGhost(countGhost, frame: containerFrame, transition: transition)
            syncMessageActionsGhost(forwardGhost, frame: forwardFrame, transition: transition)
        }
    }

    private func syncMessageActionsGhost(_ ghost: LiquidGlassView?, frame: NSRect, transition: ContainedViewLayoutTransition) {
        guard let ghost = ghost else { return }
        transition.updateFrame(view: ghost, frame: frame)
        ghost.updateLayout(size: frame.size, transition: transition)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var chatInteraction:ChatInteraction?
    private var forwardingRestrictionText: String?
    
    private static func restrictionText(for presentation: ChatPresentationInterfaceState) -> String {
        if presentation.peer is TelegramGroup {
            return "Forwards from this group are restricted" //TODOLANG Conversation.CopyProtectionForwardingDisabledGroup
        }
        if let peer = presentation.peer as? TelegramChannel {
            if case .broadcast = peer.info {
                return "Forwards from this channel are restricted" //TODOLANG Conversation.CopyProtectionForwardingDisabledChannel
            }
            return "Forwards from this group are restricted" //TODOLANG Conversation.CopyProtectionForwardingDisabledGroup
        }
        if let peer = presentation.peer as? TelegramUser, peer.botInfo != nil {
            return "Forwards from this bot are restricted" //TODOLANG Conversation.CopyProtectionForwardingDisabledBot
        }
        return "Forwarding is restricted" //TODOLANG Conversation.CopyProtectionForwardingDisabledSecret
    }

    private func updateUI(_ canDelete:Bool , _ canForward:Bool, _ count:Int, forwardingRestrictionText: String? = nil) -> Void {
        deleteButton.isEnabled = canDelete
        forwardButton.isEnabled = canForward || (count > 0 && forwardingRestrictionText != nil)
        self.forwardingRestrictionText = forwardingRestrictionText

        deleteButton.alphaValue = canDelete ? 1.0 : 0.3
        deleteGhost?.alphaValue = canDelete ? 1.0 : 0.3
        forwardButton.alphaValue = canForward ? 1.0 : 0.3
        forwardGhost?.alphaValue = canForward ? 1.0 : 0.3

        // Resolve against the chat theme (stored via `updateLocalizationAndTheme`),
        // not the global app `theme` — `notify` fires this on every selection
        // change and previously clobbered any chat-theme styling already
        // applied.
        let activeTheme = currentChatTheme ?? theme

        let text = count == 0 ? strings().messageActionsPanelEmptySelected : strings().messageActionsPanelSelectedCountOther(count)
        let color = (!canForward && !canDelete) || count == 0 ? activeTheme.colors.grayText : activeTheme.colors.text
        let layout = TextViewLayout(.initialize(string: text, color: color, font: .medium(.title)), maximumNumberOfLines: 1, truncationType: .middle)

        updateLocalizationAndTheme(theme: activeTheme)

        countTitle.update(layout)
        needsLayout = true
    }

    public func notify(with value: Any, oldValue: Any, animated:Bool) {
        if let value = value as? ChatPresentationInterfaceState, let selectionState = value.selectionState {
            if value.reportMode != nil {
                updateUI(true, selectionState.selectedIds.count > 0, selectionState.selectedIds.count)
            } else {
                updateUI(value.canInvokeBasicActions.delete, value.canInvokeBasicActions.forward, selectionState.selectedIds.count, forwardingRestrictionText: value.canInvokeBasicActions.forward ? nil : MessageActionsPanelView.restrictionText(for: value))
            }
        }
    }

    deinit {
    }

    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? MessageActionsPanelView {
            return self == other
        }
        return false
    }


    public func prepare(with chatInteraction:ChatInteraction) -> Void {
        if let chatInteraction = self.chatInteraction {
            chatInteraction.remove(observer: self)
        }
        self.chatInteraction = chatInteraction
        self.chatInteraction?.add(observer: self)

        forwardButton.set(handler: { [weak chatInteraction, weak self] _ in
            guard let chatInteraction else {
                return
            }
            if !chatInteraction.presentation.canInvokeBasicActions.forward, let text = self?.forwardingRestrictionText {
                chatInteraction.showAnimatedToaster(.banned, text)
            } else {
                chatInteraction.forwardSelectedMessages()
            }
        }, for: .Click)
        deleteButton.set(handler: { [weak chatInteraction, weak self] _ in
            chatInteraction?.deleteSelectedMessages(morphSource: { [weak self] in self?.deleteButton })
        }, for: .Click)

        self.notify(with: chatInteraction.presentation, oldValue: chatInteraction.presentation, animated: false)
        
    }


    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        self.currentChatTheme = theme

        deleteButton.set(image: TelegramThemeHooks.shared.image(.iconMessageActionPanelDelete).precomposed(theme.colors.text), for: .Normal)
        forwardButton.set(image: TelegramThemeHooks.shared.image(.iconMessageActionPanelForward).precomposed(theme.colors.text), for: .Normal)

        deleteButton.setGlassEffect(size: NSMakeSize(40, 40), tintColor: theme.colors.background.withAlphaComponent(0.4))
        forwardButton.setGlassEffect(size: NSMakeSize(40, 40), tintColor: theme.colors.background.withAlphaComponent(0.4))
        deleteButton.setGlassEffectHidden(true)
        forwardButton.setGlassEffectHidden(true)
        deleteButton.additionalGlassEffectView = deleteGhost
        forwardButton.additionalGlassEffectView = forwardGhost


        deleteButton.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        forwardButton.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)

        backgroundColor = .clear

        countContainer.backgroundColor = .clear

        // Forward to each ghost so its forceAppearance.didSet rebuilds the
        // inner NSGlassEffectView at the new dark/light boundary.
        deleteGhost?.updateLocalizationAndTheme(theme: theme)
        countGhost?.updateLocalizationAndTheme(theme: theme)
        forwardGhost?.updateLocalizationAndTheme(theme: theme)

        // Install the chat-theme tint on every glass surface. Without this
        // each ghost's `applyAppearance` falls back to the global
        // `presentation.colors.background`, so a chat on a custom palette
        // gets the wrong tint on its delete / count / forward pills. The
        // `deleteButton` / `forwardButton` internal glass needs the same
        // tint via `glassTintColor` since those pills are still visible on
        // the legacy (pre-glassContainer) path.
        let chatGlassTint = theme.colors.background.withAlphaComponent(0.4)
        deleteGhost?.customTint = chatGlassTint
        countGhost?.customTint = chatGlassTint
        forwardGhost?.customTint = chatGlassTint
        deleteButton.glassTintColor = chatGlassTint
        forwardButton.glassTintColor = chatGlassTint
    }

    public override func viewDidMoveToWindow() {
        if window == nil {
            self.chatInteraction?.remove(observer: self)
            self.resignFirstResponder()
        }
    }

}

extension MessageActionsPanelView: ChatInputGlassMorphing {
    func glassMorphSlots(visible: Bool) -> ChatInputGlassSlots? {
        guard let deleteGhost, let countGhost, let forwardGhost else {
            return nil
        }
        func rect(_ ghost: LiquidGlassView) -> NSRect {
            return convert(visible ? visibleFrame(ghost) : ghost.frame, from: ghost.superview)
        }
        return ChatInputGlassSlots(attach: rect(deleteGhost), text: rect(countGhost), voice: rect(forwardGhost))
    }

    func setMorphGlassHidden(_ hidden: Bool) {
        deleteGhost?.isHidden = hidden
        countGhost?.isHidden = hidden
        forwardGhost?.isHidden = hidden
    }
}
