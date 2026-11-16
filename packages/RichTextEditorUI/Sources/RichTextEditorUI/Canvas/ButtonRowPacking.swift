#if canImport(AppKit)
import AppKit
import CoreText
import RichTextEditorCore

/// A transcription of the iOS `richTextPackButtonRow` (itself a pinned copy of the renderer's button
/// row layout), parameterized by `RichTextButtonMetrics` so it packs with the macOS V2 values.
///
/// The STRUCTURE deliberately mirrors the iOS original rather than being reorganised:
/// - `justify` splits the available width into equal columns, chunked at `maximumButtonsPerRow`.
/// - `left` / `center` / `right` hug the label and wrap greedily, still capped per row.
/// - EACH WRAPPED ROW is aligned on its own width, so a short last row re-aligns on itself.
/// - One RTL rule covers all four modes: a row lays out in the page's READING direction, so `left`
///   means leading (the right edge when `isRTL`) and the first pill sits at the reading start.

/// Transcription of `Strings.isSingleEmoji` (the check behind the renderer's `.url` icon exemption
/// and the inline label emoji inset): one rendered glyph AND at least one emoji scalar. The package
/// cannot import `Strings`, so keep this in step with `packages/Strings` if that rule ever changes.
func richTextStringIsSingleEmoji(_ string: String) -> Bool {
    guard !string.isEmpty else { return false }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string))
    guard CTLineGetGlyphCount(line) == 1 else { return false }
    return string.unicodeScalars.contains { scalar in
        if scalar.properties.isEmoji && scalar.properties.isEmojiPresentation { return true }
        switch scalar.value {
        case 0x1F600...0x1F64F, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF, 0x1F1E6...0x1F1FF,
             0xE0020...0xE007F, 0xFE00...0xFE0F, 0x1F900...0x1F9FF, 0x1F018...0x1F0F5,
             0x1F200...0x1F270, 65024...65039, 9100...9300, 8400...8447, 0x1F004, 0x1F18E,
             0x1F191...0x1F19A, 0x1F5E8, 0x1FA70...0x1FA73, 0x1FA78...0x1FA7A, 0x1FA80...0x1FA82,
             0x1FA90...0x1FA95, 0x1F382, 0x1FAF1, 0x1FAF2:
            return true
        case 0x2603, 0x265F, 0x267E, 0x2692, 0x26C4, 0x26C8, 0x26CE, 0x26CF, 0x26D1...0x26D3,
             0x26E9, 0x26F0...0x26F9, 0x2705, 0x270A, 0x270B, 0x2728, 0x274E, 0x2753...0x2755,
             0x274C, 0x2795...0x2797, 0x27B0, 0x27BF:
            return true
        default:
            return false
        }
    }
}

/// The room the renderer reserves on EACH side of this pill for its corner action icon, or 0 for an
/// icon-less pill. Transcribes `instantPageButtonIconAllowance` + the `InstantPageButtonUIModel` icon
/// rules: url/copy draw an 8pt icon (reserve 28 at pill height 32), share/profile a 10pt one (30); a
/// single-emoji URL draws none; a DISABLED button labelled exactly "Open"/"Profile" still gets its
/// icon. `.unsupported` is an opaque action blob — which icon (if any) the renderer would pick is
/// unknowable here, so it keeps the flat `blockIconReserve` approximation (url/copy's 28, the most
/// common arm). The editor draws NO badge, but it must reserve the same room or its labels would
/// ellipsise at a different point than the sent message's.
@available(macOS 12, *)
func richTextButtonBadgeReserve(_ button: ButtonRef, metrics: RichTextButtonMetrics) -> CGFloat {
    let inset = max(5.0, (metrics.blockRowHeight * 0.3).rounded())
    let smallIconReserve = 8.0 + inset * 2.0
    let largeIconReserve = 10.0 + inset * 2.0
    switch button.action {
    case let .url(url):
        return richTextStringIsSingleEmoji(url) ? 0.0 : smallIconReserve
    case .copyText:
        return smallIconReserve
    case .userProfile:
        return largeIconReserve
    case .disabled:
        switch button.labelText {
        case "Open": return smallIconReserve
        case "Profile": return largeIconReserve
        default: return 0.0
        }
    case .unsupported:
        return metrics.blockIconReserve
    }
}

/// Per-side inner padding for a row pill, and the tighter value it falls back to when its label does
/// not fit there. A link button is chrome-less at 0 in both cases; `min` guarantees the fallback can
/// never hand a button MORE room than it started with.
@available(macOS 12, *)
private func rowButtonPadding(_ button: ButtonRef, metrics: RichTextButtonMetrics) -> CGFloat {
    return button.isLink ? 0.0 : metrics.blockHorizontalPadding
}

@available(macOS 12, *)
private func rowButtonMinimumPadding(_ button: ButtonRef, metrics: RichTextButtonMetrics) -> CGFloat {
    return min(rowButtonPadding(button, metrics: metrics), metrics.blockMinimumHorizontalPadding)
}

/// Room a badge-bearing pill keeps clear on EACH side BEYOND `padding`. The attachment builder already
/// subtracts `padding` per side from the cap it is handed, so only the difference is taken off on top
/// of it — making the total clearance `max(padding, reserve)`, never their sum.
@available(macOS 12, *)
private func rowButtonExtraSideInset(_ button: ButtonRef, padding: CGFloat, metrics: RichTextButtonMetrics) -> CGFloat {
    let reserve = richTextButtonBadgeReserve(button, metrics: metrics)
    guard reserve > 0.0 else {
        return 0.0
    }
    return max(0.0, reserve - padding)
}

/// Measures one row pill against the width its frame will occupy, choosing its padding: comfortable
/// when the label fits there, tight when it does not.
///
/// **A pill's inner padding is a preference, not a constraint.** The two-try shape is deliberate over
/// solving for the padding directly: truncation is decided by the typesetter's cluster break, not by a
/// width formula we could invert. The tight retry at `blockMinimumHorizontalPadding` (6.0) mirrors the
/// renderer's `instantPageBlockButtonMeasureV2` fallback, winning the padding difference back as label
/// room for a truncating label.
@available(macOS 12, *)
private func richTextMeasureRowButton(
    button: ButtonRef,
    pillWidth: CGFloat,
    metrics: RichTextButtonMetrics,
    measure: (ButtonRef, CGFloat?, CGFloat) -> ButtonTextAttachment
) -> (attachment: ButtonTextAttachment, extraSideInset: CGFloat) {
    func measured(padding: CGFloat) -> (attachment: ButtonTextAttachment, extraSideInset: CGFloat) {
        let extra = rowButtonExtraSideInset(button, padding: padding, metrics: metrics)
        return (measure(button, max(0.0, pillWidth - extra * 2.0), padding), extra)
    }
    let comfortable = rowButtonPadding(button, metrics: metrics)
    let minimum = rowButtonMinimumPadding(button, metrics: metrics)
    let result = measured(padding: comfortable)
    guard result.attachment.isTruncated, minimum < comfortable else {
        return result
    }
    return measured(padding: minimum)
}

/// Where a row's content starts within the available width, given its leftover space.
@available(macOS 12, *)
private func rowSlackOffset(alignment: ButtonRowAlignment, slack: CGFloat, isRTL: Bool) -> CGFloat {
    switch alignment {
    case .justify:
        return 0.0
    case .left:
        return isRTL ? slack : 0.0
    case .center:
        return slack / 2.0
    case .right:
        return isRTL ? 0.0 : slack
    }
}

/// Lays out one button row. Frames come back in MODEL order (frame *i* belongs to pill *i*); reading
/// direction lives in the frames themselves.
///
/// `measure` builds a pill attachment at a given cap AND per-side horizontal padding — supplied by the
/// caller so this file stays free of the mapper.
@available(macOS 12, *)
func richTextPackButtonRow(
    buttons: [ButtonRef],
    alignment: ButtonRowAlignment,
    availableWidth: CGFloat,
    metrics: RichTextButtonMetrics,
    isRTL: Bool,
    measure: (ButtonRef, CGFloat?, CGFloat) -> ButtonTextAttachment
) -> (attachments: [ButtonTextAttachment], frames: [CGRect], totalHeight: CGFloat) {
    guard !buttons.isEmpty, availableWidth > 0.0 else {
        return ([], [], 0.0)
    }
    switch alignment {
    case .justify:
        return packJustified(buttons: buttons, availableWidth: availableWidth, metrics: metrics,
                             isRTL: isRTL, measure: measure)
    case .left, .center, .right:
        return packHugging(buttons: buttons, alignment: alignment, availableWidth: availableWidth,
                           metrics: metrics, isRTL: isRTL, measure: measure)
    }
}

/// Equal columns filling the width, wrapping at the schema's cap.
@available(macOS 12, *)
private func packJustified(
    buttons: [ButtonRef],
    availableWidth: CGFloat,
    metrics: RichTextButtonMetrics,
    isRTL: Bool,
    measure: (ButtonRef, CGFloat?, CGFloat) -> ButtonTextAttachment
) -> (attachments: [ButtonTextAttachment], frames: [CGRect], totalHeight: CGFloat) {
    var attachments: [ButtonTextAttachment] = []
    var frames: [CGRect] = []
    var y: CGFloat = 0.0
    var index = 0
    while index < buttons.count {
        let upper = min(index + metrics.maximumButtonsPerRow, buttons.count)
        let rowButtons = Array(buttons[index ..< upper])
        // The renderer clamps the gap at degenerate widths (`min(spacing, availableWidth / gapCount)`)
        // so spacing can never eat the whole row; without it pill widths clamp to 0 where the sent
        // message still distributes width.
        let gapCount = max(0, rowButtons.count - 1)
        let spacing = gapCount == 0 ? 0.0 : min(metrics.blockSpacing, availableWidth / CGFloat(gapCount))
        let totalSpacing = spacing * CGFloat(gapCount)
        let buttonWidth = max(0.0, (availableWidth - totalSpacing) / CGFloat(rowButtons.count))
        for (position, button) in rowButtons.enumerated() {
            // Cap the label at the column it will be stretched to. The pill centres its label, so the
            // clearance is kept on BOTH sides — otherwise a long centred label runs under the badge.
            attachments.append(richTextMeasureRowButton(button: button, pillWidth: buttonWidth,
                                                        metrics: metrics, measure: measure).attachment)
            let column = isRTL ? (rowButtons.count - 1 - position) : position
            let x = CGFloat(column) * (buttonWidth + spacing)
            frames.append(CGRect(x: x, y: y, width: buttonWidth, height: metrics.blockRowHeight))
        }
        y += metrics.blockRowHeight + metrics.blockSpacing
        index += metrics.maximumButtonsPerRow
    }
    return (attachments, frames, max(0.0, y - metrics.blockSpacing))
}

/// Left / centre / right: every pill hugs its label, rows fill greedily, each row placed at its own
/// origin (a short last row re-aligns on itself).
@available(macOS 12, *)
private func packHugging(
    buttons: [ButtonRef],
    alignment: ButtonRowAlignment,
    availableWidth: CGFloat,
    metrics: RichTextButtonMetrics,
    isRTL: Bool,
    measure: (ButtonRef, CGFloat?, CGFloat) -> ButtonTextAttachment
) -> (attachments: [ButtonTextAttachment], frames: [CGRect], totalHeight: CGFloat) {
    // Pass 1 — measure each pill at its natural width, capped so even the longest label fits
    // `availableWidth` on its own (the builder ellipsises past the cap). Pass 2 depends on that: a
    // row can then never overflow, and an over-long single label truncates instead.
    let measured: [(attachment: ButtonTextAttachment, width: CGFloat)] = buttons.map { button in
        let (attachment, extra) = richTextMeasureRowButton(button: button, pillWidth: availableWidth,
                                                           metrics: metrics, measure: measure)
        return (attachment, min(availableWidth, attachment.size.width + extra * 2.0))
    }

    // Pass 2a — greedy packing, still capped at the schema's per-row maximum.
    var rows: [[Int]] = []
    var currentRow: [Int] = []
    var currentWidth: CGFloat = 0.0
    for index in 0 ..< measured.count {
        let width = measured[index].width
        if !currentRow.isEmpty {
            let projected = currentWidth + metrics.blockSpacing + width
            if projected > availableWidth || currentRow.count >= metrics.maximumButtonsPerRow {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0.0
            }
        }
        currentWidth = currentRow.isEmpty ? width : currentWidth + metrics.blockSpacing + width
        currentRow.append(index)
    }
    if !currentRow.isEmpty {
        rows.append(currentRow)
    }

    // Pass 2b — place each row at its own origin.
    var frames = [CGRect](repeating: .zero, count: measured.count)
    var y: CGFloat = 0.0
    for row in rows {
        let rowWidth = row.reduce(0.0) { $0 + measured[$1].width }
            + metrics.blockSpacing * CGFloat(max(0, row.count - 1))
        let slack = max(0.0, availableWidth - rowWidth)
        var x = rowSlackOffset(alignment: alignment, slack: slack, isRTL: isRTL)
        // The first button sits at the reading start, so on an RTL page the pills run right-to-left.
        let visualOrder = isRTL ? Array(row.reversed()) : row
        for index in visualOrder {
            frames[index] = CGRect(x: x, y: y, width: measured[index].width, height: metrics.blockRowHeight)
            x += measured[index].width + metrics.blockSpacing
        }
        y += metrics.blockRowHeight + metrics.blockSpacing
    }
    return (measured.map(\.attachment), frames, max(0.0, y - metrics.blockSpacing))
}
#endif
