import Foundation
import Cocoa
import TGUIKit
import InputView
import ColorPalette
import SwiftSignalKit
import TelegramMedia
import Translate
import TelegramCore
import Postbox
import Localization
import InAppSettings
import TelegramUtils
import TelegramContext
import TelegramTheme
import InlineStickerLayer

public final class InputAnimatedEmojiAttach: View {
    
    fileprivate var attachmentValue: TextInputTextCustomEmojiAttribute?
    fileprivate var size: NSSize?
    fileprivate var textColor: NSColor?
    fileprivate var context: (any AccountContextProtocol)?
    
    private var media: InlineStickerItemLayer!
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
    }
    
    public var fileId: Int64 {
        return media.fileId
    }
    
    public func set(_ attachment: TextInputTextCustomEmojiAttribute, size: NSSize, context: any AccountContextProtocol, textColor: NSColor, playPolicy: LottiePlayPolicy = .loop) -> Void {
        
       
        if media != nil {
            self.media.removeFromSuperlayer()
        }
        
        let fileId = attachment.fileId
        let file = attachment.file
        
        self.attachmentValue = attachment

        self.context = context
        self.size = size
        self.textColor = textColor
        
        
        self.media = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: file, emoji: ""), size: size, playPolicy: playPolicy, textColor: textColor)
        
        self.media.superview = self
        let mediaRect = self.focus(media.frame.size)
        
        self.media.isPlayable = !TelegramUtilsHooks.shared.isLite(.emoji)
        self.media.frame = mediaRect
        self.layer?.addSublayer(media)
                
        needsLayout = true
    }
    
    public func updatePlayPolicy(_ playPolicy: LottiePlayPolicy) {
        if let attachmentValue, let size, let context, let textColor {
            self.set(attachmentValue, size: size, context: context, textColor: textColor, playPolicy: playPolicy)
        }
    }
    
    public override func layout() {
        super.layout()
        guard let media = self.media else {
            return
        }
        media.frame = focus(media.frame.size)

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}






public final class TextView_Interactions : InterfaceObserver {
    public var presentation: Updated_ChatTextInputState
    
    public var max_height: CGFloat = 40
    public var min_height: CGFloat = 40
    public var max_input: Int = 100000
    public var supports_continuity_camera: Bool = false
    public var inputIsEnabled: Bool = true
    public var canTransform: Bool = true
    public var simpleTransform: Bool = false
    public var emojiPlayPolicy: LottiePlayPolicy = .loop
    
    public var allowedLinkHosts: [String] = []
    
    public init(presentation: Updated_ChatTextInputState = .init()) {
        self.presentation = presentation
    }
    
    public func update(animated:Bool = true, _ f:(Updated_ChatTextInputState)->Updated_ChatTextInputState)->Void {
        let oldValue = self.presentation
        let presentation = f(oldValue)
        self.presentation = presentation
        if oldValue != presentation {
            self.notifyObservers(value: presentation, oldValue:oldValue, animated:animated)
        }
    }
    
    public func insertText(_ text: NSAttributedString, selectedRange:Range<Int>? = nil) -> Updated_ChatTextInputState {
        
        var selectedRange = selectedRange ?? presentation.selectionRange
        let inputText = presentation.inputText.mutableCopy() as! NSMutableAttributedString
        
        if selectedRange.upperBound - selectedRange.lowerBound > 0 {
            inputText.replaceCharacters(in: NSMakeRange(selectedRange.lowerBound, selectedRange.upperBound - selectedRange.lowerBound), with: text)
            selectedRange = selectedRange.lowerBound ..< selectedRange.lowerBound
        } else {
            inputText.insert(text, at: selectedRange.lowerBound)
        }
        
        let nRange:Range<Int> = selectedRange.lowerBound + text.length ..< selectedRange.lowerBound + text.length
        return Updated_ChatTextInputState(inputText: inputText, selectionRange: nRange)
    }
    
    public var inputDidUpdate:((Updated_ChatTextInputState)->Void) = { _ in }
    public var processEnter:(NSEvent)->Bool = { event in return InputTextViewHooks.shared.checkSendingAbility(event) }
    public var processPaste:(NSPasteboard)->Bool = { _ in return false }
    public var processAttriburedCopy: (NSAttributedString) -> Bool = { _ in return false }
    public var responderDidUpdate:()->Void = { }
    
    public var filterEvent: (NSEvent)->Bool = { _ in return true }
}


public final class UITextView : View, Notifable, ChatInputTextViewDelegate {
    public func inputViewIsEnabled(_ event: NSEvent) -> Bool {
        return interactions.filterEvent(event) && interactions.inputIsEnabled
    }
    
    public func inputViewProcessEnter(_ theEvent: NSEvent) -> Bool {
        return interactions.processEnter(theEvent)
    }
    
    public func inputViewMaybeClosed() -> Bool {
        return false
    }
    public func inputMaximumHeight() -> CGFloat {
        return max_height
    }
    public func inputMaximumLenght() -> Int {
        return max_input_length
    }
    public func inputViewSupportsContinuityCamera() -> Bool {
        return supports_continuity_camera
    }
    public func inputViewProcessPastepoard(_ pboard: NSPasteboard) -> Bool {
        return self.interactions.processPaste(pboard)
    }
    public func inputViewCopyAttributedString(_ attributedString: NSAttributedString) -> Bool {
        return self.interactions.processAttriburedCopy(attributedString)
    }
    
    public func inputViewResponderDidUpdate() {
        self.interactions.responderDidUpdate()
    }
    
    public var inputTheme: InputViewTheme = theme.inputTheme {
        didSet {
            let placeholder = self.placeholder
            self.placeholder = placeholder
            self.view.theme = inputTheme
            self.chatInputTextViewDidUpdateText()
        }
    }
    public var placeholderFontSize: CGFloat? = nil
    public var placeholder: String = "" {
        didSet {
            self.view.placeholderString = .initialize(string: placeholder, color: inputTheme.grayTextColor, font: .normal(placeholderFontSize ?? inputTheme.fontSize))
        }
    }
    public var placeholderMaxLines: Int32 {
        get { return self.view.placeholderMaxLines }
        set { self.view.placeholderMaxLines = newValue }
    }
    
    private var revealSpoilers: Bool = false {
        didSet {
            self.updateInput(current: self.interactions.presentation, previous: self.interactions.presentation)
        }
    }
    
    private let delayDisposable = MetaDisposable()
    
    private var updatingInputState: Bool = false
    
    public var isEmpty: Bool {
        return self.inputTextState.inputText.string.isEmpty
    }
    
    public func chatInputTextViewDidUpdateText() {
        refreshInputView()
        
        let inputTextState = self.inputTextState
     
        self.interactions.update { _ in
            return inputTextState
        }
    }
    
    public var inputTextState: Updated_ChatTextInputState {
        let selectionRange: Range<Int> = view.selectedRange.location ..< (view.selectedRange.location + view.selectedRange.length)
        return Updated_ChatTextInputState(inputText: stateAttributedStringForText(view.attributedText.copy() as! NSAttributedString), selectionRange: selectionRange)
    }

    private func refreshInputView() {
        refreshTextInputAttributes(self.view.textView, theme: inputTheme, spoilersRevealed: revealSpoilers, availableEmojis: Set())
       // refreshChatTextInputTypingAttributes(self.view.textView, theme: inputTheme)
    }
    
    public func chatInputTextViewDidChangeSelection(dueToEditing: Bool) {
        if !dueToEditing && !self.updatingInputState {
            refreshInputView()
            let inputTextState = self.inputTextState
            interactions.update { _ in
                inputTextState
            }
        }

    }
    
    public func chatInputTextViewDidBeginEditing() {
        
    }
    
    public func chatInputTextViewDidFinishEditing() {
        
    }
    
    public func chatInputTextView(shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return true
    }
    
    public func chatInputTextViewShouldCopy() -> Bool {
        return true
    }
    
    public func chatInputTextViewShouldPaste() -> Bool {
        return true
    }
    
    public func inputTextCanTransform() -> Bool {
        return interactions.canTransform
    }
    
    public func inputTextSimpleTransform() -> Bool {
        return interactions.simpleTransform
    }
    
    public func inputViewRevealSpoilers() {
        self.revealSpoilers = true
        delayDisposable.set(delaySignal(5.0).start(completed: { [weak self] in
            self?.revealSpoilers = false
        }))
    }

    public func inputApplyDateEdit(range: NSRange, currentDate: Int32) {
        guard let window = _window, let context = self.context else { return }
        let defaultDate = Date(timeIntervalSince1970: TimeInterval(currentDate))
        InputTextViewHooks.shared.showDateSelector(context, window, defaultDate, { [weak self] date in
            self?.interactions.update { current in
                return chatTextInputAddDateAttribute(current, selectionRange: range.min ..< range.max, date: Int32(date.timeIntervalSince1970))
            }
        })
    }

    public func inputTextCanTranslate() -> Bool {
        guard let context = self.context, !isSecretChat else { return false }
        let translateConfig = AppConfigTranslateState(rawValue: context.appConfiguration.getStringValue("translations_manual_enabled", orElse: "enabled")) ?? .disabled
        return translateConfig.canTranslate
    }

    public func inputTextTranslateLockIcon() -> NSImage? {
        guard let context = self.context else { return nil }
        if context.isPremium {
            return nil
        }
        return TelegramThemeHooks.shared.image(.iconPremiumLock)
    }

    public func inputTextTranslateSelected() {
        guard let context = self.context, let window = _window else { return }

        if !context.isPremium {
            InputTextViewHooks.shared.showPremiumBoardingObserved(context, window)
            return
        }

        let range = self.interactions.presentation.selectionRange
        let textRange = NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound)
        guard textRange.length > 0 else { return }

        let selected = self.interactions.presentation.inputText.attributedSubstring(from: textRange)
        let selectedText = selected.string
        let selectedEntities = ChatTextInputState(attributedText: selected, selectionRange: 0 ..< 0).messageTextEntities()

        let language = Translate.detectLanguage(for: selectedText)

        InputTextViewHooks.shared.showTranslateObserved(context, window, language, selectedText, selectedEntities, onUse: { [weak self] translated in
            guard let self else { return }
            self.interactions.update { current in
                return chatTextInputReplaceSelectedText(current, selectionRange: textRange.min..<textRange.max, text: translated)
            }
        })
    }

    public func inputApplyTransform(_ reason: InputViewTransformReason) {
        
        if !interactions.canTransform {
            return
        }
        switch reason {
        case let .attribute(attribute):
            self.interactions.update({ current in
                return chatTextInputAddFormattingAttribute(current, attribute: attribute)
            })
        case .url:
            let range = self.interactions.presentation.selectionRange
            let textRange = NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound)
            guard textRange.min != textRange.max, let window = _window else {
                return
            }
            
            let text = self.interactions.presentation.inputText.attributedSubstring(from: textRange)
            var link: String?
            text.enumerateAttributes(in: NSMakeRange(0, text.length)) { attributes, _, _ in
                if let linkAttribute = attributes[TextInputAttributes.textUrl] as? TextInputTextUrlAttribute {
                    link = linkAttribute.url
                }
            }
            
            InputTextViewHooks.shared.showURLFormatter(window, text.string, link, self.interactions.allowedLinkHosts, { [weak self] text, url in
                
                self?.interactions.update { current in
                    var current = current
                    if let url = url {
                        current = chatTextInputAddLinkAttribute(current, selectionRange: textRange.min ..< textRange.max, url: url, text: text)
                    } else {
                        current = chatTextInputClearFormattingAttributes(current, targetKey: TextInputAttributes.textUrl)
                    }
                    return current
                }
            })
            
        case .date:
            let range = self.interactions.presentation.selectionRange
            let textRange = NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound)
            guard textRange.min != textRange.max, let window = _window, let context = self.context else {
                return
            }

            var existingDate: Int32? = nil
            let text = self.interactions.presentation.inputText.attributedSubstring(from: textRange)
            text.enumerateAttributes(in: NSMakeRange(0, text.length)) { attributes, _, _ in
                if let dateAttr = attributes[TextInputAttributes.formattedDate] as? TextInputTextDateAttribute {
                    existingDate = dateAttr.date
                }
            }

            let defaultDate: Date
            if let existingDate = existingDate {
                defaultDate = Date(timeIntervalSince1970: TimeInterval(existingDate))
            } else {
                defaultDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970 + 60 * 60)
            }
            InputTextViewHooks.shared.showDateSelector(context, window, defaultDate, { [weak self] date in
                self?.interactions.update { current in
                    return chatTextInputAddDateAttribute(current, selectionRange: textRange.min ..< textRange.max, date: Int32(date.timeIntervalSince1970))
                }
            })
        case .clear:
            self.interactions.update({ current in
                return chatTextInputClearFormattingAttributes(current)
            })
        case let .toggleQuote(quote, range):
            self.interactions.update({ current in
                return chatTextInputAddQuoteAttribute(current, selectionRange: range.min ..< range.max, collapsed: !quote.collapsed, doNotUpdateSelection: true)
            })
            if let window = self._window {
                showModalText(for: window, text: !quote.collapsed ? strings().inputQuoteCollapsed : strings().inputQuoteExpanded)
            }
        }
    }
    
    public func insertText(_ string: NSAttributedString, range: Range<Int>? = nil) {
        let updatedText = self.interactions.insertText(string, selectedRange: range)
        self.interactions.update { _ in
            updatedText
        }
    }
    
    public func scrollToCursor() {
        self.view.scrollToCursor()
    }
    
    public func string() -> String {
        return self.inputTextState.inputText.string
    }
    
    public func highlight(for range: NSRange, whole: Bool) -> NSRect {
        return self.view.highlight(for: range, whole: whole)
    }
    
    public var inputView:NSTextView {
        return self.view.inputView
    }
    
    public var selectedRange: NSRange {
        return self.view.selectedRange
    }
    public var scrollView: ScrollView {
        return self.view
    }
    
    public var max_height: CGFloat {
        return interactions.max_height
    }
    public var max_input_length: Int {
        return interactions.max_input
    }
    public var min_height: CGFloat {
        return interactions.min_height
    }
    public var supports_continuity_camera: Bool {
        return interactions.supports_continuity_camera
    }
    
    public let view: ChatInputTextView
    
    private var passNext: Bool = false
    
    public var interactions: TextView_Interactions {
        didSet {
            oldValue.remove(observer: self)
            interactions.add(observer: self)
        }
    }
    
    public var context: (any AccountContextProtocol)?
    public var isSecretChat: Bool = false
    public required init(frame frameRect: NSRect, interactions: TextView_Interactions) {
        self.view = ChatInputTextView(frame: frameRect.size.bounds)
        self.interactions = interactions
        super.init(frame: frameRect)
        self.interactions.add(observer: self)
        addSubview(view)
        view.delegate = self
        
        self.view.emojiViewProvider = { [weak self] attachment, size, theme in
            let rect = size.bounds.insetBy(dx: -1.5, dy: -1.5)
            let view = InputAnimatedEmojiAttach(frame: rect)
            if let context = self?.context, let interactions = self?.interactions {
                view.set(attachment, size: rect.size, context: context, textColor: theme.textColor, playPolicy: interactions.emojiPlayPolicy)
            }
            return view
        }
    }
    
    public func updatePlayPolicy(_ playPolicy: LottiePlayPolicy) {
        for emoji in emojis {
            emoji.updatePlayPolicy(playPolicy)
        }
    }
    
    public var emojis:[InputAnimatedEmojiAttach] {
        return view.emojis.compactMap { $0 as? InputAnimatedEmojiAttach }
    }
    
    
    public override func layout() {
        super.layout()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, interactions: .init())
    }
    
    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? UITextView {
            return other === self
        }
        return false
    }
        
    
    public func set(_ input: ChatTextInputState) {
        if passNext {
            return
        }
        let inputState = input.textInputState()
        if self.interactions.presentation != inputState {
            self.interactions.update { _ in
                return inputState
            }
        }
    }
    
    public func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? Updated_ChatTextInputState, let oldValue = oldValue as? Updated_ChatTextInputState {
            passNext = true
            self.updateInput(current: value, previous: oldValue)
            passNext = false
        }
    }
    
    private func updateInput(current: Updated_ChatTextInputState, previous: Updated_ChatTextInputState) {
        
        self.updatingInputState = true
        

        
        let attributedText = textAttributedStringForStateText(current.inputText, fontSize: inputTheme.fontSize, textColor: inputTheme.textColor, accentTextColor: inputTheme.accentColor, writingDirection: nil, spoilersRevealed: revealSpoilers, availableEmojis: Set())
        
        
        let textViewAttributed = textAttributedStringForStateText(view.attributedText.copy() as! NSAttributedString, fontSize: inputTheme.fontSize, textColor: inputTheme.textColor, accentTextColor: inputTheme.accentColor, writingDirection: nil, spoilersRevealed: revealSpoilers, availableEmojis: Set())


        
        let selectionRange = NSMakeRange(current.selectionRange.lowerBound, current.selectionRange.count)

        if attributedText.string != textViewAttributed.string || chatTextAttributes(from: attributedText) != chatTextAttributes(from: textViewAttributed) {
            let undoItem = InputViewUndoItem(was: textViewAttributed, be: attributedText, wasRange: self.view.selectedRange, beRange: selectionRange)
            self.view.addUndoItem(undoItem)
        }
        
        refreshInputView()

        
        if previous != current {
            self.interactions.inputDidUpdate(current)
        }
        self.updatingInputState = false

    }
    
    public func updateLayout(size: NSSize, textHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self.view, frame: size.bounds)
        self.view.updateLayout(size: size, textHeight: textHeight, transition: transition)
    }
    
    public func height(for width: CGFloat) -> CGFloat {
        return self.view.textHeightForWidth(width)
    }

    public func numberOfLines(for width: CGFloat) -> Int {
        return self.view.numberOfLines(forWidth: width)
    }

    public func setToEnd() {
        self.interactions.update({ current in
            var current = current
            current.selectionRange = current.inputText.length ..< current.inputText.length
            return current
        })
    }
    
    public func selectAll() {
        self.interactions.update({ current in
            var current = current
            current.selectionRange = 0 ..< current.inputText.length
            return current
        })
    }
    
    public func makeFirstResponder() {
        self.window?.makeFirstResponder(self.inputView)
    }

    private var clickFocusMonitor: Any?

    public func installClickToFocus() {
        guard clickFocusMonitor == nil else { return }
//        self.clickFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
//            guard let self, let window = self.window, event.window === window, let target = self.superview else {
//                return event
//            }
//            let pointInTarget = target.convert(event.locationInWindow, from: nil)
//            if target.bounds.contains(pointInTarget) {
//                self.makeFirstResponder()
//            }
//            return event
//        }
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.inputTheme = theme.inputTheme
    }

    deinit {
        delayDisposable.dispose()
        if let monitor = clickFocusMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
