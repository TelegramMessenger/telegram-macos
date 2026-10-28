import Foundation
import Cocoa
import TGUIKit
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InputView
import RichTextEditorCore
import RichTextEditorUI
import Postbox
import Translate
import ColorPalette
import TelegramMedia
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AlertsUI
import GeneralRows
import InputTextView
import PremiumUI
import InlineStickerLayer

public protocol ChatInputDelegate : AnyObject {
    func inputChanged(height:CGFloat, animated:Bool);
}

public final class InputMessageEffectView : Control {
    
    
    public class RadialGradientView: View {
        
        public override func draw(_ layer: CALayer, in context: CGContext) {
            super.draw(layer, in: context)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            let colors = [theme.colors.background.cgColor, theme.colors.background.withAlphaComponent(0).cgColor] as CFArray

            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) else { return }

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = min(bounds.width, bounds.height) / 2

            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: .drawsBeforeStartLocation)
        }
    }
    
    public let view: InlineStickerView
    private let gradient: RadialGradientView = RadialGradientView(frame: NSMakeRect(0, 0, 20, 20))
    public init(account: Account, file: TelegramMediaFile, size: NSSize) {
        self.view = .init(account: account, file: file, size: size, playPolicy: .onceEnd)
        super.init(frame: NSMakeSize(size.width, 20).bounds)
        self.layer?.masksToBounds = false
        addSubview(gradient)
        addSubview(view)
        scaleOnClick = true
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        gradient.center()
        view.center()
    }
}

public final class ChatInputContainerView: FlippableView {
    public let chatInteraction: ChatInteraction

    // Read-only preview of a structural rich-text draft, shown at the top of the pill (above the text),
    // mirroring the accessory slot. Height is 0 when there is no draft → no effect on normal chats.
    fileprivate var richDraftPreview: RichTextDraftPreviewView?
    fileprivate var richDraftPreviewHeight: CGFloat = 0
    public var reopenRichDraft: (() -> Void)?
    /// Return pressed inside the inline (text-only) editor → host composes + sends the current content.
    public var sendRichDraft: (() -> Void)?
    /// The inline editor's content grew/shrank → host propagates the new input height.
    public var richDraftHeightChanged: (() -> Void)?

    public let accessory: ChatInputAccessory
    public let contentView: FlippableView
    public let actionsView: ChatInputActionsView
    public let sendButton: ChatInputSendButton
    public let textFieldContainer: View
    public let textView: UITextView
    public let attachView: ChatInputAttachButton

    /// Top-right "open in rich editor" affordance, shown when the input grows to 4+ lines (mirrors the AI
    /// button trigger). Clicking opens the rich editor with the current input (works even for plain text).
    /// Created lazily (only while shown).
    fileprivate var expandRichButton: ImageButton?
    public var openRichEditor: (() -> Void)?

    public let glassWrapper: GlassContainerView

    public var inputRowGlassContainer: (NSView & GlassEffectContainer)? { glassWrapper.glassContainer }
    public var inputRowGlassContent: View? { glassWrapper.glassContent }

    public var attachGhost: LiquidGlassView?
    public var textGhost: LiquidGlassView?
    public var voiceGhost: LiquidGlassView?
    public var botMenuGhost: LiquidGlassView?
    public var keyboardGhost: LiquidGlassView?

    public let bottomView: ScrollView = ScrollView()
    public let keyboardGlass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: true, hasBorder: true)

    public var botMenuView: ChatInputMenuView?
    public var sendAsView: ChatInputSendAsView?

    public var bottomHeight: CGFloat = 0

    var glassSlotsOverride: (() -> ChatInputGlassSlots?)?
    var springsFieldMerge = false
    private static let sendAppearOffset: CGFloat = 8

    public init(frame frameRect: NSRect, chatInteraction: ChatInteraction, textInteractions: TextView_Interactions) {
        self.chatInteraction = chatInteraction
        self.accessory = ChatInputAccessory(chatInteraction: chatInteraction)
        self.contentView = FlippableView(frame: NSMakeRect(0, 0, NSWidth(frameRect), NSHeight(frameRect)))
        let attachWidth: CGFloat = chatInteraction.mode.customChatLink != nil ? 20 : 40
        self.attachView = ChatInputAttachButton(frame: NSMakeRect(0, 0, attachWidth, 40), chatInteraction: chatInteraction)
        self.attachView.isHidden = chatInteraction.mode.customChatLink != nil
        self.actionsView = ChatInputActionsView(frame: NSMakeRect(0, 0, 60, contentView.frame.height), chatInteraction: chatInteraction)
        self.sendButton = ChatInputSendButton(frame: NSMakeRect(0, 0, 40, 40), chatInteraction: chatInteraction)
        self.textFieldContainer = View(frame: NSMakeRect(0, 0, 100, contentView.frame.height))
        self.textView = UITextView(frame: NSMakeRect(0, 0, 100, contentView.frame.height), interactions: textInteractions)
        self.glassWrapper = GlassContainerView(frame: NSRect(origin: .zero, size: frameRect.size), flipped: false, spacing: 5)

        super.init(frame: frameRect)

        self.flip = false
        self.layer?.masksToBounds = false

        contentView.flip = false
        contentView.backgroundColor = .clear
        contentView.layer?.masksToBounds = false
        textFieldContainer.layer?.masksToBounds = true

        textFieldContainer.addSubview(accessory)
        textFieldContainer.addSubview(textView)
        textFieldContainer.addSubview(actionsView)

        addSubview(glassWrapper)

        let attachGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        let textGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        let voiceGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        let botMenuGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        let keyboardGhost = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true)
        self.attachGhost = attachGhost
        self.textGhost = textGhost
        self.voiceGhost = voiceGhost
        self.botMenuGhost = botMenuGhost
        self.keyboardGhost = keyboardGhost

        glassWrapper.addGhost(attachGhost)
        glassWrapper.addGhost(textGhost)
        glassWrapper.addGhost(voiceGhost)
        glassWrapper.addGhost(botMenuGhost)
        glassWrapper.addGhost(keyboardGhost)

        sendButton.setMediaActionInnerGlassHidden(true)
        sendButton.setSharedGlassGhost(voiceGhost)

        attachView.onMorphHoldChange = { [weak self] held in
            self?.attachGhost?.isHidden = held
        }

        contentView.addSubview(attachView)

        self.addSubview(contentView)
        self.addSubview(textFieldContainer)
        self.addSubview(sendButton)

        // bottomView (keyboard markup scroll area) + keyboardGlass live in the
        // container so they're hidden together when the input state changes
        // (recording / action panel / etc. via container.isHidden).
        keyboardGlass.isHidden = true
        bottomView.documentView = ReplyMarkupContainerView()
        bottomView.layer?.cornerRadius = 16
        bottomView.documentView?.background = .clear
        bottomView.scrollerStyle = .overlay
        bottomView.contentView.backgroundColor = .clear
        bottomView.background = .clear
        bottomView.backgroundColor = .clear
        self.addSubview(keyboardGlass)
        self.addSubview(bottomView)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public required init(frame frameRect: NSRect) { fatalError("use init(frame:chatInteraction:textInteractions:)") }

    public var chatState: ChatState { chatInteraction.presentation.state }

    public var accessoryHeight: CGFloat {
        accessory.isVisibility() ? 10 + accessory.size.height : 0
    }

    fileprivate var richDraftSlotHeight: CGFloat {
        let minHeight = CGFloat(textView.min_height)
        let draftHeight = richDraftPreviewHeight - RichTextDraftPreviewView.vInset * 2
        return max(minHeight, min(richDraftPreviewHeight, draftHeight * 2 - minHeight))
    }

    public func contentHeight(for width: CGFloat) -> CGFloat {
        // A rich draft stands IN PLACE of the text (it looks like the entered content), so it replaces the
        // text's base height rather than stacking above an empty field.
        if richDraftPreviewHeight > 0 {
            return richDraftSlotHeight + accessoryHeight
        }
        let base = (chatState == .normal || chatState == .editing) ? textViewSize(width).0.height : CGFloat(textView.min_height)
        return base + accessoryHeight
    }

    /// Show / update / hide the rich-draft preview. Returns true when the height changed (so the host can
    /// propagate the new input height). Measured against the current text width.
    @discardableResult
    public func setRichDraft(_ instantPage: InstantPage?, theme presentationTheme: TelegramPresentationTheme) -> Bool {
        let previousHeight = richDraftPreviewHeight
        if let instantPage = instantPage {
            let current: RichTextDraftPreviewView
            var isNew = false
            if let view = richDraftPreview {
                current = view
            } else {
                current = RichTextDraftPreviewView(frame: .zero)
                current.onReopen = { [weak self] in
                    self?.reopenRichDraft?()
                }
                current.onSend = { [weak self] in
                    self?.sendRichDraft?()
                }
                current.onEditorHeightChange = { [weak self] in
                    guard let self = self, let preview = self.richDraftPreview else { return }
                    // Editing emptied the draft (e.g. ⌘A + Delete removed all text AND media) → drop the rich
                    // editor and return to the plain input.
                    if let blocks = preview.currentOutgoing(), !richTextOutgoingHasContent(blocks) {
                        self.chatInteraction.setRichTextDraft(nil)
                        return
                    }
                    let width = max(40, self.textViewSize(self.frame.width).0.width)
                    preview.maxContentHeight = max(CGFloat(self.textView.max_height), CGFloat(self.textView.min_height))
                    let h = preview.relayout(width: width)
                    if h != self.richDraftPreviewHeight {
                        self.richDraftPreviewHeight = h
                        self.richDraftHeightChanged?()
                    }
                    self.needsLayout = true
                }
                self.richDraftPreview = current
                textFieldContainer.addSubview(current)
                isNew = true
            }
            let width = max(40, textViewSize(frame.width).0.width)
            // Grow the rich draft to the same extent as normal typed text before it starts scrolling.
            current.maxContentHeight = max(CGFloat(textView.max_height), CGFloat(textView.min_height))
            richDraftPreviewHeight = current.update(instantPage: instantPage, width: width, chatInteraction: chatInteraction, theme: presentationTheme)
            if isNew {
                // Position the freshly-created preview immediately (same formula as updateLayout) so it
                // doesn't flash at the origin before the next layout pass.
                let sendAsInset: CGFloat = sendAsView != nil ? 34 + 3 : 0
                let textLeftInset: CGFloat = 12 + sendAsInset
                let previewY = accessoryHeight + (richDraftSlotHeight - richDraftPreviewHeight) / 2
                current.frame = NSMakeRect(textLeftInset, previewY, width, richDraftPreviewHeight)
            }
        } else if let view = richDraftPreview {
            view.removeFromSuperview()
            richDraftPreview = nil
            richDraftPreviewHeight = 0
        }
        return previousHeight != richDraftPreviewHeight
    }

    public func textViewSize(_ width: CGFloat) -> (NSSize, CGFloat) {
        let edge: CGFloat = 12
        let gap: CGFloat = 10
        var leftInset: CGFloat = attachView.frame.width
        if let botMenu = self.botMenuView {
            leftInset += botMenu.glassFrame.width + gap
        }
        let sendAsInset: CGFloat = sendAsView != nil ? 34 + 3 : 0
        let sendSlot = self.sendSlot(gap: gap)
        let containerWidth = width - edge - leftInset - gap - sendSlot.outside - edge
        let textLeftInset: CGFloat = 10 + sendAsInset
        let actionsWidth = actionsView.visibleWidth + sendSlot.inField
        let textWidth = max(0, containerWidth - textLeftInset - actionsWidth)
        let height = self.textView.height(for: textWidth)
        return (NSMakeSize(textWidth, min(max(height, textView.min_height), textView.max_height)), height)
    }

    private func sendSlot(gap: CGFloat) -> (outside: CGFloat, inField: CGFloat) {
        if sendButton.isInField {
            return (0, ChatInputSendButton.fieldInset + sendButton.desiredSize.width + ChatInputSendButton.fieldTextGap)
        }
        return (gap + sendButton.desiredSize.width, 0)
    }

    public override func layout() {
        super.layout()
        updateLayout(transition: .immediate)
    }

    public func updateLayout(transition: ContainedViewLayoutTransition) {
        let size = bounds.size
        let bottomInset = chatInteraction.presentation.isKeyboardShown ? bottomHeight : 0
        let keyboardWidth = size.width - 26
        let contentHeight = contentHeight(for: size.width)
        let contentY = bottomInset + ChatInputView.inputBottomInset

        let glassBottomMargin = ChatInputView.keyboardGlassBottomMargin
        let keyboardGlassHeight = max(0, bottomHeight - glassBottomMargin)
        let keyboardGlassY = chatInteraction.presentation.isKeyboardShown ? glassBottomMargin : -keyboardGlassHeight

        // keyboardGlass parks at a negative y while the markup keyboard is
        // hidden — `keyboardGlassHeight <= 0` hides it in that state.
        let keyboardInset: CGFloat = 3
        let glassFrame = NSMakeRect(13, keyboardGlassY, keyboardWidth, keyboardGlassHeight)
        if inputRowGlassContainer == nil {
            transition.updateFrame(view: keyboardGlass, frame: glassFrame)
            keyboardGlass.updateLayout(size: glassFrame.size, transition: transition)
            keyboardGlass.isHidden = keyboardGlassHeight <= 0
        }
        let bottomViewFrame: NSRect
        if keyboardGlassHeight > keyboardInset * 2 {
            bottomViewFrame = glassFrame.insetBy(dx: keyboardInset, dy: keyboardInset)
        } else {
            bottomViewFrame = NSMakeRect(glassFrame.minX + keyboardInset, glassFrame.minY, max(0, glassFrame.width - keyboardInset * 2), 0)
        }
        transition.updateFrame(view: bottomView, frame: bottomViewFrame)

        let edge: CGFloat = 12
        let gap: CGFloat = 10

        transition.updateFrame(view: contentView, frame: NSMakeRect(0, contentY, size.width, contentHeight))

        var leftInset: CGFloat = 0
        if let view = botMenuView, let botMenu = chatInteraction.presentation.botMenu {
            let compact = !textView.string().isEmpty
            view.update(botMenu, compact: compact, animated: transition.isAnimated)
            let desired = view.desiredSize
            view.updateLayout(size: desired, transition: transition)
            let internalLeftPadding = view.glassFrame.minX
            let pillWidth = view.glassFrame.width
            let frame = NSMakeRect(edge - internalLeftPadding, 0, desired.width, desired.height)
            if transition.isAnimated && view.frame == .zero {
                view.frame = frame
            }
            transition.updateFrame(view: view, frame: frame)
            leftInset += pillWidth + gap
        }
        
        let (textSize, textHeight) = textViewSize(size.width)
        let accessoryHeight = self.accessoryHeight

        // The AI (rephrase) button lives in the attach view and appears once the input has grown to 4+
        // lines; the attach view then expands into a vertical pill to hold it (glass ghost follows).
        let showAi = (chatInteraction.presentation.state == .normal || chatInteraction.presentation.state == .editing)
            && (chatInteraction.presentation.interfaceState.editState?.loadingState ?? EditStateLoading.none) == EditStateLoading.none
            && chatInteraction.presentation.peer?.isSecretChat != true
            && textView.numberOfLines(for: textSize.width) >= 4

        let sendAsInset: CGFloat = sendAsView != nil ? 34 + 3 : 0
        let sendSize = sendButton.desiredSize
        let sendWidth = sendSize.width

        let attachX = leftInset + edge
        // When the AI button is shown the attach pill is a FIXED, capped size and does NOT grow as the
        // input keeps expanding. Otherwise it's the standard single-button circle.
        let attachHeight: CGFloat = showAi ? ChatInputAttachButton.expandedHeight : ChatInputAttachButton.collapsedHeight
        let attachFrame = NSMakeRect(attachX, 0, attachView.frame.width, attachHeight)
        transition.updateFrame(view: attachView, frame: attachFrame)
        attachView.setAI(visible: showAi, transition: transition)

        let containerX = attachView.frame.maxX + gap
        let rightX = size.width - edge - sendWidth
        let sendSlot = self.sendSlot(gap: gap)
        let containerWidth = size.width - edge - sendSlot.outside - containerX
        let fieldContentWidth = containerWidth - sendSlot.inField

        textFieldContainer.layer?.cornerRadius = 20

        let textFieldFrame = NSMakeRect(containerX, contentY, containerWidth, contentHeight)
        transition.updateFrame(view: textFieldContainer, frame: textFieldFrame)

        glassWrapper.updateLayout(size: size, transition: transition)

        let inputBarBottom = contentY

        let sendFrame: NSRect
        let voiceGhostFrame: NSRect
        if sendButton.isInField {
            let capsule = NSMakeSize(sendWidth, ChatInputSendButton.fieldSize.height)
            sendFrame = NSMakeRect(textFieldFrame.maxX - ChatInputSendButton.fieldInset - sendWidth, inputBarBottom, sendWidth, sendSize.height)
            voiceGhostFrame = NSRect(x: sendFrame.midX - capsule.width / 2, y: sendFrame.midY - capsule.height / 2, width: capsule.width, height: capsule.height)
        } else {
            sendFrame = NSMakeRect(rightX, inputBarBottom, sendWidth, sendSize.height)
            voiceGhostFrame = sendFrame
        }

        let attachGhostFrame = NSRect(x: attachFrame.minX, y: inputBarBottom, width: attachFrame.width, height: attachFrame.height)
        let textGhostFrame = textFieldFrame
        let botGhostFrame: NSRect? = botMenuView.map { botMenu in
            let pill = botMenu.glassFrame
            return NSRect(x: botMenu.frame.minX + pill.minX, y: inputBarBottom + pill.minY, width: pill.width, height: pill.height)
        }
        let keyboardGhostFrame = glassFrame

        let morphSlots = glassSlotsOverride?()
        var attachTarget: NSRect? = attachGhostFrame
        var textTarget = textGhostFrame
        var voiceTarget: NSRect? = voiceGhostFrame
        var botTarget = botGhostFrame
        if let morphSlots {
            attachTarget = morphSlots.attach
            textTarget = morphSlots.text
            voiceTarget = morphSlots.voice
            if botTarget != nil {
                botTarget = morphSlots.attach ?? morphSlots.text
            }
        }

        let botMenuAppearing = transition.isAnimated && morphSlots == nil && botMenuGhost.map { $0.frame == .zero || $0.isHidden } == true
        keyboardGhost?.isHidden = keyboardGlassHeight <= 0 || morphSlots != nil
        botMenuGhost?.isHidden = botTarget == nil
        attachGhost?.isHidden = attachTarget == nil || attachView.isMorphHeld
        voiceGhost?.isHidden = voiceTarget == nil

        if let attachGhost, let attachTarget {
            glassWrapper.setGhostFrame(attachGhost, frame: attachTarget, transition: transition)
        }
        if let textGhost {
            setFieldGhostFrame(textGhost, frame: textTarget, transition: transition)
        }
        if let voiceGhost, let voiceTarget {
            setFieldGhostFrame(voiceGhost, frame: voiceTarget, transition: transition)
        }
        if let botMenuGhost, let botTarget {
            if botMenuAppearing {
                let initialFrame = NSMakeRect(botTarget.minX, botTarget.minY, botTarget.height, botTarget.height)
                glassWrapper.setGhostFrame(botMenuGhost, frame: initialFrame, transition: .immediate)
            }
            glassWrapper.setGhostFrame(botMenuGhost, frame: botTarget, transition: transition)
        }
        if let keyboardGhost, morphSlots == nil {
            glassWrapper.setGhostFrame(keyboardGhost, frame: keyboardGhostFrame, transition: transition)
        }

        accessory.measureSize(containerWidth - 20)
        let accessoryShown = accessory.isVisibility()
        let accessoryFrame = NSMakeRect(5, accessoryShown ? 5 : -accessory.size.height, containerWidth - 8, accessory.size.height)
        if accessoryShown, transition.isAnimated, accessory.frame.minY < accessoryFrame.minY {
            accessory.frame = accessoryFrame.offsetBy(dx: 0, dy: -accessoryFrame.maxY)
        }
        transition.updateFrame(view: accessory, frame: accessoryFrame)
        accessory.updateLayout(accessoryFrame.size, transition: transition)

        let textY = accessoryHeight
        if let view = sendAsView {
            let frame = NSMakeRect(3, textY + textSize.height - 34 - 3, 34, 34)
            if transition.isAnimated && view.frame.origin == .zero {
                view.frame = frame
            }
            transition.updateFrame(view: view, frame: frame)
        }

        let textLeftInset: CGFloat = 12 + sendAsInset
        let textRect = NSMakeRect(textLeftInset, textY, textSize.width, textSize.height)

        if let preview = richDraftPreview {
            // A rich draft IS the input content: hide the text field (and its placeholder) and render the
            // draft in the text content slot, vertically centered like a real single line of input.
            let measured = preview.relayout(width: textSize.width)
            if measured != richDraftPreviewHeight {
                // The draft was first measured before this width existed (e.g. on chat open) — the input's
                // outer height was derived from that stale value, so re-propagate it. Deferred a tick: we're
                // inside layout, and the host reacts by re-laying the input.
                richDraftPreviewHeight = measured
                DispatchQueue.main.async { [weak self] in
                    self?.richDraftHeightChanged?()
                }
            }
            textView.isHidden = true
            let previewY = textY + (richDraftSlotHeight - richDraftPreviewHeight) / 2
            transition.updateFrame(view: preview, frame: NSMakeRect(textLeftInset, previewY, textSize.width, richDraftPreviewHeight))
        } else {
            textView.isHidden = false
            transition.updateFrame(view: textView, frame: textRect)
            textView.updateLayout(size: textRect.size, textHeight: textHeight, transition: transition)
        }

        let showExpand = ((showAi && chatInteraction.presentation.state == .normal) || richDraftPreview != nil) && chatInteraction.interactionContext.appConfiguration.isRichTextEditorEnabled
        if showExpand {
            let current: ImageButton
            var isNew = false
            if let view = expandRichButton {
                current = view
            } else {
                current = ImageButton()
                current.autohighlight = false
                current.scaleOnClick = true
                current.set(image: TelegramThemeHooks.shared.image(.iconExpandRichText).precomposed(theme.colors.text), for: .Normal)
                current.sizeToFit(NSZeroSize, NSMakeSize(24, 24), thatFit: true)
                current.set(handler: { [weak self] _ in self?.openRichEditor?() }, for: .Click)
                current.setAccessibilityLabel(strings().voiceOverCommonExpand)
                textFieldContainer.addSubview(current)
                expandRichButton = current
                isNew = true
            }
            let bs = current.frame.size
            let sendColumnMidX = containerWidth - ChatInputSendButton.fieldInset - sendWidth / 2
            let stackedY = accessoryHeight + 8
            let frame: NSRect
            if richDraftPreview != nil, sendButton.isInField, stackedY + bs.height > contentHeight - sendSize.height {
                let slot = actionsView.entertaiments.frame.size
                frame = NSMakeRect(fieldContentWidth - (slot.width + bs.width) / 2, contentHeight - (slot.height + bs.height) / 2, bs.width, bs.height)
            } else {
                frame = NSMakeRect(sendColumnMidX - bs.width / 2, stackedY, bs.width, bs.height)
            }
            if isNew {
                current.frame = frame
            } else {
                transition.updateFrame(view: current, frame: frame)
            }
        } else if let view = expandRichButton {
            view.removeFromSuperview()
            expandRichButton = nil
        }


        let actionsFrame = NSMakeRect(0, textY, fieldContentWidth, textSize.height)
        transition.updateFrame(view: actionsView, frame: actionsFrame)
        actionsView.updateLayout(size: actionsFrame.size, transition: transition)
        actionsView.isHidden = richDraftPreview != nil

        if springsFieldMerge, transition.isAnimated {
            sendButton.frame = sendFrame.offsetBy(dx: -ChatInputContainerView.sendAppearOffset, dy: 0)
            ChatInputGlassSpring.animate {
                sendButton.animator().frame = sendFrame
            }
        } else {
            transition.updateFrame(view: sendButton, frame: sendFrame)
        }
        sendButton.updateLayout(size: sendSize, transition: transition)
    }

    private func setFieldGhostFrame(_ ghost: LiquidGlassView, frame: NSRect, transition: ContainedViewLayoutTransition) {
        guard springsFieldMerge, transition.isAnimated, ghost.effectView.superview === glassWrapper.glassContent else {
            glassWrapper.setGhostFrame(ghost, frame: frame, transition: transition)
            return
        }
        ChatInputGlassSpring.animate {
            ghost.setAnimatorFrame(frame)
            ghost.effectView.animator().frame = frame
        }
    }

    func glassSlots(of panel: ChatInputGlassMorphing, visible: Bool) -> ChatInputGlassSlots? {
        guard let slots = panel.glassMorphSlots(visible: visible) else {
            return nil
        }
        let content = glassWrapper.glassContent
        return ChatInputGlassSlots(
            attach: slots.attach.map { content.convert($0, from: panel) },
            text: content.convert(slots.text, from: panel),
            voice: slots.voice.map { content.convert($0, from: panel) }
        )
    }

    func visibleGlassSlots() -> ChatInputGlassSlots? {
        let content = glassWrapper.glassContent
        func visible(_ ghost: LiquidGlassView?) -> NSRect? {
            guard let ghost, !ghost.isHidden, let effectView = ghost.effectView, effectView.superview === content else {
                return nil
            }
            return visibleFrame(effectView)
        }
        guard let text = visible(textGhost) else {
            return nil
        }
        return ChatInputGlassSlots(attach: visible(attachGhost), text: text, voice: visible(voiceGhost))
    }

    func startGlass(at slots: ChatInputGlassSlots) {
        func start(_ ghost: LiquidGlassView?, _ frame: NSRect?) {
            guard let ghost, let frame else {
                return
            }
            ghost.layer?.removeAllAnimations()
            ghost.effectView.layer?.removeAllAnimations()
            glassWrapper.setGhostFrame(ghost, frame: frame, transition: .immediate)
        }
        start(attachGhost, slots.attach)
        start(textGhost, slots.text)
        start(voiceGhost, slots.voice)
        start(botMenuView != nil ? botMenuGhost : nil, slots.attach ?? slots.text)
    }
}

public class ChatInputView: View, Notifable {

    private var standart:CGFloat = 40.0
    private var bottomHeight:CGFloat = 0
    public static let bottomPadding:CGFloat = 10

    
    private let sendActivityDisposable = MetaDisposable()
    public let ready = Promise<Bool>()
    public weak var delegate:ChatInputDelegate?
    public var chatInteraction:ChatInteraction

    public let container: ChatInputContainerView

    public var accessory: ChatInputAccessory { container.accessory }
    public var contentView: FlippableView { container.contentView }
    public var actionsView: ChatInputActionsView { container.actionsView }
    public var sendButton: ChatInputSendButton { container.sendButton }
    public var textFieldContainer: View { container.textFieldContainer }
    public var textView: UITextView { container.textView }
    public var attachView: ChatInputAttachButton { container.attachView }

    public var inputRowGlassContainer: (NSView & GlassEffectContainer)? { container.inputRowGlassContainer }
    public var inputRowGlassContent: View? { container.inputRowGlassContent }

    public var attachGhost: LiquidGlassView? {
        get { container.attachGhost }
        set { container.attachGhost = newValue }
    }
    public var textGhost: LiquidGlassView? {
        get { container.textGhost }
        set { container.textGhost = newValue }
    }
    public var voiceGhost: LiquidGlassView? {
        get { container.voiceGhost }
        set { container.voiceGhost = newValue }
    }
    public var botMenuGhost: LiquidGlassView? {
        get { container.botMenuGhost }
        set { container.botMenuGhost = newValue }
    }
    public var keyboardGhost: LiquidGlassView? {
        get { container.keyboardGhost }
        set { container.keyboardGhost = newValue }
    }

    public var botMenuView: ChatInputMenuView? {
        get { container.botMenuView }
        set { container.botMenuView = newValue }
    }
    public var sendAsView: ChatInputSendAsView? {
        get { container.sendAsView }
        set { container.sendAsView = newValue }
    }

    private var bottomView: ScrollView { container.bottomView }
    private var keyboardGlass: LiquidGlassView { container.keyboardGlass }


    private var messageActionsPanelView: MessageActionsPanelView?

    /// Latest chat theme passed in via `updateLocalizationAndTheme`. Stored
    /// so paths that create subviews on-the-fly (e.g. `setState` instantiating
    /// `MessageActionsPanelView` when the user enters selection mode) can
    /// apply the chat palette immediately instead of waiting for the next
    /// theme pass and flashing the global app colours.
    private var currentChatTheme: TelegramPresentationTheme?
    private var recordingPanelView: ChatInputRecordingView?
    private var stateView: ChatInputStateView?
    private var disallowText: Control?
    private var messageEffect: InputMessageEffectView?

    private var paidMessageView: InteractiveTextView?

    public var textContainerFrame: NSRect {
        return textFieldContainer.frame
    }

    private let rtfAttachmentsDisposable = MetaDisposable()
    private let slowModeUntilDisposable = MetaDisposable()
    private let accessoryDisposable:MetaDisposable = MetaDisposable()
    private let richDraftDisposable = MetaDisposable()
    private let incomingTypingDraftDisposable = MetaDisposable()
    private var incomingTypingDraftKey: PeerAndThreadId?
    private var canStopIncomingStreamingMessage = false
    private var sendAsHiddenByState = false
    private var glassMorphToken: Int = 0
    private var glassMorphOutCompletion: (() -> Void)?

    private static let glassMorphTransition: ContainedViewLayoutTransition = .animated(duration: ChatInputSendButton.fieldMotionDuration, curve: .easeOut)
    private static let glassMorphFadeOut: Double = 0.08
    private static let glassMorphFadeIn: Double = 0.12
    private static let glassMorphFadeKey = "glassMorphFade"


    private var replyMarkupModel:ReplyMarkupNode?
    public override var isFlipped: Bool {
        return false
    }

    public static let maxBottomHeight = ReplyMarkupNode.rowHeight * 5 + ReplyMarkupNode.buttonHeight / 2
    public static let keyboardGlassBottomMargin: CGFloat = 12

    private let textInteractions: TextView_Interactions


    public init(frame frameRect: NSRect, chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction

        let textInteractions = TextView_Interactions()
        self.textInteractions = textInteractions
        self.container = ChatInputContainerView(frame: NSMakeRect(0, 0, NSWidth(frameRect), NSHeight(frameRect)), chatInteraction: chatInteraction, textInteractions: textInteractions)

        super.init(frame: frameRect)

        self.textView.context = chatInteraction.interactionContext
        self.textView.isSecretChat = chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat || chatInteraction.presentation.peer?.isSecretChat == true

        self.animates = true

        self.layer?.masksToBounds = false

        // bottomView + keyboardGlass moved into the container.
        self.addSubview(container)

        self.background = .clear
        contentView.backgroundColor = .clear
        textFieldContainer.backgroundColor = .clear
        actionsView.backgroundColor = .clear
        bottomView.backgroundColor = .clear
        bottomView.documentView?.background = .clear

        updateLocalizationAndTheme(theme: theme)

        self.textView.installClickToFocus()
        
        
        textInteractions.inputDidUpdate = { [weak self] state in
            guard let `self` = self else {
                return
            }
            self.set(state)
            self.inputDidUpdateLayout(animated: true)
        }
        
        textInteractions.processEnter = { [weak self] event in
            return self?.textViewEnterPressed(event) ?? true
        }
        textInteractions.processPaste = { [weak self] pasteboard in
            return self?.processPaste(pasteboard) ?? false
        }
        textInteractions.processAttriburedCopy = { attributedString in
            return LinkHooks.shared.globalLinkExecutor().copyAttributedString(attributedString)
        }

        // Read-only rich-draft preview above the input. Reopen the editor on click.
        container.reopenRichDraft = { [weak self] in
            guard let self = self else { return }
            if #available(macOS 12, *) {
                showRichTextEditor(chatInteraction: self.chatInteraction)
            }
        }
        // Top-right expand affordance → open the current input in the rich editor.
        container.openRichEditor = { [weak self] in
            guard let self = self else { return }
            if #available(macOS 12, *) {
                showRichTextEditor(chatInteraction: self.chatInteraction)
            }
        }
        // Return inside the inline editor → send (sendMessage flushes the editor into the draft first).
        container.sendRichDraft = { [weak self] in
            self?.sendInlineRichDraft()
        }
        // Just before any send reads the stored draft, write the live inline-editor content into it (or into
        // the composer text when the content reduced to plain) — so the send button posts the edited content.
        chatInteraction.flushRichTextDraft = { [weak self] in
            guard let self = self, let preview = self.container.richDraftPreview, preview.isInlineEditing,
                  let blocks = preview.currentOutgoing() else { return }
            switch composeRichMessage(from: blocks, media: preview.currentMedia()) {
            case let .rich(page):
                self.chatInteraction.setRichTextDraft(page)
            case let .plain(text, entities):
                self.chatInteraction.setRichTextDraft(nil)
                if !text.isEmpty {
                    var attributes = chatTextAttributes(from: TextEntitiesMessageAttribute(entities: entities))
                    let restored = ChatTextInputState(inputText: text, selectionRange: text.length ..< text.length, attributes: attributes)
                    self.chatInteraction.update { $0.updatedInterfaceState { $0.withUpdatedInputState(restored) } }
                }
            case .empty:
                self.chatInteraction.setRichTextDraft(nil)
            }
        }
        // The inline editor changed → just re-propagate the input height. We deliberately DON'T sync the
        // stored draft here: that re-emits the draft signal → re-seeds the editor → loops (and churns media
        // ids, which is what made the image blue-box and the field read-only). The editor stays the source of
        // truth; the send path composes from it directly.
        container.richDraftHeightChanged = { [weak self] in
            self?.inputDidUpdateLayout(animated: true)
        }
        richDraftDisposable.set((chatInteraction.richTextDraftSignal |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self = self else { return }
            if self.container.setRichDraft(page, theme: self.currentChatTheme ?? theme) {
                self.inputDidUpdateLayout(animated: true)
            }
            let sendState = ChatInputView.sendButtonState(
                from: self.chatInteraction.presentation,
                hasRichDraft: page != nil,
                canStopIncomingStreamingMessage: self.canStopIncomingStreamingMessage
            )
            self.updateSendButton(sendState, animated: true)

            if page != nil { self.deletedRichDraft = nil }
            self.updateRichDraftKeyHandlers()
        }))
        chatInteraction.reloadRichTextDraft()
        self.bindIncomingTypingDraft(for: chatInteraction.chatLocation, animated: false)
    }

    private func bindIncomingTypingDraft(for chatLocation: ChatLocation, animated: Bool) {
        let key = PeerAndThreadId(peerId: chatLocation.peerId, threadId: chatLocation.threadId)
        guard self.incomingTypingDraftKey != key else {
            return
        }

        self.incomingTypingDraftKey = key
        self.updateCanStopIncomingStreamingMessage(false, animated: animated)

        let viewKey = PostboxViewKey.typingDrafts(key)
        let signal = self.chatInteraction.interactionContext.account.postbox.combinedView(keys: [viewKey])
        |> map { views -> Bool in
            guard let view = views.views[viewKey] as? TypingDraftsView, let typingDraft = view.typingDraft else {
                return false
            }
            return typingDraft.attributes.contains(where: { attribute in
                return (attribute as? TypingDraftMessageAttribute)?.canStop == true
            })
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue

        self.incomingTypingDraftDisposable.set(signal.start(next: { [weak self] canStop in
            guard let self, self.incomingTypingDraftKey == key else {
                return
            }
            self.updateCanStopIncomingStreamingMessage(canStop, animated: true)
        }))
    }

    private func updateCanStopIncomingStreamingMessage(_ canStop: Bool, animated: Bool) {
        guard self.canStopIncomingStreamingMessage != canStop else {
            return
        }
        self.canStopIncomingStreamingMessage = canStop

        let sendState = ChatInputView.sendButtonState(
            from: self.chatInteraction.presentation,
            hasRichDraft: self.chatInteraction.richTextDraft != nil,
            canStopIncomingStreamingMessage: canStop
        )
        self.updateSendButton(sendState, animated: animated)
    }

    private func updateSendButton(_ state: ChatInputSendButton.State, animated: Bool) {
        let wasInField = sendButton.isInField
        let hadState = sendButton.hasAppliedState
        let desiredChanged = sendButton.update(state: state, animated: animated)
        let animated = animated && hadState && window != nil
        if wasInField != sendButton.isInField {
            container.springsFieldMerge = animated && sendButton.isInField && chatInteraction.presentation.state == .normal
            container.updateLayout(transition: animated ? .animated(duration: ChatInputSendButton.fieldMotionDuration, curve: .easeOut) : .immediate)
            container.springsFieldMerge = false
        } else if desiredChanged {
            container.updateLayout(transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        }
    }

    /// The just-deleted rich draft, kept so ⌘Z can restore it.
    private var deletedRichDraft: InstantPage?

    /// Window key handlers active only around a rich draft (the text field is hidden, so its own handlers
    /// can't fire). While a draft is shown: Enter sends it, Delete removes the whole draft. After a delete:
    /// ⌘Z restores it (while the composer is still empty). Re-evaluated whenever the draft state changes.
    private func updateRichDraftKeyHandlers() {
        let window = chatInteraction.interactionContext.window
        window.remove(object: self, for: .Return)
        window.remove(object: self, for: .Delete)
        window.remove(object: self, for: .Z, modifierFlags: [.command], forceCheckFlags: true)
        window.remove(object: self, for: .Z, modifierFlags: [.command, .shift], forceCheckFlags: true)

        // Whether the draft is shown in the LIVE inline editor (vs the read-only media preview). Matches the
        // preview's block-based decision (NOT `media.isEmpty`, which can be non-empty for a text-only draft):
        // a draft with no unsupported-media block is the live inline editor. Both cases get a window Return
        // handler honoring the send preference; the inline case rejects non-send Returns so the editor adds a
        // newline, while Delete/⌘Z go to the editor.
        let isInlineEditable: Bool = {
            guard #available(macOS 12, *), let draft = chatInteraction.richTextDraft else { return false }
            let hasUninlineableBlock = draft.blocks.contains { block in
                switch block {
                case .video, .audio, .map, .collage, .slideshow: return true
                default: return false
                }
            }
            return !hasUninlineableBlock
        }()

        if isInlineEditable {
            // Return follows the plain-input send preference even with the caret inside the editor: the
            // configured send combo (Enter, or ⌘/⇧-Enter) sends; any other Return combo is rejected so the
            // editor inserts a newline. A window handler (not just the editor's own Return) is needed so
            // ⌘-Enter — which the editor never receives as `insertNewline` — still sends.
            window.set(handler: { [weak self] event -> KeyHandlerResult in
                guard let self = self, self.chatInteraction.richTextDraft != nil else { return .rejected }
                if FastSettings.checkSendingAbility(for: event) {
                    self.chatInteraction.sendMessage(false, nil, self.chatInteraction.presentation.messageEffect)
                    return .invoked
                }
                return .rejected
            }, with: self, for: .Return, priority: .high, modifierFlags: nil)
            // ⌘Z / ⌘⇧Z drive the editor's undo / redo.
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.container.richDraftPreview?.undoInline()
                return .invoked
            }, with: self, for: .Z, priority: .high, modifierFlags: [.command])
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                self?.container.richDraftPreview?.redoInline()
                return .invoked
            }, with: self, for: .Z, priority: .high, modifierFlags: [.command, .shift])
        } else if chatInteraction.richTextDraft != nil {
            // Enter sends (honoring the Enter / ⌘-Enter send preference).
            window.set(handler: { [weak self] event -> KeyHandlerResult in
                guard let self = self, self.chatInteraction.richTextDraft != nil else { return .rejected }
                if FastSettings.checkSendingAbility(for: event) {
                    self.chatInteraction.sendMessage(false, nil, self.chatInteraction.presentation.messageEffect)
                    return .invoked
                }
                return .rejected
            }, with: self, for: .Return, priority: .high, modifierFlags: nil)

            // Delete removes the whole draft, stashing it for ⌘Z.
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                guard let self = self, let draft = self.chatInteraction.richTextDraft else { return .rejected }
                self.deletedRichDraft = draft
                self.chatInteraction.setRichTextDraft(nil)
                return .invoked
            }, with: self, for: .Delete, priority: .high, modifierFlags: nil)
        } else if deletedRichDraft != nil {
            // ⌘Z restores the just-deleted draft, but only while the composer is still empty (otherwise let
            // the normal text undo run).
            window.set(handler: { [weak self] _ -> KeyHandlerResult in
                guard let self = self, let draft = self.deletedRichDraft,
                      self.chatInteraction.presentation.effectiveInput.inputText.isEmpty else { return .rejected }
                self.deletedRichDraft = nil
                self.chatInteraction.setRichTextDraft(draft)
                return .invoked
            }, with: self, for: .Z, priority: .high, modifierFlags: [.command])
        }
    }
    
    public func set(_ state: Updated_ChatTextInputState) {
        self.chatInteraction.update({
            $0.withUpdatedEffectiveInputState(state.textInputState())
        })
    }
    
    private var markNextTextChangeToFalseActivity: Bool = false

    public func textViewEnterPressed(_ event: NSEvent) -> Bool {
        
        let interaction = self.chatInteraction
        let context = interaction.interactionContext
        
        if FastSettings.checkSendingAbility(for: event) {
            let text = textView.string().trimmed
            if text.length > interaction.maxInputCharacters {
                if context.isPremium || context.premiumIsBlocked {
                    alert(for: context.window, info: strings().chatInputErrorMessageTooLongOther(text.length - Int(interaction.maxInputCharacters)))
                } else {
                    verifyAlert_button(for: context.window, information: strings().chatInputErrorMessageTooLongOther(text.length - Int(interaction.maxInputCharacters)), ok: strings().alertOK, cancel: "", option: strings().premiumGetPremiumDouble, successHandler: { result in
                        switch result {
                        case .thrid:
                            showPremiumLimit(context: context, type: .caption(text.length))
                        default:
                            break
                        }

                    })
                }
                return true
            }
            if !text.isEmpty || !interaction.presentation.interfaceState.forwardMessageIds.isEmpty || interaction.presentation.state == .editing {
                interaction.sendMessage(false, nil, interaction.presentation.messageEffect)
                if interaction.peerIsAccountPeer {
                    interaction.interactionContext.account.updateLocalInputActivity(peerId: interaction.activitySpace, activity: .typingText, isPresent: false)
                }
                markNextTextChangeToFalseActivity = true
            } else if text.isEmpty {
                interaction.scrollToLatest(true)
            }
            return true
        }
        return false
    }
    
    public static let inputBottomInset: CGFloat = 12

    public func height(for width: CGFloat) -> CGFloat {
        let contentHeight:CGFloat = contentHeight(for: width)
        var sumHeight:CGFloat = contentHeight + ChatInputView.inputBottomInset
        if let markup = replyMarkupModel  {
            bottomHeight = min(
                ChatInputView.maxBottomHeight,
                markup.size.height + 6
            ) + ChatInputView.keyboardGlassBottomMargin
        } else {
            bottomHeight = 0
        }
        if chatInteraction.presentation.isKeyboardShown {
            sumHeight += bottomHeight
        }
        return sumHeight
    }
    
    
    
    
    public override var responder:NSResponder? {
        // While a text-only rich draft is shown inline, the composer's focus target is the live editor (the
        // plain text field is hidden) — so typing / deleting edits the draft in place.
        if let editor = container.richDraftPreview?.editorResponder {
            return editor
        }
        return textView.inputView
    }
    
    public func updateInterface(with interaction:ChatInteraction) -> Void {
        self.chatInteraction = interaction
        sendButton.prepare(with: chatInteraction)
        needUpdateChatState(with: chatState, false)
        needUpdateReplyMarkup(with: interaction.presentation, false)
        
        updateMessageEffect(interaction.presentation.interfaceState.messageEffect, animated: false)
        
        updateAdditions(interaction.presentation, false)
        
        chatInteraction.add(observer: self)
        ready.set(accessory.nodeReady.get() |> map {_ in return true} |> take(1) )
        

        
        updateLayout(size: frame.size, transition: .immediate)
        
        self.updateInput(interaction.presentation, prevState: ChatPresentationInterfaceState(chatLocation: interaction.chatLocation, chatMode: interaction.mode), animated: false, initial: true)

    }
    
    private var textPlaceholder: String {
        
        
        if let amount = chatInteraction.presentation.sendPaidMessageStars {
            return strings().messagePlaceholderPaidMessage(strings().starListItemCountOther(Int(amount.value)))
        }
        
        if case let .thread(mode) = chatInteraction.mode {
            switch mode {
            case .comments:
                return strings().messagesPlaceholderComment
            case .replies:
                return strings().messagesPlaceholderReply
            case .topic:
                return strings().messagesPlaceholderSentMessage
            case .savedMessages, .saved: 
                break
            }
        }
        if case let .customChatContents(contents) = chatInteraction.mode {
            switch contents.kind {
            case .awayMessageInput:
                return strings().chatInputBusinessAway
            case .greetingMessageInput:
                return strings().chatInputBusinessGreeting
            case .quickReplyMessageInput:
                return strings().chatInputBusinessQuickReply
            case .welcomeMessages:
                if let limit = contents.messageLimit,
                   let historyCount = chatInteraction.presentation.historyCount,
                   historyCount >= limit {
                    return strings().welcomeMessageLimitReached(limit)
                }
                return strings().welcomeMessageInputPlaceholder
            case .searchHashtag:
                return ""
            }
        }
        if case .customLink = chatInteraction.mode {
            return strings().chatInputBusinessLink
        }
        
        guard let peer = chatInteraction.presentation.peer else {
            return strings().messagesPlaceholderSentMessage
        }
        
        if let _ = permissionText(from: peer, for: .banSendText, cachedData: chatInteraction.presentation.cachedData), chatInteraction.presentation.state == .normal {
            return strings().channelPersmissionMessageBlock
        }
        

            
        if let cachedData = chatInteraction.presentation.cachedData as? CachedChannelData {
            let viewForumAsMessages = cachedData.viewForumAsMessages.knownValue
            if TelegramUtilsHooks.shared.peerIsForum(peer), viewForumAsMessages == true {
                if let replyMessage = chatInteraction.presentation.interfaceState.replyMessage {
                    if let threadInfo = replyMessage.associatedThreadInfo {
                        return strings().messagePlaceholderReplyToTopic(threadInfo.title)
                    }
                } else {
                    return strings().messagePlaceholderMessageInGeneral
                }
            }
        }

        if let user = peer as? TelegramUser, let botInfo = user.botInfo, botInfo.flags.contains(.hasForum), !botInfo.flags.contains(.forumManagedByUser) {
            if chatInteraction.chatLocation.threadId == nil {
                return strings().chatOffThreadMessage
            }
        }

        if chatInteraction.presentation.interfaceState.editState != nil {
            return strings().messagePlaceholderEdit
        }
        if chatInteraction.mode == .scheduled {
            return strings().messagesPlaceholderScheduled
        }
        if let replyMarkup = chatInteraction.presentation.keyboardButtonsMessage?.replyMarkup {
            if let placeholder = replyMarkup.placeholder {
                return placeholder
            }
        }
        if let peer = chatInteraction.presentation.peer {
            if let peer = peer as? TelegramChannel {
                if peer.hasPermission(.canBeAnonymous) {
                    return strings().messagesPlaceholderAnonymous
                }
            }
            if peer.isChannel {
                return FastSettings.isChannelMessagesMuted(peer.id) ? strings().messagesPlaceholderSilentBroadcast : strings().messagesPlaceholderBroadcast
            }
        }
        if !chatInteraction.peerIsAccountPeer {
            return strings().messagesPlaceholderAnonymous
        }
        return strings().messagesPlaceholderSentMessage
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        self.currentChatTheme = theme

        attachView.updateLocalizationAndTheme(theme: theme)
        attachView.setInnerGlassHidden(true)
        attachView.setSharedGlassGhost(attachGhost)
        container.expandRichButton?.set(image: TelegramThemeHooks.shared.image(.iconExpandRichText).precomposed(theme.colors.text), for: .Normal)

        // Forward the appearance change to each ghost — its forceAppearance
        // didSet rebuilds the inner NSGlassEffectView at the new dark/light
        // boundary (Apple's glass surface bakes its render appearance at
        // construction time, so toggling .appearance on the existing instance
        // leaves it visually stale). Without this, the merged SDF surface
        // keeps the previous theme's tint until something else triggers a
        // ghost rebuild (resize, reparent, etc.).
        attachGhost?.updateLocalizationAndTheme(theme: theme)
        textGhost?.updateLocalizationAndTheme(theme: theme)
        voiceGhost?.updateLocalizationAndTheme(theme: theme)
        botMenuGhost?.updateLocalizationAndTheme(theme: theme)
        keyboardGhost?.updateLocalizationAndTheme(theme: theme)

        // Install the chat-theme tint on every ghost. Without this each
        // ghost's `applyAppearance` falls back to
        // `presentation.colors.background` (the app theme singleton), which
        // is wrong for chats on a custom palette / wallpaper — the input
        // bar would tint with the app background instead of the chat's.
        let chatGlassTint = theme.colors.background.withAlphaComponent(0.4)
        attachGhost?.customTint = chatGlassTint
        textGhost?.customTint = chatGlassTint
        voiceGhost?.customTint = chatGlassTint
        botMenuGhost?.customTint = chatGlassTint
        keyboardGhost?.customTint = chatGlassTint

       
        stateView?.updateLocalizationAndTheme(theme: theme)
        // When the user is in selection mode, the action panel is presented
        // in place of the regular input row — forward the chat theme so it
        // resolves tints/colours through the chat palette instead of the
        // global app theme.
        messageActionsPanelView?.updateLocalizationAndTheme(theme: theme)
        self.needUpdateReplyMarkup(with: chatInteraction.presentation, false)
    
        accessory.update(with: chatInteraction.presentation, context: chatInteraction.interactionContext, animated: false)
        
        
        let myPeerColor = chatInteraction.interactionContext.myPeer?.namePeerColor
        let colors: PeerNameColors.Colors
        if let myPeerColor = myPeerColor {
            colors = chatInteraction.interactionContext.peerNameColors.get(myPeerColor)
        } else {
            colors = .init(main: theme.colors.accent)
        }
        textView.inputTheme = theme.inputTheme
            .withUpdatedQuote(colors)
            .withUpdatedPlaceholderColor(theme.colors.darkGrayText)
    }
    
    public func notify(with value: Any, oldValue:Any, animated:Bool) {
        guard Thread.isMainThread else {
            return
        }

        self.actionsView.notify(with: value, oldValue: oldValue, animated: animated)
        if let value = value as? ChatPresentationInterfaceState {
            if let oldValue = oldValue as? ChatPresentationInterfaceState, value.chatLocation != oldValue.chatLocation {
                self.bindIncomingTypingDraft(for: value.chatLocation, animated: animated)
            }
            let sendState = ChatInputView.sendButtonState(
                from: value,
                hasRichDraft: chatInteraction.richTextDraft != nil,
                canStopIncomingStreamingMessage: self.canStopIncomingStreamingMessage
            )
            self.updateSendButton(sendState, animated: animated)
        }

        if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
            let textPermissionChanged = permissionText(from: value.peer, for: .banSendText, cachedData: value.cachedData) != permissionText(from: oldValue.peer, for: .banSendText, cachedData: oldValue.cachedData)

            if value.effectiveInput != oldValue.effectiveInput || oldValue.state != value.state || textPermissionChanged {
                updateInput(value, prevState: oldValue, animated: animated)
            }
            updateAttachments(value,animated)
            
            var urlPreviewChanged:Bool
            if value.urlPreview?.0 != oldValue.urlPreview?.0 {
                urlPreviewChanged = true
            } else if let valuePreview = value.urlPreview?.1, let oldValuePreview = oldValue.urlPreview?.1 {
                urlPreviewChanged = !valuePreview.isEqual(to: oldValuePreview)
            } else if (value.urlPreview?.1 == nil) != (oldValue.urlPreview?.1 == nil) {
                urlPreviewChanged = true
            } else {
                urlPreviewChanged = false
            }
            
            urlPreviewChanged = urlPreviewChanged || value.interfaceState.composeDisableUrlPreview != oldValue.interfaceState.composeDisableUrlPreview
            
            let peerIsNotEqual = value.peer.flatMap(EnginePeer.init) != oldValue.peer.flatMap(EnginePeer.init)
            
            if !isEqualMessageList(lhs: value.interfaceState.forwardMessages, rhs: oldValue.interfaceState.forwardMessages) || value.interfaceState.forwardMessageIds != oldValue.interfaceState.forwardMessageIds || value.interfaceState.replyMessageId != oldValue.interfaceState.replyMessageId || value.interfaceState.editState != oldValue.interfaceState.editState || urlPreviewChanged || value.interfaceState.hideSendersName != oldValue.interfaceState.hideSendersName || value.interfaceState.hideCaptions != oldValue.interfaceState.hideCaptions || value.interfaceState.linkBelowMessage != oldValue.interfaceState.linkBelowMessage || value.interfaceState.largeMedia != oldValue.interfaceState.largeMedia || peerIsNotEqual || value.interfaceState.suggestPost != oldValue.interfaceState.suggestPost {
                updateAdditions(value,animated)
            }
            
            if value.state != oldValue.state || textPermissionChanged {
                needUpdateChatState(with:value.state, animated)
            }
            
            var updateReplyMarkup = false
            
            if let lhsMessage = value.keyboardButtonsMessage, let rhsMessage = oldValue.keyboardButtonsMessage {
                if lhsMessage.id != rhsMessage.id || lhsMessage.stableVersion != rhsMessage.stableVersion {
                    updateReplyMarkup = true
                }
            } else if (value.keyboardButtonsMessage == nil) != (oldValue.keyboardButtonsMessage == nil) {
                updateReplyMarkup = true
            }
            
            if !updateReplyMarkup {
                updateReplyMarkup = value.isKeyboardShown != oldValue.isKeyboardShown
            }
            
            if updateReplyMarkup {
                needUpdateReplyMarkup(with: value, animated)
                inputDidUpdateLayout(animated: animated)
            }
            
            if value.interfaceState.messageEffect != oldValue.interfaceState.messageEffect  {
                self.updateMessageEffect(value.interfaceState.messageEffect, animated: animated)
            }
            self.messageEffect?.change(opacity: value.effectiveInput.inputText.isEmpty || value.interfaceState.editState != nil ? 0 : 1, animated: animated)
            //self.updateLayout(size: self.frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
            
        }
    }
    
    private func updateMessageEffect(_ messageEffect: ChatInterfaceMessageEffect?, animated: Bool) {
        let context = self.chatInteraction.interactionContext
        if let messageEffect {
            if self.messageEffect?.view.animateLayer.fileId != messageEffect.effect.effectSticker.fileId.id {
                if let view = self.messageEffect {
                    performSubviewRemoval(view, animated: animated)
                }
                let current = InputMessageEffectView(account: chatInteraction.interactionContext.account, file: messageEffect.effect.effectSticker._parse(), size: NSMakeSize(16, 16))
                current.userInteractionEnabled = true
                current.setFrameOrigin(NSMakePoint(frame.width - current.frame.width - 10, 5))
                
                
                let showMenu:(Control)->Void = { [weak self] control in
                    if let event = NSApp.currentEvent, let chatInteraction = self?.chatInteraction {
                        let sendMenu = chatInteraction.sendMessageMenu(true) |> deliverOnMainQueue
                        _ = sendMenu.startStandalone(next: { menu in
                            if let menu {
                                AppMenu.show(menu: menu, event: event, for: control)
                            }
                        })
                    }
                }

                current.set(handler: { control in
                    showMenu(control)
                }, for: .Down)
                
                current.set(handler: { control in
                    showMenu(control)
                }, for: .LongMouseDown)
                
 
                self.messageEffect = current
                
                
                if let fromRect = messageEffect.fromRect {
                    let layer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: messageEffect.effect.effectSticker.fileId.id, file: messageEffect.effect.effectSticker._parse(), emoji: ""), size: current.frame.size)
                    
                    let toRect = current.convert(current.frame.size.bounds, to: nil)
                    
                    let from = fromRect.origin.offsetBy(dx: fromRect.width / 2, dy: fromRect.height / 2)
                    let to = toRect.origin.offsetBy(dx: toRect.width / 2, dy: toRect.height / 2)
                    
                    let completed: (Bool)->Void = { [weak self] _ in
                        DispatchQueue.main.async {
                            if let container = self?.messageEffect {
                                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                                container.isHidden = false
                            }
                        }
                    }
                    current.isHidden = true
                    parabollicReactionAnimation(layer, fromPoint: from, toPoint: to, window: context.window, completion: completed)
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.chatInteraction.update {
                            $0.updatedInterfaceState {
                                $0.withRemovedEffectRect()
                            }
                        }
                    }
                    
                    let messageEffect = messageEffect.effect
                    let file = messageEffect.effectSticker._parse()
                    let signal: Signal<(LottieAnimation, String)?, NoError>
                    
                    let animationSize = NSMakeSize(200, 200)
                                        
                    if let animation = messageEffect.effectAnimation?._parse() {
                        signal = context.account.postbox.mediaBox.resourceData(animation.resource) |> filter { $0.complete } |> take(1) |> map { data in
                            if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                                return (LottieAnimation(compressed: data, key: .init(key: .bundle("_prem_effect_\(animation.fileId.id)"), size: animationSize, backingScale: Int(System.backingScale), mirror: false), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd), animation.stickerText ?? "")
                            } else {
                                return nil
                            }
                        }
                    } else {
                        if let effect = messageEffect.effectSticker._parse().premiumEffect {
                            signal = context.account.postbox.mediaBox.resourceData(effect.resource) |> filter { $0.complete } |> take(1) |> map { data in
                                if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                                    return (LottieAnimation(compressed: data, key: .init(key: .bundle("_prem_effect_\(file.fileId.id)"), size: animationSize, backingScale: Int(System.backingScale), mirror: false), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd), file.stickerText ?? "")
                                } else {
                                    return nil
                                }
                            }
                        } else {
                            signal = .single(nil)
                        }
                    }
                    _ = (signal |> deliverOnMainQueue).startStandalone(next: { value in
                        
                        if let animation = value?.0 {
                            let player = LottiePlayerView(frame: NSMakeRect(toRect.minX - animationSize.width / 2 - 50, toRect.minY - animationSize.height / 2 + 30, animationSize.width, animationSize.height))

                            animation.triggerOn = (LottiePlayerTriggerFrame.last, { [weak player] in
                                player?.removeFromSuperview()
                            }, {})
                            player.set(animation)
                            context.window.contentView?.addSubview(player)
                        }
                    })
                }
            }
        } else if let view = self.messageEffect {
            performSubviewRemoval(view, animated: animated)
            self.messageEffect = nil
            
            let players = context.window.contentView?.subviews.compactMap {
                $0 as? LottiePlayerView
            }
            
            if let players {
                for view in players {
                    performSubviewRemoval(view, animated: animated, scale: true)
                }
            }
            
        }
    }
    
    public func needUpdateReplyMarkup(with state:ChatPresentationInterfaceState, _ animated:Bool) {
        if let keyboardMessage = state.keyboardButtonsMessage, let attribute = keyboardMessage.replyMarkup, state.isKeyboardShown || attribute.flags.contains(.persistent) {
            replyMarkupModel = ReplyMarkupNode(attribute.rows, attribute.flags, chatInteraction.processBotKeyboard(with: keyboardMessage), theme, bottomView.documentView as? View, true, outerCornerRadius: 16)
            replyMarkupModel?.measureSize(frame.width - 40 - 24)
            replyMarkupModel?.redraw()
            replyMarkupModel?.layout()
            bottomView.contentView.scroll(to: NSZeroPoint)
        }
    }
    
    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? ChatInputView {
            return other == self
        }
        return false
    }
    
    public var chatState: ChatState { container.chatState }

    public func contentHeight(for width: CGFloat) -> CGFloat {
        return container.contentHeight(for: width)
    }
    
    private var canMorphGlass: Bool {
        return window != nil && !(container.inputRowGlassContainer is LegacyGlassEffectContainerView)
    }

    private var glassMorphPanel: ChatInputGlassMorphing? {
        if let view = recordingPanelView {
            return view
        }
        if let view = messageActionsPanelView {
            return view
        }
        return stateView
    }

    private var glassMorphContentViews: [NSView] {
        return [textFieldContainer, sendButton, bottomView] + contentView.subviews
    }

    private func morphGlassIn(from slots: ChatInputGlassSlots) {
        container.isHidden = false
        container.startGlass(at: slots)
        for view in glassMorphContentViews {
            guard let layer = view.layer else {
                continue
            }
            let from: Float = layer.animation(forKey: ChatInputView.glassMorphFadeKey) != nil ? layer.presentation()?.opacity ?? 0 : 0
            layer.removeAnimation(forKey: ChatInputView.glassMorphFadeKey)
            layer.animateAlpha(from: CGFloat(from), to: 1, duration: ChatInputView.glassMorphFadeIn)
        }
    }

    private func morphGlassOut(into panel: ChatInputGlassMorphing?, from slots: ChatInputGlassSlots) {
        guard let panel, container.glassSlots(of: panel, visible: false) != nil else {
            contentView.isHidden = true
            container.isHidden = true
            return
        }
        glassMorphToken += 1
        let token = glassMorphToken

        panel.setMorphGlassHidden(true)
        container.isHidden = false
        container.startGlass(at: slots)
        container.glassSlotsOverride = { [weak self, weak panel] in
            guard let self, let panel else {
                return nil
            }
            return self.container.glassSlots(of: panel, visible: false)
        }

        let fading = glassMorphContentViews.filter { $0.layer != nil }
        let duration = ChatInputView.glassMorphTransition.duration
        for (index, view) in fading.enumerated() {
            guard let layer = view.layer else {
                continue
            }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [layer.presentation()?.opacity ?? layer.opacity, Float(0), Float(0)]
            fade.keyTimes = [0, NSNumber(value: ChatInputView.glassMorphFadeOut / duration), 1]
            fade.duration = duration
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            if index == 0 {
                fade.completion = { [weak self] _ in
                    self?.completeGlassMorphOut(token)
                }
            }
            layer.add(fade, forKey: ChatInputView.glassMorphFadeKey)
        }

        glassMorphOutCompletion = { [weak self, weak panel] in
            guard let self else {
                return
            }
            self.container.glassSlotsOverride = nil
            for view in fading {
                view.layer?.removeAnimation(forKey: ChatInputView.glassMorphFadeKey)
            }
            self.contentView.isHidden = true
            self.container.isHidden = true
            panel?.setMorphGlassHidden(false)
            self.container.updateLayout(transition: .immediate)
        }

        container.updateLayout(transition: ChatInputView.glassMorphTransition)
    }

    private func completeGlassMorphOut(_ token: Int) {
        guard token == glassMorphToken else {
            return
        }
        finishGlassMorph()
    }

    private func finishGlassMorph() {
        guard let completion = glassMorphOutCompletion else {
            return
        }
        glassMorphOutCompletion = nil
        glassMorphToken += 1
        completion()
    }

    private func reverseGlassMorphOut() -> ChatInputGlassSlots? {
        guard glassMorphOutCompletion != nil, let slots = container.visibleGlassSlots() else {
            return nil
        }
        glassMorphOutCompletion = nil
        glassMorphToken += 1
        container.glassSlotsOverride = nil
        return slots
    }


    public func needUpdateChatState(with state:ChatState, _ animated:Bool) -> Void {
        CATransaction.begin()

        let morphsGlass = animated && canMorphGlass
        let isInputState = state == .normal || state == .editing
        var morphInSlots: ChatInputGlassSlots?
        if morphsGlass, isInputState {
            morphInSlots = reverseGlassMorphOut()
            if morphInSlots == nil, container.isHidden, let panel = glassMorphPanel, let slots = container.glassSlots(of: panel, visible: true) {
                panel.setMorphGlassHidden(true)
                morphInSlots = slots
            }
        }
        finishGlassMorph()
        let inputVisibleSlots = morphsGlass && !isInputState && !container.isHidden ? container.visibleGlassSlots() : nil
        if let morphInSlots {
            morphGlassIn(from: morphInSlots)
        }

        if animated {
            inputDidUpdateLayout(animated: animated)
        }
        if morphInSlots != nil {
            container.updateLayout(transition: ChatInputView.glassMorphTransition)
        }

        let morphsOut: Bool
        if inputVisibleSlots == nil {
            morphsOut = false
        } else {
            switch state {
            case .normal, .editing, .botStart:
                morphsOut = false
            case let .block(string):
                morphsOut = !string.isEmpty
            default:
                morphsOut = true
            }
        }

        let chatInteraction = self.chatInteraction
        let wasRecording = recordingPanelView != nil

        if let view = paidMessageView {
            performSubviewRemoval(view, animated: animated)
            paidMessageView = nil
        }
        let reusableActionView: ChatInputActionButtonView?
        if animated, case let .action(_, _, rightAddition, leftAddition, accent) = state, let view = stateView as? ChatInputActionButtonView, view.canUpdateInPlace(accent: accent, rightAdditionData: rightAddition, leftAdditionData: leftAddition) {
            reusableActionView = view
        } else {
            reusableActionView = nil
            if let view = stateView {
                performSubviewRemoval(view, animated: animated)
                stateView = nil
            }
        }

        // Reset base controls to default visibility; cases below override.
        textView.isHidden = false
        textFieldContainer.isHidden = false
        sendButton.isHidden = false
        if chatInteraction.mode.customChatLink == nil {
            attachView.isHidden = false
        }

        // Recording panel — lazy create / reuse across same-kind transitions,
        // remove when the new state isn't `.recording`.
        if case let .recording(recorder) = state {
            let current: ChatInputRecordingView
            var isNew = false
            if let view = recordingPanelView {
                current = view
            } else {
                current = ChatInputRecordingView(frame: NSMakeRect(12, 12, frame.width, standart), chatInteraction: chatInteraction, recorder: recorder)
                current.glassInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 12 + sendButton.frame.width)
                self.recordingPanelView = current
                self.addSubview(current)
                isNew = true
            }
            current.updateLayout(size: current.frame.size, transition: .immediate)
            if isNew, animated {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        } else if let view = recordingPanelView {
            recordingPanelView = nil
            if animated {
                view.animateOut(completion: { [weak view] in
                    view?.removeFromSuperview()
                })
            } else {
                view.removeFromSuperview()
            }
        }

        if state == .selecting {
            let current: MessageActionsPanelView
            var isNew = false
            if let view = messageActionsPanelView {
                current = view
            } else {
                current = MessageActionsPanelView(frame: bounds)
                current.prepare(with: chatInteraction)
                current.updateLocalizationAndTheme(theme: currentChatTheme ?? theme)
                self.messageActionsPanelView = current
                self.addSubview(current, positioned: .above, relativeTo: container)
                current.updateLayout(size: current.frame.size, transition: .immediate)
                isNew = true
            }
            if isNew, animated {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        } else if let view = messageActionsPanelView {
            performSubviewRemoval(view, animated: animated)
            messageActionsPanelView = nil
        }

        func installStateView(_ view: ChatInputStateView, hideContainer: Bool = true) {
            self.stateView = view
            self.addSubview(view)
            if morphsOut {
                view.updateLayout(size: view.frame.size, transition: .immediate)
            }
            if animated {
                view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            self.contentView.change(opacity: 0.0, animated: animated)
            if !morphsOut {
                self.contentView.isHidden = true
                if hideContainer {
                    self.container.isHidden = true
                }
            }
        }

        switch state {
        case .normal, .editing:
            self.contentView.isHidden = false
            self.contentView.change(opacity: 1.0, animated: animated)
            self.container.isHidden = false
            if wasRecording, animated, morphInSlots == nil {
                self.container.layer?.animateAlpha(from: 0.1, to: 1, duration: 0.25, timingFunction: .spring)
            }
        case .selecting:
            self.contentView.change(opacity: 0.0, animated: animated)
            if !morphsOut {
                self.contentView.isHidden = true
                self.container.isHidden = true
            }
        case let .block(string):
            if !string.isEmpty {
                let view = ChatInputBlockView(frame: bounds)
                view.update(text: string, context: chatInteraction.interactionContext)
                installStateView(view)
            }
        case let .action(text, action, rightAddition, leftAddition, accent):
            if let view = reusableActionView {
                view.update(text: text, action: action, chatInteraction: chatInteraction, rightAdditionData: rightAddition, leftAdditionData: leftAddition, accent: accent, animated: true)
            } else {
                let view = ChatInputActionButtonView(frame: bounds)
                view.update(text: text, action: action, chatInteraction: chatInteraction, rightAdditionData: rightAddition, leftAdditionData: leftAddition, accent: accent)
                installStateView(view)
            }
        case let .botStart(text, action):
            let view = ChatInputActionButtonView(frame: bounds)
            view.update(text: text, action: action, chatInteraction: chatInteraction, isBot: true)
            installStateView(view)
        case let .channelWithDiscussion(discussionGroupId, leftAction, rightAction):
            let view = ChatInputDiscussionView(frame: bounds)
            view.update(chatInteraction: chatInteraction, discussionGroupId: discussionGroupId, leftAction: leftAction, rightAction: rightAction)
            installStateView(view)
        case let .frozen(action):
            let view = ChatInputFrozenView(frame: bounds)
            view.update(action: action, chatInteraction: chatInteraction)
            installStateView(view)
        case .recording:
            if !morphsOut {
                textView.isHidden = true
                textFieldContainer.isHidden = true
                attachView.isHidden = true
                sendButton.isHidden = true
                self.container.isHidden = true
            }
            inputDidUpdateLayout(animated: animated)
        case let .restricted(text):
            let view = ChatInputRestrictedView(frame: bounds)
            view.update(text: text)
            installStateView(view)
        }

        if morphsOut, let inputVisibleSlots {
            morphGlassOut(into: glassMorphPanel, from: inputVisibleSlots)
        }

        if let peer = chatInteraction.presentation.peer, let text = permissionText(from: peer, for: .banSendText, cachedData: chatInteraction.presentation.cachedData), state == .normal {
            let context = chatInteraction.interactionContext
            let current: Control
            if let view = self.disallowText {
                current = view
            } else {
                current = Control(frame: textView.frame)
                self.contentView.addSubview(current)
                self.disallowText = current
            }
            current.removeAllHandlers()
            current.set(handler: { _ in
                showModalText(for: context.window, text: text)
            }, for: .Click)
            current.setAccessibilityLabel(text)
            current.set(cursor: .arrow, for: .Normal)
            current.set(cursor: .arrow, for: .Highlight)
            current.set(cursor: .arrow, for: .Hover)
        } else if let view = self.disallowText {
            performSubviewRemoval(view, animated: animated)
            self.disallowText = nil
        }

        CATransaction.commit()
    }
    
    public func updateInput(_ state:ChatPresentationInterfaceState, prevState: ChatPresentationInterfaceState, animated:Bool = true, initial: Bool = false) -> Void {
        
        if let peer = state.peer, let _ = permissionText(from: peer, for: .banSendText, cachedData: state.cachedData), state.state == .normal {
            textView.inputView.isEditable = false
            textView.isHidden = false
        } else {
            switch state.state {
            case .normal, .editing:
                textView.inputView.isEditable = true
                textView.isHidden = false
            case let .block(string):
                textView.isHidden = !string.isEmpty
            default:
                textView.inputView.isEditable = false
            }
        }
        
        let input = state.effectiveInput
        
        self.textView.interactions.inputIsEnabled = self.isEnabled()
        self.textView.set(input)
        let placeholder = textPlaceholder
        self.textView.placeholder = placeholder
        self.textView.inputView.setAccessibilityLabel(placeholder)
        
        if prevState.effectiveInput.inputText.isEmpty {
            self.textView.scrollToCursor()
        }

        if state.effectiveInput != prevState.effectiveInput {
            if state.effectiveInput.inputText.count != prevState.effectiveInput.inputText.count {
                self.textView.scrollToCursor()
            }
        }
        
        if chatInteraction.interactionContext.peerId != chatInteraction.peerId, let peer = chatInteraction.presentation.peer, !peer.isChannel && !markNextTextChangeToFalseActivity {
            sendActivityDisposable.set((Signal<Bool, NoError>.single(!state.effectiveInput.inputText.isEmpty) |> then(Signal<Bool, NoError>.single(false) |> delay(4.0, queue: Queue.mainQueue()))).start(next: { [weak self] isPresent in
                if let chatInteraction = self?.chatInteraction, let peer = chatInteraction.presentation.peer, !peer.isChannel && chatInteraction.presentation.state != .editing {
                    if self?.chatInteraction.peerIsAccountPeer == true {
                        chatInteraction.interactionContext.account.updateLocalInputActivity(peerId: .init(peerId: peer.id, category: chatInteraction.mode.activityCategory(chatInteraction.chatLocation.threadId)), activity: .typingText, isPresent: isPresent)
                    }
                }
            }))
        }
        markNextTextChangeToFalseActivity = false
        
        actionsView.notify(with: state, oldValue: prevState, animated: animated)
        
    }
    private var updateFirstTime: Bool = true
    public func updateAdditions(_ state:ChatPresentationInterfaceState, _ animated:Bool = true) -> Void {
        accessory.update(with: state, context: chatInteraction.interactionContext, animated: animated)

        accessoryDisposable.set(accessory.nodeReady.get().start(next: { [weak self] animated in
            self?.updateAccesory(animated: animated)
        }))
        let placeholder = textPlaceholder
        self.textView.placeholder = placeholder
        self.textView.inputView.setAccessibilityLabel(placeholder)
    }
    
    public func updatePlaceholder() {
        let placeholder = textPlaceholder
        self.textView.placeholder = placeholder
        self.textView.inputView.setAccessibilityLabel(placeholder)
    }
    
    private func updateAccesory(animated: Bool) {
        self.accessory.measureSize(self.textFieldContainer.frame.width - 35)
        self.inputDidUpdateLayout(animated: animated)
        if self.updateFirstTime {
            self.updateFirstTime = false
            self.textView.scrollToCursor()
        }
    }
    
    
    public func updateAttachments(_ inputState:ChatPresentationInterfaceState, _ animated:Bool = true) -> Void {
        var updated: Bool = false
        if let botMenu = inputState.botMenu, !botMenu.isEmpty {
            let current: ChatInputMenuView
            if let view = self.botMenuView {
                current = view
            } else {
                current = ChatInputMenuView(frame: .zero)
                self.botMenuView = current
                contentView.addSubview(current)
                current.setInnerGlassHidden(true)
                current.setSharedGlassGhost(botMenuGhost)

                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                updated = true
            }
            current.chatInteraction = self.chatInteraction
            // The outer frame, the compact toggle, and the internal layout
            // are all driven by `ChatInputContainerView.updateLayout` so the
            // pill resize rides the same transition as attach/text positions.
        } else {
            if let view = self.botMenuView {
                self.botMenuView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
                updated = true
            }
        }
        var anim = animated
        var appearingSendAs: ChatInputSendAsView?
        let hasSendAs = inputState.sendAsPeers?.isEmpty == false
        if let sendAsPeers = inputState.sendAsPeers, !sendAsPeers.isEmpty && inputState.state == .normal {
            let current: ChatInputSendAsView
            if let view = self.sendAsView {
                current = view
            } else {
                current = ChatInputSendAsView(frame: NSMakeRect(0, 0, 34, 34))
                self.sendAsView = current
                textFieldContainer.addSubview(current)
                let returns = animated && sendAsHiddenByState && window != nil
                anim = returns
                appearingSendAs = returns ? current : nil
                updated = true
            }
            current.update(sendAsPeers, currentPeerId: inputState.currentSendAsPeerId ?? self.chatInteraction.interactionContext.peerId, chatInteraction: self.chatInteraction, animated: animated, photoSize: 34)
        } else {
            if let view = self.sendAsView {
                self.sendAsView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
                updated = true
            }
        }
        sendAsHiddenByState = hasSendAs && inputState.state != .normal
        if updated {
            updateLayout(size: frame.size, transition: anim ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        }
        if let view = appearingSendAs {
            view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            view.layer?.animateScaleCenter(from: 0.01, to: 1, duration: 0.2, timingFunction: .easeOut)
        }
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {


        let keyboardWidth = frame.width - 26
        let keyboardInset: CGFloat = 3
        // keyboardGlass + bottomView positioning lives in ChatInputContainerView
        // now (they're its subviews); ChatInputView just sets the container frame.

        if let view = messageEffect {
            transition.updateFrame(view: view, frame: NSMakeRect(size.width - view.frame.width - 10, 5, view.frame.width, view.frame.height))
        }

        if let markup = replyMarkupModel, markup.hasButtons, let view = markup.view {
            markup.measureSize(keyboardWidth - keyboardInset * 2)
            transition.updateFrame(view: view, frame: NSMakeRect(0, 0, markup.size.width, markup.size.height))
            markup.layout(transition: transition)
        }

        if let view = stateView {
            transition.updateFrame(view: view, frame: size.bounds)
            view.updateLayout(size: size, transition: .immediate)
        }

        // The container fills ChatInputView so every child it lays out
        // (contentView, textFieldContainer, glass, keyboard markup) is inside
        // its frame and hit-tests by default. Its internal layout uses the
        // stored `bottomHeight` to shift the input row UP above the keyboard
        // markup area when shown.
        transition.updateFrame(view: container, frame: size.bounds)
        container.bottomHeight = bottomHeight
        container.updateLayout(transition: transition)

        if let view = recordingPanelView {
            let edge: CGFloat = 12
            let sendWidth = sendButton.frame.width
            let sendMinX = size.width - edge - sendWidth
            let recContentY = contentView.frame.origin.y
            let totalHeight = standart

            let panelMinX: CGFloat = edge
            let panelWidth = size.width - edge - panelMinX
            let panelFrame = NSMakeRect(panelMinX, recContentY, panelWidth, totalHeight)
            transition.updateFrame(view: view, frame: panelFrame)

            let sendCenter = NSMakePoint(sendMinX + sendWidth / 2, standart / 2)
            view.updateSendButtonCenter(NSMakePoint(sendCenter.x - panelMinX, sendCenter.y), transition: transition)
            view.updateLayout(size: panelFrame.size, transition: transition)
        }

        if let view = disallowText {
            transition.updateFrame(view: view, frame: textView.frame)
        }
                
        if let view = paidMessageView {
            transition.updateFrame(view: view, frame: size.bounds)
        }

        if let view = messageActionsPanelView {
            transition.updateFrame(view: view, frame: size.bounds)
            view.updateLayout(size: size, transition: .immediate)
        }
        
        guard let superview = superview else { return }
        textInteractions.max_height = floorToScreenPixels(backingScaleFactor, superview.frame.height / 2) + 50.0

    }

    public func updateFloatingColumnAnchor(_ anchor: NSPoint?, transition: ContainedViewLayoutTransition) {
        recordingPanelView?.updateColumnAnchor(anchor, transition: transition)
    }
    
    
    public override func layout() {
        super.layout()
        
    }
    
    
    public var stringValue:String {
        return textView.string() 
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    /// Compose + send the inline (text-only) editor's current content. Mirrors the modal editor's send:
    /// structural content → a rich `InstantPage` message (routed through `sendMessage`, which keeps the
    /// slow-mode / permission checks + the empty-content guard); content reduced to plain text → a normal
    /// text+entities message; empty → an error.
    /// Return inside the inline editor → send. `sendMessage` flushes the live editor into the draft (and runs
    /// the empty-content guard); here we just surface the empty error early for the common no-content case.
    private func sendInlineRichDraft() {
        if let blocks = container.richDraftPreview?.currentOutgoing(), !richTextOutgoingHasContent(blocks) {
            showModalText(for: chatInteraction.interactionContext.window, text: strings().chatInputEmptyMessageError)
            return
        }
        chatInteraction.sendMessage(false, nil, chatInteraction.presentation.messageEffect)
    }

    public func inputDidUpdateLayout(animated: Bool) {
        delegate?.inputChanged(height: height(for: self.frame.width), animated: animated)
    }
    
    public var currentActionView: NSView {
        return self.sendButton.currentActionView
    }

    private static func sendButtonState(
        from value: ChatPresentationInterfaceState,
        hasRichDraft: Bool = false,
        canStopIncomingStreamingMessage: Bool = false
    ) -> ChatInputSendButton.State {
        let isInlineLoading: Bool = {
            if let query = value.inputQueryResult, case let .contextRequestResult(peer, data) = query {
                if let address = peer.addressName, "@\(address)" != value.effectiveInput.inputText {
                    return data == nil
                }
            }
            return false
        }()

        let hasInlineRequest: Bool = {
            if let query = value.inputQueryResult, case .contextRequestResult = query {
                return true
            }
            return false
        }()

        let slowModeActive = ((value.slowMode?.timeout != nil && !value.restrictedByBoosts) || value.boostNeed > 0)
            && value.interfaceState.editState == nil
            && !isInlineLoading
            && !hasInlineRequest

        let hasContent = !value.effectiveInput.inputText.isEmpty
            || !value.interfaceState.forwardMessageIds.isEmpty
            || value.state == .editing
            || value.chatMode.customChatLink != nil
            || hasRichDraft   // a structural rich draft is sendable even though the text input is empty

        let kind: ChatInputSendButton.State.Kind
        if canStopIncomingStreamingMessage {
            kind = .stop
        } else if slowModeActive {
            let text: String
            if let timeout = value.slowMode?.timeout, timeout >= 0 {
                let minutes = timeout / 60
                let seconds = timeout % 60
                text = String(format: "%@:%@", minutes < 10 ? "0\(minutes)" : "\(minutes)", seconds < 10 ? "0\(seconds)" : "\(seconds)")
            } else {
                text = ""
            }
            kind = .slowMode(text: text, isBoost: value.boostNeed > 0)
        } else if hasInlineRequest && !isInlineLoading {
            kind = .inlineCancel
        } else if hasContent, let stars = value.sendPaidMessageStars {
            let messagesCount = (value.interfaceState.inputState.inputText.isEmpty ? 0 : 1) + value.interfaceState.forwardMessages.count
            kind = .paidStars(amount: stars.value * Int64(messagesCount))
        } else if hasContent {
            kind = .send
        } else {
            kind = .voice
        }

        let isSendEnabled: Bool = value.chatMode.customChatLink == nil || !value.effectiveInput.inputText.isEmpty

        return ChatInputSendButton.State(
            kind: kind,
            isEditing: value.state == .editing,
            isSendEnabled: isSendEnabled,
            isInlineLoading: isInlineLoading
        )
    }
    public var emojiView: NSView {
        return self.actionsView.entertaiments
    }
    public func makeSpoiler() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.spoiler))
    }
    public func makeUnderline() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.underline))
    }
    public func makeQuote() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.quote))
    }
    public func makeStrikethrough() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.strikethrough))
    }
    public func makeBold() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.bold))
    }
    public func removeAllAttributes() {
        self.textView.inputApplyTransform(.clear)
    }
    public func makeUrl() {
        self.textView.inputApplyTransform(.url)
    }
    public func makeItalic() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.italic))
    }
    public func makeMonospace() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.monospace))
    }
    
    public override func becomeFirstResponder() -> Bool {
        // Focus the inline rich editor when one is active (the plain field is hidden), so the draft is editable.
        if let editor = container.richDraftPreview?.editorResponder {
            return window?.makeFirstResponder(editor) ?? false
        }
        return self.textView.inputView.becomeFirstResponder()
    }
    
    public func makeFirstResponder()  {
        self.window?.makeFirstResponder(self.responder)
    }
    
    
    deinit {
        self.accessoryDisposable.dispose()
        self.rtfAttachmentsDisposable.dispose()
        self.slowModeUntilDisposable.dispose()
        self.richDraftDisposable.dispose()
        self.incomingTypingDraftDisposable.dispose()
        self.chatInteraction.interactionContext.window.remove(object: self, for: .Return)
        self.chatInteraction.interactionContext.window.remove(object: self, for: .Delete)
        self.chatInteraction.interactionContext.window.remove(object: self, for: .Z, modifierFlags: [.command], forceCheckFlags: true)
        self.chatInteraction.interactionContext.window.remove(object: self, for: .Z, modifierFlags: [.command, .shift], forceCheckFlags: true)
        self.chatInteraction.remove(observer: self)
    }
    
    public func isEnabled() -> Bool {
        if let editState = chatInteraction.presentation.interfaceState.editState {
            if editState.loadingState != .none {
                return false
            }
        }
        if case let .customChatContents(contents) = chatInteraction.mode,
           contents.kind == .welcomeMessages,
           chatState != .editing,
           let limit = contents.messageLimit,
           let historyCount = chatInteraction.presentation.historyCount,
           historyCount >= limit {
            return false
        }
        return self.chatState == .normal || self.chatState == .editing
    }
    
    
    public func copyAttributedString(_ attributedString: NSAttributedString!) -> Bool {
        return LinkHooks.shared.globalLinkExecutor().copyAttributedString(attributedString)
    }
    
    public func processPaste(_ pasteboard: NSPasteboard) -> Bool {
        
        let interaction = self.chatInteraction
        
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.textView.scrollToCursor()
            }
        }
        
        if let window = _window, self.chatState == .normal || self.chatState == .editing {

            // Pasting a selection copied from a rendered rich-text message → open the rich editor seeded with
            // it (instead of dropping it into the plain input), preserving inline formatting AND formulas
            // (which the flat clipboard can't carry). The attributed selection is archived by the copy path.
            // A media-bearing rich message → refetch it and seed the editor with its FULL content (media
            // included); the flat Document below can't carry media.
            if #available(macOS 12, *), interaction.interactionContext.appConfiguration.isRichTextEditorEnabled, let refData = pasteboard.data(forType: .kRichTextMessageRef),
               let ref = String(data: refData, encoding: .utf8) {
                let parts = ref.split(separator: ":").compactMap { Int64($0) }
                if parts.count == 3 {
                    let messageId = MessageId(peerId: PeerId(parts[0]), namespace: Int32(clamping: parts[1]), id: Int32(clamping: parts[2]))
                    showRichTextEditor(chatInteraction: interaction, refetching: messageId)
                    return true
                }
            }
            if #available(macOS 12, *), interaction.interactionContext.appConfiguration.isRichTextEditorEnabled, let data = pasteboard.data(forType: .kRichTextMessage),
               let document = try? JSONDecoder().decode(Document.self, from: data) {
                showRichTextEditor(chatInteraction: interaction, seeding: document)
                return true
            }
            // A fragment copied inside the rich editor itself (⌘C in the editor, pasted after closing it):
            // same JSON `Document` payload under the editor's own pasteboard type.
            if #available(macOS 12, *), interaction.interactionContext.appConfiguration.isRichTextEditorEnabled, let data = pasteboard.data(forType: .richTextEditorFragment),
               let document = try? JSONDecoder().decode(Document.self, from: data), !document.blocks.isEmpty {
                showRichTextEditor(chatInteraction: interaction, seeding: document)
                return true
            }

            if let string = pasteboard.string(forType: .string) {
                interaction.update { current in
                    if let disabled = current.interfaceState.composeDisableUrlPreview, disabled.lowercased() == string.lowercased() {
                        return current.updatedInterfaceState {$0.withUpdatedComposeDisableUrlPreview(nil)}
                    }
                    return current
                }
            }
            
            let result = InputPasteboardParser.proccess(pasteboard: pasteboard, chatInteraction: interaction, window: window)
            if result {
                if let disallowText = disallowText {
                    disallowText.send(event: .Click)
                    textView.shake(beep: true)
                } else {
                    if let data = pasteboard.data(forType: .kInApp) {
                        let decoder = AdaptedPostboxDecoder()
                        if let decoded = try? decoder.decode(ChatTextInputState.self, from: data) {
                            let state = decoded.unique(isPremium: interaction.interactionContext.isPremium)
                            
                            interaction.appendText(state.attributedString())
                            
                            return true
                        }
                    } else if let data = pasteboard.data(forType: .rtf) {
                        if let attributed = (try? NSAttributedString(data: data, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)) ?? (try? NSAttributedString(data: data, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))  {
                            
                            let (attributed, attachments) = attributed.applyRtf()
                            
                            if !attachments.isEmpty {
                                rtfAttachmentsDisposable.set((prepareTextAttachments(attachments) |> deliverOnMainQueue).start(next: { [weak self] urls in
                                    if !urls.isEmpty, let interaction = self?.chatInteraction {
                                        interaction.showPreviewSender(urls, true, attributed)
                                    } else if urls.isEmpty {
                                    }
                                }))
                            } else {
                                self.chatInteraction.appendText(attributed)
                            }
                            return true
                        }
                    }
                }
            }
            return !result
        }
        
        return self.chatState != .normal
    }
    
}
