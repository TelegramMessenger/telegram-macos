import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InAppSettings
import libwebp

class SEFoldersRowItem: TableStickItem {
    fileprivate let action:((ChatListFilter)->Void)?
    fileprivate let context: AccountContext?
    fileprivate let tabs: [ChatListFilter]
    fileprivate let selected: ChatListFilter
    fileprivate let presentation: TelegramPresentationTheme
    init(_ initialSize: NSSize, context: AccountContext, tabs: [ChatListFilter], selected: ChatListFilter, action: ((ChatListFilter)->Void)? = nil, presentation: TelegramPresentationTheme = theme) {
        self.action = action
        self.context = context
        self.tabs = tabs
        self.presentation = presentation
        self.selected = selected
        super.init(initialSize)
    }
    
    required init(_ initialSize: NSSize) {
        self.action = nil
        self.context = nil
        self.tabs = []
        self.presentation = theme
        self.selected = .allChats
        super.init(initialSize)
    }
    

    override var backdorColor: NSColor {
        return self.presentation.colors.background
    }
    
    override var borderColor: NSColor {
        return .clear
    }

    override var singletonItem: Bool {
        return false
    }
    
    override var stableId: AnyHashable {
        return SelectablePeersEntryStableId.folders
    }
    
    override func viewClass() -> AnyClass {
        return FoldersRowView.self
    }
    
    override var identifier: String {
        return "FoldersRowView"
    }
    
    override var height: CGFloat {
        return 44
    }
}


final class FoldersRowView : TableStickView {
    private let containerView = View()
    private let glass = LiquidGlassView(frame: .zero, cornerRadius: 18, hasShadow: false, hasBorder: false)
    private var animated: Bool = false
    let segmentView: ScrollableSegmentView = ScrollableSegmentView(frame: NSZeroRect)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(containerView)
        containerView.addSubview(glass)
        containerView.addSubview(segmentView)
        segmentView.layer?.cornerRadius = 18
        segmentView.layer?.masksToBounds = true
        containerView.backgroundColor = .clear
        glass.isEventLess = true
    }
    
    
    
    override func mouseUp(with event: NSEvent) {
       
    }
    override func mouseDown(with event: NSEvent) {
        if mouseInside() {
        }
    }
    
    
    override func updateIsVisible(_ visible: Bool, animated: Bool) {
        super.updateIsVisible(visible, animated: animated)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func updateColors() {
        super.updateColors()
        if let item = item as? SEFoldersRowItem {
            glass.updateLocalizationAndTheme(theme: item.presentation)
        }
        needsDisplay = true
    }
    
    private var splitViewState: SplitViewState?
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? SEFoldersRowItem else {
            return
        }
        
        var animated = (self.animated || animated)
        self.animated = true
        
        
        guard let context = item.context else {
            return
        }
        
        animated = animated && splitViewState == context.layout
        self.splitViewState = context.layout
        
        let segmentTheme = ScrollableSegmentTheme(background: .clear, border: .clear, selector: item.presentation.colors.accent, inactiveText: item.presentation.colors.grayText, activeText: item.presentation.colors.accent, textFont: .normal(.title))
        segmentView.theme = segmentTheme
        var index: Int = 0
        let insets = NSEdgeInsets(left: 10, right: 10)
        var items:[ScrollableSegmentItem] = []
        for tab in item.tabs {
            let title: String = tab.title
            let selected = item.selected == tab
            items.append(ScrollableSegmentItem(title: title, index: index, uniqueId: Int64(tab.id), selected: selected, insets: insets, icon: nil, theme: segmentTheme, equatable: UIEquatable(tab), customTextView: {
                return SEFolderTitleView(title: title, entities: tab.entities, color: selected ? segmentTheme.activeText : segmentTheme.inactiveText, font: segmentTheme.textFont, context: context, animated: tab.enableAnimations && !context.isLite(.emoji) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }))
            index += 1
        }
        
        segmentView.updateItems(items, animated: animated)

        segmentView.didChangeSelectedItem = { [weak item] selected in
            if let item = item {
                if selected.uniqueId == -1 {
                    item.action?(.allChats)
                } else {
                    item.action?(item.tabs[selected.index])
                }
            }
        }
      
    }
    
    
    override var isHidden: Bool {
        didSet {
            if isHidden {
                var bp:Int = 0
                bp += 1
            }
        }
    }
    
    override var isAlwaysUp: Bool {
        return true
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview()
    }
    
    public override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func layout() {
        super.layout()
        
        containerView.frame = bounds.insetBy(dx: 10, dy: 4)
        glass.frame = containerView.bounds
        glass.updateLayout(size: glass.frame.size, transition: .immediate)
        segmentView.frame = containerView.bounds
      
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct SEFolderTitleEmoji {
    let fileId: Int64
    let fallback: String
}

private enum SEFolderTitle {
    static func make(title: String, entities: [MessageTextEntity], color: NSColor, font: NSFont) -> (text: NSAttributedString, emojis: [Int: SEFolderTitleEmoji]) {
        let attributed = NSMutableAttributedString(string: title, attributes: [.foregroundColor: color, .font: font])
        var embedded: [Int: SEFolderTitleEmoji] = [:]
        var previousStart = attributed.length
        for entity in entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            guard case let .CustomEmoji(_, fileId) = entity.type,
                  entity.range.lowerBound >= 0,
                  entity.range.upperBound <= previousStart,
                  !entity.range.isEmpty else {
                continue
            }
            let range = NSRange(location: entity.range.lowerBound, length: entity.range.count)
            guard (title as NSString).rangeOfComposedCharacterSequences(for: range) == range else {
                continue
            }
            let fallback = (title as NSString).substring(with: range)
            let token = embedded.count
            var attributes = attributed.attributes(at: range.location, effectiveRange: nil)
            attributes[TextInputAttributes.embedded] = token
            attributed.replaceCharacters(in: range, with: NSAttributedString(string: "🤡", attributes: attributes))
            embedded[token] = SEFolderTitleEmoji(fileId: fileId, fallback: fallback)
            previousStart = range.location
        }

        return (attributed, embedded)
    }
}

private final class SEFolderTitleView: View {
    private let textView = TextView()
    private let resolveDisposable = MetaDisposable()

    init(title: String, entities: [MessageTextEntity], color: NSColor, font: NSFont, context: AccountContext, animated: Bool) {
        super.init(frame: .zero)
        userInteractionEnabled = false
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        layer?.masksToBounds = false
        addSubview(textView)

        let content = SEFolderTitle.make(title: title, entities: entities, color: color, font: font)
        let layout = TextViewLayout(content.text, maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
        setFrameSize(layout.layoutSize)

        var emojiViews: [(view: SEFolderEmojiView, fileId: Int64)] = []
        for item in layout.embeddedItems {
            guard let token = item.value.base as? Int, let emoji = content.emojis[token] else {
                continue
            }
            let view = SEFolderEmojiView(frame: item.rect, fallback: emoji.fallback, color: color, font: font)
            addSubview(view)
            emojiViews.append((view, emoji.fileId))
        }
        let fileIds = Array(Set(emojiViews.map { $0.fileId }))
        if !fileIds.isEmpty {
            resolveDisposable.set((context.engine.stickers.resolveInlineStickers(fileIds: fileIds) |> deliverOnMainQueue).start(next: { files in
                for (view, fileId) in emojiViews {
                    if let file = files[fileId] {
                        view.update(file: file, context: context, animated: animated, color: color)
                    }
                }
            }))
        }
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        resolveDisposable.dispose()
    }
}

private final class SEFolderEmojiView: View {
    private let fallbackView = TextView()
    private let imageView = ImageView()
    private let player = SE_LottiePlayerView(frame: .zero)
    private let resourceDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let stateDisposable = MetaDisposable()
    private var file: TelegramMediaFile?

    init(frame: NSRect, fallback: String, color: NSColor, font: NSFont) {
        super.init(frame: frame)
        userInteractionEnabled = false
        fallbackView.userInteractionEnabled = false
        fallbackView.isSelectable = false
        let layout = TextViewLayout(.initialize(string: fallback, color: color, font: font), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        fallbackView.update(layout)
        fallbackView.frame = bounds.focus(layout.layoutSize)
        imageView.frame = bounds
        player.frame = bounds
        addSubview(fallbackView)
        addSubview(imageView)
        addSubview(player)
        stateDisposable.set((player.state |> deliverOnMainQueue).start(next: { [weak self] state in
            switch state {
            case .playing, .finished:
                self?.fallbackView.isHidden = true
            case .failed:
                self?.fallbackView.isHidden = false
            default:
                break
            }
        }))
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(file: TelegramMediaFile, context: AccountContext, animated: Bool, color: NSColor) {
        guard self.file != file else {
            return
        }
        self.file = file
        let isVideo = file.mimeType == "video/webm"
        let resource: MediaResource
        if isVideo {
            guard let preview = file.previewRepresentations.last else {
                return
            }
            resource = preview.resource
        } else {
            resource = file.resource
        }
        let reference = MediaResourceReference.media(media: .standalone(media: file), resource: resource)
        fetchDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .sticker, reference: reference).start())
        resourceDisposable.set((context.account.postbox.mediaBox.resourceData(resource) |> filter { $0.complete } |> take(1) |> map { data -> Data? in
            return try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedIfSafe)
        } |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self, let data else {
                return
            }
            if isVideo {
                let image = (WebPImageDecoder(data: data, scale: System.backingScale)?.frame(at: 0, decodeForDisplay: true)?.image ?? NSImage(data: data))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                if let image {
                    self.imageView.image = file.isCustomTemplateEmoji ? image.highlight(color: color) : image
                    self.fallbackView.isHidden = true
                }
            } else if file.mimeType == "image/webp" || file.isAnimatedSticker {
                let colors: [LottieColor] = file.isCustomTemplateEmoji ? [LottieColor(keyPath: "", color: color)] : []
                let animation = SE_LottieAnimation(compressed: data, key: SE_LottieAnimationEntryKey(key: .media(file.id), size: self.bounds.size), type: file.mimeType == "image/webp" ? .webp : .lottie, playPolicy: animated ? .playCount(2) : .framesCount(1), maximumFps: 30, colors: colors, postbox: context.account.postbox)
                self.player.set(animation)
            }
        }))
    }

    deinit {
        resourceDisposable.dispose()
        fetchDisposable.dispose()
        stateDisposable.dispose()
    }
}
