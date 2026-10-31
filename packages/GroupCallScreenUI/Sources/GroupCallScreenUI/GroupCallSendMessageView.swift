import Cocoa
import TelegramCallsCore
import TGUIKit
import InputView
import TelegramCore
import Postbox
import SwiftSignalKit
import ChatModeTypes
import EntertainmentUI
import InAppSettings
import InputTextView
import Localization
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import MessageUtils
import Strings
import InlineStickerLayer

public struct GroupCallReactionAction {
    public let item: UpdateMessageReaction
    public let fromRect: CGRect?
}

private func reactions(context: any AccountContextProtocol, react: @escaping(GroupCallReactionAction)->Void, onClose: @escaping()->Void, selectedItems: [EmojiesSectionRowItem.SelectedItem] = [], parentWindow: Window) -> Signal<NSView?, NoError> {
    return reactionsValues(context: context, react: react, onClose: onClose, selectedItems: selectedItems, parentWindow: parentWindow) |> map { $0?.1 }
}

private func reactionsValues(context: any AccountContextProtocol, react: @escaping(GroupCallReactionAction)->Void, onClose: @escaping()->Void, name: String = "", selectedItems: [EmojiesSectionRowItem.SelectedItem] = [], parentWindow: Window) -> Signal<(Window, NSView)?, NoError> {
    
    
    let builtin = context.reactions.stateValue
    
    
    var orderedItemListCollectionIds: [Int32] = []
    
    orderedItemListCollectionIds.append(Namespaces.OrderedItemList.CloudRecentReactions)
    orderedItemListCollectionIds.append(Namespaces.OrderedItemList.CloudTopReactions)

    let reactions:Signal<[RecentReactionItem], NoError> = context.diceCache.emojies_reactions(100) |> map { view in
        
        var recentReactionsView: OrderedItemListView?
        var topReactionsView: OrderedItemListView?
        for orderedView in view.orderedItemListsViews {
            if orderedView.collectionId == Namespaces.OrderedItemList.CloudRecentReactions {
                recentReactionsView = orderedView
            } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudTopReactions {
                topReactionsView = orderedView
            }
        }
        var recentReactionsItems:[RecentReactionItem] = []
        var topReactionsItems:[RecentReactionItem] = []

        if let recentReactionsView = recentReactionsView {
            for item in recentReactionsView.items {
                guard let item = item.contents.get(RecentReactionItem.self) else {
                    continue
                }
                recentReactionsItems.append(item)
            }
        }
        if let topReactionsView = topReactionsView {
            for item in topReactionsView.items {
                guard let item = item.contents.get(RecentReactionItem.self) else {
                    continue
                }
                topReactionsItems.append(item)
            }
        }
        return topReactionsItems.filter { value in
            if context.isPremium {
                return true
            } else {
                if case .custom = value.content {
                    return false
                } else {
                    return true
                }
            }
        }
    }
    
    
    let signal = combineLatest(queue: .mainQueue(), builtin, reactions)
    |> take(1)

    return signal |> map { builtin, reactions -> (Window, NSView)? in
        let enabled = builtin?.enabled ?? []

        var available:[ContextReaction] = []
        
        
        let accessToAll: Bool = true
        
        available = reactions.compactMap { value in
            switch value.content {
            case let .builtin(emoji):
                if let generic = enabled.first(where: { $0.value.emojiString == emoji }) {
                    return .builtin(value: generic.value, staticFile: generic.staticIcon._parse(), selectFile: generic.selectAnimation._parse(), appearFile: generic.appearAnimation._parse(), isSelected: selectedItems.contains(where: { $0.source == .builtin(emoji) }))
                } else {
                    return nil
                }
            case let .custom(file):
                return .custom(value: .custom(file._parse().fileId.id), fileId: file._parse().fileId.id, file._parse(), isSelected: selectedItems.contains(where: { $0.source == .custom(file._parse().fileId.id) }))
            case .stars:
                return nil
            }
        }
        
        
        guard !available.isEmpty else {
            return nil
        }
        
        if accessToAll {
            available = Array(available.prefix(7))
        }
        
        let width = GroupCallScreenUIHooks.shared.reactionsListWidth(available.count, 7, accessToAll)
        
        
        let rect = NSMakeRect(0, 0, width + 20 + (accessToAll ? 0 : 20), 40 + 20)
        
        
        let panel = MenuPanelWindow(contentRect: rect, styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
       
        

        let reveal:((NSView & StickerFramesCollector)->Void)? = { view in
            GroupCallScreenUIHooks.shared.showReactionsWindow(context, context.peerId, { sticker, fromRect in
                let value: UpdateMessageReaction
                if let bundle = sticker.file._parse().stickerText {
                    value = .builtin(bundle)
                } else {
                    value = .custom(fileId: sticker.file._parse().fileId.id, file: sticker.file._parse())
                }
                react(.init(item: value, fromRect: fromRect))
                onClose()
            }, onClose, TelegramThemeHooks.shared.darkAppearance(), name, parentWindow, view)
        }
        
        
                
        let view = GroupCallScreenUIHooks.shared.makeReactionsListView(rect, context, available, { value, checkPrem, fromRect in
            react(.init(item: value.toUpdate(), fromRect: fromRect))
            onClose()
        }, reveal, TelegramThemeHooks.shared.darkAppearance(), parentWindow)
        
        return (panel, view)
    } |> deliverOnMainQueue
}


public final class GroupCallSendMessageView : View {
    
    public enum InputState : Equatable {
        case focus
        case none
    }

    
    private let backgroundView: Control
    private var arguments: GroupCallUIArguments?
    private var state: GroupCallUIState.Messages?
    
    public let textView: UITextView
    public let textContainer = View()
    private var glassInputView: NSView?
    private let inputContextContainer = View()
    
    private let sendButton = ImageButton()
    private let emojiButton = ImageButton()
    
    fileprivate let textInteractions: TextView_Interactions = .init()
    
    public private(set) var inputState: InputState = .none {
        didSet {
            if oldValue != inputState {
                inputStateDidUpdate?(inputState)
            }
        }
    }
    
    private var inputStateDidUpdate:((InputState)->Void)? = nil
    
    private var reactionsView: NSView?
    private let reactionsDisposable = MetaDisposable()
    private var reactionsInited: Bool = false
    
    private let reactionsContainer = View()
    private var emoji: GroupCallEmojiesController?
    
    public var controlsRect: NSRect = .zero

    deinit {
        reactionsDisposable.dispose()
    }
    
    private var textInputState: Updated_ChatTextInputState = .init()
    public func set(_ state: Updated_ChatTextInputState) {
        self.textInputState = state
        
        self.updateLayout(size: self.frame.size, transition: .animated(duration: 0.2, curve: .easeOut))
    }
    
    public init(frame frameRect: NSRect, controlsRect: CGRect) {
        self.controlsRect = controlsRect
        backgroundView = .init(frame: frameRect.size.bounds)
        self.textView = UITextView(frame: NSMakeRect(0, 0, 100, 34), interactions: textInteractions)
        super.init(frame: frameRect)
        addSubview(backgroundView)
        
        addSubview(textContainer)
        addSubview(inputContextContainer)
        
        addSubview(reactionsContainer)
        
        reactionsContainer.setFrameSize(NSMakeSize(350, 50))

        
        backgroundView.backgroundColor = NSColor.blackTransparent
        
        backgroundView.setSingle(handler: { [weak self] _ in
            self?.arguments?.message(nil)
        }, for: .Click)
        
        textContainer.addSubview(textView)
        
        textView.backgroundColor = .clear
        
        textContainer.backgroundColor = .clear
        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: true, hasBorder: true, forceAppearance: .forceDark)
        textContainer.addSubview(glass, positioned: .below, relativeTo: textContainer.subviews.first)
        glassInputView = glass

        textContainer.addSubview(sendButton)
        textContainer.addSubview(emojiButton)

        textContainer.layer?.cornerRadius = 20
        
        self.textView.inputView.appearance = TelegramThemeHooks.shared.darkAppearance().appearance
        
        self.textView.interactions.max_height = 200
        self.textView.interactions.min_height = 34
        
        sendButton.set(image: GroupCallTheme.send_message_image, for: .Normal)
        sendButton.setAccessibilityLabel(strings().voiceOverMessageContextSend)
        emojiButton.setAccessibilityLabel(strings().voiceOverCommonEmoji)
        sendButton.sizeToFit()
        sendButton.autohighlight = false
        sendButton.scaleOnClick = true
        
        emojiButton.set(image: GroupCallTheme.emoji_image_active, for: .Normal)
        emojiButton.sizeToFit()
        emojiButton.autohighlight = false
        emojiButton.scaleOnClick = true


        textView.placeholder = strings().groupCallInputPlaceholder

        emojiButton.set(handler: { [weak self] control in
            if let emoji = self?.emoji {
                showPopover(for: control, with: emoji)
            }
        }, for: .Hover)
        
        sendButton.set(handler: { [weak self] control in
            self?.sendMessage()
        }, for: .Click)
        
        
        self.updateLayout(size: self.frame.size, transition: .immediate)
        
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self.textView.inputView)
    }
    
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        
        if let window = newWindow as? Window {
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.textView.inputApplyTransform(.attribute(TextInputAttributes.bold))
                return .invoked
            }, with: self, for: .B, priority: .modal, modifierFlags: [.command])

            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.textView.inputApplyTransform(.attribute(TextInputAttributes.underline))
                return .invoked
            }, with: self, for: .U, priority: .modal, modifierFlags: [.shift, .command])
            
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.textView.inputApplyTransform(.attribute(TextInputAttributes.spoiler))
                return .invoked
            }, with: self, for: .P, priority: .modal, modifierFlags: [.shift, .command])
            
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.textView.inputApplyTransform(.attribute(TextInputAttributes.strikethrough))
                return .invoked
            }, with: self, for: .X, priority: .modal, modifierFlags: [.shift, .command])
            
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.textView.inputApplyTransform(.clear)
                return .invoked
            }, with: self, for: .Backslash, priority: .modal, modifierFlags: [.command])
            
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.textView.inputApplyTransform(.url)
                return .invoked
            }, with: self, for: .U, priority: .modal, modifierFlags: [.command])
            
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.textView.inputApplyTransform(.attribute(TextInputAttributes.italic))
                return .invoked
            }, with: self, for: .I, priority: .modal, modifierFlags: [.command])
        } else {
            _window?.removeAllHandlers(for: self)
        }
    }
    
    private func sendMessage() {
        let text = textView.inputTextState
        self.textView.set(.init())
        self.arguments?.message(text)

    }
    
    public func textViewSize(_ width: CGFloat) -> (NSSize, CGFloat) {
        let w = width
        let height = self.textView.height(for: w)
        return (NSMakeSize(w, min(max(height, textView.min_height), textView.max_height)), height)
    }
    
    
    public func textViewIsTypingEnabled() -> Bool {
        return true
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: backgroundView, frame: size.bounds)
        
        
        
        let (textSize, textHeight) = textViewSize(320 - 50)
        
        var textRect = textSize.bounds
        textRect.origin.x = controlsRect.minX
        textRect.origin.y = (controlsRect.minY + 110) - textRect.height
        
        //textRect.insetBy(dx:0, dy: -3)
        transition.updateFrame(view: textContainer, frame: NSMakeRect(controlsRect.minX + 10, textRect.origin.y, controlsRect.width - 20, textRect.height + 6))
        
        transition.updateFrame(view: textView, frame: NSMakeRect(10, 3, textRect.width - 35, textRect.height))
        textView.updateLayout(size: textRect.size, textHeight: textHeight, transition: transition)
        
        
        if let glassInputView {
            transition.updateFrame(view: glassInputView, frame: textContainer.bounds)
            (glassInputView as? LiquidGlassView)?.updateLayout(size: textContainer.bounds.size, transition: transition)
        }
        transition.updateFrame(view: sendButton, frame: sendButton.centerFrameY(x: textContainer.frame.width - sendButton.frame.width - 10))
        transition.updateFrame(view: emojiButton, frame: emojiButton.centerFrameY(x: sendButton.frame.minX - sendButton.frame.width - 15))
        
        
        var reactRect = reactionsContainer.frame
        reactRect.origin.x = floorToScreenPixels(textContainer.frame.minX + (textContainer.frame.width - reactRect.width) / 2)
        reactRect.origin.y = textContainer.frame.minY - reactionsContainer.frame.height - 10
        
        transition.updateFrame(view: reactionsContainer, frame: reactRect)

    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func textViewEnterPressed(_ event: NSEvent) -> Bool {
        if FastSettings.checkSendingAbility(for: event) {
            self.sendMessage()
            return true
        }
        return false

    }
    
    public func responderDidUpdate() {
        
        self.inputState = .focus
        self.updateInputState()
       // self.textView.update(true)
        DispatchQueue.main.async {
            self.textView.setToEnd()
        }
    }
    
    public func updateInputState(animated: Bool = true) {
        
    }
    
    private func makeReactions(arguments: GroupCallUIArguments) {
        if !self.reactionsInited, let _window {
            self.reactionsInited = true
            var reacted: Bool = false
            if let context = arguments.getContext() {
                reactionsDisposable.set(reactions(context: context, react: { action in
                    arguments.messageReact(action)
                    reacted = true
                }, onClose: {
                    if !reacted {
                        arguments.message(nil)
                    }
                }, parentWindow: _window).start(next: { [weak self] view in
                    if let view {
                        self?.reactionsView = view
                        self?.reactionsContainer.addSubview(view)
                        view.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
                        view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }))
                
                let emoji = GroupCallScreenUIHooks.shared.makeEmojies(context, TelegramThemeHooks.shared.darkAppearance())
                self.emoji = emoji
            
                let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
                
                interactions.sendEmoji = { [weak self] emoji, fromRect in
                    let updatedState = self?.textView.interactions.insertText(.initialize(string: emoji))
                    if let updatedState {
                        self?.textView.set(updatedState.textInputState())
                    }
                    _ = self?.window?.makeFirstResponder(self?.textView.inputView)
                }
                interactions.sendAnimatedEmoji = { [weak self] sticker, _, _, _, fromRect in
                    let text = (sticker.file._parse().customEmojiText ?? sticker.file._parse().stickerText ?? clown).fixed
                    
                    let updatedState = self?.textView.interactions.insertText(.makeAnimated(sticker.file._parse(), text: text))
                    if let updatedState {
                        self?.textView.set(updatedState.textInputState())
                    }
                    _ = self?.window?.makeFirstResponder(self?.textView.inputView)
                }
                
                GroupCallScreenUIHooks.shared.updateEmojies(emoji, interactions, EntertainmentUIHooks.shared.makeChatInteraction(context, context.peerId))
                
            }
            
        }
    }
    
    public func update(state: GroupCallUIState.Messages, arguments: GroupCallUIArguments, animated: Bool) {
        self.arguments = arguments
        self.state = state
        
        self.textView.context = arguments.getContext()
        self.textView.inputTheme = TelegramThemeHooks.shared.darkAppearance().inputTheme

        
        makeReactions(arguments: arguments)
        
        let max_limit = arguments.getContext()?.appConfiguration.getGeneralValue("group_call_message_length_limit", orElse: 128) ?? 128
        
        textInteractions.max_input = Int(max_limit)
        
        self.textView.interactions.inputDidUpdate = { [weak self] state in
            guard let `self` = self else {
                return
            }
            if state.string.length < max_limit {
                self.set(state)
            } else {
                self.textView.set(self.textInputState.textInputState())
                self.shake(beep: true)
            }
//            self.inputDidUpdateLayout(animated: true)

        }
        self.textView.interactions.responderDidUpdate = {
        }
        textInteractions.processEnter = { [weak self] event in
            return self?.textViewEnterPressed(event) ?? true
        }
        textInteractions.processPaste = { pasteboard in
            return false
        }
        textInteractions.processAttriburedCopy = { attributedString in
            return LinkHooks.shared.globalLinkExecutor().copyAttributedString(attributedString)
        }
        

    }
    
    public var firstResponder: NSResponder? {
        return textView.inputView
    }
}
