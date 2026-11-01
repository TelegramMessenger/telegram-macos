import Cocoa
import TGUIKit
import SwiftSignalKit
import Translate
import ObjcUtils
import Localization
import TelegramCore
import Postbox
import TelegramMedia
import RichTextEditorCore
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import ChatUI
import InputView
import InlineStickerLayer

private enum TranslateTabMode: Equatable {
    case translate
    case style
    case fix
}

private struct TranslationStyleItem: Equatable {
    let id: String
    let title: String
    let fileId: Int64
    let reference: TelegramComposeAIMessageMode.CloudStyle.Reference?
    let isAuthor: Bool
    let slug: String?
    let authorId: EnginePeer.Id?
    let cloudStyle: TelegramComposeAIMessageMode.CloudStyle?

    init(id: String, title: String, fileId: Int64, reference: TelegramComposeAIMessageMode.CloudStyle.Reference? = nil, isAuthor: Bool = false, slug: String? = nil, authorId: EnginePeer.Id? = nil, cloudStyle: TelegramComposeAIMessageMode.CloudStyle? = nil) {
        self.id = id
        self.title = title
        self.fileId = fileId
        self.reference = reference
        self.isAuthor = isAuthor
        self.slug = slug
        self.authorId = authorId
        self.cloudStyle = cloudStyle
    }

    var isCustom: Bool {
        if case .custom = reference {
            return true
        }
        return false
    }
}

private func makeStyleItem(from cloudStyle: TelegramComposeAIMessageMode.CloudStyle) -> TranslationStyleItem {
    switch cloudStyle.content {
    case let .standard(standard):
        return TranslationStyleItem(id: standard.type, title: standard.title, fileId: standard.emojiFileId ?? 0, reference: cloudStyle.reference, isAuthor: false, slug: nil, authorId: nil, cloudStyle: cloudStyle)
    case let .custom(custom):
        return TranslationStyleItem(id: "custom_\(custom.id)", title: custom.title, fileId: custom.emojiFileId ?? 0, reference: cloudStyle.reference, isAuthor: custom.isCreator, slug: custom.slug, authorId: custom.authorId, cloudStyle: cloudStyle)
    }
}

private let defaultTranslationStyles: [TranslationStyleItem] = [
    .init(id: "formal", title: "Formal", fileId: 0, reference: .standard("formal")),
    .init(id: "short", title: "Short", fileId: 0, reference: .standard("short")),
    .init(id: "savage", title: "Savage", fileId: 0, reference: .standard("savage")),
    .init(id: "biblical", title: "Biblical", fileId: 0, reference: .standard("biblical")),
    .init(id: "posh", title: "Posh", fileId: 0, reference: .standard("posh"))
]

private func translationStyles(from context: any AccountContextProtocol) -> [TranslationStyleItem] {
    if let data = context.appConfiguration.data, let styles = data["ai_compose_styles"] as? [[Any]] {
        let items = styles.compactMap { entry -> TranslationStyleItem? in
            guard entry.count >= 3,
                  let id = entry[0] as? String,
                  let emojiIdStr = entry[1] as? String,
                  let fileId = Int64(emojiIdStr),
                  let title = entry[2] as? String else {
                return nil
            }
            return TranslationStyleItem(id: id, title: title, fileId: fileId, reference: .standard(id))
        }
        if !items.isEmpty {
            return items
        }
    }
    return defaultTranslationStyles
}

private final class Arguments {
    let context: any AccountContextProtocol
    let revealFrom:()->Void
    let revealTo:()->Void
    let updateFrom:(String?)->Void
    let updateTo:(String)->Void
    let updateTone:(String)->Void
    let copyTranslation:()->Void
    let translateEntireChat:(()->Void)?
    let updateMode:(TranslateTabMode)->Void
    let updateStyle:(String)->Void
    let toggleEmojify:()->Void
    let showStyleTooltip:()->Void
    let createNewStyle:()->Void
    let styleMenu:(TranslationStyleItem)->ContextMenu?
    let isInputMode: Bool
    let isRich: Bool
    let richPage: InstantPage?
    let updateCustomPrompt:(String)->Void

    init(context: any AccountContextProtocol, revealFrom:@escaping()->Void, revealTo:@escaping()->Void, updateFrom:@escaping(String?)->Void, updateTo:@escaping(String)->Void, updateTone:@escaping(String)->Void, copyTranslation:@escaping()->Void, translateEntireChat:(()->Void)? = nil, updateMode:@escaping(TranslateTabMode)->Void = { _ in }, updateStyle:@escaping(String)->Void = { _ in }, toggleEmojify:@escaping()->Void = { }, showStyleTooltip:@escaping()->Void = { }, createNewStyle:@escaping()->Void = { }, styleMenu:@escaping(TranslationStyleItem)->ContextMenu? = { _ in nil }, isInputMode: Bool = false, isRich: Bool = false, richPage: InstantPage? = nil, updateCustomPrompt:@escaping(String)->Void = { _ in }) {
        self.context = context
        self.revealFrom = revealFrom
        self.revealTo = revealTo
        self.updateFrom = updateFrom
        self.updateTo = updateTo
        self.updateTone = updateTone
        self.copyTranslation = copyTranslation
        self.translateEntireChat = translateEntireChat
        self.updateMode = updateMode
        self.updateStyle = updateStyle
        self.toggleEmojify = toggleEmojify
        self.showStyleTooltip = showStyleTooltip
        self.createNewStyle = createNewStyle
        self.styleMenu = styleMenu
        self.isInputMode = isInputMode
        self.isRich = isRich
        self.richPage = richPage
        self.updateCustomPrompt = updateCustomPrompt
    }
}

private struct ComposeKey: Hashable {
    let mode: TranslateTabMode
    let toLang: String
    let styleId: String
    let emojify: Bool
    let toneId: String
    var prompt: String = ""
}

private struct ComposeResult: Equatable {
    let text: String
    let entities: [MessageTextEntity]
}

private struct State : Equatable {
    let text: String
    let textEntities: [MessageTextEntity]

    var from: String?
    var to: String
    var tone: TranslationTone = .neutral
    var toneId: String = "neutral"
    var styleId: String = "formal"
    var tones: [TranslationStyleItem] = []
    var styles: [TranslationStyleItem] = []
    var authorNames: [EnginePeer.Id: String] = [:]
    var translated: String?
    var translatedEntities: [MessageTextEntity] = []
    var fromIsRevealed: Bool
    var toIsRevealed: Bool
    var mode: TranslateTabMode = .translate
    var emojify: Bool = false
    var limitExceeded: Bool = false
    var isTranslating: Bool = false
    var cache: [ComposeKey: ComposeResult] = [:]
    var customPrompt: String = ""
    var translatedRich: InstantPage? = nil
    var richCache: [ComposeKey: InstantPage] = [:]

    var cacheKey: ComposeKey {
        return ComposeKey(mode: mode, toLang: to, styleId: styleId, emojify: emojify, toneId: toneId, prompt: styleId == "prompt" ? customPrompt : "")
    }

    func translatedAttr(context: any AccountContextProtocol) -> NSAttributedString? {
        if let translated {
            return ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: translatedEntities)], for: translated, message: nil, context: context, fontSize: 13, openInfo: { _, _, _, _ in }, isDark: false, bubbled: false)
        }
        return nil
    }
}

private final class TranslateTabRowItem : GeneralRowItem {
    fileprivate let mode: TranslateTabMode
    fileprivate let updateMode: (TranslateTabMode)->Void
    init(_ initialSize: NSSize, stableId: AnyHashable, mode: TranslateTabMode, updateMode: @escaping(TranslateTabMode)->Void) {
        self.mode = mode
        self.updateMode = updateMode
        super.init(initialSize, stableId: stableId)
    }
    override var accessibilityLabel: String? {
        switch mode {
        case .translate:
            return strings().translateTabTranslate
        case .style:
            return strings().translateTabStyle
        case .fix:
            return strings().translateTabFix
        }
    }
    override func viewClass() -> AnyClass {
        return TranslateTabRowView.self
    }
    override var height: CGFloat {
        return 56
    }
}

private final class TranslateTabItemView : Control {
    private let imageView = ImageView()
    private let activeTextView = TextView()
    private let inactiveTextView = TextView()

    init(title: String, icon: NSImage, select: @escaping()->Void) {
        self.title = title
        self.icon = icon
        super.init(frame: NSZeroRect)
        addSubview(imageView)
        addSubview(activeTextView)
        addSubview(inactiveTextView)
        activeTextView.userInteractionEnabled = false
        activeTextView.isSelectable = false
        inactiveTextView.userInteractionEnabled = false
        inactiveTextView.isSelectable = false
        imageView.isAccessibilityDecorative = true
        activeTextView.isAccessibilityDecorative = true
        inactiveTextView.isAccessibilityDecorative = true
        setAccessibilityLabel(title)
        scaleOnClick = true
        set(handler: { _ in select() }, for: .SingleClick)
    }

    let title: String
    let icon: NSImage

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    func set(selected: Bool, animated: Bool) {
        let activeColor = theme.colors.text
        let inactiveColor = theme.colors.grayIcon

        imageView.image = icon.precomposed(selected ? activeColor : inactiveColor)
        imageView.sizeToFit()

        let activeLayout = TextViewLayout(.initialize(string: title, color: activeColor, font: .medium(.small)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        activeLayout.measure(width: .greatestFiniteMagnitude)
        activeTextView.update(activeLayout)

        let inactiveLayout = TextViewLayout(.initialize(string: title, color: theme.colors.grayText, font: .normal(.small)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        inactiveLayout.measure(width: .greatestFiniteMagnitude)
        inactiveTextView.update(inactiveLayout)

        activeTextView.change(opacity: selected ? 1 : 0, animated: animated)
        inactiveTextView.change(opacity: !selected ? 1 : 0, animated: animated)

        isSelected = selected
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let totalH = imageView.frame.height + 4 + (activeTextView.frame.height)
        let topY = (frame.height - totalH) / 2
        imageView.centerX(y: topY)
        activeTextView.centerX(y: topY + imageView.frame.height + 4)
        inactiveTextView.centerX(y: topY + imageView.frame.height + 4)
    }
}

private final class TranslateTabRowView : GeneralRowView {
    private let container = View()
    private let pill = View()
    private var tabViews: [TranslateTabItemView] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.addSubview(pill)
        addSubview(container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let allModes: [TranslateTabMode] = [.translate, .style, .fix]

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? TranslateTabRowItem else { return }

        container.backgroundColor = theme.colors.background
        pill.backgroundColor = theme.colors.listBackground

        let allModes = TranslateTabRowView.allModes
        if tabViews.isEmpty {
            for (i, m) in allModes.enumerated() {
                let title: String
                let iconName: String
                switch m {
                case .translate:
                    title = strings().translateTabTranslate
                    iconName = "Icon_InputTranslate_Translate"
                case .style:
                    title = strings().translateTabStyle
                    iconName = "Icon_InputTranslate_Style"
                case .fix:
                    title = strings().translateTabFix
                    iconName = "Icon_InputTranslate_Fix"
                }
                let icon = NSImage(named: iconName)!
                let tabView = TranslateTabItemView(title: title, icon: icon, select: { [weak self] in
                    if let self, let item = self.item as? TranslateTabRowItem {
                        item.updateMode(allModes[i])
                    }
                })
                tabViews.append(tabView)
                container.addSubview(tabView)
            }
        }

        let selectedIndex = allModes.firstIndex(of: item.mode) ?? 0
        for (i, tabView) in tabViews.enumerated() {
            tabView.set(selected: i == selectedIndex, animated: animated)
        }

        if animated {
            let itemWidth = floor(container.frame.width / CGFloat(tabViews.count))
            let pillX = CGFloat(selectedIndex) * itemWidth + 3
            let pillW = itemWidth - 6
            let pillH = container.frame.height - 6
            pill.change(pos: NSMakePoint(pillX, 3), animated: true)
            pill.change(size: NSMakeSize(pillW, pillH), animated: false)
            pill.layer?.cornerRadius = pillH / 2
        } else {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 20
        let containerH = frame.height
        container.frame = NSMakeRect(inset, 0, frame.width - inset * 2, containerH)
        container.layer?.cornerRadius = containerH / 2

        guard !tabViews.isEmpty else { return }

        let itemWidth = floor(container.frame.width / CGFloat(tabViews.count))
        var x: CGFloat = 0
        for tabView in tabViews {
            tabView.frame = NSMakeRect(x, 0, itemWidth, container.frame.height)
            if tabView.isSelected {
                let pillW = itemWidth - 6
                let pillH = container.frame.height - 6
                pill.frame = NSMakeRect(x + 3, 3, pillW, pillH)
                pill.layer?.cornerRadius = pillH / 2
            }
            x += itemWidth
        }
    }

    override var backdorColor: NSColor {
        return .clear
    }
}

private final class StyleEmojiRowItem : GeneralRowItem {
    fileprivate let styles: [TranslationStyleItem]
    fileprivate let selectedId: String
    fileprivate let updateStyle: (String)->Void
    fileprivate let createNewStyle: ()->Void
    fileprivate let styleMenu: (TranslationStyleItem)->ContextMenu?
    fileprivate let context: any AccountContextProtocol
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, styles: [TranslationStyleItem], selectedId: String, updateStyle: @escaping(String)->Void, createNewStyle: @escaping()->Void, styleMenu: @escaping(TranslationStyleItem)->ContextMenu? = { _ in nil }, viewType: GeneralViewType) {
        self.context = context
        self.styles = styles
        self.selectedId = selectedId
        self.updateStyle = updateStyle
        self.createNewStyle = createNewStyle
        self.styleMenu = styleMenu
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    override var accessibilityLabel: String? {
        return styles.first(where: { $0.id == selectedId })?.title ?? strings().translateTabStyle
    }
    override func viewClass() -> AnyClass {
        return StyleEmojiRowView.self
    }
    override var height: CGFloat {
        return 60
    }
}

private final class StyleEmojiItemView : Control {
    private let emojiView: InteractiveTextView
    private var iconView: ImageView?
    private let activeLabel = TextView()
    private let inactiveLabel = TextView()
    private let fileId: Int64
    private let title: String
    private let context: any AccountContextProtocol

    init(fileId: Int64, title: String, context: any AccountContextProtocol, select: @escaping()->Void) {
        self.fileId = fileId
        self.title = title
        self.context = context
        self.emojiView = InteractiveTextView(frame: NSZeroRect)
        super.init(frame: NSZeroRect)
        addSubview(emojiView)
        addSubview(activeLabel)
        addSubview(inactiveLabel)
        emojiView.userInteractionEnabled = false
        emojiView.textView.isSelectable = false
        activeLabel.userInteractionEnabled = false
        activeLabel.isSelectable = false
        inactiveLabel.userInteractionEnabled = false
        inactiveLabel.isSelectable = false
        emojiView.isAccessibilityDecorative = true
        emojiView.textView.isAccessibilityDecorative = true
        activeLabel.isAccessibilityDecorative = true
        inactiveLabel.isAccessibilityDecorative = true
        setAccessibilityLabel(title)
        scaleOnClick = true
        set(handler: { _ in select() }, for: .SingleClick)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private var wasSelected: Bool = false

    func set(selected: Bool, animated: Bool) {
        let justSelected = selected && !wasSelected
        wasSelected = selected

        if fileId == 0 {
            // A special chip without a custom-emoji glyph (the single-use "Prompt" style) draws a static icon.
            emojiView.isHidden = true
            let iconView: ImageView
            if let view = self.iconView {
                iconView = view
            } else {
                iconView = ImageView()
                iconView.isAccessibilityDecorative = true
                self.iconView = iconView
                addSubview(iconView)
            }
            iconView.image = NSImage(named: "Icon_AiEditor_Prompt")?.precomposed(selected ? theme.colors.accent : theme.colors.grayIcon)
            iconView.sizeToFit()
        } else {
            let emojiText = "⭐️"
            let entities: [MessageTextEntity] = [MessageTextEntity(range: 0 ..< (emojiText as NSString).length, type: .CustomEmoji(stickerPack: nil, fileId: fileId))]

            let attr = NSMutableAttributedString(attributedString: .initialize(string: emojiText, font: .normal(24)))
            InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: entities, isPremium: context.isPremium, playPolicy: .framesCount(1))
            let emojiLayout = TextViewLayout(attr, maximumNumberOfLines: 1, alwaysStaticItems: true)
            emojiLayout.measure(width: .greatestFiniteMagnitude)
            emojiView.set(text: emojiLayout, context: context)

            if justSelected {
                emojiView.textView.embeddedContainer.sublayers?.forEach { sublayer in
                    if let stickerLayer = sublayer as? InlineStickerItemLayer {
                        stickerLayer.playAgain()
                    }
                }
            }
        }

        let activeLayout = TextViewLayout(.initialize(string: title, color: theme.colors.text, font: .medium(.small)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        activeLayout.measure(width: .greatestFiniteMagnitude)
        activeLabel.update(activeLayout)

        let inactiveLayout = TextViewLayout(.initialize(string: title, color: theme.colors.grayText, font: .normal(.small)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        inactiveLayout.measure(width: .greatestFiniteMagnitude)
        inactiveLabel.update(inactiveLayout)

        activeLabel.change(opacity: selected ? 1 : 0, animated: animated)
        inactiveLabel.change(opacity: !selected ? 1 : 0, animated: animated)

        isSelected = selected
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let glyphHeight = iconView?.frame.height ?? emojiView.frame.height
        let totalH = glyphHeight + 4 + activeLabel.frame.height
        let topY = (frame.height - totalH) / 2
        if let iconView {
            iconView.centerX(y: topY)
        } else {
            emojiView.centerX(y: topY)
        }
        activeLabel.centerX(y: topY + glyphHeight + 4)
        inactiveLabel.centerX(y: topY + glyphHeight + 4)
    }
}

private final class StyleCreateItemView : Control {
    private let imageView = ImageView()
    private let label = TextView()

    init(select: @escaping()->Void) {
        super.init(frame: NSZeroRect)
        addSubview(imageView)
        addSubview(label)
        label.userInteractionEnabled = false
        label.isSelectable = false
        imageView.isAccessibilityDecorative = true
        label.isAccessibilityDecorative = true
        setAccessibilityLabel(strings().translateModalCreate)
        scaleOnClick = true
        set(handler: { _ in select() }, for: .SingleClick)
        updateTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private func updateTheme() {
        imageView.image = NSImage(named: "Icon_NewStyle_Create")?.precomposed(theme.colors.grayText)
        imageView.sizeToFit()

        let layout = TextViewLayout(.initialize(string: strings().translateModalCreate, color: theme.colors.grayText, font: .normal(.small)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        layout.measure(width: .greatestFiniteMagnitude)
        label.update(layout)
    }

    func updateAppearance() {
        updateTheme()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let totalH = imageView.frame.height + 4 + label.frame.height
        let topY = (frame.height - totalH) / 2
        imageView.centerX(y: topY)
        label.centerX(y: topY + imageView.frame.height + 4)
    }
}

private final class StyleEmojiRowView : GeneralContainableRowView {
    private let pill = View()
    private let scrollView = ScrollView()
    private let documentView = View()
    private let separatorView = View()
    fileprivate var itemViews: [StyleEmojiItemView] = []
    private var createView: StyleCreateItemView?

    private static let minItemWidth: CGFloat = 60

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        containerView.addSubview(scrollView)
        containerView.addSubview(separatorView)
        documentView.addSubview(pill)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? StyleEmojiRowItem else { return }

        pill.backgroundColor = theme.colors.background

        if itemViews.count != item.styles.count {
            for iv in itemViews { iv.removeFromSuperview() }
            itemViews.removeAll()
            for style in item.styles {
                let itemView = StyleEmojiItemView(fileId: style.fileId, title: style.title, context: item.context, select: { [weak self] in
                    if let self, let item = self.item as? StyleEmojiRowItem {
                        item.updateStyle(style.id)
                    }
                })
                itemView.contextMenu = { [weak self] in
                    if let self, let item = self.item as? StyleEmojiRowItem {
                        return item.styleMenu(style)
                    }
                    return nil
                }
                itemViews.append(itemView)
                documentView.addSubview(itemView)
            }
        }

        if createView == nil {
            let createView = StyleCreateItemView(select: { [weak self] in
                if let item = self?.item as? StyleEmojiRowItem {
                    item.createNewStyle()
                }
            })
            self.createView = createView
            documentView.addSubview(createView)
        } else {
            createView?.updateAppearance()
        }

        let selectedIndex = item.styles.firstIndex(where: { $0.id == item.selectedId })
        for (i, iv) in itemViews.enumerated() {
            iv.set(selected: i == selectedIndex, animated: animated)
        }

        updateItemLayout(selectedIndex: selectedIndex, animated: animated)
    }

    private func updateItemLayout(selectedIndex: Int?, animated: Bool) {
        guard !itemViews.isEmpty else { return }

        let totalSlots = itemViews.count + (createView != nil ? 1 : 0)
        let visibleW = containerView.frame.width
        let fittedItemW = floor(visibleW / CGFloat(totalSlots))
        let itemW = max(fittedItemW, StyleEmojiRowView.minItemWidth)
        let totalW = itemW * CGFloat(totalSlots)
        let h = containerView.frame.height

        scrollView.frame = containerView.bounds
        documentView.frame = NSMakeRect(0, 0, totalW, h)

        var x: CGFloat = 0
        for iv in itemViews {
            iv.frame = NSMakeRect(x, 0, itemW, h)
            x += itemW
        }
        if let createView {
            createView.frame = NSMakeRect(x, 0, itemW, h)
        }

        if let selectedIndex = selectedIndex {
            pill.isHidden = false
            let pillW = itemW - 6
            let pillH = h - 6
            let pillX = CGFloat(selectedIndex) * itemW + 3
            if animated {
                pill.change(pos: NSMakePoint(pillX, 3), animated: true)
                pill.change(size: NSMakeSize(pillW, pillH), animated: false)
            } else {
                pill.frame = NSMakeRect(pillX, 3, pillW, pillH)
            }
            pill.layer?.cornerRadius = 15
        } else {
            pill.isHidden = true
        }

        if let selectedIndex = selectedIndex, totalW > visibleW {
            let selectedCenter = CGFloat(selectedIndex) * itemW + itemW / 2
            let scrollX = max(0, min(selectedCenter - visibleW / 2, totalW - visibleW))
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    scrollView.contentView.animator().setBoundsOrigin(NSMakePoint(scrollX, 0))
                }
            } else {
                scrollView.contentView.scroll(to: NSMakePoint(scrollX, 0))
            }
        }
    }

    override func layout() {
        super.layout()
        if let item = self.item as? StyleEmojiRowItem {
            let selectedIndex = item.styles.firstIndex(where: { $0.id == item.selectedId })
            updateItemLayout(selectedIndex: selectedIndex, animated: false)
        }
        if let item = self.item as? StyleEmojiRowItem {
            switch item.viewType {
            case let .modern(position, insets):
                let showSeparator = position == .first || position == .inner
                separatorView.isHidden = !showSeparator
                separatorView.frame = NSMakeRect(insets.left, containerView.frame.height - .borderSize, containerView.frame.width - insets.left - insets.right, .borderSize)
                separatorView.background = theme.colors.border
            default:
                separatorView.isHidden = true
            }
        }
    }
}

private let langToCountry: [String: String] = [
    "af": "ZA", "sq": "AL", "am": "ET", "ar": "SA", "hy": "AM", "az": "AZ",
    "eu": "ES", "be": "BY", "bn": "BD", "bs": "BA", "bg": "BG", "ca": "ES",
    "zh": "CN", "hr": "HR", "cs": "CZ", "da": "DK", "nl": "NL", "en": "GB",
    "eo": "EU", "et": "EE", "fi": "FI", "fr": "FR", "gl": "ES", "ka": "GE",
    "de": "DE", "el": "GR", "gu": "IN", "ht": "HT", "ha": "NG", "he": "IL",
    "iw": "IL", "hi": "IN", "hu": "HU", "is": "IS", "ig": "NG", "id": "ID",
    "ga": "IE", "it": "IT", "ja": "JP", "jv": "ID", "kn": "IN", "kk": "KZ",
    "km": "KH", "rw": "RW", "ko": "KR", "ku": "IQ", "ky": "KG", "lo": "LA",
    "la": "VA", "lv": "LV", "lt": "LT", "lb": "LU", "mk": "MK", "mg": "MG",
    "ms": "MY", "ml": "IN", "mt": "MT", "mi": "NZ", "mr": "IN", "mn": "MN",
    "my": "MM", "ne": "NP", "no": "NO", "nb": "NO", "ny": "MW", "or": "IN",
    "ps": "AF", "fa": "IR", "pl": "PL", "pt": "PT", "pa": "IN", "ro": "RO",
    "ru": "RU", "sm": "WS", "gd": "GB", "sr": "RS", "sn": "ZW", "sd": "PK",
    "si": "LK", "sk": "SK", "sl": "SI", "so": "SO", "st": "ZA", "es": "ES",
    "su": "ID", "sw": "KE", "sv": "SE", "tg": "TJ", "ta": "IN", "tt": "RU",
    "te": "IN", "th": "TH", "tr": "TR", "tk": "TM", "uk": "UA", "ur": "PK",
    "ug": "CN", "uz": "UZ", "vi": "VN", "cy": "GB", "xh": "ZA", "yi": "IL",
    "yo": "NG", "zu": "ZA"
]

private func flagEmoji(for langCode: String) -> String {
    guard let country = langToCountry[langCode] else { return "🌐" }
    let base: UInt32 = 127397
    let flag = country.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }.map { String($0) }.joined()
    return flag.isEmpty ? "🌐" : flag
}

private func languageMenuItem(for language: Translate.Value, selected: Bool, handler: @escaping () -> Void) -> ContextMenuItem {
    let flag = flagEmoji(for: language.code[0])
    let title = "\(flag) \(language.language)"
    return ContextMenuItem(title, handler: handler, state: selected ? .on : nil)
}

private func generateX50Badge(textColor: NSColor) -> CGImage {
    let text = "X50"
    let font = NSFont.bold(.small)
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
    let line = CTLineCreateWithAttributedString(attr)
    let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let badgeSize = NSMakeSize(ceil(textBounds.width) + 10, ceil(textBounds.height) + 6)
    return generateImage(badgeSize, contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.setFillColor(NSColor.white.cgColor)
        let path = CGPath(roundedRect: size.bounds, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let textX = (size.width - textBounds.width) / 2 - textBounds.origin.x
        let textY = (size.height - textBounds.height) / 2 - textBounds.origin.y
        ctx.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, ctx)
    })!
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    if arguments.isInputMode {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("tab_selector"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            TranslateTabRowItem(initialSize, stableId: stableId, mode: state.mode, updateMode: arguments.updateMode)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    if true {
        let showOriginal = !arguments.isInputMode || state.mode == .translate || state.mode == .fix
        let isStyleMode = arguments.isInputMode && state.mode == .style
        let isTranslateMode = !arguments.isInputMode || state.mode == .translate

        if showOriginal {
            let fromName: String
            if let fr = state.from, let value = Translate.find(fr) {
                fromName = _NSLocalizedString(value.localizationKey)
            } else {
                fromName = strings().translateLanguageAuto
            }

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("original"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return TranslateTableRowItem(initialSize, stableId: stableId, context: arguments.context, text: state.text, entities: state.textEntities, revealed: state.fromIsRevealed, headerData: TranslateHeaderData(
                    label: strings().translateFrom,
                    language: fromName,
                    languageMenu: {
                        var items: [ContextMenuItem] = []
                        if let fromCode = state.from, let selected = Translate.codes.first(where: { $0.code.contains(fromCode) }) {
                            items.append(languageMenuItem(for: selected, selected: true, handler: {
                                arguments.updateFrom(selected.code[0])
                            }))
                        }
                        for language in Translate.codes {
                            items.append(languageMenuItem(for: language, selected: language.code.contains(state.from ?? ""), handler: {
                                arguments.updateFrom(language.code[0])
                            }))
                        }
                        return items
                    },
                    toneLabel: nil,
                    toneName: nil,
                    toneMenu: nil
                ), richPage: arguments.richPage, viewType: .firstItem, reveal: arguments.revealFrom)
            }))
            index += 1
        }

        let toName: String
        if let value = Translate.find(state.to) {
            toName = _NSLocalizedString(value.localizationKey)
        } else {
            toName = strings().translateLanguageAuto
        }

        let tones = state.tones
        let toneName = tones.first(where: { $0.id == state.toneId })?.title ?? tones.first?.title ?? "Neutral"

        var activeStyles: [TranslationStyleItem] = !state.styles.isEmpty ? state.styles : translationStyles(from: arguments.context)
        if arguments.isRich {
            // Single-use custom prompt (rich-only per the API): injected as `inputAiComposeToneSingleUse`,
            // never saved as a tone.
            activeStyles.insert(TranslationStyleItem(id: "prompt", title: strings().translateModalPromptStyle, fileId: 0), at: 0)
        }

        if isStyleMode {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("style_selector"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                StyleEmojiRowItem(initialSize, stableId: stableId, context: arguments.context, styles: activeStyles, selectedId: state.styleId, updateStyle: arguments.updateStyle, createNewStyle: arguments.createNewStyle, styleMenu: arguments.styleMenu, viewType: .firstItem)
            }))
            index += 1

            if state.styleId == "prompt" {
                entries.append(.input(sectionId: sectionId, index: index, value: .string(state.customPrompt), error: nil, identifier: .init("custom_prompt"), mode: .plain, data: .init(viewType: .innerItem), placeholder: nil, inputPlaceholder: strings().translateModalPromptPlaceholder, filter: { $0 }, limit: 1024))
                index += 1
            }
        }

        var translatedHeader: TranslateHeaderData
        if state.limitExceeded {
            translatedHeader = TranslateHeaderData(
                label: strings().translateOriginal,
                language: nil,
                languageMenu: nil,
                toneLabel: nil,
                toneName: nil,
                toneMenu: nil
            )
        } else if isTranslateMode {
            let isDefaultTone = state.toneId == "neutral"
            let languageWithTone: String
            if !isDefaultTone {
                languageWithTone = "\(toName) (\(toneName))"
            } else {
                languageWithTone = toName
            }
            translatedHeader = TranslateHeaderData(
                label: strings().translateTo,
                language: languageWithTone,
                languageMenu: {
                    var items: [ContextMenuItem] = []

                    let toneItem = ContextMenuItem(strings().translateTone, handler: {}, itemImage: MenuAnimation.menu_tune_fork.value)
                    let toneSubmenu = ContextMenu()
                    toneSubmenu.addItem(ContextMenuItem(strings().chatHeaderToneNeutral, handler: {
                        arguments.updateTone("neutral")
                    }, state: isDefaultTone ? .on : nil))
                    for tone in tones where tone.id != "neutral" {
                        toneSubmenu.addItem(ContextMenuItem(tone.title, handler: {
                            arguments.updateTone(tone.id)
                        }, state: state.toneId == tone.id ? .on : nil))
                    }
                    toneItem.submenu = toneSubmenu
                    items.append(toneItem)
                    items.append(ContextSeparatorItem())

                    if let selected = Translate.codes.first(where: { $0.code.contains(state.to) }) {
                        items.append(languageMenuItem(for: selected, selected: true, handler: {
                            arguments.updateTo(selected.code[0])
                        }))
                    }
                    for language in Translate.codes {
                        items.append(languageMenuItem(for: language, selected: language.code.contains(state.to), handler: {
                            arguments.updateTo(language.code[0])
                        }))
                    }
                    return items
                },
                toneLabel: nil,
                toneName: nil,
                toneMenu: nil
            )
        } else {
            let resultLabel: String
            if state.mode == .style && state.styleId.isEmpty && !state.emojify {
                resultLabel = strings().translateOriginal
            } else {
                resultLabel = strings().translateResult
            }
            translatedHeader = TranslateHeaderData(
                label: resultLabel,
                language: nil,
                languageMenu: nil,
                toneLabel: nil,
                toneName: nil,
                toneMenu: nil
            )
        }
        if arguments.isInputMode && state.mode != .fix && !state.limitExceeded {
            let emojifyDisabled = isStyleMode && state.styleId.isEmpty
            translatedHeader.emojifyLabel = strings().translateEmojify
            translatedHeader.emojifyEnabled = emojifyDisabled ? false : state.emojify
            translatedHeader.emojifyDisabled = emojifyDisabled
            translatedHeader.toggleEmojify = {
                if emojifyDisabled {
                    arguments.showStyleTooltip()
                } else {
                    arguments.toggleEmojify()
                }
            }
        }

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("translated"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            let translatedViewType: GeneralViewType = (showOriginal || isStyleMode) ? .lastItem : .singleItem
            let showPreviousWhileLoading = state.isTranslating && state.translated != nil
            return TranslateTableRowItem(initialSize, stableId: stableId, context: arguments.context, text: state.translated ?? "", entities: state.translatedEntities, revealed: state.toIsRevealed, headerData: translatedHeader, isLoading: state.translated == nil || state.isTranslating, originalText: showPreviousWhileLoading ? state.translated : state.text, originalEntities: showPreviousWhileLoading ? state.translatedEntities : state.textEntities, richPage: state.translatedRich, viewType: translatedViewType, copyTranslation: {
                arguments.copyTranslation()
            }, reveal: arguments.revealTo)
        }))
        index += 1

        if isStyleMode, let selected = activeStyles.first(where: { $0.id == state.styleId }), let authorId = selected.authorId, let addressName = state.authorNames[authorId], !addressName.isEmpty {
            let text = strings().translateModalStyleByAuthor(addressName)
            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { link in
                LinkHooks.shared.openExternalLink(link, false)
            }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    if state.translated != nil, arguments.translateEntireChat != nil {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("copy_translation"), data: .init(name: strings().translateCopyToClipboard, color: theme.colors.accent, viewType: .firstItem, action: {
            arguments.copyTranslation()
        })))
        index += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("translate_chat"), data: .init(name: strings().translateTranslateEntireChat, color: theme.colors.accent, viewType: .lastItem, action: {
            arguments.translateEntireChat?()
        })))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    return entries
}




func translateBlocks(context: any AccountContextProtocol, from: String?, to: String, blocks: [(String, [MessageTextEntity])], configState: AppConfigTranslateState, tone: TranslationTone = .neutral) -> Signal<(detect: String?, result: String, entities: [MessageTextEntity]), Translate.Error> {
    var signals:[Signal<(detect: String?, result: String, entities: [MessageTextEntity]), Translate.Error>] = []
    for block in blocks {
        switch configState {
        case .enabled:
            signals.append(context.engine.messages.translate(text: block.0, toLang: to, entities: block.1, tone: tone) |> `catch` { error in
                switch error {
                case .tryAlternative:
                    return .single(nil)
                default:
                    #if DEBUG
                    return .single(nil)
                    #endif
                    return .fail(.generic)
                }
            } |> mapToSignal { value in
                if let value = value {
                    return .single((detect: nil, result: value.0, entities: value.1))
                } else {
                    return Translate.translateText(text: block.0, from: from, to: to) |> map {
                        (detect: $0.detect, result: $0.result, entities: [])
                    }
                }
            })
        case .alternative:
            signals.append(Translate.translateText(text: block.0, from: from, to: to) |> map {
                (detect: $0.detect, result: $0.result, entities: [])
            })
        case .disabled, .system:
            continue
        }
        
    }
    var signal: Signal<(detect: String?, result: String, entities: [MessageTextEntity]), Translate.Error> = .single((detect: nil, result: "", entities: []))
    for (index, blockSignal) in signals.enumerated() {
        let next = index == 0 ? blockSignal : (blockSignal |> delay(2.0, queue: .mainQueue()))
        signal = signal |> mapToSignal { result in
            return next |> map { value in
                var entities: [MessageTextEntity] = []
                for entity in value.entities {
                    var current = entity
                    current.range = entity.range.lowerBound + result.result.length ..< entity.range.upperBound + result.result.length
                    entities.append(current)
                }
                return (detect: value.detect, result.result + value.result, entities: result.entities + entities)
            }
        }
    }
    
    return signal
}
public func TranslateModalController(context: any AccountContextProtocol, from: String?, toLang: String, text: String, entities: [MessageTextEntity] = [], canBreak: Bool = true, configState: AppConfigTranslateState = .enabled, messageId: MessageId? = nil, isRichMessage: Bool = false, richMessagePage: InstantPage? = nil, onUse: ((NSAttributedString)->Void)? = nil, onSend: ((NSAttributedString)->Void)? = nil, richBlocks: [Block]? = nil, onUseRich: (([Block])->Void)? = nil, dismissOnly: Bool = false, onToneChanged: ((TranslationTone)->Void)? = nil, translateEntireChat: (()->Void)? = nil) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let disposable = MetaDisposable()
    actionsDisposable.add(disposable)
    let promptRequestDisposable = MetaDisposable()
    actionsDisposable.add(promptRequestDisposable)

    // Rich content: from an editor selection (`richBlocks`, the AI-editor input mode) or a rich message
    // (`richMessagePage`, the translate flow). Requests go through the rich methods, the FROM/RESULT rows
    // render via the InstantPage V2 renderer, and Apply hands rich results back via `onUseRich`.
    let richPage: InstantPage? = richMessagePage ?? richBlocks.flatMap { richTextInstantPage(from: outgoingBlocks(fromSelection: $0), media: [:]) }

    let isInputMode = onUse != nil || onUseRich != nil

    let configTones = translationStyles(from: context)
    var initialState = State(text: text, textEntities: entities, from: from, to: Translate.normalizeLanguageCode(toLang), fromIsRevealed: !canBreak, toIsRevealed: true)
    initialState.tones = configTones
    initialState.mode = isInputMode ? .style : .translate
    initialState.styleId = ""
    if isInputMode {
        initialState.mode = .style
    }
    
    var close:(()->Void)? = nil
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let reloadStyles: ValuePromise<Int32> = ValuePromise(0, ignoreRepeated: false)
    let reloadCounter: Atomic<Int32> = Atomic(value: 0)
    let pinnedNewStyleIds: Atomic<[Int64]> = Atomic(value: [])
    let triggerReloadStyles: () -> Void = {
        reloadStyles.set(reloadCounter.modify { $0 + 1 })
    }
    let cloudStylesSignal: Signal<[TranslationStyleItem], NoError> = reloadStyles.get()
    |> mapToSignal { _ in
        return context.engine.messages.composeAIMessageStyles()
    }
    |> map { cloudStyles in
        return cloudStyles.map { makeStyleItem(from: $0) }
    }

    actionsDisposable.add((cloudStylesSignal |> deliverOnMainQueue).start(next: { styles in
        var reordered = styles
        let pinned = pinnedNewStyleIds.with { $0 }
        if !pinned.isEmpty {
            var remaining = reordered
            var front: [TranslationStyleItem] = []
            for id in pinned {
                let target = "custom_\(id)"
                if let idx = remaining.firstIndex(where: { $0.id == target }) {
                    front.append(remaining.remove(at: idx))
                }
            }
            reordered = front + remaining
        }
        let authorIds = Array(Set(reordered.compactMap { $0.authorId }))
        updateState { current in
            var current = current
            current.styles = reordered
            return current
        }
        if !authorIds.isEmpty {
            let authorsSignal = context.engine.data.get(EngineDataMap(authorIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
            actionsDisposable.add((authorsSignal |> deliverOnMainQueue).start(next: { peers in
                updateState { current in
                    var current = current
                    for (id, peer) in peers {
                        if let peer = peer, let addressName = peer.addressName, !addressName.isEmpty {
                            current.authorNames[id] = addressName
                        }
                    }
                    return current
                }
            }))
        }
    }))

    let input = ChatTextInputState(inputText: text, selectionRange: 0..<0, attributes: chatTextAttributes(from: TextEntitiesMessageAttribute(entities: entities), associatedMedia: [:]))

    var inset: Int = 0
    let blocks:[(String, [MessageTextEntity])] = cut_long_message(text, 1024).compactMap { value in
        let text = input.subInputState(from: NSMakeRange(inset, value.length))
        inset += value.length
        return (value, text.messageTextEntities())
    }


    let request:()->Void = {
        let state = stateValue.with { $0 }

        if state.limitExceeded {
            return
        }

        let promptIsEmpty = state.styleId == "prompt" && state.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isInputMode && state.mode == .style && (state.styleId.isEmpty || promptIsEmpty) && !state.emojify {
            updateState { current in
                var current = current
                current.translated = current.text
                current.translatedEntities = current.textEntities
                current.translatedRich = nil
                current.isTranslating = false
                return current
            }
            return
        }

        let key = state.cacheKey
        if let cached = state.cache[key] {
            updateState { current in
                var current = current
                current.translated = cached.text
                current.translatedEntities = cached.entities
                current.translatedRich = current.richCache[key]
                current.isTranslating = false
                return current
            }
            return
        }
        updateState { current in
            var current = current
            current.isTranslating = true
            return current
        }

        if !isInputMode, isRichMessage, let messageId {
            // Rich messages translate through messages.translateRichMessage (layer 228); the result is an
            // InstantPage — rendered in the RESULT row via IV2, and stored on the message by the core so
            // the chat's inline translation shows the same rich result.
            let richSignal = context.engine.messages.translateRichMessage(messageId: messageId, toLang: state.to, tone: state.tone)
            |> deliverOnMainQueue
            disposable.set((richSignal).start(next: { page in
                updateState { current in
                    var current = current
                    if let page {
                        let (previewText, previewEntities) = richTextPlainPreview(from: page)
                        current.translated = previewText
                        current.translatedEntities = previewEntities
                        current.translatedRich = page
                        current.cache[key] = ComposeResult(text: previewText, entities: previewEntities)
                        current.richCache[key] = page
                    } else {
                        current.translated = current.text
                        current.translatedEntities = current.textEntities
                    }
                    current.isTranslating = false
                    return current
                }
            }, error: { error in
                updateState { current in
                    var current = current
                    current.isTranslating = false
                    if case .limitExceeded = error {
                        current.limitExceeded = true
                        current.translated = current.text
                        current.translatedEntities = current.textEntities
                    } else {
                        current.translated = strings().unknownError
                    }
                    return current
                }
            }))
            return
        }

        if isInputMode, let richPage {
            let proofread = state.mode == .fix
            let translateToLang: String? = state.mode == .translate ? state.to : nil
            var changeStyle: TelegramComposeAIMessageMode.CloudStyle.Reference? = nil
            var customPrompt: String? = nil
            if state.mode == .style {
                if state.styleId == "prompt" {
                    customPrompt = state.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if !state.styleId.isEmpty {
                    if let selected = state.styles.first(where: { $0.id == state.styleId })?.reference {
                        changeStyle = selected
                    } else {
                        changeStyle = .standard(state.styleId)
                    }
                }
            } else if state.mode == .translate && state.toneId != "neutral" {
                changeStyle = .standard(state.toneId)
            }
            let emojify = state.mode == .fix ? false : state.emojify

            let richSignal = context.engine.messages.composeRichMessageWithAI(instantPage: richPage, proofread: proofread, translateToLang: translateToLang, changeStyle: changeStyle, customPrompt: customPrompt, emojify: emojify)
            |> deliverOnMainQueue
            disposable.set((richSignal).start(next: { page in
                let (previewText, previewEntities) = richTextPlainPreview(from: page)
                updateState { current in
                    var current = current
                    current.translated = previewText.isEmpty ? current.text : previewText
                    current.translatedEntities = previewEntities
                    current.translatedRich = page
                    current.isTranslating = false
                    current.cache[key] = ComposeResult(text: current.translated ?? previewText, entities: current.translatedEntities)
                    current.richCache[key] = page
                    return current
                }
            }, error: { error in
                updateState { current in
                    var current = current
                    current.isTranslating = false
                    if case .limitExceeded = error {
                        current.limitExceeded = true
                        current.translated = current.text
                        current.translatedEntities = current.textEntities
                    } else {
                        current.translated = strings().unknownError
                    }
                    return current
                }
            }))
            return
        }

        let signal: Signal<(detect: String?, result: String, entities: [MessageTextEntity]), Translate.Error>
        if isInputMode {
            let proofread = state.mode == .fix
            let translateToLang: String? = state.mode == .translate ? state.to : nil
            let changeStyle: TelegramComposeAIMessageMode.CloudStyle.Reference?
            if state.mode == .style && !state.styleId.isEmpty {
                if let selected = state.styles.first(where: { $0.id == state.styleId })?.reference {
                    changeStyle = selected
                } else {
                    changeStyle = .standard(state.styleId)
                }
            } else if state.mode == .translate && state.toneId != "neutral" {
                changeStyle = .standard(state.toneId)
            } else {
                changeStyle = nil
            }
            let emojify = state.mode == .fix ? false : state.emojify

            signal = context.engine.messages.composeMessageWithAI(text: text, entities: entities, proofread: proofread, translateToLang: translateToLang, changeStyle: changeStyle, emojify: emojify)
            |> mapError { error -> Translate.Error in
                if case .limitExceeded = error {
                    return .limitExceeded
                }
                return .generic
            }
            |> map { result -> (detect: String?, result: String, entities: [MessageTextEntity]) in
                return (detect: nil, result: result.0, entities: result.1)
            }
        } else if let messageId = messageId {
            signal = context.engine.messages.translate(text: text, toLang: stateValue.with { $0.to }, tone: stateValue.with { $0.tone }, messageId: messageId)
            |> mapError { _ -> Translate.Error in
                return .generic
            }
            |> map { result -> (detect: String?, result: String, entities: [MessageTextEntity]) in
                if let result = result {
                    return (detect: nil, result: result.0, entities: result.1)
                } else {
                    return (detect: nil, result: "", entities: [])
                }
            }
        } else {
            signal = translateBlocks(context: context, from: stateValue.with { $0.from }, to: stateValue.with { $0.to }, blocks: blocks, configState: configState, tone: stateValue.with { $0.tone })
        }
        disposable.set((signal).start(next: { result in
            updateState { current in
                var current = current
                if result.result.isEmpty {
                    current.translated = current.text
                    current.translatedEntities = current.textEntities
                } else {
                    current.translated = result.result
                    current.translatedEntities = result.entities
                }
                current.isTranslating = false
                current.cache[key] = ComposeResult(text: current.translated ?? result.result, entities: current.translatedEntities)
                if current.from == nil {
                    current.from = result.detect
                }
                return current
            }
        }, error: { error in
            updateState { current in
                var current = current
                current.isTranslating = false
                if case .limitExceeded = error {
                    current.limitExceeded = true
                    current.translated = current.text
                    current.translatedEntities = current.textEntities
                } else {
                    current.translated = strings().unknownError
                }
                return current
            }
        }))
    }
    

    var getController: (()->InputDataController?)? = nil

    let showStyleTooltip: () -> Void = {
        if let view = getController?()?.tableView.item(stableId: InputDataEntryId.custom(InputDataIdentifier("style_selector")))?.view as? StyleEmojiRowView {
            let middleIndex = view.itemViews.count / 2 - 1
            if middleIndex >= 0, middleIndex < view.itemViews.count {
                tooltip(for: view.itemViews[middleIndex], text: strings().translateSelectStyle)
            }
        }
    }

    let arguments = Arguments(context: context, revealFrom: {
        updateState { current in
            var current = current
            current.fromIsRevealed = true
            return current
        }
    }, revealTo: {
        updateState { current in
            var current = current
            current.toIsRevealed = true
            return current
        }
    }, updateFrom: { language in
        updateState { current in
            var current = current
            current.from = language
            return current
        }
        request()
    }, updateTo: { language in
        updateState { current in
            var current = current
            current.to = language
            return current
        }
        request()
    }, updateTone: { tone in
        updateState { current in
            var current = current
            current.toneId = tone
            current.tone = TranslationTone(rawValue: tone) ?? .neutral
            return current
        }
        request()
        onToneChanged?(TranslationTone(rawValue: tone) ?? .neutral)
    }, copyTranslation: {
        let text = stateValue.with { $0.translatedAttr(context: context) }
        if let text {
            _ = LinkHooks.shared.globalLinkExecutor().copyAttributedString(text)
            showModalText(for: context.window, text: strings().shareLinkCopied)
        }
    }, translateEntireChat: translateEntireChat != nil ? {
        translateEntireChat?()
        close?()
    } : nil, updateMode: { mode in
        updateState { current in
            var current = current
            current.mode = mode
            return current
        }
        request()
        if mode == .style {
            let state = stateValue.with { $0 }
            if state.styleId.isEmpty && !state.emojify {
                delay(0.2, closure: {
                    showStyleTooltip()
                })
            }
        }
    }, updateStyle: { styleId in
        updateState { current in
            var current = current
            current.styleId = styleId
            return current
        }
        request()
    }, toggleEmojify: {
        updateState { current in
            var current = current
            current.emojify = !current.emojify
            return current
        }
        request()
    }, showStyleTooltip: showStyleTooltip, createNewStyle: {
        showModal(with: AIStyleModalController(context: context, onCompleted: { newStyleId in
            if let newStyleId {
                _ = pinnedNewStyleIds.modify { [newStyleId] + $0.filter { $0 != newStyleId } }
            }
            triggerReloadStyles()
        }), for: context.window)
    }, styleMenu: { style -> ContextMenu? in
        guard case .custom(let styleId, let accessHash) = style.reference else {
            return nil
        }
        let menu = ContextMenu()
        if style.isAuthor, let cloudStyle = style.cloudStyle {
            menu.addItem(ContextMenuItem(strings().translateModalEditStyle, handler: {
                showModal(with: AIStyleModalController(context: context, editing: cloudStyle, onCompleted: { _ in
                    triggerReloadStyles()
                }), for: context.window)
            }, itemImage: MenuAnimation.menu_edit.value))
        }
        menu.addItem(ContextMenuItem(strings().translateModalShareStyle, handler: {
            if let slug = style.slug {
                TranslateUIHooks.shared.shareLinkObserved(context, context.meUrlPrefix + "addstyle/\(slug)")
            }
        }, itemImage: MenuAnimation.menu_share.value))
        menu.addItem(ContextSeparatorItem())
        menu.addItem(ContextMenuItem(strings().translateModalDeleteStyle, handler: {
            let removedId = style.id
            let removeLocal: () -> Void = {
                updateState { current in
                    var current = current
                    current.styles.removeAll(where: { $0.id == removedId })
                    if current.styleId == removedId {
                        current.styleId = ""
                    }
                    return current
                }
                request()
            }
            if style.isAuthor {
                verifyAlert(for: context.window, header: strings().translateModalDeleteStyleHeader, information: strings().translateModalDeleteStyleConfirm, ok: strings().modalDelete, option: strings().translateModalDeleteStyleForAll, successHandler: { result in
                    switch result {
                    case .thrid:
                        _ = (context.engine.messages.deleteAITextStyle(id: styleId, accessHash: accessHash)).startStandalone()
                    case .basic:
                        _ = (context.engine.messages.unsaveAITextStyle(id: styleId, accessHash: accessHash)).startStandalone()
                    }
                    removeLocal()
                })
            } else {
                verifyAlert(for: context.window, header: strings().translateModalDeleteStyleHeader, information: strings().translateModalDeleteStyleConfirm, ok: strings().modalDelete, successHandler: { _ in
                    _ = (context.engine.messages.unsaveAITextStyle(id: styleId, accessHash: accessHash)).startStandalone()
                    removeLocal()
                })
            }
        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
        return menu
    }, isInputMode: isInputMode, isRich: richPage != nil, richPage: richPage, updateCustomPrompt: { prompt in
        updateState { current in
            var current = current
            current.customPrompt = prompt
            return current
        }
    })
    
    request()
    
    let signal = (statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: isInputMode ? strings().translateAIEditor : strings().translateTitle)

    controller.updateDatas = { data in
        if let prompt = data[InputDataIdentifier("custom_prompt")]?.stringValue {
            let changed = stateValue.with { $0.customPrompt != prompt }
            if changed {
                updateState { current in
                    var current = current
                    current.customPrompt = prompt
                    return current
                }
                promptRequestDisposable.set((Signal<Void, NoError>.single(Void()) |> delay(1.0, queue: .mainQueue())).start(completed: {
                    request()
                }))
            }
        }
        return .fail(.none)
    }

    getController = { [weak controller] in controller }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    let modalInteractions: ModalInteractions
    if isInputMode {
        let sendIcon: CGImage? = onSend != nil ? theme.icons.send_message_large : nil
        modalInteractions = ModalInteractions(acceptTitle: strings().translateApply, accept: {
            if stateValue.with({ $0.limitExceeded }) {
                close?()
                FeatureNavigationHooks.shared.showPremiumBoardingObserved(context, context.window, .aiCompose, false, nil)
                return
            }
            if let onUseRich {
                if let rich = stateValue.with({ $0.translatedRich }) {
                    let (blocks, _) = richTextOutgoing(from: rich)
                    onUseRich(coreBlocks(fromOutgoing: blocks))
                }
                close?()
                return
            }
            let text = stateValue.with { $0.translatedAttr(context: context) }
            if let text, let onUse {
                onUse(text)
                close?()
            }
        }, singleButton: true, extraActionImage: sendIcon, extraAction: onSend != nil ? {
            let text = stateValue.with { $0.translatedAttr(context: context) }
            if let text {
                onSend?(text)
                close?()
            }
        } : nil)
    } else if dismissOnly {
        modalInteractions = ModalInteractions(acceptTitle: strings().modalOK, accept: {
            close?()
        }, singleButton: true)
    } else {
        modalInteractions = ModalInteractions(acceptTitle: strings().contextCopy, accept: {
            let text = stateValue.with { $0.translatedAttr(context: context) }
            if let text {
                _ = LinkHooks.shared.globalLinkExecutor().copyAttributedString(text)
                showModalText(for: context.window, text: strings().shareLinkCopied)
            }
        }, singleButton: true)
    }

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 0))
    

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    if isInputMode {
        controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionInfo, handler: {
            TranslateUIHooks.shared.showAboutCocoonModalObserved(context)
        })
    }
    
    var limitTooltipShown = false
    controller.afterTransaction = { [weak modalInteractions] controller in
        let state = stateValue.with { $0 }
        modalInteractions?.updateDone { d in
            d.isEnabled = state.translated != nil && !state.isTranslating
            if state.limitExceeded {
                d.set(text: strings().premiumLimitIncrease, for: .Normal)
                let badge = generateX50Badge(textColor: theme.colors.accent)
                d.set(image: badge, for: .Normal)
                d.direction = .right
            }
        }
        modalInteractions?.updateExtraAction { button in
            button.isEnabled = state.translated != nil && !state.isTranslating
        }
        if state.limitExceeded && !limitTooltipShown {
            limitTooltipShown = true
            delay(0.2, closure: {
                showModalText(for: context.window, text: strings().translateDailyLimitInfo, title: strings().translateDailyLimitReached)
            })
        }
    }
    
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}


