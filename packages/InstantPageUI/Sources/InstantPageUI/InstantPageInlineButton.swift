import Cocoa
import CoreText
import TelegramCore
import TGUIKit
import Emoji
import TelegramTheme
import TelegramUtils
import TelegramContext
import InlineStickerLayer
import InputView

public enum InstantPageButtonUIIcon {
    case url
    case share
    case profile
    case web
    case copy
    case payment
}

public struct InstantPageButtonUIModel {
    public let button: InstantPageButton
    public let isEnabled: Bool
    public let icon: InstantPageButtonUIIcon?

    public init(button: InstantPageButton, isEnabled: Bool = true) {
        self.button = button
        let actionEnabled = button.action != .disabled && !instantPageButtonHasDisabledMarker(button.text)
        self.isEnabled = isEnabled && actionEnabled
        if let icon = instantPageButtonIcon(button.action) {
            self.icon = icon
        } else if !actionEnabled {
            switch button.text.plainText {
            case "Open":
                self.icon = .url
            case "Profile":
                self.icon = .profile
            default:
                self.icon = nil
            }
        } else {
            self.icon = nil
        }
    }
}

public func instantPageDisabledButtonText(_ text: RichText) -> RichText {
    return .concat([text, .fixed(.plain(""))])
}

private func instantPageButtonHasDisabledMarker(_ text: RichText) -> Bool {
    guard case let .concat(items) = text, let last = items.last else {
        return false
    }
    guard case let .fixed(value) = last, case let .plain(string) = value else {
        return false
    }
    return string.isEmpty
}

/// A custom emoji inside a button's label, positioned relative to the LABEL BOX rather than the pill.
/// The label is drawn by the pill rather than by the paragraph, so its emoji never reach the
/// paragraph's own run scan; the V2 view walks these to hang an `InlineStickerItemLayer` over each.
///
/// Label-relative because a block pill is drawn stretched to the column width — its frame is both
/// taller and wider than `attachment.size`, and the label is re-centred inside it. Anything baked
/// against the attachment's own size drifts by half that difference on both axes.
public struct InstantPageInlineButtonEmojiItem {
    public let frame: CGRect
    public let emoji: ChatTextCustomEmojiAttribute
    public init(frame: CGRect, emoji: ChatTextCustomEmojiAttribute) {
        self.frame = frame
        self.emoji = emoji
    }
}

public enum InstantPageInlineButtonPresentation: Equatable {
    case pill
    case plain

    public var horizontalPadding: CGFloat {
        return self == .pill ? instantPageInlineButtonHorizontalPadding : 0.0
    }

    public var verticalPadding: CGFloat {
        return self == .pill ? instantPageInlineButtonVerticalPadding : 0.0
    }

    public var drawsChrome: Bool {
        return self == .pill
    }
}

public func instantPageButtonLabelOrigin(attachment: InstantPageInlineButtonAttachment, frame: CGRect) -> CGPoint {
    let labelWidth = attachment.size.width - attachment.horizontalPadding * 2.0
    return CGPoint(
        x: frame.minX + max(attachment.horizontalPadding, (frame.width - labelWidth) / 2.0),
        y: frame.minY + (frame.height - attachment.size.height) / 2.0 + attachment.verticalPadding
    )
}

/// A measured inline button. Mirrors `InstantPageMathAttachment`: the attribute payload carries both
/// the model and the metrics, because the V2 line-breaker raises the line's ascent/descent from the
/// attachment itself and has no `styleStack` with which to re-measure.
public final class InstantPageInlineButtonAttachment: NSObject {
    public let model: InstantPageButtonUIModel
    public let presentation: InstantPageInlineButtonPresentation
    public var button: InstantPageButton { return self.model.button }
    public var isEnabled: Bool { return self.model.isEnabled }
    public var icon: InstantPageButtonUIIcon? { return self.model.icon }
    public var isPressed: Bool = false
    /// The label, already laid out with the surrounding style stack.
    public let labelString: NSAttributedString
    public let size: CGSize
    public let ascent: CGFloat
    public let descent: CGFloat
    public let labelEmojiItems: [InstantPageInlineButtonEmojiItem]
    /// A label that is nothing but one emoji — unicode or custom — draws without the pill fill, so it
    /// reads as the emoji itself rather than a chip around it. Matches iOS.
    public let isEmojiOnly: Bool
    /// The padding this pill was actually measured with — zero for an emoji-only label. Stored so the
    /// label origin and the drawing cannot disagree about it.
    public let horizontalPadding: CGFloat
    public let verticalPadding: CGFloat
    /// True when `maxWidth` forced an ellipsis — i.e. the label did NOT fit at this padding. The row
    /// layout re-measures such a pill at the tight padding to win the difference back as label room;
    /// see `instantPageBlockButtonMeasureV2`.
    public let isTruncated: Bool

    public init(button: InstantPageButton, presentation: InstantPageInlineButtonPresentation, labelString: NSAttributedString, size: CGSize, ascent: CGFloat, descent: CGFloat, labelEmojiItems: [InstantPageInlineButtonEmojiItem], isEmojiOnly: Bool, horizontalPadding: CGFloat, verticalPadding: CGFloat, isTruncated: Bool = false, isEnabled: Bool = true) {
        self.model = InstantPageButtonUIModel(button: button, isEnabled: isEnabled)
        self.presentation = presentation
        self.labelString = labelString
        self.size = size
        self.ascent = ascent
        self.descent = descent
        self.labelEmojiItems = labelEmojiItems
        self.isEmojiOnly = isEmojiOnly
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.isTruncated = isTruncated
    }
}

public let instantPageInlineButtonHorizontalPadding: CGFloat = 7.0
/// Keep the nominal 1pt inset, less half a physical pixel on each edge. At 13pt the label's painted
/// height is an even number of pixels while the unadjusted pill is odd, so a one-pixel-shorter pill
/// gives both the same raster centre without shifting the text baseline.
public var instantPageInlineButtonVerticalPadding: CGFloat {
    return max(0.0, 1.0 - System.pixel / 2.0)
}

/// Button labels carry their own typography rather than inheriting the paragraph's. Fixed sizes, so
/// they do not scale with the Instant View font-size setting; the chat bubble's own text categories
/// are likewise fixed.
public let instantPageInlineButtonFontSize: CGFloat = 13.0
public let instantPageBlockButtonFontSize: CGFloat = 14.0
private let instantPageInlineButtonEmojiScale: CGFloat = 0.75

public func instantPageButtonLabelWithFittedEmoji(_ labelString: NSAttributedString, preserveBodyEmojiSize: Bool = false) -> NSAttributedString {
    struct RunStruct {
        let ascent: CGFloat
        let descent: CGFloat
        let width: CGFloat
    }

    var emojiIndices: [Int] = []
    for index in 0 ..< labelString.length {
        if let item = labelString.attribute(TextInputAttributes.embedded, at: index, effectiveRange: nil) as? InlineStickerItem,
           case .attribute = item.source {
            emojiIndices.append(index)
        }
    }
    guard !emojiIndices.isEmpty else {
        return labelString
    }

    let result = labelString.mutableCopy() as! NSMutableAttributedString
    for index in emojiIndices {
        let font = (labelString.attribute(.font, at: index, effectiveRange: nil) as? NSFont) ?? NSFont.systemFont(ofSize: 17.0)
        let side: CGFloat
        if preserveBodyEmojiSize {
            side = font.ascender - font.descender + 4.0 * font.pointSize / 17.0
        } else {
            side = font.ascender - font.descender
        }
        let extentBuffer = UnsafeMutablePointer<RunStruct>.allocate(capacity: 1)
        extentBuffer.initialize(to: RunStruct(ascent: font.ascender, descent: -font.descender, width: side))
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { pointer in
            pointer.assumingMemoryBound(to: RunStruct.self).deallocate()
        }, getAscent: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.ascent
        }, getDescent: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.descent
        }, getWidth: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.width
        })
        let delegate = CTRunDelegateCreate(&callbacks, extentBuffer)
        result.addAttributes([
            kCTRunDelegateAttributeName as NSAttributedString.Key: delegate as Any
        ], range: NSRange(location: index, length: 1))
    }
    return result
}

/// Apple Color Emoji paints substantially larger than SF text at the same point size on macOS.
/// Scale only Unicode emoji inside inline button labels so their visible bounds match the lettering
/// without increasing the attachment or surrounding line height.
public func instantPageInlineButtonLabelWithInsetEmoji(_ labelString: NSAttributedString) -> NSAttributedString {
    let result = labelString.mutableCopy() as! NSMutableAttributedString
    let string = result.string as NSString
    string.enumerateSubstrings(
        in: NSRange(location: 0, length: string.length),
        options: .byComposedCharacterSequences
    ) { substring, range, _, _ in
        guard let substring,
              substring.isSingleEmoji,
              result.attribute(TextInputAttributes.embedded, at: range.location, effectiveRange: nil) == nil,
              let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
              let scaledFont = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * instantPageInlineButtonEmojiScale) else {
            return
        }
        result.addAttribute(.font, value: scaledFont, range: range)
    }
    return result
}

/// Truncates `labelString` with a tail ellipsis so its ink fits `availableWidth`. Returns the input
/// unchanged when it already fits.
///
/// `truncated` is reported rather than inferred from the returned string: a one-character label
/// replaced by a bare ellipsis keeps the same length, so a length comparison would miss exactly the
/// case that is cut hardest.
private func instantPageButtonTruncatedLabel(_ labelString: NSAttributedString, availableWidth: CGFloat) -> (label: NSAttributedString, truncated: Bool) {
    guard labelString.length != 0, availableWidth > 0.0 else {
        // A zero (or negative) budget cannot fit a non-empty label; an empty one has nothing to cut.
        return (labelString, labelString.length != 0)
    }
    let fullWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(labelString), nil, nil, nil))
    if fullWidth <= availableWidth {
        return (labelString, false)
    }

    let tailAttributes = labelString.attributes(at: labelString.length - 1, effectiveRange: nil)
    let ellipsis = NSAttributedString(string: "\u{2026}", attributes: tailAttributes)
    let ellipsisWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(ellipsis), nil, nil, nil))

    let widthForText = availableWidth - ellipsisWidth
    guard widthForText > 0.0 else {
        return (ellipsis, true)
    }

    let typesetter = CTTypesetterCreateWithAttributedString(labelString)
    let fittingCount = CTTypesetterSuggestClusterBreak(typesetter, 0, Double(widthForText))
    guard fittingCount > 0 else {
        return (ellipsis, true)
    }

    let result = NSMutableAttributedString(attributedString: labelString.attributedSubstring(from: NSRange(location: 0, length: min(fittingCount, labelString.length))))
    result.append(ellipsis)
    return (result, true)
}

/// Measures `labelString` and inflates it by the presentation's padding. The single construction path
/// for both inline `textButton`s and `pageBlockButtonRow` members, so `size`, `ascent` and `descent`
/// mean the same thing in both — the pill drawing relies on that when it centres the label.
///
/// `maxWidth` caps the whole pill. A pill wider than the line it sits on cannot be moved anywhere by
/// the line-breaker's re-break (that path requires the line to hold more than the pill), so the label
/// is truncated with an ellipsis instead of overflowing. Pass nil for no cap.
/// `allowBareEmoji` is true only inside a table cell, where an emoji-only label is drawn as the emoji
/// itself. Everywhere else in running text a button keeps its chip — without one there is nothing to
/// mark it as interactive, and it would read as a stray emoji in the sentence. This has to be decided
/// here rather than at draw time because it also removes the chip's padding, which is measurement.
/// `horizontalPadding` overrides the presentation's own value — the row layout passes it per button
/// (zero for a link-styled pill, the tight fallback for one whose label truncates).
public func instantPageInlineButtonAttachment(button: InstantPageButton, presentation: InstantPageInlineButtonPresentation, labelString: NSAttributedString, maxWidth: CGFloat? = nil, allowBareEmoji: Bool = false, horizontalPadding: CGFloat? = nil, isEnabled: Bool = true) -> InstantPageInlineButtonAttachment {
    let hPad = horizontalPadding ?? presentation.horizontalPadding
    let vPad = presentation.verticalPadding

    // A plain (link-styled) label keeps its emoji at the ordinary body size: it is text in the
    // paragraph, not a pill whose capsule would shave the overhang, and shrinking it would make the
    // very same emoji smaller than one sitting beside it in the surrounding text.
    let preservesBodyEmojiSize = presentation == .plain

    var effectiveLabel = instantPageButtonLabelWithFittedEmoji(
        labelString,
        preserveBodyEmojiSize: preservesBodyEmojiSize
    )
    var isTruncated = false
    if let maxWidth = maxWidth {
        (effectiveLabel, isTruncated) = instantPageButtonTruncatedLabel(effectiveLabel, availableWidth: max(0.0, maxWidth - hPad * 2.0))
    }

    let line = CTLineCreateWithAttributedString(effectiveLabel)
    var labelAscent: CGFloat = 0.0
    var labelDescent: CGFloat = 0.0
    let labelWidth = CGFloat(CTLineGetTypographicBounds(line, &labelAscent, &labelDescent, nil))

    var labelEmojiItems: [InstantPageInlineButtonEmojiItem] = []
    let emojiHeight = labelAscent + labelDescent
    effectiveLabel.enumerateAttribute(TextInputAttributes.embedded, in: NSRange(location: 0, length: effectiveLabel.length), options: [.longestEffectiveRangeNotRequired]) { value, range, _ in
        guard let item = value as? InlineStickerItem, case let .attribute(emoji) = item.source else {
            return
        }
        let lowerX = CTLineGetOffsetForStringIndex(line, range.location, nil)
        let upperX = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
        let x = min(lowerX, upperX)
        let width = abs(upperX - lowerX)
        let height = preservesBodyEmojiSize ? width : emojiHeight
        labelEmojiItems.append(InstantPageInlineButtonEmojiItem(
            frame: CGRect(
                x: x,
                y: preservesBodyEmojiSize ? (emojiHeight - height) / 2.0 : 0.0,
                width: width,
                height: height
            ),
            emoji: emoji
        ))
    }

    let fullRange = NSRange(location: 0, length: effectiveLabel.length)
    let labelText = effectiveLabel.string as NSString
    var emojiRunCount = 0
    var residue = ""
    effectiveLabel.enumerateAttribute(TextInputAttributes.embedded, in: fullRange, options: [.longestEffectiveRangeNotRequired]) { value, range, _ in
        if let item = value as? InlineStickerItem, case .attribute = item.source {
            emojiRunCount += 1
        } else {
            residue += labelText.substring(with: range)
        }
    }
    let residueTrimmed = residue.trimmingCharacters(in: .whitespacesAndNewlines)

    let isPictographicOnly: Bool
    if emojiRunCount == 1 {
        isPictographicOnly = residueTrimmed.isEmpty
    } else if emojiRunCount == 0, residueTrimmed.count == 1 {
        // A plain-text label that is one pictographic grapheme: an emoji, or a symbol-presentation
        // character that reads as a picture all the same (chess pieces, geometric shapes).
        let pictographic = CharacterSet.symbols.union(.nonBaseCharacters)
        isPictographicOnly = residueTrimmed.isSingleEmoji
            || residueTrimmed.unicodeScalars.allSatisfy { pictographic.contains($0) }
    } else {
        isPictographicOnly = false
    }
    let isEmojiOnly = isPictographicOnly && allowBareEmoji

    // No chip means no chip padding: the 7pt each side exists to inset the label from a fill that is
    // no longer drawn. Keeping it made every emoji-only button 14pt wider than its emoji, which in a
    // table is 14pt per column — enough to push an 8-column board past the bubble and arm the
    // horizontal scroller even though the board itself fits.
    let pillHPad = isEmojiOnly ? 0.0 : hPad
    let pillVPad = isEmojiOnly ? 0.0 : vPad
    let pillSize = CGSize(width: labelWidth + pillHPad * 2.0, height: labelAscent + labelDescent + pillVPad * 2.0)

    return InstantPageInlineButtonAttachment(
        button: button,
        presentation: presentation,
        labelString: effectiveLabel,
        size: pillSize,
        ascent: labelAscent + pillVPad,
        descent: labelDescent + pillVPad,
        labelEmojiItems: labelEmojiItems,
        isEmojiOnly: isEmojiOnly,
        horizontalPadding: pillHPad,
        verticalPadding: pillVPad,
        isTruncated: isTruncated,
        isEnabled: isEnabled
    )
}

/// Fill and label colours for a button pill, sourced from `InstantPageTheme` (what the V2 renderer is
/// handed). `isInline` distinguishes an inline `RichText.textButton` pill from a block-level
/// `pageBlockButtonRow` pill: an inline pill sits inside running text and takes a lighter fill.
/// `withMultipliedAlpha` reads components via `getRed:green:blue:alpha:`, which RAISES on a non-RGB
/// colorspace. Theme colours are not guaranteed to be RGB — `.white` and `.black` are Generic Gray —
/// so every alpha multiplication here converts first.
private func multipliedAlpha(_ color: NSColor, _ alpha: CGFloat) -> NSColor {
    return (color.usingColorSpace(.sRGB) ?? color).withMultipliedAlpha(alpha)
}

private func instantPageButtonPillColors(
    _ color: ReplyMarkupButton.Style.Color?,
    theme: InstantPageTheme,
    isInline: Bool,
    isDisabled: Bool,
    isLink: Bool
) -> (fill: NSColor?, label: NSColor) {
    // A link-styled ROW button is chrome-less: no fill, the page's link colour for the label — the
    // treatment the INLINE path reaches by rendering plain link text instead of a pill. It wins over
    // the background bits, matching the `link > bg_primary > bg_danger > bg_success` precedence.
    if isLink {
        let label = theme.linkColor
        return (nil, isDisabled ? multipliedAlpha(label, instantPageButtonDisabledAlpha) : label)
    }
    let fill: NSColor
    let label: NSColor
    switch color {
    case .none:
        if isInline {
            fill = theme.panelBackgroundColor
            label = theme.panelAccentColor
        } else {
            fill = theme.tableHeaderColor
            label = theme.panelPrimaryColor
        }
    case .some(.primary):
        fill = theme.checkboxFill
        label = theme.checkboxForeground
    case .some(.danger):
        fill = multipliedAlpha(theme.buttonDangerColor, 0.15)
        label = theme.buttonDangerColor
    case .some(.success):
        fill = multipliedAlpha(theme.buttonSuccessColor, 0.15)
        label = theme.buttonSuccessColor
    }
    if isDisabled {
        return (fill, multipliedAlpha(label, instantPageButtonDisabledAlpha))
    }
    return (fill, label)
}

/// How far a disabled pill's label is faded. Also applied as layer opacity to any custom emoji in the
/// label: the tint above only reaches monochrome emoji, so a full-colour one would otherwise stay at
/// full strength inside a dimmed pill.
public let instantPageButtonDisabledAlpha: CGFloat = 0.4

public func instantPageButtonColors(
    _ attachment: InstantPageInlineButtonAttachment,
    theme: InstantPageTheme,
    isInline: Bool,
    isDisabled: Bool
) -> (fill: NSColor?, label: NSColor) {
    if attachment.presentation == .plain {
        let label = attachment.labelString.length > 0
            ? (attachment.labelString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            : nil
        let color = label ?? theme.panelAccentColor
        return (nil, isDisabled ? multipliedAlpha(color, instantPageButtonDisabledAlpha) : color)
    }
    let colors = instantPageButtonPillColors(
        attachment.button.color,
        theme: theme,
        isInline: isInline,
        isDisabled: isDisabled,
        isLink: attachment.button.isLink
    )
    return (colors.fill, colors.label)
}

/// The trailing corner icon for a button's action, matching the set `ReplyMarkupNode.redraw()` puts on
/// bot-keyboard buttons — so a page button that opens a link, a web app or copies text is marked the
/// same way as its reply-markup equivalent.
///
/// The returned image is used as an alpha MASK and re-tinted to the pill's label colour at draw time:
/// the cached originals are precomposed with `chatServiceItemTextColor`, which is right on the blurred
/// service background reply markups sit on but wrong on a pill whose label colour varies per style.
private func instantPageButtonIcon(_ action: ReplyMarkupButtonAction) -> InstantPageButtonUIIcon? {
    switch action {
    case let .url(url):
        return url.isSingleEmoji ? nil : .url
    case .urlAuth:
        return .url
    case .switchInline:
        return .share
    case .openUserProfile:
        return .profile
    case .openWebApp, .openWebView:
        return .web
    case .copyText:
        return .copy
    case .payment:
        return .payment
    default:
        return nil
    }
}

public func instantPageButtonActionIcon(_ icon: InstantPageButtonUIIcon?) -> CGImage? {
    guard let icon else {
        return nil
    }
    let presentation = theme
    switch icon {
    case .url:
        return presentation.chat.chatActionUrl(theme: presentation)
    case .share:
        return presentation.chat.chatActionShare(theme: presentation)
    case .profile:
        return presentation.chat.chatActionProfile(theme: presentation)
    case .web:
        return presentation.chat.chatActionWebUrl(theme: presentation)
    case .copy:
        return presentation.chat.chatActionCopy(theme: presentation)
    case .payment:
        return presentation.chat.chatInvoiceAction(theme: presentation)
    }
}

/// Inset of the action icon from the pill's top-right corner. Reply-markup buttons use a flat 5pt, but
/// they have a small corner radius; a pill is a capsule (radius = height/2), so a 5pt inset puts the
/// icon inside the curve and clips it. Scaled off the height instead, which keeps it clear of the arc
/// at any pill size.
public func instantPageButtonIconInsets(pillHeight: CGFloat) -> (horizontal: CGFloat, vertical: CGFloat) {
    return (horizontal: max(5.0, round(pillHeight * 0.3)), vertical: max(4.0, round(pillHeight * 0.2)))
}

/// Width a block pill must keep clear on its trailing edge so a centred label cannot run under the
/// corner icon.
public func instantPageButtonIconAllowance(_ button: InstantPageButton, pillHeight: CGFloat) -> CGFloat {
    guard let icon = instantPageButtonActionIcon(InstantPageButtonUIModel(button: button).icon) else {
        return 0.0
    }
    return CGFloat(icon.width) / System.backingScale + instantPageButtonIconInsets(pillHeight: pillHeight).horizontal * 2.0
}

public func instantPageDrawButton(
    _ attachment: InstantPageInlineButtonAttachment,
    in frame: CGRect,
    context: CGContext,
    theme: InstantPageTheme,
    isInline: Bool
) {
    let isDisabled = !attachment.isEnabled
    let colors = instantPageButtonColors(attachment, theme: theme, isInline: isInline, isDisabled: isDisabled)

    context.saveGState()

    // Press dims the WHOLE pill — fill, label and icon together — to 80% so the bubble shows through.
    // Done as a transparency layer rather than per-element alpha so the label keeps its full contrast
    // against the fill instead of muddying into it. Neither a neutral highlight colour (which makes a
    // solid `.primary` pill lose its identity) nor a black/white overlay (a grey wash) preserves hue
    // the way this does.
    let isHighlighted = attachment.isPressed && !isDisabled
    if isHighlighted {
        context.setAlpha(0.8)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
    }

    if let fillColor = colors.fill, !attachment.isEmojiOnly {
        let radius = frame.height / 2.0
        let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(path)
        context.setFillColor(fillColor.cgColor)
        context.fillPath()
    }

    // The label is recoloured here rather than at construction: `attributedStringForRichText` bakes the
    // *paragraph* colour and has no `InstantPageTheme` to resolve a button colour with.
    let displayLabel = attachment.labelString.mutableCopy() as! NSMutableAttributedString
    if displayLabel.length != 0 {
        let full = NSRange(location: 0, length: displayLabel.length)
        displayLabel.addAttribute(.foregroundColor, value: colors.label, range: full)
        displayLabel.enumerateAttribute(TextInputAttributes.embedded, in: full, options: [.longestEffectiveRangeNotRequired]) { value, range, _ in
            if value is InlineStickerItem {
                displayLabel.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            }
        }
    }

    let labelOrigin = instantPageButtonLabelOrigin(attachment: attachment, frame: frame)
    let x = labelOrigin.x
    let typographicY = labelOrigin.y + attachment.ascent - attachment.verticalPadding
    let labelLine = CTLineCreateWithAttributedString(displayLabel)
    context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
    context.textPosition = .zero
    let inkBounds = CTLineGetImageBounds(labelLine, context)
    let y: CGFloat
    if !inkBounds.isNull, !inkBounds.isInfinite, inkBounds.height > 0.0 {
        y = frame.midY + inkBounds.midY
    } else {
        y = typographicY
    }
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(labelLine, context)

    if displayLabel.length != 0 {
        let strikethroughY = floor(frame.midY)
        displayLabel.enumerateAttribute(.instantPageStrikethroughAttribute, in: NSRange(location: 0, length: displayLabel.length), options: []) { value, range, _ in
            guard value != nil else { return }
            let lowerX = CTLineGetOffsetForStringIndex(labelLine, range.location, nil)
            let upperX = CTLineGetOffsetForStringIndex(labelLine, range.location + range.length, nil)
            let startX = x + min(lowerX, upperX)
            let width = abs(upperX - lowerX)
            guard width > 0.0 else { return }
            context.setFillColor(colors.label.cgColor)
            context.fill(CGRect(x: startX, y: strikethroughY, width: width, height: 1.0))
        }
    }

    // Action icon, block pills only. An inline pill hugs its label, so a corner icon would sit on top
    // of the text; block pills are stretched to a column width and have the room, which is also where
    // reply-markup buttons put theirs.
    if attachment.presentation.drawsChrome, !isInline, let icon = instantPageButtonActionIcon(attachment.icon) {
        let iconSize = CGSize(width: CGFloat(icon.width) / System.backingScale,
                              height: CGFloat(icon.height) / System.backingScale)
        let insets = instantPageButtonIconInsets(pillHeight: frame.height)
        let iconRect = CGRect(
            x: frame.maxX - iconSize.width - insets.horizontal,
            y: frame.minY + insets.vertical,
            width: iconSize.width,
            height: iconSize.height
        )
        context.saveGState()
        // Re-tint: clip to the icon's alpha and fill with the label colour, rather than drawing the
        // cached image, whose baked colour belongs to the service background.
        context.translateBy(x: iconRect.minX, y: iconRect.maxY)
        context.scaleBy(x: 1.0, y: -1.0)
        context.clip(to: CGRect(origin: .zero, size: iconSize), mask: icon)
        if isDisabled {
            context.setAlpha(0.0)
        }
        context.setFillColor(colors.label.cgColor)
        context.fill(CGRect(origin: .zero, size: iconSize))
        context.restoreGState()
    }

    if isHighlighted {
        context.endTransparencyLayer()
    }
    context.restoreGState()
}
