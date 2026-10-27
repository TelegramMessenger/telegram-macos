import Cocoa
import TGUIKit
import SwiftSignalKit
import UniformTypeIdentifiers
import TelegramCore
import Postbox
import RichTextEditorUI
import RichTextEditorCore
import InAppSettings
import KeyboardKey
import ColorPalette
import Localization
import TelegramMediaResources
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AlertsUI
import FilePanels
import GeneralRows
import InputDataUI
import InputTextView
import InstantPageUI
import LocalAnimations
import PremiumUI
import InlineStickerLayer
import InputView

/// Routes the editor package's built-in menu titles / placeholders through the app's localization.
/// Lazily evaluated once (global `let`) the first time an editor is created.
private let _richTextEditorLocalizationSetup: Void = {
    RichTextEditorLocalization.localize = { key, fallback in
        let value = _NSLocalizedString(key)
        return value == key ? fallback : value
    }
    // The block pill's corner action badge (the ↗ on a URL button) — the chat renderer's own icon set,
    // handed to the editor as an alpha mask so its pills read exactly like the sent message. A
    // link-styled pill draws no chrome, so no badge either.
    RichTextEditorButtonBadges.provider = { button in
        guard !button.isLink else { return nil }
        let pageButton = InstantPageButton(text: .empty,
                                           action: replyMarkupButtonAction(from: button.action),
                                           color: replyMarkupColor(from: button.color),
                                           isLink: button.isLink)
        guard let cg = instantPageButtonActionIcon(InstantPageButtonUIModel(button: pageButton).icon) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / System.backingScale,
                                                 height: CGFloat(cg.height) / System.backingScale))
    }
}()

private func richTextScheduleRequest(chatInteraction: ChatInteraction) -> ((@escaping (Date, Int32?) -> Void) -> Void)? {
    guard case .scheduled = chatInteraction.mode, let peer = chatInteraction.peer else { return nil }
    let context = chatInteraction.interactionContext
    return { selected in
        showModal(with: chatDateSelector(context: context, mode: .schedule(peer.id), selectedAt: { date, repeatPeriod in
            selected(date, repeatPeriod)
        }), for: context.window)
    }
}

private func richTextSendMenuItems(chatInteraction: ChatInteraction) -> ((@escaping (Bool, ChatInteraction.Schedule?) -> Void) -> [ContextMenuItem]?) {
    return { [weak chatInteraction] send in
        guard let chatInteraction else { return nil }
        return sendMessageMenuItems(chatInteraction: chatInteraction, send: { silent, schedule in
            send(silent, schedule)
        })
    }
}

func richTextThreadReplySubject(chatInteraction: ChatInteraction) -> EngineMessageReplySubject? {
    guard let threadId = chatInteraction.chatLocation.threadId, !chatInteraction.isMonoforum, threadId != Message.newTopicThreadId else {
        return nil
    }
    return .init(messageId: MessageId(peerId: chatInteraction.peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId)), quote: nil, innerSubject: nil)
}

func richTextEnqueue(chatInteraction: ChatInteraction, text: String, attributes: [MessageAttribute]) {
    let context = chatInteraction.interactionContext
    let message: EnqueueMessage = .message(text: text, attributes: attributes, inlineStickers: [:],
                                           mediaReference: nil, threadId: chatInteraction.chatLocation.threadId,
                                           replyToMessageId: chatInteraction.presentation.interfaceState.replyMessageId ?? richTextThreadReplySubject(chatInteraction: chatInteraction), replyToStoryId: nil, localGroupingKey: nil,
                                           correlationId: nil, bubbleUpEmojiOrStickersets: [])
    if let customChatContents = chatInteraction.mode.customChatContents {
        _ = (customChatContents.enqueueMessages(messages: [message])).start()
    } else {
        _ = (enqueueMessages(account: context.account, peerId: chatInteraction.peerId, messages: [message])).start()
    }
    chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedReplyMessageId(nil) } }
    if chatInteraction.mode != .scheduled, attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute }) {
        delay(0.1, closure: { [weak chatInteraction] in
            guard let chatInteraction else { return }
            chatInteraction.openScheduledMessages()
        })
    }
}

// MARK: - Entry point (called from ChatInputAttachView inside `if #available(macOS 12, *)`)

@available(macOS 12, *)
public func showRichTextEditor(chatInteraction: ChatInteraction, morphSource: (() -> NSView?)? = nil) {
    let context = chatInteraction.interactionContext

    // Seed the editor from whatever draft the composer currently holds, consuming the source:
    //   • an existing structural rich draft (the InstantPage preview shown above the input), or
    //   • the plain composer text (which is then cleared).
    var initialDocument: Document?
    var initialDraft: (blocks: [RichTextOutgoingBlock], media: [String: Media])?
    if let draft = chatInteraction.richTextDraft {
        // Reopen the structural draft WITH its media (text→photo→text round-trips).
        initialDraft = richTextOutgoing(from: draft)
        chatInteraction.setRichTextDraft(nil)
    } else {
        let inputState = chatInteraction.presentation.effectiveInput
        let composerText = inputState.inputText
        if !composerText.isEmpty {
            // Parse the composer's ``` fences (the input's native code currency) into .Pre entities so
            // fenced code opens as a real code block, exactly like the send path parses it.
            let parsed = inputState.subInputState(from: NSMakeRange(0, composerText.length))
            initialDocument = richTextDocument(text: parsed.inputText, entities: parsed.messageTextEntities())
            chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedInputState(ChatTextInputState()) } }
        }
    }

    let controller = RichTextEditorController(context: context, initialDocument: initialDocument, initialDraft: initialDraft, requestScheduleDate: richTextScheduleRequest(chatInteraction: chatInteraction), sendMenuItems: richTextSendMenuItems(chatInteraction: chatInteraction), onCancel: { composed in
        switch composed {
        case let .rich(instantPage):
            chatInteraction.setRichTextDraft(instantPage)
        case let .plain(text, entities):
            chatInteraction.setRichTextDraft(nil)
            guard !text.isEmpty else { return }
            let attributes = chatTextAttributes(from: TextEntitiesMessageAttribute(entities: entities))
            let state = ChatTextInputState(inputText: text, selectionRange: text.length ..< text.length, attributes: attributes)
            // The composer's native code-block currency is ``` fences — the `.pre` attribute has no
            // input rendering and is silently dropped on the next edit — so hand code back as fenced
            // text (the send path re-parses the fences into Pre entities).
            let formatted = state.makeAttributeString(addPreAsBlock: true)
            let fenced = formatted
            let restored = ChatTextInputState(attributedText: fenced, selectionRange: fenced.length ..< fenced.length)
            chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedInputState(restored) } }
        case .empty:
            chatInteraction.setRichTextDraft(nil)
        }
    }, send: { text, attributes in
        chatInteraction.setRichTextDraft(nil)
        richTextEnqueue(chatInteraction: chatInteraction, text: text, attributes: attributes)
    })
    showModal(with: controller, for: context.window, morphSource: morphSource)
}

// Builds a composer-style editor controller seeded with an explicit document OR a media-bearing draft,
// with the shared enqueue-on-send / draft-on-cancel behavior of the attach-menu entry.
@available(macOS 12, *)
private func composerEditorController(chatInteraction: ChatInteraction, initialDocument: Document?, initialDraft: (blocks: [RichTextOutgoingBlock], media: [String: Media])?) -> InputDataModalController {
    let context = chatInteraction.interactionContext
    let controller = RichTextEditorController(context: context, initialDocument: initialDocument, initialDraft: initialDraft, requestScheduleDate: richTextScheduleRequest(chatInteraction: chatInteraction), sendMenuItems: richTextSendMenuItems(chatInteraction: chatInteraction), onCancel: { composed in
        switch composed {
        case let .rich(instantPage):
            chatInteraction.setRichTextDraft(instantPage)
        case let .plain(text, entities):
            chatInteraction.setRichTextDraft(nil)
            guard !text.isEmpty else { return }
            let attributes = chatTextAttributes(from: TextEntitiesMessageAttribute(entities: entities))
            let state = ChatTextInputState(inputText: text, selectionRange: text.length ..< text.length, attributes: attributes)
            let formatted = state.makeAttributeString(addPreAsBlock: true)
            let fenced = formatted
            let restored = ChatTextInputState(attributedText: fenced, selectionRange: fenced.length ..< fenced.length)
            chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedInputState(restored) } }
        case .empty:
            chatInteraction.setRichTextDraft(nil)
        }
    }, send: { text, attributes in
        chatInteraction.setRichTextDraft(nil)
        richTextEnqueue(chatInteraction: chatInteraction, text: text, attributes: attributes)
    })
    return controller
}

// Opens the editor seeded with an explicit document (e.g. text/formula pasted from a rendered rich message).
@available(macOS 12, *)
public func showRichTextEditor(chatInteraction: ChatInteraction, seeding document: Document) {
    let controller = composerEditorController(chatInteraction: chatInteraction, initialDocument: document, initialDraft: nil)
    showModal(with: controller, for: chatInteraction.interactionContext.window)
}

// Opens the editor with the FULL content of a rich-text message (refetched by id) — used when pasting a
// copy of a media-bearing rich message, so the media (and all structure) come through, not just text.
@available(macOS 12, *)
public func showRichTextEditor(chatInteraction: ChatInteraction, refetching messageId: MessageId) {
    let context = chatInteraction.interactionContext
    _ = (context.account.postbox.messagesAtIds([messageId]) |> deliverOnMainQueue).start(next: { messages in
        guard let message = messages.first, message.id == messageId,
              let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first else { return }
        let draft = richTextOutgoing(from: rich.instantPage)
        let controller = composerEditorController(chatInteraction: chatInteraction, initialDocument: nil, initialDraft: draft)
        showModal(with: controller, for: context.window)
    })
}

@available(macOS 12, *)
public func showRichTextEditor(chatInteraction: ChatInteraction, editing message: Message) {
    let context = chatInteraction.interactionContext
    let messageId = message.id
    let scheduleInfo: OutgoingScheduleInfoMessageAttribute? = message.isScheduledMessage
        ? OutgoingScheduleInfoMessageAttribute(scheduleTime: message.scheduleTime ?? message.timestamp, repeatPeriod: message.scheduleRepeatPeriod)
        : nil
    // A rich message keeps its content (incl. media) in an InstantPage — seed media-preserving so photos /
    // files / tables come back into the editor. Plain messages seed as a text+entities document.
    var initialDocument: Document?
    var initialDraft: (blocks: [RichTextOutgoingBlock], media: [String: Media])?
    if let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
        initialDraft = richTextOutgoing(from: rich.instantPage)
    } else {
        initialDocument = richTextDocument(from: message)
    }
    let controller = RichTextEditorController(context: context, initialDocument: initialDocument, initialDraft: initialDraft, isEditing: true, onDeleteMessage: { [weak chatInteraction] in
        guard let chatInteraction else { return }
        chatInteraction.deleteMessages([messageId], nil)
    }, send: { text, attributes in
        let entities = attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first
        let richText = attributes.compactMap { $0 as? RichTextMessageAttribute }.first
        _ = (context.engine.messages.requestEditMessage(messageId: messageId, text: text, media: .keep, entities: entities, richText: richText, inlineStickers: [:], scheduleInfoAttribute: scheduleInfo) |> deliverOnMainQueue).start(error: { _ in
            showModalText(for: context.window, text: strings().unknownError)
        })
    })
    showModal(with: controller, for: context.window)
}

// MARK: - Controller

private let _id_toolbar = InputDataIdentifier("_id_rte_toolbar")
private let _id_editor = InputDataIdentifier("_id_rte_editor")

private struct RichTextEditorState: Equatable {
    var contentHeight: CGFloat = 0
    /// Extra top space reserved by the spacer row while the premium-formatting toast is visible,
    /// so the toast doesn't overlap the editor content.
    var premiumToastReserve: CGFloat = 0
}

@available(macOS 12, *)
private func richTextEditorEntries(_ state: RichTextEditorState, coordinator: RichTextEditorCoordinator) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    // Toolbar SPACER row — the toolbar itself floats pinned above the table (added in didLoad) so it
    // stays visible while the editor scrolls; this row just reserves its height at the top of the content.
    // (View-less: item closures run on the prepare queue, where creating an NSView trips the main-thread checker.)
    let toastReserve = state.premiumToastReserve
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_toolbar, equatable: InputDataEquatable(toastReserve), comparable: nil, item: { initialSize, stableId in
        return ToolbarSpacerRowItem(initialSize, stableId: stableId, heightForWidth: { width in
            coordinator.toolbar.height(forWidth: width) + toastReserve
        })
    }))
    index += 1

    // Editor row — hosts the (persistent) RichTextEditorView. The editor doesn't scroll internally, so
    // its row grows to the FULL content height (floored at a usable minimum); the modal grows with it
    // and, past the modal's cap, the modal's own table scrolls.
    let editorHeight = max(state.contentHeight, 300)
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_editor, equatable: InputDataEquatable(state.contentHeight), comparable: nil, item: { initialSize, stableId in
        return HostedViewRowItem(initialSize, stableId: stableId, hostedView: coordinator.editor, viewType: .legacy, fixedHeight: editorHeight, initialFirstResponder: { coordinator.editor.inputResponder })
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

@available(macOS 12, *)
public func RichTextEditorController(context: any AccountContextProtocol, initialDocument: Document? = nil, initialDraft: (blocks: [RichTextOutgoingBlock], media: [String: Media])? = nil, isEditing: Bool = false, requestScheduleDate: ((@escaping (Date, Int32?) -> Void) -> Void)? = nil, sendMenuItems: ((@escaping (Bool, ChatInteraction.Schedule?) -> Void) -> [ContextMenuItem]?)? = nil, onDeleteMessage: (() -> Void)? = nil, onCancel: ((ComposedRichMessage) -> Void)? = nil, send: @escaping (_ text: String, _ attributes: [MessageAttribute]) -> Void) -> InputDataModalController {
    let coordinator = RichTextEditorCoordinator(context: context)
    coordinator.editor.withPasteContext = { paste in
        paste()
    }
    let showPremiumFormatting: () -> Void = {
        prem(with: PremiumBoardingController(context: context, source: .rich_formatting, openFeatures: true), for: context.window)
    }
    var didSend = false
    var isClosed = false
    // Non-premium close-confirm: strips the premium formatting from the handed-back draft (text survives).
    var discardPremiumFormatting = false
    // The "requires Telegram Premium" toast pinned under the toolbar (created in didLoad).
    var premiumToastView: NSView?

    /// True when the CURRENT editor content would send as a rich (InstantPage) message — premium-only
    /// formatting for non-premium users. WEAK coordinator capture: this closure is retained by
    /// coordinator-owned hooks (`closeAction`, `onFormatStateChange`), so a strong capture leaks the
    /// whole editor per open.
    let contentNeedsPremium: () -> Bool = { [weak coordinator] in
        guard !context.isPremium, let coordinator else { return false }
        let outgoing = coordinator.editor.outgoingBlocks()
        // Emptied content (e.g. an empty heading/table shell left after deleting all text) never gates.
        guard richTextOutgoingHasContent(outgoing) else { return false }
        if case .rich = composeRichMessage(from: outgoing, media: coordinator.pickedMedia) {
            return true
        }
        return false
    }
    // Assigned once `updateState` exists below; pushes the toast's reserved height into the entries state.
    var applyPremiumToastReserve: ((CGFloat) -> Void)? = nil
    let updatePremiumGate: () -> Void = { [weak coordinator] in
        guard let coordinator else { return }
        let needsPremium = contentNeedsPremium()
        coordinator.setSendLocked(needsPremium)
        premiumToastView?.isHidden = !needsPremium
        // Content starts at the spacer's end (== toolbar frame maxY + reserve); the toast sits at
        // pillBottom + 8, so reserving height + 16 − contentBottomInset leaves the same 8pt below it.
        let reserve: CGFloat = (needsPremium && premiumToastView != nil) ? (premiumToastView!.frame.height + 16 - coordinator.toolbar.contentBottomInset) : 0
        applyPremiumToastReserve?(reserve)
    }

    // Seed the editor's content up front (editing flow). The blocks enter the canvas model now; the first
    // layout re-flows them at the real width (RichTextEditorView.layout → setParagraphsWidthIfNeeded).
    // A media-bearing draft (initialDraft) is seeded only in didAppear (its async image loads need the
    // laid-out editor), so it's not seeded here.
    var initialState = RichTextEditorState()
    var didSeedInitial = false
    var didPositionInitialCaret = false
    if initialDraft == nil, let initialDocument = initialDocument {
        coordinator.editor.document = initialDocument
        // Pre-measure at ~the modal's editor width so the modal opens at the seeded content's height
        // instead of popping up from the 300 default after the first layout.
        coordinator.editor.frame = NSRect(x: 0, y: 0, width: 380, height: 300)
        coordinator.editor.layoutSubtreeIfNeeded()
        initialState.contentHeight = coordinator.editor.contentHeight
        // Already seeded — `didLoad` must NOT re-seed (a second `document =` rebuilds the canvas and reports
        // a transient height, flickering the modal). It still focuses + drops the caret below.
        didSeedInitial = true
    }

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((RichTextEditorState) -> RichTextEditorState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    // Grow the editor row with its content (and re-measure the modal) the standard InputData way:
    // a content-height change updates the state, which re-runs `entries` with a new editor-row height.
    coordinator.onContentHeightChange = { [weak coordinator] height in
        // Ignore heights reported before the editor has a real width (e.g. seedDraft runs in didLoad while
        // the editor frame is still 0): at width 0 the content wraps maximally and reports a bogus large
        // height, which sizes the modal huge for a frame before the real layout corrects it (flicker).
        guard let coordinator, coordinator.editor.frame.width > 0 else { return }
        updateState { current in
            var current = current
            current.contentHeight = height
            return current
        }
    }

    applyPremiumToastReserve = { reserve in
        updateState { current in
            var current = current
            current.premiumToastReserve = reserve
            return current
        }
    }

    let signal = statePromise.get()
        |> deliverOnPrepareQueue
        |> map { state in
            return InputDataSignalValue(entries: richTextEditorEntries(state, coordinator: coordinator))
        }

    var close: (() -> Void)? = nil

    let controller = InputDataController(dataSignal: signal, title: "", hasDone: false, returnKeyInvocation: { _, _ in
        // Let the editor handle Return / Shift-Return (new paragraph, exit a table) instead of the
        // controller consuming it to validate/submit (our rows expose no string value, so the default
        // path would otherwise swallow Return).
        return .invokeEvent
    })

    controller.onDeinit = {
        coordinator.dispose()
    }

    // Hardware-keyboard formatting shortcuts, registered on the modal's window the standard TGUIKit way
    // (mirrors the chat composer's ⌘B/⌘I/⌘U, ⇧⌘M/X/P). Scoped to the controller and torn down on disappear.
    controller.didLoad = { controller, _ in
        // Pin the toolbar ABOVE the scrolling table (a direct ScrollView subview doesn't scroll with the
        // document) so it stays visible while the editor content scrolls; the `_id_toolbar` spacer row
        // reserves its slot at the top of the content. Mirrors the old row's 6pt side insets.
        let toolbar = coordinator.toolbar
        if toolbar.superview !== controller.tableView {
            toolbar.removeFromSuperview()
            controller.tableView.addSubview(toolbar)
            let width = controller.tableView.frame.width
            toolbar.frame = NSMakeRect(6, 10, max(0, width - 12), toolbar.height(forWidth: max(0, width - 12)))
            toolbar.autoresizingMask = [.width]
        }
        // Non-premium: the "requires Telegram Premium" toast, pinned right under the toolbar; shown
        // whenever the current content would send as a rich message. The link opens the premium boarding.
        if !context.isPremium, premiumToastView == nil {
            let toast = View()
            let textView = TextView()
            textView.isSelectable = false
            let toastText = isEditing
                ? strings().richTextEditorWindowPremiumToastEdit
                : strings().richTextEditorWindowPremiumToastSend
            let attr = parseMarkdownIntoAttributedString(toastText, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.link), linkAttribute: { contents in
                (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { _ in
                    showPremiumFormatting()
                }))
            }))
            let layout = TextViewLayout(attr, maximumNumberOfLines: 2, alignment: .center)
            layout.measure(width: controller.tableView.frame.width - 80)
            layout.interactions = LinkHooks.shared.globalLinkExecutor()
            textView.update(layout)
            let toastSize = NSMakeSize(layout.layoutSize.width + 32, layout.layoutSize.height + 16)
            // Same frosted glass as the toolbar pills; fully rounded (pill).
            let glass = LiquidGlassView(frame: toastSize.bounds, cornerRadius: toastSize.height / 2, hasShadow: true, hasBorder: true)
            toast.addSubview(glass)
            toast.addSubview(textView)
            toast.setFrameSize(toastSize)
            textView.center()
            // Space from the pills' VISIBLE bottom edge (the toolbar frame extends past them), so the gap
            // above the toast matches the gap below it to the content.
            toast.setFrameOrigin(NSMakePoint(floorToScreenPixels((controller.tableView.frame.width - toastSize.width) / 2), toolbar.frame.maxY - toolbar.contentBottomInset + 8))
            toast.autoresizingMask = [.minXMargin, .maxXMargin]
            toast.isHidden = true
            controller.tableView.addSubview(toast)
            premiumToastView = toast
        }
        coordinator.editor.onFormatStateChange = { updatePremiumGate() }
        updatePremiumGate()
        // A media-bearing draft is seeded here (its async image loads need the laid-out editor); a plain
        // document was already seeded + pre-measured at creation (didSeedInitial), so it is NOT re-seeded —
        // re-seeding rebuilds the canvas and reports a transient height, flickering the modal. Both paths
        // then place the caret at the end once; InputData's regular appearance routing focuses the canvas.
        if !didSeedInitial, let initialDraft = initialDraft {
            didSeedInitial = true
            coordinator.seedDraft(blocks: initialDraft.blocks, media: initialDraft.media)
        }
        if !didPositionInitialCaret {
            didPositionInitialCaret = true
            coordinator.editor.moveCaretToEnd()
        }
        guard let window = controller.window else { return }
        func register(_ key: KeyboardKey, _ flags: NSEvent.ModifierFlags, _ action: @escaping () -> Void) {
            window.set(handler: { _ -> KeyHandlerResult in
                coordinator.editor.makeEditorFirstResponder()
                action()
                return .invoked
            }, with: controller, for: key, priority: .modal, modifierFlags: flags)
        }
        register(.B, [.command]) { coordinator.editor.toggleBold() }
        register(.I, [.command]) { coordinator.editor.toggleItalic() }
        register(.U, [.command]) { coordinator.editor.toggleUnderline() }
        register(.M, [.command, .shift]) { coordinator.editor.toggleInlineCode() }
        register(.X, [.command, .shift]) { coordinator.editor.toggleStrikethrough() }
        register(.P, [.command, .shift]) { coordinator.editor.toggleSpoiler() }
        // Undo/redo on the modal's window — the editor owns a dedicated undo manager, so the system
        // Edit▸Undo only reaches it when the canvas is first responder; routing ⌘Z here (which focuses the
        // editor first) makes it work regardless of what currently holds focus (e.g. ModalBackground).
        register(.Z, [.command]) { coordinator.editor.undo() }
        register(.Z, [.command, .shift]) { coordinator.editor.redo() }
    }
    controller.willDisappear = { controller in
        isClosed = true
        controller.window?.removeAllHandlers(for: controller)
        // Dismissed without sending → hand the editor's composed content back to the caller (chat composer):
        // a structural InstantPage becomes a rich draft, plain text returns to the input.
        if !didSend {
            // A confirmed "Discard Changes" hands back NOTHING — the draft is dropped entirely.
            // Structurally-present but EMPTY content (an empty table / quote / code block / blank
            // paragraphs) is also nothing: don't hand back a blank draft the composer can't do
            // anything with.
            let outgoing = coordinator.editor.outgoingBlocks()
            let composed: ComposedRichMessage = (discardPremiumFormatting || !richTextOutgoingHasContent(outgoing))
                ? .empty
                : composeRichMessage(from: outgoing, media: coordinator.pickedMedia)
            onCancel?(composed)
        }
    }

    // No title, no bottom button, no close header — the floating glass toolbar owns close / send / undo.
    let modalController = RichEditorModalController(controller, modalInteractions: nil, size: NSMakeSize(560, 500))

    // Re-frame the pinned floating toolbar to the editor's (dynamic) width on every resize, and
    // re-center the premium toast under it — autoresizing inside the table view isn't reliable.
    modalController.onResize = { [weak coordinator, weak controller] in
        guard let coordinator, let controller else { return }
        let toolbar = coordinator.toolbar
        guard toolbar.superview === controller.tableView else { return }
        let width = controller.tableView.frame.width
        toolbar.frame = NSMakeRect(6, 10, max(0, width - 12), toolbar.height(forWidth: max(0, width - 12)))
        toolbar.needsLayout = true
        if let toast = premiumToastView {
            toast.setFrameOrigin(NSMakePoint(floorToScreenPixels((width - toast.frame.width) / 2), toolbar.frame.maxY - coordinator.toolbar.contentBottomInset + 8))
        }
    }

    close = { [weak modalController] in
        isClosed = true
        // A send transforms the draft into a message, so it must not morph back onto the attach button
        // (that reads as a cancel); only an actual cancel morphs back.
        modalController?.modal?.close(animationType: didSend ? .noMorph : .common)
    }
    // Non-premium close-confirm: the handed-back draft would be a rich draft they can't send — the
    // standard Discard Changes alert (same as the media sender / other modals) confirms; the premium
    // formatting is stripped and the text survives as plain input.
    let confirmDiscardIfNeeded: () -> Bool = {
        guard !isClosed, !didSend, contentNeedsPremium() else { return true }
        verifyAlert_button(for: context.window, header: strings().mediaSenderDiscardChangesHeader, information: strings().mediaSenderDiscardChangesText, ok: strings().mediaSenderDiscardChangesOK, successHandler: { _ in
            guard !isClosed, !didSend else { return }
            discardPremiumFormatting = true
            close?()
        })
        return false
    }
    modalController.closableImpl = {
        confirmDiscardIfNeeded()   // gates ESC / click-outside the same way as the ✕ button
    }
    coordinator.closeAction.action = {
        if !confirmDiscardIfNeeded() {
            return
        }
        close?()
    }
    coordinator.aiAction.action = { [weak coordinator] in
        guard let coordinator else { return }
        guard context.isPremium else {
            showModalText(for: context.window, text: strings().richTextEditorWindowAiPremiumRequired, button: strings().alertLearnMore, callback: { _ in
                showPremiumFormatting()
            })
            return
        }
        let editor = coordinator.editor
        // A selection opens the full AI editor (proofread / translate / style incl. a single-use prompt)
        // on the selected rich fragment; Apply splices the transformed blocks back over the selection.
        if editor.hasSelection {
            let selection = editor.selectedBlocks()
            let page = richTextInstantPage(from: outgoingBlocks(fromSelection: selection), media: [:])
            if let page {
                let (text, entities) = richTextPlainPreview(from: page)
                showModal(with: ChatInputUIHooks.shared.makeRichTranslateModalObserved(context, nil, appAppearance.languageCode, text, entities, selection, onUse: { [weak coordinator] blocks in
                    guard let coordinator else { return }
                    coordinator.editor.replaceSelection(with: blocks)
                    coordinator.editor.makeEditorFirstResponder()
                }), for: context.window)
                return
            }
        }
        // No selection: free-form generation — the result is spliced at the caret. Formulas the model
        // left as literal `$…$` / `\(…\)` / `\[…\]` text are extracted into formula atoms.
        showModal(with: RichTextAiComposeController(context: context, completion: { [weak coordinator] result in
            guard let coordinator else { return }
            let (blocks, _) = richTextOutgoing(from: result)
            coordinator.editor.replaceSelection(with: extractingAIFormulas(coreBlocks(fromOutgoing: blocks)))
            coordinator.editor.makeEditorFirstResponder()
        }), for: context.window)
    }
    let deliver: (String, [MessageAttribute], Bool, ChatInteraction.Schedule?) -> Void = { text, attributes, silent, schedule in
        guard !isClosed, !didSend else { return }
        let commit: ([MessageAttribute]) -> Void = { attributes in
            guard !isClosed, !didSend else { return }
            var attributes = attributes
            if silent {
                attributes.append(NotificationInfoMessageAttribute(flags: [.muted]))
            }
            didSend = true
            send(text, attributes)
            close?()
        }
        let scheduled: (Date, Int32?) -> MessageAttribute = { date, repeatPeriod in
            let scheduleTime = Int32(min(date.timeIntervalSince1970, Double(scheduleWhenOnlineTimestamp)))
            return OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: repeatPeriod)
        }
        if let schedule {
            commit(attributes + [scheduled(schedule.date, schedule.repeatPeriod)])
        } else if let requestScheduleDate {
            requestScheduleDate({ date, repeatPeriod in
                commit(attributes + [scheduled(date, repeatPeriod)])
            })
        } else {
            commit(attributes)
        }
    }
    let performSend: (Bool, ChatInteraction.Schedule?) -> Void = { [weak coordinator] silent, schedule in
        guard let coordinator, !isClosed, !didSend else { return }
        let outgoing = coordinator.editor.outgoingBlocks()
        guard richTextOutgoingHasContent(outgoing) else {
            if isEditing, let onDeleteMessage {
                didSend = true
                close?()
                onDeleteMessage()
                return
            }
            showModalText(for: context.window, text: strings().richTextEditorWindowEmptyMessage)
            return
        }
        let composed = composeRichMessage(from: outgoing, media: coordinator.pickedMedia)
        if case let .rich(instantPage) = composed, !context.isPremium {
            verifyAlert(for: context.window,
                        header: isEditing ? strings().richTextEditorWindowEditWithoutFormatting : strings().richTextEditorWindowSendWithoutFormatting,
                        information: strings().richTextEditorWindowRichFormattingRequiresPremium,
                        ok: isEditing ? strings().richTextEditorWindowEdit : strings().richTextEditorWindowSend,
                        option: strings().richTextEditorWindowRemoveFormatting,
                        optionIsSelected: true,
                        successHandler: { result in
                guard !isClosed, !didSend else { return }
                switch result {
                case .basic:
                    showPremiumFormatting()
                case .thrid:
                    let (text, entities) = richTextPlainPreview(from: instantPage)
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    deliver(text, entities.isEmpty ? [] : [TextEntitiesMessageAttribute(entities: entities)], silent, schedule)
                }
            })
            return
        }
        switch composed {
        case let .rich(instantPage):
            deliver("", [RichTextMessageAttribute(instantPage: instantPage, fullInstantPage: nil)], silent, schedule)
        case let .plain(text, entities):
            deliver(text, entities.isEmpty ? [] : [TextEntitiesMessageAttribute(entities: entities)], silent, schedule)
        case .empty:
            didSend = true
            close?()
        }
    }
    coordinator.sendAction.action = {
        performSend(false, nil)
    }
    if let sendMenuItems {
        coordinator.setSendContextMenu({ [weak coordinator] in
            guard let coordinator, !isClosed, !didSend else { return nil }
            let outgoing = coordinator.editor.outgoingBlocks()
            let media = coordinator.pickedMedia
            let action = ChatDeferredSendAction { [weak coordinator] in
                guard let coordinator, !isClosed, !didSend, coordinator.editor.outgoingBlocks() == outgoing else { return false }
                let currentMedia = coordinator.pickedMedia
                return currentMedia.count == media.count && media.allSatisfy { key, value in
                    currentMedia[key]?.isEqual(to: value) == true
                }
            }
            return sendMenuItems({ silent, schedule in
                guard action.takeIfCurrent() else { return }
                performSend(silent, schedule)
            })
        })
    }

    return modalController
}

// MARK: - Coordinator (owns the persistent editor + toolbar, theme, spoiler dust)

@available(macOS 12, *)
public final class RichTextEditorCoordinator {
    public let editor: RichTextEditorView = { _ = _richTextEditorLocalizationSetup; return RichTextEditorView() }()
    public let toolbar: EditorToolbarView
    /// Fired (with the new content height) when the editor's content height changes — the controller
    /// wires this to its state so the editor row re-measures and the modal re-sizes.
    public var onContentHeightChange: ((CGFloat) -> Void)?
    /// Fired by the toolbar's close (✕) / send (➤) buttons; the controller wires these to the modal.
    public let closeAction = ActionBox()
    public let sendAction = ActionBox()
    /// Fired by the toolbar's AI button; the controller wires this to the AI-compose modal.
    public let aiAction = ActionBox()
    /// The toolbar's send button (for the premium lock badge).
    private var sendButtonView: Control?
    private var sendLockBadge: ImageView?

    /// Shows/hides the small lock badge on the send button (non-premium user with premium formatting —
    /// sending is gated behind the Subscribe/Send-Without-Formatting alert).
    public func setSendLocked(_ locked: Bool) {
        guard let send = sendButtonView else { return }
        if locked {
            guard sendLockBadge == nil else { return }
            // 2px background-colored outline ring separates the badge from the send circle underneath.
            let ring: CGFloat = 2
            let badgeSize = NSMakeSize(20 + ring * 2, 20 + ring * 2)
            let lockIcon = TelegramThemeHooks.shared.image(.iconRichEditorLock).precomposed(presentation.colors.underSelectedColor)
            let image = generateImage(badgeSize, contextGenerator: { size, ctx in
                ctx.clear(size.bounds)
                ctx.setFillColor(presentation.colors.background.cgColor)
                ctx.fillEllipse(in: size.bounds)
                ctx.setFillColor(presentation.colors.accent.cgColor)
                ctx.fillEllipse(in: size.bounds.insetBy(dx: ring, dy: ring))
                ctx.draw(lockIcon, in: size.bounds.focus(NSMakeSize(12, 12)))
            })!
            let badge = ImageView()
            badge.isAccessibilityDecorative = true
            badge.image = image
            badge.setFrameSize(badgeSize)
            send.layer?.masksToBounds = false   // the badge overlaps slightly OUTSIDE the send circle
            send.addSubview(badge)
            badge.setFrameOrigin(NSMakePoint(-5, send.frame.height - badgeSize.height + 5))
            sendLockBadge = badge
        } else if let badge = sendLockBadge {
            badge.removeFromSuperview()
            sendLockBadge = nil
        }
    }

    public func setSendContextMenu(_ items: @escaping () -> [ContextMenuItem]?) {
        sendButtonView?.contextMenu = {
            guard let items = items(), !items.isEmpty else {
                return nil
            }
            let menu = ContextMenu(presentation: .current(presentation.colors))
            for item in items {
                menu.addItem(item)
            }
            return menu
        }
    }
    private let context: any AccountContextProtocol
    private let appearanceDisposable = MetaDisposable()
    /// Custom-emoji files picked from the panel, keyed by their fileId string, so the emoji-view provider
    /// renders them immediately (otherwise it resolves the fileId asynchronously via inlinePacksContext).
    private let emojiFileCache = EmojiFileCache()
    /// Picked attachment media, keyed by the editor block's opaque `mediaID`.
    private let mediaFileCache = MediaFileCache()
    /// The picked media, keyed by `mediaID` — used by the send path to resolve `outgoingBlocks()` media refs.
    public var pickedMedia: [String: Media] { mediaFileCache.media }
    /// A single throwaway interaction (no real peer/chat) shared by all hosted media content nodes —
    /// they hold it, so it must outlive the views. Mirrors `MediaPreviewRowItem`'s throwaway interaction.
    private let mediaInteraction: ChatInteraction
    /// Retains the in-flight `Sender.generateMedia` subscription so it isn't cancelled by disposal.
    private let mediaDisposable = MetaDisposable()
    /// Retains the image-bitmap loads kicked off by `seedDraft` (reopening a media draft).
    private let imageLoadDisposable = DisposableSet()

    public init(context: any AccountContextProtocol) {
        self.context = context
        self.mediaInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: context)
        let editor = self.editor
        let emojiCache = self.emojiFileCache   // capture instances (not self) for the closures below
        let mediaCache = self.mediaFileCache
        let mediaInteraction = self.mediaInteraction
        let mediaDisposable = self.mediaDisposable
        let closeAction = self.closeAction
        let sendAction = self.sendAction
        let aiAction = self.aiAction
        let iconColor = presentation.colors.text   // enabled tint (gray would read as disabled)

        func richIcon(_ resource: TelegramThemeImage) -> CGImage { TelegramThemeHooks.shared.image(resource).precomposed(iconColor) }
        func sfIcon(_ name: String) -> CGImage {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)   // match the 24pt custom glyphs' weight
            let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
            return (img ?? NSImage()).precomposed(iconColor)
        }

        // Selection-preserving wrapper for every formatting action (toolbar button or menu item): clicking
        // can move focus and collapse the editor's selection, so capture it, refocus, restore (only if it
        // changed — re-setting clears the pending typing-format toggles), then run.
        func formatAction(_ apply: @escaping () -> Void) -> () -> Void {
            return {
                let selection = editor.selectedRange
                editor.makeEditorFirstResponder()
                if editor.selectedRange != selection { editor.selectedRange = selection }
                apply()
            }
        }
        // Render an inserted custom emoji `id` (its fileId) as Telegram's animated inline-sticker view.
        editor.registerEmojiViewProvider { id, size in
            guard let fileId = Int64(id) else { return nil }
            let emoji = ChatTextCustomEmojiAttribute(fileId: fileId, file: emojiCache.files[id], emoji: "")
            return InlineStickerView(account: context.account, inlinePacksContext: context.inlinePacksContext,
                                     emoji: emoji, size: size)
        }

        RichTextEditorCoordinator.installSyntaxHighlighter(on: editor, theme: { theme })

        // Render an inserted media block (file/audio/map) with the app's chat content node, built from a
        // local `Media` the same way `MediaPreviewRowItem` renders not-yet-sent media (parent: nil).
        editor.registerMediaBlockViewProvider { _, mediaID, spoiler, width in
            guard let media = mediaCache.media[mediaID] else { return nil }
            return RichTextEditorCoordinator.makeMediaContentView(media: media, width: width, spoiler: spoiler,
                                                                  context: context, interaction: mediaInteraction)
        }
        // Release the content node's status subscription when its block goes away — otherwise the
        // statusDisposable keeps firing on an orphaned view (leak / stray updates).
        editor.registerMediaBlockViewTeardown { view in
            guard let content = view as? ChatMediaContentView else { return }
            content.willRemove()
            content.clean()
        }

        // Collage mosaic — wrap the chat's `GroupedLayout` with synthetic per-media messages (mirrors
        // `ChatRichTextRowItem`'s collageMosaic), measured to the full-bleed width.
        editor.registerMediaGroupMosaic { mediaIDs, maxWidth in
            var messages: [Message] = []
            for (i, mid) in mediaIDs.enumerated() {
                guard let media = mediaCache.media[mid] else { continue }
                messages.append(Message(media, stableId: UInt32(truncatingIfNeeded: i + 1),
                                        messageId: MessageId(peerId: PeerId(0), namespace: Namespaces.Message.Local, id: Int32(i))))
            }
            guard messages.count == mediaIDs.count, !messages.isEmpty else { return [] }
            let grouped = GroupedLayout(messages, type: .photoOrVideo)
            grouped.measure(NSMakeSize(maxWidth, min(maxWidth, 320.0)), spacing: 2.0)
            return (0 ..< grouped.count).map { grouped.frame(at: $0) }
        }
        // Collage tile — a chat content node cropped to the mosaic tile size. Tile teardown reuses the
        // media-block teardown above (a tile is a `ChatMediaContentView`).
        editor.registerMediaGroupTileProvider { mediaID, spoiler, size in
            guard let media = mediaCache.media[mediaID] else { return nil }
            return RichTextEditorCoordinator.makeCollageTileView(media: media, size: size, spoiler: spoiler,
                                                                 context: context, interaction: mediaInteraction)
        }
        // Slider — the chat's paging InstantPageV2SlideshowView, built from the group's cached media.
        editor.registerMediaGroupSliderProvider { mediaIDs, width in
            RichTextEditorCoordinator.makeSliderView(mediaIDs: mediaIDs, width: width,
                                                     media: { mediaCache.media[$0] }, context: context)
        }
        // On-media glass overlay controls: ••• per tile, + add, collage⇄slider toggle.
        editor.registerMediaControlsProvider { [weak editor] ctx in
            guard let editor = editor else { return nil }
            let toggleIcon: CGImage? = (ctx.kind == .collage) ? richIcon(.iconRichMediaStack)
                                      : (ctx.kind == .slider)  ? richIcon(.iconRichMediaGrid) : nil
            let toggleTooltip: String? = (ctx.kind == .collage) ? strings().richTextEditorShowAsSlider
                                        : (ctx.kind == .slider)  ? strings().richTextEditorShowAsCollage : nil
            return MediaGroupControlsView(
                context: ctx, accent: presentation.colors.accent,
                moreIcon: richIcon(.iconRichMediaMore), addIcon: richIcon(.iconRichMediaPlus),
                toggleIcon: toggleIcon, toggleTooltip: toggleTooltip,
                onMore: { [weak editor] index in
                    guard let editor else { return }
                    RichTextEditorCoordinator.presentMediaTileMenu(editor, context: ctx, tileIndex: index,
                                                                   accountContext: context, cache: mediaCache,
                                                                   disposable: mediaDisposable)
                },
                onAdd: { [weak editor] in
                    guard let editor else { return }
                    let isGroup = (ctx.kind == .collage || ctx.kind == .slider)
                    RichTextEditorCoordinator.presentAddToGroupPicker(editor, context: context, cache: mediaCache,
                                                                      disposable: mediaDisposable,
                                                                      groupID: isGroup ? ctx.blockID : nil,
                                                                      convertBlockID: isGroup ? nil : ctx.blockID)
                },
                onToggle: (ctx.kind == .collage || ctx.kind == .slider) ? { [weak editor] in
                    editor?.setMediaGroupKind(groupID: ctx.blockID, kind: ctx.kind == .collage ? "slideshow" : "collage")
                } : nil)
        }

        // Custom (app) context menu — replaces the native NSMenu, adds collage/slider actions on a media.
        editor.registerContextMenuHandler { [weak editor] _, media, hasSelection, event in
            guard let editor = editor else { return false }
            RichTextEditorCoordinator.presentEditorContextMenu(editor, media: media, hasSelection: hasSelection,
                                                               event: event, context: context, cache: mediaCache,
                                                               disposable: mediaDisposable)
            return true
        }

        // Button pills: a click opens the property sheet (label / URL / style / delete). Wiring this
        // hook is also what enables the package's authoring chrome (the row's "…" menu affordance).
        editor.onEditButtonRequested = { [weak editor] button, isBlockPill, completion in
            guard let editor = editor else { return }
            RichTextEditorCoordinator.presentButtonEditor(editor, button: button, isBlockPill: isBlockPill,
                                                          context: context, completion: completion)
        }

        // LEFT pill: close. (Undo is available via the standard ⌘Z shortcut.)
        let closeButton = EditorIconButton(image: sfIcon("xmark")) { _ in closeAction.action?() }

        // "Aa" Format popup: a Heading-style submenu + the character formats, all with the menu_* glyphs.
        let formatButton = RichTextEditorCoordinator.makeMenuButton(icon: richIcon(.iconRichTextFormat)) {
            let cs = editor.currentFormatState()
            let ps = editor.currentParagraphFormatState().style
            func fmt(_ title: String, _ on: Bool, _ icon: TelegramThemeImage, _ apply: @escaping () -> Void) -> ContextMenuItem {
                ContextMenuItem(title, handler: formatAction(apply), state: on ? .on : nil,
                                itemImage: RichTextEditorCoordinator.menuIcon(icon))
            }
            func sty(_ title: String, _ name: ParagraphStyleName, _ icon: TelegramThemeImage, premium: Bool = false, titleFont: NSFont? = nil) -> ContextMenuItem {
                let handler = formatAction { editor.setParagraphStyle(name) }
                let state: NSControl.StateValue? = ps == name ? .on : nil
                let image = RichTextEditorCoordinator.menuIcon(icon)
                let locked = premium && !context.isPremium
                let item: ContextMenuItem
                if let titleFont {
                    let attr = NSAttributedString.initialize(string: title, color: presentation.colors.text, font: titleFont)
                    item = HeadingMenuItem(title, displayTitle: attr, handler: handler, state: state, itemImage: image, locked: locked)
                } else {
                    item = ContextMenuItem(title, handler: handler, state: state, itemImage: image, locked: locked)
                }
                if item.locked { item.lockImage = TelegramThemeHooks.shared.image(.iconMenuStar) }
                return item
            }
            let heading = ContextMenuItem(strings().richTextEditorHeading, itemImage: RichTextEditorCoordinator.menuIcon(.menuHeading))
            let headingMenu = ContextMenu(presentation: .current(presentation.colors))
            headingMenu.addItem(sty("Heading 1", .heading1, .menuHeading1, premium: true, titleFont: .bold(16)))
            headingMenu.addItem(sty("Heading 2", .heading2, .menuHeading2, premium: true, titleFont: .bold(15)))
            headingMenu.addItem(sty("Heading 3", .heading3, .menuHeading3, premium: true, titleFont: .bold(14)))
            headingMenu.addItem(sty("Heading 4", .heading4, .menuHeading4, premium: true, titleFont: .semibold(13)))
            headingMenu.addItem(sty("Heading 5", .heading5, .menuHeading5, premium: true, titleFont: .medium(13)))
            headingMenu.addItem(sty("Heading 6", .heading6, .menuHeading6, premium: true, titleFont: .medium(12)))
            heading.submenu = headingMenu
            return [
                heading,
                sty(strings().richTextEditorText, .body, .menuText),
                ContextSeparatorItem(),
                fmt(strings().textViewTransformBold, cs.bold, .menuBold) { editor.toggleBold() },
                fmt(strings().textViewTransformItalic, cs.italic, .menuItalic) { editor.toggleItalic() },
                fmt(strings().textViewTransformUnderline, cs.underline, .menuUnderline) { editor.toggleUnderline() },
                fmt(strings().textViewTransformStrikethrough, cs.strikethrough, .menuStrikethrough) { editor.toggleStrikethrough() },
                fmt(strings().textViewTransformCode, cs.inlineCode, .menuCode) { editor.toggleInlineCode() },
                ContextMenuItem(strings().textViewTransformSpoiler, handler: formatAction { editor.toggleSpoiler() }, state: cs.spoiler ? .on : nil,
                                itemImage: RichTextEditorCoordinator.menuIcon(.menuSpoiler)),
                { () -> ContextMenuItem in
                    let item = ContextMenuItem(strings().richTextEditorFormula, handler: { RichTextEditorCoordinator.presentLatexPrompt(editor, context: context) },
                                               itemImage: RichTextEditorCoordinator.menuIcon(.menuFormula), locked: !context.isPremium)
                    if item.locked { item.lockImage = TelegramThemeHooks.shared.image(.iconMenuStar) }
                    return item
                }(),
                ContextSeparatorItem(),
                // Both SHEET-FIRST: the property sheet collects label/URL/style, and only Done inserts
                // the result (Cancel inserts nothing; the sheet's URL validation runs first).
                // "Button" is an INLINE pill — from the selection (its text seeds the label) or at a
                // bare caret; "Button Row" is the block form.
                { () -> ContextMenuItem in
                    let item = ContextMenuItem(strings().richTextEditorMenuInlineButton, handler: {
                        RichTextEditorCoordinator.presentNewButtonSheet(editor, isBlockPill: false, context: context)
                    }, itemImage: RichTextEditorCoordinator.menuIcon(.menuAddButton), locked: !context.isPremium)
                    if item.locked { item.lockImage = TelegramThemeHooks.shared.image(.iconMenuStar) }
                    // The command's own guard (a text run, not a code block), so the item is never
                    // enabled-yet-inert.
                    item.isEnabled = editor.canInsertInlineButton && !editor.hasStructuralTableSelection
                    return item
                }(),
                { () -> ContextMenuItem in
                    let item = ContextMenuItem(strings().richTextEditorMenuButtonRow, handler: {
                        RichTextEditorCoordinator.presentNewButtonSheet(editor, isBlockPill: true, context: context)
                    }, itemImage: RichTextEditorCoordinator.menuIcon(.menuButtonRow), locked: !context.isPremium)
                    if item.locked { item.lockImage = TelegramThemeHooks.shared.image(.iconMenuStar) }
                    // Rows are creatable only in a top-level paragraph.
                    item.isEnabled = editor.canInsertButtonRow
                    return item
                }(),
            ]
        }

        // Non-premium: a small star at a toolbar button's bottom-right corner, marking buttons whose
        // menus contain premium tools (mirrors the star badges on the menu items themselves).
        func addPremiumStarBadge(_ button: Control) {
            guard !context.isPremium else { return }
            // The outline star, tinted to the pill background, knocks a halo out of the glyph; the colored
            // star draws above it (see the reference design).
            let outline = TelegramThemeHooks.shared.image(.iconMenuStarOutline).precomposed(presentation.colors.background)
            let star = TelegramThemeHooks.shared.image(.iconMenuStar)._cgImage
            let size = outline.backingSize
            let composed = generateImage(size, contextGenerator: { sz, ctx in
                ctx.clear(sz.bounds)
                ctx.draw(outline, in: sz.bounds)
                if let star {
                    ctx.draw(star, in: sz.bounds.focus(star.backingSize))
                }
            })
            let badge = ImageView()
            badge.isAccessibilityDecorative = true
            badge.image = composed
            badge.sizeToFit()
            button.addSubview(badge)
            // TGUIKit views are flipped: bottom-right = (width − w, height − h).
            badge.setFrameOrigin(NSMakePoint(button.frame.width - badge.frame.width, button.frame.height - badge.frame.height))
        }

        // List / block popup.
        let listButton = RichTextEditorCoordinator.makeMenuButton(icon: richIcon(.iconRichTextList)) {
            let list = editor.currentParagraphFormatState().list
            func icon(_ r: TelegramThemeImage) -> (NSColor, ContextMenuItem) -> AppMenuItemImageDrawable { RichTextEditorCoordinator.menuIcon(r) }
            // Lists have no message-entity representation — they send as a rich (premium) message.
            // Lists aren't supported inside table cells — disable them there like the other cell-locked tools.
            let inTable = editor.isCaretInTable
            func premium(_ item: ContextMenuItem) -> ContextMenuItem {
                if item.locked { item.lockImage = TelegramThemeHooks.shared.image(.iconMenuStar) }
                item.isEnabled = !inTable
                return item
            }
            let locked = !context.isPremium
            return [
                { () -> ContextMenuItem in
                    let item = ContextMenuItem(strings().richTextEditorListNone, handler: formatAction { editor.setList(nil) }, state: list == .none ? .on : nil, itemImage: icon(.menuNone))
                    item.isEnabled = !inTable
                    return item
                }(),
                premium(ContextMenuItem(strings().richTextEditorBulletList, handler: formatAction { editor.setList(.bullet) }, state: list == .marker(.bullet) ? .on : nil, itemImage: icon(.menuBulletList), locked: locked)),
                premium(ContextMenuItem(strings().richTextEditorNumberedList, handler: formatAction { editor.setList(.ordered) }, state: list == .marker(.ordered) ? .on : nil, itemImage: icon(.menuNumberedList), locked: locked)),
                premium(ContextMenuItem(strings().richTextEditorChecklist, handler: formatAction { editor.setList(.checklist) }, state: list == .marker(.checklist) ? .on : nil, itemImage: icon(.menuChecklist), locked: locked)),
                ContextSeparatorItem(),
                ContextMenuItem(strings().richTextEditorIncreaseIndent, handler: formatAction { editor.indent() }, itemImage: icon(.menuIndent)),
                ContextMenuItem(strings().richTextEditorDecreaseIndent, handler: formatAction { editor.outdent() }, itemImage: icon(.menuOutdent)),
            ]
        }

        // Quote / code block popup: Quote · Pull Quote · Code Block (apply/insert actions).
        let quoteButton = RichTextEditorCoordinator.makeMenuButton(icon: richIcon(.iconRichTextQuote)) {
            func icon(_ r: TelegramThemeImage) -> (NSColor, ContextMenuItem) -> AppMenuItemImageDrawable { RichTextEditorCoordinator.menuIcon(r) }
            // These are apply/insert actions, not a radio selection — no active-state checkmark.
            let items: [ContextMenuItem] = [
                { () -> ContextMenuItem in
                    let item = ContextMenuItem(strings().textViewTransformQuote, handler: formatAction {
                        if editor.isCaretInCodeBlock {
                            editor.makeCodeBlock()
                        } else if editor.currentParagraphFormatState().isPullQuote {
                            editor.makePullQuote()
                        }
                        editor.wrapInBlockQuote()
                    }, itemImage: icon(.menuQuote))
                    item.isEnabled = !editor.isCaretInTable   // block quotes can't nest in table cells
                    return item
                }(),
                { () -> ContextMenuItem in
                    let item = ContextMenuItem(strings().richTextEditorWindowPullQuote, handler: formatAction {
                        if editor.isCaretInCodeBlock {
                            editor.makeCodeBlock()
                        }
                        editor.makePullQuote()
                    }, itemImage: icon(.menuPullquote))
                    item.isEnabled = !editor.isCaretInTable   // pull quotes can't nest in table cells
                    return item
                }(),
                { () -> ContextMenuItem in
                    let item = ContextMenuItem(strings().richTextEditorWindowCodeBlock, handler: formatAction {
                        if editor.currentParagraphFormatState().isPullQuote {
                            editor.makePullQuote()
                        }
                        if !editor.isCaretInCodeBlock {
                            editor.makeCodeBlock()
                        }
                    }, itemImage: icon(.menuCode))
                    item.isEnabled = !editor.isCaretInTable   // code blocks can't nest in table cells
                    return item
                }(),
            ]
            return items
        }

        // Table popup, context-aware: outside a table only strings().richTextEditorInsertTable; inside, the editing actions
        // (insert row/column · highlight · align · delete) — the structural commands no-op outside a table
        // anyway, so they'd otherwise be dead items.
        let tableButton = RichTextEditorCoordinator.makeMenuButton(icon: richIcon(.iconRichTextTable)) {
            func item(_ title: String, _ icon: TelegramThemeImage, mode: AppMenu.ItemMode = .normal, premium: Bool = false, _ apply: @escaping () -> Void) -> ContextMenuItem {
                let item = ContextMenuItem(title, handler: formatAction(apply), itemMode: mode, itemImage: RichTextEditorCoordinator.menuIcon(icon), locked: premium && !context.isPremium)
                if item.locked { item.lockImage = TelegramThemeHooks.shared.image(.iconMenuStar) }
                return item
            }
            guard editor.isCaretInTable else {
                return [item(strings().richTextEditorInsertTable, .menuTable, premium: true) { editor.insertTable(rows: 2, cols: 2) }]
            }
            let hl = RichTextEditorCoordinator.cellHighlightColor
            return [
                item(strings().richTextEditorInsertAbove, .menuAddAbove) { editor.insertTableRowAbove() },
                item(strings().richTextEditorInsertBelow, .menuAddBelow) { editor.insertTableRowBelow() },
                item(strings().richTextEditorInsertLeft, .menuAddLeft) { editor.insertTableColumnLeft() },
                item(strings().richTextEditorInsertRight, .menuAddRight) { editor.insertTableColumnRight() },
                ContextSeparatorItem(),
                item(strings().richTextEditorHighlight, .menuHighlight) { editor.setTableCellHighlight(hl) },
                item(strings().richTextEditorRemoveHighlight, .menuRemoveHighlight) { editor.removeTableCellHighlight() },
                ContextSeparatorItem(),
                item(strings().richTextEditorAlignLeft, .menuAlignLeft) { editor.setTableColumnAlignment(.left) },
                item(strings().richTextEditorAlignCenter, .menuCenterHorizontal) { editor.setTableColumnAlignment(.center) },
                item(strings().richTextEditorAlignRight, .menuAlignRight) { editor.setTableColumnAlignment(.right) },
                ContextSeparatorItem(),
                ContextMenuItem(editor.isCaretTableBordered ? strings().richTextEditorTableBordersOff : strings().richTextEditorTableBordersOn,
                                handler: formatAction { editor.toggleTableBordered() }),
                ContextMenuItem(editor.isCaretTableCompact ? strings().richTextEditorTableCompactOff : strings().richTextEditorTableCompactOn,
                                handler: formatAction { editor.toggleTableCompact() }),
                ContextSeparatorItem(),
                item(strings().richTextEditorDeleteRow, .menuDeleteCell, mode: .destruct) { editor.deleteTableRow() },
                item(strings().richTextEditorDeleteColumn, .menuDeleteCell, mode: .destruct) { editor.deleteTableColumn() },
            ]
        }

        // Attach: a context menu mirroring the chat attach popover (animated MenuAnimation icons).
        let attachButton = RichTextEditorCoordinator.makeMenuButton(icon: richIcon(.iconRichTextAttach)) {
            // Inline media makes the message a rich (premium) message.
            func premium(_ item: ContextMenuItem) -> ContextMenuItem {
                if item.locked { item.lockImage = TelegramThemeHooks.shared.image(.iconMenuStar) }
                item.isEnabled = !editor.isCaretInTable   // media can't be embedded in table cells
                return item
            }
            let locked = !context.isPremium
            return [
                premium(ContextMenuItem(strings().inputAttachPopoverPhotoOrVideo, handler: { RichTextEditorCoordinator.presentImagePicker(editor, context: context, cache: mediaCache, disposable: mediaDisposable) }, itemImage: MenuAnimation.menu_shared_media.value, locked: locked)),
                premium(ContextMenuItem(strings().inputAttachPopoverFile, handler: { RichTextEditorCoordinator.presentFilePicker(editor, context: context, cache: mediaCache, disposable: mediaDisposable) }, itemImage: MenuAnimation.menu_file.value, locked: locked)),
                premium(ContextMenuItem(strings().inputAttachPopoverLocation, handler: { RichTextEditorCoordinator.presentLocationPicker(editor, context: context, cache: mediaCache, interaction: mediaInteraction) }, itemImage: MenuAnimation.menu_location.value, locked: locked)),
                premium(ContextMenuItem(strings().inputAttachPopoverMusic, handler: { RichTextEditorCoordinator.presentAudioPicker(editor, context: context, cache: mediaCache, disposable: mediaDisposable) }, itemImage: MenuAnimation.menu_music.value, locked: locked)),
            ]
        }
        let linkButton = EditorIconButton(image: richIcon(.iconRichTextLink)) { _ in RichTextEditorCoordinator.presentLinkPrompt(editor, context: context) }
        // AI compose: fires the controller-wired action (serialize → AI modal → re-seed).
        let aiButton = EditorIconButton(image: richIcon(.iconAiRichComposer)) { _ in aiAction.action?() }
        let emojiButton = EditorIconButton(image: richIcon(.iconRichTextEmoji)) { control in
            RichTextEditorCoordinator.presentEmojiPicker(editor, context: context, cache: emojiCache, from: control)
        }

        // Send: accent glass circle (same height as the pills) with the white paper-plane inset inside it.
        let sendIcon: CGImage = {
            let img = TelegramThemeHooks.shared.image(.iconSendMessageLarge)
            return img.precomposed(presentation.colors.underSelectedColor)
        }()
        let sendButton = EditorIconButton(image: sendIcon, size: 38) { _ in sendAction.action?() }
        sendButton.setGlassEffect(size: NSMakeSize(38, 38), tintColor: presentation.colors.accent)

        addPremiumStarBadge(listButton)
        addPremiumStarBadge(tableButton)
        addPremiumStarBadge(aiButton)

        self.toolbar = EditorToolbarView(
            left: [closeButton],
            ai: aiButton,
            center: [formatButton, listButton, quoteButton, tableButton, attachButton, linkButton, emojiButton],
            send: sendButton
        )
        self.sendButtonView = sendButton

        // The editor lives inside the modal's scrolling InputData table; let the table scroll and grow
        // the editor row to fit. In non-scroll mode RichTextEditorView hosts its canvas directly, so its
        // internal NSScrollView is not part of this table row's accessibility hierarchy.
        editor.isScrollEnabled = false
        editor.spoilerEffectProvider = { _ in RichEditorSpoilerEffect() }
        editor.pasteFragmentProvider = { richTextBlocksFromInAppPasteboard() }
        editor.onCodeCopied = { [weak editor] in
            if let window = (editor?.window as? Window) ?? (context.window as Window?) {
                showModalText(for: window, text: localizedString("Share.Link.Copied"))
            }
        }
        editor.onCodeHeaderClicked = { [weak editor] in
            guard let editor else { return }
            RichTextEditorCoordinator.presentCodeLanguagePrompt(editor, context: context)
        }
        editor.document = Document(blocks: [])
        editor.onContentHeightChange = { [weak self] in
            guard let self else { return }
            self.onContentHeightChange?(self.editor.contentHeight)
        }

        applyTheme()
        appearanceDisposable.set((appearanceSignal |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.applyTheme()
        }))
        
    }

    public func dispose() {
        appearanceDisposable.dispose()
        mediaDisposable.dispose()
        imageLoadDisposable.dispose()
    }

    /// Seed the editor with a media-bearing draft (reopening a rich draft): populate the media cache so ALL
    /// hosted media views — image (now a `ChatInteractiveContentView` like video), file/audio/map/video,
    /// collage — resolve from their `mediaID`, then set the blocks. The mediaIDs match `outgoingBlocks()`, so
    /// cancelling re-composes the draft WITH its media (no data loss).
    public func seedDraft(blocks: [RichTextOutgoingBlock], media: [String: Media]) {
        for (id, m) in media { mediaFileCache.media[id] = m }
        editor.setOutgoingBlocks(blocks)
    }

    private func applyTheme() {
        let colors = presentation.colors
        // Button pill slots mirror `ChatRichTextRowItem.buildInstantPageTheme`'s non-bubbled incoming
        // derivation, so the editor's pills match the rendered message: inline neutral =
        // (panelBackground, panelAccent), block neutral = (tableHeader, panelPrimary), primary =
        // (checkboxFill, checkboxForeground).
        editor.editorAppearance = EditorAppearance(
            caretColor: colors.text,
            selectionFocused: colors.accent.withAlphaComponent(0.7),
            selectionUnfocused: colors.accent.withAlphaComponent(0.5),
            background: .clear,
            linkColor: colors.link,
            inlineCodeBackground: colors.grayBackground,
            defaultForeground: colors.text,
            secondaryForeground: colors.grayText,
            spoilerCoverColor: colors.grayText,
            codeAccent: colors.accent,
            isDark: colors.isDark,
            buttonNeutralFill: colors.accent.withAlphaComponent(0.1),
            buttonNeutralLabel: colors.accent,
            buttonNeutralBlockFill: colors.isDark ? colors.accent.withAlphaComponent(0.1) : NSColor(rgb: 0x000000, alpha: 0.05),
            buttonNeutralBlockLabel: colors.text,
            buttonPrimaryFill: colors.accent,
            buttonPrimaryLabel: NSColor(rgb: 0xffffff),
            buttonDanger: colors.redUI,
            buttonSuccess: colors.isDark ? NSColor(rgb: 0x30cf30) : NSColor(rgb: 0x26972c)
        )
    }

    /// An icon toolbar button that opens the app's `ContextMenu` (TGUIKit) on click. `items` is evaluated
    /// fresh each click so the menu's selected-item marks reflect the current selection.
    private static func makeMenuButton(icon: CGImage, items: @escaping () -> [ContextMenuItem]) -> EditorIconButton {
        return EditorIconButton(image: icon, click: { control in
            guard let event = NSApp.currentEvent else { return }
            let menu = ContextMenu(presentation: .current(presentation.colors))
            for item in items() { menu.addItem(item) }
            AppMenu(menu: menu).show(event: event, view: control)
        })
    }

    /// A `ContextMenuItem.itemImage` factory drawing an Icon_RichText_* glyph in the menu.
    private static func menuIcon(_ image: NSImage) -> (NSColor, ContextMenuItem) -> AppMenuItemImageDrawable {
        return { color, _ in
            let view = RichTextMenuIcon(image)
            view.setColor(color)
            return view
        }
    }

    /// Same, by asset symbol — the `menu_*` rich-editor menu glyphs (`.menuBold`, `.menuAlignLeft`, …).
    private static func menuIcon(_ resource: TelegramThemeImage) -> (NSColor, ContextMenuItem) -> AppMenuItemImageDrawable {
        return menuIcon(TelegramThemeHooks.shared.image(resource))
    }


    /// The tint applied to a table cell by the menu's strings().richTextEditorHighlight action (cleared by strings().richTextEditorRemoveHighlight).
    private static var cellHighlightColor: NSColor { presentation.colors.accent.withAlphaComponent(0.2) }

    /// Opens Telegram's emoji panel and inserts the chosen emoji into the editor: a custom (animated)
    /// emoji as an inline atom (rendered by the registered provider), a unicode emoji as plain text.
    /// Mirrors the chat/`InputTextDataRowItem` flow — a throwaway `ChatInteraction` satisfies the panel.
    private static func presentEmojiPicker(_ editor: RichTextEditorView, context: any AccountContextProtocol, cache: EmojiFileCache, from control: Control) {
        let emojis = ChatInputUIHooks.shared.makeEmojiPickerObserved(context, sendAnimatedEmoji: { [weak editor] sticker, _, _, _, _ in
            guard let editor else { return }
            let file = sticker.file._parse()
            cache.files["\(file.fileId.id)"] = file
            editor.makeEditorFirstResponder()
            editor.insertEmoji(id: "\(file.fileId.id)", altText: file.customEmojiText ?? file.stickerText)
        }, sendEmoji: { [weak editor] emoji, _ in
            guard let editor else { return }
            editor.makeEditorFirstResponder()
            editor.insertText(emoji)
        })
        showPopover(for: control, with: emojis)
    }

    /// Picks one OR several photos/videos. A single photo is drawn inline as a bitmap (`insertImage`); a
    /// single video attaches as a hosted chat node (`"video"` media block). Picking 2–10 makes a COLLAGE —
    /// each file becomes a `Media` via `generateMedia` (no send), cached, and inserted as a `"collage"`
    /// group laid out by the chat's `GroupedLayout` mosaic.
    private static func presentImagePicker(_ editor: RichTextEditorView, context: any AccountContextProtocol, cache: MediaFileCache, disposable: MetaDisposable) {
        guard let window = editor.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [editor, panel] response in
            guard response == .OK else { return }
            let urls = Array(panel.urls.prefix(10))   // album cap
            guard !urls.isEmpty else { return }
            if urls.count == 1 {
                let url = urls[0]
                let isVideo = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .movie) ?? false
                if isVideo {
                    disposable.set((Sender.generateMedia(for: MediaSenderContainer(path: url.path, isFile: false),
                                                         account: context.account, isSecretRelated: false)
                                    |> deliverOnMainQueue).start(next: { [weak editor] media, _ in
                        guard let editor = editor else { return }
                        let mediaID = "media-\(arc4random())"
                        cache.media[mediaID] = media
                        editor.makeEditorFirstResponder()
                        editor.insertMediaBlock(kind: "video", mediaID: mediaID)
                    }))
                } else if NSImage(contentsOf: url) != nil {
                    // A photo is a hosted `ChatInteractiveContentView` (like video): generate the media,
                    // cache it, then insert the block so the provider resolves + renders it (native spoiler).
                    disposable.set((Sender.generateMedia(for: MediaSenderContainer(path: url.path, isFile: false),
                                                         account: context.account, isSecretRelated: false)
                                    |> deliverOnMainQueue).start(next: { [weak editor] media, _ in
                        guard let editor = editor else { return }
                        let mediaID = "media-\(arc4random())"
                        cache.media[mediaID] = media
                        editor.makeEditorFirstResponder()
                        editor.insertMediaBlock(kind: "image", mediaID: mediaID)
                    }))
                }
                return
            }
            // 2–10 → a collage. Build each Media (image or video), then insert one group.
            let signals = urls.map { url in
                Sender.generateMedia(for: MediaSenderContainer(path: url.path, isFile: false),
                                     account: context.account, isSecretRelated: false)
            }
            disposable.set((combineLatest(signals) |> deliverOnMainQueue).start(next: { [weak editor] results in
                guard let editor = editor else { return }
                var mediaIDs: [String] = []
                for (media, _) in results {
                    let mediaID = "media-\(arc4random())"
                    cache.media[mediaID] = media
                    mediaIDs.append(mediaID)
                }
                editor.makeEditorFirstResponder()
                editor.insertMediaGroup(kind: "collage", mediaIDs: mediaIDs)
            }))
        }
    }

    /// Picks a local file, turns it into a `Media` via `Sender.generateMedia` (no send), caches it by an
    /// opaque id, and inserts a media block referencing that id. The view is realized by the provider.
    private static func presentFilePicker(_ editor: RichTextEditorView, context: any AccountContextProtocol, cache: MediaFileCache, disposable: MetaDisposable) {
        guard let window = editor.window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [editor, panel] response in
            guard response == .OK, let url = panel.url else { return }
            disposable.set((Sender.generateMedia(for: MediaSenderContainer(path: url.path, isFile: true),
                                                 account: context.account, isSecretRelated: false)
                            |> deliverOnMainQueue).start(next: { [weak editor] media, _ in
                guard let editor = editor else { return }
                let mediaID = "media-\(arc4random())"
                cache.media[mediaID] = media
                editor.makeEditorFirstResponder()
                editor.insertMediaBlock(kind: "file", mediaID: mediaID)
            }))
        }
    }

    /// Presents the location picker; the chosen `TelegramMediaMap` is cached and inserted as a map block.
    /// `LocationModalController` (in `.select` mode) invokes `selectCallback` then closes itself.
    private static func presentLocationPicker(_ editor: RichTextEditorView, context: any AccountContextProtocol, cache: MediaFileCache, interaction: ChatInteraction) {
        ChatNavigationHooks.shared.showLocationSelectorObserved(interaction, { [weak editor] map in
            guard let editor = editor else { return }
            let mediaID = "media-\(arc4random())"
            cache.media[mediaID] = map
            editor.makeEditorFirstResponder()
            editor.insertMediaBlock(kind: "map", mediaID: mediaID)
        }, context.window)
    }

    /// Picks an audio file (same file types as `SendAudioModalController`) and inserts it as an audio
    /// block. `isFile: false` makes `generateMedia` add the `.Audio` attribute, so the file renders as a
    /// music/voice node (not a generic file chip).
    private static func presentAudioPicker(_ editor: RichTextEditorView, context: any AccountContextProtocol, cache: MediaFileCache, disposable: MetaDisposable) {
        filePanel(with: ["mp3", "m4a", "aac", "flac", "ogg", "wav", "opus"], allowMultiple: false, for: context.window, completion: { [editor] paths in
            guard let path = paths?.first else { return }
            disposable.set((Sender.generateMedia(for: MediaSenderContainer(path: path, isFile: false),
                                                 account: context.account, isSecretRelated: false)
                            |> deliverOnMainQueue).start(next: { [weak editor] media, _ in
                guard let editor = editor else { return }
                let mediaID = "media-\(arc4random())"
                cache.media[mediaID] = media
                editor.makeEditorFirstResponder()
                editor.insertMediaBlock(kind: "audio", mediaID: mediaID)
            }))
        })
    }

    /// Syntax-highlight code blocks with the SAME libprisma engine the chat bubble and Instant View
    /// use (`CodeSyntax`/Syntaxer), so what the editor shows is what the sent message shows. The
    /// editor owns detection, debounce and caching, and only asks for (language, text) → colours;
    /// the language arrives trimmed + lowercased (libprisma's grammar lookup is an exact
    /// lowercase-keyed map — "Swift" would produce zero tokens with no error). Generation runs off
    /// the main queue, mirroring the chat's `enqueueCodeSyntax`; the palette is read at request time
    /// (through `theme`) so new blocks pick up the current theme.
    ///
    /// Shared because BOTH editor hosts must register it — this coordinator's modal editor and the chat
    /// composer's inline editor (`RichTextDraftPreviewView.updateEditable`). A host that skips it leaves
    /// `canvas.syntaxHighlighter` nil, and the same document then renders plain in one surface while it is
    /// highlighted in the other and in the sent bubble.
    public static func installSyntaxHighlighter(on editor: RichTextEditorView,
                                         theme: @escaping () -> TelegramPresentationTheme) {
        editor.registerSyntaxHighlighter { language, code, completion in
            ChatInputUIHooks.shared.highlightRichTextSyntax(language, code, theme, completion)
        }
    }

    /// Builds a chat content node for a local `Media`, exactly as `MediaPreviewRowItem` renders not-yet-
    /// sent media: a type-specific `ChatMediaLayoutParameters` via the `.layout(for:)` factory, sized by
    /// `ChatLayoutUtils.contentSize`, updated with `parent: nil`. Returned to the editor's media provider.
    public static func makeMediaContentView(media: Media, width: CGFloat, spoiler: Bool = false, context: any AccountContextProtocol, interaction: ChatInteraction) -> NSView {
        let parameters: ChatMediaLayoutParameters
        let size: NSSize
        if let file = media as? TelegramMediaFile {
            parameters = ChatMediaLayoutParameters.layout(for: file, isWebpage: false, chatInteraction: interaction,
                                                          presentation: .make(theme: theme), automaticDownload: true,
                                                          isIncoming: false, autoplayMedia: AutoplayMediaPreferences.defaultSettings)
            if file.isVideo, let dim = file.dimensions?.size, dim.width > 0, dim.height > 0 {
                // Video fills the full (bled) content width, aspect-preserved — like a photo; the chat
                // content node blurs to fill when the source doesn't fit. (file/audio render as × 40 rows.)
                size = NSMakeSize(width, floor(width * dim.height / dim.width))
            } else {
                size = ChatLayoutUtils.contentSize(for: media, with: width)
            }
        } else if let map = media as? TelegramMediaMap {
            // Full-width map snapshot (default 320:120 aspect), mirroring ChatRichTextRowItem's sizing —
            // contentSize gives a fixed 320×120, so size + imageSize are set to the full content width.
            let mapSize = NSMakeSize(width, floor(width * (120.0 / 320.0)))
            var pw = max(1, Int(mapSize.width * 2)); var ph = max(1, Int(mapSize.height * 2))
            let maxW = 1280
            if pw > maxW { ph = Int(CGFloat(ph) * CGFloat(maxW) / CGFloat(pw)); pw = maxW }
            let resource = MapSnapshotMediaResource(latitude: map.latitude, longitude: map.longitude, width: Int32(pw), height: Int32(ph), zoom: 15)
            parameters = ChatMediaMapLayoutParameters(map: map, resource: resource, presentation: .make(theme: theme),
                                                      automaticDownload: true, execute: {}, imageSize: mapSize)
            size = mapSize
        } else if let image = media as? TelegramMediaImage,
                  let dim = image.representations.last?.dimensions.size, dim.width > 0, dim.height > 0 {
            // A photo fills the full (bled) content width, aspect-preserved — like video — so it stretches
            // edge to edge instead of the aspect-fitted (often narrower) chat content size.
            parameters = ChatMediaLayoutParameters(presentation: .make(theme: theme), media: media)
            size = NSMakeSize(width, floor(width * dim.height / dim.width))
        } else {
            parameters = ChatMediaLayoutParameters(presentation: .make(theme: theme), media: media)
            size = ChatLayoutUtils.contentSize(for: media, with: width)
        }
        parameters.makeLabelsForWidth(width)
        parameters.forceSpoiler = spoiler
        let view = ChatLayoutUtils.contentNode(for: media).init(frame: NSRect(origin: .zero, size: size))
        view.update(with: media, size: size, context: context, parent: nil, table: nil, parameters: parameters, animated: false)
        return view
    }

    /// Builds one collage tile: a chat content node (image/video) rendered to FILL `size` (cropping),
    /// exactly the tile size the mosaic assigned. Same recipe as `makeMediaContentView` but sized to the tile.
    public static func makeCollageTileView(media: Media, size: NSSize, spoiler: Bool = false, context: any AccountContextProtocol, interaction: ChatInteraction) -> NSView {
        let parameters: ChatMediaLayoutParameters
        if let file = media as? TelegramMediaFile {
            parameters = ChatMediaLayoutParameters.layout(for: file, isWebpage: false, chatInteraction: interaction,
                                                          presentation: .make(theme: theme), automaticDownload: true,
                                                          isIncoming: false, autoplayMedia: AutoplayMediaPreferences.defaultSettings)
        } else {
            parameters = ChatMediaLayoutParameters(presentation: .make(theme: theme), media: media)
        }
        parameters.makeLabelsForWidth(size.width)
        parameters.forceSpoiler = spoiler
        let view = ChatLayoutUtils.contentNode(for: media).init(frame: NSRect(origin: .zero, size: size))
        view.update(with: media, size: size, context: context, parent: nil, table: nil, parameters: parameters, animated: false)
        //TODOLANG Task 7: relocate video duration badge to bottom-left so the ••• pill at top-left is clear.
        // The badge is `durationView` on `ChatVideoMessageContentView` (private). Add a public `durationCorner`
        // option to the content node (or expose `durationView`) so editor tiles can set it to bottom-left
        // without affecting chat-message rendering. Do NOT reach into private subviews.
        return view
    }

    /// Builds the paging slider view (the chat's `InstantPageV2SlideshowView`) for a group's media, sized
    /// to the tallest fitted media height. Mirrors `InstantPageV2View.reconcileSlideshows`'s config closure.
    public static func makeSliderView(mediaIDs: [String], width: CGFloat, media: @escaping (String) -> Media?, context: any AccountContextProtocol) -> NSView? {
        // InstantPageMedia requires a (non-optional) webpage; the slideshow view only reads `.media`/`.index`,
        // so a throwaway pending webpage is fine.
        let webpage = TelegramMediaWebpage(webpageId: MediaId(namespace: Namespaces.Media.LocalWebpage, id: 0), content: .Pending(0, nil))
        var medias: [InstantPageMedia] = []
        var height: CGFloat = 0
        for (i, mid) in mediaIDs.enumerated() {
            guard let media = media(mid) else { continue }
            let dim: CGSize
            if let image = media as? TelegramMediaImage, let d = largestImageRepresentation(image.representations)?.dimensions.size { dim = d }
            else if let file = media as? TelegramMediaFile, let d = file.dimensions?.size { dim = d }
            else { dim = CGSize(width: width, height: width) }
            height = max(height, dim.fitted(CGSize(width: width, height: 1200.0)).height)
            medias.append(InstantPageMedia(index: i, media: media, webpage: webpage, url: nil, caption: nil, credit: nil))
        }
        guard !medias.isEmpty else { return nil }
        if height <= 0 { height = 240 }
        let size = NSMakeSize(width, height)
        let view = InstantPageV2SlideshowView(frame: CGRect(origin: .zero, size: size))
        view.cornerRadius = 0
        view.configure(medias: medias, context: context, config: { media, _, _, _ in
            let parent = Message(media, stableId: UInt32(truncatingIfNeeded: arc4random()),
                                 messageId: MessageId(peerId: PeerId(0), namespace: Namespaces.Message.Local, id: 0))
            let presentation = ChatMediaPresentation.make(for: parent, account: context.account, renderType: .bubble, theme: theme)
            let parameters = ChatMediaGalleryParameters(showMedia: { _ in }, showMessage: { _ in }, isWebpage: true,
                                                        presentation: presentation, media: media, automaticDownload: true)
            return (parent, parameters)
        }, size: size)
        return view
    }

    /// Presents the app's (TGUIKit) context menu in place of the native one. Standard edit items plus, when
    /// the click is on a media, collage actions: Add Photo or Video, and a Collage↔Slider toggle.
    private static func presentEditorContextMenu(_ editor: RichTextEditorView, media: EditorMediaContext?, hasSelection: Bool, event: NSEvent, context: any AccountContextProtocol, cache: MediaFileCache, disposable: MetaDisposable) {
        func icon(_ r: TelegramThemeImage) -> (NSColor, ContextMenuItem) -> AppMenuItemImageDrawable { menuIcon(r) }
        var items: [ContextMenuItem] = []
        if hasSelection {
            items.append(ContextMenuItem(strings().richTextEditorCut, handler: { editor.makeEditorFirstResponder(); editor.cut() }, itemImage: icon(.menuCut)))
            items.append(ContextMenuItem(strings().richTextEditorCopy, handler: { editor.makeEditorFirstResponder(); editor.copySelection() }, itemImage: icon(.menuCopy)))
        }
        items.append(ContextMenuItem(strings().richTextEditorPaste, handler: { editor.makeEditorFirstResponder(); editor.paste() }, itemImage: icon(.menuPaste)))
        items.append(ContextMenuItem(strings().richTextEditorSelectAll, handler: { editor.makeEditorFirstResponder(); editor.selectAll() }, itemImage: icon(.menuSelectAll)))

        // Text-formatting submenu — not applicable when the right-click is on a media block.
        if media == nil {
            let formatItem = ContextMenuItem(strings().richTextEditorFormat, itemImage: icon(.menuText))
            let formatMenu = ContextMenu(presentation: .current(presentation.colors))
            formatMenu.addItem(ContextMenuItem(strings().textViewTransformBold, handler: { editor.makeEditorFirstResponder(); editor.toggleBold() }, itemImage: icon(.menuBold)))
            formatMenu.addItem(ContextMenuItem(strings().textViewTransformItalic, handler: { editor.makeEditorFirstResponder(); editor.toggleItalic() }, itemImage: icon(.menuItalic)))
            formatMenu.addItem(ContextMenuItem(strings().textViewTransformUnderline, handler: { editor.makeEditorFirstResponder(); editor.toggleUnderline() }, itemImage: icon(.menuUnderline)))
            formatMenu.addItem(ContextMenuItem(strings().textViewTransformStrikethrough, handler: { editor.makeEditorFirstResponder(); editor.toggleStrikethrough() }, itemImage: icon(.menuStrikethrough)))
            formatMenu.addItem(ContextMenuItem(strings().richTextEditorLink, handler: { presentLinkPrompt(editor, context: context) }, itemImage: icon(.menuLink)))
            formatMenu.addItem(ContextMenuItem(strings().textViewTransformSpoiler, handler: { editor.makeEditorFirstResponder(); editor.toggleSpoiler() }, itemImage: icon(.menuSpoiler)))
            formatMenu.addItem(ContextMenuItem(strings().richTextEditorBody, handler: { editor.makeEditorFirstResponder(); editor.setParagraphStyle(.body) }, itemImage: icon(.menuText)))
            formatItem.submenu = formatMenu
            items.append(formatItem)
        }

        // Right-clicked on a formula (the package put the caret on it): offer to edit it in the LaTeX modal.
        if editor.currentFormula() != nil {
            items.append(ContextSeparatorItem())
            items.append(ContextMenuItem(strings().richTextEditorEditFormula, handler: { presentLatexPrompt(editor, context: context) },
                                         itemImage: icon(.iconRichEditorLatex)))
        }

        // Right-clicked inside a code block (the package put the caret there): set/change its language.
        if editor.isCaretInCodeBlock {
            items.append(ContextSeparatorItem())
            items.append(ContextMenuItem(strings().richTextEditorWindowSetLanguage, handler: {
                presentCodeLanguagePrompt(editor, context: context)
            }, itemImage: MenuAnimation.menu_edit.value))
        }

        if let media = media {
            items.append(ContextSeparatorItem())
            if media.kind == "collage" || media.kind == "slideshow" {
                items.append(ContextMenuItem(strings().richTextEditorAddMedia, handler: {
                    presentAddToGroupPicker(editor, context: context, cache: cache, disposable: disposable,
                                            groupID: media.blockID, convertBlockID: nil)
                }, itemImage: MenuAnimation.menu_shared_media.value))
                let toSlider = media.kind == "collage"
                items.append(ContextMenuItem(toSlider ? strings().richTextEditorShowAsSlider : strings().richTextEditorShowAsCollage, handler: {
                    editor.setMediaGroupKind(groupID: media.blockID, kind: toSlider ? "slideshow" : "collage")
                }))
            } else if media.kind == "image" || media.kind == "video" {
                items.append(ContextMenuItem(strings().richTextEditorAddMedia, handler: {
                    presentAddToGroupPicker(editor, context: context, cache: cache, disposable: disposable,
                                            groupID: nil, convertBlockID: media.blockID)
                }, itemImage: MenuAnimation.menu_shared_media.value))
            }
            items.append(ContextMenuItem(strings().richTextEditorRemove, handler: { editor.removeMediaBlock(blockID: media.blockID) },
                                         itemMode: .destruct, itemImage: icon(.menuDeleteCell)))
        } else if editor.isCaretInTable {
            // Right-clicked inside a table cell (the package moved the caret there): the table editing
            // actions, mirroring the toolbar's in-table menu. Each refocuses the editor; the caret (in
            // the clicked cell) drives the command.
            func tItem(_ title: String, _ glyph: TelegramThemeImage, mode: AppMenu.ItemMode = .normal, _ apply: @escaping () -> Void) -> ContextMenuItem {
                ContextMenuItem(title, handler: { editor.makeEditorFirstResponder(); apply() }, itemMode: mode, itemImage: icon(glyph))
            }
            let hl = cellHighlightColor
            items.append(ContextSeparatorItem())
            items.append(tItem(strings().richTextEditorInsertAbove, .menuAddAbove) { editor.insertTableRowAbove() })
            items.append(tItem(strings().richTextEditorInsertBelow, .menuAddBelow) { editor.insertTableRowBelow() })
            items.append(tItem(strings().richTextEditorInsertLeft, .menuAddLeft) { editor.insertTableColumnLeft() })
            items.append(tItem(strings().richTextEditorInsertRight, .menuAddRight) { editor.insertTableColumnRight() })
            items.append(ContextSeparatorItem())
            items.append(tItem(strings().richTextEditorHighlight, .menuHighlight) { editor.setTableCellHighlight(hl) })
            items.append(tItem(strings().richTextEditorRemoveHighlight, .menuRemoveHighlight) { editor.removeTableCellHighlight() })
            items.append(ContextSeparatorItem())
            items.append(tItem(strings().richTextEditorAlignLeft, .menuAlignLeft) { editor.setTableColumnAlignment(.left) })
            items.append(tItem(strings().richTextEditorAlignCenter, .menuCenterHorizontal) { editor.setTableColumnAlignment(.center) })
            items.append(tItem(strings().richTextEditorAlignRight, .menuAlignRight) { editor.setTableColumnAlignment(.right) })
            items.append(ContextSeparatorItem())
            items.append(ContextMenuItem(editor.isCaretTableBordered ? strings().richTextEditorTableBordersOff : strings().richTextEditorTableBordersOn,
                                         handler: { editor.makeEditorFirstResponder(); editor.toggleTableBordered() }))
            items.append(ContextMenuItem(editor.isCaretTableCompact ? strings().richTextEditorTableCompactOff : strings().richTextEditorTableCompactOn,
                                         handler: { editor.makeEditorFirstResponder(); editor.toggleTableCompact() }))
            items.append(ContextSeparatorItem())
            items.append(tItem(strings().richTextEditorDeleteRow, .menuDeleteCell, mode: .destruct) { editor.deleteTableRow() })
            items.append(tItem(strings().richTextEditorDeleteColumn, .menuDeleteCell, mode: .destruct) { editor.deleteTableColumn() })
        } else if editor.canInsertInlineButton {
            // An inline button pill — from the selection (its text seeds the label) or at a bare
            // caret. Gated on the command's own guard (a text run, not a code block). Sheet-first:
            // the property sheet opens, and Done inserts the pill.
            items.append(ContextSeparatorItem())
            items.append(ContextMenuItem(strings().richTextEditorMenuInlineButton, handler: {
                presentNewButtonSheet(editor, isBlockPill: false, context: context)
            }, itemImage: icon(.menuAddButton)))
        }
        ContextMenu.show(items: items, view: editor, event: event)
    }

    /// Multi-select picker used by the context menu to grow a collage (or convert a single media to one).
    private static func presentAddToGroupPicker(_ editor: RichTextEditorView, context: any AccountContextProtocol, cache: MediaFileCache, disposable: MetaDisposable, groupID: String?, convertBlockID: String?) {
        let targetBlockID = groupID ?? convertBlockID
        let targetTileIndex: Int? = groupID == nil ? nil : 0
        guard let window = editor.window, let targetBlockID,
              let originalMediaID = editor.mediaID(forBlock: targetBlockID, tileIndex: targetTileIndex) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [editor, panel] response in
            guard response == .OK else { return }
            let urls = Array(panel.urls.prefix(10))
            guard !urls.isEmpty else { return }
            let signals = urls.map { Sender.generateMedia(for: MediaSenderContainer(path: $0.path, isFile: false),
                                                          account: context.account, isSecretRelated: false) }
            disposable.set((combineLatest(signals) |> deliverOnMainQueue).start(next: { [weak editor] results in
                guard let editor = editor,
                      editor.mediaID(forBlock: targetBlockID, tileIndex: targetTileIndex) == originalMediaID else { return }
                var mediaIDs: [String] = []
                for (media, _) in results { let id = "media-\(arc4random())"; cache.media[id] = media; mediaIDs.append(id) }
                editor.makeEditorFirstResponder()
                if let groupID = groupID {
                    editor.addMediaToGroup(groupID: groupID, mediaIDs: mediaIDs)
                } else if let convertBlockID = convertBlockID {
                    editor.convertMediaToGroup(blockID: convertBlockID, kind: "collage", addingMediaIDs: mediaIDs)
                }
            }))
        }
    }

    private static func presentLinkPrompt(_ editor: RichTextEditorView, context: any AccountContextProtocol) {
        // A structural table row/column selection is cleared when the editor yields focus to the modal,
        // so it can't be linked through the prompt — skip it rather than insert stray text into a cell.
        guard !editor.hasStructuralTableSelection else { return }
        // Reuse the native chat-input link editor (text + URL). Its completion mirrors that flow:
        // `url == nil` clears the link while keeping the text; editing the text replaces the selection.
        let controller = InputURLFormatterModalController(string: editor.selectedText(), defaultUrl: editor.currentLink(), completion: { [weak editor] text, url in
            guard let editor else { return }
            editor.makeEditorFirstResponder()
            editor.applyLink(text: text, url: url)
        })
        showModal(with: controller, for: context.window)
    }

    /// Opens the LaTeX editor (input + live preview); Apply inserts/edits the formula at the caret. Pre-fills
    /// from `currentFormula()` so the modal edits the formula the caret is on (mirrors the link prompt).
    private static func presentLatexPrompt(_ editor: RichTextEditorView, context: any AccountContextProtocol) {
        guard !editor.hasStructuralTableSelection else { return }
        let controller = RichTextLatexModalController(latex: editor.currentFormula(), completion: { [weak editor] latex in
            guard let editor else { return }
            editor.makeEditorFirstResponder()
            editor.insertFormula(latex: latex)
        })
        showModal(with: controller, for: context.window)
    }

    /// A small one-field prompt for the caret's code-block language (shown in the block's header band,
    /// sent as the message code block's language for syntax highlighting).
    private static func presentCodeLanguagePrompt(_ editor: RichTextEditorView, context: any AccountContextProtocol) {
        let identifier = InputDataIdentifier("_id_code_language")
        let initial = editor.caretCodeBlockLanguage ?? ""
        let entries: [InputDataEntry] = [
            .sectionId(0, type: .customModern(10)),
            .input(sectionId: 0, index: 0, value: .string(initial), error: nil, identifier: identifier,
                   mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil,
                   inputPlaceholder: "swift", filter: { $0 }, limit: 30),
            .sectionId(1, type: .customModern(20)),
        ]
        var close: (() -> Void)? = nil
        let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)),
                                             title: strings().richTextEditorWindowCodeLanguage, validateData: { [weak editor] data in
            editor?.setCodeBlockLanguage(data[identifier]?.stringValue)
            editor?.makeEditorFirstResponder()
            close?()
            return .none
        })
        let modalInteractions = ModalInteractions(acceptTitle: strings().modalOK, accept: { [weak controller] in
            controller?.validateInputValues()
        }, singleButton: true)
        let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(300, 130))
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
            modalController?.close()
        })
        close = { [weak modalController] in
            modalController?.modal?.close()
        }
        controller.didAppear = { controller in
            controller.makeFirstResponderIfPossible(for: identifier, focusIdentifier: nil, scrollDown: false, scrollIfNeeded: true)
        }
        showModal(with: modalController, for: context.window)
    }

    /// The committed form of a button URL, or nil when the entry is not a link. Detection mirrors the
    /// link editor (`InputURLFormatterModalController`): the entry (or its case-normalized form) must
    /// parse as ONE whole link — "wefqwef" and "foo example.com bar" both fail. A detected external
    /// link commits in its normalized form; a telegram-internal link (t.me/…) passes as typed.
    /// Extracted from the sheet's `validateData` closure — inlined there it also blew past the
    /// type-checker's inference budget.
    private static func validatedButtonURL(_ raw: String) -> String? {
        var candidates: [String] = [raw]
        let normalized = caseNormalizedURL(raw)
        if normalized != raw {
            candidates.append(normalized)
        }
        for candidate in candidates {
            let attr = NSMutableAttributedString(string: candidate)
            LinkHooks.shared.detectLinks(attr, [.Links])
            var detected: String? = nil
            attr.enumerateAttribute(NSAttributedString.Key.link, in: attr.range, options: NSAttributedString.EnumerationOptions(rawValue: 0), using: { value, range, stop in
                guard let value = ChatInputUIHooks.shared.resolveInAppLink(value), range.length == attr.length else { return }
                switch value {
                case let .external(link, _):
                    detected = link
                default:
                    detected = candidate
                }
                let s: ObjCBool = true
                stop.pointee = s
            })
            if let detected = detected {
                return detected
            }
        }
        return nil
    }

    /// The SHEET-FIRST create flow: opens the property sheet for a NEW button (no Delete section) and
    /// inserts the configured result only when the sheet commits — Cancel inserts nothing, so no blank
    /// placeholder ever enters the document. An inline pill is seeded with the selected text as its
    /// label; a block pill starts blank. The sheet's mandatory-URL validation runs before the insert.
    public static func presentNewButtonSheet(_ editor: RichTextEditorView, isBlockPill: Bool, context: any AccountContextProtocol) {
        let seed: ButtonRef
        if isBlockPill {
            seed = ButtonRef(label: [], action: .url(""))
        } else {
            // An inline pill from a SELECTION seeds its label with the selected text; a bare caret
            // starts blank and the pill lands at the caret like an emoji atom.
            let label = editor.selectedText()
            seed = ButtonRef(label: label.isEmpty ? [] : [TextRun(text: label)], action: .url(""))
        }
        presentButtonEditor(editor, button: seed, isBlockPill: isBlockPill, showsDelete: false,
                            context: context) { [weak editor] updated in
            guard let editor, let updated else { return }
            editor.makeEditorFirstResponder()
            if isBlockPill {
                editor.insertButtonRow(with: updated)
            } else {
                editor.insertInlineButton(with: updated)
            }
        }
    }

    /// The button property sheet (label / URL / style / delete), mirroring the iOS `ButtonEditorScreen`
    /// semantics: only a `.url` action is authorable — a copyText / disabled / unsupported action
    /// arrives via the edit round-trip, is described read-only, and its payload passes through
    /// untouched. The `link` style is offered for an INLINE pill only (a link-styled row pill renders
    /// chrome-less, a shape an author has no reason to create), and choosing it PRESERVES the
    /// underlying color so an incoming `link + danger` still round-trips; picking a color clears it.
    /// `completion(nil)` deletes the pill (and its row when it was the last); dismissing without Done
    /// makes no change.
    private static func presentButtonEditor(_ editor: RichTextEditorView, button: ButtonRef, isBlockPill: Bool,
                                            showsDelete: Bool = true,
                                            context: any AccountContextProtocol, completion: @escaping (ButtonRef?) -> Void) {
        struct ButtonEditorState: Equatable {
            public var label: String
            public var url: String
            public var color: ButtonColor?
            public var isLink: Bool
        }
        enum StyleChoice: CaseIterable {
            case none, primary, danger, success, link
            public var title: String {
                switch self {
                case .none: return strings().richTextEditorButtonStyleDefault
                case .primary: return strings().richTextEditorButtonStylePrimary
                case .danger: return strings().richTextEditorButtonStyleDanger
                case .success: return strings().richTextEditorButtonStyleSuccess
                case .link: return strings().richTextEditorButtonStyleLink
                }
            }
        }
        let urlEditable: Bool
        let initialURL: String
        switch button.action {
        case let .url(url): urlEditable = true; initialURL = url
        default: urlEditable = false; initialURL = ""
        }
        let initialState = ButtonEditorState(label: button.labelText, url: initialURL,
                                             color: button.color, isLink: button.isLink)
        let statePromise = ValuePromise(initialState, ignoreRepeated: true)
        let stateValue = Atomic(value: initialState)
        let updateState: ((ButtonEditorState) -> ButtonEditorState) -> Void = { f in
            statePromise.set(stateValue.modify(f))
        }

        // A human-readable line for an action the editor cannot author, shown as the fields' footer.
        let actionFooter: String?
        switch button.action {
        case .url: actionFooter = nil
        case let .copyText(payload): actionFooter = payload.isEmpty ? strings().richTextEditorButtonActionCopy : payload
        case .disabled: actionFooter = strings().richTextEditorButtonActionDisabled
        case .unsupported: actionFooter = strings().richTextEditorButtonActionNotEditable
        }

        let idLabel = InputDataIdentifier("_id_button_label")
        let idURL = InputDataIdentifier("_id_button_url")
        func idStyle(_ c: StyleChoice) -> InputDataIdentifier { InputDataIdentifier("_id_button_style_\(c)") }
        let idDelete = InputDataIdentifier("_id_button_delete")
        let idPreview = InputDataIdentifier("_id_button_preview")

        var close: (() -> Void)? = nil

        func entries(_ state: ButtonEditorState) -> [InputDataEntry] {
            var entries: [InputDataEntry] = []
            var sectionId: Int32 = 0
            var index: Int32 = 0
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1

            // Live preview — a real V2 pill reflecting the fields as they are typed.
            let previewButton: ButtonRef = {
                var b = button
                b.label = state.label.isEmpty ? [] : [TextRun(text: state.label)]
                if urlEditable { b.action = .url(state.url) }
                b.color = state.color
                b.isLink = state.isLink
                return b
            }()
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: idPreview,
                                   equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                ButtonPreviewRowItem(initialSize, stableId: stableId, context: context,
                                     button: previewButton, viewType: .singleItem)
            }))
            index += 1
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1

            entries.append(.desc(sectionId: sectionId, index: index,
                                 text: .plain(strings().richTextEditorButtonSectionContent),
                                 data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            entries.append(.input(sectionId: sectionId, index: index, value: .string(state.label), error: nil,
                                  identifier: idLabel, mode: .plain,
                                  data: InputDataRowData(viewType: urlEditable ? .firstItem : .singleItem),
                                  placeholder: nil, inputPlaceholder: strings().richTextEditorButtonLabelPlaceholder,
                                  filter: { $0 }, limit: 64))
            index += 1
            if urlEditable {
                entries.append(.input(sectionId: sectionId, index: index, value: .string(state.url), error: nil,
                                      identifier: idURL, mode: .plain,
                                      data: InputDataRowData(viewType: .lastItem),
                                      placeholder: nil, inputPlaceholder: strings().richTextEditorButtonURLPlaceholder,
                                      filter: { $0 }, limit: 1024))
                index += 1
            }
            if let footer = actionFooter {
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footer),
                                     data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
                index += 1
            }
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1

            entries.append(.desc(sectionId: sectionId, index: index,
                                 text: .plain(strings().richTextEditorButtonSectionStyle),
                                 data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            // The authorable style set: a block-row pill drops `link` (see the doc comment above).
            let choices = StyleChoice.allCases.filter { isBlockPill ? $0 != .link : true }
            let current: StyleChoice = state.isLink ? .link : {
                switch state.color {
                case .none: return .none
                case .some(.primary): return .primary
                case .some(.danger): return .danger
                case .some(.success): return .success
                }
            }()
            for (i, choice) in choices.enumerated() {
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil,
                                        identifier: idStyle(choice),
                                        data: .init(name: choice.title, color: theme.colors.text,
                                                    type: .selectable(choice == current),
                                                    viewType: bestGeneralViewType(choices, for: i),
                                                    action: {
                    updateState { st in
                        var st = st
                        switch choice {
                        case .none: st.color = nil; st.isLink = false
                        case .primary: st.color = .primary; st.isLink = false
                        case .danger: st.color = .danger; st.isLink = false
                        case .success: st.color = .success; st.isLink = false
                        case .link: st.isLink = true   // color intentionally untouched
                        }
                        return st
                    }
                })))
                index += 1
            }
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1

            // A NEW button (the sheet-first create flow) has nothing to delete — the section is hidden.
            if showsDelete {
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil,
                                        identifier: idDelete,
                                        data: .init(name: strings().richTextEditorButtonDelete,
                                                    color: theme.colors.redUI, type: .none, viewType: .singleItem,
                                                    action: {
                    completion(nil)
                    close?()
                })))
                index += 1
            }
            entries.append(.sectionId(sectionId, type: .customModern(20)))
            return entries
        }

        let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
            InputDataSignalValue(entries: entries(state))
        }
        let controller = InputDataController(dataSignal: signal, title: strings().richTextEditorButtonEditorTitle,
                                             validateData: { [weak editor] data in
            let state = stateValue.with { $0 }
            // A `.url` button's URL is MANDATORY and must actually BE a link: Done shakes the field on
            // an empty or undetectable entry instead of saving a dead pill. (Delete bypasses this — it
            // never validates — and read-only actions have no URL field.)
            var validatedURL: String? = nil
            if urlEditable {
                let raw = (data[idURL]?.stringValue ?? state.url).trimmingCharacters(in: .whitespacesAndNewlines)
                validatedURL = raw.isEmpty ? nil : RichTextEditorCoordinator.validatedButtonURL(raw)
                if validatedURL == nil {
                    return .fail(.fields([idURL: .shake]))
                }
            }
            var updated = button
            let label = data[idLabel]?.stringValue ?? state.label
            // An untouched label keeps the incoming rich runs; an edited one flattens to plain text
            // (the field edits a String — the accepted iOS limitation).
            if label != button.labelText {
                updated.label = label.isEmpty ? [] : [TextRun(text: label)]
            }
            if urlEditable, let url = validatedURL {
                updated.action = .url(url)
            }
            updated.color = state.color
            updated.isLink = state.isLink
            completion(updated)
            editor?.makeEditorFirstResponder()
            close?()
            return .none
        })
        // Keep the state in sync while typing, so a style tap does not rebuild the fields from stale text.
        controller.updateDatas = { data in
            updateState { st in
                var st = st
                st.label = data[idLabel]?.stringValue ?? st.label
                if urlEditable { st.url = data[idURL]?.stringValue ?? st.url }
                return st
            }
            return .none
        }
        let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: { [weak controller] in
            controller?.validateInputValues()
        }, singleButton: true)
        let modalController = InputDataModalController(controller, modalInteractions: modalInteractions,
                                                       size: NSMakeSize(340, 0))
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
            modalController?.close()
        })
        close = { [weak modalController] in
            modalController?.modal?.close()
        }
        controller.didAppear = { controller in
            controller.makeFirstResponderIfPossible(for: idLabel, focusIdentifier: nil, scrollDown: false, scrollIfNeeded: true)
        }
        showModal(with: modalController, for: context.window)
    }

    /// Shows a `•••` context menu for one media tile: Edit (images only, via EditImageModalController),
    /// Replace (re-pick a file), Delete (removes the tile or the whole single-media block).
    private static func presentMediaTileMenu(_ editor: RichTextEditorView, context ctx: MediaControlsContext,
                                             tileIndex: Int, accountContext context: any AccountContextProtocol,
                                             cache: MediaFileCache, disposable: MetaDisposable) {
        let isGroup = (ctx.kind == .collage || ctx.kind == .slider)
        let tileArg: Int? = isGroup ? tileIndex : nil
        let mediaID = editor.mediaID(forBlock: ctx.blockID, tileIndex: tileArg)
        let isImage = mediaID.flatMap { cache.media[$0] as? TelegramMediaImage } != nil
        let isVideo = (mediaID.flatMap { cache.media[$0] as? TelegramMediaFile })?.isVideo == true
        var items: [ContextMenuItem] = []
        if isImage, let mid = mediaID {
            items.append(ContextMenuItem(strings().richTextEditorEdit, handler: {
                presentMediaEditor(editor, ctx: ctx, tileIndex: tileIndex, isGroup: isGroup, mediaID: mid,
                                   accountContext: context, cache: cache, disposable: disposable)
            }, itemImage: MenuAnimation.menu_change_colors.value))
        }
        if isImage || isVideo {
            let on = editor.isMediaSpoiler(blockID: ctx.blockID, tileIndex: tileArg)
            items.append(ContextMenuItem(on ? strings().previewSenderSpoilerTooltipDisable : strings().previewSenderSpoilerTooltipEnable, handler: {
                editor.makeEditorFirstResponder()
                editor.setMediaSpoiler(blockID: ctx.blockID, tileIndex: tileArg, spoiler: !on)
            }, state: on ? .on : nil, itemImage: (on ? MenuAnimation.menu_eye : MenuAnimation.menu_eye_slash).value))
        }
        items.append(ContextMenuItem(strings().richTextEditorReplace, handler: {
            presentReplacePicker(editor, ctx: ctx, tileIndex: tileIndex, isGroup: isGroup,
                                 accountContext: context, cache: cache, disposable: disposable)
        }, itemImage: MenuAnimation.menu_shared_media.value))
        items.append(ContextMenuItem(strings().richTextEditorDelete, handler: {
            if isGroup { editor.makeEditorFirstResponder(); editor.removeCollageTile(groupID: ctx.blockID, index: tileIndex) }
            else { editor.removeMediaBlock(blockID: ctx.blockID) }
        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
        if let event = NSApp.currentEvent {
            ContextMenu.show(items: items, view: editor, event: event)
        }
    }

    /// Opens a single-file picker to replace one tile (or a single media block) with a new media asset.
    private static func presentReplacePicker(_ editor: RichTextEditorView, ctx: MediaControlsContext,
                                             tileIndex: Int, isGroup: Bool, accountContext context: any AccountContextProtocol,
                                             cache: MediaFileCache, disposable: MetaDisposable) {
        guard let window = editor.window,
              let originalMediaID = editor.mediaID(forBlock: ctx.blockID, tileIndex: isGroup ? tileIndex : nil) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [editor, panel] resp in
            guard resp == .OK, let url = panel.url else { return }
            disposable.set((Sender.generateMedia(for: MediaSenderContainer(path: url.path, isFile: false),
                                                  account: context.account, isSecretRelated: false)
                            |> deliverOnMainQueue).start(next: { [weak editor] media, _ in
                guard let editor = editor,
                      editor.mediaID(forBlock: ctx.blockID, tileIndex: isGroup ? tileIndex : nil) == originalMediaID else { return }
                let newID = "media-\(arc4random())"; cache.media[newID] = media
                editor.makeEditorFirstResponder()
                if isGroup { editor.replaceGroupMedia(groupID: ctx.blockID, index: tileIndex, newMediaID: newID) }
                else { editor.replaceMedia(blockID: ctx.blockID, newMediaID: newID) }
            }))
        }
    }

    /// Opens EditImageModalController for an image tile; on save, replaces the tile with the edited image.
    private static func presentMediaEditor(_ editor: RichTextEditorView, ctx: MediaControlsContext,
                                           tileIndex: Int, isGroup: Bool, mediaID: String,
                                           accountContext context: any AccountContextProtocol,
                                           cache: MediaFileCache, disposable: MetaDisposable) {
        guard editor.mediaID(forBlock: ctx.blockID, tileIndex: isGroup ? tileIndex : nil) == mediaID,
              let image = cache.media[mediaID] as? TelegramMediaImage,
              let resource = image.representationForDisplayAtSize(PixelDimensions(1280, 1280))?.resource else { return }
        // `resourceData` emits immediately with whatever is on disk — for a freshly picked image that can
        // be the `…_partial` file still being copied into the media box, whose path NSImage can't load.
        // Kick a fetch and wait for the COMPLETE file before opening the editor.
        let operation = DisposableSet()
        disposable.set(operation)
        operation.add((fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .image, reference: .standalone(resource: resource))).start())
        let editedMedia = context.account.postbox.mediaBox.resourceData(resource)
            |> filter { $0.complete }
            |> take(1)
            |> deliverOnMainQueue
            |> mapToSignal { [weak editor] data -> Signal<Media, NoError> in
                guard let editor,
                      editor.mediaID(forBlock: ctx.blockID, tileIndex: isGroup ? tileIndex : nil) == mediaID,
                      let path = link(path: data.path, ext: kMediaImageExt) else { return .complete() }
                let url = URL(fileURLWithPath: path)
                let editResult = ChatNavigationHooks.shared.editImageObserved(context, url, nil)
                return (editResult |> take(1) |> deliverOnMainQueue
                    |> mapToSignal { [weak editor] new, _ -> Signal<Media, NoError> in
                        guard let editor, new != url,
                              editor.mediaID(forBlock: ctx.blockID, tileIndex: isGroup ? tileIndex : nil) == mediaID else { return .complete() }
                        return (Sender.generateMedia(for: MediaSenderContainer(path: new.path, isFile: false), account: context.account, isSecretRelated: false)
                            |> map { $0.0 })
                    })
            }
            |> deliverOnMainQueue
        operation.add((editedMedia).start(next: { [weak editor] media in
            guard let editor,
                  editor.mediaID(forBlock: ctx.blockID, tileIndex: isGroup ? tileIndex : nil) == mediaID else { return }
            let newID = "media-\(arc4random())"
            cache.media[newID] = media
            editor.makeEditorFirstResponder()
            if isGroup { editor.replaceGroupMedia(groupID: ctx.blockID, index: tileIndex, newMediaID: newID) }
            else { editor.replaceMedia(blockID: ctx.blockID, newMediaID: newID) }
        }))
    }
}

// MARK: - LaTeX formula editor modal (input + live preview)

private struct LatexState: Equatable { var latex: String }
private let _id_latex_input = InputDataIdentifier("_id_latex_input")
private let _id_latex_preview = InputDataIdentifier("_id_latex_preview")

private func latexEntries(_ state: LatexState) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().richTextEditorLatexSection),
                         data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.latex), error: nil,
                          identifier: _id_latex_input, mode: .plain, data: InputDataRowData(viewType: .singleItem),
                          placeholder: nil, inputPlaceholder: "E=mc^2",
                          filter: { $0 }, limit: 1024))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().richTextEditorResultSection),
                         data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_latex_preview,
                           equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
        return LatexPreviewRowItem(initialSize, stableId: stableId, latex: state.latex, viewType: .singleItem)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

/// A two-section modal: a LaTeX input and a live preview rendered with the chat's SwiftMath pipeline.
/// `Apply` hands the (trimmed) LaTeX back; a blank string clears/skips (the editor's `insertFormula`
/// removes an existing formula on blank, inserts nothing on a blank new one).
public func RichTextLatexModalController(latex initial: String?, completion: @escaping (String) -> Void) -> InputDataModalController {
    let initialState = LatexState(latex: initial ?? "")
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((LatexState) -> LatexState) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    let dataSignal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: latexEntries(state))
    }

    var close: (() -> Void)? = nil

    let controller = InputDataController(dataSignal: dataSignal, title: strings().richTextEditorFormula, validateData: { data in
        let latex = (data[_id_latex_input]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        completion(latex)
        close?()
        return .none
    }, updateDatas: { data in
        updateState { current in
            var current = current
            current.latex = data[_id_latex_input]?.stringValue ?? ""
            return current
        }
        return .none
    })

    let modalInteractions = ModalInteractions(acceptTitle: strings().richTextEditorApply, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 320))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}

/// Renders the current LaTeX to a centered image (chat's `instantPageMathAttachment`); shows a faint
/// "E = mc²" ghost when empty and a red strings().richTextEditorInvalidFormula when the LaTeX doesn't parse. Re-created on each
/// keystroke (the entry's equatable is the state), so the preview tracks typing.
private final class LatexPreviewRowItem: GeneralRowItem {
    fileprivate let formulaImage: CGImage?
    fileprivate let formulaNaturalSize: NSSize
    fileprivate let messageLayout: TextViewLayout?
    private let verticalPad: CGFloat = 16
    private let latex: String

    init(_ initialSize: NSSize, stableId: AnyHashable, latex: String, viewType: GeneralViewType) {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latex = trimmed
        // Empty → a faint "E = mc²" ghost (rendered placeholder, like the input's "E=mc^2"); typed →
        // the live formula in the text colour; unparseable → a red strings().richTextEditorInvalidFormula.
        let renderLatex = trimmed.isEmpty ? "E=mc^2" : trimmed
        let renderColor = trimmed.isEmpty ? theme.colors.grayText.withAlphaComponent(0.35) : theme.colors.text
        if let att = instantPageMathAttachmentForAuthoring(latex: renderLatex, fontSize: 24, textColor: renderColor, mode: .block),
           let cg = att.rendered.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            formulaImage = cg; formulaNaturalSize = att.rendered.size; messageLayout = nil
        } else if trimmed.isEmpty {
            formulaImage = nil; formulaNaturalSize = .zero
            messageLayout = TextViewLayout(.initialize(string: strings().richTextEditorFormulaPreviewPlaceholder, color: theme.colors.grayText, font: .normal(.text)), alignment: .center)
        } else {
            formulaImage = nil; formulaNaturalSize = .zero
            messageLayout = TextViewLayout(.initialize(string: strings().richTextEditorInvalidFormula, color: theme.colors.redUI, font: .normal(.text)), alignment: .center)
        }
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    private var contentWidth: CGFloat { blockWidth - viewType.innerInset.left - viewType.innerInset.right }

    /// The formula image fitted to the content width (scaled down only when wider).
    fileprivate var fittedFormulaSize: NSSize {
        guard formulaImage != nil, formulaNaturalSize.width > 0 else { return .zero }
        guard formulaNaturalSize.width > contentWidth else { return formulaNaturalSize }
        let scale = contentWidth / formulaNaturalSize.width
        return NSMakeSize(contentWidth, floor(formulaNaturalSize.height * scale))
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        messageLayout?.measure(width: contentWidth)
        return true
    }

    override var height: CGFloat {
        let content = formulaImage != nil ? fittedFormulaSize.height : (messageLayout?.layoutSize.height ?? 20)
        return max(60, content + verticalPad * 2)
    }

    override func viewClass() -> AnyClass { return LatexPreviewRowView.self }

    override var accessibilityLabel: String? {
        if let messageLayout {
            return messageLayout.attributedString.string
        }
        return latex
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class LatexPreviewRowView: GeneralContainableRowView {
    private let imageView = ImageView()
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        imageView.isAccessibilityDecorative = true
        addSubview(imageView)
        addSubview(textView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? LatexPreviewRowItem else { return }
        if let img = item.formulaImage {
            imageView.image = img
            imageView.isHidden = false
            textView.isHidden = true
        } else {
            imageView.isHidden = true
            textView.isHidden = false
            if let layout = item.messageLayout { textView.update(layout) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? LatexPreviewRowItem else { return }
        if item.formulaImage != nil {
            let size = item.fittedFormulaSize
            imageView.frame = NSRect(x: (containerView.frame.width - size.width) / 2,
                                     y: (containerView.frame.height - size.height) / 2,
                                     width: size.width, height: size.height)
        } else if let layout = item.messageLayout {
            textView.update(layout)
            textView.center()
        }
    }
}

// MARK: - Spoiler effect backed by the app's InvisibleInkDustView

@available(macOS 12, *)
public final class RichEditorSpoilerEffect: SpoilerEffect {
    private let dust = InvisibleInkDustView()
    public init() {
    }
    public var nsView: NSView { dust }
    public var isRevealed: Bool { dust.isRevealed }
    public func update(size: CGSize, color: NSColor, lineRects: [CGRect], wordRects: [CGRect]) {
        dust.update(size: size, color: color, textColor: color, rects: lineRects, wordRects: wordRects)
    }
    public func dissolve(explodingAt point: CGPoint?, completion: @escaping () -> Void) {
        dust.update(revealed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completion() }
    }
}

// MARK: - Generic hosted-view InputData row (reparents a given NSView into the row container)

/// An InputData row that hosts an externally-owned, persistent NSView (the editor or the toolbar).
/// Height is either fixed or derived from a width-dependent closure.
private final class HostedViewRowItem: GeneralRowItem {
    fileprivate let hostedView: NSView
    fileprivate let fixedHeight: CGFloat?
    fileprivate let heightForWidth: ((CGFloat) -> CGFloat)?
    fileprivate let initialFirstResponder: (() -> NSResponder?)?

    init(_ initialSize: NSSize, stableId: AnyHashable, hostedView: NSView, viewType: GeneralViewType, fixedHeight: CGFloat? = nil, heightForWidth: ((CGFloat) -> CGFloat)? = nil, initialFirstResponder: (() -> NSResponder?)? = nil) {
        self.hostedView = hostedView
        self.fixedHeight = fixedHeight
        self.heightForWidth = heightForWidth
        self.initialFirstResponder = initialFirstResponder
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: NSEdgeInsets(left: 6, right: 6))
    }

    override var height: CGFloat {
        if let heightForWidth = heightForWidth {
            return heightForWidth(blockWidth)
        }
        return fixedHeight ?? 200
    }

    override func viewClass() -> AnyClass {
        return HostedViewRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverChatEditor
    }
}

private final class HostedViewRowView: GeneralRowView {
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false   // let the toolbar's glass-pill shadows render past the row bounds
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? HostedViewRowItem else { return }
        if item.hostedView.superview !== self {
            addSubview(item.hostedView)   // flat row: no inner container — the view is the row's content
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? HostedViewRowItem else { return }
        let blockWidth = item.blockWidth
        let minX = (frame.width - blockWidth) / 2
        item.hostedView.frame = NSRect(x: minX, y: 0, width: blockWidth, height: frame.height)
    }

    override func hasFirstResponder() -> Bool {
        return (item as? HostedViewRowItem)?.initialFirstResponder != nil
    }

    override var firstResponder: NSResponder? {
        return (item as? HostedViewRowItem)?.initialFirstResponder?()
    }

    override var backdorColor: NSColor {
        return .clear
    }
}

/// A view-less spacer row (reserves the pinned toolbar's height at the top of the table). Item closures
/// run on the prepare queue, so this must not create any NSView.
private final class ToolbarSpacerRowItem: GeneralRowItem {
    private let heightForWidth: (CGFloat) -> CGFloat
    init(_ initialSize: NSSize, stableId: AnyHashable, heightForWidth: @escaping (CGFloat) -> CGFloat) {
        self.heightForWidth = heightForWidth
        super.init(initialSize, stableId: stableId, viewType: .legacy, inset: NSEdgeInsets(left: 6, right: 6))
    }
    override var height: CGFloat { heightForWidth(blockWidth) }
    override func viewClass() -> AnyClass { ToolbarSpacerRowView.self }
    override var accessibilityIsSpacer: Bool { true }
}

private final class ToolbarSpacerRowView: GeneralRowView {
    // InputDataController probes every visible row's responder, not only rows that advertise one.
    // The spacer must opt out so the editor canvas is selected as the first input responder.
    override var firstResponder: NSResponder? { nil }
    override var backdorColor: NSColor { .clear }
}

// MARK: - Toolbar (glass pills: [close · undo]  ·  [tools]  ·  send)

/// The floating editor toolbar from the new design: a left glass pill (close + undo), a centered glass
/// pill of tool buttons, and a trailing accent send button. Frosted "liquid glass" via `LiquidGlassView`
/// (falls back to a blurred/solid rounded background on systems without it). Manual frame layout.
public final class EditorToolbarView: NSView {
    private let leftButtons: [NSView]
    private let aiButton: NSView?
    private let centerButtons: [NSView]
    private let sendButton: NSView
    private let leftPill = LiquidGlassView(frame: .zero, cornerRadius: 19, hasShadow: true, hasBorder: true)
    private let aiPill = LiquidGlassView(frame: .zero, cornerRadius: 19, hasShadow: true, hasBorder: true)
    private let centerPill = LiquidGlassView(frame: .zero, cornerRadius: 19, hasShadow: true, hasBorder: true)

    private let toolbarHeight: CGFloat = 52
    private let pillHeight: CGFloat = 38
    private let buttonSize: CGFloat = 30
    private let gap: CGFloat = 2
    private let pad: CGFloat = 5          // horizontal padding inside a pill
    private let inset: CGFloat = 10       // left/right edge inset (the row adds ~6pt centering, so ≈ the top inset)
    private let aiGap: CGFloat = 8        // minimum inter-section gap (sections space out equally from the free width)
    private let sendSize: CGFloat = 38    // same height as the pills

    public init(left: [NSView], ai: NSView? = nil, center: [NSView], send: NSView) {
        self.leftButtons = left
        self.aiButton = ai
        self.centerButtons = center
        self.sendButton = send
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        addSubview(leftPill)             // pills below the buttons
        if ai != nil { addSubview(aiPill) }
        addSubview(centerPill)
        for b in left { addSubview(b) }
        if let ai { addSubview(ai) }
        for b in center { addSubview(b) }
        addSubview(send)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override var isFlipped: Bool { true }

    public func height(forWidth width: CGFloat) -> CGFloat { toolbarHeight }

    /// Distance from the frame's bottom edge to the pills' visual bottom (they're centered in the frame) —
    /// lets overlays below (the premium toast) space themselves from the VISIBLE pill edge.
    public var contentBottomInset: CGFloat { (toolbarHeight - pillHeight) / 2 }

    private func pillWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return pad * 2 + CGFloat(count) * buttonSize + CGFloat(count - 1) * gap
    }

    private func layoutButtons(_ buttons: [NSView], in pill: NSRect) {
        let y = pill.minY + (pill.height - buttonSize) / 2
        var x = pill.minX + pad
        for b in buttons {
            b.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
            x += buttonSize + gap
        }
    }

    // Autoresizing changes our frame (the editor grows/shrinks with the window) but doesn't re-run
    // `layout()`, so re-lay-out on every resize — otherwise send stays pinned to the old right edge.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let pillY = (toolbarHeight - pillHeight) / 2
        let leftW = pillWidth(leftButtons.count)
        let centerW = pillWidth(centerButtons.count)
        // Pack the left pill, AI circle and center pill together at a FIXED gap on the leading edge, and
        // pin send to the trailing edge — the sections keep constant spacing regardless of window width
        // instead of stretching to fill it.
        let gap = aiGap

        leftPill.frame = NSRect(x: inset, y: pillY, width: leftW, height: pillHeight)
        layoutButtons(leftButtons, in: leftPill.frame)

        // Standalone AI circle: its own round glass pill right after the left pill.
        var leadingEdge = leftPill.frame.maxX
        if let ai = aiButton {
            aiPill.frame = NSRect(x: leadingEdge + gap, y: pillY, width: pillHeight, height: pillHeight)
            ai.frame = NSRect(x: aiPill.frame.minX + (pillHeight - buttonSize) / 2,
                              y: aiPill.frame.minY + (pillHeight - buttonSize) / 2,
                              width: buttonSize, height: buttonSize)
            leadingEdge = aiPill.frame.maxX
        }

        sendButton.frame = NSRect(x: bounds.width - inset - sendSize, y: (toolbarHeight - sendSize) / 2, width: sendSize, height: sendSize)

        centerPill.frame = NSRect(x: leadingEdge + gap, y: pillY, width: centerW, height: pillHeight)
        layoutButtons(centerButtons, in: centerPill.frame)
    }
}

// MARK: - Toolbar control helpers

/// A reference box holding picked custom-emoji files (fileId string → file) shared between the editor's
/// emoji-view provider and the picker callback, so it survives as a captured value (not via `self`).
@available(macOS 12, *)
private final class EmojiFileCache {
    var files: [String: TelegramMediaFile] = [:]
}

/// Picked attachment media (file/audio/map) keyed by the opaque `mediaID` carried in the editor's media
/// block, shared between the file picker and the media-block view provider (mirrors `EmojiFileCache`).
@available(macOS 12, *)
private final class MediaFileCache {
    var media: [String: Media] = [:]
}

/// The editor modal, sized PROPORTIONALLY to the window (with side margins, clamped) so it grows and
/// shrinks as the window is resized — instead of the base modal's fixed-cap width. Only the width cap is
/// overridden; the base `measure`/`updateSize` still own the height and the actual resize.
private final class RichEditorModalController: InputDataModalController {
    /// Fired AFTER a resize (once the table width is final) so the pinned floating toolbar can re-frame
    /// itself to the new width — autoresizing inside the table view doesn't do this reliably.
    var onResize: (() -> Void)?
    private func applyWidth(_ available: CGFloat) {
        let margin: CGFloat = 32
        let proportional = floor(available * 0.72)
        let width = min(available - margin, max(420, min(800, proportional)))
        current._frameRect.size.width = max(280, width)
    }
    override func measure(size: NSSize) {
        applyWidth(size.width)
        super.measure(size: size)
        onResize?()
    }
    override func updateSize(_ animated: Bool) {
        if let contentSize = modal?.window.contentView?.frame.size {
            applyWidth(contentSize.width)
        }
        super.updateSize(animated)
        onResize?()
    }
}

/// A boxed callback so the toolbar's close/send buttons (built in the coordinator's init, before the
/// modal exists) can fire actions the controller wires up afterward.
public final class ActionBox { var action: (() -> Void)? }

/// A square icon button (TGUIKit `ImageButton`, a `Control` — its click handler receives the control,
/// for anchoring menus/popovers). Doesn't accept first responder, so the editor keeps focus.
private final class EditorIconButton: ImageButton {
    init(image: CGImage, size: CGFloat = 30, click: @escaping (Control) -> Void) {
        super.init(frame: NSMakeRect(0, 0, size, size))
        self.autohighlight = false
        self.scaleOnClick = true
        self.set(image: image, for: .Normal)
        self.set(handler: click, for: .Click)
    }

    required init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var acceptsFirstResponder: Bool { false }
}

/// Glass overlay pills drawn over a media area (collage, slider, or single image/video). The view spans
/// the full media area; `hitTest` returns a button only when the click is inside a pill so non-pill
/// clicks fall through to the tile select overlay below.
/// Coordinate convention: `mediaBlockHost` (and therefore this view) is a FLIPPED view (y grows DOWN),
/// so top = low y. Tile frames are in local (media-area-relative) flipped coordinates.
@available(macOS 12, *)
private final class MediaGroupControlsView: NSView {
    private let onMore: (Int) -> Void
    private let onAdd: () -> Void
    private let onToggle: (() -> Void)?
    private var buttons: [ImageButton] = []

    init(context: MediaControlsContext, accent: NSColor,
         moreIcon: CGImage, addIcon: CGImage, toggleIcon: CGImage?, toggleTooltip: String?,
         onMore: @escaping (Int) -> Void, onAdd: @escaping () -> Void, onToggle: (() -> Void)?) {
        self.onMore = onMore; self.onAdd = onAdd; self.onToggle = onToggle
        super.init(frame: CGRect(origin: .zero, size: context.areaSize))
        wantsLayer = true

        let pill: CGFloat = 36, inset: CGFloat = 6

        func glassButton(_ image: CGImage) -> ImageButton {
            let b = ImageButton()
            b.set(image: image, for: .Normal)
            b.setFrameSize(NSMakeSize(pill, pill))
            b.setGlassEffect(size: NSMakeSize(pill, pill), tintColor: nil)
            addSubview(b)
            buttons.append(b)
            return b
        }

        // ••• per tile at the tile's top-left (flipped: top = low y, so minY + inset).
        for (i, tile) in context.tileFrames.enumerated() {
            let b = glassButton(moreIcon)
            b.setFrameOrigin(NSMakePoint(tile.minX + inset, tile.minY + inset))
            b.appTooltip = strings().richTextEditorMore
            b.set(handler: { [weak self] _ in self?.onMore(i) }, for: .Click)
        }

        // + (add) and toggle at the media area's top-right (flipped: y = inset from the top edge).
        var x = context.areaSize.width - inset - pill
        let topY: CGFloat = inset
        if let toggleIcon = toggleIcon, let onToggle = onToggle {
            let t = glassButton(toggleIcon)
            t.setFrameOrigin(NSMakePoint(x, topY))
            t.appTooltip = toggleTooltip
            t.set(handler: { _ in onToggle() }, for: .Click)
            x -= (pill + inset)
        }
        let add = glassButton(addIcon)
        add.setFrameOrigin(NSMakePoint(x, topY))
        add.appTooltip = strings().richTextEditorAddMedia
        add.set(handler: { _ in onAdd() }, for: .Click)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Flipped so this view's coordinates match the (flipped) canvas host: y grows DOWN, y=0 is the TOP.
    // The button origins above use the top=low-y convention, so this puts the pills at the TOP of each
    // tile / the media area (an unflipped view would render those low-y origins at the bottom).
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for b in buttons where b.frame.contains(local) { return b }
        return nil
    }
}

/// A static-image drawable for `ContextMenuItem.itemImage`, so the format popup's items show the
/// Icon_RichText_* glyphs, re-tinted by the menu (`setColor`) to match hover/selection.
private final class RichTextMenuIcon: NSView, AppMenuItemImageDrawable {
    private let icon: NSImage
    private let imageView = ImageView()
    init(_ icon: NSImage) {
        self.icon = icon
        super.init(frame: NSMakeRect(0, 0, 18, 18))
        imageView.isAccessibilityDecorative = true
        addSubview(imageView)
        imageView.frame = bounds
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    func updateState(_ controlState: ControlState) {}
    func setColor(_ color: NSColor) { imageView.image = icon.precomposed(color) }
    func isEqual(to other: ContextMenuItem) -> Bool { false }
}

/// Converts the chat input's private pasteboard payload (`.kInApp`, an encoded `ChatTextInputState`)
/// into editor blocks — the paste bridge that keeps custom emoji and inline formatting when text copied
/// from the plain composer is pasted into the rich editor. nil when no such payload is on the pasteboard.
@available(macOS 12, *)
public func richTextBlocksFromInAppPasteboard() -> [Block]? {
    guard let data = NSPasteboard.general.data(forType: .kInApp) else { return nil }
    let decoder = AdaptedPostboxDecoder()
    guard let state = try? decoder.decode(ChatTextInputState.self, from: data), !state.inputText.isEmpty else { return nil }
    return richTextDocument(text: state.inputText, entities: state.messageTextEntities()).blocks
}

private final class HeadingMenuItem: ContextMenuItem {
    fileprivate let displayTitle: NSAttributedString
    init(_ title: String, displayTitle: NSAttributedString, handler: @escaping () -> Void, state: NSControl.StateValue?, itemImage: ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)?, locked: Bool) {
        self.displayTitle = displayTitle
        super.init(title, handler: handler, state: state, itemImage: itemImage, attributedTitle: displayTitle, customTextView: {
            let layout = TextViewLayout(displayTitle, maximumNumberOfLines: 1)
            layout.measure(width: .greatestFiniteMagnitude)
            let textView = TextView()
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            textView.disableBackgroundDrawing = true
            textView.isEventLess = true
            textView.update(layout)
            return textView
        }, locked: locked)
    }
    required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func rowItem(presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction) -> TableRowItem {
        return HeadingMenuRowItem(.zero, item: self, interaction: interaction, presentation: presentation)
    }
}

private final class HeadingMenuRowItem: AppMenuRowItem {
    private let displayLayout: TextViewLayout
    init(_ initialSize: NSSize, item: HeadingMenuItem, interaction: AppMenuBasicItem.Interaction, presentation: AppMenu.Presentation) {
        self.displayLayout = TextViewLayout(item.displayTitle, maximumNumberOfLines: 1)
        self.displayLayout.measure(width: .greatestFiniteMagnitude)
        super.init(initialSize, item: item, interaction: interaction, presentation: presentation)
    }
    required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override var effectiveSize: NSSize {
        var size = super.effectiveSize
        let delta = displayLayout.layoutSize.width - text.layoutSize.width
        if delta > 0 {
            size.width += ceil(delta)
        }
        return size
    }
    override var height: CGFloat {
        return max(super.height, ceil(displayLayout.layoutSize.height) + 10)
    }
}

// MARK: - Button property sheet: live V2 preview row

/// A REAL V2 pill for the button property sheet: builds a one-block `InstantPage` carrying the edited
/// button and renders it through the chat's own `InstantPageV2View` — nothing is mocked, so what the
/// author sees is what the recipient gets (the iOS `ButtonPreviewItemComponent`, in InputData form;
/// same shape as `AiResultRowItem`).
private final class ButtonPreviewRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate private(set) var richLayout: InstantPageV2Layout?
    fileprivate private(set) var richTheme: InstantPageTheme?
    fileprivate private(set) var richContentHeight: CGFloat = 0
    private let button: ButtonRef

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, button: ButtonRef, viewType: GeneralViewType) {
        self.context = context
        self.button = button
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let availableWidth = blockWidth - viewType.innerInset.left - viewType.innerInset.right
        // The label falls back to the field placeholder so an unnamed button still previews as a pill.
        let label = button.labelText.isEmpty ? strings().richTextEditorButtonLabelPlaceholder : button.labelText
        let page = InstantPage(
            blocks: [.buttonRow(alignment: .center, buttons: [InstantPageButton(
                text: .plain(label),
                action: replyMarkupButtonAction(from: button.action),
                color: replyMarkupColor(from: button.color),
                isLink: button.isLink
            )])],
            media: [:], isComplete: true, rtl: false, url: "", views: nil
        )
        let webpage = TelegramMediaWebpage(
            webpageId: MediaId(namespace: 0, id: 0),
            content: .Loaded(TelegramMediaWebpageLoadedContent(
                url: "", displayUrl: "", hash: 0, type: nil,
                websiteName: nil, title: nil, text: nil,
                embedUrl: nil, embedType: nil, embedSize: nil, duration: nil,
                author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false,
                image: nil, file: nil, story: nil, attributes: [],
                instantPage: page
            ))
        )
        let ipTheme = ChatRichTextRowItem.buildInstantPageTheme(for: theme, isIncoming: true, isBubbled: false)
        let layout = layoutInstantPageV2(webpage: webpage, instantPage: page, boundingWidth: max(40, availableWidth), horizontalInset: 0, theme: ipTheme)
        self.richLayout = layout
        self.richTheme = ipTheme
        self.richContentHeight = (layout.items.map { $0.frame.maxY }.max() ?? layout.contentSize.height)
        return result
    }

    override var height: CGFloat {
        return richContentHeight + viewType.innerInset.top + viewType.innerInset.bottom + 8
    }

    override func viewClass() -> AnyClass { return ButtonPreviewRowView.self }

    override var accessibilityLabel: String? {
        return button.labelText.isEmpty ? strings().richTextEditorButtonLabelPlaceholder : button.labelText
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class ButtonPreviewRowView: GeneralContainableRowView {
    private var richView: InstantPageV2View? = nil

    /// The preview floats on the sheet background — no white card behind the pill.
    override var backdorColor: NSColor { .clear }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ButtonPreviewRowItem else { return }
        if let richLayout = item.richLayout, let richTheme = item.richTheme {
            let current: InstantPageV2View
            if let view = self.richView {
                current = view
            } else {
                current = InstantPageV2View(frame: .zero)
                addSubview(current)
                self.richView = current
            }
            current.context = item.context
            current.update(layout: richLayout, theme: richTheme)
        } else if let view = self.richView {
            view.removeFromSuperview()
            self.richView = nil
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? ButtonPreviewRowItem else { return }
        if let richView = richView {
            let availableWidth = item.blockWidth - item.viewType.innerInset.left - item.viewType.innerInset.right
            richView.frame = CGRect(origin: CGPoint(x: item.viewType.innerInset.left, y: item.viewType.innerInset.top + 4),
                                    size: NSMakeSize(max(40, availableWidth), item.richContentHeight))
        }
    }
}
