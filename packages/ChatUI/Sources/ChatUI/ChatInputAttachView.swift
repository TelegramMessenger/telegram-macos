import Cocoa
import InputView
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Translate
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
import AlertsUI
import FilePanels
import LocalAnimations
import MessageTextUtils
import PremiumUI
import StarsUI

@available(macOS 10.15, *)
func showWalletSendMoney(chatInteraction: ChatInteraction, user: TelegramUser, flyIntoChat: Bool, morphSource: (() -> NSView?)? = nil) {
    let context = chatInteraction.context
    guard let walletContext = ChatInputUIHooks.shared.walletHooks.walletContext(context) else {
        return
    }
    var acceptedTransferAnimation = false
    let handlers = ChatWalletSendHandlers(transferAnimationWillStart: !flyIntoChat ? nil : { [weak chatInteraction] id in
        chatInteraction?.walletTransferAnimation?.prepare(id: id)
    }, transferAnimation: !flyIntoChat ? nil : { [weak chatInteraction] id, source in
        acceptedTransferAnimation = chatInteraction?.walletTransferAnimation?.receive(id: id, source: source) ?? false
        return acceptedTransferAnimation
    }, completed: { [weak chatInteraction] in
        if !acceptedTransferAnimation {
            chatInteraction?.scrollToLatest(true)
        }
    })
    showModal(with: ChatInputUIHooks.shared.walletHooks.makeWalletSendControllerObserved(context, walletContext, user, handlers), for: context.window, morphSource: morphSource)
}

public final class ChatInputAttachButton: View, MorphHoldObserving {

    /// Stacked-button heights. Collapsed = just the attach (paperclip) button; expanded adds the AI
    /// button ABOVE it (the shared glass ghost grows into a vertical pill to match — see ChatInputView).
    /// The expanded height is a fixed, capped value: the two 40pt button frames overlap slightly but
    /// their icons stay clear, keeping the pill compact rather than as tall as a 4-line input.
    public static let buttonSize: CGFloat = 40
    public static let collapsedHeight: CGFloat = buttonSize
    public static let expandedHeight: CGFloat = 74

    public let button: ImageButton = ImageButton()
    /// AI (rephrase/translate) button — present only while the input has grown to several lines.
    public private(set) var aiButton: ImageButton?
    public var isAIVisible: Bool { aiButton != nil }

    public private(set) var isMorphHeld = false
    public var onMorphHoldChange: ((Bool) -> Void)?
    public func morphHoldDidChange(_ isHeld: Bool) {
        isMorphHeld = isHeld
        onMorphHoldChange?(isHeld)
    }

    private let chatInteraction: ChatInteraction

    public init(frame frameRect: NSRect, chatInteraction: ChatInteraction) {
        self.chatInteraction = chatInteraction
        super.init(frame: frameRect)

        self.layer?.masksToBounds = false
        button.scaleOnClick = true
        button.setAccessibilityLabel(strings().voiceOverAttachMedia)
        addSubview(button)

        setupContextMenu()
        updateLocalizationAndTheme(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        layoutButtons(transition: .immediate)
    }

    /// This view is flipped (y = 0 is the TOP). The attach button pins to the BOTTOM (aligned with the
    /// send button) and the AI button sits at the TOP. In the capped 74pt pill the two 40pt frames
    /// overlap by a few points in the middle, but their icons stay clear.
    private func layoutButtons(transition: ContainedViewLayoutTransition) {
        let s = ChatInputAttachButton.buttonSize
        transition.updateFrame(view: button, frame: NSMakeRect(0, bounds.height - s, bounds.width, s))
        if let aiButton = aiButton {
            transition.updateFrame(view: aiButton, frame: NSMakeRect(0, 0, bounds.width, s))
        }
    }

    /// Shows/hides the AI button above the attach button. The caller drives this view's height
    /// (collapsed/expanded) so the shared glass ghost can animate into a vertical pill in lock-step.
    public func setAI(visible: Bool, transition: ContainedViewLayoutTransition) {
        if visible {
            if aiButton == nil {
                let ai = ImageButton()
                ai.autohighlight = false
                ai.setAccessibilityLabel(strings().voiceOverCommonTranslate)
                ai.scaleOnClick = true
                ai.set(handler: { [weak self] _ in
                    self?.runAITranslate()
                }, for: .Click)
                addSubview(ai)
                self.aiButton = ai
                if transition.isAnimated {
                    ai.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            aiButton?.set(image: theme.icons.chat_input_ai, for: .Normal)
        } else if let ai = aiButton {
            performSubviewRemoval(ai, animated: transition.isAnimated, scale: true)
            aiButton = nil
        }
        layoutButtons(transition: transition)
    }

    private func runAITranslate() {
        let chatInteraction = self.chatInteraction
        let presentation = chatInteraction.presentation
        let text = presentation.effectiveInput.inputText
        let editMessageId = presentation.interfaceState.editState?.message.id
        guard !text.isEmpty else { return }
        let context = chatInteraction.interactionContext
        let language = Translate.detectLanguage(for: text)
        let apply: (NSAttributedString, Bool) -> Void = { [weak chatInteraction] translated, send in
            guard let chatInteraction,
                  chatInteraction.presentation.state == .normal || chatInteraction.presentation.state == .editing,
                  (chatInteraction.presentation.interfaceState.editState?.loadingState ?? EditStateLoading.none) == EditStateLoading.none,
                  chatInteraction.presentation.interfaceState.editState?.message.id == editMessageId else {
                return
            }
            let inputState = ChatTextInputState(attributedText: translated, selectionRange: translated.length ..< translated.length)
            chatInteraction.update { $0.withUpdatedEffectiveInputState(inputState) }
            if send {
                chatInteraction.sendMessage(true, nil, nil)
            }
        }
        showModal(with: ChatInputUIHooks.shared.makeTranslateModalObserved(context, language, appAppearance.languageCode, text, onUse: { translated in
            apply(translated, false)
        }, onSend: { translated in
            apply(translated, true)
        }), for: context.window, morphSource: { [weak self] in self?.aiButton })
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        button.set(image: theme.icons.chat_input_attach, for: .Normal)
        button.setGlassEffect(size: NSMakeSize(40, 40))
        aiButton?.set(image: theme.icons.chat_input_ai, for: .Normal)
    }

    public func setInnerGlassHidden(_ hidden: Bool) {
        button.setGlassEffectHidden(hidden)
    }

    public func setSharedGlassGhost(_ ghost: NSView?) {
        button.additionalGlassEffectView = ghost
    }

    private func setupContextMenu() {
        let chatInteraction = self.chatInteraction
        let context = chatInteraction.interactionContext
        button.contextMenu = { [weak self] in
            guard let self = self else {
                return ContextMenu()
            }
            let chatInteraction = self.chatInteraction
            guard let peer = chatInteraction.presentation.peer else {
                return nil
            }
            var items: [ContextMenuItem] = []
            if let editState = chatInteraction.presentation.interfaceState.editState, editState.message.pendingProcessingAttribute == nil {
                if let media = editState.originalMedia, media is TelegramMediaFile || media is TelegramMediaImage {
                    if editState.message.groupingKey == nil {
                        items.append(ContextMenuItem(strings().inputAttachPopoverPhotoOrVideo, handler: { [weak self] in
                            self?.chatInteraction.updateEditingMessageMedia(nil, true)
                        }, itemImage: MenuAnimation.menu_shared_media.value))

                        items.append(ContextMenuItem(strings().inputAttachPopoverFile, handler: { [weak self] in
                            self?.chatInteraction.updateEditingMessageMedia(nil, false)
                        }, itemImage: MenuAnimation.menu_file.value))

                        if media is TelegramMediaImage {
                            items.append(ContextMenuItem(strings().editMessageEditCurrentPhoto, handler: { [weak self] in
                                self?.chatInteraction.editEditingMessagePhoto(media as! TelegramMediaImage)
                            }, itemImage: MenuAnimation.menu_edit.value))
                        }
                    } else {
                        if let _ = editState.message.anyMedia as? TelegramMediaImage {
                            items.append(ContextMenuItem(strings().inputAttachPopoverPhotoOrVideo, handler: { [weak self] in
                                self?.chatInteraction.updateEditingMessageMedia(mediaExts, true)
                            }, itemImage: MenuAnimation.menu_edit.value))
                        } else if let file = editState.message.anyMedia as? TelegramMediaFile {
                            if file.isVideoFile {
                                items.append(ContextMenuItem(strings().inputAttachPopoverPhotoOrVideo, handler: { [weak self] in
                                    self?.chatInteraction.updateEditingMessageMedia(mediaExts, true)
                                }, itemImage: MenuAnimation.menu_shared_media.value))
                            }
                            if file.isMusic {
                                items.append(ContextMenuItem(strings().inputAttachPopoverMusic, handler: { [weak self] in
                                    self?.chatInteraction.updateEditingMessageMedia(audioExts, false)
                                }, itemImage: MenuAnimation.menu_music.value))
                            } else {
                                items.append(ContextMenuItem(strings().inputAttachPopoverFile, handler: { [weak self] in
                                    self?.chatInteraction.updateEditingMessageMedia(nil, false)
                                }, itemImage: MenuAnimation.menu_file.value))
                            }
                        }
                    }
                } else if editState.message.pendingProcessingAttribute == nil {
                    if editState.message.media.isEmpty {
                        items.append(ContextMenuItem(strings().inputAttachPopoverPhotoOrVideo, handler: { [weak self] in
                            self?.chatInteraction.updateEditingMessageMedia(nil, true)
                        }, itemImage: MenuAnimation.menu_shared_media.value))

                        items.append(ContextMenuItem(strings().inputAttachPopoverFile, handler: { [weak self] in
                            self?.chatInteraction.updateEditingMessageMedia(nil, false)
                        }, itemImage: MenuAnimation.menu_file.value))
                    }
                }
            } else if chatInteraction.presentation.interfaceState.editState == nil {

                let peerId = chatInteraction.peerId

                if let slowMode = self.chatInteraction.presentation.slowMode, slowMode.hasLocked {
                    showSlowModeTimeoutTooltip(slowMode, for: self.button)
                    return ContextMenu()
                }

                if let channel = peer as? TelegramChannel {
                    if channel.hasPermission(.sendPhoto) && channel.hasPermission(.sendVideo) {
                        items.append(ContextMenuItem(strings().inputAttachPopoverPhotoOrVideo, handler: { [weak self] in
                            self?.chatInteraction.attachPhotoOrVideo(nil)
                        }, itemImage: MenuAnimation.menu_shared_media.value))
                    } else {
                        if channel.hasPermission(.sendPhoto) {
                            items.append(ContextMenuItem(strings().inputAttachPopoverPhoto, handler: { [weak self] in
                                self?.chatInteraction.attachPhotoOrVideo(.photo)
                            }, itemImage: MenuAnimation.menu_shared_media.value))
                        } else if channel.hasPermission(.sendVideo) {
                            items.append(ContextMenuItem(strings().inputAttachPopoverVideo, handler: { [weak self] in
                                self?.chatInteraction.attachPhotoOrVideo(.video)
                            }, itemImage: MenuAnimation.menu_shared_media.value))
                        }
                    }
                } else {
                    items.append(ContextMenuItem(strings().inputAttachPopoverPhotoOrVideo, handler: { [weak self] in
                        self?.chatInteraction.attachPhotoOrVideo(nil)
                    }, itemImage: MenuAnimation.menu_shared_media.value))
                }

                if let shortcuts = chatInteraction.presentation.shortcuts, let peer = chatInteraction.peer, chatInteraction.presentation.chatMode == .history {
                    if peer.isUser && !peer.isBot {
                        if !shortcuts.items.isEmpty, context.isPremium {
                            items.append(ContextMenuItem(strings().chatInputAttachQuickReply, handler: { [weak self] in
                                self?.chatInteraction.clearInput()
                                self?.chatInteraction.appendText(.initialize(string: "/"))
                            }, itemImage: MenuAnimation.menu_reply.value))
                        }
                    }
                }

                let chatMode = chatInteraction.presentation.chatMode

                let replyTo = chatInteraction.presentation.interfaceState.replyMessageId?.messageId ?? chatInteraction.chatLocation.threadMsgId

                let threadId = chatInteraction.presentation.chatLocation.threadId

                let acceptMode = chatMode == .history || (chatMode.isThreadMode || chatMode.isTopicMode)


                if let peer = chatInteraction.presentation.mainPeer {
                    if context.premiumLimits.show_premium_gift_in_attach_menu, !peer.isPremium, peer.isUser {
                        items.append(ContextMenuItem(strings().inputAttachPopoverGift, handler: { [weak self] in
                            showModal(with: GiftingController(context: context, peerId: peerId, isBirthday: false), for: context.window, morphSource: { [weak self] in self?.button })
                        }, itemImage: MenuAnimation.menu_gift.value))
                    }
                }

                if #available(macOS 10.15, *), context.appConfiguration.getBoolValue("wallet_available", orElse: false), chatMode != .scheduled, let user = peer as? TelegramUser,
                   user.canBeDirectRecipient(accountPeerId: context.peerId) {
                    items.append(ContextMenuItem(strings().chatInputAttachViewMoney, handler: { [weak self] in
                        showWalletSendMoney(chatInteraction: chatInteraction, user: user, flyIntoChat: true, morphSource: { [weak self] in self?.button })
                    }, itemImage: MenuAnimation.menu_gram.value))
                }

                if acceptMode, let peer = chatInteraction.presentation.peer {
                    for attach in chatInteraction.presentation.attachItems {

                        var value: (NSColor, ContextMenuItem)-> AppMenuItemImageDrawable
                        if let file = attach.icons[.macOSAnimated] {
                            value = MenuRemoteAnimation(context, file: file, bot: attach.peer._asPeer(), thumb: MenuAnimation.menu_webapp_placeholder).value
                        } else {
                            value = MenuAnimation.menu_folder_bot.value
                        }
                        var canAddAttach: Bool
                        if peer.isUser {
                            canAddAttach = attach.peerTypes.contains(.all) || attach.peerTypes.contains(.user)
                        } else if peer.isBot {
                            canAddAttach = attach.peerTypes.contains(.all) || attach.peerTypes.contains(.bot) || (attach.peerTypes.contains(.sameBot) && attach.peer.id == peer.id)
                        } else if peer.isGroup || peer.isSupergroup {
                            canAddAttach = attach.peerTypes.contains(.all) || attach.peerTypes.contains(.group)
                        } else if peer.isChannel, !peer.hasBannedRights(.banSendText) {
                            canAddAttach = attach.peerTypes.contains(.all) || attach.peerTypes.contains(.channel)
                        } else {
                            canAddAttach = false
                        }

                        canAddAttach = canAddAttach && attach.flags.contains(.showInAttachMenu)

                        if canAddAttach {
                            let bot = attach
                            items.append(ContextMenuItem(attach.shortName, handler: {
                                chatOpenAttachMenuBot(bot, context: context, peerId: peerId, threadId: threadId, replyId: replyTo)
                            }, itemImage: value))
                        }
                    }
                }
                if let channel = peer as? TelegramChannel {
                    if permissionText(from: channel, for: .banSendFiles) == nil {
                        items.append(ContextMenuItem(strings().inputAttachPopoverFile, handler: { [weak self] in
                            self?.chatInteraction.attachFile(false)
                        }, itemImage: MenuAnimation.menu_file.value))
                    }
                } else {
                    items.append(ContextMenuItem(strings().inputAttachPopoverFile, handler: { [weak self] in
                        self?.chatInteraction.attachFile(false)
                    }, itemImage: MenuAnimation.menu_file.value))
                }


                if let channel = peer as? TelegramChannel {
                    if channel.hasPermission(.sendPhoto) {
                        items.append(ContextMenuItem(strings().inputAttachPopoverPicture, handler: { [weak self] in
                            guard let `self` = self else { return }
                            self.chatInteraction.attachPicture()
                        }, itemImage: MenuAnimation.menu_camera.value))
                    }
                } else {
                    items.append(ContextMenuItem(strings().inputAttachPopoverPicture, handler: { [weak self] in
                        guard let `self` = self else { return }
                        self.chatInteraction.attachPicture()
                    }, itemImage: MenuAnimation.menu_camera.value))
                }


                var canAttachPoll: Bool = false
                var canAttachLocation: Bool = true
                var canAttachTodo: Bool = true

                if let peer = chatInteraction.presentation.peer, peer.isChannel {
                    canAttachTodo = false
                }

                if let peer = chatInteraction.presentation.peer, peer.isGroup || peer.isSupergroup, !peer.isMonoForum {
                    canAttachPoll = true
                }
                if let peer = chatInteraction.presentation.mainPeer, peer.isBot {
                    canAttachPoll = true
                }

                if let peer = chatInteraction.presentation.peer as? TelegramChannel {
                    if peer.hasPermission(.sendText) {
                        canAttachPoll = true
                    } else {
                        canAttachLocation = false
                    }
                }
                if canAttachPoll && permissionText(from: peer, for: .banSendPolls) != nil {
                    canAttachPoll = false
                }

                if canAttachPoll {
                    items.append(ContextMenuItem(strings().inputAttachPopoverPoll, handler: { [weak self] in
                        guard let `self` = self else { return }
                        if let permissionText = permissionText(from: peer, for: .banSendPolls) {
                            showModalText(for: context.window, text: permissionText)
                            return
                        }
                        ChatNavigationHooks.shared.showNewPoll(self.chatInteraction, .new, self.chatInteraction.interactionContext.window, { [weak self] in self?.button })
                    }, itemImage: MenuAnimation.menu_poll.value))
                }

                items.append(ContextMenuItem(strings().inputAttachAudio, handler: { [weak self] in
                    guard let `self` = self else { return }
                    if let permissionText = permissionText(from: peer, for: .banSendFiles) {
                        showModalText(for: context.window, text: permissionText)
                        return
                    }
                    self.chatInteraction.attachAudio({ [weak self] in self?.button })
                }, itemImage: MenuAnimation.menu_music.value))

                if canAttachTodo, context.isPremium {
                    let item = ContextMenuItem(strings().inputAttachPopoverChecklist, handler: { [weak self] in
                        guard let `self` = self else { return }
                        if let permissionText = permissionText(from: peer, for: .banSendPolls) {
                            showModalText(for: context.window, text: permissionText)
                            return
                        }
                        if !context.isPremium {
                            prem(with: PremiumBoardingController(context: context, source: .todo, openFeatures: true), for: context.window, morphSource: { [weak self] in self?.button })
                        } else {
                            ChatNavigationHooks.shared.showNewTodo(self.chatInteraction, .create, self.chatInteraction.interactionContext.window, { [weak self] in self?.button })
                        }
                    }, itemImage: MenuAnimation.menu_list.value, locked: !context.isPremium)
                    items.append(item)
                }

                if canAttachLocation {
                    items.append(ContextMenuItem(strings().inputAttachPopoverLocation, handler: { [weak self] in
                        if let permissionText = permissionText(from: peer, for: .banSendText) {
                            showModalText(for: context.window, text: permissionText)
                            return
                        }
                        self?.chatInteraction.attachLocation({ [weak self] in self?.button })
                    }, itemImage: MenuAnimation.menu_location.value))
                }

                if #available(macOS 12, *), chatInteraction.interactionContext.appConfiguration.isRichTextEditorEnabled {
                    items.append(ContextMenuItem(strings().richTextEditorAttachTitle, handler: { [weak self] in
                        guard let self = self else { return }
                        showRichTextEditor(chatInteraction: self.chatInteraction, morphSource: { [weak self] in self?.button })
                    }, itemImage: MenuAnimation.menu_article.value))
                }
            }


            if !items.isEmpty {
                let menu = ContextMenu(betterInside: true)
                menu.delegate = menu

                menu.onShow = { _ in
                }
                menu.onClose = {
                }
                for item in items {
                    menu.addItem(item)
                }
                return menu
            }
            return nil
        }
    }
}
