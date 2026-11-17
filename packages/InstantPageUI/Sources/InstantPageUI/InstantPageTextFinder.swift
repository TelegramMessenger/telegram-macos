import Cocoa

struct InstantPageFindLine {
    let line: CTLine
    let range: NSRange
    let frame: CGRect
}

final class InstantPageFindText {
    let attributedString: NSAttributedString
    let lines: [InstantPageFindLine]
    let ranges: [NSRange]
    let location: () -> (view: NSView, origin: CGPoint)?
    let scrollToVisible: (CGRect) -> Void

    init(attributedString: NSAttributedString, lines: [InstantPageFindLine], excludedRanges: [NSRange], location: @escaping () -> (view: NSView, origin: CGPoint)?, scrollToVisible: @escaping (CGRect) -> Void) {
        self.attributedString = attributedString
        self.lines = lines
        self.location = location
        self.scrollToVisible = scrollToVisible
        var indices = IndexSet()
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        for line in lines {
            let sourceLine = CTTypesetterCreateLine(typesetter, CFRange(location: line.range.location, length: line.range.length))
            var sourceIndices: [Int] = [NSMaxRange(line.range)]
            for run in CTLineGetGlyphRuns(sourceLine) as! [CTRun] {
                var values = [CFIndex](repeating: 0, count: CTRunGetGlyphCount(run))
                CTRunGetStringIndices(run, CFRange(location: 0, length: values.count), &values)
                sourceIndices.append(contentsOf: values)
            }
            let boundaries = Array(Set(sourceIndices)).sorted()
            let glyphRanges = Dictionary(uniqueKeysWithValues: zip(boundaries, boundaries.dropFirst()).map { ($0, $0 ..< $1) })
            for run in CTLineGetGlyphRuns(line.line) as! [CTRun] {
                var values = [CFIndex](repeating: 0, count: CTRunGetGlyphCount(run))
                CTRunGetStringIndices(run, CFRange(location: 0, length: values.count), &values)
                for index in values {
                    if let range = glyphRanges[index] {
                        indices.insert(integersIn: range)
                    }
                }
            }
        }
        for range in excludedRanges {
            let range = NSIntersectionRange(range, NSRange(location: 0, length: attributedString.length))
            indices.remove(integersIn: range.location ..< NSMaxRange(range))
        }
        self.ranges = indices.rangeView.map { NSRange(location: $0.lowerBound, length: $0.count) }
    }

    func rects(for range: NSRange) -> [CGRect] {
        var result: [CGRect] = []
        for line in lines where NSIntersectionRange(line.range, range).length > 0 {
            var rects: [CGRect] = []
            for run in CTLineGetGlyphRuns(line.line) as! [CTRun] {
                let runRange = CTRunGetStringRange(run)
                guard NSIntersectionRange(NSRange(location: runRange.location, length: runRange.length), range).length > 0 else {
                    continue
                }
                let count = CTRunGetGlyphCount(run)
                var indices = [CFIndex](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)
                let boundaries = Array(Set(indices + [runRange.location + runRange.length])).sorted()
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                _ = CTRunGetTypographicBounds(run, CFRange(location: 0, length: count), &ascent, &descent, nil)
                for index in 0 ..< count {
                    let start = indices[index]
                    let end = boundaries.first(where: { $0 > start }) ?? start
                    guard NSIntersectionRange(NSRange(location: start, length: end - start), range).length > 0 else {
                        continue
                    }
                    let position = positions[index]
                    let width = abs(advances[index].width)
                    if width > 0 {
                        rects.append(CGRect(x: line.frame.minX + min(position.x, position.x + advances[index].width), y: line.frame.maxY - ascent - position.y, width: width, height: ascent + descent))
                    }
                }
            }
            var merged: CGRect?
            for rect in rects.sorted(by: { $0.minX < $1.minX }) {
                if let previous = merged, rect.minX <= previous.maxX + 0.5 {
                    merged = previous.union(rect)
                } else {
                    if let merged = merged {
                        result.append(merged)
                    }
                    merged = rect
                }
            }
            if let merged = merged {
                result.append(merged)
            }
        }
        return result
    }
}

final class InstantPageTextFinder: NSObject, NSTextFinderClient {
    private struct Segment {
        let text: InstantPageFindText
        let sourceRange: NSRange
        let range: NSRange
        let string: String

        func sourceRange(for range: NSRange) -> NSRange {
            let intersection = NSIntersectionRange(self.range, range)
            return NSRange(location: sourceRange.location + intersection.location - self.range.location, length: intersection.length)
        }
    }

    let finder = NSTextFinder()
    private weak var scrollView: NSScrollView?
    private let indicatorColor: () -> NSColor
    private var segments: [Segment] = []
    private var selection = NSRange(location: 0, length: 0)
    private var length: Int = 0
    private(set) var query = ""
    private(set) var matches: [NSRange] = []
    private(set) var matchIndex: Int?
    var resultsUpdated: (() -> Void)?

    init(scrollView: NSScrollView, indicatorColor: @escaping () -> NSColor) {
        self.scrollView = scrollView
        self.indicatorColor = indicatorColor
        super.init()
        finder.client = self
        finder.findBarContainer = scrollView
        finder.isIncrementalSearchingEnabled = true
    }

    func invalidate() {
        finder.noteClientStringWillChange()
        finder.cancelFindIndicator()
        segments.removeAll()
        length = 0
        selection = NSRange(location: 0, length: 0)
        matches.removeAll()
        matchIndex = nil
        resultsUpdated?()
    }

    func update(_ texts: [InstantPageFindText]) {
        let previousSelection = selection
        invalidate()
        for text in texts {
            for range in text.ranges {
                segments.append(Segment(text: text, sourceRange: range, range: NSRange(location: length, length: range.length), string: (text.attributedString.string as NSString).substring(with: range)))
                length += range.length
            }
        }
        rebuildMatches()
        if let index = matches.firstIndex(of: previousSelection) {
            matchIndex = index
            selection = matches[index]
        }
        resultsUpdated?()
    }

    func search(_ query: String) {
        self.query = query
        finder.cancelFindIndicator()
        rebuildMatches()
        selectMatch()
    }

    func navigate(backwards: Bool) {
        guard !matches.isEmpty else { return }
        matchIndex = ((matchIndex ?? (backwards ? 0 : -1)) + (backwards ? -1 : 1) + matches.count) % matches.count
        selectMatch()
    }

    private func rebuildMatches() {
        matches.removeAll()
        matchIndex = nil
        selection = NSRange(location: 0, length: 0)
        guard !query.isEmpty else { return }
        for segment in segments {
            let string = segment.string as NSString
            var remaining = NSRange(location: 0, length: string.length)
            while remaining.length > 0 {
                let range = string.range(of: query, options: [.caseInsensitive], range: remaining)
                guard range.location != NSNotFound, range.length > 0 else { break }
                matches.append(NSRange(location: segment.range.location + range.location, length: range.length))
                remaining = NSRange(location: NSMaxRange(range), length: string.length - NSMaxRange(range))
            }
        }
        if let first = matches.first {
            matchIndex = 0
            selection = first
        }
    }

    private func selectMatch() {
        if let index = matchIndex, matches.indices.contains(index) {
            selection = matches[index]
            scrollRangeToVisible(selection)
        }
        resultsUpdated?()
    }

    func highlights() -> [(view: NSView, rects: [CGRect], selected: [CGRect])] {
        var result: [(view: NSView, rects: [CGRect], selected: [CGRect])] = []
        for segment in segments {
            guard let location = segment.text.location(), segment.text.lines.contains(where: {
                NSIntersectionRange($0.range, segment.sourceRange).length > 0 && $0.frame.offsetBy(dx: location.origin.x, dy: location.origin.y).intersects(location.view.visibleRect)
            }) else { continue }
            var lower = 0
            var upper = matches.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if NSMaxRange(matches[middle]) <= segment.range.location {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            var rects: [CGRect] = []
            var selected: [CGRect] = []
            var index = lower
            while index < matches.count, matches[index].location < NSMaxRange(segment.range) {
                let range = matches[index]
                let frames = segment.text.rects(for: segment.sourceRange(for: range)).map {
                    $0.offsetBy(dx: location.origin.x, dy: location.origin.y)
                }.filter { $0.intersects(location.view.visibleRect) }
                if index == matchIndex {
                    selected.append(contentsOf: frames)
                } else {
                    rects.append(contentsOf: frames)
                }
                index += 1
            }
            guard !rects.isEmpty || !selected.isEmpty else { continue }
            if let index = result.firstIndex(where: { $0.view === location.view }) {
                result[index].rects.append(contentsOf: rects)
                result[index].selected.append(contentsOf: selected)
            } else {
                result.append((location.view, rects, selected))
            }
        }
        return result
    }

    func stringLength() -> Int {
        return length
    }

    var isEditable: Bool {
        return false
    }

    var allowsMultipleSelection: Bool {
        return false
    }

    func string(at characterIndex: Int, effectiveRange outRange: NSRangePointer, endsWithSearchBoundary outFlag: UnsafeMutablePointer<ObjCBool>) -> String {
        outFlag.pointee = true
        guard let segment = segments.first(where: { NSLocationInRange(characterIndex, $0.range) }) else {
            outRange.pointee = NSRange(location: length, length: 0)
            return ""
        }
        outRange.pointee = segment.range
        return segment.string
    }

    var firstSelectedRange: NSRange {
        return selection
    }

    var selectedRanges: [NSValue] {
        get {
            return [NSValue(range: selection)]
        }
        set {
            if let range = newValue.first?.rangeValue, range.location != NSNotFound, range.location <= length, range.length <= length - range.location {
                selection = range
            }
        }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        guard let segment = segments.first(where: { NSIntersectionRange($0.range, range).length > 0 }) else {
            return
        }
        let rects = segment.text.rects(for: segment.sourceRange(for: range))
        if let rect = rects.first {
            segment.text.scrollToVisible(rect)
        }
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        if let segment = segments.first(where: { NSLocationInRange(index, $0.range) }), let location = segment.text.location() {
            outRange.pointee = segment.range
            return location.view
        }
        outRange.pointee = NSRange(location: index, length: 0)
        return scrollView?.documentView ?? NSView()
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        return segments.filter { NSIntersectionRange($0.range, range).length > 0 }.flatMap { segment -> [NSValue] in
            guard let location = segment.text.location() else {
                return []
            }
            return segment.text.rects(for: segment.sourceRange(for: range)).map { NSValue(rect: $0.offsetBy(dx: location.origin.x, dy: location.origin.y)) }
        }
    }

    var visibleCharacterRanges: [NSValue] {
        return segments.compactMap { segment in
            guard let location = segment.text.location(), segment.text.lines.contains(where: { NSIntersectionRange($0.range, segment.sourceRange).length > 0 && $0.frame.offsetBy(dx: location.origin.x, dy: location.origin.y).intersects(location.view.visibleRect) }) else {
                return nil
            }
            return NSValue(range: segment.range)
        }
    }

    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        for segment in segments where NSIntersectionRange(segment.range, range).length > 0 {
            guard let location = segment.text.location(), location.view === view else {
                continue
            }
            let sourceRange = segment.sourceRange(for: range)
            context.saveGState()
            context.translateBy(x: location.origin.x, y: location.origin.y)
            context.clip(to: segment.text.rects(for: sourceRange))
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            for line in segment.text.lines where NSIntersectionRange(line.range, sourceRange).length > 0 {
                if view.isDrawingFindIndicator {
                    context.saveGState()
                    context.translateBy(x: line.frame.minX, y: line.frame.maxY)
                    context.scaleBy(x: 1, y: -1)
                    context.textMatrix = .identity
                    context.setFillColor(indicatorColor().cgColor)
                    for run in CTLineGetGlyphRuns(line.line) as! [CTRun] {
                        let attributes = CTRunGetAttributes(run) as NSDictionary
                        guard let font = attributes[kCTFontAttributeName as String] else { continue }
                        let count = CTRunGetGlyphCount(run)
                        var glyphs = [CGGlyph](repeating: 0, count: count)
                        var positions = [CGPoint](repeating: .zero, count: count)
                        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                        CTFontDrawGlyphs(font as! CTFont, glyphs, positions, count, context)
                    }
                    context.restoreGState()
                } else {
                    context.textPosition = CGPoint(x: line.frame.minX, y: line.frame.maxY)
                    CTLineDraw(line.line, context)
                }
            }
            context.restoreGState()
        }
    }

    deinit {
        finder.cancelFindIndicator()
        finder.client = nil
        finder.findBarContainer = nil
    }
}
