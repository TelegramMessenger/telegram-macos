import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import TelegramUtils
import TelegramTheme
import ColorPalette
import Localization
import MessageTextUtils


public struct InstantPageV2Layout {
    public let contentSize: CGSize
    public let items: [InstantPageV2LaidOutItem]
    public let detailsIndices: [Int]

    public init(contentSize: CGSize, items: [InstantPageV2LaidOutItem], detailsIndices: [Int]) {
        self.contentSize = contentSize
        self.items = items
        self.detailsIndices = detailsIndices
    }

    public func allMedias() -> [InstantPageMedia] {
        var result: [InstantPageMedia] = []
        InstantPageV2Layout.collectMedias(in: self.items, into: &result)
        return result
    }

    public func collapsedDetailsIndex(forQuote text: String, range: NSRange? = nil) -> Int? {
        guard !text.isEmpty else { return nil }
        var blocks: [NSAttributedString] = []
        var collapsedParents: [Int?] = []
        func append(_ text: NSAttributedString, collapsedParent: Int?) {
            blocks.append(text)
            collapsedParents.append(collapsedParent)
        }
        func collect(_ layout: InstantPageV2Layout, collapsedParent: Int?) {
            for item in layout.items {
                switch item {
                case let .text(text):
                    append(text.textItem.attributedString, collapsedParent: collapsedParent)
                case let .codeBlock(code):
                    append(code.textItem.attributedString, collapsedParent: collapsedParent)
                case let .formula(formula):
                    append(NSAttributedString(string: formula.attachment.latex), collapsedParent: collapsedParent)
                case let .details(details):
                    append(details.titleTextItem.attributedString, collapsedParent: collapsedParent)
                    if let inner = details.innerLayout ?? details.layoutCollapsedContent?() {
                        collect(inner, collapsedParent: collapsedParent ?? (details.isExpanded ? nil : details.index))
                    }
                case let .table(table):
                    if let title = table.titleSubLayout {
                        collect(title, collapsedParent: collapsedParent)
                    }
                    for cell in table.cells {
                        if let content = cell.subLayout {
                            collect(content, collapsedParent: collapsedParent)
                        }
                    }
                default:
                    break
                }
            }
        }
        collect(self, collapsedParent: nil)
        let ranges = instantPageQuoteRanges(in: blocks, text: text, range: range)
        for (range, parent) in zip(ranges, collapsedParents) {
            if range != nil, let parent {
                return parent
            }
        }
        return nil
    }

    private static func collectMedias(in items: [InstantPageV2LaidOutItem], into result: inout [InstantPageMedia]) {
        for item in items {
            switch item {
            case let .mediaImage(m):      result.append(m.media)
            case let .mediaVideo(m):      result.append(m.media)
            case let .mediaMap(m):        result.append(m.media)
            case let .mediaCoverImage(m): result.append(m.media)
            case let .mediaPlaceholder(p): result.append(contentsOf: p.slideshowMedias)
            case let .details(d):
                if let inner = d.innerLayout {
                    collectMedias(in: inner.items, into: &result)
                }
            case let .table(t):
                if let title = t.titleSubLayout {
                    collectMedias(in: title.items, into: &result)
                }
                for cell in t.cells {
                    if let sub = cell.subLayout {
                        collectMedias(in: sub.items, into: &result)
                    }
                }
            default:
                continue
            }
        }
    }
}

public enum InstantPageV2LaidOutItem {
    case text(InstantPageV2TextItem)
    case codeBlock(InstantPageV2CodeBlockItem)
    case divider(InstantPageV2DividerItem)
    case listMarker(InstantPageV2ListMarkerItem)
    case blockQuoteBar(InstantPageV2BarItem)
    case blockQuoteDecoration(InstantPageV2BlockQuoteDecorationItem)
    case shape(InstantPageV2ShapeItem)
    case pullQuoteMark(InstantPageV2PullQuoteMarkItem)
    case mediaPlaceholder(InstantPageV2MediaPlaceholderItem)
    case details(InstantPageV2DetailsItem)
    case table(InstantPageV2TableItem)
    case anchor(InstantPageV2AnchorItem)
    case mediaImage(InstantPageV2MediaImageItem)
    case mediaVideo(InstantPageV2MediaVideoItem)
    case mediaMap(InstantPageV2MediaMapItem)
    case mediaCoverImage(InstantPageV2MediaCoverImageItem)
    case formula(InstantPageV2FormulaItem)
    case buttonRow(InstantPageV2ButtonRowItem)
    case unsupported(InstantPageV2UnsupportedItem)

    public var frame: CGRect {
        switch self {
        case let .text(item):                   return item.frame
        case let .codeBlock(item):              return item.frame
        case let .divider(item):                return item.frame
        case let .listMarker(item):             return item.frame
        case let .blockQuoteBar(item):          return item.frame
        case let .blockQuoteDecoration(item):   return item.frame
        case let .shape(item):                  return item.frame
        case let .pullQuoteMark(item):          return item.frame
        case let .mediaPlaceholder(item):       return item.frame
        case let .details(item):                return item.frame
        case let .table(item):                  return item.frame
        case let .anchor(item):                 return item.frame
        case let .mediaImage(item):             return item.frame
        case let .mediaVideo(item):             return item.frame
        case let .mediaMap(item):               return item.frame
        case let .mediaCoverImage(item):        return item.frame
        case let .formula(item):                return item.frame
        case let .buttonRow(item):              return item.frame
        case let .unsupported(item):            return item.frame
        }
    }

    public func offsetBy(_ delta: CGPoint) -> InstantPageV2LaidOutItem {
        switch self {
        case var .text(item):                   item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .text(item)
        case var .codeBlock(item):              item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .codeBlock(item)
        case var .divider(item):                item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .divider(item)
        case var .listMarker(item):             item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .listMarker(item)
        case var .blockQuoteBar(item):          item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .blockQuoteBar(item)
        case var .blockQuoteDecoration(item):   item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .blockQuoteDecoration(item)
        case var .shape(item):                  item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .shape(item)
        case var .pullQuoteMark(item):          item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .pullQuoteMark(item)
        case var .mediaPlaceholder(item):       item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .mediaPlaceholder(item)
        case var .details(item):                item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .details(item)
        case var .table(item):                  item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .table(item)
        case var .anchor(item):                 item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .anchor(item)
        case var .mediaImage(item):             item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .mediaImage(item)
        case var .mediaVideo(item):             item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .mediaVideo(item)
        case var .mediaMap(item):               item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .mediaMap(item)
        case var .mediaCoverImage(item):        item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .mediaCoverImage(item)
        case var .formula(item):                item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .formula(item)
        case var .buttonRow(item):              item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .buttonRow(item)
        case var .unsupported(item):            item.frame = item.frame.offsetBy(dx: delta.x, dy: delta.y); return .unsupported(item)
        }
    }
}

public struct InstantPageV2UnsupportedItem {
    public var frame: CGRect
    public let layout: any InstantPageV2UnsupportedBandLayout
}

public struct InstantPageV2BlockQuoteDecorationItem {
    public var frame: CGRect           // whole block area
    public let color: NSColor          // accent (used for bar, icon, background tint)
    public let backgroundCornerRadius: CGFloat
    public let barWidth: CGFloat
    public let drawsIcon: Bool
    public var rtl: Bool = false       // bar on the right, icon on the left
}

public struct InstantPageV2TextItem {
    public var frame: CGRect
    public let textItem: InstantPageTextItem
    public var isThinking: Bool = false
}

public struct InstantPageV2CodeBlockItem {
    public var frame: CGRect
    public let backgroundColor: NSColor
    public let cornerRadius: CGFloat
    public let textItem: InstantPageTextItem
    public let inset: NSEdgeInsets
    public let headerText: String?
    public let headerHeight: CGFloat
    public let headerColor: NSColor
}

public struct InstantPageV2DividerItem {
    public var frame: CGRect
    public let color: NSColor
}

public enum InstantPageV2ListMarkerKind {
    case bullet
    case number(String)
    case checklist(checked: Bool, colors: InstantPageV2CheckboxColors)
}

public struct InstantPageV2CheckboxColors {
    public let background: NSColor
    public let foreground: NSColor
    public let border: NSColor
}

public struct InstantPageV2ListMarkerItem {
    public var frame: CGRect
    public let kind: InstantPageV2ListMarkerKind
    public let color: NSColor
}

public struct InstantPageV2BarItem {
    public var frame: CGRect
    public let color: NSColor
    public let cornerRadius: CGFloat
}

public enum InstantPageV2ShapeKind {
    case roundedRect(cornerRadius: CGFloat)
    case line(thickness: CGFloat)
}

public struct InstantPageV2ShapeItem {
    public var frame: CGRect
    public let kind: InstantPageV2ShapeKind
    public let color: NSColor
}

public enum InstantPageV2PullQuoteMarkKind {
    case open
    case close
}

public struct InstantPageV2PullQuoteMarkItem {
    public var frame: CGRect
    public let color: NSColor
    public let kind: InstantPageV2PullQuoteMarkKind
}

public enum InstantPageV2MediaPlaceholderKind {
    case image
    case video
    case audio
    case webEmbed
    case postEmbed
    case collage
    case slideshow
    case channelBanner
    case map
    case relatedArticles
}

public struct InstantPageV2MediaPlaceholderItem {
    public var frame: CGRect
    public let kind: InstantPageV2MediaPlaceholderKind
    public let cornerRadius: CGFloat
    public var slideshowMedias: [InstantPageMedia] = []
    public var webPage: TelegramMediaWebpage? = nil
}

public struct InstantPageV2MediaImageItem {
    public var frame: CGRect
    public let cornerRadius: CGFloat
    public let media: InstantPageMedia
    public let webPage: TelegramMediaWebpage
    public let attributes: [InstantPageImageAttribute]
    public var spoiler: Bool = false
}

public struct InstantPageV2MediaVideoItem {
    public var frame: CGRect
    public let cornerRadius: CGFloat
    public let media: InstantPageMedia
    public let webPage: TelegramMediaWebpage
    public let attributes: [InstantPageImageAttribute]
    public let isFile: Bool
    public var spoiler: Bool = false
}

public struct InstantPageV2MediaMapItem {
    public var frame: CGRect
    public let cornerRadius: CGFloat
    public let media: InstantPageMedia
    public let webPage: TelegramMediaWebpage
    public let attributes: [InstantPageImageAttribute]
}

public struct InstantPageV2MediaCoverImageItem {
    public var frame: CGRect
    public let cornerRadius: CGFloat
    public let media: InstantPageMedia
    public let webPage: TelegramMediaWebpage
    public let attributes: [InstantPageImageAttribute]
}

public struct InstantPageV2DetailsItem {
    public var frame: CGRect
    public let index: Int
    public let sideInset: CGFloat
    public let titleTextItem: InstantPageTextItem
    public let titleFrame: CGRect
    public let isExpanded: Bool
    public let innerLayout: InstantPageV2Layout?
    public let defaultExpanded: Bool
    public let rtl: Bool
    var layoutCollapsedContent: (() -> InstantPageV2Layout)? = nil
}

public enum InstantPageV2TableVerticalAlignment {
    case top, middle, bottom
}

public struct InstantPageV2TableCell {
    public let frame: CGRect
    public let isHeader: Bool
    public let horizontalAlignment: NSTextAlignment
    public let verticalAlignment: InstantPageV2TableVerticalAlignment
    public let backgroundColor: NSColor?
    public let subLayout: InstantPageV2Layout?
}

public struct InstantPageV2TableItem {
    public var frame: CGRect
    public let titleSubLayout: InstantPageV2Layout?
    public let titleFrame: CGRect?
    public let contentSize: CGSize
    public let cells: [InstantPageV2TableCell]
    public let horizontalLines: [CGRect]
    public let verticalLines: [CGRect]
    public let outerFrame: CGRect
    public let outerCornerRadius: CGFloat
    public let bordered: Bool
    public let striped: Bool
    public let borderColor: NSColor

    public var isHorizontallyScrollable: Bool {
        return self.contentSize.width - self.frame.width > System.pixel
    }
}

public struct InstantPageV2AnchorItem {
    public var frame: CGRect
    public let name: String
}

public struct InstantPageV2FormulaItem {
    public var frame: CGRect
    public let attachment: InstantPageMathAttachment
    public let isScrollable: Bool
    public let imageFrame: CGRect
    public let scrollContentSize: CGSize
}

public struct InstantPageV2ButtonRowItem {
    public var frame: CGRect
    public let buttons: [(attachment: InstantPageInlineButtonAttachment, frame: CGRect)]
}


public func layoutInstantPageV2(
    webpage: TelegramMediaWebpage,
    instantPage: InstantPage,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    theme: InstantPageTheme,
    toggledDetails: Set<Int> = [],
    fitToWidth: Bool = true,
    computeRevealCharacterRects: Bool = false,
    codeSyntaxThemeKeys: [String: NSColor] = [:],
    codeTextColor: NSColor? = nil,
    collageMosaic: (([Media], CGFloat) -> [CGRect])? = nil,
    mediaBleed: CGFloat = 0,
    unsupportedStyle: (any InstantPageV2UnsupportedBandStyle)? = nil,
    buttonsEnabled: Bool = true
) -> InstantPageV2Layout {
    guard case let .Loaded(loadedContent) = webpage.content else {
        return InstantPageV2Layout(contentSize: .zero, items: [], detailsIndices: [])
    }

    var media = instantPage.media.mapValues { $0._asMedia() }
    if let image = loadedContent.image, let id = image.id {
        media[id] = image
    }
    if let file = loadedContent.file, let id = file.id {
        media[id] = file
    }

    var context = LayoutContextV2(
        theme: theme,
        webpage: webpage,
        media: media,
        rtl: instantPage.rtl,
        fitToWidth: fitToWidth,
        mediaIndexCounter: 0,
        detailsIndexCounter: 0,
        toggledDetails: toggledDetails,
        computeRevealCharacterRects: computeRevealCharacterRects,
        codeSyntaxThemeKeys: codeSyntaxThemeKeys,
        codeTextColor: codeTextColor,
        collageMosaic: collageMosaic,
        mediaBleed: mediaBleed,
        unsupportedStyle: unsupportedStyle,
        buttonsEnabled: buttonsEnabled
    )

    return layoutBlockSequenceV2(
        instantPage.blocks,
        boundingWidth: boundingWidth,
        horizontalInset: horizontalInset,
        context: &context,
        kind: .topLevel
    )
}

public func lastTextLineFrameV2(in layout: InstantPageV2Layout) -> CGRect? {
    for item in layout.items.reversed() {
        switch item {
        case let .text(text):
            if let last = text.textItem.lines.last {
                return text.textItem.visualLineFrame(last).offsetBy(dx: text.frame.minX, dy: text.frame.minY)
            }
        case let .codeBlock(block):
            if let last = block.textItem.lines.last {
                return last.frame
                    .offsetBy(dx: block.textItem.frame.minX, dy: block.textItem.frame.minY)
                    .offsetBy(dx: block.frame.minX, dy: block.frame.minY)
            }
        case let .details(details):
            if let inner = details.innerLayout, let innerFrame = lastTextLineFrameV2(in: inner) {
                return innerFrame.offsetBy(dx: details.frame.minX, dy: details.frame.minY + details.titleFrame.maxY)
            }
            if let last = details.titleTextItem.lines.last {
                return details.titleTextItem.visualLineFrame(last)
                    .offsetBy(dx: details.titleTextItem.frame.minX, dy: details.titleTextItem.frame.minY)
                    .offsetBy(dx: details.frame.minX, dy: details.frame.minY)
            }
        default:
            continue
        }
    }
    return nil
}

public func lastTextLineFrameV2IfLastItemIsText(in layout: InstantPageV2Layout) -> CGRect? {
    guard let bottom = layout.items.max(by: { $0.frame.maxY < $1.frame.maxY }) else {
        return nil
    }
    if case let .text(text) = bottom, let last = text.textItem.lines.last {
        return text.textItem.visualLineFrame(last).offsetBy(dx: text.frame.minX, dy: text.frame.minY)
    }
    return nil
}


private struct LayoutContextV2 {
    public let theme: InstantPageTheme
    public let webpage: TelegramMediaWebpage
    public let media: [MediaId: Media]
    public let rtl: Bool
    public let fitToWidth: Bool

    public var mediaIndexCounter: Int
    public var detailsIndexCounter: Int

    public let toggledDetails: Set<Int>
    public let computeRevealCharacterRects: Bool

    public let codeSyntaxThemeKeys: [String: NSColor]
    public let codeTextColor: NSColor?
    public let collageMosaic: (([Media], CGFloat) -> [CGRect])?
    public let mediaBleed: CGFloat
    public let unsupportedStyle: (any InstantPageV2UnsupportedBandStyle)?
    public let buttonsEnabled: Bool

    public var isInsideTableCell: Bool = false
}


private enum InstantPageV2BlockSequenceKind {
    case topLevel
    case detail
    case cell
}

private struct InstantPageV2BlockSpacing {
    public var verticalPadding: CGFloat
    public var flushAbove: Bool = false
    public var flushBelow: Bool = false
}

private func instantPageV2BlockSpacing(_ block: InstantPageBlock) -> InstantPageV2BlockSpacing {
    switch block {
    case .anchor:
        return InstantPageV2BlockSpacing(verticalPadding: 0.0, flushAbove: true, flushBelow: true)
    case .cover, .channelBanner:
        return InstantPageV2BlockSpacing(verticalPadding: 4.0, flushAbove: true)
    case .relatedArticles:
        return InstantPageV2BlockSpacing(verticalPadding: 4.0, flushBelow: true)
    case .heading:
        return InstantPageV2BlockSpacing(verticalPadding: 8.0)
    case .divider:
        return InstantPageV2BlockSpacing(verticalPadding: 4.0)
    case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _),
         let .document(_, caption), let .audio(_, caption), let .slideshow(_, caption),
         let .collage(_, caption), let .map(_, _, _, _, caption):
        let hasCredit = caption.credit != .empty && caption.credit != .plain("")
        return InstantPageV2BlockSpacing(
            verticalPadding: 4.0,
            flushAbove: true,
            flushBelow: !hasCredit
        )
    default:
        return InstantPageV2BlockSpacing(verticalPadding: 4.0)
    }
}

private func instantPageV2Spacing(upper: InstantPageBlock?, lower: InstantPageBlock?) -> CGFloat {
    if let upper, let lower {
        switch (upper, lower) {
        case (_, .unsupported), (.unsupported, _):
            return 4.0
        default:
            break
        }

        var upperSpacing = instantPageV2BlockSpacing(upper)
        let lowerSpacing = instantPageV2BlockSpacing(lower)

        var upperIsRawMedia = false
        switch upper {
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _),
             let .document(_, caption), let .audio(_, caption), let .slideshow(_, caption),
             let .collage(_, caption), let .map(_, _, _, _, caption):
            if caption.credit != .empty && caption.credit != .plain("") {
                upperSpacing.verticalPadding += 2.0
            } else {
                switch upper {
                case .image, .video, .slideshow, .collage, .map:
                    upperIsRawMedia = true
                default:
                    break
                }
            }
        default:
            break
        }

        var lowerIsRawMedia = false
        switch lower {
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _),
             let .document(_, caption), let .audio(_, caption), let .slideshow(_, caption),
             let .collage(_, caption), let .map(_, _, _, _, caption):
            if caption.credit == .empty || caption.credit == .plain("") {
                switch lower {
                case .image, .video, .slideshow, .collage, .map:
                    lowerIsRawMedia = true
                default:
                    break
                }
            }
        default:
            break
        }

        if upperIsRawMedia && lowerIsRawMedia {
            return 1.0
        }
        if case .buttonRow = upper, case .buttonRow = lower {
            return upperSpacing.verticalPadding + lowerSpacing.verticalPadding
        }
        if case .list = upper, case .list = lower {
            return upperSpacing.verticalPadding + lowerSpacing.verticalPadding
        }
        if case .heading = upper {
            switch lower {
            case .heading:
                return upperSpacing.verticalPadding
            case .paragraph, .thinking, .list:
                return upperSpacing.verticalPadding + lowerSpacing.verticalPadding
            default:
                break
            }
        }
        if case .paragraph = upper {
            switch lower {
            case .heading:
                return upperSpacing.verticalPadding + 8.0 + lowerSpacing.verticalPadding
            case .list:
                return upperSpacing.verticalPadding + lowerSpacing.verticalPadding
            case .paragraph:
                return 1.0
            default:
                if lowerIsRawMedia {
                    return max(1.0, upperSpacing.verticalPadding + lowerSpacing.verticalPadding + 1.0)
                }
            }
        }
        if case .list = upper, case .paragraph = lower {
            return upperSpacing.verticalPadding + lowerSpacing.verticalPadding
        }
        switch lower {
        case .paragraph, .thinking, .list:
            if upperIsRawMedia {
                return max(1.0, upperSpacing.verticalPadding + lowerSpacing.verticalPadding + 1.0)
            }
        default:
            break
        }
        if case .details = upper {
            if case .details = lower {
                return upperSpacing.verticalPadding + lowerSpacing.verticalPadding
            }
            return upperSpacing.verticalPadding + 4.0 + lowerSpacing.verticalPadding
        }
        return upperSpacing.verticalPadding + 8.0 + lowerSpacing.verticalPadding
    } else if let lower {
        let lowerSpacing = instantPageV2BlockSpacing(lower)
        switch lower {
        case .paragraph, .thinking:
            return lowerSpacing.verticalPadding + 2.0
        default:
            return lowerSpacing.flushAbove ? 0.0 : lowerSpacing.verticalPadding
        }
    } else if let upper {
        let upperSpacing = instantPageV2BlockSpacing(upper)
        switch upper {
        case .paragraph, .thinking:
            return upperSpacing.verticalPadding + 2.0
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _),
             let .slideshow(_, caption), let .collage(_, caption),
             let .document(_, caption), let .audio(_, caption):
            if caption.credit != .empty && caption.credit != .plain("") {
                return upperSpacing.verticalPadding + 2.0
            }
        default:
            break
        }
        return upperSpacing.flushBelow ? 0.0 : upperSpacing.verticalPadding
    } else {
        return 0.0
    }
}

private func layoutBlockSequenceV2(
    _ blocks: [InstantPageBlock],
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2,
    kind: InstantPageV2BlockSequenceKind
) -> InstantPageV2Layout {
    var items: [InstantPageV2LaidOutItem] = []
    var detailsIndices: [Int] = []
    var pullQuoteRanges: [(range: Range<Int>, pillWidth: CGFloat)] = []
    var directCodeBlockIndices: [Int] = []
    var contentHeight: CGFloat = 0.0
    var previousBlock: InstantPageBlock?

    for block in blocks {
        let localItems = layoutBlockV2(
            block,
            boundingWidth: boundingWidth,
            horizontalInset: horizontalInset,
            isCover: false,
            previousItems: items,
            context: &context
        )
        let effectiveBlock: InstantPageBlock = localItems.contains(where: {
            if case .unsupported = $0 { return true }
            return false
        }) ? .unsupported : block
        let blockSpacing: CGFloat
        if kind == .cell {
            if previousBlock == nil {
                blockSpacing = 0.0
            } else {
                blockSpacing = spacingBetweenBlocks(upper: previousBlock, lower: effectiveBlock, fitToWidth: context.fitToWidth)
            }
        } else {
            blockSpacing = instantPageV2Spacing(upper: previousBlock, lower: effectiveBlock)
        }

        let dy = contentHeight + blockSpacing
        var blockMaxY: CGFloat = 0.0
        let blockStartIndex = items.count
        for var item in localItems {
            item = item.offsetBy(CGPoint(x: 0.0, y: dy))
            if case let .details(d) = item {
                detailsIndices.append(d.index)
            }
            let f = item.frame
            if f.maxY > blockMaxY {
                blockMaxY = f.maxY
            }
            items.append(item)
        }
        if case .preformatted = block {
            for i in blockStartIndex ..< items.count {
                if case .codeBlock = items[i] {
                    directCodeBlockIndices.append(i)
                }
            }
        }
        if case .pullQuote = block {
            let pillWidth = localItems.reduce(CGFloat(0)) { acc, item in
                if case let .shape(s) = item { return max(acc, s.frame.width) }
                return acc
            }
            if pillWidth > 0 {
                pullQuoteRanges.append((blockStartIndex ..< items.count, pillWidth))
            }
        }

        if blockMaxY > contentHeight {
            contentHeight = blockMaxY
            previousBlock = effectiveBlock
        }
    }

    if kind == .cell {
    } else {
        contentHeight += instantPageV2Spacing(upper: previousBlock, lower: nil)
    }

    var contentSize = CGSize(width: boundingWidth, height: contentHeight)
    if context.fitToWidth {
        let directCodeBlockIndexSet = Set(directCodeBlockIndices)
        var maxX: CGFloat = 0.0
        for (i, item) in items.enumerated() {
            var itemMaxX = item.frame.maxX
            if case let .text(text) = item, !text.textItem.lines.isEmpty {
                itemMaxX = text.textItem.lines.reduce(CGFloat(0)) {
                    max($0, text.frame.minX + text.textItem.visualLineFrame($1).maxX)
                }
            } else if directCodeBlockIndexSet.contains(i), case let .codeBlock(block) = item, !block.textItem.lines.isEmpty {
                let widest = block.textItem.lines.reduce(CGFloat(0)) { max($0, $1.frame.width) }
                itemMaxX = block.frame.minX + block.inset.left + widest + block.inset.right
            }
            maxX = max(maxX, ceil(itemMaxX) + horizontalInset)
        }
        contentSize.width = min(boundingWidth, maxX)
        for (range, pillWidth) in pullQuoteRanges {
            let dx = (contentSize.width - pillWidth) / 2.0 - horizontalInset
            if dx > 0.5 {
                for i in range {
                    items[i] = items[i].offsetBy(CGPoint(x: dx, y: 0.0))
                }
            }
        }
        for i in directCodeBlockIndices {
            if case var .codeBlock(block) = items[i] {
                let availableWidth = max(0.0, contentSize.width - horizontalInset - block.frame.minX)
                block.frame.size.width = availableWidth
                items[i] = .codeBlock(block)
            }
        }
    }

    centerBlockFormulas(in: &items, contentWidth: contentSize.width, horizontalInset: horizontalInset)

    return InstantPageV2Layout(contentSize: contentSize, items: items, detailsIndices: detailsIndices)
}

private func centerBlockFormulas(in items: inout [InstantPageV2LaidOutItem], contentWidth: CGFloat, horizontalInset: CGFloat) {
    for i in items.indices {
        guard case var .formula(item) = items[i], !item.isScrollable else {
            continue
        }
        let availableWidth = contentWidth - horizontalInset * 2.0
        item.frame.origin.x = horizontalInset + max(0.0, (availableWidth - item.frame.width) / 2.0)
        items[i] = .formula(item)
    }
}

private func layoutBlockV2(
    _ block: InstantPageBlock,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    isCover: Bool,
    previousItems: [InstantPageV2LaidOutItem],
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    switch block {
    case let .cover(inner):
        return layoutBlockV2(inner, boundingWidth: boundingWidth, horizontalInset: horizontalInset,
                             isCover: true, previousItems: previousItems, context: &context)
    case let .title(text):
        return layoutSimpleTextV2(text, category: .header, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, context: &context)
    case let .subtitle(text):
        return layoutSimpleTextV2(text, category: .subheader, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, context: &context)
    case let .kicker(text):
        return layoutSimpleTextV2(text, category: .kicker, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, context: &context)
    case let .header(text):
        return layoutSimpleTextV2(text, category: .header, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, context: &context)
    case let .subheader(text):
        return layoutSimpleTextV2(text, category: .subheader, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, context: &context)
    case let .heading(text, level):
        return layoutHeadingV2(text, level: level, boundingWidth: boundingWidth,
                               horizontalInset: horizontalInset, context: &context)
    case let .footer(text):
        return layoutSimpleTextV2(text, category: .caption, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, context: &context)
    case let .paragraph(text):
        return layoutSimpleTextV2(text, category: .paragraph, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, context: &context)
    case let .thinking(text):
        return layoutThinkingV2(text, boundingWidth: boundingWidth,
                                horizontalInset: horizontalInset, context: &context)
    case let .authorDate(author, date):
        return layoutAuthorDateV2(author: author, date: date, boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset, previousItems: previousItems,
                                  context: &context)
    case .divider:
        return layoutDividerV2(boundingWidth: boundingWidth, context: context)
    case let .anchor(name):
        return [.anchor(InstantPageV2AnchorItem(frame: CGRect(x: 0.0, y: 0.0, width: 0.0, height: 0.0), name: name))]

    case let .list(items, ordered):
        return layoutListV2(items, ordered: ordered, boundingWidth: boundingWidth,
                            horizontalInset: horizontalInset, context: &context)

    case let .preformatted(text, language):
        return layoutCodeBlockV2(text, language: language, boundingWidth: boundingWidth,
                                 horizontalInset: horizontalInset, context: &context)

    case let .blockQuote(blocks, caption, _):
        return layoutBlockQuoteBlocksV2(blocks: blocks, caption: caption,
                                        boundingWidth: boundingWidth, horizontalInset: horizontalInset,
                                        context: &context)
    case let .pullQuote(text, caption):
        return layoutPullQuoteV2(text: text, caption: caption,
                                 boundingWidth: boundingWidth, horizontalInset: horizontalInset,
                                 context: &context)

    case let .table(title, rows, bordered, striped, compact):
        return layoutTableV2(title: title, rows: rows, bordered: bordered, striped: striped, compact: compact,
                             boundingWidth: boundingWidth, horizontalInset: horizontalInset,
                             context: &context)

    case let .details(title, blocks, expanded):
        return layoutDetailsV2(title: title, blocks: blocks, defaultExpanded: expanded,
                               boundingWidth: boundingWidth, horizontalInset: horizontalInset,
                               context: &context)

    case let .formula(latex):
        return layoutFormulaV2(latex: latex, boundingWidth: boundingWidth,
                               horizontalInset: horizontalInset, previousItems: previousItems,
                               context: &context)

    case let .buttonRow(alignment, buttons):
        return layoutButtonRowV2(buttons, alignment: alignment, boundingWidth: boundingWidth,
                                 horizontalInset: horizontalInset, context: &context)

    case let .image(id, caption, url, webpageId, spoiler):
        if let image = context.media[id] as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
            let naturalSize = CGSize(width: CGFloat(largest.dimensions.width), height: CGFloat(largest.dimensions.height))
            let mediaUrl: InstantPageUrlItem? = url.flatMap { InstantPageUrlItem(url: $0, webpageId: webpageId) }
            let mediaIndex = context.mediaIndexCounter
            context.mediaIndexCounter += 1
            let webpage = context.webpage
            let media = InstantPageMedia(index: mediaIndex, media: image, webpage: webpage,
                                         url: mediaUrl, caption: caption.text, credit: caption.credit)
            return layoutTypedMediaWithCaptionV2(
                produceItem: { frame, cornerRadius in
                    .mediaImage(InstantPageV2MediaImageItem(frame: frame, cornerRadius: cornerRadius,
                                                            media: media, webPage: webpage, attributes: [], spoiler: spoiler))
                },
                naturalSize: naturalSize, caption: caption, isCover: isCover, cornerRadius: 8.0,
                boundingWidth: boundingWidth, horizontalInset: horizontalInset, bleed: true, capHeight: true, context: &context)
        }
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        return []

    case let .video(id, caption, _, _, spoiler):
        if let file = context.media[id] as? TelegramMediaFile, let dimensions = file.dimensions {
            let naturalSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
            let mediaIndex = context.mediaIndexCounter
            context.mediaIndexCounter += 1
            let webpage = context.webpage
            let media = InstantPageMedia(index: mediaIndex, media: file, webpage: webpage,
                                         url: nil, caption: caption.text, credit: caption.credit)
            return layoutTypedMediaWithCaptionV2(
                produceItem: { frame, cornerRadius in
                    .mediaVideo(InstantPageV2MediaVideoItem(frame: frame, cornerRadius: cornerRadius,
                                                            media: media, webPage: webpage, attributes: [], isFile: false, spoiler: spoiler))
                },
                naturalSize: naturalSize, caption: caption, isCover: isCover, cornerRadius: 8.0,
                boundingWidth: boundingWidth, horizontalInset: horizontalInset, bleed: true, capHeight: true, context: &context)
        }
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        return []

    case let .map(latitude, longitude, zoom, dimensions, caption):
        let naturalSize = CGSize(width: 4000.0, height: 1500.0)
        let map = TelegramMediaMap(
            latitude: latitude, longitude: longitude, heading: nil,
            accuracyRadius: nil, venue: nil,
            liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil
        )
        let attrs: [InstantPageImageAttribute] = [InstantPageMapAttribute(zoom: zoom, dimensions: dimensions.size)]
        let mediaIndex = context.mediaIndexCounter
        context.mediaIndexCounter += 1
        let webpage = context.webpage
        let media = InstantPageMedia(index: mediaIndex, media: map, webpage: webpage,
                                     url: nil, caption: caption.text, credit: caption.credit)
        return layoutTypedMediaWithCaptionV2(
            produceItem: { frame, cornerRadius in
                .mediaMap(InstantPageV2MediaMapItem(frame: frame, cornerRadius: cornerRadius,
                                                    media: media, webPage: webpage, attributes: attrs))
            },
            naturalSize: naturalSize, caption: caption, isCover: false, cornerRadius: 8.0,
            boundingWidth: boundingWidth, horizontalInset: horizontalInset, bleed: true, context: &context)

    case let .audio(id, caption):
        if let file = context.media[id] as? TelegramMediaFile {
            let mediaIndex = context.mediaIndexCounter
            context.mediaIndexCounter += 1
            let webpage = context.webpage
            let media = InstantPageMedia(index: mediaIndex, media: file, webpage: webpage,
                                         url: nil, caption: caption.text, credit: caption.credit)
            return layoutTypedMediaWithCaptionV2(
                produceItem: { frame, cornerRadius in
                    .mediaVideo(InstantPageV2MediaVideoItem(frame: frame, cornerRadius: cornerRadius,
                                                            media: media, webPage: webpage, attributes: [], isFile: false))
                },
                naturalSize: CGSize(width: boundingWidth - horizontalInset * 2.0, height: 40.0),
                caption: caption, isCover: false, cornerRadius: 0.0,
                boundingWidth: boundingWidth, horizontalInset: horizontalInset, context: &context)
        }
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        return layoutMediaWithCaptionV2(kind: .audio,
            naturalSize: CGSize(width: boundingWidth, height: 56.0), caption: caption,
            isCover: false, cornerRadius: 8.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)

    case let .document(id, caption):
        if let file = context.media[id] as? TelegramMediaFile {
            let mediaIndex = context.mediaIndexCounter
            context.mediaIndexCounter += 1
            let webpage = context.webpage
            let media = InstantPageMedia(index: mediaIndex, media: file, webpage: webpage,
                                         url: nil, caption: caption.text, credit: caption.credit)
            return layoutTypedMediaWithCaptionV2(
                produceItem: { frame, cornerRadius in
                    .mediaVideo(InstantPageV2MediaVideoItem(frame: frame, cornerRadius: cornerRadius,
                                                            media: media, webPage: webpage, attributes: [], isFile: true))
                },
                naturalSize: CGSize(width: boundingWidth - horizontalInset * 2.0, height: 48.0),
                caption: caption, isCover: false, cornerRadius: 0.0,
                boundingWidth: boundingWidth, horizontalInset: horizontalInset, context: &context)
        }
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        return layoutMediaWithCaptionV2(kind: .audio,
            naturalSize: CGSize(width: boundingWidth, height: 56.0), caption: caption,
            isCover: false, cornerRadius: 8.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)

    case let .webEmbed(_, _, dimensions, caption, _, _, _):
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        let h: CGFloat = CGFloat(dimensions?.height ?? 240)
        return layoutMediaWithCaptionV2(kind: .webEmbed,
            naturalSize: CGSize(width: boundingWidth, height: h), caption: caption,
            isCover: false, cornerRadius: 0.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)

    case let .postEmbed(_, _, _, _, _, _, caption):
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        return layoutMediaWithCaptionV2(kind: .postEmbed,
            naturalSize: CGSize(width: boundingWidth, height: 140.0), caption: caption,
            isCover: false, cornerRadius: 8.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)

    case let .collage(blocks, caption):
        return layoutCollageV2(blocks, caption: caption, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)

    case let .slideshow(blocks, caption):
        return layoutSlideshowV2(blocks, caption: caption, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)

    case let .channelBanner(channel):
        if context.unsupportedStyle != nil {
            return layoutUnsupportedV2(boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: context)
        }
        if channel == nil { return [] }
        return layoutMediaWithCaptionV2(kind: .channelBanner,
            naturalSize: CGSize(width: boundingWidth, height: 60.0),
            caption: InstantPageCaption(text: .empty, credit: .empty),
            isCover: false, cornerRadius: 0.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)

    case let .relatedArticles(_, articles):
        if context.unsupportedStyle != nil {
            return layoutUnsupportedV2(boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: context)
        }
        let h = min(CGFloat(articles.count) * 80.0, 320.0)
        return layoutMediaWithCaptionV2(kind: .relatedArticles,
            naturalSize: CGSize(width: boundingWidth, height: max(h, 80.0)),
            caption: InstantPageCaption(text: .empty, credit: .empty),
            isCover: false, cornerRadius: 0.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)
    case .unsupported:
        return layoutUnsupportedV2(boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: context)
    }
}


private func layoutSimpleTextV2(
    _ text: RichText,
    category: InstantPageTextCategoryType,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(styleStack, theme: context.theme, category: category, link: false)
    let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)
    let attributedString = attributedStringForRichText(text, styleStack: styleStack, inlineButtonMaxWidth: boundingWidth - horizontalInset * 2.0, isInsideTableCell: context.isInsideTableCell)
    let (textItem, _, _) = layoutTextItemWithStringV2(
        attributedString,
        boundingWidth: boundingWidth - horizontalInset * 2.0,
        offset: CGPoint(x: horizontalInset, y: 0.0),
        media: context.media,
        webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: lineMetrics
    )
    guard let textItem else { return [] }
    return [.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem))]
}

private let instantPageBlockButtonHeightV2: CGFloat = 32.0
private let instantPageBlockButtonSpacingV2: CGFloat = 6.0
private let instantPageBlockButtonsPerRowV2 = 8

private let instantPageBlockButtonMinimumHorizontalPaddingV2: CGFloat = 6.0

private func instantPageBlockButtonPaddingV2(for button: InstantPageButton) -> CGFloat {
    return button.isLink ? 0.0 : instantPageInlineButtonHorizontalPadding
}

private func instantPageBlockButtonMinimumPaddingV2(for button: InstantPageButton) -> CGFloat {
    return min(instantPageBlockButtonPaddingV2(for: button), instantPageBlockButtonMinimumHorizontalPaddingV2)
}

private func instantPageBlockButtonExtraSideInsetV2(_ button: InstantPageButton, padding: CGFloat) -> CGFloat {
    let iconAllowance = instantPageButtonIconAllowance(button, pillHeight: instantPageBlockButtonHeightV2)
    return max(0.0, iconAllowance - padding)
}

private func instantPageBlockButtonMeasureV2(
    button: InstantPageButton,
    labelString: NSAttributedString,
    pillWidth: CGFloat,
    buttonsEnabled: Bool
) -> (attachment: InstantPageInlineButtonAttachment, extraSideInset: CGFloat) {
    func measure(padding: CGFloat) -> (attachment: InstantPageInlineButtonAttachment, extraSideInset: CGFloat) {
        let extra = instantPageBlockButtonExtraSideInsetV2(button, padding: padding)
        let attachment = instantPageInlineButtonAttachment(
            button: button,
            presentation: .pill,
            labelString: labelString,
            maxWidth: max(0.0, pillWidth - extra * 2.0),
            horizontalPadding: padding,
            isEnabled: buttonsEnabled
        )
        return (attachment, extra)
    }
    let comfortable = instantPageBlockButtonPaddingV2(for: button)
    let minimum = instantPageBlockButtonMinimumPaddingV2(for: button)
    let result = measure(padding: comfortable)
    guard result.attachment.isTruncated, minimum < comfortable else {
        return result
    }
    return measure(padding: minimum)
}

private func instantPageBlockButtonSlackOffsetV2(
    alignment: InstantPageButtonRowAlignment,
    slack: CGFloat,
    rtl: Bool
) -> CGFloat {
    switch alignment {
    case .justify:
        return 0.0
    case .left:
        return rtl ? slack : 0.0
    case .center:
        return slack / 2.0
    case .right:
        return rtl ? 0.0 : slack
    }
}

private func layoutButtonRowV2(
    _ buttons: [InstantPageButton],
    alignment: InstantPageButtonRowAlignment,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let availableWidth = boundingWidth - horizontalInset * 2.0
    guard !buttons.isEmpty, availableWidth > 0.0 else {
        return []
    }

    let labelledButtons: [(button: InstantPageButton, labelString: NSAttributedString)] = buttons.map { button in
        let labelStyleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
        setupStyleStackV2(labelStyleStack, theme: context.theme, category: .paragraph, link: false)
        labelStyleStack.push(.fontSize(instantPageBlockButtonFontSize))
        labelStyleStack.push(.semibold)
        return (button, attributedStringForRichText(button.text, styleStack: labelStyleStack))
    }

    let layout: (entries: [(attachment: InstantPageInlineButtonAttachment, frame: CGRect)], totalHeight: CGFloat)
    switch alignment {
    case .justify:
        layout = layoutJustifiedButtonRowV2(
            labelledButtons,
            availableWidth: availableWidth,
            horizontalInset: horizontalInset,
            rtl: context.rtl,
            buttonsEnabled: context.buttonsEnabled
        )
    case .left, .center, .right:
        layout = layoutHuggingButtonRowV2(
            labelledButtons,
            alignment: alignment,
            availableWidth: availableWidth,
            horizontalInset: horizontalInset,
            rtl: context.rtl,
            buttonsEnabled: context.buttonsEnabled
        )
    }

    guard !layout.entries.isEmpty else {
        return []
    }
    return [.buttonRow(InstantPageV2ButtonRowItem(
        frame: CGRect(x: 0.0, y: 0.0, width: boundingWidth, height: layout.totalHeight),
        buttons: layout.entries
    ))]
}

private func layoutJustifiedButtonRowV2(
    _ labelledButtons: [(button: InstantPageButton, labelString: NSAttributedString)],
    availableWidth: CGFloat,
    horizontalInset: CGFloat,
    rtl: Bool,
    buttonsEnabled: Bool
) -> (entries: [(attachment: InstantPageInlineButtonAttachment, frame: CGRect)], totalHeight: CGFloat) {
    var entries: [(attachment: InstantPageInlineButtonAttachment, frame: CGRect)] = []
    var y: CGFloat = 0.0
    var index = 0
    while index < labelledButtons.count {
        let rowButtons = Array(labelledButtons[index ..< min(index + instantPageBlockButtonsPerRowV2, labelledButtons.count)])
        let gapCount = max(0, rowButtons.count - 1)
        let buttonSpacing = gapCount == 0
            ? 0.0
            : min(instantPageBlockButtonSpacingV2, availableWidth / CGFloat(gapCount))
        let totalSpacing = buttonSpacing * CGFloat(gapCount)
        let buttonWidth = max(0.0, (availableWidth - totalSpacing) / CGFloat(rowButtons.count))
        for (position, entry) in rowButtons.enumerated() {
            let (attachment, _) = instantPageBlockButtonMeasureV2(button: entry.button, labelString: entry.labelString, pillWidth: buttonWidth, buttonsEnabled: buttonsEnabled)
            let column = rtl ? rowButtons.count - 1 - position : position
            let x = horizontalInset + CGFloat(column) * (buttonWidth + buttonSpacing)
            entries.append((attachment, CGRect(x: x, y: y, width: buttonWidth, height: instantPageBlockButtonHeightV2)))
        }
        y += instantPageBlockButtonHeightV2 + instantPageBlockButtonSpacingV2
        index += instantPageBlockButtonsPerRowV2
    }
    return (entries, max(0.0, y - instantPageBlockButtonSpacingV2))
}

private func layoutHuggingButtonRowV2(
    _ labelledButtons: [(button: InstantPageButton, labelString: NSAttributedString)],
    alignment: InstantPageButtonRowAlignment,
    availableWidth: CGFloat,
    horizontalInset: CGFloat,
    rtl: Bool,
    buttonsEnabled: Bool
) -> (entries: [(attachment: InstantPageInlineButtonAttachment, frame: CGRect)], totalHeight: CGFloat) {
    let measured: [(attachment: InstantPageInlineButtonAttachment, width: CGFloat)] = labelledButtons.map { entry in
        let (attachment, extraInset) = instantPageBlockButtonMeasureV2(
            button: entry.button, labelString: entry.labelString, pillWidth: availableWidth, buttonsEnabled: buttonsEnabled)
        return (attachment, min(availableWidth, attachment.size.width + extraInset * 2.0))
    }

    var rows: [[Int]] = []
    var currentRow: [Int] = []
    var currentWidth: CGFloat = 0.0
    for index in measured.indices {
        let width = measured[index].width
        if !currentRow.isEmpty {
            let projectedWidth = currentWidth + instantPageBlockButtonSpacingV2 + width
            if projectedWidth > availableWidth || currentRow.count >= instantPageBlockButtonsPerRowV2 {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0.0
            }
        }
        currentWidth = currentRow.isEmpty ? width : currentWidth + instantPageBlockButtonSpacingV2 + width
        currentRow.append(index)
    }
    if !currentRow.isEmpty {
        rows.append(currentRow)
    }

    var frames = [CGRect](repeating: .zero, count: measured.count)
    var y: CGFloat = 0.0
    for row in rows {
        let rowWidth = row.reduce(0.0) { partialResult, index in
            partialResult + measured[index].width
        } + instantPageBlockButtonSpacingV2 * CGFloat(max(0, row.count - 1))
        let slack = max(0.0, availableWidth - rowWidth)
        var x = horizontalInset + instantPageBlockButtonSlackOffsetV2(alignment: alignment, slack: slack, rtl: rtl)
        let visualOrder = rtl ? Array(row.reversed()) : row
        for index in visualOrder {
            frames[index] = CGRect(x: x, y: y, width: measured[index].width, height: instantPageBlockButtonHeightV2)
            x += measured[index].width + instantPageBlockButtonSpacingV2
        }
        y += instantPageBlockButtonHeightV2 + instantPageBlockButtonSpacingV2
    }

    let entries = measured.indices.map { index in
        return (attachment: measured[index].attachment, frame: frames[index])
    }
    return (entries, max(0.0, y - instantPageBlockButtonSpacingV2))
}

private func layoutThinkingV2(
    _ text: RichText,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(styleStack, theme: context.theme, category: .paragraph, link: false)
    let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)
    styleStack.push(.textColor(context.theme.panelSecondaryColor))
    let attributedString = attributedStringForRichText(text, styleStack: styleStack, inlineButtonMaxWidth: boundingWidth - horizontalInset * 2.0)
    let (textItem, _, _) = layoutTextItemWithStringV2(
        attributedString,
        boundingWidth: boundingWidth - horizontalInset * 2.0,
        offset: CGPoint(x: horizontalInset, y: 0.0),
        media: context.media,
        webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: lineMetrics
    )
    guard let textItem else { return [] }
    return [.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem, isThinking: true))]
}

private func layoutHeadingV2(
    _ text: RichText,
    level: Int32,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(styleStack, theme: context.theme, attributes: context.theme.headingTextAttributes(level: level, link: false))
    let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)
    let attributedString = attributedStringForRichText(text, styleStack: styleStack, inlineButtonMaxWidth: boundingWidth - horizontalInset * 2.0)
    let (textItem, _, _) = layoutTextItemWithStringV2(
        attributedString,
        boundingWidth: boundingWidth - horizontalInset * 2.0,
        offset: CGPoint(x: horizontalInset, y: 0.0),
        media: context.media,
        webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: lineMetrics
    )
    guard let textItem else { return [] }
    return [.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem))]
}

private func layoutAuthorDateV2(
    author: RichText,
    date: Int32,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    previousItems: [InstantPageV2LaidOutItem],
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(styleStack, theme: context.theme, category: .caption, link: false)
    let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)

    let stringForDate: (Int32) -> String = { d in
        DateFormatter.localizedString(from: Date(timeIntervalSince1970: Double(d)), dateStyle: .long, timeStyle: .none)
    }

    var text: RichText?
    if case .empty = author {
        if date != 0 {
            text = .plain(stringForDate(date))
        }
    } else {
        if date != 0 {
            text = .concat([author, .plain(" • " + stringForDate(date))])
        } else {
            text = author
        }
    }

    guard let resolvedText = text else { return [] }

    var previousItemHasRTL = false
    if case let .text(prev) = previousItems.last, prev.textItem.containsRTL {
        previousItemHasRTL = true
    }
    let alignment: NSTextAlignment = (context.rtl || previousItemHasRTL) ? .right : .natural

    let (textItem, _, _) = layoutTextItemWithStringV2(
        attributedStringForRichText(resolvedText, styleStack: styleStack, inlineButtonMaxWidth: boundingWidth - horizontalInset * 2.0),
        boundingWidth: boundingWidth - horizontalInset * 2.0,
        alignment: alignment,
        offset: CGPoint(x: horizontalInset, y: 0.0),
        media: context.media,
        webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: lineMetrics
    )
    guard let textItem else { return [] }
    return [.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem))]
}

private func layoutUnsupportedV2(
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    guard let style = context.unsupportedStyle, boundingWidth > 0 else {
        return []
    }
    let layout = style.makeBandLayout(
        title: strings().chatUnsupportedBlockTitle,
        subtitle: strings().chatUnsupportedBlockInfo,
        action: strings().chatUnsupportedUpdate
    )
    layout.measure(width: boundingWidth)
    let frame = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
    return [.unsupported(InstantPageV2UnsupportedItem(frame: frame, layout: layout))]
}

private func layoutUnsupportedMediaV2(
    caption: InstantPageCaption,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    var result = layoutUnsupportedV2(
        boundingWidth: boundingWidth,
        horizontalInset: horizontalInset,
        context: context
    )
    guard let bandHeight = result.map({ $0.frame.maxY }).max() else {
        return []
    }
    let (captionItems, _) = layoutCaptionAndCreditV2(
        caption,
        offset: bandHeight,
        boundingWidth: boundingWidth,
        horizontalInset: horizontalInset,
        context: &context
    )
    result.append(contentsOf: captionItems)
    return result
}

private func layoutDividerV2(
    boundingWidth: CGFloat,
    context: LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let lineWidth = floor(boundingWidth / 2.0)
    let frame = CGRect(
        x: floor((boundingWidth - lineWidth) / 2.0),
        y: 0.0,
        width: lineWidth,
        height: System.pixel
    )
    return [.divider(InstantPageV2DividerItem(frame: frame, color: context.theme.separatorColor))]
}


private func applyCodeSyntaxV2(to attributedString: NSAttributedString, language: String?, theme: InstantPageTheme, themeKeys: [String: NSColor], baseTextColor: NSColor? = nil) -> NSAttributedString {
    guard let language, !language.isEmpty else { return attributedString }
    let textValue = attributedString.string
    guard !textValue.isEmpty else { return attributedString }

    let attributes = theme.textCategories.attributes(type: .paragraph, link: false)
    let baseColor = baseTextColor ?? attributes.color
    let linkColor = theme.linkColor
    let markerColor = theme.markerColor
    let isDark = theme.type == .dark

    let highlightColors: [String: NSColor] = [
        "comment": baseColor.withAlphaComponent(0.6),
        "block-comment": baseColor.withAlphaComponent(0.6),
        "prolog": baseColor.withAlphaComponent(0.6),
        "doctype": baseColor.withAlphaComponent(0.6),
        "cdata": baseColor.withAlphaComponent(0.6),
        "punctuation": baseColor.withAlphaComponent(0.7),
        "property": markerColor,
        "tag": markerColor,
        "boolean": linkColor,
        "number": linkColor,
        "constant": linkColor,
        "symbol": linkColor,
        "deleted": linkColor,
        "selector": linkColor,
        "attr-name": linkColor,
        "string": baseColor,
        "char": markerColor,
        "builtin": baseColor,
        "inserted": linkColor,
        "operator": linkColor,
        "entity": linkColor,
        "url": linkColor,
        "atrule": linkColor,
        "attr-value": baseColor,
        "keyword": linkColor,
        "function": linkColor,
        "class-name": markerColor,
        "regex": baseColor,
        "important": markerColor,
        "variable": baseColor
    ]

    let fontSize = attributes.font.size
    guard let highlighted = InstantPageHooks.shared.highlightCode(
        textValue,
        language.lowercased(),
        isDark,
        baseColor,
        NSFont.code(fontSize),
        NSFont.italicMonospace(fontSize),
        NSFont.semiboldMonospace(fontSize),
        themeKeys.isEmpty ? highlightColors : themeKeys
    ) else {
        return attributedString
    }

    let mutable = attributedString.mutableCopy() as! NSMutableAttributedString
    applyHighlightedCode(highlighted, to: mutable, offset: 0)
    return mutable
}

private func layoutCodeBlockV2(
    _ text: RichText,
    language: String?,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let verticalInset: CGFloat = 6.0
    let lineInset: CGFloat = 9.0
    let cornerRadius: CGFloat = 6.0

    let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(styleStack, theme: context.theme, category: .paragraph, link: false)
    styleStack.push(.fontFixed(true))
    let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)

    var attributedString = attributedStringForRichText(text, styleStack: styleStack)
    if let codeTextColor = context.codeTextColor, attributedString.length > 0 {
        let recolored = attributedString.mutableCopy() as! NSMutableAttributedString
        recolored.addAttribute(.foregroundColor, value: codeTextColor, range: NSRange(location: 0, length: recolored.length))
        attributedString = recolored
    }
    let highlighted = applyCodeSyntaxV2(to: attributedString, language: language, theme: context.theme, themeKeys: context.codeSyntaxThemeKeys, baseTextColor: context.codeTextColor)

    let normalizedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasHeader = (normalizedLanguage?.isEmpty == false)
    let headerHeight: CGFloat = hasHeader ? 22.0 : 0.0

    let textBounding = boundingWidth - horizontalInset * 2.0 - lineInset * 2.0
    let (textItem, _, contentSize) = layoutTextItemWithStringV2(
        highlighted,
        boundingWidth: textBounding,
        offset: .zero,
        media: context.media,
        webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: lineMetrics
    )
    guard let textItem else { return [] }

    let overheads = instantPageV2TextBoxOverheads(attributedString)
    let topPad = max(0.0, verticalInset - overheads.top)
    let bottomPad = max(0.0, verticalInset - overheads.bottom)
    textItem.frame = CGRect(
        x: lineInset,
        y: headerHeight + topPad,
        width: textItem.frame.width,
        height: textItem.frame.height
    )

    let blockHeight = headerHeight + topPad + contentSize.height + bottomPad
    let blockFrame = CGRect(x: horizontalInset, y: 0.0,
                            width: boundingWidth - horizontalInset * 2.0,
                            height: blockHeight)
    let accent = context.theme.quoteAccentColor
    let codeBackgroundColor = accent.withAlphaComponent(0.10)
    let codeItem = InstantPageV2CodeBlockItem(
        frame: blockFrame,
        backgroundColor: codeBackgroundColor,
        cornerRadius: cornerRadius,
        textItem: textItem,
        inset: NSEdgeInsets(top: topPad, left: lineInset, bottom: bottomPad, right: lineInset),
        headerText: hasHeader ? normalizedLanguage : nil,
        headerHeight: headerHeight,
        headerColor: accent
    )
    return [.codeBlock(codeItem)]
}


private func instantPageV2TextBoxOverheads(_ string: NSAttributedString) -> (top: CGFloat, bottom: CGFloat) {
    guard string.length > 0, let font = string.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
        return (0.0, 0.0)
    }
    return (max(0.0, font.ascender - font.capHeight), max(0.0, -font.descender))
}

private func layoutPullQuoteV2(
    text: RichText,
    caption: RichText,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let quoteScale: CGFloat = 15.0 / 17.0
    func quoteMetric(_ value: CGFloat) -> CGFloat {
        return floorToScreenPixels(System.backingScale, value * quoteScale)
    }
    let verticalInset = quoteMetric(12.0)
    let hPad = quoteMetric(30.0)
    let captionSpacing = quoteMetric(3.0)
    let availWidth = max(boundingWidth - horizontalInset * 2.0, 1.0)
    let measureWidth = max(availWidth - hPad * 2.0, 1.0)

    let textStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(textStack, theme: context.theme, category: .paragraph, link: false)
    textStack.push(.fontSize(15.0))
    textStack.push(.lineSpacingFactor(1.0))
    textStack.push(.italic)
    let textLineMetrics = InstantPageTextLineMetrics(styleStack: textStack)
    let textAttributed = attributedStringForRichText(text, styleStack: textStack)

    let captionStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(captionStack, theme: context.theme, category: .caption, link: false)
    captionStack.push(.textColor(context.theme.quoteAccentColor))
    captionStack.push(.linkColor(context.theme.quoteAccentColor))
    captionStack.push(.fontSize(15.0))
    captionStack.push(.lineSpacingFactor(1.0))
    captionStack.push(.bold)
    captionStack.push(.italic)
    let captionLineMetrics = InstantPageTextLineMetrics(styleStack: captionStack)
    let captionAttributed = attributedStringForRichText(caption, styleStack: captionStack)

    let media = context.media
    let webpage = context.webpage
    func widestLine(_ s: NSAttributedString, lineMetrics: InstantPageTextLineMetrics?) -> CGFloat {
        guard s.length > 0 else { return 0.0 }
        let (item, _, size) = layoutTextItemWithStringV2(s, boundingWidth: measureWidth, alignment: .center,
                                                         offset: .zero, media: media, webpage: webpage,
                                                         lineMetrics: lineMetrics)
        return item?.lines.map { $0.frame.width }.max() ?? size.width
    }
    let contentWidth = widestLine(textAttributed, lineMetrics: textLineMetrics)
    let innerWidth = min(max(contentWidth, 1.0), measureWidth)
    let pillWidth = min(innerWidth + hPad * 2.0, availWidth)
    let pillX = horizontalInset          // left-anchored so the bubble hugs the pill
    let textX = pillX + hPad
    let textInnerWidth = max(pillWidth - hPad * 2.0, 1.0)

    var items: [InstantPageV2LaidOutItem] = []
    let bodyOverheads = instantPageV2TextBoxOverheads(textAttributed)
    var contentHeight: CGFloat = max(0.0, verticalInset - bodyOverheads.top)
    var lastBottomOverhead = bodyOverheads.bottom

    let (textItem, _, textSize) = layoutTextItemWithStringV2(
        textAttributed, boundingWidth: textInnerWidth, alignment: .center,
        offset: CGPoint(x: textX, y: contentHeight), media: context.media, webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: textLineMetrics)
    if let textItem {
        items.append(.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem)))
    }
    contentHeight += textSize.height
    let quoteRegionBottom = contentHeight + max(0.0, verticalInset - bodyOverheads.bottom)

    if captionAttributed.length > 0 {
        contentHeight += captionSpacing
        lastBottomOverhead = instantPageV2TextBoxOverheads(captionAttributed).bottom
        let (captionItem, _, captionSize) = layoutTextItemWithStringV2(
            captionAttributed, boundingWidth: textInnerWidth, alignment: .center,
            offset: CGPoint(x: textX, y: contentHeight), media: context.media, webpage: context.webpage,
            fitToWidth: context.fitToWidth,
            computeRevealCharacterRects: context.computeRevealCharacterRects,
            lineMetrics: captionLineMetrics)
        if let captionItem {
            items.append(.text(InstantPageV2TextItem(frame: captionItem.frame, textItem: captionItem)))
        }
        contentHeight += captionSize.height
    }
    contentHeight += max(0.0, verticalInset - lastBottomOverhead)

    let accent = context.theme.quoteAccentColor
    items.insert(.shape(InstantPageV2ShapeItem(
        frame: CGRect(x: pillX, y: 0.0, width: pillWidth, height: contentHeight),
        kind: .roundedRect(cornerRadius: 6.0),
        color: accent.withAlphaComponent(0.10))), at: 0)
    let markSize = CGSize(width: 12.0, height: 10.0)
    let markInset: CGFloat = 6.0
    items.append(.pullQuoteMark(InstantPageV2PullQuoteMarkItem(
        frame: CGRect(x: pillX + markInset, y: markInset, width: markSize.width, height: markSize.height),
        color: accent, kind: .open)))
    items.append(.pullQuoteMark(InstantPageV2PullQuoteMarkItem(
        frame: CGRect(x: pillX + pillWidth - markInset - markSize.width,
                      y: quoteRegionBottom - markInset - markSize.height,
                      width: markSize.width, height: markSize.height),
        color: accent, kind: .close)))
    return items
}

private func layoutBlockQuoteV2(
    text: RichText,
    caption: RichText,
    isPull: Bool,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let leadingInset: CGFloat = isPull ? 0.0 : 9.0
    let trailingInset: CGFloat = isPull ? 0.0 : 16.0
    let captionSpacing: CGFloat = 3.0
    let verticalInset: CGFloat = isPull ? 10.0 : 6.0

    var items: [InstantPageV2LaidOutItem] = []

    let textStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(textStack, theme: context.theme, category: .paragraph, link: false)
    if isPull {
        textStack.push(.italic)   // pull quotes render forced-italic; block quotes keep the run styling (WYSIWYG with the editor)
    }
    let textLineMetrics = InstantPageTextLineMetrics(styleStack: textStack)

    let rtl = !isPull && instantPageRichTextContainsRTL(text)
    let textBoundingWidth = boundingWidth - horizontalInset * 2.0 - leadingInset - trailingInset
    let textAttributed = attributedStringForRichText(text, styleStack: textStack, inlineButtonMaxWidth: textBoundingWidth)
    let textOriginX = horizontalInset + (rtl ? trailingInset : leadingInset)
    let bodyOverheads = instantPageV2TextBoxOverheads(textAttributed)
    var contentHeight = max(0.0, verticalInset - bodyOverheads.top)
    var lastBottomOverhead = bodyOverheads.bottom
    let (textItem, _, textSize) = layoutTextItemWithStringV2(
        textAttributed,
        boundingWidth: textBoundingWidth,
        alignment: isPull ? .center : .natural,
        offset: CGPoint(x: textOriginX, y: contentHeight),
        media: context.media,
        webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: textLineMetrics
    )
    if let textItem {
        items.append(.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem)))
    }
    contentHeight += textSize.height

    let captionStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(captionStack, theme: context.theme, category: .caption, link: false)
    if !isPull {
        captionStack.push(.textColor(context.theme.quoteAccentColor))
        captionStack.push(.linkColor(context.theme.quoteAccentColor))
        captionStack.push(.bold)
        captionStack.push(.fontSize(context.theme.textCategories.paragraph.font.size))
    }
    let captionLineMetrics = InstantPageTextLineMetrics(styleStack: captionStack)
    let captionAttributed = attributedStringForRichText(caption, styleStack: captionStack)
    if captionAttributed.length > 0 {
        lastBottomOverhead = instantPageV2TextBoxOverheads(captionAttributed).bottom
        let (captionItem, _, captionSize) = layoutTextItemWithStringV2(
            captionAttributed,
            boundingWidth: textBoundingWidth,
            alignment: isPull ? .center : (rtl ? .right : .natural),
            offset: CGPoint(x: textOriginX, y: contentHeight + captionSpacing),
            media: context.media,
            webpage: context.webpage,
            fitToWidth: context.fitToWidth,
            computeRevealCharacterRects: context.computeRevealCharacterRects,
            lineMetrics: captionLineMetrics
        )
        if let captionItem {
            items.append(.text(InstantPageV2TextItem(frame: captionItem.frame, textItem: captionItem)))
            contentHeight += captionSpacing + captionSize.height
        }
    }

    contentHeight += max(0.0, verticalInset - lastBottomOverhead)

    if !isPull && contentHeight > 0 {
        let blockFrame = CGRect(
            x: horizontalInset,
            y: 0.0,
            width: boundingWidth - horizontalInset * 2.0,
            height: contentHeight
        )
        let decoration = InstantPageV2BlockQuoteDecorationItem(
            frame: blockFrame,
            color: context.theme.quoteAccentColor,
            backgroundCornerRadius: 6.0,
            barWidth: 3.0,
            drawsIcon: true,
            rtl: rtl
        )
        items.insert(.blockQuoteDecoration(decoration), at: 0)
    }
    return items
}

private func layoutBlockQuoteBlocksV2(
    blocks: [InstantPageBlock],
    caption: RichText,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    if blocks.isEmpty {
        return layoutBlockQuoteV2(text: .empty, caption: caption, isPull: false,
                                  boundingWidth: boundingWidth, horizontalInset: horizontalInset,
                                  context: &context)
    }
    if blocks.count == 1, case let .paragraph(text) = blocks[0] {
        return layoutBlockQuoteV2(text: text, caption: caption, isPull: false,
                                  boundingWidth: boundingWidth, horizontalInset: horizontalInset,
                                  context: &context)
    }

    let leadingInset: CGFloat = 9.0
    let trailingInset: CGFloat = 16.0
    let verticalInset: CGFloat = 6.0
    let captionSpacing: CGFloat = 3.0
    let childSpacing: CGFloat = 10.0

    let rtl = instantPageRichTextContainsRTL(instantPageRichTextFromBlocks(blocks))
    let innerBoundingWidth = boundingWidth - horizontalInset * 2.0 - leadingInset - trailingInset
    let innerOriginX = horizontalInset + (rtl ? trailingInset : leadingInset)

    var items: [InstantPageV2LaidOutItem] = []
    var contentHeight: CGFloat = verticalInset

    for (i, child) in blocks.enumerated() {
        let childItems = layoutBlockV2(child, boundingWidth: innerBoundingWidth,
                                       horizontalInset: 0.0,
                                       isCover: false, previousItems: items, context: &context)
        let dy = contentHeight + (i == 0 ? 0.0 : childSpacing)
        let offset = childItems.map { $0.offsetBy(CGPoint(x: innerOriginX, y: dy)) }
        let childMaxY = offset.map { $0.frame.maxY }.max() ?? dy
        contentHeight = max(contentHeight, childMaxY)
        items.append(contentsOf: offset)
    }

    let captionStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(captionStack, theme: context.theme, category: .caption, link: false)
    captionStack.push(.textColor(context.theme.quoteAccentColor))
    captionStack.push(.linkColor(context.theme.quoteAccentColor))
    captionStack.push(.bold)
    captionStack.push(.fontSize(context.theme.textCategories.paragraph.font.size))
    let captionLineMetrics = InstantPageTextLineMetrics(styleStack: captionStack)
    let captionAttributed = attributedStringForRichText(caption, styleStack: captionStack)
    if captionAttributed.length > 0 {
        let (captionItem, _, captionSize) = layoutTextItemWithStringV2(
            captionAttributed,
            boundingWidth: innerBoundingWidth,
            alignment: rtl ? .right : .natural,
            offset: CGPoint(x: innerOriginX, y: contentHeight + captionSpacing),
            media: context.media,
            webpage: context.webpage,
            fitToWidth: context.fitToWidth,
            computeRevealCharacterRects: context.computeRevealCharacterRects,
            lineMetrics: captionLineMetrics
        )
        if let captionItem {
            items.append(.text(InstantPageV2TextItem(frame: captionItem.frame, textItem: captionItem)))
            contentHeight += captionSpacing + captionSize.height
        }
    }

    contentHeight += verticalInset

    let decoration = InstantPageV2BlockQuoteDecorationItem(
        frame: CGRect(x: horizontalInset, y: 0.0,
                      width: boundingWidth - horizontalInset * 2.0, height: contentHeight),
        color: context.theme.quoteAccentColor,
        backgroundCornerRadius: 6.0,
        barWidth: 3.0,
        drawsIcon: true,
        rtl: rtl
    )
    items.insert(.blockQuoteDecoration(decoration), at: 0)
    return items
}


public func instantPageStringContainsRTL(_ string: String) -> Bool {
    for scalar in string.unicodeScalars {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x1_0800...0x1_0FFF, 0x1_E800...0x1_EFFF:
            return true
        default:
            break
        }
    }
    return false
}

private func instantPageRichTextContainsRTL(_ text: RichText) -> Bool {
    return instantPageStringContainsRTL(text.plainText)
}

private func layoutListV2(
    _ listItems: [InstantPageListItem],
    ordered: Bool,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let indexStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(indexStack, theme: context.theme, category: .paragraph, link: false)
    let indexLineMetrics = InstantPageTextLineMetrics(styleStack: indexStack)
    var indexLayouts: [InstantPageTextItem?] = []
    var maxIndexWidth: CGFloat = 0.0
    var hasTaskItem = false
    for listItem in listItems {
        let number: String?
        let itemChecked: Bool?
        switch listItem {
        case let .text(_, n, c), let .blocks(_, n, c):
            number = n
            itemChecked = c
        case .unknown:
            number = nil
            itemChecked = nil
        }
        if itemChecked != nil || number == markdownTaskListCheckedNumber || number == markdownTaskListUncheckedNumber {
            hasTaskItem = true
            break
        }
    }
    let indexSpacing: CGFloat = ordered ? (hasTaskItem ? 10.0 : 8.0) : (hasTaskItem ? 12.0 : 10.0)
    let checklistMarkerSize: CGFloat = 18.0
    for (i, _) in listItems.enumerated() {
        if ordered {
            let value = "\(i + 1)."
            let (item, _, _) = layoutTextItemWithStringV2(
                attributedStringForRichText(.plain(value), styleStack: indexStack),
                boundingWidth: boundingWidth - horizontalInset * 2.0,
                offset: .zero,
                fitToWidth: context.fitToWidth,
                lineMetrics: indexLineMetrics
            )
            indexLayouts.append(item)
            let lineWidth = item?.lines.first?.frame.width ?? 0
            if lineWidth > 0 {
                maxIndexWidth = max(maxIndexWidth, lineWidth)
            }
        } else {
            indexLayouts.append(nil)
            maxIndexWidth = max(maxIndexWidth, hasTaskItem ? checklistMarkerSize : 5.0)
        }
    }

    let rtl = listItems.contains(where: { item in
        if case let .text(text, _, _) = item { return instantPageRichTextContainsRTL(text) }
        return false
    })
    let markerColumnWidth = maxIndexWidth + indexSpacing
    var items: [InstantPageV2LaidOutItem] = []
    var contentHeight: CGFloat = 0.0
    let textOriginX = rtl ? horizontalInset : (horizontalInset + markerColumnWidth)
    let checkboxColors = InstantPageV2CheckboxColors(
        background: context.theme.panelAccentColor,
        foreground: context.theme.checkboxForeground,
        border: context.theme.checklistBorderColor
    )
    let textBoundingWidth = boundingWidth - horizontalInset * 2.0 - markerColumnWidth

    for (i, listItem) in listItems.enumerated() {
        if i != 0 {
            contentHeight += context.fitToWidth ? 4.0 : 18.0
        }

        let textStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
        setupStyleStackV2(textStack, theme: context.theme, category: .paragraph, link: false)
        let textLineMetrics = InstantPageTextLineMetrics(styleStack: textStack)
        let textValue: RichText
        let nestedBlocks: [InstantPageBlock]
        let itemNumber: String?
        let itemChecked: Bool?
        switch listItem {
        case let .text(text, number, checked):
            textValue = text
            nestedBlocks = []
            itemNumber = number
            itemChecked = checked
        case let .blocks(blocks, number, checked):
            textValue = .plain("")
            nestedBlocks = blocks
            itemNumber = number
            itemChecked = checked
        case .unknown:
            textValue = .plain("")
            nestedBlocks = []
            itemNumber = nil
            itemChecked = nil
        }
        let taskChecked: Bool?
        if let itemChecked {
            taskChecked = itemChecked
        } else {
            switch itemNumber {
            case markdownTaskListCheckedNumber:
                taskChecked = true
            case markdownTaskListUncheckedNumber:
                taskChecked = false
            default:
                taskChecked = nil
            }
        }

        var itemContentHeight: CGFloat = 0.0
        var inlineTextItem: InstantPageTextItem? = nil
        var blockItems: [InstantPageV2LaidOutItem] = []
        var lineMidY: CGFloat = contentHeight
        var firstBlockLineMidY: CGFloat? = nil
        let originY = contentHeight

        if !nestedBlocks.isEmpty {
            var previousSubBlock: InstantPageBlock?
            var subContentHeight: CGFloat = 0.0
            for subBlock in nestedBlocks {
                let subItems = layoutBlockV2(
                    subBlock,
                    boundingWidth: textBoundingWidth,
                    horizontalInset: 0,
                    isCover: false,
                    previousItems: blockItems,
                    context: &context
                )
                let effectiveSubBlock: InstantPageBlock = subItems.contains(where: {
                    if case .unsupported = $0 { return true }
                    return false
                }) ? .unsupported : subBlock
                let subLocalMaxY: CGFloat = subItems.map { $0.frame.maxY }.max() ?? 0.0
                let spacing: CGFloat = (previousSubBlock != nil && subLocalMaxY > 0.0) ? spacingBetweenBlocks(upper: previousSubBlock, lower: effectiveSubBlock, fitToWidth: context.fitToWidth) : 0.0
                let offsetY = subContentHeight + spacing
                let translated = subItems.map { $0.offsetBy(CGPoint(x: textOriginX, y: contentHeight + offsetY)) }

                if firstBlockLineMidY == nil {
                    for ti in translated {
                        if case let .text(tv) = ti, let firstLine = tv.textItem.lines.first {
                            firstBlockLineMidY = tv.frame.minY + firstLine.frame.midY
                            break
                        }
                    }
                }

                var blockMaxY: CGFloat = offsetY
                for ti in translated {
                    blockMaxY = max(blockMaxY, ti.frame.maxY - contentHeight)
                }
                blockItems.append(contentsOf: translated)
                subContentHeight = blockMaxY
                previousSubBlock = effectiveSubBlock
            }
            itemContentHeight = subContentHeight
        } else {
            let attributed = attributedStringForRichText(textValue, styleStack: textStack, inlineButtonMaxWidth: textBoundingWidth)
            let (textItem, _, textSize) = layoutTextItemWithStringV2(
                attributed,
                boundingWidth: textBoundingWidth,
                offset: CGPoint(x: textOriginX, y: contentHeight),
                media: context.media,
                webpage: context.webpage,
                fitToWidth: context.fitToWidth,
                computeRevealCharacterRects: context.computeRevealCharacterRects,
                lineMetrics: textLineMetrics
            )
            inlineTextItem = textItem
            itemContentHeight = textSize.height
            if let textItem, let firstLine = textItem.lines.first {
                lineMidY = textItem.frame.minY + firstLine.frame.midY
            } else if let textItem {
                lineMidY = textItem.frame.midY
            } else {
                lineMidY = contentHeight + 8.0
            }
        }

        let markerKind: InstantPageV2ListMarkerKind
        let markerFrame: CGRect

        if let checked = taskChecked {
            markerKind = .checklist(checked: checked, colors: checkboxColors)
            let boxSize: CGFloat = 18.0
            let centerY = nestedBlocks.isEmpty ? lineMidY : (firstBlockLineMidY ?? (originY + boxSize / 2.0))
            let markerY = floor(centerY - boxSize / 2.0)
            markerFrame = CGRect(
                x: rtl ? (boundingWidth - horizontalInset - boxSize) : (horizontalInset + maxIndexWidth - boxSize),
                y: markerY,
                width: boxSize,
                height: boxSize
            )
            let boxBottom = markerY + boxSize - contentHeight
            itemContentHeight = max(itemContentHeight, boxBottom)
        } else if ordered, let indexItem = indexLayouts[i] {
            let markerWidth = indexItem.lines.first?.frame.width ?? indexItem.frame.width
            let numberHeight: CGFloat = 20.0
            markerKind = .number(indexItem.attributedString.string)
            let markerY: CGFloat = nestedBlocks.isEmpty ? floor(lineMidY - numberHeight / 2.0) : originY
            markerFrame = CGRect(
                x: rtl ? (boundingWidth - horizontalInset - markerWidth) : (horizontalInset + (maxIndexWidth - markerWidth)),
                y: markerY,
                width: markerWidth,
                height: numberHeight
            )
        } else {
            markerKind = .bullet
            let bulletSize: CGFloat = 5.0
            let markerY: CGFloat = nestedBlocks.isEmpty ? floor(lineMidY - bulletSize / 2.0) : originY
            markerFrame = CGRect(
                x: rtl ? (boundingWidth - horizontalInset - bulletSize) : horizontalInset,
                y: markerY,
                width: bulletSize,
                height: bulletSize
            )
        }
        items.append(.listMarker(InstantPageV2ListMarkerItem(
            frame: markerFrame,
            kind: markerKind,
            color: context.theme.textCategories.paragraph.color
        )))
        if let textItem = inlineTextItem {
            items.append(.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem)))
        }
        items.append(contentsOf: blockItems)
        contentHeight += itemContentHeight
    }
    return items
}


private func layoutFormulaV2(
    latex: String,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    previousItems: [InstantPageV2LaidOutItem],
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let textColor = context.theme.textCategories.paragraph.color
    let fontSize = context.theme.textCategories.paragraph.font.size

    guard let attachment = instantPageMathAttachment(latex: latex,
                                                     fontSize: fontSize,
                                                     textColor: textColor,
                                                     mode: .block) else {
        return layoutSimpleTextV2(.plain(latex),
                                  category: .paragraph,
                                  boundingWidth: boundingWidth,
                                  horizontalInset: horizontalInset,
                                  context: &context)
    }

    let availableWidth = boundingWidth - horizontalInset * 2.0
    let renderedSize = attachment.rendered.size

    if renderedSize.width > availableWidth {
        let frame = CGRect(x: 0.0, y: 0.0, width: boundingWidth, height: renderedSize.height)
        let item = InstantPageV2FormulaItem(
            frame: frame,
            attachment: attachment,
            isScrollable: true,
            imageFrame: CGRect(x: horizontalInset, y: 0.0,
                               width: renderedSize.width, height: renderedSize.height),
            scrollContentSize: CGSize(width: renderedSize.width + horizontalInset * 2.0,
                                      height: renderedSize.height)
        )
        return [.formula(item)]
    } else {
        let frame = CGRect(x: horizontalInset, y: 0.0,
                           width: renderedSize.width, height: renderedSize.height)
        let item = InstantPageV2FormulaItem(
            frame: frame,
            attachment: attachment,
            isScrollable: false,
            imageFrame: CGRect(origin: .zero, size: renderedSize),
            scrollContentSize: renderedSize
        )
        return [.formula(item)]
    }
}


private func detailsCountV2(in blocks: [InstantPageBlock]) -> Int {
    var count = 0
    for block in blocks {
        switch block {
        case let .details(_, children, _):
            count += 1 + detailsCountV2(in: children)
        case let .cover(child):
            count += detailsCountV2(in: [child])
        case let .blockQuote(children, _, _):
            count += detailsCountV2(in: children)
        case let .list(items, _):
            for item in items {
                if case let .blocks(children, _, _) = item {
                    count += detailsCountV2(in: children)
                }
            }
        default:
            break
        }
    }
    return count
}

private func layoutDetailsV2(
    title: RichText,
    blocks: [InstantPageBlock],
    defaultExpanded: Bool,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let index = context.detailsIndexCounter
    context.detailsIndexCounter += 1

    let minimumTitleHeight: CGFloat = 36.0
    let titleVerticalPadding: CGFloat = 15.0
    let chevronReserve: CGFloat = 32.0
    let titleHorizontalInset: CGFloat = 23.0

    let titleStyleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(titleStyleStack, theme: context.theme, category: .paragraph, link: false)
    titleStyleStack.push(.semibold)
    let titleLineMetrics = InstantPageTextLineMetrics(styleStack: titleStyleStack)
    let (titleTextItem, _, _) = layoutTextItemWithStringV2(
        attributedStringForRichText(title, styleStack: titleStyleStack),
        boundingWidth: boundingWidth - horizontalInset * 2.0 - chevronReserve,
        offset: .zero,
        media: context.media,
        webpage: context.webpage,
        fitToWidth: context.fitToWidth,
        computeRevealCharacterRects: context.computeRevealCharacterRects,
        lineMetrics: titleLineMetrics
    )
    guard let titleTextItem = titleTextItem else {
        context.detailsIndexCounter += detailsCountV2(in: blocks)
        return []
    }

    let isExpanded = context.toggledDetails.contains(index) ? !defaultExpanded : defaultExpanded

    let titleHeight = max(minimumTitleHeight, titleTextItem.frame.height + titleVerticalPadding)
    titleTextItem.frame.origin.x = context.rtl
        ? (boundingWidth - horizontalInset - titleHorizontalInset - titleTextItem.frame.width)
        : (horizontalInset + titleHorizontalInset)
    titleTextItem.frame.origin.y = floorToScreenPixels(
        System.backingScale,
        (titleHeight - titleTextItem.frame.height) * 0.5
    )
    let titleFrame = CGRect(x: 0.0, y: 0.0, width: boundingWidth, height: titleHeight)

    var innerLayout: InstantPageV2Layout?
    var totalHeight = titleHeight
    if isExpanded {
        let layout = layoutBlockSequenceV2(
            blocks,
            boundingWidth: boundingWidth,
            horizontalInset: horizontalInset,
            context: &context,
            kind: .detail
        )
        innerLayout = layout
        totalHeight += layout.contentSize.height
    }

    var item = InstantPageV2DetailsItem(
        frame: CGRect(x: 0.0, y: 0.0, width: boundingWidth, height: totalHeight),
        index: index,
        sideInset: horizontalInset,
        titleTextItem: titleTextItem,
        titleFrame: titleFrame,
        isExpanded: isExpanded,
        innerLayout: innerLayout,
        defaultExpanded: defaultExpanded,
        rtl: context.rtl
    )
    if !isExpanded {
        let collapsedContext = context
        context.detailsIndexCounter += detailsCountV2(in: blocks)
        item.layoutCollapsedContent = {
            var context = collapsedContext
            return layoutBlockSequenceV2(blocks, boundingWidth: boundingWidth, horizontalInset: horizontalInset, context: &context, kind: .detail)
        }
    }
    return [.details(item)]
}


private let v2TableCellInsets = NSEdgeInsets(top: 14.0, left: 12.0, bottom: 14.0, right: 12.0)
private let v2TableBorderWidth: CGFloat = 1.0
private let v2TableMinimumTextWidth: Int = 84
private let v2TableCaptionSkip: CGFloat = 6.0
public let v2TableScrollerHeight: CGFloat = 20.0
private let v2TableNaturalMeasureWidth: CGFloat = 65535.0

private struct V2TableCellWidth {
    let row: Int
    let columns: Range<Int>
    let minimum: Int
    let preferred: Int
}

private func v2TableSpanWidth(_ widths: [Int], _ columns: Range<Int>, border: Int) -> Int {
    return widths[columns].reduce(0, +) + max(columns.count - 1, 0) * border
}

private func v2TableSpread(_ widths: inout [Int], _ columns: Range<Int>, _ delta: Int) {
    if delta <= 0 || columns.isEmpty {
        return
    }
    let base = delta / columns.count
    let tail = delta % columns.count
    for (offset, column) in columns.enumerated() {
        widths[column] += base + (offset < tail ? 1 : 0)
    }
}

private func v2TableColumnWidths(_ cells: [V2TableCellWidth], columnCount: Int, emptyMinimum: Int, availableWidth: Int, border: Int) -> [Int] {
    var widths = [Int](repeating: emptyMinimum, count: columnCount)
    if columnCount == 0 {
        return widths
    }
    let single = cells.filter { $0.columns.count == 1 }
    let spanned = cells.filter { $0.columns.count > 1 }.sorted {
        ($0.columns.count, $0.row, $0.columns.lowerBound) < ($1.columns.count, $1.row, $1.columns.lowerBound)
    }

    for cell in single {
        widths[cell.columns.lowerBound] = max(widths[cell.columns.lowerBound], cell.minimum)
    }
    for cell in spanned {
        let deficit = cell.minimum - v2TableSpanWidth(widths, cell.columns, border: border)
        v2TableSpread(&widths, cell.columns, deficit)
    }

    var extra = availableWidth - (widths.reduce(0, +) + (columnCount + 1) * border)
    if extra < 0 {
        return widths
    }

    var deficits = [Int](repeating: 0, count: columnCount)
    for cell in single {
        deficits[cell.columns.lowerBound] = max(deficits[cell.columns.lowerBound], cell.preferred - widths[cell.columns.lowerBound])
    }
    while extra > 0 {
        let active = deficits.filter { $0 > 0 }.count
        if active == 0 {
            break
        }
        let step = max(extra / active, 1)
        for column in 0 ..< columnCount where deficits[column] > 0 && extra > 0 {
            let delta = min(deficits[column], step, extra)
            widths[column] += delta
            deficits[column] -= delta
            extra -= delta
        }
    }

    for cell in spanned where extra > 0 {
        let delta = min(max(cell.preferred - v2TableSpanWidth(widths, cell.columns, border: border), 0), extra)
        v2TableSpread(&widths, cell.columns, delta)
        extra -= delta
    }
    v2TableSpread(&widths, 0 ..< columnCount, extra)
    return widths
}

private func v2TableWidestAttachmentWidth(_ string: NSAttributedString) -> CGFloat {
    var result: CGFloat = 0.0
    string.enumerateAttributes(in: NSMakeRange(0, string.length), options: []) { attributes, _, _ in
        if let dimensions = attributes[.instantPageMediaDimensionsAttribute] as? CGSize {
            result = max(result, dimensions.width)
        }
        if let attachment = attributes[.instantPageFormulaAttribute] as? InstantPageMathAttachment {
            result = max(result, attachment.rendered.size.width)
        }
    }
    return result
}

private func layoutTableV2(
    title: RichText,
    rows unclampedRows: [InstantPageTableRow],
    bordered: Bool,
    striped: Bool,
    compact: Bool,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    if unclampedRows.isEmpty {
        return []
    }
    
    let rows = tableRowsWithClampedSpans(unclampedRows)

    let cellInsets = compact
        ? NSEdgeInsets(top: v2TableCellInsets.top / 2.0, left: v2TableCellInsets.left / 2.0, bottom: v2TableCellInsets.bottom / 2.0, right: v2TableCellInsets.right / 2.0)
        : v2TableCellInsets

    let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
    setupStyleStackV2(styleStack, theme: context.theme, category: .paragraph, link: false)
    let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)

    let borderWidth = bordered ? v2TableBorderWidth : 0.0
    let totalCellPadding = cellInsets.left + cellInsets.right
    let border = Int(borderWidth)
    let paddingWidth = Int(totalCellPadding)
    let spaceWidth = Int(ceil(
        attributedStringForRichText(.plain(" "), styleStack: styleStack).size().width
    ))

    var cellWidths: [V2TableCellWidth] = []
    var columnCount: Int = 0
    var rowSpans: [Int: [(Int, Int)]] = [:]

    var r: Int = 0
    for row in rows {
        var i: Int = 0

        for cell in row.cells {
            if let rowSpan = rowSpans[r] {
                for columnAndSpan in rowSpan {
                    if columnAndSpan.0 == i {
                        i += columnAndSpan.1
                    } else {
                        break
                    }
                }
            }

            let colspan = cell.colspan > 1 ? Int(clamping: cell.colspan) : 1

            if let text = cell.text {
                let attrStr = attributedStringForRichText(text, styleStack: styleStack, isInsideTableCell: true)
                if attrStr.length > 0, let naturalItem = layoutTextItemWithStringV2(
                    attrStr,
                    boundingWidth: v2TableNaturalMeasureWidth,
                    offset: .zero,
                    media: context.media,
                    webpage: context.webpage,
                    lineMetrics: lineMetrics
                ).0 {
                    let naturalWidth = Int(naturalItem.effectiveWidth())
                    let minimumTextWidth = max(v2TableMinimumTextWidth, Int(ceil(v2TableWidestAttachmentWidth(attrStr))))
                    cellWidths.append(V2TableCellWidth(
                        row: r,
                        columns: i ..< i + colspan,
                        minimum: min(naturalWidth, minimumTextWidth) + paddingWidth,
                        preferred: naturalWidth + paddingWidth
                    ))
                }
            }

            if cell.rowspan > 1 {
                for j in r ..< r + Int(cell.rowspan) {
                    if rowSpans[j] == nil {
                        rowSpans[j] = [(i, colspan)]
                    } else {
                        rowSpans[j]!.append((i, colspan))
                    }
                }
            }

            i += colspan
        }
        columnCount = max(columnCount, i)
        r += 1
    }

    let columnWidths = v2TableColumnWidths(
        cellWidths,
        columnCount: columnCount,
        emptyMinimum: paddingWidth + max(spaceWidth, 1),
        availableWidth: Int(floor(boundingWidth)),
        border: border
    )
    var finalColumnWidths: [Int: CGFloat] = [:]
    for (column, width) in columnWidths.enumerated() {
        finalColumnWidths[column] = CGFloat(width + border)
    }
    let totalWidth: CGFloat = columnCount == 0 ? boundingWidth : CGFloat(columnWidths.reduce(0, +) + (columnCount + 1) * border)

    struct PendingCell {
        let rowIndex: Int
        let column: Int
        let colspan: Int
        let rowspan: Int
        let cell: InstantPageTableCell
        var frame: CGRect
        let isHeader: Bool
        let isFilled: Bool
        let subLayout: InstantPageV2Layout?
        let subLayoutContentHeight: CGFloat
    }

    var finalizedCells: [InstantPageV2TableCell] = []
    var origin = CGPoint(x: borderWidth / 2.0, y: borderWidth / 2.0)
    var totalHeight: CGFloat = 0.0
    var rowHeights: [Int: CGFloat] = [:]
    var awaitingSpanCells: [Int: [(Int, PendingCell)]] = [:]

    for i in 0 ..< rows.count {
        let row = rows[i]
        var maxRowHeight: CGFloat = 0.0
        var isEmptyRow = true
        origin.x = borderWidth / 2.0

        var k: Int = 0
        var rowCells: [PendingCell] = []

        for cell in row.cells {
            if let cells = awaitingSpanCells[i] {
                for colAndCell in cells {
                    if colAndCell.1.column == k {
                        for j in 0 ..< colAndCell.1.colspan {
                            if let width = finalColumnWidths[k + j] {
                                origin.x += width
                            }
                        }
                        k += colAndCell.1.colspan
                    } else {
                        break
                    }
                }
            }

            let colspan: Int = cell.colspan > 1 ? Int(clamping: cell.colspan) : 1
            let rowspan: Int = cell.rowspan > 1 ? Int(clamping: cell.rowspan) : 1

            var cellWidth: CGFloat = 0.0
            for j in 0 ..< colspan {
                if let width = finalColumnWidths[k + j] {
                    cellWidth += width
                }
            }

            var subLayout: InstantPageV2Layout?
            var subLayoutHeight: CGFloat = 0.0
            if let cellText = cell.text {
                let cellContentWidth = cellWidth - borderWidth - totalCellPadding
                if cellContentWidth > 0.0 {
                    let wasInsideTableCell = context.isInsideTableCell
                    context.isInsideTableCell = true
                    let cellLayout = layoutBlockSequenceV2(
                        [.paragraph(cellText)],
                        boundingWidth: cellContentWidth,
                        horizontalInset: 0.0,
                        context: &context,
                        kind: .cell
                    )
                    context.isInsideTableCell = wasInsideTableCell
                    subLayout = cellLayout
                    subLayoutHeight = cellLayout.contentSize.height
                    isEmptyRow = false
                }
            }

            var cellHeight: CGFloat?
            if subLayout != nil {
                cellHeight = ceil(subLayoutHeight) + cellInsets.top + cellInsets.bottom
            }

            var isFilled = cell.header
            if !isFilled && striped {
                isFilled = i % 2 == 0
            }

            let pendingCell = PendingCell(
                rowIndex: i,
                column: k,
                colspan: colspan,
                rowspan: rowspan,
                cell: cell,
                frame: CGRect(x: origin.x, y: origin.y, width: cellWidth, height: cellHeight ?? 20.0),
                isHeader: cell.header,
                isFilled: isFilled,
                subLayout: subLayout,
                subLayoutContentHeight: subLayoutHeight
            )

            if rowspan == 1 {
                rowCells.append(pendingCell)
                if let ch = cellHeight {
                    maxRowHeight = max(maxRowHeight, ch)
                }
            } else {
                for j in i ..< i + rowspan {
                    if awaitingSpanCells[j] == nil {
                        awaitingSpanCells[j] = [(k, pendingCell)]
                    } else {
                        awaitingSpanCells[j]!.append((k, pendingCell))
                    }
                }
            }

            k += colspan
            origin.x += cellWidth
        }

        let tableHeaderColor = context.theme.tableHeaderColor

        let finalizeCell: (PendingCell, CGFloat) -> InstantPageV2TableCell = { pending, height in
            let finalFrame = CGRect(x: pending.frame.minX, y: pending.frame.minY,
                                    width: pending.frame.width, height: height)

            var subLayout = pending.subLayout
            if var sl = subLayout {
                let textHeight = pending.subLayoutContentHeight
                let vertOffset: CGFloat
                switch pending.cell.verticalAlignment {
                case .top:
                    vertOffset = cellInsets.top
                case .middle:
                    vertOffset = max(cellInsets.top, (height - textHeight) / 2.0)
                case .bottom:
                    vertOffset = max(cellInsets.top, height - textHeight - cellInsets.bottom)
                }
                let horizOffset: CGFloat
                switch pending.cell.alignment {
                case .left:
                    horizOffset = borderWidth + cellInsets.left
                case .center:
                    horizOffset = borderWidth + (pending.frame.width - borderWidth - sl.contentSize.width) / 2.0
                case .right:
                    horizOffset = pending.frame.width - sl.contentSize.width - cellInsets.right
                }
                let delta = CGPoint(x: horizOffset, y: vertOffset)
                let translatedItems = sl.items.map { $0.offsetBy(delta) }
                sl = InstantPageV2Layout(contentSize: sl.contentSize, items: translatedItems, detailsIndices: sl.detailsIndices)
                subLayout = sl
            }

            let bgColor: NSColor? = pending.isFilled ? tableHeaderColor : nil
            let hAlign: NSTextAlignment
            switch pending.cell.alignment {
            case .left: hAlign = .left
            case .center: hAlign = .center
            case .right: hAlign = .right
            }
            let vAlign: InstantPageV2TableVerticalAlignment
            switch pending.cell.verticalAlignment {
            case .top: vAlign = .top
            case .middle: vAlign = .middle
            case .bottom: vAlign = .bottom
            }

            return InstantPageV2TableCell(
                frame: finalFrame,
                isHeader: pending.isHeader,
                horizontalAlignment: hAlign,
                verticalAlignment: vAlign,
                backgroundColor: bgColor,
                subLayout: subLayout
            )
        }

        if !isEmptyRow {
            rowHeights[i] = maxRowHeight
        } else {
            rowHeights[i] = 0.0
            maxRowHeight = 0.0
        }

        var completedSpans = [Int: Set<Int>]()
        if let cells = awaitingSpanCells[i] {
            isEmptyRow = false
            for colAndCell in cells {
                let pending = colAndCell.1
                let utmostRow = pending.rowIndex + pending.rowspan - 1
                if rowHeights[utmostRow] == nil {
                    continue
                }

                var cellHeight: CGFloat = 0.0
                for k in pending.rowIndex ..< utmostRow + 1 {
                    if let h = rowHeights[k] { cellHeight += h }
                    if completedSpans[k] == nil {
                        completedSpans[k] = Set([colAndCell.0])
                    } else {
                        completedSpans[k]!.insert(colAndCell.0)
                    }
                }

                if pending.frame.height > cellHeight {
                    let delta = pending.frame.height - cellHeight
                    cellHeight = pending.frame.height
                    maxRowHeight += delta
                    rowHeights[i] = maxRowHeight
                }

                finalizedCells.append(finalizeCell(pending, cellHeight))
            }
        }

        for pending in rowCells {
            finalizedCells.append(finalizeCell(pending, maxRowHeight))
        }

        if !completedSpans.isEmpty {
            awaitingSpanCells = awaitingSpanCells.reduce([Int: [(Int, PendingCell)]]()) { current, rowAndValue in
                var result = current
                let cells = rowAndValue.value.filter { column, _ in
                    if let completedSet = completedSpans[rowAndValue.key] {
                        return !completedSet.contains(column)
                    }
                    return true
                }
                if !cells.isEmpty { result[rowAndValue.key] = cells }
                return result
            }
        }

        if !isEmptyRow {
            totalHeight += maxRowHeight
            origin.y += maxRowHeight
        }
    }
    totalHeight += borderWidth


    var horizontalLines: [CGRect] = []
    var verticalLines: [CGRect] = []
    let lineWidth = v2TableBorderWidth
    if bordered {
        for cell in finalizedCells {
            let isFirstRow = cell.frame.minY <= lineWidth / 2.0 + 0.5
            let isFirstCol = cell.frame.minX <= lineWidth / 2.0 + 0.5
            if !isFirstRow {
                horizontalLines.append(CGRect(x: cell.frame.minX, y: cell.frame.minY,
                                              width: cell.frame.width, height: lineWidth))
            }
            if !isFirstCol {
                verticalLines.append(CGRect(x: cell.frame.minX, y: cell.frame.minY,
                                            width: lineWidth, height: cell.frame.height))
            }
        }
    }
    let outerInset = bordered ? lineWidth : 0.0
    let gridContentWidth = totalWidth - outerInset
    let gridContentHeight = totalHeight - outerInset
    let outerFrame = CGRect(x: outerInset / 2.0, y: outerInset / 2.0,
                            width: gridContentWidth, height: gridContentHeight)
    let outerCornerRadius: CGFloat = 10.0

    let tableVisibleWidth = boundingWidth + horizontalInset * 2.0

    var titleSubLayout: InstantPageV2Layout?
    var titleFrame: CGRect?
    if case .empty = title {
    } else {
        let titleString = attributedStringForRichText(title, styleStack: styleStack, inlineButtonMaxWidth: boundingWidth, isInsideTableCell: context.isInsideTableCell)
        let (titleItem, _, _) = layoutTextItemWithStringV2(
            titleString,
            boundingWidth: boundingWidth,
            alignment: .center,
            offset: CGPoint(x: horizontalInset, y: 0.0),
            media: context.media,
            webpage: context.webpage,
            fitToWidth: context.fitToWidth,
            computeRevealCharacterRects: context.computeRevealCharacterRects,
            lineMetrics: lineMetrics
        )
        if let titleItem {
            let titleHeight = ceil(titleItem.frame.height)
            titleSubLayout = InstantPageV2Layout(
                contentSize: CGSize(width: tableVisibleWidth, height: titleHeight),
                items: [.text(InstantPageV2TextItem(frame: titleItem.frame, textItem: titleItem))],
                detailsIndices: []
            )
            titleFrame = CGRect(x: 0.0, y: 0.0, width: tableVisibleWidth, height: titleHeight + v2TableCaptionSkip)
        }
    }

    let hasHorizontalScroller = totalWidth - tableVisibleWidth > System.pixel
    let scrollerReserve: CGFloat = hasHorizontalScroller ? v2TableScrollerHeight : 0
    let tableFrame = CGRect(x: 0.0, y: 0.0,
                            width: tableVisibleWidth,
                            height: totalHeight + (titleFrame?.height ?? 0.0) + scrollerReserve)
    let contentSize = CGSize(
        width: totalWidth,
        height: totalHeight + (titleFrame?.height ?? 0.0)
    )

    let tableItem = InstantPageV2TableItem(
        frame: tableFrame,
        titleSubLayout: titleSubLayout,
        titleFrame: titleFrame,
        contentSize: contentSize,
        cells: finalizedCells,
        horizontalLines: horizontalLines,
        verticalLines: verticalLines,
        outerFrame: outerFrame,
        outerCornerRadius: outerCornerRadius,
        bordered: bordered,
        striped: striped,
        borderColor: context.theme.tableBorderColor
    )
    return [.table(tableItem)]
}


private func layoutCaptionAndCreditV2(
    _ caption: InstantPageCaption,
    offset: CGFloat,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> ([InstantPageV2LaidOutItem], CGFloat) {
    var items: [InstantPageV2LaidOutItem] = []
    var y = offset
    var totalHeight: CGFloat = 0.0
    var rtl = context.rtl
    var captionIsEmpty = true
    let mediaCaptionSpacing: CGFloat = 7.0

    if case .empty = caption.text {
    } else {
        captionIsEmpty = false
        totalHeight += mediaCaptionSpacing
        y += mediaCaptionSpacing
        let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
        setupStyleStackV2(styleStack, theme: context.theme, category: .caption, link: false)
        let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)
        let attributedString = attributedStringForRichText(caption.text, styleStack: styleStack, inlineButtonMaxWidth: boundingWidth - horizontalInset * 2.0)
        let (textItem, _, captionSize) = layoutTextItemWithStringV2(
            attributedString,
            boundingWidth: boundingWidth - horizontalInset * 2.0,
            offset: CGPoint(x: horizontalInset, y: y),
            media: context.media,
            webpage: context.webpage,
            fitToWidth: context.fitToWidth,
            computeRevealCharacterRects: context.computeRevealCharacterRects,
            lineMetrics: lineMetrics
        )
        totalHeight += captionSize.height
        y += captionSize.height
        if let textItem {
            items.append(.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem)))
            rtl = textItem.containsRTL
        }
    }

    if case .empty = caption.credit {
    } else {
        if captionIsEmpty {
            totalHeight += mediaCaptionSpacing
            y += mediaCaptionSpacing
        } else {
            totalHeight += 10.0
            y += 10.0
        }
        let styleStack = InstantPageTextStyleStack(buttonsEnabled: context.buttonsEnabled)
        setupStyleStackV2(styleStack, theme: context.theme, category: .credit, link: false)
        let lineMetrics = InstantPageTextLineMetrics(styleStack: styleStack)
        let attributedString = attributedStringForRichText(caption.credit, styleStack: styleStack, inlineButtonMaxWidth: boundingWidth - horizontalInset * 2.0)
        let (textItem, _, creditSize) = layoutTextItemWithStringV2(
            attributedString,
            boundingWidth: boundingWidth - horizontalInset * 2.0,
            alignment: rtl ? .right : .natural,
            offset: CGPoint(x: horizontalInset, y: y),
            media: context.media,
            webpage: context.webpage,
            fitToWidth: context.fitToWidth,
            computeRevealCharacterRects: context.computeRevealCharacterRects,
            lineMetrics: lineMetrics
        )
        totalHeight += creditSize.height
        if let textItem {
            items.append(.text(InstantPageV2TextItem(frame: textItem.frame, textItem: textItem)))
        }
    }

    return (items, totalHeight)
}

private func layoutTypedMediaWithCaptionV2(
    produceItem: (CGRect, CGFloat) -> InstantPageV2LaidOutItem,
    naturalSize: CGSize,
    caption: InstantPageCaption,
    isCover: Bool,
    cornerRadius: CGFloat,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    bleed: Bool = false,
    capHeight: Bool = false,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let columnWidth = boundingWidth - horizontalInset * 2.0
    func fit(_ width: CGFloat) -> CGSize {
        guard naturalSize.width > 0.0, naturalSize.height > 0.0 else {
            return CGSize(width: width, height: naturalSize.height)
        }
        let scale = min(width / naturalSize.width, 1.0)
        return CGSize(width: floor(naturalSize.width * scale), height: floor(naturalSize.height * scale))
    }

    var bleedAmount = bleed ? context.mediaBleed : 0.0
    var availableWidth = columnWidth + bleedAmount * 2.0
    var scaledSize = fit(availableWidth)
    if bleedAmount > 0.0, scaledSize.width < availableWidth - 0.5 {
        bleedAmount = 0.0
        availableWidth = columnWidth
        scaledSize = fit(availableWidth)
    }
    if capHeight {
        scaledSize.height = min(scaledSize.height, min(1000.0, availableWidth))
    }

    let mediaX = horizontalInset - bleedAmount + floor((availableWidth - scaledSize.width) / 2.0)
    let mediaFrame = CGRect(x: mediaX, y: 0.0, width: scaledSize.width, height: scaledSize.height)
    let effectiveCorner: CGFloat = bleedAmount > 0 ? 0.0 : cornerRadius
    var result: [InstantPageV2LaidOutItem] = [produceItem(mediaFrame, effectiveCorner)]

    let (captionItems, captionHeight) = layoutCaptionAndCreditV2(
        caption, offset: scaledSize.height,
        boundingWidth: boundingWidth, horizontalInset: horizontalInset,
        context: &context
    )
    result.append(contentsOf: captionItems)

    if isCover && captionHeight > 0.0 {
        if let lastIndex = result.lastIndex(where: { if case .text = $0 { return true } else { return false } }) {
            if case var .text(lastText) = result[lastIndex] {
                lastText.frame = CGRect(origin: lastText.frame.origin,
                                        size: CGSize(width: lastText.frame.width, height: lastText.frame.height + 14.0))
                result[lastIndex] = .text(lastText)
            }
        }
    }

    return result
}

private func layoutMediaWithCaptionV2(
    kind: InstantPageV2MediaPlaceholderKind,
    naturalSize: CGSize,
    caption: InstantPageCaption,
    isCover: Bool,
    cornerRadius: CGFloat,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let availableWidth = boundingWidth - horizontalInset * 2.0
    let scaledSize: CGSize
    if naturalSize.width > 0.0 && naturalSize.height > 0.0 {
        let scale = min(availableWidth / naturalSize.width, 1.0)
        scaledSize = CGSize(width: floor(naturalSize.width * scale), height: floor(naturalSize.height * scale))
    } else {
        scaledSize = CGSize(width: availableWidth, height: naturalSize.height)
    }

    let placeholderFrame = CGRect(x: horizontalInset, y: 0.0,
                                  width: scaledSize.width, height: scaledSize.height)
    var result: [InstantPageV2LaidOutItem] = [.mediaPlaceholder(InstantPageV2MediaPlaceholderItem(
        frame: placeholderFrame, kind: kind, cornerRadius: cornerRadius
    ))]

    let (captionItems, captionHeight) = layoutCaptionAndCreditV2(
        caption, offset: scaledSize.height,
        boundingWidth: boundingWidth, horizontalInset: horizontalInset,
        context: &context
    )
    result.append(contentsOf: captionItems)

    if isCover && captionHeight > 0.0 {
        if let lastIndex = result.lastIndex(where: { if case .text = $0 { return true } else { return false } }) {
            if case var .text(lastText) = result[lastIndex] {
                lastText.frame = CGRect(origin: lastText.frame.origin,
                                        size: CGSize(width: lastText.frame.width, height: lastText.frame.height + 14.0))
                result[lastIndex] = .text(lastText)
            }
        }
    }

    return result
}


private func collageMediaItemV2(_ block: InstantPageBlock, frame: CGRect, context: inout LayoutContextV2) -> InstantPageV2LaidOutItem? {
    let webpage = context.webpage
    switch block {
    case let .image(id, caption, url, webpageId, spoiler):
        if let image = context.media[id] as? TelegramMediaImage {
            let mediaUrl: InstantPageUrlItem? = url.flatMap { InstantPageUrlItem(url: $0, webpageId: webpageId) }
            let mediaIndex = context.mediaIndexCounter
            context.mediaIndexCounter += 1
            let media = InstantPageMedia(index: mediaIndex, media: image, webpage: webpage,
                                         url: mediaUrl, caption: caption.text, credit: caption.credit)
            return .mediaImage(InstantPageV2MediaImageItem(frame: frame, cornerRadius: 0.0,
                                                           media: media, webPage: webpage, attributes: [], spoiler: spoiler))
        }
    case let .video(id, caption, _, _, spoiler):
        if let file = context.media[id] as? TelegramMediaFile {
            let mediaIndex = context.mediaIndexCounter
            context.mediaIndexCounter += 1
            let media = InstantPageMedia(index: mediaIndex, media: file, webpage: webpage,
                                         url: nil, caption: caption.text, credit: caption.credit)
            return .mediaVideo(InstantPageV2MediaVideoItem(frame: frame, cornerRadius: 0.0,
                                                           media: media, webPage: webpage, attributes: [], isFile: false, spoiler: spoiler))
        }
    default:
        break
    }
    return nil
}

private func layoutCollageV2(
    _ blocks: [InstantPageBlock],
    caption: InstantPageCaption,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let bleed = context.mediaBleed
    let leftX = horizontalInset - bleed
    let availableWidth = boundingWidth - horizontalInset * 2.0 + bleed * 2.0
    var mediaBlocks: [(block: InstantPageBlock, media: Media)] = []
    var hasUnrenderableBlock = false
    for block in blocks {
        switch block {
        case let .image(id, _, _, _, _):
            if let media = context.media[id] as? TelegramMediaImage {
                mediaBlocks.append((block, media))
            } else {
                hasUnrenderableBlock = true
            }
        case let .video(id, _, _, _, _):
            if let media = context.media[id] as? TelegramMediaFile {
                mediaBlocks.append((block, media))
            } else {
                hasUnrenderableBlock = true
            }
        default:
            hasUnrenderableBlock = true
        }
    }
    if context.unsupportedStyle != nil && (hasUnrenderableBlock || mediaBlocks.count != blocks.count) {
        return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)
    }
    guard !mediaBlocks.isEmpty, availableWidth > 0 else {
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        return layoutMediaWithCaptionV2(kind: .collage,
            naturalSize: CGSize(width: boundingWidth, height: 240.0), caption: caption,
            isCover: false, cornerRadius: 8.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)
    }

    var items: [InstantPageV2LaidOutItem] = []
    var maxY: CGFloat = 0.0

    if let mosaic = context.collageMosaic {
        let frames = mosaic(mediaBlocks.map { $0.media }, availableWidth)
        if frames.count == mediaBlocks.count {
            for (i, entry) in mediaBlocks.enumerated() {
                let frame = frames[i].offsetBy(dx: leftX, dy: 0.0)
                if let item = collageMediaItemV2(entry.block, frame: frame, context: &context) {
                    items.append(item)
                }
                maxY = max(maxY, frame.maxY)
            }
        }
    }

    if items.isEmpty {
        let spacing: CGFloat = 2.0
        let perRow = max(1, min(Int((availableWidth / 150.0).rounded()), mediaBlocks.count))
        let itemSize = floor((availableWidth - spacing * CGFloat(perRow - 1)) / CGFloat(perRow))
        var x = leftX
        var y: CGFloat = 0.0
        var col = 0
        for entry in mediaBlocks {
            if col >= perRow {
                col = 0
                x = leftX
                y += itemSize + spacing
            }
            let frame = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            if let item = collageMediaItemV2(entry.block, frame: frame, context: &context) {
                items.append(item)
            }
            maxY = max(maxY, frame.maxY)
            x += itemSize + spacing
            col += 1
        }
    }

    let (captionItems, _) = layoutCaptionAndCreditV2(caption, offset: maxY,
        boundingWidth: boundingWidth, horizontalInset: horizontalInset, context: &context)
    items.append(contentsOf: captionItems)
    return items
}

private func layoutSlideshowV2(
    _ blocks: [InstantPageBlock],
    caption: InstantPageCaption,
    boundingWidth: CGFloat,
    horizontalInset: CGFloat,
    context: inout LayoutContextV2
) -> [InstantPageV2LaidOutItem] {
    let bleed = context.mediaBleed
    let availableWidth = boundingWidth - horizontalInset * 2.0 + bleed * 2.0
    let heightCap = min(1000.0, availableWidth)
    var medias: [InstantPageMedia] = []
    var height: CGFloat = 0.0
    var hasUnrenderableBlock = false
    for block in blocks {
        switch block {
        case let .image(id, caption, url, webpageId, _):
            if let image = context.media[id] as? TelegramMediaImage,
               let dimensions = largestImageRepresentation(image.representations)?.dimensions.size {
                let mediaIndex = context.mediaIndexCounter
                context.mediaIndexCounter += 1
                let mediaUrl: InstantPageUrlItem? = url.flatMap { InstantPageUrlItem(url: $0, webpageId: webpageId) }
                height = max(height, dimensions.fitted(CGSize(width: availableWidth, height: heightCap)).height)
                medias.append(InstantPageMedia(index: mediaIndex, media: image, webpage: context.webpage,
                                               url: mediaUrl, caption: caption.text, credit: caption.credit))
            } else {
                hasUnrenderableBlock = true
            }
        case let .video(id, caption, _, _, _):
            if let file = context.media[id] as? TelegramMediaFile, let dimensions = file.dimensions?.size {
                let mediaIndex = context.mediaIndexCounter
                context.mediaIndexCounter += 1
                height = max(height, dimensions.fitted(CGSize(width: availableWidth, height: heightCap)).height)
                medias.append(InstantPageMedia(index: mediaIndex, media: file, webpage: context.webpage,
                                               url: nil, caption: caption.text, credit: caption.credit))
            } else {
                hasUnrenderableBlock = true
            }
        default:
            hasUnrenderableBlock = true
        }
    }
    if context.unsupportedStyle != nil && (hasUnrenderableBlock || medias.count != blocks.count) {
        return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)
    }
    guard !medias.isEmpty else {
        if context.unsupportedStyle != nil {
            return layoutUnsupportedMediaV2(caption: caption, boundingWidth: boundingWidth,
                horizontalInset: horizontalInset, context: &context)
        }
        return layoutMediaWithCaptionV2(kind: .slideshow,
            naturalSize: CGSize(width: boundingWidth, height: 240.0), caption: caption,
            isCover: false, cornerRadius: 8.0, boundingWidth: boundingWidth,
            horizontalInset: horizontalInset, context: &context)
    }
    if height <= 0.0 { height = 240.0 }
    let frame = CGRect(x: horizontalInset - bleed, y: 0.0, width: availableWidth, height: height)
    let slideshowCorner: CGFloat = bleed > 0 ? 0.0 : 8.0
    var items: [InstantPageV2LaidOutItem] = [.mediaPlaceholder(InstantPageV2MediaPlaceholderItem(
        frame: frame, kind: .slideshow, cornerRadius: slideshowCorner, slideshowMedias: medias, webPage: context.webpage
    ))]
    let (captionItems, _) = layoutCaptionAndCreditV2(caption, offset: height,
        boundingWidth: boundingWidth, horizontalInset: horizontalInset, context: &context)
    items.append(contentsOf: captionItems)
    return items
}


private func setupStyleStackV2(_ stack: InstantPageTextStyleStack, theme: InstantPageTheme, category: InstantPageTextCategoryType, link: Bool) {
    setupStyleStackV2(stack, theme: theme, attributes: theme.textCategories.attributes(type: category, link: link))
}

private func setupStyleStackV2(_ stack: InstantPageTextStyleStack, theme: InstantPageTheme, attributes: InstantPageTextAttributes) {
    stack.push(.textColor(attributes.color))
    stack.push(.markerColor(theme.markerColor))
    stack.push(.linkColor(theme.linkColor))
    stack.push(.linkMarkerColor(theme.linkHighlightColor))
    switch attributes.font.style {
    case .sans:
        stack.push(.fontSerif(false))
    case .serif:
        stack.push(.fontSerif(true))
    }
    switch attributes.font.weight {
    case .regular:
        break
    case .medium:
        stack.push(.medium)
    case .semibold:
        stack.push(.semibold)
    }
    stack.push(.fontSize(attributes.font.size))
    stack.push(.lineSpacingFactor(attributes.font.lineSpacingFactor))
    if attributes.underline {
        stack.push(.underline)
    }
}

private func layoutTextItemWithStringV2(_ string: NSAttributedString, boundingWidth: CGFloat, horizontalInset: CGFloat = 0.0, alignment: NSTextAlignment = .natural, offset: CGPoint, media: [MediaId: Media] = [:], webpage: TelegramMediaWebpage? = nil, minimizeWidth: Bool = false, fitToWidth: Bool = false, maxNumberOfLines: Int = 0, computeRevealCharacterRects: Bool = false, lineMetrics: InstantPageTextLineMetrics? = nil) -> (InstantPageTextItem?, [InstantPageItem], CGSize) {
    return layoutTextItemWithString(string, boundingWidth: boundingWidth, horizontalInset: horizontalInset, alignment: alignment, offset: offset, media: media, webpage: webpage, minimizeWidth: minimizeWidth, fitToWidth: fitToWidth, maxNumberOfLines: maxNumberOfLines, computeRevealCharacterRects: computeRevealCharacterRects, trueLineBox: true, lineMetrics: lineMetrics)
}
