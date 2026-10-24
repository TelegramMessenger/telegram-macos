import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InputView
import InputTextView
import GeneralRows
import InputDataUI
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import InlineStickerLayer
import Localization


public class InputTextDataRowItem: GeneralRowItem, InputDataRowDataValue {

    fileprivate let placeholderLayout: TextViewLayout?
    fileprivate let placeholder: InputDataInputPlaceholder?
    
    fileprivate let inputPlaceholder: NSAttributedString
    fileprivate let filter:(String)->String
    public let limit:Int32
    
    fileprivate let state: Updated_ChatTextInputState
    fileprivate let updateState:(Updated_ChatTextInputState)->Void
    
    fileprivate let hasEmoji: Bool
    
    fileprivate let context: any AccountContextProtocol

    public var value: InputDataValue {
        return .attributedString(state.inputText)
    }
    
    public override var inset: NSEdgeInsets {
        var inset = super.inset
        switch viewType {
        case .legacy:
            break
        case .modern:
            if let errorLayout = errorLayout {
                inset.bottom += errorLayout.layoutSize.height + 4
            }
        }
        return inset
    }

    fileprivate let rightItem: InputDataRightItem?
    fileprivate let canMakeTransformations: Bool
    fileprivate let simpleTransform: Bool
    fileprivate let allowedLinkHosts: [String]
    fileprivate let playAnimation: Bool
    fileprivate let fitPlaceholderHeight: Bool
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, state: Updated_ChatTextInputState, viewType: GeneralViewType, placeholder: InputDataInputPlaceholder?, inputPlaceholder: String, rightItem: InputDataRightItem? = nil, canMakeTransformations: Bool = false, simpleTransform: Bool = true, filter:@escaping(String)->String, updateState:@escaping(Updated_ChatTextInputState)->Void, limit: Int32, hasEmoji: Bool = false, allowedLinkHosts: [String] = [], playAnimation: Bool = true, enabled: Bool = true, fitPlaceholderHeight: Bool = false) {
        self.filter = filter
        self.limit = limit
        self.context = context
        self.placeholder = placeholder
        self.hasEmoji = hasEmoji
        self.allowedLinkHosts = allowedLinkHosts
        self.canMakeTransformations = canMakeTransformations
        self.simpleTransform = simpleTransform
        self.rightItem = rightItem
        self.updateState = updateState
        self.playAnimation = playAnimation
        self.fitPlaceholderHeight = fitPlaceholderHeight
        self.state = state
        self.inputPlaceholder = .initialize(string: inputPlaceholder, color: theme.colors.grayText, font: .normal(.text))
        self.placeholderLayout = placeholder?.placeholder != nil ? TextViewLayout(.initialize(string: placeholder!.placeholder!, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1) : nil
        super.init(initialSize, stableId: stableId, viewType: viewType, enabled: enabled)
    }
    
    public var textFieldLeftInset: CGFloat {
        if let placeholder = placeholder {
            if let placeholder = placeholder.placeholder {
                if placeholder.trimmingCharacters(in: CharacterSet(charactersIn: "0987654321")).isEmpty {
                    return 30
                } else {
                    return 102
                }
            } else {
                if let icon = placeholder.icon {
                    return icon.backingSize.width + 6 + placeholder.insets.left
                } else {
                    return -2
                }
            }
        } else {
            return -2
        }
    }
    
    public var hasTextLimitation: Bool {
        if self.height == 16 + (viewType.innerInset.top + viewType.innerInset.bottom) {
            return false
        }
        if let placeholder = placeholder {
            return placeholder.hasLimitationText
        } else {
            return limit > 5
        }
    }
    
    public var textWidth: CGFloat {
        var width = blockWidth - viewType.innerInset.left - viewType.innerInset.right - 4
        if hasEmoji {
            width -= 24
        }
        if let placeholder = placeholder, let icon = placeholder.icon {
            width -= (icon.backingSize.width + viewType.innerInset.left)
        }
        if let rightItem {
            switch rightItem {
            case .action(let cGImage, _), .actionWithLoading(let cGImage, _):
                width -= (cGImage.backingSize.width + 5)
            case .loading:
                width -= 20
            case .media:
                width -= 26
            }
        }
        return width
    }
    
    public override var height: CGFloat {
        let attr = NSMutableAttributedString()
        attr.append(string: self.state.inputText.string)

        attr.addAttribute(.font, value: NSFont.normal(.text), range: attr.range)
        let height = InputTextView.rawTextHeight(for: attr, width: textWidth)

        var minHeight: CGFloat = 16
        if fitPlaceholderHeight {
            let placeholderAttr = NSMutableAttributedString()
            placeholderAttr.append(string: inputPlaceholder.string)
            placeholderAttr.addAttribute(.font, value: NSFont.normal(.text), range: placeholderAttr.range)
            minHeight = max(minHeight, InputTextView.rawTextHeight(for: placeholderAttr, width: textWidth))
        }

        return max(minHeight, height) + (viewType.innerInset.top + viewType.innerInset.bottom)
    }
    
    private(set) fileprivate var additionRightInset: CGFloat = 0
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        placeholderLayout?.measure(width: 100)
        return success
    }
    
    public override func viewClass() -> AnyClass {
        return InputTextDataRowView.self
    }

    public override var accessibilityLabel: String? {
        if let text = placeholder?.placeholder, !text.isEmpty {
            return text
        }
        return inputPlaceholder.string.isEmpty ? nil : inputPlaceholder.string
    }
    
}

public class InputTextDataRowView : GeneralContainableRowView {
    private let placeholderTextView = TextView()
    private let rightActionView: ImageButton = ImageButton()
    private var loadingView: ProgressIndicator? = nil
    private var mediaLoadingView: RadialProgressView? = nil
    private var placeholderAction: ImageButton?
    internal let textView: UITextView = UITextView(frame: NSZeroRect)
    private let textLimitation: TextViewLabel = TextViewLabel(frame: NSMakeRect(0, 0, 16, 14))

    private let inputSwapDisposable = MetaDisposable()

    private var emoji: ImageButton?
    private var textInputSuggestionsView: InputSwapSuggestionsPanel?
    private var mediaImageView: TransformImageView?
    private var mediaStickerView: InlineStickerView?
    private var mediaOverlay: Control?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(placeholderTextView)
        self.addSubview(textView)
        self.addSubview(rightActionView)
        self.addSubview(textLimitation)
        rightActionView.autohighlight = false
        
        textView.scrollView.applyExternalScroll = { [weak self] event in
            self?.superview?.scrollWheel(with: event)
            return true
        }
        
        containerView.userInteractionEnabled = false
        
        textLimitation.alignment = .right
        
        
        placeholderTextView.userInteractionEnabled = false
        placeholderTextView.isSelectable = false
              
    }
    
    
    public func updateTextInputSuggestions(_ files: [TelegramMediaFile], range: NSRange, animated: Bool) {
        
        guard let item = item as? InputTextDataRowItem, let content = item.table?.superview?.superview else {
            return
        }
        
        let context = item.context
        
        if !files.isEmpty {
            let current: InputSwapSuggestionsPanel
            let isNew: Bool
            if let view = self.textInputSuggestionsView {
                current = view
                isNew = false
            } else {
                current = InputSwapSuggestionsPanel(inputView: self.textView, textContent: self.textView.scrollView.contentView, relativeView: content, window: context.window, context: context, presentation: theme, highlightRect: { [weak self] range, whole in
                    return self?.textView.highlight(for: range, whole: whole) ?? .zero
                })
                self.textInputSuggestionsView = current
                isNew = true
            }
            current.apply(files, range: range, animated: animated, isNew: isNew)
        } else if let view = self.textInputSuggestionsView {
            view.close(animated: animated)
            self.textInputSuggestionsView = nil
        }
    }

    
    deinit {
        inputSwapDisposable.dispose()
    }
    
    public override func shakeView() {
        if !textView.isHidden {
            textView.shake()
            textView.selectAll()
        }
    }
    
    public override func hasFirstResponder() -> Bool {
        return true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    public func canTransformInputText() -> Bool {
        guard let item = item as? InputTextDataRowItem else { return false }
        return item.canMakeTransformations
    }
    
    public func makeBold() {
        self.textView.inputApplyTransform(.attribute(TextInputAttributes.bold))
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
    
    public override var additionBorderInset: CGFloat {
        if let item = self.item as? InputTextDataRowItem {
            var inset: CGFloat = 0
            if let placeholderAction {
                inset += placeholderAction.frame.width + item.viewType.innerInset.left
            }
            return inset
        }
        return super.additionBorderInset
    }
    
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? InputTextDataRowItem else {return}
                     
        let innerInsets = item.viewType.innerInset
        
        transition.updateFrame(view: placeholderTextView, frame: CGRect(origin: NSMakePoint(innerInsets.left, innerInsets.top), size: placeholderTextView.frame.size))
        
        var textOffset: CGFloat = 0
        
        if let placeholderAction {
            let placeholderY = round((containerView.frame.height - placeholderAction.frame.height) / 2)
            transition.updateFrame(view: placeholderAction, frame: CGRect(origin: NSMakePoint(innerInsets.left, placeholderY), size: placeholderAction.frame.size))
            textOffset += placeholderAction.frame.width + innerInsets.left
        }

        
        let (textSize, textHeight) = textViewSize()
                
        transition.updateFrame(view: textView, frame: CGRect(origin: CGPoint(x: item.viewType.innerInset.left + textOffset, y: item.viewType.innerInset.top - 5), size: textSize))
        textView.updateLayout(size: textSize, textHeight: textHeight, transition: transition)
        
            
        var emojiOffset: CGFloat = 0
        
        if let rightItem = item.rightItem {
            switch rightItem {
            case .action:
                transition.updateFrame(view: rightActionView, frame: CGRect(origin: NSMakePoint(self.containerView.frame.width - rightActionView.frame.width - innerInsets.right, innerInsets.top - 5), size: rightActionView.frame.size))
                emojiOffset += rightActionView.frame.width + 5
            case .loading:
                if let loadingView = loadingView  {
                    transition.updateFrame(view: loadingView, frame: CGRect(origin: NSMakePoint(self.containerView.frame.width - loadingView.frame.width - innerInsets.right, innerInsets.top), size: loadingView.frame.size))
                    emojiOffset += rightActionView.frame.width + 5
                }
            case .actionWithLoading:
                transition.updateFrame(view: rightActionView, frame: CGRect(origin: NSMakePoint(self.containerView.frame.width - rightActionView.frame.width - innerInsets.right, innerInsets.top - 5), size: rightActionView.frame.size))
                if let loadingView = loadingView {
                    transition.updateFrame(view: loadingView, frame: CGRect(origin: NSMakePoint(rightActionView.frame.midX - loadingView.frame.width / 2, rightActionView.frame.midY - loadingView.frame.height / 2), size: loadingView.frame.size))
                }
                emojiOffset += rightActionView.frame.width + 5
            case .media:
                let activeMediaView: NSView? = mediaImageView ?? mediaStickerView
                if let mediaView = activeMediaView {
                    transition.updateFrame(view: mediaView, frame: CGRect(origin: NSMakePoint(self.containerView.frame.width - mediaView.frame.width - innerInsets.right, innerInsets.top - 5), size: mediaView.frame.size))
                    if let overlay = mediaOverlay {
                        transition.updateFrame(view: overlay, frame: mediaView.frame)
                    }
                    if let mediaLoadingView = mediaLoadingView {
                        transition.updateFrame(view: mediaLoadingView, frame: CGRect(origin: NSMakePoint(mediaView.frame.midX - mediaLoadingView.frame.width / 2, mediaView.frame.midY - mediaLoadingView.frame.height / 2), size: mediaLoadingView.frame.size))
                    }
                    emojiOffset += mediaView.frame.width + 5
                }
            }
        }

        transition.updateFrame(view: textLimitation, frame: CGRect(origin: NSMakePoint(item.blockWidth - innerInsets.right - textLimitation.frame.width, self.containerView.frame.height - innerInsets.bottom - textLimitation.frame.height), size: textLimitation.frame.size))


        if let emoji {
            transition.updateFrame(view: emoji, frame: CGRect(origin: NSMakePoint(containerView.frame.width - emoji.frame.width - innerInsets.right - emojiOffset, innerInsets.top - 3), size: emoji.frame.size))
        }
        
        self.textInputSuggestionsView?.updateRect(transition: transition)

    }

    
    public override var backdorColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.backgroundColor
        }
        return theme.colors.background
    }

    public override func updateColors() {
        super.updateColors()
        
        placeholderTextView.backgroundColor = backdorColor
        
        var inputTheme = textView.inputTheme
        inputTheme = inputTheme.withUpdatedFontSize(.text)
        
        textView.inputTheme = inputTheme

        containerView.backgroundColor = backdorColor
        loadingView?.progressColor = theme.colors.grayText
        guard let item = item as? InputTextDataRowItem else {
            return
        }
        self.background = item.viewType.rowBackground
    }
    
 
    public override var mouseInsideField: Bool {
        return textView._mouseInside()
    }
    
    
    public override var firstResponder: NSResponder? {
        return textView.inputView
    }
    
    public func showPlaceholderActionTooltip(_ text: String) -> Void {
        if let placeholderAction = placeholderAction {
            tooltip(for: placeholderAction, text: text)
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        
        guard let item = item as? InputTextDataRowItem else {return}
        
        super.set(item: item, animated: animated)

        placeholderTextView.isHidden = item.placeholderLayout == nil
        placeholderTextView.update(item.placeholderLayout)
        

        
        if let rightItem = item.rightItem {
            switch rightItem {
            case let .action(image, action):
                rightActionView.set(image: image, for: .Normal)
                rightActionView.setImageContentGravity(.resizeAspectFill)
                rightActionView.setFrameSize(NSMakeSize(24, 24))
                rightActionView.isHidden = false
                loadingView?.removeFromSuperview()
                loadingView = nil
                if let view = mediaImageView {
                    performSubviewRemoval(view, animated: animated)
                    mediaImageView = nil
                }
                if let view = mediaStickerView {
                    performSubviewRemoval(view, animated: animated)
                    mediaStickerView = nil
                }
                if let view = mediaOverlay {
                    performSubviewRemoval(view, animated: animated)
                    mediaOverlay = nil
                }
                mediaLoadingView?.removeFromSuperview()
                mediaLoadingView = nil
                rightActionView.removeAllHandlers()
                rightActionView.setAccessibilityLabel(nil)
                switch action {
                case .none:
                    rightActionView.userInteractionEnabled = false
                    rightActionView.autohighlight = false
                case .resort:
                    rightActionView.userInteractionEnabled = false
                    rightActionView.autohighlight = false
                case .clearText:
                    rightActionView.userInteractionEnabled = true
                    rightActionView.autohighlight = false
                    rightActionView.setAccessibilityLabel(strings().voiceOverEditingClearText)
                    rightActionView.set(handler: { [weak self] _ in
                        self?.textView.set(.init())
                    }, for: .Click)
                case let .custom(action):
                    rightActionView.userInteractionEnabled = true
                    rightActionView.autohighlight = false
                    rightActionView.setAccessibilityLabel(strings().voiceOverCommonOptions)
                    rightActionView.set(handler: { control in
                        action(item, control)
                    }, for: .Click)
                }
            case .loading:
                if loadingView == nil {
                    let innerInsets = item.viewType.innerInset
                    let origin = NSMakePoint(self.containerView.frame.width - 18 - innerInsets.right, innerInsets.top)
                    loadingView = ProgressIndicator(frame: NSMakeRect(origin.x, origin.y, 18, 18))
                    loadingView?.progressColor = theme.colors.grayText
                    containerView.addSubview(loadingView!)
                }
                rightActionView.isHidden = true
                if let view = mediaImageView {
                    performSubviewRemoval(view, animated: animated)
                    mediaImageView = nil
                }
                if let view = mediaStickerView {
                    performSubviewRemoval(view, animated: animated)
                    mediaStickerView = nil
                }
                if let view = mediaOverlay {
                    performSubviewRemoval(view, animated: animated)
                    mediaOverlay = nil
                }
                mediaLoadingView?.removeFromSuperview()
                mediaLoadingView = nil
            case let .actionWithLoading(image, _):
                rightActionView.set(image: image, for: .Normal)
                rightActionView.setImageContentGravity(.resizeAspectFill)
                rightActionView.setFrameSize(NSMakeSize(24, 24))
                rightActionView.isHidden = false
                rightActionView.removeAllHandlers()
                rightActionView.userInteractionEnabled = false
                rightActionView.autohighlight = false
                if loadingView == nil {
                    let origin = NSMakePoint(rightActionView.frame.midX - 9, rightActionView.frame.midY - 9)
                    loadingView = ProgressIndicator(frame: NSMakeRect(origin.x, origin.y, 18, 18))
                    loadingView?.progressColor = .black
                    containerView.addSubview(loadingView!)
                }
                if let view = mediaImageView {
                    performSubviewRemoval(view, animated: animated)
                    mediaImageView = nil
                }
                if let view = mediaStickerView {
                    performSubviewRemoval(view, animated: animated)
                    mediaStickerView = nil
                }
                if let view = mediaOverlay {
                    performSubviewRemoval(view, animated: animated)
                    mediaOverlay = nil
                }
                mediaLoadingView?.removeFromSuperview()
                mediaLoadingView = nil
            case let .media(media, context, isLoading, progress, action):
                rightActionView.isHidden = true
                loadingView?.removeFromSuperview()
                loadingView = nil
                let thumbSize = NSMakeSize(24, 24)
                let innerInsets = item.viewType.innerInset
                let origin = NSMakePoint(self.containerView.frame.width - thumbSize.width - innerInsets.right, innerInsets.top - 5)
                if let file = media as? TelegramMediaFile, file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                    self.mediaImageView?.removeFromSuperview()
                    self.mediaImageView = nil
                    self.mediaStickerView?.removeFromSuperview()
                    let stickerView = InlineStickerView(account: context.account, file: file, size: thumbSize)
                    stickerView.frame = NSMakeRect(origin.x, origin.y, thumbSize.width, thumbSize.height)
                    self.mediaStickerView = stickerView
                    containerView.addSubview(stickerView)
                } else {
                    self.mediaStickerView?.removeFromSuperview()
                    self.mediaStickerView = nil
                    let imageView: TransformImageView
                    if let existing = self.mediaImageView {
                        imageView = existing
                    } else {
                        imageView = TransformImageView(frame: NSMakeRect(origin.x, origin.y, thumbSize.width, thumbSize.height))
                        self.mediaImageView = imageView
                        containerView.addSubview(imageView)
                    }
                    if let file = media as? TelegramMediaFile {
                        let reference = FileMediaReference.standalone(media: file)
                        let imageSize = file.dimensions?.size ?? thumbSize
                        let arguments = TransformImageArguments(corners: ImageCorners(radius: 6), imageSize: imageSize, boundingSize: thumbSize, intrinsicInsets: NSEdgeInsets())
                        if file.isVideo {
                            imageView.setSignal(chatMessageVideo(account: context.account, fileReference: reference, scale: backingScaleFactor))
                        } else {
                            imageView.setSignal(chatMessageImageFile(account: context.account, fileReference: reference, scale: backingScaleFactor))
                        }
                        imageView.set(arguments: arguments)
                    } else if let image = media as? TelegramMediaImage {
                        let reference = ImageMediaReference.standalone(media: image)
                        let imageSize = largestImageRepresentation(image.representations)?.dimensions.size ?? thumbSize
                        let arguments = TransformImageArguments(corners: ImageCorners(radius: 6), imageSize: imageSize, boundingSize: thumbSize, intrinsicInsets: NSEdgeInsets())
                        imageView.setSignal(chatMessagePhoto(account: context.account, imageReference: reference, scale: backingScaleFactor, synchronousLoad: false, autoFetchFullSize: true))
                        imageView.set(arguments: arguments)
                    }
                }
                let mediaFrame = NSMakeRect(origin.x, origin.y, thumbSize.width, thumbSize.height)
                let overlay: Control
                if let existing = self.mediaOverlay {
                    overlay = existing
                } else {
                    overlay = Control(frame: mediaFrame)
                    self.mediaOverlay = overlay
                    containerView.addSubview(overlay)
                }
                overlay.frame = mediaFrame
                overlay.removeAllHandlers()
                if let file = media as? TelegramMediaFile {
                    overlay.setAccessibilityLabel(file.isSticker || file.isAnimatedSticker || file.isVideoSticker ? strings().voiceOverCommonSticker : file.isVideo ? strings().voiceOverCommonVideo : strings().voiceOverCommonFile)
                } else {
                    overlay.setAccessibilityLabel(strings().voiceOverCommonPhoto)
                }
                switch action {
                case let .custom(action):
                    overlay.set(handler: { [weak self] control in
                        if let item = self?.item as? InputTextDataRowItem {
                            action(item, control)
                        }
                    }, for: .Click)
                default:
                    break
                }
                if isLoading {
                    if mediaLoadingView == nil {
                        mediaLoadingView = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .blackTransparent, foregroundColor: .white, icon: nil, iconInset: NSEdgeInsets(), lineWidth: 1), twist: true, size: NSMakeSize(18, 18))
                        mediaLoadingView!.frame = NSMakeRect(mediaFrame.midX - 10, mediaFrame.midY - 10, 18, 18)
                        containerView.addSubview(mediaLoadingView!)
                    }
                    mediaLoadingView!.state = .ImpossibleFetching(progress: progress, force: false)
                } else {
                    mediaLoadingView?.removeFromSuperview()
                    mediaLoadingView = nil
                }
            }
        } else {
            rightActionView.isHidden = true
            loadingView?.removeFromSuperview()
            loadingView = nil
            if let view = mediaImageView {
                performSubviewRemoval(view, animated: animated)
                mediaImageView = nil
            }
            if let view = mediaStickerView {
                performSubviewRemoval(view, animated: animated)
                mediaStickerView = nil
            }
            if let view = mediaOverlay {
                performSubviewRemoval(view, animated: animated)
                mediaOverlay = nil
            }
            mediaLoadingView?.removeFromSuperview()
            mediaLoadingView = nil
        }

        if let placeholder = item.placeholder {
            if let icon = placeholder.icon {
                if placeholderAction == nil {
                    self.placeholderAction = ImageButton()
                    containerView.addSubview(self.placeholderAction!)
                    if animated {
                        placeholderAction!.layer?.animateAlpha(from: 0, to: 2, duration: 0.2)
                    }
                }
                guard let placeholderAction = self.placeholderAction else {
                    return
                }
                placeholderAction.setAccessibilityLabel(strings().voiceOverCommonSelect)
                placeholderAction.isAccessibilityDecorative = placeholder.action == nil
                placeholderAction.set(image: icon, for: .Normal)
                placeholderAction.set(image: icon, for: .Highlight)
                placeholderAction.set(image: icon, for: .Hover)
                _ = placeholderAction.sizeToFit()
                placeholderAction.removeAllHandlers()
                if let action = placeholder.action {
                    placeholderAction.userInteractionEnabled = true
                    placeholderAction.set(handler: { _ in
                        action()
                    }, for: .SingleClick)
                } else {
                    placeholderAction.userInteractionEnabled = false
                }
            } else {
                if let placeholderAction {
                    performSubviewRemoval(placeholderAction, animated: animated)
                    self.placeholderAction = nil
                }
            }
            
            
        } else {
            if let placeholderAction {
                performSubviewRemoval(placeholderAction, animated: animated)
                self.placeholderAction = nil
            }
        }
        
        if item.hasTextLimitation {
            textLimitation.isHidden = item.state.inputText.string.length < item.limit / 3 * 2 || item.state.inputText.string.length == item.limit || !item.enabled
            let color: NSColor = item.state.inputText.string.length > item.limit ? theme.colors.redUI : theme.colors.grayText
            textLimitation.attributedString = .initialize(string: "\(item.limit - Int32(item.state.inputText.string.length))", color: color, font: .normal(.small))
            textLimitation.sizeToFit()
        } else {
            textLimitation.isHidden = true
        }
        
        
        if item.hasEmoji {
            let current: ImageButton
            if let view = self.emoji {
                current = view
            } else {
                current = ImageButton()
                current.autohighlight = false
                current.scaleOnClick = true
                current.setAccessibilityLabel(strings().voiceOverCommonEmoji)
                addSubview(current)
                self.emoji = current
                
                current.set(handler: { [weak self] control in
                    if let item = self?.item as? InputTextDataRowItem {
                        let emojis = ChatHistoryModelHooks.shared.makeEmojiPicker(item.context, { [weak self] sticker, _, _, _, _ in
                            if let item = self?.item as? InputTextDataRowItem, let textView = self?.textView {
                                self?.textView.makeFirstResponder()
                                let text = sticker.file._parse().customEmojiText ?? sticker.file._parse().stickerText ?? clown
                                let state = textView.interactions.insertText(.makeAnimated(sticker.file._parse(), text: text))
                                item.updateState(state)
                                self?.set(state)
                            }
                        }, { [weak self] string, _ in
                            self?.textView.makeFirstResponder()
                            if let item = self?.item as? InputTextDataRowItem, let textView = self?.textView {
                                let state = textView.interactions.insertText(.initialize(string: string))
                                item.updateState(state)
                                self?.set(state)
                            }
                        })
                        
                        showPopover(for: control, with: emojis)
                    }
                }, for: .Click)
            }
            current.set(image: TelegramThemeHooks.shared.image(.iconCustomEmojiSmall).precomposed(theme.colors.grayIcon), for: .Normal)
            current.sizeToFit()
        } else if let view = self.emoji {
            performSubviewRemoval(view, animated: animated)
            self.emoji = nil
        }

        textView.placeholderFontSize = 13
        textView.placeholderMaxLines = item.fitPlaceholderHeight ? .max : 1
        textView.placeholder = item.inputPlaceholder.string
        textView.inputView.setAccessibilityLabel(item.accessibilityLabel)
        
        textView.context = item.context
        textView.interactions.max_height = 500
        textView.interactions.min_height = 20
        textView.interactions.allowedLinkHosts = item.allowedLinkHosts
        textView.interactions.canTransform = item.canMakeTransformations
        textView.interactions.simpleTransform = item.simpleTransform
        textView.interactions.inputIsEnabled = item.enabled
        
        
        self.textView.change(opacity: item.enabled ? 1 : 0.5, animated: animated)
        if case .media = item.rightItem {
            self.rightActionView.isHidden = true
        } else {
            self.rightActionView.isHidden = item.rightItem == nil || !item.enabled
        }
        self.placeholderAction?.isHidden = !item.enabled
        self.emoji?.isHidden = !item.enabled

        let prevPolicy = textView.interactions.emojiPlayPolicy
            
        textView.interactions.emojiPlayPolicy = item.playAnimation ? .loop : .framesCount(1)

        if prevPolicy != textView.interactions.emojiPlayPolicy {
            textView.updatePlayPolicy(textView.interactions.emojiPlayPolicy)
        }
        
        
        textView.interactions.filterEvent = { event in
            if let chars = event.characters {
                return chars.isEmpty || !item.filter(chars).isEmpty
            } else {
                return false
            }
        }
        
        textView.interactions.inputDidUpdate = { _ in }
        
        self.textView.set(item.state.textInputState())

        
        textView.interactions.inputDidUpdate = { [weak self] state in
            guard let `self` = self else {
                return
            }
            self.set(state)
            self.inputDidUpdateLayout(animated: true)
        }
    }
    
    public var textWidth: CGFloat {
        guard let item = item as? InputTextDataRowItem else {
            return frame.width
        }
        return item.textWidth
    }
    
    public func textViewSize() -> (NSSize, CGFloat) {
        let w = textWidth
        var height = textView.height(for: w)
        if let item = item as? InputTextDataRowItem, item.fitPlaceholderHeight, item.state.inputText.string.isEmpty {
            let placeholderAttr = NSMutableAttributedString()
            placeholderAttr.append(string: item.inputPlaceholder.string)
            placeholderAttr.addAttribute(.font, value: NSFont.normal(.text), range: placeholderAttr.range)
            let placeholderHeight = InputTextView.rawTextHeight(for: placeholderAttr, width: w)
            height = max(height, placeholderHeight)
        }
        return (NSMakeSize(w, min(max(height, textView.min_height), textView.max_height)), height)
    }
    
    private func inputDidUpdateLayout(animated: Bool) {
        updateLayout(size: self.frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }
    
    private func set(_ state: Updated_ChatTextInputState) {
        guard let item = item as? InputTextDataRowItem else {
            return
        }
        
        let context = item.context
        
        item.updateState(state)
        
        
        let input = state.textInputState()
        
        let textInputContextState = ChatHistoryModelHooks.shared.textInputStateContextQueryRange(input, false)
        var cleanup = true
        if let textInputContextState = textInputContextState, item.hasEmoji {
            if textInputContextState.1.contains(.swapEmoji) {
                let stringRange = textInputContextState.0
                let range = NSRange(string: input.inputText, range: stringRange)
                if !input.isAnimatedEmoji(at: range) {
                    let query = String(input.inputText[stringRange])
                    let signal = InputSwapSuggestionsPanelItems(query, peerId: context.peerId, context: context, ignorePremium: item.hasEmoji)
                    |> deliverOnMainQueue
                    self.inputSwapDisposable.set(signal.start(next: { [weak self] files in
                        self?.updateTextInputSuggestions(files, range: range, animated: true)
                    }))
                    cleanup = false
                }
            }
        }
        
        if cleanup {
            self.updateTextInputSuggestions([], range: NSMakeRange(0, 0), animated: true)
            self.inputSwapDisposable.set(nil)
        }
        
    }
    
}
