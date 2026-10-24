import Cocoa
import TGUIKit
import TelegramCore
import Translate
import SwiftSignalKit
import InputView
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

public final class StarsSendActionView : Control {
    private static let horizontalInset: CGFloat = 8
    private static let contentSpacing: CGFloat = 4

    public let text: TextView = TextView()
    public let image: ImageView = ImageView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(text)
        addSubview(image)

        text.userInteractionEnabled = false
        text.isSelectable = false

        image.isEventLess = true
        image.isAccessibilityDecorative = true

    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(price: Int64, context: any AccountContextProtocol, animated: Bool) {
        self.backgroundColor = theme.colors.accent

        self.scaleOnClick = true

        let layout = TextViewLayout(.initialize(string: price.prettyNumber, color: theme.colors.underSelectedColor, font: .medium(.text)))
        layout.measure(width: .greatestFiniteMagnitude)

        text.update(layout)

        image.image = theme.icons.chat_input_star
        image.sizeToFit()


        let contentWidth = image.frame.width + Self.contentSpacing + text.frame.width
        setFrameSize(NSMakeSize(max(ChatInputSendButton.fieldSize.width, contentWidth + Self.horizontalInset * 2), ChatInputSendButton.fieldSize.height))

        layer?.cornerRadius = frame.height / 2
    }

    public override func layout() {
        super.layout()
        let contentWidth = image.frame.width + Self.contentSpacing + text.frame.width
        image.centerY(x: floorToScreenPixels(backingScaleFactor, (frame.width - contentWidth) / 2))
        text.centerY(x: image.frame.maxX + Self.contentSpacing)
    }
}

public class ChatInputActionsView: View, Notifable {

    public let chatInteraction:ChatInteraction
    private let muteChannelMessages:ImageButton = ChatAccessibleImageButton()
    public let entertaiments:ImageButton = ChatAccessibleImageButton()
    private let keyboard:ImageButton = ImageButton()
    private let gift:ImageButton = ImageButton()
    private let suggestPost:ImageButton = ImageButton()

    public var scheduled:ImageButton?
    private var secretTimer:ImageButton?

    public init(frame frameRect: NSRect, chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction
        super.init(frame: frameRect)

        keyboard.autohighlight = false

        (muteChannelMessages as? ChatAccessibleImageButton)?.accessibilityLabelProvider = { [weak self] in
            guard let self else { return nil }
            return FastSettings.isChannelMessagesMuted(self.chatInteraction.peerId) ? strings().voiceOverSilentPostOn : strings().voiceOverSilentPostOff
        }
        (entertaiments as? ChatAccessibleImageButton)?.accessibilityLabelProvider = { [weak self] in
            guard let self else { return nil }
            return self.chatInteraction.presentation.isEmojiSection || self.chatInteraction.presentation.state == .editing ? strings().voiceOverCommonEmoji : strings().voiceOverStickers
        }
        keyboard.setAccessibilityLabel(strings().voiceOverBotKeyboard)
        gift.setAccessibilityLabel(strings().voiceOverCommonGift)
        suggestPost.setAccessibilityLabel(strings().voiceOverSuggestPost)

        isEventLess = true
        addSubview(entertaiments)
        addSubview(keyboard)
        addSubview(gift)

        muteChannelMessages.isHidden = true
        suggestPost.isHidden = true

        muteChannelMessages.autohighlight = false
        gift.autohighlight = false
        suggestPost.autohighlight = false
        muteChannelMessages.scaleOnClick = true
        gift.scaleOnClick = true
        suggestPost.scaleOnClick = true

        muteChannelMessages.set(handler: { [weak self] control in
            if let chatInteraction = self?.chatInteraction {
                FastSettings.toggleChannelMessagesMuted(chatInteraction.peerId)
                let isMuted = FastSettings.isChannelMessagesMuted(chatInteraction.peerId)
                self?.muteChannelMessages.set(image: !isMuted ? theme.icons.inputChannelMute : theme.icons.inputChannelUnmute, for: .Normal)
                _ = self?.muteChannelMessages.sizeToFit()
                self?.needsLayout = true
                (self?.superview?.superview as? ChatInputView)?.updatePlaceholder()
                tooltip(for: control, text: isMuted ? strings().messagesSilentTooltipSilent : strings().messagesSilentTooltip)
            }
        }, for: .Click)

        keyboard.set(handler: { [weak self] _ in
            self?.toggleKeyboard()
        }, for: .Up)

        gift.set(handler: { [weak self] _ in
            self?.chatInteraction.sendGift({ [weak self] in self?.gift })
        }, for: .Up)

        suggestPost.set(handler: { [weak self] _ in
            self?.chatInteraction.suggestPost()
        }, for: .Up)

        entertaiments.highlightHovered = true
        entertaiments.autohighlight = true
        addHoverObserver()
        addClickObserver()
        entertaiments.canHighlight = false

        updateLocalizationAndTheme(theme: theme)
        
        
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        for button in [keyboard, muteChannelMessages, gift, suggestPost] where button.superview == nil {
            button.updateLocalizationAndTheme(theme: theme)
        }
        let theme = (theme as! TelegramPresentationTheme)

        let muted = FastSettings.isChannelMessagesMuted(chatInteraction.peerId)
        muteChannelMessages.set(image: !muted ? theme.icons.inputChannelMute : theme.icons.inputChannelUnmute, for: .Normal)
        _ = muteChannelMessages.sizeToFit()

        updateEntertainmentIcon()

        keyboard.set(image: theme.icons.chatActiveReplyMarkup, for: .Normal)
        _ = keyboard.sizeToFit()

        gift.set(image: theme.icons.chat_input_send_gift, for: .Normal)
        _ = gift.sizeToFit()

        suggestPost.set(image: theme.icons.chat_input_suggest_post, for: .Normal)
        _ = suggestPost.sizeToFit()

        if let timeout = chatInteraction.presentation.messageSecretTimeout?.timeout?.effectiveValue {
            secretTimer?.set(image: theme.chat.messageSecretTimer(shortTimeIntervalString(value: timeout)), for: .Normal)
        } else {
            secretTimer?.set(image: theme.icons.chatSecretTimer, for: .Normal)
        }

        scheduled?.set(image: theme.icons.chatInputScheduled, for: .Normal)
    }

    private func updateEntertainmentIcon() {
        entertaiments.set(image: chatInteraction.presentation.isEmojiSection || chatInteraction.presentation.state == .editing ? theme.icons.chatEntertainment : theme.icons.chatEntertainmentSticker, for: .Normal)
        entertaiments.setFrameSize(40, 40)
    }

    public var entertaimentsPopover: ViewController {
        return ChatInputUIHooks.shared.makeEntertainmentsPopover(chatInteraction)
    }

    private func addHoverObserver() {
        entertaiments.set(handler: { [weak self] _ in
            guard let self, !ChatInputUIHooks.shared.isEntertainmentSidebarVisible(self.window) else { return }
            self.showEntertainment()
        }, for: .LongOver)
    }

    private func showEntertainment() {
        let controller = entertaimentsPopover
        let rect = NSMakeRect(0, 0, 350, min(max(chatInteraction.interactionContext.window.frame.height - 250, 300), 550))
        controller._frameRect = rect
        controller.view.frame = rect
        showPopover(for: entertaiments, with: controller, edge: .maxX, inset:NSMakePoint(frame.width - entertaiments.frame.maxX + 38, 10), delayBeforeShown: 0.0)
    }

    private func addClickObserver() {
        entertaiments.set(handler: { [weak self] _ in
            guard let self else { return }
            if ChatInputUIHooks.shared.isEntertainmentSidebarAvailable(self.window) {
                self.entertaiments.popover?.animates = false
                self.entertaiments.popover?.hide()
                self.chatInteraction.toggleSidebar()
            } else {
                self.showEntertainment()
            }
        }, for: .Click)
    }

    public func toggleKeyboard() {
        let keyboardId = chatInteraction.presentation.keyboardButtonsMessage?.id
        chatInteraction.update({$0.updatedInterfaceState({$0.withUpdatedMessageActionsState({ actions in
            let nid = actions.closedButtonKeyboardMessageId != nil ? nil : keyboardId
            return actions.withUpdatedClosedButtonKeyboardMessageId(nid)
        })})})
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? ChatInputActionsView {
            return self == other
        }
        return false
    }

    deinit {

    }

    public func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
            if value.interfaceState != oldValue.interfaceState || !animated || value.inputQueryResult != oldValue.inputQueryResult || value.inputContext != oldValue.inputContext || value.sidebarEnabled != oldValue.sidebarEnabled || value.sidebarShown != oldValue.sidebarShown || value.layout != oldValue.layout || value.isKeyboardActive != oldValue.isKeyboardActive || value.isKeyboardShown != oldValue.isKeyboardShown || value.slowMode != oldValue.slowMode || value.hasScheduled != oldValue.hasScheduled || value.messageSecretTimeout != oldValue.messageSecretTimeout || value.boostNeed != oldValue.boostNeed || value.restrictedByBoosts != oldValue.restrictedByBoosts || value.interfaceState.messageEffect != oldValue.interfaceState.messageEffect || value.sendPaidMessageStars != oldValue.sendPaidMessageStars || value.hasGift != oldValue.hasGift || value.allowPostSuggestion != oldValue.allowPostSuggestion || value.interfaceState.suggestPost != oldValue.interfaceState.suggestPost {

                if chatInteraction.hasSetDestructiveTimer, value.interfaceState.messageEffect == nil {
                    if secretTimer == nil {
                        let timer = ChatAccessibleImageButton()
                        timer.accessibilityLabelProvider = { [weak self] in
                            if let timeout = self?.chatInteraction.presentation.messageSecretTimeout?.timeout?.effectiveValue {
                                return strings().voiceOverSelfDestructTimerOn(shortTimeIntervalString(value: timeout))
                            }
                            return strings().voiceOverSelfDestructTimerOff
                        }
                        secretTimer = timer
                        secretTimer?.set(image: theme.icons.chatSecretTimer, for: .Normal)
                        _ = secretTimer?.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
                        addSubview(secretTimer!)
                    }
                    if let peer = self.chatInteraction.peer {
                        if peer.isSecretChat {
                            secretTimer?.contextMenu = { [weak self] in
                                let menu = ContextMenu()
                                if let items = self?.secretTimerItems() {
                                    for item in items {
                                        menu.addItem(item)
                                    }
                                }
                                return menu
                            }
                        } else {
                            secretTimer?.setSingle(handler: { [weak self] control in
                                self?.chatInteraction.showDeleterSetup(control)
                            }, for: .Click)
                        }
                    }
                } else if let view = secretTimer {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    secretTimer = nil
                }

                if let timeout = value.messageSecretTimeout?.timeout?.effectiveValue {
                    secretTimer?.set(image: theme.chat.messageSecretTimer(shortTimeIntervalString(value: timeout)), for: .Normal)
                } else {
                    secretTimer?.set(image: theme.icons.chatSecretTimer, for: .Normal)
                }

                if let peer = value.peer {
                    setExtraButton(muteChannelMessages, hidden: !peer.isChannel || !peer.canSendMessage(value.chatMode.isThreadMode) || !value.effectiveInput.inputText.isEmpty || value.interfaceState.editState != nil, animated: animated)
                }

                entertaiments.apply(state: .Normal)
                entertaiments.isSelected = ChatInputUIHooks.shared.isEntertainmentSidebarVisible(self.window)

                setExtraButton(keyboard, hidden: !value.isKeyboardActive, animated: animated)
                let inputIsEmpty = value.effectiveInput.inputText.isEmpty
                setExtraButton(gift, hidden: !value.hasGift || !inputIsEmpty, animated: animated)
                setExtraButton(suggestPost, hidden: !value.allowPostSuggestion || value.interfaceState.suggestPost != nil, animated: animated)

                if let keyboardMessage = value.keyboardButtonsMessage {
                    if let closedId = value.interfaceState.messageActionsState.closedButtonKeyboardMessageId, closedId == keyboardMessage.id {
                        self.keyboard.set(image: theme.icons.chatDisabledReplyMarkup, for: .Normal)
                    } else {
                        self.keyboard.set(image: theme.icons.chatActiveReplyMarkup, for: .Normal)
                    }
                }

                if value.hasScheduled && value.effectiveInput.inputText.isEmpty && value.interfaceState.editState == nil {
                    if scheduled == nil {
                        scheduled = ImageButton()
                        scheduled?.setAccessibilityLabel(strings().voiceOverScheduledMessages)
                        scheduled!.set(image: theme.icons.chatInputScheduled, for: .Normal)
                        _ = scheduled!.sizeToFit()
                        addSubview(scheduled!)
                    }
                    scheduled?.removeAllHandlers()
                    scheduled?.set(handler: { [weak self] _ in
                        self?.chatInteraction.openScheduledMessages()
                    }, for: .Click)
                } else if let view = scheduled {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    scheduled = nil
                }
                updateEntertainmentIcon()

                updateLayout(size: frame.size, transition: .immediate)

            } else if value.isEmojiSection != oldValue.isEmojiSection {
                updateEntertainmentIcon()
                updateLayout(size: frame.size, transition: .immediate)
            }
        }
    }

    private static let extraButtonSize: CGFloat = 40

    private func setExtraButton(_ button: ImageButton, hidden: Bool, animated: Bool) {
        guard button.controlIsHidden != hidden else {
            return
        }
        if button.superview == nil {
            addSubview(button)
        }
        let animated = animated && window != nil
        if animated {
            let scale = button.isHidden ? 0.2 : (button.layer?.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1)
            button.layer?.animateScaleSpring(from: scale, to: hidden ? 0.2 : 1, duration: 0.3, bounce: false)
        }
        if button.isHidden {
            button.layer?.opacity = 0
            button.isHidden = false
        }
        button.change(opacity: hidden ? 0 : 1, animated: animated, completion: { [weak button] _ in
            if button?.layer?.opacity == 0 {
                button?.isHidden = true
            }
        })
    }

    private var extraButtons: [ImageButton] {
        return [keyboard, muteChannelMessages, gift, suggestPost, scheduled, secretTimer].compactMap { $0 }
    }

    public var visibleWidth: CGFloat {
        let shown = extraButtons.reduce(0) { $1.controlIsHidden ? $0 : $0 + 1 }
        return entertaiments.frame.width + CGFloat(shown) * ChatInputActionsView.extraButtonSize
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let bottomY = size.height - entertaiments.frame.height
        var x = size.width - entertaiments.frame.width

        transition.updateFrame(view: entertaiments, frame: NSMakeRect(x, bottomY, entertaiments.frame.width, entertaiments.frame.height))

        let centerY = { (view: NSView) -> CGFloat in
            bottomY + (self.entertaiments.frame.height - view.frame.height) / 2
        }

        let buttonSize = ChatInputActionsView.extraButtonSize

        for button in extraButtons {
            transition.updateFrame(view: button, frame: NSMakeRect(x - buttonSize, centerY(button), buttonSize, button.frame.height))
            if !button.controlIsHidden {
                x -= buttonSize
            }
        }
    }

    public func secretTimerItems() -> [ContextMenuItem] {
        var items:[ContextMenuItem] = []
        if chatInteraction.hasSetDestructiveTimer {
            if chatInteraction.presentation.messageSecretTimeout != nil {
                items.append(ContextMenuItem(strings().secretTimerOff, handler: { [weak self] in
                    self?.chatInteraction.setChatMessageAutoremoveTimeout(nil)
                }))
            }
        }
        if chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat {
            for i in 0 ..< 30 {
                items.append(ContextMenuItem(strings().timerSecondsOther(i + 1), handler: { [weak self] in
                    self?.chatInteraction.setChatMessageAutoremoveTimeout(Int32(i + 1))
                }))
            }
            for i in [1, 2, 3, 4, 5, 10, 15, 30] {
                items.append(ContextMenuItem(strings().timerMinutesOther(i), handler: { [weak self] in
                    self?.chatInteraction.setChatMessageAutoremoveTimeout(Int32(i) * 60)
                }))
            }
            for i in [1, 2, 3, 5, 8, 12, 24] {
                items.append(ContextMenuItem(strings().timerHoursOther(i), handler: { [weak self] in
                    self?.chatInteraction.setChatMessageAutoremoveTimeout(Int32(i) * 60 * 60)
                }))
            }
            for i in [1, 2, 3, 4, 5, 6] {
                items.append(ContextMenuItem(strings().timerDaysOther(i), handler: { [weak self] in
                    self?.chatInteraction.setChatMessageAutoremoveTimeout(Int32(i) * 60 * 60 * 24)
                }))
            }
            items.append(ContextMenuItem(strings().timerWeeksOther(1), handler: { [weak self] in
                self?.chatInteraction.setChatMessageAutoremoveTimeout(Int32(1) * 60 * 60 * 24 * 7)
            }))
        }
        return items
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}
