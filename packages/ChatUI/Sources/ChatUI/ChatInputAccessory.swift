import Cocoa
import Postbox
import TelegramCore

import TGUIKit
import SwiftSignalKit
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
import LocalAnimations
import PremiumUI


public class ChatInputAccessory: View {


    public let nodeReady = Promise<Bool>()

    public var chatInteraction:ChatInteraction

    public private(set) var displayNode:ChatAccessoryModel?
    private var panelStack = ChatInputAccessoryPanelStack<ChatInputAccessoryPanelKey>()

    private let dismiss:ImageButton = ImageButton()
    private var progress: Control?
    public let container:ChatAccessoryView = ChatAccessoryView()

    private let disposable = MetaDisposable()

    public var dismissForward:(()->Void)!
    public var dismissReply:(()->Void)!
    public var dismissEdit:(()->Void)!
    public var dismissUrlPreview:(()->Void)!
    public var dismissSuggestPost:(()->Void)!

    public init(chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction
        super.init(frame: .zero)
        self.addSubview(container)
        self.addSubview(dismiss)

        self.backgroundColor = .clear
        container.backgroundColor = .clear

        dismissForward = { [weak self] in
            self?.chatInteraction.update({$0.updatedInterfaceState({$0.withoutForwardMessages()})})
        }
        dismissReply = { [weak self] in
            self?.chatInteraction.update({$0.updatedInterfaceState({$0.withUpdatedReplyMessageId(nil).withUpdatedDismissedForceReplyId($0.replyMessageId?.messageId)})})
        }
        dismissEdit = { [weak self] in
            self?.chatInteraction.cancelEditing(userInitiated: true)
        }
        dismissUrlPreview = { [weak self] in
            self?.chatInteraction.update({ state -> ChatPresentationInterfaceState in
                return state.updatedInterfaceState({$0.withUpdatedComposeDisableUrlPreview(state.urlPreview?.0)})
            })
        }
        dismissSuggestPost = { [weak self] in
            self?.chatInteraction.update({ state -> ChatPresentationInterfaceState in
                return state.updatedInterfaceState({$0.withUpdatedSuggestPost(nil).withoutEditMessage()})
            })
        }

        self.dismiss.set(image: theme.icons.chat_header_dismiss, for: .Normal)
        _ = dismiss.sizeToFit()
        dismiss.setAccessibilityLabel(strings().voiceOverDiscardPreparedContent)


    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }




    //edit
    //webpage
    //forward
    //reply

    public func update(with state:ChatPresentationInterfaceState, context: any AccountContextProtocol, animated:Bool) -> Void {

        dismiss.isHidden = false
        progress?.isHidden = true

        var availableKeys: [ChatInputAccessoryPanelKey] = []
        if state.interfaceState.suggestPost != nil {
            availableKeys.append(.suggestPost)
        } else {
            if let preview = state.urlPreview, state.interfaceState.composeDisableUrlPreview != preview.0,
               let peer = state.peer, !peer.webUrlRestricted {
                availableKeys.append(.urlPreview(preview.0, state.interfaceState.editState?.message.id))
            }
            if let edit = state.interfaceState.editState {
                availableKeys.append(.edit(edit.message.id))
            }
            if !state.interfaceState.forwardMessages.isEmpty && !state.interfaceState.forwardMessageIds.isEmpty {
                availableKeys.append(.forward(state.interfaceState.forwardMessageIds))
            }
            if let reply = state.interfaceState.replyMessageId {
                availableKeys.append(.reply(reply.messageId))
            }
        }
        let slotVisible: Bool
        switch state.state {
        case .normal, .editing, .recording: slotVisible = true
        default: slotVisible = false
        }
        let selectedPanel = panelStack.update(availableKeys: slotVisible ? availableKeys : nil)
        displayNode = nil
        dismiss.removeAllHandlers()
        container.removeAllHandlers()
        container.removeAllStateHandlers()


        if selectedPanel?.kind == .suggestPost, let data = state.interfaceState.suggestPost {
            displayNode = ChatInputUIHooks.shared.makeSuggestPostPanelModel(data, context)
            dismiss.set(handler: { [weak self ] _ in
                self?.dismissSuggestPost()
            }, for: .Click)

            container.set(handler: { [weak self] _ in
                self?.chatInteraction.editPostSuggestion(data)
             }, for: .Click)

            container.contextMenu = {
                return nil
            }


        } else if selectedPanel?.kind == .urlPreview, let urlPreview = state.urlPreview {
            displayNode = ChatInputUIHooks.shared.makeUrlPreviewModel(context, urlPreview.1, urlPreview.0)
            dismiss.set(handler: { [weak self ] _ in
                self?.dismissUrlPreview()
            }, for: .Click)

            let toggleLinkPosition:(Bool)->Void = { [weak self] below in
                self?.chatInteraction.update {
                    $0.updatedInterfaceState {
                        $0.withUpdatedLinkBelowMessage(below)
                    }
                }
            }
            let toggleLinkSize:(Bool)->Void = { [weak self] big in
                self?.chatInteraction.update {
                    $0.updatedInterfaceState {
                        $0.withUpdatedLargeMedia(big)
                    }
                }
            }

            container.contextMenu = { [weak self] in
                let menu = ContextMenu()
                menu.addItem(ContextMenuItem(strings().chatInputEditLinkAboveTheMessage, handler: {
                    toggleLinkPosition(false)
                }, itemImage: state.interfaceState.linkBelowMessage ? nil : MenuAnimation.menu_check_selected.value))

                menu.addItem(ContextMenuItem(strings().chatInputEditLinkBelowTheMessage, handler: {
                    toggleLinkPosition(true)
                }, itemImage: !state.interfaceState.linkBelowMessage ? nil : MenuAnimation.menu_check_selected.value))

                if let presentation = self?.chatInteraction.presentation, let urlPreview = presentation.urlPreview {
                    switch urlPreview.1.content {
                    case let .Loaded(content):
                        if let defaultValue = content.isMediaLargeByDefault {
                            menu.addItem(ContextSeparatorItem())

                            let value = state.interfaceState.largeMedia ?? defaultValue

                            menu.addItem(ContextMenuItem(strings().chatInputEditLinkLargerMedia, handler: {
                                toggleLinkSize(true)
                            }, itemImage: value ? MenuAnimation.menu_check_selected.value : nil))

                            menu.addItem(ContextMenuItem(strings().chatInputEditLinkSmallerMedia, handler: {
                                toggleLinkSize(false)
                            }, itemImage: !value ? MenuAnimation.menu_check_selected.value : nil))
                        }
                    default:
                        break
                    }
                }

                menu.addItem(ContextSeparatorItem())

                menu.addItem(ContextMenuItem(strings().chatInputEditLinkRemovePreview, handler: { [weak self] in
                    self?.dismissUrlPreview()
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))

                return menu
            }

        } else if selectedPanel?.kind == .edit, let editState = state.interfaceState.editState {
            displayNode = ChatInputUIHooks.shared.makeEditMessageModel(editState, context)
            progress?.isHidden = editState.loadingState == .none
            updateProgress(editState.loadingState)
            dismiss.set(handler: { [weak self] _ in
                self?.dismissEdit()
            }, for: .Click)
            progress?.set(handler: { [weak self] _ in
                self?.dismiss.send(event: .Click)
            }, for: .Click)

            container.contextMenu = { [weak self] in
                let menu = ContextMenu()

                if !editState.message.media.isEmpty {
                    menu.addItem(ContextMenuItem(editState.invertMedia ? strings().previewSenderMoveTextDown : strings().previewSenderMoveTextUp, handler: {
                        self?.chatInteraction.update {
                            $0.updatedInterfaceState {
                                $0.updatedEditState {
                                    $0?.withUpdatedInvertMedia(!editState.invertMedia)
                                }
                            }
                        }
                    }, itemImage: editState.invertMedia ? MenuAnimation.menu_sort_down.value : MenuAnimation.menu_sort_up.value))
                }
                if !editState.message.media.isEmpty, editState.addedMedia {
                    menu.addItem(ContextMenuItem(strings().previewSenderRemoveMedia, handler: {
                        self?.chatInteraction.update {
                            $0.updatedInterfaceState {
                                $0.updatedEditState { value in
                                    if let value = value {
                                        return .init(message: value.message.withUpdatedMedia([]))
                                    } else {
                                        return nil
                                    }
                                }
                            }
                        }
                    }, itemImage: MenuAnimation.menu_clear_history.value))
                }

                return menu
            }

        } else if selectedPanel?.kind == .forward {
            // Rich-text (AI-composed) messages keep the sender shown for non-premium users: hiding the
            // sender's name on such a forward is a Premium feature. When locked, force it off and show a
            // premium prompt on tap (see setHideAction); premium users hide as usual.
            let hasRichText = state.interfaceState.forwardMessages.contains(where: { message in
                message.attributes.contains(where: { $0 is RichTextMessageAttribute })
            })
            let lockHideSender = hasRichText && !context.isPremium
            if lockHideSender, state.interfaceState.hideSendersName {
                Queue.mainQueue().justDispatch { [weak self] in
                    self?.chatInteraction.update {
                        $0.updatedInterfaceState { $0.withUpdatedHideSendersName(false, saveTempValue: false) }
                    }
                }
            }
            displayNode = ChatInputUIHooks.shared.makeForwardPanelModel(state.interfaceState.forwardMessages, lockHideSender ? false : state.interfaceState.hideSendersName, context)

            let anotherAction = { [weak self] in
                guard let context = self?.chatInteraction.interactionContext else {
                    return
                }
                let fwdMessages = state.interfaceState.forwardMessages
                showModal(with: ChatInputUIHooks.shared.makeForwardMessagesModal(context, fwdMessages), for: context.window)
                delay(0.15, closure: {
                    self?.chatInteraction.update({$0.updatedInterfaceState({$0.withoutForwardMessages()})})
                })
            }
            let setHideAction:(Bool)->Void = { [weak self] hide in
                guard let self else { return }
                if hide, lockHideSender {
                    showModalText(for: context.window, text: strings().chatInputAccessoryHideSenderPremium, callback: { _ in
                        prem(with: PremiumBoardingController(context: context, source: .ai_compose, openFeatures: true), for: context.window)
                    })
                    return
                }
                self.chatInteraction.update {
                    $0.updatedInterfaceState {
                        $0.withUpdatedHideSendersName(hide, saveTempValue: true)
                    }
                }
            }
            let setHideCaption:(Bool)->Void = { [weak self] hide in
                self?.chatInteraction.update {
                    $0.updatedInterfaceState { current in
                        var current = current
                        current = current.withUpdatedHideCaption(hide)
                        if current.tempSenderName == nil {
                            current = current.withUpdatedHideSendersName(hide, saveTempValue: false)
                        }
                        return current
                    }
                }
            }


            container.contextMenu = {
                var items:[ContextMenuItem] = []

                let authors = state.interfaceState.forwardMessages.compactMap { $0.author?.id }.uniqueElements.count

                let hideSendersName = lockHideSender ? false : state.interfaceState.hideSendersName

                items.append(ContextMenuItem(strings().chatAlertForwardActionShow1Other(authors), handler: {
                    setHideAction(false)
                }, itemImage: !hideSendersName ? MenuAnimation.menu_check_selected.value : nil))

                // Kept enabled even when locked: tapping shows the premium prompt (setHideAction).
                items.append(ContextMenuItem(strings().chatAlertForwardActionHide1Other(authors), handler: {
                    setHideAction(true)
                }, itemImage: hideSendersName ? MenuAnimation.menu_check_selected.value : nil))

                items.append(ContextSeparatorItem())

                let messagesWithCaption = state.interfaceState.forwardMessages.filter {
                    !$0.text.isEmpty && $0.anyMedia != nil
                }.count

                if messagesWithCaption > 0 {

                    items.append(ContextMenuItem(strings().chatAlertForwardActionShowCaptionOther(messagesWithCaption), handler: {
                        setHideCaption(false)
                    }, itemImage: !state.interfaceState.hideCaptions ? MenuAnimation.menu_check_selected.value : nil))

                    items.append(ContextMenuItem(strings().chatAlertForwardActionHideCaptionOther(messagesWithCaption), handler: {
                        setHideCaption(true)
                    }, itemImage: state.interfaceState.hideCaptions ? MenuAnimation.menu_check_selected.value : nil))

                    items.append(ContextSeparatorItem())

                }
                if let peer = state.peer, !peer.isCopyProtected(cachedData: state.cachedData) {
                    items.append(ContextMenuItem(strings().chatAlertForwardActionAnother, handler: anotherAction, itemImage: MenuAnimation.menu_replace.value))
                }

                let menu = ContextMenu()
                for item in items {
                    menu.addItem(item)
                }
                return menu

            }

            dismiss.set(handler: { [weak self] _ in
                self?.dismissForward()
            }, for: .Click)


        } else if selectedPanel?.kind == .reply, let replyMessageId = state.interfaceState.replyMessageId {
            displayNode = ReplyModel(message: nil, replyMessageId: replyMessageId.messageId, context: chatInteraction.interactionContext, replyMessage: state.interfaceState.replyMessage, quote: replyMessageId.quote, innerSubject: replyMessageId.innerSubject, dismissReply: dismissReply, forceClassic: true)
            dismiss.set(handler: { [weak self ] _ in
                self?.dismissReply()
            }, for: .Click)

            container.set(handler: { [weak self] _ in
                self?.chatInteraction.focusMessageId(nil, .init(messageId: replyMessageId.messageId, quote: replyMessageId.quote), .CenterEmpty)
             }, for: .Click)


            container.contextMenu = { [weak self] in
                let menu = ContextMenu()
                if let peer = state.peer, !peer.isCopyProtected(cachedData: state.cachedData) {
                    menu.addItem(ContextMenuItem(strings().chatInputReplyReplyToAnother, handler: {
                        self?.chatInteraction.replyToAnother(replyMessageId, true)
                    }, itemImage: MenuAnimation.menu_replace.value))
                }
                return menu

            }
        }

        if let displayNode = displayNode {
            displayNode.backgroundColor = .clear
            nodeReady.set(displayNode.nodeReady.get() |> map { _ in return animated })
        } else {
            nodeReady.set(.single(animated))
        }
        
        disposable.set(nodeReady.get().startStandalone(next: { [weak self, container] value in
            self?.displayNode?.view = container
        }))
    }

    private func updateProgress(_ loadingState: EditStateLoading) {
        switch loadingState {
        case .none:
            progress?.removeFromSuperview()
            progress = nil
        case .loading:

            let indicator:ProgressIndicator
            if let _indicator = progress as? ProgressIndicator {
                indicator = _indicator
            } else {
                indicator = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
                progress = indicator
                self.addSubview(indicator)
            }
            indicator.progressColor = theme.colors.text
        case let .progress(progress):
            let radial: RadialProgressView
            if let _radial = self.progress as? RadialProgressView {
                radial = _radial
            } else {
                radial = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .clear, foregroundColor: theme.colors.accent), twist: true, size: NSMakeSize(20, 20))
                self.progress = radial
                self.addSubview(radial)
            }
            radial.state = .ImpossibleFetching(progress: progress, force: false)
        }
    }


    public override func layout() {
        super.layout()
        updateLayout(frame.size, transition: .immediate)
    }

    public func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(view: self.container, alpha: isVisibility() ? 1 : 0)
        transition.updateAlpha(view: self.dismiss, alpha: isVisibility() ? 1 : 0)
        transition.updateFrame(view: self.container, frame: NSMakeRect(10, 0, size.width - 10, size.height))
        transition.updateFrame(view: dismiss, frame: dismiss.centerFrameY(x: size.width - dismiss.frame.width - 6))
        displayNode?.setNeedDisplay()

    }


    deinit {
        disposable.dispose()
    }

    public var size: NSSize = .zero

    public func isVisibility() -> Bool {
        let isRecordingVoice:Bool
        if case .recording = chatInteraction.presentation.state {
            isRecordingVoice = true
        } else {
            isRecordingVoice = false
        }
        return (displayNode != nil) && (self.chatInteraction.presentation.state == .normal || self.chatInteraction.presentation.state == .editing || isRecordingVoice)
    }


    public func measureSize(_ width: CGFloat) {
        displayNode?.measureSize(width - 10 - (displayNode?.cutout?.topLeft?.width ?? 0))

        if let displayNode = displayNode {
            self.size = NSMakeSize(width, displayNode.size.height)
        }
    }



}
