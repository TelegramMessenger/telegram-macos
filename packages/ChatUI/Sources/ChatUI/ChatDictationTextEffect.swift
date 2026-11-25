import Cocoa
import QuartzCore

final class ChatDictationRevealTicker: NSObject {
    private let tick: () -> Void
    private var displayLink: AnyObject?
    private var timer: Timer?

    init(view: NSView, tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(fire))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 120.0, target: self, selector: #selector(fire), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func fire() {
        tick()
    }

    func invalidate() {
        if #available(macOS 14.0, *) {
            (displayLink as? CADisplayLink)?.invalidate()
        }
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }
}

final class ChatDictationTextEffect {
    private struct Reveal {
        var range: NSRange
        var start: CFTimeInterval
        var layer: CALayer?
        var symbol: Int
        var swapAt: CFTimeInterval
        var peak: Float = 1
    }

    private struct GlyphImage {
        let image: CGImage
        let size: NSSize
    }

    static let scrambleDuration: CFTimeInterval = 0.3
    static let resolveDuration: CFTimeInterval = 0.16
    private static let fadeIn: CFTimeInterval = 0.06
    private static let stagger: CFTimeInterval = 0.022
    private static let maxStagger: CFTimeInterval = 0.3
    private static let swapInterval: CFTimeInterval = 0.055
    private static let inPlaceLimit = 4
    private static let maxReveals = 64
    private static let allSymbols: [String] = ["ᔑ", "ʖ", "ᓵ", "↸", "ᒷ", "⎓", "⊣", "⍑", "╎", "⋮", "ꖌ", "ꖎ", "ᒲ", "リ", "ᑑ", "∷", "ᓭ", "ℸ", "⚍", "⍊", "∴", "⨅", "⟟", "⟒", "⏃", "⋏", "⍜", "⌇", "⊑", "⍀", "⟊", "☊"]

    static let symbols: [String] = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize) as CTFont
        let available = allSymbols.filter { symbol in
            let fallback = CTFontCreateForString(font, symbol as CFString, CFRange(location: 0, length: symbol.utf16.count))
            return !(CTFontCopyPostScriptName(fallback) as String).contains("LastResort")
        }
        return available.isEmpty ? ["∴", "⋮", "∷"] : available
    }()

    private struct Shimmer {
        var range: NSRange
        var length: Int
        var start: CFTimeInterval
        var duration: CFTimeInterval
        var loop: ShimmerLoop?
        var expected: String?
    }

    private struct ShimmerLoop {
        var from: Double
        var to: Double
        var start: CFTimeInterval
        var duration: CFTimeInterval

        func envelope(at now: CFTimeInterval) -> Double {
            let t = duration > 0 ? min(1, max(0, (now - start) / duration)) : 1
            return from + (to - from) * t * t * (3 - 2 * t)
        }

        func isOver(at now: CFTimeInterval) -> Bool {
            return to == 0 && now >= start + duration
        }
    }

    private struct WaveGlyph {
        let range: NSRange
        let layer: CALayer
        let tint: CALayer
        let distance: Double
        let position: Int
    }

    private struct Wave {
        var range: NSRange
        var origin: Int
        var start: CFTimeInterval
        var tint: NSColor
        var text: String?
        var glyphs: [WaveGlyph]
        var count: Int
        var speed: Double
        var duration: CFTimeInterval
        var amplitude: CGFloat
        var arrivals: [NSRange]? = nil
        var expected: String? = nil
    }

    private static let waveWidth: Double = 2.6
    static let arrivalDuration: CFTimeInterval = 0.42
    private static let arrivalMaxStagger: CFTimeInterval = 0.3
    private static let maxWaveGlyphs = 160
    private static let shimmerDim: CGFloat = 0.5
    private static let completionDim: CGFloat = 0.35
    private static let shimmerWidth: Double = 5
    static let loopPeriod: CFTimeInterval = 1.1
    static let loopRise: CFTimeInterval = 0.3
    static let settleDuration: CFTimeInterval = 0.5

    private weak var textView: NSTextView?
    private let animationsEnabled: Bool
    private var reveals: [Reveal] = []
    private var shimmer: Shimmer?
    private var wave: Wave?
    private var finishing: ChatDictationTextEffect?
    private var editObserver: NSObjectProtocol?
    private var pending: (text: String, animated: NSRange, kept: Int)?
    private var ticker: ChatDictationRevealTicker?
    private var images: [String: GlyphImage] = [:]

    init(textView: NSTextView, animationsEnabled: Bool) {
        self.textView = textView
        self.animationsEnabled = animationsEnabled
    }

    deinit {
        ticker?.invalidate()
        clearAttributes()
        reveals.forEach { $0.layer?.removeFromSuperlayer() }
        wave?.glyphs.forEach { $0.layer.removeFromSuperlayer() }
        if let editObserver {
            NotificationCenter.default.removeObserver(editObserver)
        }
    }

    var canAnimate: Bool {
        return animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func changedRange(from previous: String, to current: String) -> NSRange {
        let before = Array(previous)
        let after = Array(current)
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - suffix - 1] == after[after.count - suffix - 1] {
            suffix += 1
        }
        let start = current.index(current.startIndex, offsetBy: prefix)
        let end = current.index(current.endIndex, offsetBy: -suffix)
        return NSRange(start ..< end, in: current)
    }

    static func animatedRange(from previous: String, to current: String) -> NSRange {
        let changed = changedRange(from: previous, to: current)
        let suffix = (current as NSString).length - NSMaxRange(changed)
        let replaced = (previous as NSString).length - changed.location - suffix
        guard replaced > inPlaceLimit else {
            return changed
        }
        let skip = min(replaced, changed.length)
        return NSRange(location: changed.location + skip, length: changed.length - skip)
    }

    func cancelReveal() {
        pending = nil
        stopTicking()
        clearAttributes()
        reveals.forEach { $0.layer?.removeFromSuperlayer() }
        reveals.removeAll()
        endWave()
        endShimmer()
        finishing = nil
    }

    private func clearAttributes() {
        guard let textView, let layout = textView.layoutManager, !reveals.isEmpty || shimmer != nil || wave != nil else { return }
        let length = textView.string.utf16.count
        if length > 0 {
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSMakeRange(0, length))
        }
    }

    private func endWave(clearingAll: Bool = false) {
        guard let current = wave else { return }
        wave = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current.glyphs.forEach { $0.layer.removeFromSuperlayer() }
        CATransaction.commit()
        guard let textView, let layout = textView.layoutManager else { return }
        let length = textView.string.utf16.count
        if clearingAll {
            if length > 0 {
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSMakeRange(0, length))
            }
            return
        }
        for glyph in current.glyphs where NSMaxRange(glyph.range) <= length {
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: glyph.range)
        }
    }

    func ripple(range: NSRange, from origin: Int, after delay: CFTimeInterval, tint: NSColor) {
        guard canAnimate, let textView, textView.window != nil else { return }
        let clamped = NSIntersectionRange(range, NSMakeRange(0, textView.string.utf16.count))
        guard clamped.length > 0 else { return }
        endWave()
        wave = Wave(range: clamped, origin: origin, start: CACurrentMediaTime() + delay, tint: tint, text: nil, glyphs: [], count: 0, speed: 0, duration: 0, amplitude: 0)
        finishing = self
        if ticker == nil {
            ticker = ChatDictationRevealTicker(view: textView, tick: { [weak self] in
                self?.step()
            })
        }
        for deadline in [delay, delay + 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
                self?.step()
            }
        }
    }

    func arrive(ranges: [NSRange], within range: NSRange, text: String, tint: NSColor) {
        guard canAnimate, let textView, textView.window != nil, !ranges.isEmpty, range.length > 0 else { return }
        endWave()
        wave = Wave(range: range, origin: ranges[0].location, start: CACurrentMediaTime(), tint: tint, text: nil, glyphs: [], count: 0, speed: 0, duration: 0, amplitude: 0, arrivals: ranges, expected: text)
        finishing = self
        if ticker == nil {
            ticker = ChatDictationRevealTicker(view: textView, tick: { [weak self] in
                self?.step()
            })
        }
        for deadline in [0.1, Self.arrivalMaxStagger + Self.arrivalDuration + 0.1] {
            DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
                self?.step()
            }
        }
    }

    static func arrival(progress: Double) -> (appear: Double, offset: Double, scale: Double, tint: Double) {
        let clamped = min(1, max(0, progress))
        let appear = 1 - pow(1 - clamped, 3)
        return (appear, 1 - appear, 0.82 + 0.18 * appear + 0.07 * sin(clamped * .pi), 1 - smoothstep(0.3, 1, clamped))
    }

    private func endShimmer() {
        shimmer = nil
        if let editObserver {
            NotificationCenter.default.removeObserver(editObserver)
            self.editObserver = nil
        }
    }

    func finish(range: NSRange) {
        guard canAnimate, let textView, textView.window != nil else {
            cancelReveal()
            return
        }
        pending = nil
        let now = CACurrentMediaTime()
        for index in reveals.indices {
            let elapsed = now - reveals[index].start
            if elapsed < Self.scrambleDuration {
                reveals[index].peak = elapsed <= 0 ? 0 : Float(min(1, elapsed / Self.fadeIn))
                reveals[index].start = now - Self.scrambleDuration
            }
        }
        finishing = self
        let length = textView.string.utf16.count
        let clamped = NSIntersectionRange(range, NSMakeRange(0, length))
        guard clamped.length > 0 else {
            step()
            return
        }
        let settle = reveals.map { $0.start + Self.scrambleDuration + Self.resolveDuration - now }.max() ?? 0
        let delay = max(0.08, settle)
        let duration = min(0.7, max(0.45, 0.42 + Double(clamped.length) * 0.004))
        shimmer = Shimmer(range: clamped, length: length, start: now + delay, duration: duration, loop: nil, expected: nil)
        runShimmer(in: textView, until: delay + duration + 0.1)
    }

    func loopShimmer(range: NSRange, after delay: CFTimeInterval = 0) {
        guard canAnimate, let textView, textView.window != nil else { return }
        let length = textView.string.utf16.count
        let clamped = NSIntersectionRange(range, NSMakeRange(0, length))
        guard clamped.length > 0 else { return }
        let now = CACurrentMediaTime()
        if let current = shimmer, current.range != clamped {
            removeShimmerAttributes(current.range)
        }
        let envelope = shimmer.map { shimmerEnvelope($0, at: now) } ?? 0
        let start = shimmer?.start ?? now
        let duration = shimmer?.duration ?? Self.loopPeriod
        shimmer = Shimmer(range: clamped, length: length, start: start, duration: duration, loop: ShimmerLoop(from: envelope, to: 1, start: now + delay, duration: Self.loopRise), expected: nil)
        finishing = self
        runShimmer(in: textView, until: delay + Self.loopRise + 0.1)
    }

    func settleShimmer(range: NSRange, text: String?) {
        guard var current = shimmer, let textView else { return }
        let now = CACurrentMediaTime()
        current.loop = ShimmerLoop(from: shimmerEnvelope(current, at: now), to: 0, start: now, duration: Self.settleDuration)
        if let text {
            current.range = range
            current.length = text.utf16.count
            current.expected = text
        }
        shimmer = current
        runShimmer(in: textView, until: Self.settleDuration + 0.1)
    }

    func redraw() {
        step()
    }

    private func runShimmer(in textView: NSTextView, until deadline: CFTimeInterval) {
        if editObserver == nil {
            editObserver = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in
                guard let self else { return }
                if let expected = self.shimmer?.expected, self.textView?.string == expected {
                    return
                }
                self.cancelReveal()
            }
        }
        if ticker == nil {
            ticker = ChatDictationRevealTicker(view: textView, tick: { [weak self] in
                self?.step()
            })
        }
        step()
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self] in
            self?.step()
        }
    }

    private func shimmerEnvelope(_ shimmer: Shimmer, at now: CFTimeInterval) -> Double {
        if let loop = shimmer.loop {
            return loop.envelope(at: now)
        }
        return Self.completionEnvelope((now - shimmer.start) / shimmer.duration) * Double((1 - Self.completionDim) / (1 - Self.shimmerDim))
    }

    private func removeShimmerAttributes(_ range: NSRange) {
        guard let textView, let layout = textView.layoutManager else { return }
        let clamped = NSIntersectionRange(range, NSMakeRange(0, textView.string.utf16.count))
        if clamped.length > 0 {
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: clamped)
        }
    }

    func revealChange(from previous: String, to current: String) {
        guard canAnimate else {
            cancelReveal()
            return
        }
        guard let textView, textView.window != nil else {
            cancelReveal()
            return
        }
        let changed = Self.changedRange(from: previous, to: current)
        let animated = Self.animatedRange(from: previous, to: current)
        if textView.string == current {
            pending = nil
            apply(animated: animated, keptBefore: changed.location, in: textView)
        } else {
            pending = (current, animated, changed.location)
            DispatchQueue.main.async { [weak self] in
                guard let self, let pending = self.pending, pending.text == current, let textView = self.textView, textView.string == current else { return }
                self.pending = nil
                self.apply(animated: pending.animated, keptBefore: pending.kept, in: textView)
            }
        }
    }

    private func apply(animated: NSRange, keptBefore: Int, in textView: NSTextView) {
        guard let layout = textView.layoutManager else { return }
        let text = textView.string as NSString
        let length = text.length
        var updated: [Reveal] = []
        for reveal in reveals {
            if NSMaxRange(reveal.range) <= keptBefore, NSMaxRange(reveal.range) <= length {
                updated.append(reveal)
            } else {
                reveal.layer?.removeFromSuperlayer()
                if reveal.range.location < length {
                    layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSIntersectionRange(reveal.range, NSMakeRange(0, length)))
                }
            }
        }
        let now = CACurrentMediaTime()
        var index = animated.location
        var count = 0
        while index < NSMaxRange(animated), index < length, updated.count < Self.maxReveals {
            let character = text.rangeOfComposedCharacterSequence(at: index)
            index = NSMaxRange(character)
            if text.substring(with: character).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            let start = now + min(Double(count) * Self.stagger, Self.maxStagger)
            updated.append(Reveal(range: character, start: start, layer: nil, symbol: Int.random(in: 0 ..< Self.symbols.count), swapAt: start))
            count += 1
        }
        reveals = updated
        step()
        if reveals.isEmpty {
            stopTicking()
            return
        }
        if ticker == nil {
            ticker = ChatDictationRevealTicker(view: textView, tick: { [weak self] in
                self?.step()
            })
        }
        let total = Self.maxStagger + Self.scrambleDuration + Self.resolveDuration + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            self?.step()
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func step() {
        guard let textView, let layout = textView.layoutManager, let storage = textView.textStorage, let container = textView.textContainer else {
            stopTicking()
            reveals.forEach { $0.layer?.removeFromSuperlayer() }
            reveals.removeAll()
            wave?.glyphs.forEach { $0.layer.removeFromSuperlayer() }
            wave = nil
            endShimmer()
            finishing = nil
            return
        }
        let now = CACurrentMediaTime()
        let length = storage.length
        let fallback = textView.textColor ?? NSColor.textColor
        let scale = textView.window?.backingScaleFactor ?? 2
        let total = Self.scrambleDuration + Self.resolveDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var running: [Reveal] = []
        for var reveal in reveals {
            guard NSMaxRange(reveal.range) <= length else {
                reveal.layer?.removeFromSuperlayer()
                continue
            }
            let elapsed = now - reveal.start
            if elapsed >= total {
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: reveal.range)
                reveal.layer?.removeFromSuperlayer()
                continue
            }
            let color = (storage.attribute(.foregroundColor, at: reveal.range.location, effectiveRange: nil) as? NSColor) ?? fallback
            if elapsed < 0 {
                layout.addTemporaryAttribute(.foregroundColor, value: color.withAlphaComponent(0), forCharacterRange: reveal.range)
                reveal.layer?.opacity = 0
                running.append(reveal)
                continue
            }
            let glyphs = layout.glyphRange(forCharacterRange: reveal.range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let font = (storage.attribute(.font, at: reveal.range.location, effectiveRange: nil) as? NSFont) ?? textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            if reveal.layer == nil, reveal.peak > 0, let parent = textView.layer {
                let layer = CALayer()
                layer.name = "dictationScramble"
                layer.contentsScale = scale
                layer.contentsGravity = .center
                parent.addSublayer(layer)
                reveal.layer = layer
            }
            if reveal.layer != nil, now >= reveal.swapAt || reveal.layer?.contents == nil {
                var next = Int.random(in: 0 ..< Self.symbols.count)
                if next == reveal.symbol {
                    next = (next + 1) % Self.symbols.count
                }
                reveal.symbol = next
                reveal.swapAt = now + Self.swapInterval * Double.random(in: 0.7 ... 1.3)
                if let glyph = image(Self.symbols[next], font: font, color: color, scale: scale) {
                    reveal.layer?.contents = glyph.image
                    let size = NSSize(width: max(rect.width, glyph.size.width), height: max(rect.height, glyph.size.height))
                    reveal.layer?.frame = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
                }
            } else if let layer = reveal.layer {
                let size = layer.bounds.size
                layer.frame = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
            }
            if elapsed < Self.scrambleDuration {
                layout.addTemporaryAttribute(.foregroundColor, value: color.withAlphaComponent(0), forCharacterRange: reveal.range)
                reveal.layer?.opacity = Float(min(1, elapsed / Self.fadeIn))
            } else {
                let progress = (elapsed - Self.scrambleDuration) / Self.resolveDuration
                let eased = 1 - pow(1 - progress, 3)
                layout.addTemporaryAttribute(.foregroundColor, value: color.withAlphaComponent(color.alphaComponent * CGFloat(eased)), forCharacterRange: reveal.range)
                reveal.layer?.opacity = reveal.peak * Float(1 - eased)
            }
            running.append(reveal)
        }
        CATransaction.commit()
        reveals = running
        stepWave(now: now, textView: textView, layout: layout, storage: storage, container: container)
        stepShimmer(now: now, layout: layout, storage: storage, fallback: fallback)
        if reveals.isEmpty && shimmer == nil && wave == nil {
            stopTicking()
            finishing = nil
        }
    }

    static func shimmerFactor(position: Double, count: Int, progress: Double) -> CGFloat {
        return shimmerFactor(position: position, count: count, travel: shimmerTravel(progress), envelope: completionEnvelope(progress), dim: completionDim)
    }

    static func loopFactor(position: Double, count: Int, elapsed: CFTimeInterval, period: CFTimeInterval, envelope: Double) -> CGFloat {
        let progress = elapsed / period
        return shimmerFactor(position: position, count: count, travel: shimmerTravel(progress < 0 ? 0 : progress - floor(progress)), envelope: envelope, dim: shimmerDim)
    }

    private static func completionEnvelope(_ progress: Double) -> Double {
        return smoothstep(0, 0.2, progress) * (1 - smoothstep(0.8, 1, progress))
    }

    private static func shimmerTravel(_ progress: Double) -> Double {
        return 0.5 - cos(min(1, max(0, progress)) * .pi) / 2
    }

    private static func shimmerFactor(position: Double, count: Int, travel: Double, envelope: Double, dim: CGFloat) -> CGFloat {
        let center = -2 * shimmerWidth + (Double(count) + 4 * shimmerWidth) * travel
        let distance = (position - center) / shimmerWidth
        let band = exp(-distance * distance)
        return 1 - (1 - dim) * CGFloat(envelope * (1 - band))
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func stepShimmer(now: CFTimeInterval, layout: NSLayoutManager, storage: NSTextStorage, fallback: NSColor) {
        guard let current = shimmer else { return }
        let length = storage.length
        let progress = (now - current.start) / current.duration
        let finished = current.loop.map { $0.isOver(at: now) } ?? (progress >= 1)
        if let expected = current.expected, !finished, length != current.length || storage.string != expected {
            return
        }
        let range = NSIntersectionRange(current.range, NSMakeRange(0, length))
        let active = Set(reveals.map { $0.range.location } + (wave?.glyphs.map { $0.range.location } ?? []))
        let text = storage.string as NSString
        if finished || range.length == 0 || length != current.length {
            var index = range.location
            while index < NSMaxRange(range) {
                let character = text.rangeOfComposedCharacterSequence(at: index)
                index = NSMaxRange(character)
                if !active.contains(character.location) {
                    layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: character)
                }
            }
            endShimmer()
            return
        }
        guard current.loop != nil || progress >= 0 else { return }
        var characters: [NSRange] = []
        var index = range.location
        while index < NSMaxRange(range) {
            let character = text.rangeOfComposedCharacterSequence(at: index)
            index = NSMaxRange(character)
            characters.append(character)
        }
        for (position, character) in characters.enumerated() where !active.contains(character.location) {
            let factor = shimmerFactor(current, now: now, position: position, count: characters.count)
            if factor > 0.995 {
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: character)
            } else {
                let color = (storage.attribute(.foregroundColor, at: character.location, effectiveRange: nil) as? NSColor) ?? fallback
                layout.addTemporaryAttribute(.foregroundColor, value: color.withAlphaComponent(color.alphaComponent * factor), forCharacterRange: character)
            }
        }
    }

    private func shimmerFactor(_ current: Shimmer, now: CFTimeInterval, position: Int, count: Int) -> CGFloat {
        if let loop = current.loop {
            return Self.loopFactor(position: Double(position), count: count, elapsed: now - current.start, period: current.duration, envelope: loop.envelope(at: now))
        }
        let progress = (now - current.start) / current.duration
        guard progress >= 0, progress < 1 else { return 1 }
        return Self.shimmerFactor(position: Double(position), count: count, progress: progress)
    }

    static func waveLift(distance: Double, front: Double, fade: Double) -> (lift: Double, crest: Double, soak: Double) {
        let ahead = (distance - front) / waveWidth
        let crest = exp(-ahead * ahead)
        let behind = ahead + 1.7
        let trough = exp(-behind * behind)
        let reach = 1 / (1 + distance * 0.02)
        let soak = 1 - smoothstep(-0.3, 2.2, -ahead)
        return ((crest - 0.4 * trough) * reach * fade, crest * reach * fade, soak)
    }

    private func stepWave(now: CFTimeInterval, textView: NSTextView, layout: NSLayoutManager, storage: NSTextStorage, container: NSTextContainer) {
        guard var current = wave, now >= current.start else { return }
        if current.text == nil {
            if let expected = current.expected, storage.length != expected.utf16.count || storage.string != expected {
                if now - current.start > 0.6 {
                    wave = nil
                }
                return
            }
            guard let started = startWave(current, textView: textView, layout: layout, storage: storage, container: container) else {
                wave = nil
                return
            }
            current = started
            wave = current
        }
        let elapsed = now - current.start
        if storage.length != current.text?.utf16.count || storage.string != current.text {
            endWave(clearingAll: true)
            return
        }
        if elapsed >= current.duration {
            endWave()
            return
        }
        let front = elapsed * current.speed
        let fade = 1 - Self.smoothstep(0.6, 1, elapsed / current.duration)
        let dimming = shimmer.flatMap { $0.range == current.range ? $0 : nil }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if current.arrivals != nil {
            let stagger = min(0.03, Self.arrivalMaxStagger / Double(max(1, current.glyphs.count - 1)))
            for glyph in current.glyphs {
                let motion = Self.arrival(progress: (elapsed - glyph.distance * stagger) / Self.arrivalDuration)
                let scale = CGFloat(motion.scale)
                glyph.layer.transform = CATransform3DScale(CATransform3DMakeTranslation(0, current.amplitude * 0.8 * CGFloat(motion.offset), 0), scale, scale, 1)
                glyph.tint.opacity = Float(0.9 * motion.tint)
                let dim = dimming.map { shimmerFactor($0, now: now, position: glyph.position, count: current.count) } ?? 1
                glyph.layer.opacity = Float(CGFloat(motion.appear) * dim)
            }
            CATransaction.commit()
            return
        }
        for glyph in current.glyphs {
            let motion = Self.waveLift(distance: glyph.distance, front: front, fade: fade)
            let swell = 1 + 0.16 * CGFloat(motion.crest)
            glyph.layer.transform = CATransform3DScale(CATransform3DMakeTranslation(0, -current.amplitude * CGFloat(motion.lift), 0), swell, swell, 1)
            glyph.tint.opacity = Float(0.9 * motion.soak)
            glyph.layer.opacity = Float(dimming.map { shimmerFactor($0, now: now, position: glyph.position, count: current.count) } ?? 1)
        }
        CATransaction.commit()
    }

    private func startWave(_ pending: Wave, textView: NSTextView, layout: NSLayoutManager, storage: NSTextStorage, container: NSTextContainer) -> Wave? {
        guard let parent = textView.layer else { return nil }
        let text = storage.string as NSString
        let range = NSIntersectionRange(pending.range, NSMakeRange(0, text.length))
        guard range.length > 0 else { return nil }
        let scale = textView.window?.backingScaleFactor ?? 2
        let space = textView.window?.colorSpace?.cgColorSpace ?? CGColorSpaceCreateDeviceRGB()
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        var characters: [NSRange] = []
        var index = range.location
        while index < NSMaxRange(range) {
            let character = text.rangeOfComposedCharacterSequence(at: index)
            index = NSMaxRange(character)
            characters.append(character)
        }
        let originPosition = characters.firstIndex(where: { NSLocationInRange(pending.origin, $0) }) ?? 0
        var candidates: [(position: Int, range: NSRange, glyphs: NSRange, rect: NSRect)] = []
        for (position, character) in characters.enumerated() {
            guard !text.substring(with: character).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let arrivals = pending.arrivals, !arrivals.contains(where: { NSIntersectionRange($0, character).length > 0 }) {
                continue
            }
            let glyphs = layout.glyphRange(forCharacterRange: character, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            guard bounds.intersects(visible) else { continue }
            candidates.append((position, character, glyphs, Self.pixelAligned(bounds.insetBy(dx: -3, dy: -2), scale: scale)))
        }
        if pending.arrivals == nil {
            candidates.sort { abs($0.position - originPosition) < abs($1.position - originPosition) }
        }
        candidates = Array(candidates.prefix(Self.maxWaveGlyphs))
        guard !candidates.isEmpty else { return nil }
        for candidate in candidates {
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: candidate.range)
        }
        var glyphs: [WaveGlyph] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for candidate in candidates {
            guard let image = snapshot(glyphs: candidate.glyphs, rect: candidate.rect, in: textView, scale: scale, space: space) else { continue }
            let layer = CALayer()
            layer.name = "dictationWave"
            layer.contentsScale = scale
            layer.contents = image
            layer.frame = candidate.rect
            let mask = CALayer()
            mask.contentsScale = scale
            mask.contents = image
            mask.frame = layer.bounds
            let tint = CALayer()
            tint.frame = layer.bounds
            tint.backgroundColor = pending.tint.cgColor
            tint.mask = mask
            tint.opacity = 0.9
            layer.addSublayer(tint)
            parent.addSublayer(layer)
            let distance = pending.arrivals == nil ? Double(abs(candidate.position - originPosition)) : Double(glyphs.count)
            glyphs.append(WaveGlyph(range: candidate.range, layer: layer, tint: tint, distance: distance, position: candidate.position))
        }
        CATransaction.commit()
        guard !glyphs.isEmpty else { return nil }
        let fallback = textView.textColor ?? NSColor.textColor
        for glyph in glyphs {
            let color = (storage.attribute(.foregroundColor, at: glyph.range.location, effectiveRange: nil) as? NSColor) ?? fallback
            layout.addTemporaryAttribute(.foregroundColor, value: color.withAlphaComponent(0), forCharacterRange: glyph.range)
        }
        let farthest = glyphs.map { $0.distance }.max() ?? 0
        let speed = max(18, farthest / 0.6)
        let font = (storage.attribute(.font, at: glyphs[0].range.location, effectiveRange: nil) as? NSFont) ?? textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        var started = pending
        started.text = storage.string
        started.glyphs = glyphs
        started.count = characters.count
        started.speed = speed
        if pending.arrivals != nil {
            let stagger = min(0.03, Self.arrivalMaxStagger / Double(max(1, glyphs.count - 1)))
            started.duration = Double(max(0, glyphs.count - 1)) * stagger + Self.arrivalDuration + 0.05
        } else {
            started.duration = (farthest + 4 * Self.waveWidth) / speed + 0.15
        }
        started.amplitude = min(7, font.pointSize * 0.45)
        return started
    }

    private static func pixelAligned(_ rect: NSRect, scale: CGFloat) -> NSRect {
        let minX = floor(rect.minX * scale) / scale
        let minY = floor(rect.minY * scale) / scale
        return NSRect(x: minX, y: minY, width: ceil(rect.maxX * scale) / scale - minX, height: ceil(rect.maxY * scale) / scale - minY)
    }

    private func snapshot(glyphs: NSRange, rect: NSRect, in textView: NSTextView, scale: CGFloat, space: CGColorSpace) -> CGImage? {
        guard rect.width > 0, rect.height > 0, let layout = textView.layoutManager else { return nil }
        let deep = textView.window?.canRepresent(.p3) == true
        let bitmapInfo = deep ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: Int(round(rect.width * scale)), height: Int(round(rect.height * scale)), bitsPerComponent: deep ? 16 : 8, bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: textView.textContainerOrigin.x - rect.minX, y: textView.textContainerOrigin.y - rect.minY))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private func image(_ symbol: String, font: NSFont, color: NSColor, scale: CGFloat) -> GlyphImage? {
        let key = "\(symbol)|\(font.fontName)|\(font.pointSize)|\(color.description)|\(scale)"
        if let cached = images[key] {
            return cached
        }
        let string = NSAttributedString(string: symbol, attributes: [.font: font, .foregroundColor: color])
        let bounds = string.size()
        let size = NSSize(width: ceil(bounds.width) + 2, height: ceil(bounds.height) + 2)
        guard size.width > 0, size.height > 0, let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: NSPoint(x: 1, y: 1))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else {
            return nil
        }
        if images.count > 256 {
            images.removeAll()
        }
        let glyph = GlyphImage(image: image, size: size)
        images[key] = glyph
        return glyph
    }

}
