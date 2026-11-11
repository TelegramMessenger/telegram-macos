import Foundation
import TGUIKit
import TelegramCore
import Postbox
import Cocoa
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InstantPageUI
import ChatUI
import InlineStickerLayer

struct TranslateHeaderData {
    let label: String
    let language: String?
    let languageMenu: (() -> [ContextMenuItem])?
    let toneLabel: String?
    let toneName: String?
    let toneMenu: (() -> [ContextMenuItem])?
    var emojifyLabel: String?
    var emojifyEnabled: Bool = false
    var emojifyDisabled: Bool = false
    var toggleEmojify: (()->Void)?
}

final class TranslateTableRowItem : GeneralRowItem {
    let textLayout: TextViewLayout
    let context: any AccountContextProtocol
    private(set) var revealed: Bool
    let reveal: ()->Void
    let headerData: TranslateHeaderData?
    let isLoading: Bool
    let copyTranslation: (()->Void)?
    let canCopy: Bool
    fileprivate var headerLayout: TextViewLayout?
    fileprivate var toneLayout: TextViewLayout?
    fileprivate var emojifyLayout: TextViewLayout?
    fileprivate let originalTextLayout: TextViewLayout?
    /// Rich content: rendered through the InstantPage V2 renderer instead of the flat text layout.
    fileprivate let richPage: InstantPage?
    fileprivate private(set) var richLayout: InstantPageV2Layout?
    fileprivate private(set) var richTheme: InstantPageTheme?
    fileprivate private(set) var richContentHeight: CGFloat = 0
    /// The collapsed cap snapped to a whole line/item boundary (computed per layout in `makeSize`).
    fileprivate private(set) var collapsedRichHeightResolved: CGFloat = TranslateTableRowItem.collapsedRichHeight

    /// Collapsed cap for rich content (≈3 text lines), revealed via the "Show more" overlay.
    private static let collapsedRichHeight: CGFloat = 66

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, text: String, entities: [MessageTextEntity] = [], revealed: Bool = false, headerData: TranslateHeaderData? = nil, isLoading: Bool = false, originalText: String? = nil, originalEntities: [MessageTextEntity] = [], richPage: InstantPage? = nil, viewType: GeneralViewType, copyTranslation: (()->Void)? = nil, canCopy: Bool = true, reveal: @escaping()->Void) {
        self.reveal = reveal
        self.canCopy = canCopy
        self.revealed = revealed
        self.context = context
        self.headerData = headerData
        self.isLoading = isLoading
        self.copyTranslation = copyTranslation
        self.richPage = richPage

        var attr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: context, fontSize: FontSize.text, openInfo: { _,_,_,_ in }, isDark: theme.colors.isDark, bubbled: true).mutableCopy() as! NSMutableAttributedString

        InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: entities, isPremium: context.isPremium)

        if !revealed {
            attr = attr.trimNewLinesToSpace.mutableCopy() as! NSMutableAttributedString
        }

        self.textLayout = .init(attr, maximumNumberOfLines: revealed ? Int32.max : 2)
        self.textLayout.mayItems = canCopy

        if isLoading, let originalText = originalText, !originalText.isEmpty {
            var origAttr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: originalEntities)], for: originalText, message: nil, context: context, fontSize: FontSize.text, openInfo: { _,_,_,_ in }, isDark: theme.colors.isDark, bubbled: true).mutableCopy() as! NSMutableAttributedString
            InlineStickerItem.apply(to: origAttr, associatedMedia: [:], entities: originalEntities, isPremium: context.isPremium)
            origAttr = origAttr.trimNewLinesToSpace.mutableCopy() as! NSMutableAttributedString
            let layout = TextViewLayout(origAttr, maximumNumberOfLines: 3)
            layout.mayItems = canCopy
            self.originalTextLayout = layout
        } else {
            self.originalTextLayout = nil
        }

        if let headerData = headerData {
            let headerAttr = NSMutableAttributedString()
            headerAttr.append(string: headerData.label, color: theme.colors.listGrayText, font: .normal(.text))
            if let language = headerData.language {
                headerAttr.append(string: " " + language, color: theme.colors.accent, font: .medium(.text))
            }
            self.headerLayout = TextViewLayout(headerAttr, maximumNumberOfLines: 1)

            if let toneLabel = headerData.toneLabel, let toneName = headerData.toneName {
                let toneAttr = NSMutableAttributedString()
                toneAttr.append(string: toneLabel + " ", color: theme.colors.listGrayText, font: .normal(.text))
                toneAttr.append(string: toneName, color: theme.colors.accent, font: .medium(.text))
                self.toneLayout = TextViewLayout(toneAttr, maximumNumberOfLines: 1)
            }
            if let emojifyLabel = headerData.emojifyLabel {
                let emojifyAttr = NSMutableAttributedString()
                emojifyAttr.append(string: emojifyLabel, color: theme.colors.listGrayText, font: .normal(.text))
                self.emojifyLayout = TextViewLayout(emojifyAttr, maximumNumberOfLines: 1)
            }
        }

        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    private var headerHeight: CGFloat {
        if let headerLayout = headerLayout {
            return headerLayout.layoutSize.height + 6
        }
        return 0
    }

    override var height: CGFloat {
        if isLoading {
            if let originalTextLayout = originalTextLayout {
                return headerHeight + originalTextLayout.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom
            }
            return headerHeight + 30 + viewType.innerInset.top + viewType.innerInset.bottom
        }

        let copyInset: CGFloat = (copyTranslation != nil && !isLoading) ? 4 : 0
        if richLayout != nil {
            return richDisplayHeight + headerHeight + copyInset + viewType.innerInset.top + viewType.innerInset.bottom
        }
        return textLayout.layoutSize.height + headerHeight + copyInset + viewType.innerInset.top + viewType.innerInset.bottom
    }

    /// Rich content height as displayed: full when revealed, capped (with the "Show more" overlay) otherwise.
    var richDisplayHeight: CGFloat {
        return revealed ? richContentHeight : min(richContentHeight, collapsedRichHeightResolved)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let availableWidth = self.blockWidth - viewType.innerInset.left - viewType.innerInset.right
        headerLayout?.measure(width: availableWidth)
        toneLayout?.measure(width: availableWidth)
        emojifyLayout?.measure(width: availableWidth)
        textLayout.measure(width: availableWidth)
        originalTextLayout?.measure(width: availableWidth)
        if let originalTextLayout = originalTextLayout {
            originalTextLayout.maskBlockImage = originalTextLayout.generateBlock(backgroundColor: NSColor.black.withAlphaComponent(0.4))
        }
        if let page = richPage, !isLoading {
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
            // Snap the collapsed cap to a whole line/item boundary so the last visible line isn't cut mid-glyph.
            var snapped: CGFloat = 0
            for item in layout.items {
                if case let .text(textValue) = item {
                    for line in textValue.textItem.lines {
                        let bottom = textValue.frame.minY + line.frame.maxY
                        if bottom <= TranslateTableRowItem.collapsedRichHeight {
                            snapped = max(snapped, bottom)
                        }
                    }
                } else if item.frame.maxY <= TranslateTableRowItem.collapsedRichHeight {
                    snapped = max(snapped, item.frame.maxY)
                }
            }
            self.collapsedRichHeightResolved = snapped > 0 ? snapped + 2 : TranslateTableRowItem.collapsedRichHeight
        } else {
            self.richLayout = nil
            self.richTheme = nil
            self.richContentHeight = 0
        }
        if richLayout != nil {
            // Rich content that fits the collapsed cap needs no reveal affordance.
            if richContentHeight <= TranslateTableRowItem.collapsedRichHeight {
                revealed = true
            }
        } else if textLayout.isPerfectSized {
            revealed = true
        }
        return true
    }

    override var accessibilityLabel: String? {
        return headerLayout?.attributedString.string ?? strings().voiceOverCommonTranslate
    }

    override var accessibilityValue: String? {
        return isLoading ? strings().voiceOverCommonLoading : nil
    }

    override func viewClass() -> AnyClass {
        return TranslateTableRowView.self
    }
}


private final class MoreView : Control {
    private var more: TextView = TextView()
    private let shadowView = ShadowView()
    private let back: View = View()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(back)
        addSubview(shadowView)
        addSubview(more)


        more.isSelectable = false
        more.userInteractionEnabled = false
        more.isAccessibilityDecorative = true
        setAccessibilityLabel(strings().translateShowMore)
        let layout = TextViewLayout(.initialize(string: strings().translateShowMore, color: theme.colors.accent, font: .medium(.text)))
        layout.measure(width: .greatestFiniteMagnitude)
        more.update(layout)



        self.setFrameSize(NSMakeSize(layout.layoutSize.width + 30, layout.layoutSize.height + 2))

        scaleOnClick = true
        shadowView.shadowBackground = theme.colors.background
        shadowView.direction = .horizontal(true)
        back.backgroundColor = theme.colors.background

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        shadowView.frame = NSMakeRect(0, 0, 30, frame.height)
        back.frame = NSMakeRect(shadowView.frame.maxX, 0, frame.width - shadowView.frame.maxX, frame.height)
        more.centerY(x: frame.width - more.frame.width)
    }
}

private final class TranslateHeaderButton : Control {
    let label = TextView()
    let chevron = ImageView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(label)
        addSubview(chevron)
        label.isSelectable = false
        label.userInteractionEnabled = false
        label.isAccessibilityDecorative = true
        chevron.isEventLess = true
        chevron.isAccessibilityDecorative = true
        scaleOnClick = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: TextViewLayout, hasMenu: Bool = true) {
        label.update(layout)
        setAccessibilityLabel(layout.attributedString.string)
        chevron.isHidden = !hasMenu

        if hasMenu {
            let circleSize: CGFloat = 16
            let chevronIcon = TelegramThemeHooks.shared.image(.iconSmallChevronDown).precomposed(theme.colors.accent, flipVertical: false)
            let image = generateImage(NSMakeSize(circleSize, circleSize), contextGenerator: { size, ctx in
                ctx.clear(size.bounds)
                ctx.setFillColor(theme.colors.accent.withAlphaComponent(0.2).cgColor)
                ctx.fillEllipse(in: size.bounds)
                ctx.draw(chevronIcon, in: size.bounds.focus(chevronIcon.backingSize))
            })
            chevron.image = image
            chevron.setFrameSize(NSMakeSize(circleSize, circleSize))

            let totalWidth = layout.layoutSize.width + 4 + circleSize
            let totalHeight = max(layout.layoutSize.height, circleSize)
            setFrameSize(NSMakeSize(totalWidth, totalHeight))
            label.setFrameOrigin(NSMakePoint(0, floorToScreenPixels((totalHeight - layout.layoutSize.height) / 2)))
            chevron.setFrameOrigin(NSMakePoint(layout.layoutSize.width + 4, floorToScreenPixels((totalHeight - circleSize) / 2)))
        } else {
            setFrameSize(layout.layoutSize)
            label.setFrameOrigin(.zero)
        }
    }
}

private final class TranslateTableRowView : GeneralContainableRowView {
    private let textView = InteractiveTextView()
    private var richView: InstantPageV2View? = nil
    private var more: MoreView? = nil
    private var headerButton: TranslateHeaderButton?
    private var toneButton: TranslateHeaderButton?
    private var emojifyControl: Control?
    private var emojifyToggle: SelectingControl?
    private var emojifyLabel: TextView?
    private var progressIndicator: ProgressIndicator?
    private var copyButton: ImageButton?
    private let separatorView = View()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        containerView.addSubview(separatorView)
        textView.textView.isSelectable = true
        textView.textView.userInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = item as? TranslateTableRowItem else {
            return
        }

        let textY: CGFloat
        if let headerButton = headerButton {
            transition.updateFrame(view: headerButton, frame: CGRect(origin: CGPoint(x: item.viewType.innerInset.left, y: item.viewType.innerInset.top), size: headerButton.frame.size))

            if let toneButton = toneButton {
                transition.updateFrame(view: toneButton, frame: CGRect(origin: CGPoint(x: containerView.frame.width - item.viewType.innerInset.right - toneButton.frame.width, y: item.viewType.innerInset.top), size: toneButton.frame.size))
            }
            if let emojifyControl = emojifyControl {
                let rightX = containerView.frame.width - item.viewType.innerInset.right
                let controlX = rightX - emojifyControl.frame.width
                let centerY = item.viewType.innerInset.top + (headerButton.frame.height - emojifyControl.frame.height) / 2
                transition.updateFrame(view: emojifyControl, frame: CGRect(origin: CGPoint(x: controlX, y: centerY), size: emojifyControl.frame.size))
            }
            textY = headerButton.frame.maxY + 6
        } else {
            textY = item.viewType.innerInset.top
        }

        if let progressIndicator = progressIndicator {
            transition.updateFrame(view: progressIndicator, frame: CGRect(origin: CGPoint(x: item.viewType.innerInset.left, y: textY + 5), size: progressIndicator.frame.size))
        }

        transition.updateFrame(view: textView, frame: CGRect(origin: CGPoint(x: item.viewType.innerInset.left, y: textY), size: textView.frame.size))

        if let richView = richView {
            let availableWidth = item.blockWidth - item.viewType.innerInset.left - item.viewType.innerInset.right
            transition.updateFrame(view: richView, frame: CGRect(origin: CGPoint(x: item.viewType.innerInset.left, y: textY), size: NSMakeSize(max(40, availableWidth), item.richDisplayHeight)))
        }

        if let copyButton = copyButton {
            let x = containerView.frame.width - item.viewType.innerInset.right - copyButton.frame.width
            let y = containerView.frame.height - item.viewType.innerInset.bottom - copyButton.frame.height + 4
            transition.updateFrame(view: copyButton, frame: CGRect(origin: CGPoint(x: x, y: y), size: copyButton.frame.size))
        }

        if let more = more {
            transition.updateFrame(view: more, frame: CGRect(origin: CGPoint(x: containerView.frame.width - item.viewType.innerInset.left - more.frame.width, y: containerView.frame.height - item.viewType.innerInset.top - more.frame.height + 1), size: more.frame.size))
        }

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

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? TranslateTableRowItem else {
            return
        }

        textView.textView.isSelectable = item.canCopy

        if let headerData = item.headerData, let headerLayout = item.headerLayout {
            let hButton: TranslateHeaderButton
            if let existing = self.headerButton {
                hButton = existing
            } else {
                hButton = TranslateHeaderButton(frame: .zero)
                addSubview(hButton)
                self.headerButton = hButton
            }
            hButton.update(layout: headerLayout, hasMenu: headerData.languageMenu != nil)
            hButton.removeAllHandlers()
            if let languageMenu = headerData.languageMenu {
                hButton.contextMenu = {
                    let menu = ContextMenu()
                    for menuItem in languageMenu() {
                        menu.addItem(menuItem)
                    }
                    return menu
                }
            } else {
                hButton.contextMenu = nil
            }

            if let toneLayout = item.toneLayout, let toneMenu = headerData.toneMenu {
                let tButton: TranslateHeaderButton
                if let existing = self.toneButton {
                    tButton = existing
                } else {
                    tButton = TranslateHeaderButton(frame: .zero)
                    addSubview(tButton)
                    self.toneButton = tButton
                }
                tButton.update(layout: toneLayout)
                tButton.removeAllHandlers()
                tButton.contextMenu = {
                    let menu = ContextMenu()
                    for menuItem in toneMenu() {
                        menu.addItem(menuItem)
                    }
                    return menu
                }
            } else if let view = self.toneButton {
                performSubviewRemoval(view, animated: animated)
                self.toneButton = nil
            }

            if let emojifyTextLayout = item.emojifyLayout, let toggleEmojify = headerData.toggleEmojify {
                let control: Control
                var isNew = false
                if let existing = self.emojifyControl {
                    control = existing
                } else {
                    control = Control(frame: .zero)
                    addSubview(control)
                    self.emojifyControl = control
                    isNew = true
                }

                let checkSize: CGFloat = 17
                let selectedImg = generateImage(NSMakeSize(checkSize, checkSize), rotatedContext: { size, ctx in
                    ctx.clear(size.bounds)
                    ctx.round(size, size.width / 2)
                    ctx.setFillColor(theme.colors.accent.cgColor)
                    ctx.fill(size.bounds)
                    ctx.setStrokeColor(theme.colors.underSelectedColor.cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.move(to: NSMakePoint(5, 9))
                    ctx.addLine(to: NSMakePoint(7.5, 12))
                    ctx.addLine(to: NSMakePoint(13, 6.5))
                    ctx.strokePath()
                })!
                let unselectedImg = generateImage(NSMakeSize(checkSize, checkSize), rotatedContext: { size, ctx in
                    ctx.clear(size.bounds)
                    ctx.setStrokeColor(theme.colors.grayIcon.withAlphaComponent(0.6).cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.strokeEllipse(in: size.bounds.insetBy(dx: 0.75, dy: 0.75))
                })!

                let toggle: SelectingControl
                if let existing = self.emojifyToggle {
                    toggle = existing
                    toggle.update(unselectedImage: unselectedImg, selectedImage: selectedImg, selected: headerData.emojifyEnabled, animated: animated)
                } else {
                    toggle = SelectingControl(unselectedImage: unselectedImg, selectedImage: selectedImg, selected: headerData.emojifyEnabled)
                    toggle.isAccessibilityDecorative = true
                    control.addSubview(toggle)
                    self.emojifyToggle = toggle
                }

                let label: TextView
                if let existing = self.emojifyLabel {
                    label = existing
                } else {
                    label = TextView()
                    label.isSelectable = false
                    label.userInteractionEnabled = false
                    label.isAccessibilityDecorative = true
                    control.addSubview(label)
                    self.emojifyLabel = label
                }
                label.update(emojifyTextLayout)
                control.setAccessibilityLabel(emojifyTextLayout.attributedString.string)
                control.setAccessibilityValue(headerData.emojifyEnabled ? strings().voiceOverCommonChecked : strings().voiceOverCommonUnchecked)

                let totalW = toggle.frame.width + 4 + label.frame.width
                let totalH = max(toggle.frame.height, label.frame.height)
                control.setFrameSize(NSMakeSize(totalW, totalH))
                toggle.setFrameOrigin(NSMakePoint(0, floorToScreenPixels((totalH - toggle.frame.height) / 2)))
                label.setFrameOrigin(NSMakePoint(toggle.frame.maxX + 4, floorToScreenPixels((totalH - label.frame.height) / 2)))

                if isNew, let headerButton = self.headerButton {
                    let rightX = containerView.frame.width - item.viewType.innerInset.right
                    let controlX = rightX - control.frame.width
                    let centerY = item.viewType.innerInset.top + (headerButton.frame.height - control.frame.height) / 2
                    control.setFrameOrigin(NSMakePoint(controlX, centerY))
                }

                control.alphaValue = (item.isLoading || headerData.emojifyDisabled) ? 0.5 : 1.0
                control.removeAllHandlers()
                control.set(handler: { _ in
                    toggleEmojify()
                }, for: .Click)
            } else {
                if let view = self.emojifyControl {
                    performSubviewRemoval(view, animated: animated)
                    self.emojifyControl = nil
                    self.emojifyToggle = nil
                    self.emojifyLabel = nil
                }
            }
        } else {
            if let view = self.headerButton {
                performSubviewRemoval(view, animated: animated)
                self.headerButton = nil
            }
            if let view = self.toneButton {
                performSubviewRemoval(view, animated: animated)
                self.toneButton = nil
            }
            if let view = self.emojifyControl {
                performSubviewRemoval(view, animated: animated)
                self.emojifyControl = nil
                self.emojifyToggle = nil
                self.emojifyLabel = nil
            }
        }

        if item.isLoading {
            if let view = self.richView {
                performSubviewRemoval(view, animated: animated)
                self.richView = nil
            }
            if let originalTextLayout = item.originalTextLayout {
                textView.isHidden = false
                textView.set(text: originalTextLayout, context: item.context)
                textView.textView.setIsShimmering(true, animated: animated)
                if let view = self.progressIndicator {
                    performSubviewRemoval(view, animated: animated)
                    self.progressIndicator = nil
                }
            } else {
                textView.isHidden = true
                let indicator: ProgressIndicator
                if let existing = self.progressIndicator {
                    indicator = existing
                } else {
                    indicator = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
                    addSubview(indicator)
                    self.progressIndicator = indicator
                }
                indicator.progressColor = theme.colors.text
                indicator.animates = true
            }
        } else {
            if let richLayout = item.richLayout, let richTheme = item.richTheme {
                // Rich content: render through the InstantPage V2 view (headings/lists/tables/formulas),
                // hiding the flat text.
                textView.isHidden = true
                let current: InstantPageV2View
                if let view = self.richView {
                    current = view
                } else {
                    current = InstantPageV2View(frame: .zero)
                    addSubview(current)
                    self.richView = current
                }
                // Clip so the collapsed (3-line capped) state crops the document instead of overflowing the row.
                current.layer?.masksToBounds = true
                current.context = item.context
                current.canCopy = item.canCopy
                current.update(layout: richLayout, theme: richTheme)
            } else {
                if let view = self.richView {
                    performSubviewRemoval(view, animated: animated)
                    self.richView = nil
                }
                textView.isHidden = false
                textView.set(text: item.textLayout, context: item.context)
                textView.textView.setIsShimmering(false, animated: animated)
            }
            if let view = self.progressIndicator {
                performSubviewRemoval(view, animated: animated)
                self.progressIndicator = nil
            }
        }

        if !item.isLoading && item.copyTranslation != nil {
            let button: ImageButton
            if let existing = self.copyButton {
                button = existing
            } else {
                button = ImageButton()
                button.autohighlight = false
                button.scaleOnClick = true
                button.setAccessibilityLabel(strings().voiceOverCommonCopy)
                containerView.addSubview(button)
                self.copyButton = button

                button.set(image: TelegramThemeHooks.shared.image(.iconCopyLink).precomposed(theme.colors.accent), for: .Normal)
                button.sizeToFit()
                let x = containerView.frame.width - item.viewType.innerInset.right - button.frame.width
                let y = containerView.frame.height - item.viewType.innerInset.bottom - button.frame.height + 4
                button.frame = CGRect(origin: CGPoint(x: x, y: y), size: button.frame.size)
            }
            button.set(image: TelegramThemeHooks.shared.image(.iconCopyLink).precomposed(theme.colors.accent), for: .Normal)
            button.sizeToFit()
            button.removeAllHandlers()
            button.set(handler: { [weak self] _ in
                if let item = self?.item as? TranslateTableRowItem {
                    item.copyTranslation?()
                }
            }, for: .Click)
        } else {
            if let view = self.copyButton {
                performSubviewRemoval(view, animated: animated)
                self.copyButton = nil
            }
        }

        if !item.revealed && !item.isLoading {
            let current: MoreView
            if let view = self.more {
                current = view
            } else {
                let view = MoreView(frame: .zero)
                current = view
                addSubview(current)
                self.more = view
                current.set(handler: { [weak self] _ in
                    if let item = self?.item as? TranslateTableRowItem {
                        item.reveal()
                    }
                }, for: .Click)
            }
        } else if let view = self.more {
            self.more = nil
            performSubviewRemoval(view, animated: animated)
        }
    }
}
