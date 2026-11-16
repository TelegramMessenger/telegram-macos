import Cocoa


import Cocoa

public enum TextButtonImageDirection {
    case left
    case right
    case top
}

import AppKit

private let textButtonSubtextDuration: Double = 0.22

open class TextButton: ImageButton {

    // MARK: - Views

    private var text: TextView = {
        let view = TextView(frame: NSMakeRect(0, 0, 16, 14))
        view.userInteractionEnabled = false
        view.isSelectable = false
        view.isEventLess = true
        view.isAccessibilityDecorative = true
        view.disableBackgroundDrawing = true
        return view
    }()
    private var subText: TextView?
    private var subTextIsNew: Bool = false
    private var animatesSubtextChange: Bool = false

    // MARK: - State storages

    private var stateText:    [ControlState:String]  = [:]
    private var stateColor:   [ControlState:NSColor] = [:]
    private var stateFont:    [ControlState:NSFont]  = [:]

    private var stateSubText: [ControlState:String]  = [:]
    private var stateSubColor:[ControlState:NSColor] = [:]
    private var stateSubFont: [ControlState:NSFont]  = [:]

    // MARK: - Layout caches / flags

    private var currentTextSize:  NSSize?
    private var currentBlockSize: NSSize? // title(+sub) measured together

    private struct TextLayoutCache {
        let string: String
        let color: NSColor
        let font: NSFont
        let scale: CGFloat
        let attributedString: NSAttributedString
        let layout: TextViewLayout
        let size: NSSize

        func matches(_ current: TextViewLayout) -> Bool {
            return current === layout && current.attributedString === attributedString
                && scale == System.backingScale && current.constrainedWidth == .greatestFiniteMagnitude
                && current.layoutSize == size && current.maximumNumberOfLines == 1
                && current.penFlush == 0.5 && current.cutout == nil
        }
    }

    private var titleLayoutCache: TextLayoutCache?
    private var subtextLayoutCache: TextLayoutCache?

    private static func updateText(_ view: TextView, string: String, color: NSColor, font: NSFont, cache: TextLayoutCache?) -> TextLayoutCache? {
        if color.type == .componentBased, let cache = cache,
           cache.string == string, cache.color.isEqual(color), cache.font.isEqual(font),
           let layout = view.textLayout, cache.matches(layout) {
            if view.frame.size != cache.size {
                view.update(cache.layout)
            }
            return cache
        }
        let attributedString = NSAttributedString.initialize(string: string, color: color, font: font)
        let layout = TextViewLayout(attributedString, maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
        layout.measure(width: .greatestFiniteMagnitude)
        view.update(layout)
        guard color.type == .componentBased else { return nil }
        return TextLayoutCache(string: string, color: color, font: font, scale: System.backingScale, attributedString: attributedString, layout: layout, size: layout.layoutSize)
    }

    public var autoSizeToFit: Bool = true
    public var showsSubtextWhenEmptyTitle: Bool = false
    public var subtextSpacing: CGFloat = 1

    public var direction: TextButtonImageDirection = .left {
        didSet { if direction != oldValue { updateLayout() } }
    }

    public var textOffset: NSPoint = .zero {
        didSet { if textOffset != oldValue { updateLayout() } }
    }

    public var buttonImageInset: CGFloat = 6 {
        didSet { if buttonImageInset != oldValue { updateLayout() } }
    }

    // MARK: - Init

    public override init() {
        super.init()
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        disableActions()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override var accessibilityDefaultLabel: String? {
        if let title = stateText[.Normal] ?? stateText.values.first, !title.isEmpty {
            return title
        }
        return super.accessibilityDefaultLabel
    }

    // MARK: - Public API (Title)

    public func set(text: String, for state: ControlState) {
        stateText[state] = text
        apply(state: self.controlState)
        if autoSizeToFit {
            _ = sizeToFit(NSZeroSize, self.frame.size, thatFit: _thatFit)
        }
    }

    public func set(color: NSColor, for state: ControlState) {
        stateColor[state] = color
        apply(state: self.controlState)
    }

    public func set(font: NSFont, for state: ControlState) {
        stateFont[state] = font
        apply(state: self.controlState)
    }

    // MARK: - Public API (Subtext)

    public func set(subtext: String?, for state: ControlState, animated: Bool = false) {
        if let subtext {
            stateSubText[state] = subtext
        } else {
            stateSubText.removeValue(forKey: state)
        }
        let hadSubtext = subText != nil
        animatesSubtextChange = animated && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        apply(state: self.controlState)
        let transition: ContainedViewLayoutTransition = animatesSubtextChange && hadSubtext != (subText != nil) ? .animated(duration: textButtonSubtextDuration, curve: .easeInOut) : .immediate
        animatesSubtextChange = false
        if autoSizeToFit {
            _ = sizeToFit(NSZeroSize, self.frame.size, thatFit: _thatFit, transition: transition)
        }
    }

    public func set(subtextColor color: NSColor, for state: ControlState) {
        stateSubColor[state] = color
        apply(state: self.controlState)
    }

    public func set(subtextFont font: NSFont, for state: ControlState) {
        stateSubFont[state] = font
        apply(state: self.controlState)
    }

    // MARK: - State application

    override public func apply(state: ControlState) {
        let state = self.isSelected ? .Highlight : state
        super.apply(state: state)

        let titleText = stateText[state] ?? stateText[.Normal] ?? ""

        var titleColor = stateColor[state] ?? stateColor[.Normal] ?? style.foregroundColor
        if let tint = _glassContentTint {
            titleColor = tint
        }
        if !isEnabled { titleColor = titleColor.withAlphaComponent(0.5) }

        let titleFont = stateFont[state] ?? stateFont[.Normal] ?? style.font

        let subStr   = stateSubText[state] ?? stateSubText[.Normal] ?? ""

        self.text.backgroundColor = .clear

        titleLayoutCache = Self.updateText(text, string: titleText, color: titleColor, font: titleFont, cache: titleLayoutCache)
        if subStr.isEmpty {
            subtextLayoutCache = nil
            if let view = self.subText {
                performSubviewRemoval(view, animated: animatesSubtextChange, duration: textButtonSubtextDuration, timingFunction: .easeInEaseOut)
                self.subText = nil
            }
            self.subTextIsNew = false
        } else {
            var subColor = stateSubColor[state] ?? stateSubColor[.Normal] ?? titleColor.withAlphaComponent(0.8)
            if !isEnabled { subColor = subColor.withAlphaComponent(0.5) }
            let subFont = stateSubFont[state] ?? stateSubFont[.Normal] ?? NSFont.systemFont(ofSize: max(10, titleFont.pointSize - 2), weight: .regular)
            let current: TextView
            if let view = self.subText {
                current = view
            } else {
                current = TextView(frame: NSMakeRect(0, 0, 16, 12))
                current.userInteractionEnabled = false
                current.isSelectable = false
                current.isEventLess = true
                current.disableBackgroundDrawing = true
                current.backgroundColor = .clear
                addSubview(current)
                self.subText = current
                self.subTextIsNew = true
                if animatesSubtextChange {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: textButtonSubtextDuration, timingFunction: .easeInEaseOut)
                }
            }
            subtextLayoutCache = Self.updateText(current, string: subStr, color: subColor, font: subFont, cache: subtextLayoutCache)
        }

        needsLayout = true
    }

    // MARK: - Computed helpers

    public var isEmpty: Bool {
        if let string = text.textLayout?.attributedString.string {
            return string.isEmpty
        } else {
            return true
        }
    }

    var string: String? {
        return text.textLayout?.attributedString.string
    }

    public var textSize: NSSize {
        return self.text.frame.size
    }

    // MARK: - Sizing

    @discardableResult
    public override func sizeToFit(_ addition: NSSize = NSZeroSize, _ maxSize: NSSize = NSZeroSize, thatFit: Bool = false, transition: ContainedViewLayoutTransition = .immediate) -> Bool {

        let subStr = self.subText?.textLayout?.attributedString.string ?? ""
        let hasSub = !subStr.isEmpty

        if isEmpty && !(showsSubtextWhenEmptyTitle && hasSub) {
            return super.sizeToFit(addition, maxSize, thatFit: thatFit, transition: transition)
        } else {
            _ = super.sizeToFit(addition, maxSize, thatFit: thatFit, transition: transition)
        }

        let titleSize: NSSize
        if let layout = text.textLayout {
            if titleLayoutCache?.matches(layout) != true {
                layout.measure(width: .greatestFiniteMagnitude)
            }
            titleSize = layout.layoutSize
        } else {
            titleSize = .zero
        }
        let subSize: NSSize
        if hasSub, let layout = self.subText?.textLayout {
            if subtextLayoutCache?.matches(layout) != true {
                layout.measure(width: .greatestFiniteMagnitude)
            }
            subSize = layout.layoutSize
        } else {
            subSize = .zero
        }

        let blockW = max(titleSize.width, subSize.width)
        let blockH = titleSize.height + (hasSub ? (subtextSpacing + subSize.height) : 0)
        var msize  = NSSize(width: blockW, height: blockH)

        if maxSize.width < msize.width {
            if let image = imageView.image, direction != .top {
                msize.width += (image.backingSize.width + buttonImageInset)
            }
        }

        var maxWidth: CGFloat = !thatFit || maxSize.width == 0
            ? (maxSize.width > 0 ? maxSize.width : msize.width)
            : maxSize.width

        var textWidth: CGFloat = maxWidth

        if let image = imageView.image, direction != .top {
            textWidth = min(maxWidth, blockW)
            let iwidth: CGFloat = (image.backingSize.width + buttonImageInset)

            if textWidth == maxWidth {
                textWidth -= iwidth
            } else {
                textWidth = (maxWidth - blockW) >= iwidth ? blockW : maxWidth - iwidth
                maxWidth = textWidth + iwidth
            }
        } else {
            maxWidth = min(blockW, textWidth)
            textWidth = min(blockW, textWidth)
        }

        if thatFit && maxSize.width > 0 {
            maxWidth = maxSize.width
        } else {
            maxWidth += addition.width
        }

        let finalHeight = max(blockH, maxSize.height) + addition.height
        let newSize = NSSize(width: maxWidth, height: finalHeight)
        transition.updateFrame(view: self, frame: CGRect(origin: frame.origin, size: newSize))

        self.currentTextSize  = NSSize(width: textWidth, height: titleSize.height)
        self.currentBlockSize = NSSize(width: textWidth, height: blockH)

        updateLayout(size: newSize, transition: transition)
        return frame.width >= maxWidth
    }

    // MARK: - Layout

    open override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)

        let subView = self.subText
        let hasSubtext = subView != nil

        let subSize: NSSize = subView?.frame.size ?? .zero
        let blockSize = currentBlockSize ?? NSSize(
            width: max(self.text.frame.width, subSize.width),
            height: self.text.frame.height + (hasSubtext ? (subtextSpacing + subSize.height) : 0)
        )

        let containerBounds = NSRect(origin: .zero, size: size)

        func placeBlock(originX: CGFloat, originY: CGFloat, centerLines: Bool = false) {
            let textX = centerLines ? originX + round((blockSize.width - self.text.frame.width) / 2.0) : originX
            let textFrame = NSMakeRect(textX, originY, self.text.frame.width, self.text.frame.height)
            transition.updateFrame(view: self.text, frame: textFrame)

            if let subView = subView {
                let subY = originY + self.text.frame.height + subtextSpacing
                let subX = centerLines ? originX + round((blockSize.width - subView.frame.width) / 2.0) : originX
                let subFrame = NSMakeRect(subX, subY, subView.frame.width, subView.frame.height)
                if self.subTextIsNew {
                    subView.frame = subFrame
                    self.subTextIsNew = false
                } else {
                    transition.updateFrame(view: subView, frame: subFrame)
                }
            }
        }

        guard let _ = imageView.image else {
            let x = round((size.width - blockSize.width) / 2.0) + textOffset.x
            let y = floor((size.height - blockSize.height) / 2.0) + textOffset.y
            placeBlock(originX: x, originY: y, centerLines: hasSubtext)
            return
        }

        // There is an image. Show text block only if there is a title or we're allowed to show only subtext.
        let canShowBlock = (self.string?.isEmpty == false) || (showsSubtextWhenEmptyTitle && hasSubtext)
        if !canShowBlock {
            transition.updateFrame(view: self.imageView, frame: self.imageView.centerFrameY())
            // Only image is visible — let the base class center it.
            return
        }

        let imageSize = imageView.frame.size
        let imageFocus = containerBounds.focus(imageSize)
        switch direction {
        case .left:
            // Image on the left, text block to its right, both vertically centered.
            let imageFrame = NSMakeRect(
                round((size.width - blockSize.width - imageSize.width - buttonImageInset) / 2.0),
                imageFocus.minY,
                imageSize.width,
                imageSize.height
            )
            transition.updateFrame(view: imageView, frame: imageFrame)
            var blockFocus = containerBounds.focus(blockSize)
            blockFocus.origin.y -= 1
            let textX = imageFrame.maxX + buttonImageInset
            placeBlock(originX: textX, originY: blockFocus.minY)

        case .right:
            // Text centered together with image, image after text.
            let totalWidth = blockSize.width + buttonImageInset + imageSize.width
            let textX = round((size.width - totalWidth) / 2.0)
            let blockFocus = containerBounds.focus(blockSize)
            placeBlock(originX: textX, originY: blockFocus.minY)
            let imageFrame = NSMakeRect(
                round(textX + blockSize.width + buttonImageInset),
                imageFocus.minY,
                imageSize.width,
                imageSize.height
            )
            transition.updateFrame(view: imageView, frame: imageFrame)

        case .top:
            // Image above, then the stacked text block below it with a small gap.
            let imageFrame = NSMakeRect(
                imageFocus.minX,
                imageFocus.minY,
                imageSize.width,
                imageSize.height
            )
            transition.updateFrame(view: imageView, frame: imageFrame)
            let blockFocusForX = containerBounds.focus(blockSize)
            let textX = blockFocusForX.minX
            let gap: CGFloat = 2
            let blockBottomY = imageFrame.minY - gap - blockSize.height
            placeBlock(originX: textX, originY: blockBottomY)
        }
    }


    public override var style: ControlStyle {
        set {
            super.style = newValue
            apply(state: self.controlState)
        }
        get { return super.style }
    }

    public override var backgroundColor: NSColor {
        set {
            super.backgroundColor = newValue
            self.text.backgroundColor = newValue
            self.subText?.backgroundColor = newValue
        }
        get { return super.backgroundColor }
    }

    // MARK: - Prepare / drawing

    override func prepare() {
        super.prepare()
        self.addSubview(text)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    public override func disableActions() {
        super.disableActions()
        self.layer?.disableActions()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }

    // MARK: - Utilities

    public static func size(with string: String?, font: NSFont?) -> NSSize {
        guard let font = font, let string = string else {
            return .zero
        }
        let attributedString: NSAttributedString = NSAttributedString.initialize(string: string, font: font)
        let layout = TextViewLayout(attributedString)
        layout.measure(width: .greatestFiniteMagnitude)
        var size: NSSize = layout.layoutSize
        size.width  = ceil(size.width) + (size.width == 0 ? 0 : 10)
        size.height = ceil(size.height + 1)
        return size
    }
}
