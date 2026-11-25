import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import ColorPalette
import ThemeSettings
import Postbox
import InAppSettings
import CoreGraphics
import TelegramMedia
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import TelegramMediaUtils
import ChatHistoryModel
import PremiumUI
import AppAnalytics

private final class WallpaperActionButton : Control {
    private let glass: LiquidGlassView = LiquidGlassView(frame: .zero, cornerRadius: 999, hasShadow: true, hasBorder: true, forceAppearance: .forceDark)
    private let textView = TextView()
    private let imageView = LottiePlayerView(frame: NSMakeRect(0, 0, 20, 20))
    private let container = View()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(glass)
        container.addSubview(textView)
        container.addSubview(imageView)
        addSubview(container)
        scaleOnClick = true

        textView.userInteractionEnabled = false
        textView.isSelectable = false

        layer?.masksToBounds = false
        self.stretchReferenceView = glass
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        glass.updateLayout(size: bounds.size, transition: .immediate)
        container.center()
        if imageView.isHidden {
            textView.center()
        } else {
            imageView.centerY(x: 0)
            textView.centerY(x: imageView.frame.maxX)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    public func update(text: String, lottie: LocalAnimatedSticker?) {
        let layout = TextViewLayout(.initialize(string: text, color: theme.colors.underSelectedColor, font: .medium(.text)))
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
        
        if let lottie = lottie, let data = lottie.data {
            let colors:[LottieColor] = [.init(keyPath: "", color: NSColor(0xffffff))]
            imageView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("bundle_\(lottie.rawValue)"), size: NSMakeSize(20, 20), colors: colors), cachePurpose: .temporaryLZ4(.thumb), playPolicy: .onceEnd, maximumFps: 60, colors: colors, runOnQueue: .mainQueue()))
        }
        imageView.isHidden = lottie == nil
              
        if imageView.isHidden {
            container.setFrameSize(NSMakeSize(layout.layoutSize.width, max(layout.layoutSize.height, imageView.frame.height)))
        } else {
            container.setFrameSize(NSMakeSize(layout.layoutSize.width + imageView.frame.width, max(layout.layoutSize.height, imageView.frame.height)))
        }
        glass.customTint = theme.colors.accent
        needsLayout = true
        
    }
}









private enum WallpaperPreviewViewState  {
    case color
    case pattern
    case normal
}


public enum WallpaperColorSelectMode : Equatable {
    case single(NSColor)
    case gradient([NSColor], Int, Int32?)
    
    public var colors: [NSColor] {
        switch self {
        case let .single(color):
            return [color]
        case let .gradient(colors, _, _):
            return colors
        }
    }
    public var rotation: Int32? {
        switch self {
        case .single:
            return nil
        case let .gradient(_, _, rotation):
            return rotation
        }
    }
    
    public func withRemovedColor(_ index: Int) -> WallpaperColorSelectMode {
        switch self {
        case .single:
            return self
        case let .gradient(colors, selected, rotation):
            var colors = colors
            if colors.count == 1 {
                return .gradient(colors, 0, rotation)
            }
            colors.remove(at: index)
            return .gradient(colors, min(selected, colors.count - 1), rotation)
        }
    }
    public func withAddedColor(_ color: NSColor, at index: Int) -> WallpaperColorSelectMode {
        switch self {
        case let .single(current):
            return .gradient([current, color], 1, nil)
        case let .gradient(colors, _, rotation):
            var colors = colors
            colors.insert(color, at: index)
            return .gradient(colors, index + 1, rotation)
        }
    }
    public func withUpdatedRotatation(_ rotation: Int32?) -> WallpaperColorSelectMode {
        switch self {
        case .single:
            return self
        case let .gradient(colors, index, _):
            return .gradient(colors, index, rotation)
        }
    }
    
    public func withUpdatedColor(_ color: NSColor) -> WallpaperColorSelectMode {
        switch self {
        case .single:
            return .single(color)
        case let .gradient(colors, index, rotation):
            var colors = colors
            colors[index] = color
            return .gradient(colors, index, rotation)
        }
    }
    public func withUpdatedIndex(_ index: Int) -> WallpaperColorSelectMode {
        switch self {
        case let .single(current):
            return .single(current)
        case let .gradient(colors, _, rotation):
            return .gradient(colors, index, rotation)
        }
    }

}


private final class WallpaperPreviewView: View {
    private let updateStateDisposable = MetaDisposable()
    private let backgroundView: BackgroundView = BackgroundView(frame: NSZeroRect)
    private var image: CGImage?
    private let disposable = MetaDisposable()
    private let loadImageDisposable = MetaDisposable()

    private var progressView: RadialProgressView?
    private let tableView: TableView
    private let documentView: NSView
    
    public let blurCheckbox = WallpaperCheckboxView(frame: NSMakeRect(0, 0, 70, 28), title: strings().wallpaperPreviewBlurred)
    public let patternCheckbox = WallpaperCheckboxView(frame: NSMakeRect(0, 0, 70, 28), title: strings().chatWPPattern)
    public let colorCheckbox = WallpaperCheckboxView(frame: NSMakeRect(0, 0, 70, 28), title: strings().chatWPColor)
    
    private let rotateColors: WallpaperPlayRotateView = WallpaperPlayRotateView(frame: NSMakeRect(0, 0, 40, 40))
    
    public let checkboxContainer: View = View()
    
    public let patternsController: WallpaperPatternPreviewController
    public let colorPicker = WallpaperColorPickerContainerView(frame: NSZeroRect)
    private let controlsBg = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: true, hasBorder: true, forceAppearance: .forceDark)
    
    private var previewState: WallpaperPreviewViewState = .normal
    private var imageSize: NSSize = NSZeroSize
    private let context: any AccountContextProtocol
    
    fileprivate let apply: WallpaperActionButton = WallpaperActionButton(frame: .zero)
    fileprivate var forBothCheckbox: WallpaperCheckboxView?

    fileprivate let dismissButton: ImageButton = ImageButton()
    fileprivate let shareButton: ImageButton = ImageButton()

    fileprivate var forBoth: Bool {
        return forBothCheckbox?.isSelected ?? false
    }

    fileprivate var onWallpaperChange: ((Wallpaper) -> Void)? = nil
    fileprivate var onForBothChange: ((Bool) -> Void)? = nil

    fileprivate var ready:(()->Void)? = nil

    private(set) var wallpaper: Wallpaper
    
    
    
    public required init(frame frameRect: NSRect, source: WallpaperSource, context: any AccountContextProtocol, wallpaper: Wallpaper) {
        self.context = context
        self.wallpaper = wallpaper
        self.tableView = TableView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height), isFlipped: false, drawBorder: false)
        self.documentView = tableView.documentView!
        self.patternsController = WallpaperPatternPreviewController(context: context)
        super.init(frame: frameRect)
        backgroundView.useSharedAnimationPhase = false
        addSubview(backgroundView)
        addSubview(tableView)
        checkboxContainer.addSubview(blurCheckbox)
        checkboxContainer.addSubview(patternCheckbox)
        checkboxContainer.addSubview(colorCheckbox)
        checkboxContainer.addSubview(rotateColors)
        
        checkboxContainer.layer?.masksToBounds = false
        
        addSubview(checkboxContainer)
        
        addSubview(controlsBg)
        addSubview(colorPicker)
        addSubview(patternsController.view)
        
        
        
        tableView.layer?.masksToBounds = false
        tableView.documentView?.layer?.masksToBounds = false
        tableView.clipView.layer?.masksToBounds = false

        addSubview(apply)

        apply.update(text: strings().wallpaperPreviewApply, lottie: nil)

        dismissButton.set(image: theme.icons.glass_close, for: .Normal)
        dismissButton.setGlassEffect()
        dismissButton.setAccessibilityLabel(strings().voiceOverCommonClose)
        dismissButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        addSubview(dismissButton)

        shareButton.set(image: TelegramThemeHooks.shared.image(.iconShareStickerPack).precomposed(theme.colors.text), for: .Normal)
        shareButton.setGlassEffect()
        shareButton.setAccessibilityLabel(strings().voiceOverCommonShare)
        shareButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        addSubview(shareButton)
        
        
        colorPicker.useTransparentBackground = true
        colorPicker.canUseGradient = true
        
        colorPicker.modeDidUpdate = { [weak self] mode in
            guard let strongSelf = self, !strongSelf.isApplyingState else {
                return
            }
            let wallpaper = strongSelf.wallpaper
            let updated: Wallpaper
            switch mode {
            case let .single(color):
                switch wallpaper {
                case let .file(_, _, settings, _, _):
                    updated = wallpaper.withUpdatedSettings(settings.withUpdatedColor(color.argb))
                default:
                    updated = .color(color.argb)
                }
            case let .gradient(colors, _, rotation):
                switch wallpaper {
                case let .file(_, _, settings, _, _):
                    let s = WallpaperSettings(blur: settings.blur, motion: settings.motion, colors: colors.map { $0.argb }, intensity: settings.intensity, rotation: rotation)
                    updated = wallpaper.withUpdatedSettings(s)
                default:
                    updated = .gradient(nil, colors.map { $0.argb }, rotation)
                }
            }
            strongSelf.onWallpaperChange?(updated)
        }
                
        tableView.backgroundColor = .clear
        tableView.layer?.backgroundColor = .clear
        tableView.getBackgroundColor = {
            .clear
        }
        
        addTableItems(context, source: source)
        

        
        blurCheckbox.onChangedValue = { [weak self] isSelected in
            guard let `self` = self, !self.isApplyingState else { return }
            self.onWallpaperChange?(self.wallpaper.withUpdatedBlurrred(isSelected))
        }
        
        colorCheckbox.onChangedValue = { [weak self] isSelected in
            guard let `self` = self else { return }
            switch self.previewState {
            case .color:
                self.updateModifyState(.normal, animated: true)
            default:
                self.updateModifyState(.color, animated: true)
            }
        }
        
        patternCheckbox.onChangedValue = { [weak self] isSelected in
            guard let `self` = self else { return }
            switch self.previewState {
            case .pattern:
                self.updateModifyState(.normal, animated: true)
            default:
                self.updateModifyState(.pattern, animated: true)
            }
        }
        
        rotateColors.onClick = { [weak self] in
            guard let `self` = self else { return }
            
            let mode = self.colorPicker.mode
            let rotation: Int32?

            if mode.colors.count > 2 {
                rotation = nil
                self.backgroundView.doAction()
            } else {
                switch mode {
                case let .gradient(_, _, r):
                    if let r = r {
                        if r + 45 == 360 {
                            rotation = nil
                        } else {
                            rotation = r + 45
                        }
                    } else {
                        rotation = 45
                    }
                default:
                    rotation = nil
                }
            }
            
            self.colorPicker.modeDidUpdate?(mode.withUpdatedRotatation(rotation))
            
        }
        
        switch wallpaper {
        case let .color(color):
            self.updateMode(.single(NSColor(argb: color)), animated: false)
        case let .file(_, _, settings, _, _):
            let colors:[NSColor] = settings.colors.map { .init(argb: $0) }
            if !colors.isEmpty {
                if colors.count == 1 {
                    self.updateMode(.single(colors[0]), animated: false)
                } else {
                    self.updateMode(.gradient(colors, colors.count - 1, settings.rotation), animated: false)
                }
            }
        case let .gradient(_, colors, rotation):
            let colors = colors.map { NSColor(argb: $0) }
            self.updateMode(.gradient(colors, 0, rotation), animated: false)
        default:
            break
        }


        colorPicker.colorChanged = { [weak self] mode in
            guard let `self` = self else {return}
            switch mode {
            case let .single(color):
                self.patternsController.colors = ([color], nil)
            case let .gradient(colors, _, rotation):
                self.patternsController.colors = (colors, rotation)
            }
            self.updateMode(mode, animated: true)
        }
        
        patternsController.selected = { [weak self] wallpaper in
            guard let `self` = self, !self.isApplyingState else { return }
            let updated: Wallpaper?
            if let wallpaper = wallpaper {
                switch self.wallpaper {
                case let .color(color):
                    updated = wallpaper.withUpdatedSettings(WallpaperSettings(colors: [color], intensity: self.patternsController.intensity))
                case let .gradient(_, colors, r):
                    updated = wallpaper.withUpdatedSettings(WallpaperSettings(colors: colors.map {
                        NSColor(argb: $0).withAlphaComponent(1.0).argb
                    }, intensity: self.patternsController.intensity, rotation: r))
                case let .file(_, _, settings, _, _):
                    updated = wallpaper.withUpdatedSettings(WallpaperSettings(colors: settings.colors, intensity: self.patternsController.intensity, rotation: settings.rotation))
                default:
                    updated = nil
                }
            } else {
                switch self.wallpaper {
                case .color:
                    updated = nil
                case let .file(_, _, settings, _, _):
                    if settings.colors.count == 1 {
                        updated = .color(settings.colors.first!)
                    } else if settings.colors.count > 1 {
                        updated = .gradient(nil, settings.colors, nil)
                    } else {
                        updated = nil
                    }
                default:
                    updated = nil
                }
            }
            if let updated {
                self.onWallpaperChange?(updated)
            }
        }
        
    
        tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            guard let `self` = self else {
                return
            }
            self.tableView.enumerateVisibleViews(with: { view in
                WallpaperHooks.shared.updateChatPreviewBackground(view, false, false)
            })
        }))
        
        switch source {
        case let .chat(peer, _):
            if peer.isUser {
                let title = strings().channelWallpaperApplyBoth(peer.compactDisplayTitle)
                let checkbox = WallpaperCheckboxView(frame: NSMakeRect(0, 0, 200, 28), title: title)
                checkbox.onChangedValue = { [weak self] value in
                    self?.onForBothChange?(value)
                }
                checkboxContainer.addSubview(checkbox)
                self.forBothCheckbox = checkbox
            }
        default:
            break
        }
        
    }
    
    private func addTableItems(_ context: any AccountContextProtocol, source: WallpaperSource) {
        
        
        
        let chatInteraction = WallpaperHooks.shared.makeChatPreviewContext(context, { [weak self] in
            guard let `self` = self else {
                return .zero
            }
            return CGRect(origin: NSMakePoint(0, self.documentView.frame.height), size: self.documentView.frame.size)
        })
        
        
        let fromUser1 = TelegramUser(id: PeerId(1), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName1, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        let fromUser2 = TelegramUser(id: PeerId(2), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName2, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        

        let firstText: String
        let secondText: String
        switch wallpaper {
        case let .file(_, _, _, isPattern, _):
            if isPattern {
                firstText = strings().chatWPColorFirstMessage
                secondText = strings().chatWPColorSecondMessage
            } else {
                firstText = strings().chatWPFirstMessage
                secondText = strings().chatWPSecondMessage
            }
        case .image:
            firstText = strings().chatWPFirstMessage
            secondText = strings().chatWPSecondMessage
        default:
            firstText = strings().chatWPColorFirstMessage
            secondText = strings().chatWPColorSecondMessage
        }
        



        let firstMessage = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 0), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 20 + 60*60*18, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser2, text: firstText, attributes: [], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let firstEntry: ChatHistoryEntry = .MessageEntry(firstMessage, MessageIndex(firstMessage), true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))

        let secondMessage = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 22 + 60*60*18, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: secondText, attributes: [], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let secondEntry: ChatHistoryEntry = .MessageEntry(secondMessage, MessageIndex(secondMessage), true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        
        
        
        
        let item1 = WallpaperHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, firstEntry, theme)
        let item2 = WallpaperHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, secondEntry, theme)
        
        
        item1.makeSize(frame.size.width)
        item2.makeSize(frame.size.width)

        _ = tableView.addItem(item: item2)
        _ = tableView.addItem(item: item1)
        
        switch source {
        case let .chat(peer, _):
            let zeroMessage = Message(stableId: 111, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 0), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 20 + 60*60*18, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser2, text: firstText, attributes: [], media: [TelegramMediaAction(action: .customText(text: strings().wallpaperBackgroundNoApplyToPeer(peer.compactDisplayTitle), entities: [], additionalAttributes: nil))], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])

            let zeroEntry: ChatHistoryEntry = .MessageEntry(zeroMessage, MessageIndex(zeroMessage), true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
            let item0 = WallpaperHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, zeroEntry, theme)
            item0.makeSize(frame.size.width)

            _ = tableView.addItem(item: item0)
        default:
            break
        }
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public var croppedRect: NSRect {
        let fittedSize = WallpaperDimensions.aspectFitted(imageSize)
        return imageSize.bounds.focus(fittedSize)
    }
    
    deinit {
        updateStateDisposable.dispose()
        disposable.dispose()
        loadImageDisposable.dispose()
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    public override var needsLayout: Bool {
        didSet {
            var bp = 0
            bp += 1
        }
    }
    
    
    private func updateMode(_ mode: WallpaperColorSelectMode, animated: Bool) {
        self.colorPicker.updateMode(mode, animated: animated)
        patternsController.colors = (mode.colors, mode.rotation)
        self.rotateColors.set(rotation: mode.rotation, animated: animated)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        
        var checkboxViews:[NSView] = []

        if !patternCheckbox.isHidden {
            checkboxViews.append(patternCheckbox)
        }
        if !rotateColors.isHidden {
            checkboxViews.append(rotateColors)
        }
        if !colorCheckbox.isHidden {
            checkboxViews.append(colorCheckbox)
        }
        if !blurCheckbox.isHidden {
            checkboxViews.append(blurCheckbox)
        }
        if let forBothCheckbox, !forBothCheckbox.isHidden {
            checkboxViews.append(forBothCheckbox)
        }
        
        let checkboxWidth: CGFloat = checkboxViews.reduce(0, { current, value in
            return current + value.frame.width
        }) + CGFloat(max(0, checkboxViews.count - 1)) * 10

        
        let buttonInset: CGFloat = 0
        
        
        let colorPickerSize = NSMakeSize(frame.width, 168 + buttonInset)
        let patternsSize = NSMakeSize(frame.width, 168 + buttonInset)
        let controlsSize = NSMakeSize(frame.width, 168 + buttonInset)

        let checkboxSize = NSMakeSize(checkboxWidth, 50)
        let documentSize = NSMakeSize(size.width, documentView.frame.height)
        
      

                
        if let progressView = progressView {
            transition.updateFrame(view: progressView, frame: progressView.centerFrame())
        }
        
        self.tableView.enumerateVisibleViews(with: { view in
            WallpaperHooks.shared.updateChatPreviewBackground(view, transition.isAnimated, false)
        })
        
       
        
        let backgroundSize: NSSize = size

        transition.updateFrame(view: backgroundView, frame: backgroundSize.bounds)

        let headerInset: CGFloat = 10
        transition.updateFrame(view: dismissButton, frame: NSMakeRect(headerInset, headerInset, dismissButton.frame.width, dismissButton.frame.height))
        transition.updateFrame(view: shareButton, frame: NSMakeRect(size.width - headerInset - shareButton.frame.width, headerInset, shareButton.frame.width, shareButton.frame.height))
        
        

        let pickerEdgeInset: CGFloat = 12
        let applyTopMargin: CGFloat = 12
        let applyHeight: CGFloat = 40
        let applyBottomMargin: CGFloat = 12
        let pickerBottomY = size.height - applyBottomMargin - applyHeight - applyTopMargin
        let pickerWidth = size.width - pickerEdgeInset * 2

        switch previewState {
        case .color, .pattern:
            let checkboxRect = CGRect(origin: NSMakePoint(focus(checkboxSize).minX, pickerBottomY - colorPicker.frame.height - checkboxSize.height - 10), size: checkboxSize)

            transition.updateFrame(view: checkboxContainer, frame: checkboxRect)
        case .normal:
            let checkboxRect = CGRect(origin: NSMakePoint(focus(checkboxSize).minX, pickerBottomY - checkboxSize.height - 10), size: checkboxSize)

            transition.updateFrame(view: checkboxContainer, frame: checkboxRect)

            transition.updateFrame(view: colorPicker, frame: CGRect(origin: NSMakePoint(0, size.height), size: colorPickerSize))

            transition.updateFrame(view: patternsController.view, frame: .init(origin: NSMakePoint(0, size.height), size: patternsSize))

            transition.updateFrame(view: controlsBg, frame: .init(origin: NSMakePoint(0, size.height), size: controlsSize))

        }

        switch previewState {
        case .color:
            let pickerHeight = colorPickerSize.height
            let pickerRect = CGRect(origin: NSMakePoint(pickerEdgeInset, pickerBottomY - pickerHeight), size: NSMakeSize(pickerWidth, pickerHeight))
            transition.updateFrame(view: colorPicker, frame: pickerRect)

            transition.updateFrame(view: patternsController.view, frame: .init(origin: NSMakePoint(0, size.height), size: patternsSize))

            transition.updateFrame(view: controlsBg, frame: pickerRect)

        case .pattern:
            transition.updateFrame(view: colorPicker, frame: CGRect.init(origin: .init(x: 0, y: size.height), size: colorPickerSize))

            let patternsHeight = patternsSize.height
            let patternsRect = CGRect(origin: NSMakePoint(pickerEdgeInset, pickerBottomY - patternsHeight), size: NSMakeSize(pickerWidth, patternsHeight))

            transition.updateFrame(view: patternsController.view, frame: patternsRect)
            transition.updateFrame(view: controlsBg, frame: patternsRect)

        default:
            break
        }
        do {
            let buttonY: CGFloat = size.height - applyHeight - applyBottomMargin
            transition.updateFrame(view: apply, frame: NSMakeRect(pickerEdgeInset, buttonY, size.width - pickerEdgeInset * 2, applyHeight))
        }
        
        patternsController.genericView.updateLayout(size: NSMakeSize(pickerWidth, patternsSize.height), transition: transition)
        colorPicker.updateLayout(size: NSMakeSize(pickerWidth, colorPickerSize.height), transition: transition)
        
      
        var x: CGFloat = 0
        for view in checkboxViews {
            transition.updateFrame(view: view, frame: view.centerFrameY(x: x))
            x += view.frame.width + 10
        }

        
        tableView.setFrameSize(documentSize)
        tableView.reloadData(width: size.width)
        
        switch previewState {
        case .color, .pattern:
            let tableBottomY = apply.frame.minY - colorPicker.frame.height - checkboxSize.height - 20
            transition.updateFrame(view: tableView, frame: .init(origin: .init(x: 0, y: tableBottomY - tableView.listHeight), size: NSMakeSize(documentSize.width, tableView.listHeight)))
        case .normal:
            let tableBottomY = apply.frame.minY - checkboxSize.height - 20
            transition.updateFrame(view: tableView, frame: .init(origin: .init(x: 0, y: tableBottomY - tableView.listHeight), size: NSMakeSize(documentSize.width, tableView.listHeight)))
        }
        
        
    }
    
    public func updateModifyState(_ state: WallpaperPreviewViewState, animated: Bool) {
        
        self.previewState = state
        switch state {
        case .color:
            patternCheckbox.isSelected = false
            colorCheckbox.isSelected = true
            updateBackground(wallpaper, image: self.image)
        case .normal:
            patternCheckbox.isSelected = false
            colorCheckbox.isSelected = false
            updateBackground(wallpaper, image: self.image)
        case .pattern:
            if let selected = patternsController.pattern {
                self.wallpaper = selected.withUpdatedSettings(self.wallpaper.settings)
            }
            patternCheckbox.isSelected = true
            colorCheckbox.isSelected = false
            
            updateBackground(wallpaper, image: self.image)
        }
        rotateColors.set(rotation: wallpaper.settings.rotation, animated: animated)
        updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate)
    }
    
    private func updateBackground(_ wallpaper: Wallpaper, image: CGImage?) {
        switch wallpaper {
        case .builtin:
            backgroundView.backgroundMode = .plain
        case let .color(color):
            backgroundView.backgroundMode = .color(color: NSColor(UInt32(color)))
        case let .gradient(_, colors, rotation):
            backgroundView.backgroundMode = .gradient(colors: colors.map { NSColor(argb: $0) }, rotation: rotation)
        case .image:
            if let image = image {
                backgroundView.backgroundMode = .background(image: NSImage(cgImage: image, size: image.size), intensity: nil, colors: nil, rotation: nil, metadata: nil)
            } else {
                backgroundView.backgroundMode = .plain
            }
        case let .file(_, _, settings, isPattern, _):
            if isPattern, settings.colors.count > 2 {
                if let image = image {
                    backgroundView.backgroundMode = .background(image: NSImage(cgImage: image, size: image.size), intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: nil)
                } else {
                    backgroundView.backgroundMode = .gradient(colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation)
                }
            } else {
                if let image = image {
                    backgroundView.backgroundMode = .background(image: NSImage(cgImage: image, size: image.size), intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: nil)
                } else {
                    backgroundView.backgroundMode = .gradient(colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation)
                }
            }
        default:
            backgroundView.backgroundMode = .plain
        }
    }
    
    private func loadImage(_ signal:Signal<ImageDataTransformation, NoError>, palette: ColorPalette, boundingSize: NSSize, isPattern: Bool) {
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: boundingSize, boundingSize: boundingSize, intrinsicInsets: NSEdgeInsets())
        
        
        let intense = CGFloat(abs(wallpaper.settings.intensity ?? 0)) / 100.0
        let signal: Signal<CGImage?, NoError> = signal |> map { result in
            var image = result.execute(arguments, result.data)?.generateImage()
            if palette.isDark, let img = image, isPattern {
                image = generateImage(img.size, contextGenerator: { size, ctx in
                    ctx.clear(size.bounds)
                    ctx.setFillColor(NSColor.black.cgColor)
                    ctx.fill(size.bounds)
                    ctx.clip(to: size.bounds, mask: img)
                    
                    ctx.clear(size.bounds)
                    
                    ctx.setFillColor(NSColor.black.withAlphaComponent(1 - intense).cgColor)
                    ctx.fill(size.bounds)
                })
            }
            return image
        } |> deliverOnMainQueue
        
        loadImageDisposable.set(signal.start(next: { [weak self] image in
            guard let strongSelf = self else {
                return
            }
            strongSelf.image = image
            strongSelf.updateBackground(strongSelf.wallpaper, image: image)
            strongSelf.ready?()
        }))
    }
    
    fileprivate var isApplyingState: Bool = false

    fileprivate func applyState(_ state: WallpaperPreviewState, animated: Bool) {
        isApplyingState = true
        defer { isApplyingState = false }

        let wallpaperChanged = wallpaper != state.wallpaper
        if wallpaperChanged {
            wallpaper = state.wallpaper
        }

        let colors: [NSColor]
        let rotation: Int32?
        switch state.wallpaper {
        case let .color(color):
            colors = [NSColor(argb: color)]
            rotation = nil
        case let .gradient(_, c, r):
            colors = c.map { NSColor(argb: $0) }
            rotation = r
        case let .file(_, _, settings, _, _):
            colors = settings.colors.map { NSColor(argb: $0) }
            rotation = settings.rotation
        default:
            colors = []
            rotation = nil
        }

        if !colors.isEmpty {
            let mode: WallpaperColorSelectMode
            if colors.count == 1 {
                mode = .single(colors[0])
            } else {
                mode = .gradient(colors, colors.count - 1, rotation)
            }
            updateMode(mode, animated: animated)
        }

        if blurCheckbox.isSelected != state.wallpaper.isBlurred {
            blurCheckbox.isSelected = state.wallpaper.isBlurred
        }

        if let checkbox = forBothCheckbox, checkbox.isSelected != state.forBoth {
            checkbox.isSelected = state.forBoth
        }

        if wallpaperChanged || image == nil {
            updateState(synchronousLoad: !animated)
        }
    }

    public func updateState(synchronousLoad: Bool) {
        let maximumSize: NSSize = WallpaperDimensions
        var updatedStatusSignal: Signal<MediaResourceStatus, NoError>?
        
        switch wallpaper {
        case let .color(color):
            self.image = nil
            blurCheckbox.isHidden = true
            colorCheckbox.isHidden = false
            patternCheckbox.isHidden = false
            self.patternCheckbox.hasPattern = false
            rotateColors.isHidden = true
            self.colorCheckbox.colorsValue = [color].map { NSColor($0) }
            self.ready?()
        case let .gradient(_, colors, _):
            self.image = nil
            blurCheckbox.isHidden = true
            colorCheckbox.isHidden = false
            patternCheckbox.isHidden = false
            rotateColors.isHidden = false
            self.patternCheckbox.hasPattern = false
            self.colorCheckbox.colorsValue = colors.map { NSColor($0) }
            self.rotateColors.update(colors.count > 2 ? theme.icons.wallpaper_color_play : theme.icons.wallpaper_color_rotate)
            self.rotateColors.setAccessibilityLabel(colors.count > 2 ? strings().voiceOverCommonPlay : strings().voiceOverCommonRotate)
            self.ready?()
        case let .image(representations, settings):
            self.patternCheckbox.hasPattern = false
            blurCheckbox.isHidden = false
            colorCheckbox.isHidden = true
            patternCheckbox.isHidden = true
            rotateColors.isHidden = true
            let dimensions = largestImageRepresentation(representations)!.dimensions.size
            let boundingSize = dimensions.fitted(maximumSize)
            self.imageSize = dimensions
            
            loadImage(chatWallpaper(account: context.account, representations: representations, mode: .screen, isPattern: false, autoFetchFullSize: true, scale: backingScaleFactor, isBlurred: settings.blur, synchronousLoad: synchronousLoad, drawPatternOnly: true), palette: theme.colors, boundingSize: boundingSize, isPattern: false)

            
            updatedStatusSignal = context.account.postbox.mediaBox.resourceStatus(largestImageRepresentation(representations)!.resource, approximateSynchronousValue: synchronousLoad) |> deliverOnMainQueue

        case let .file(_, file, settings, isPattern, _):
            blurCheckbox.isHidden = isPattern

            colorCheckbox.isHidden = !isPattern
            patternCheckbox.isHidden = !isPattern
            rotateColors.isHidden = !isPattern
            
            if isPattern {
                self.colorCheckbox.colorsValue = settings.colors.map { NSColor($0) }
            }

            self.patternCheckbox.hasPattern = isPattern
            
            var representations:[TelegramMediaImageRepresentation] = []
            representations.append(contentsOf: file.previewRepresentations)
            if let dimensions = file.dimensions {
                representations.append(TelegramMediaImageRepresentation(dimensions: dimensions, resource: file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
            } else {
                representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(maximumSize), resource: file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
            }
            
            if isPattern {
                self.rotateColors.update(settings.colors.count > 2 ? theme.icons.wallpaper_color_play : theme.icons.wallpaper_color_rotate)
                self.rotateColors.setAccessibilityLabel(settings.colors.count > 2 ? strings().voiceOverCommonPlay : strings().voiceOverCommonRotate)
            }
            
            let dimensions = largestImageRepresentation(representations)!.dimensions.size
            let boundingSize = dimensions.aspectFilled(frame.size)

            
            loadImage(chatWallpaper(account: context.account, representations: representations, file: file, mode: .thumbnail, isPattern: isPattern, autoFetchFullSize: true, scale: backingScaleFactor, isBlurred:  settings.blur, synchronousLoad: synchronousLoad, drawPatternOnly: true), palette: theme.colors, boundingSize: boundingSize, isPattern: isPattern)

                        
            self.imageSize = dimensions

            updatedStatusSignal = context.account.postbox.mediaBox.resourceStatus(largestImageRepresentation(representations)!.resource, approximateSynchronousValue: synchronousLoad) |> deliverOnMainQueue
        default:
            break
        }
        
        updateBackground(self.wallpaper, image: self.image)

        
        if let updatedStatusSignal = updatedStatusSignal {
            disposable.set(updatedStatusSignal.start(next: { [weak self] status in
                guard let `self` = self else { return }
                switch status {
                case let .Fetching(_, progress), let .Paused(progress):
                    if self.progressView == nil {
                        self.progressView = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .blackTransparent, foregroundColor: .white), twist: true, size: NSMakeSize(40, 40))
                        self.addSubview(self.progressView!)
                        self.progressView?.center()
                    }
                    self.progressView?.state = .ImpossibleFetching(progress: progress, force: false)
                    break
                case .Local:
                    if let progressView = self.progressView {
                        progressView.state = .ImpossibleFetching(progress:1.0, force: false)
                        self.progressView = nil
                        progressView.layer?.animateAlpha(from: 1, to: 0, duration: 0.25, timingFunction: .linear, removeOnCompletion: false, completion: { [weak progressView] completed in
                            if completed {
                                progressView?.removeFromSuperview()
                            }
                        })
                    }
                    
                case .Remote:
                    break
                }
            }))
        } else {
            progressView?.removeFromSuperview()
            progressView = nil
        }
        
        let serviceColor = self.serviceColor
        
        self.blurCheckbox.update(by: serviceColor)
        self.colorCheckbox.update(by: serviceColor)
        self.patternCheckbox.update(by: serviceColor)
        self.rotateColors.update(by: serviceColor)
        
        needsLayout = true
    }
    
    public var serviceColor: NSColor {
        switch wallpaper {
        case .builtin, .file, .color, .gradient:
            switch backgroundView.backgroundMode {
            case let .background(image, _, colors, _, _):
                if let colors = colors, let first = colors.first {
                    let blended = colors.reduce(first, { color, with in
                        return color.blended(withFraction: 0.5, of: with)!
                    })
                    return getAverageColor(blended)
                } else {
                    return getAverageColor(image)
                }
            case let .color(color):
                return getAverageColor(color)
            case let .gradient(colors, _):
                if !colors.isEmpty {
                    let blended = colors.reduce(colors.first!, { color, with in
                        return color.blended(withFraction: 0.5, of: with)!
                    })
                    return getAverageColor(blended)
                } else {
                    return getAverageColor(theme.colors.chatBackground)
                }
                
            case let .tiled(image):
                return getAverageColor(image)
            case .plain:
                return getAverageColor(theme.colors.chatBackground)
            }
        default:
            return getAverageColor(theme.colors.chatBackground)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

public enum WallpaperSource {
    case link(TelegramWallpaper)
    case chat(Peer, TelegramWallpaper?)
    case message(MessageId, TelegramWallpaper?)
    case gallery(TelegramWallpaper)
    case none
    case custom(TelegramWallpaper?)
    public var peerId: PeerId? {
        switch self {
        case let .chat(peer, _):
            return peer.id
        case let .message(messageId, _):
            return messageId.peerId
        default:
            return nil
        }
    }
    
    public func withWallpaper(_ wallpaper: TelegramWallpaper) -> WallpaperSource {
        switch self {
        case .none:
            return .gallery(wallpaper)
        case let .message(messageId, _):
            return .message(messageId, wallpaper)
        case let .chat(peerId, _):
            return .chat(peerId, wallpaper)
        case .gallery:
            return .gallery(wallpaper)
        case .link:
            return .link(wallpaper)
        case .custom:
            return .custom(wallpaper)
        }
    }
}

private func cropWallpaperImage(_ image: CGImage, dimensions: NSSize, rect: NSRect, magnify: CGFloat, settings: WallpaperSettings?) -> CGImage {
    let fittedSize = NSMakeSize(dimensions.width * magnify, dimensions.height * magnify)//WallpaperDimensions.aspectFitted(representation.dimensions)
    
    let image = generateImage(rect.size, contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.normal)
        let imageRect = NSMakeRect(-rect.minX, -rect.minY, fittedSize.width, fittedSize.height)
        ctx.draw(image, in: imageRect)
    }, opaque: false, scale: 1.0)!
    
    let fitted = WallpaperDimensions.aspectFitted(dimensions)
    
    return generateImage(fitted, contextGenerator: { size, ctx in
        let imageRect = NSMakeRect(0, 0, fitted.width, fitted.height)
        ctx.clear(imageRect)
        if let settings = settings {
            
          var _patternColor: NSColor = NSColor(rgb: 0xd6e2ee, alpha: 0.5)
            
            var patternIntensity: CGFloat = 0.5
            if let color = settings.colors.first {
                if let intensity = settings.intensity {
                    patternIntensity = CGFloat(intensity) / 100.0
                }
                _patternColor = NSColor(rgb: color, alpha: patternIntensity)
            }
            
            let color = _patternColor.withAlphaComponent(1.0)
            let intensity = _patternColor.alpha
            
            ctx.setBlendMode(.copy)
            ctx.setFillColor(color.cgColor)
            ctx.fill(imageRect)
            
            ctx.setBlendMode(.normal)
            ctx.interpolationQuality = .high

            ctx.clip(to: imageRect, mask: image)
            ctx.setFillColor(patternColor(for: color, intensity: intensity).cgColor)
            ctx.fill(imageRect)
        } else {
            ctx.draw(image, in: imageRect)
        }
    }, opaque: false, scale: 1.0)!
    
}

private func cropWallpaperIfNeeded(_ wallpaper: Wallpaper, account: Account, rect: NSRect, magnify: CGFloat = 1.0) -> Signal<Wallpaper, NoError> {
    return Signal { subscriber in
        
        let disposable = MetaDisposable()
        switch wallpaper {
        case let .image(representations, _):
            if let representation = largestImageRepresentation(representations) {
                let path = account.postbox.mediaBox.resourcePath(representation.resource)
                if let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    
                    let fittedImage = cropWallpaperImage(image, dimensions: representation.dimensions.size, rect: rect, magnify: magnify, settings: nil)

                    let options = NSMutableDictionary()
                    options.setValue(90 as NSNumber, forKey: kCGImageDestinationImageMaxPixelSize as String)
                    var result: [TelegramMediaImageRepresentation] = []
                    let colorQuality: Float = 0.1
                    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                    let mutableData: CFMutableData = NSMutableData() as CFMutableData
                    
                    if let colorDestination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) {
                        CGImageDestinationAddImage(colorDestination, fittedImage, options as CFDictionary)
                        if CGImageDestinationFinalize(colorDestination) {
                            let thumdResource = LocalFileMediaResource(fileId: arc4random64())
                            account.postbox.mediaBox.storeResourceData(thumdResource.id, data: mutableData as Data)
                            result.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(fittedImage.backingSize.aspectFitted(NSMakeSize(90, 90))), resource: thumdResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                        }
                    }
                    
                    let fittedDimensions = WallpaperDimensions.aspectFitted(representation.dimensions.size)
                    
                     disposable.set(putToTemp(image: NSImage(cgImage: fittedImage, size: fittedDimensions), compress: false).start(next: { path in
                         
                         let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                         guard let data = data else {
                             subscriber.putCompletion()
                             return
                         }
                         let resource = LocalFileMediaResource(fileId: arc4random64(), size: Int64(data.count))
                         account.postbox.mediaBox.storeResourceData(resource.id, data: data)
                         
                         result.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(fittedDimensions), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))

                         

                         
                        
                        let wallpaper: Wallpaper = .image(result, settings: wallpaper.settings)
                        subscriber.putNext(wallpaper)
                        subscriber.putCompletion()
                    }))
                }
            }
        case let .file(slug, file, settings, isPattern, _):
            
            let dimensions = file.dimensions?.size ?? WallpaperDimensions
            if isPattern {
                
                let path = account.postbox.mediaBox.cachedRepresentationCompletePath(file.resource.id, representation: CachedPatternWallpaperMaskRepresentation(size: nil))
                
                if let image = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                    let size = image.size.aspectFilled(WallpaperDimensions)
                    
                    let image = generateImage(size, contextGenerator: { size, ctx in
                        let imageRect = NSMakeRect(0, 0, size.width, size.height)
                        
                        let colors:[NSColor]
                        var intensity: CGFloat = 0.5
                        
                        if settings.colors.count == 1 {
                            let combinedColor = NSColor(settings.colors.first!)
                            if let i = settings.intensity {
                                intensity = CGFloat(i) / 100.0
                            }
                            intensity = combinedColor.alpha
                            colors = [combinedColor.withAlphaComponent(1.0)]
                        } else if settings.colors.count > 1 {
                            if let i = settings.intensity {
                                intensity = CGFloat(i) / 100.0
                            }
                            colors = settings.colors.map { NSColor(argb: $0) }.reversed().map { $0.withAlphaComponent(1.0) }
                        } else {
                            colors = [NSColor(rgb: 0xd6e2ee, alpha: 0.5)]
                        }
                        
                        ctx.setBlendMode(.copy)
                        if colors.count == 1, let color = colors.first {
                            ctx.setFillColor(color.cgColor)
                            ctx.fill(imageRect)
                        } else {
                            let gradient = CGGradient.evenlySpaced(colors)!

                            ctx.saveGState()
                            ctx.translateBy(x: imageRect.width / 2.0, y: imageRect.height / 2.0)
                            ctx.rotate(by: CGFloat(settings.rotation ?? 0) * CGFloat.pi / -180.0)
                            ctx.translateBy(x: -imageRect.width / 2.0, y: -imageRect.height / 2.0)

                            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: imageRect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                            ctx.restoreGState()
                        }
                        
                        
                        ctx.setBlendMode(.normal)
                        ctx.interpolationQuality = .medium
                        ctx.clip(to: imageRect, mask: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                        
                        if colors.count == 1, let color = colors.first {
                            ctx.setFillColor(patternColor(for: color, intensity: intensity).cgColor)
                            ctx.fill(imageRect)
                        } else {
                            let gradient = CGGradient.evenlySpaced(colors.map { patternColor(for: $0, intensity: intensity).cgColor })!
                            
                            ctx.translateBy(x: imageRect.width / 2.0, y: imageRect.height / 2.0)
                            ctx.rotate(by: CGFloat(settings.rotation ?? 0) * CGFloat.pi / -180.0)
                            ctx.translateBy(x: -imageRect.width / 2.0, y: -imageRect.height / 2.0)
                            
                            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: imageRect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                        }
                        
                    })!
                    
                    disposable.set(putToTemp(image: NSImage(cgImage: image, size: size), compress: false).start(next: { path in
                        
                        
                        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                        guard let data = data else {
                            subscriber.putCompletion()
                            return
                        }
                        let resource = LocalFileMediaResource(fileId: arc4random64(), size: Int64(data.count))
                        account.postbox.mediaBox.storeResourceData(resource.id, data: data)
                                                                        
                        var attributes = file.attributes
                        loop: for (i, attr) in attributes.enumerated() {
                            switch attr {
                            case .ImageSize:
                                attributes[i] = .ImageSize(size: PixelDimensions(size))
                                break loop
                            default:
                                break
                            }
                        }
                        let wallpaper: Wallpaper = .file(slug: slug, file: file.withUpdatedResource(resource).withUpdatedAttributes(attributes), settings: settings, isPattern: isPattern, gift: nil)
                        subscriber.putNext(wallpaper)
                        subscriber.putCompletion()
                    }))
                }
                
                subscriber.putNext(wallpaper.withUpdatedSettings(settings))
                subscriber.putCompletion()
            } else {
                if let path = account.postbox.mediaBox.completedResourcePath(file.resource), let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let fittedImage = cropWallpaperImage(image, dimensions: dimensions, rect: rect, magnify: magnify, settings: isPattern ? settings : nil)
                    
                    let options = NSMutableDictionary()
                    options.setValue(90 as NSNumber, forKey: kCGImageDestinationImageMaxPixelSize as String)
                    var result: [TelegramMediaImageRepresentation] = []
                    let colorQuality: Float = 0.1
                    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                    let mutableData: CFMutableData = NSMutableData() as CFMutableData
                    
                    if let colorDestination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) {
                        CGImageDestinationAddImage(colorDestination, fittedImage, options as CFDictionary)
                        if CGImageDestinationFinalize(colorDestination) {
                            let thumdResource = LocalFileMediaResource(fileId: arc4random64())
                            account.postbox.mediaBox.storeResourceData(thumdResource.id, data: mutableData as Data)
                            result.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(fittedImage.backingSize.aspectFitted(NSMakeSize(90, 90))), resource: thumdResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                        }
                    }
                    
                    let fittedDimensions = WallpaperDimensions.aspectFitted(dimensions)
                    
                    disposable.set(putToTemp(image: NSImage(cgImage: fittedImage, size: fittedDimensions), compress: false).start(next: { path in
                        
                        
                        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                        guard let data = data else {
                            subscriber.putCompletion()
                            return
                        }
                        let resource = LocalFileMediaResource(fileId: arc4random64(), size: Int64(data.count))
                        account.postbox.mediaBox.storeResourceData(resource.id, data: data)
                        
                        result.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(fittedDimensions), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                                                
                        var attributes = file.attributes
                        loop: for (i, attr) in attributes.enumerated() {
                            switch attr {
                            case .ImageSize:
                                attributes[i] = .ImageSize(size: PixelDimensions(fittedDimensions))
                                break loop
                            default:
                                break
                            }
                        }
                        
                        let wallpaper: Wallpaper = .file(slug: slug, file: file.withUpdatedPreviewRepresentations(result).withUpdatedResource(resource).withUpdatedAttributes(attributes), settings: settings, isPattern: isPattern, gift: nil)
                        subscriber.putNext(wallpaper)
                        subscriber.putCompletion()
                    }))
                }
            }
        default:
            subscriber.putNext(wallpaper)
            subscriber.putCompletion()
        }
        
        return ActionDisposable {
            disposable.dispose()
        }
    } |> runOn(resourcesQueue)
}


private final class WallpaperPreviewRowItem: GeneralRowItem {
    fileprivate let previewView: WallpaperPreviewView
    fileprivate let viewHeight: CGFloat
    fileprivate let state: WallpaperPreviewState
    public init(_ initialSize: NSSize, stableId: AnyHashable, previewView: WallpaperPreviewView, viewHeight: CGFloat, state: WallpaperPreviewState) {
        self.previewView = previewView
        self.viewHeight = viewHeight
        self.state = state
        super.init(initialSize, stableId: stableId)
    }
    public override var height: CGFloat {
        return viewHeight
    }
    public override func viewClass() -> AnyClass {
        return WallpaperPreviewRowView.self
    }
    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonWallpaper
    }
}

private final class WallpaperPreviewRowView: TableRowView {
    public override var backdorColor: NSColor {
        return .clear
    }
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? WallpaperPreviewRowItem else { return }
        if item.previewView.superview !== self {
            item.previewView.removeFromSuperview()
            item.previewView.frame = bounds
            addSubview(item.previewView)
        }
        item.previewView.applyState(item.state, animated: animated)
    }
    public override func layout() {
        super.layout()
        guard let item = self.item as? WallpaperPreviewRowItem else { return }
        item.previewView.frame = bounds
        item.previewView.updateLayout(size: bounds.size, transition: .immediate)
    }
}

private func wallpaperPreviewEntries(_ state: WallpaperPreviewState, previewView: WallpaperPreviewView, viewHeight: CGFloat) -> [InputDataEntry] {
    let _id_preview = InputDataIdentifier("_id_preview")
    return [
        .custom(sectionId: 0, index: 0, value: .none, identifier: _id_preview, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return WallpaperPreviewRowItem(initialSize, stableId: stableId, previewView: previewView, viewHeight: viewHeight, state: state)
        })
    ]
}

private func shareWallpaper(_ context: any AccountContextProtocol, _ wallpaper: Wallpaper) {
    switch wallpaper {
    case let .file(slug, _, settings, isPattern, _):
        var options: [String] = []
        if settings.blur {
            options.append("mode=blur")
        }
        if isPattern {
            if !settings.colors.isEmpty {
                let colors: [String] = settings.colors.map { value in
                    let color = NSColor(argb: value).rgbHexString.lowercased()
                    return String(color[color.index(after: color.startIndex) ..< color.endIndex])
                }
                options.append("bg_color=\(colors.joined(separator: "~"))")
            }
            if let intensity = settings.intensity {
                options.append("intensity=\(intensity)")
            } else {
                options.append("intensity=50")
            }
            if let r = settings.rotation {
                options.append("rotation=\(r)")
            }
        }
        var optionsString = ""
        if !options.isEmpty {
            optionsString = "?\(options.joined(separator: "&"))"
        }
        WallpaperHooks.shared.shareLink(context, context.meUrlPrefix + "bg/\(slug)\(optionsString)")
    case let .color(color):
        var color = NSColor(argb: color).rgbHexString.lowercased()
        color = String(color[color.index(after: color.startIndex) ..< color.endIndex])
        WallpaperHooks.shared.shareLink(context, context.meUrlPrefix + "bg/\(color)")
    case let .gradient(_, colors, r):
        let parts: [String] = colors.map { value in
            let color = NSColor(argb: value).rgbHexString.lowercased()
            return String(color[color.index(after: color.startIndex) ..< color.endIndex])
        }
        var rotation: String = ""
        if let r = r {
            rotation = "?rotation=\(r)"
        }
        WallpaperHooks.shared.shareLink(context, context.meUrlPrefix + "bg/\(parts.joined(separator: "~"))" + rotation)
    default:
        break
    }
}

private struct WallpaperPreviewState: Equatable {
    public var wallpaper: Wallpaper
    public var forBoth: Bool
}

public func WallpaperPreviewController(_ context: any AccountContextProtocol, wallpaper: Wallpaper, source: WallpaperSource, onComplete: ((TelegramWallpaper?) -> Void)? = nil) -> InputDataModalController {

    let baseWallpaper: Wallpaper = wallpaper.isSemanticallyEqual(to: theme.wallpaper.wallpaper) ? wallpaper.withUpdatedBlurrred(theme.wallpaper.wallpaper.isBlurred) : wallpaper

    let initialWallpaper: Wallpaper
    switch baseWallpaper {
    case let .file(_, _, settings, isPattern, _):
        if isPattern && settings.colors.isEmpty {
            let defaultColor: UInt32 = NSColor(rgb: 0xd6e2ee, alpha: 0.5).argb
            initialWallpaper = baseWallpaper.withUpdatedSettings(settings.withUpdatedColor(defaultColor))
        } else {
            initialWallpaper = baseWallpaper
        }
    default:
        initialWallpaper = baseWallpaper
    }

    let initialState = WallpaperPreviewState(wallpaper: initialWallpaper, forBoth: false)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WallpaperPreviewState) -> WallpaperPreviewState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let chatSize = NSMakeSize(context.bindings.rootNavigation().frame.width, min(500, context.window.frame.height - 150))
    let modalSize = WallpaperDimensions.aspectFitted(chatSize)

    let previewView = WallpaperPreviewView(frame: NSMakeRect(0, 0, modalSize.width, modalSize.height), source: source, context: context, wallpaper: initialWallpaper)

    var close: (() -> Void)? = nil
    var applyAndCloseRef: (() -> Void)? = nil

    let signal: Signal<InputDataSignalValue, NoError> = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: wallpaperPreviewEntries(state, previewView: previewView, viewHeight: modalSize.height))
    }

    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .appWallpaperPreview

    let hasShare: Bool
    switch initialWallpaper {
    case .color, .gradient, .file:
        hasShare = true
    default:
        hasShare = false
    }
    previewView.shareButton.isHidden = !hasShare

    controller.didLoad = { controller, _ in
        previewView.ready = { [weak controller] in
            controller?.tableView.needsLayout = true
        }
        previewView.apply.set(handler: { _ in
            applyAndCloseRef?()
        }, for: .Click)
        previewView.dismissButton.set(handler: { _ in
            close?()
        }, for: .Click)
        previewView.shareButton.set(handler: { _ in
            shareWallpaper(context, stateValue.with { $0.wallpaper })
        }, for: .Click)

        previewView.onWallpaperChange = { wallpaper in
            updateState { current in
                var current = current
                current.wallpaper = wallpaper
                return current
            }
        }
        previewView.onForBothChange = { value in
            updateState { current in
                var current = current
                current.forBoth = value
                return current
            }
        }
    }

    let applyAndClose: () -> Void = { [weak previewView] in
        guard let previewView = previewView else {
            return
        }
        let state = stateValue.with { $0 }
        let bothPeer = state.forBoth
        if case .chat = source, !context.isPremium, bothPeer {
            prem(with: PremiumBoardingController(context: context, openFeatures: true), for: context.window)
            return
        }
        switch source {
        case .custom:
            close?()
        default:
            closeAllModals()
        }
        let current = state.wallpaper
        switch source {
        case .gallery, .link, .none:
            let signal = cropWallpaperIfNeeded(current, account: context.account, rect: previewView.croppedRect) |> mapToSignal { wallpaper in
                return moveWallpaperToCache(postbox: context.account.postbox, wallpaper: wallpaper)
            }
            _ = signal.start(next: { wallpaper in
                _ = (updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                    return settings.updateWallpaper { $0.withUpdatedWallpaper(wallpaper) }.saveDefaultWallpaper().withSavedAssociatedTheme().withUpdatedBubbled(true)
                }) |> delay(0.2, queue: .mainQueue()) |> deliverOnMainQueue).start(completed: {
                    var stats: [Signal<Void, NoError>] = []
                    switch source {
                    case let .gallery(wallpaper):
                        stats = [installWallpaper(account: context.account, wallpaper: wallpaper)]
                    case let .link(wallpaper):
                        stats = [installWallpaper(account: context.account, wallpaper: wallpaper), saveWallpaper(account: context.account, wallpaper: wallpaper)]
                    default:
                        break
                    }
                    let _ = combineLatest(stats).start()
                    onComplete?(wallpaper.cloudWallpaper)
                })
            })
        case .chat, .message:
            _ = (updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                return settings.withUpdatedBubbled(true)
            }) |> delay(0.2, queue: .mainQueue()) |> deliverOnMainQueue).start(completed: {
                let complete: Signal<Never, NoError>
                switch current {
                case let .image(representations, settings):
                    if let peerId = source.peerId {
                        let temporaryWallpaper: TelegramWallpaper = .image(representations, settings)
                        context.account.pendingPeerMediaUploadManager.add(peerId: peerId, content: .wallpaper(wallpaper: temporaryWallpaper, forBoth: bothPeer))
                    }
                    complete = .complete()
                default:
                    switch source {
                    case let .chat(peer, _):
                        complete = context.engine.themes.setChatWallpaper(peerId: peer.id, wallpaper: current.cloudWallpaper, forBoth: bothPeer) |> `catch` { _ in return .complete() }
                    case let .message(messageId, _):
                        complete = context.engine.themes.setExistingChatWallpaper(messageId: messageId, settings: current.settings, forBoth: bothPeer) |> `catch` { _ in return .complete() } |> ignoreValues
                    default:
                        complete = .complete()
                    }
                }
                let _ = complete.start()
                onComplete?(current.cloudWallpaper)
            })
        case .custom:
            let signal = cropWallpaperIfNeeded(current, account: context.account, rect: previewView.croppedRect) |> mapToSignal { wallpaper in
                return moveWallpaperToCache(postbox: context.account.postbox, wallpaper: wallpaper)
            }
            _ = signal.start(next: { wallpaper in
                onComplete?(wallpaper.cloudWallpaper)
            })
        }
    }

    applyAndCloseRef = applyAndClose

    let modalController = InputDataModalController(controller, modalInteractions: nil, size: modalSize)

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
