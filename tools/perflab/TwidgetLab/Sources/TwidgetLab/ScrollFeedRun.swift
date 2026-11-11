import Cocoa
import WidgetSandbox
import TwidgetRenderer

protocol FeedAdapter: AnyObject {
    var count: Int { get }
    var onResize: ((Int) -> Void)? { get set }
    func bubbleHeight(_ index: Int) -> CGFloat
    func makeBubble() -> NSView
    func configure(_ bubble: NSView, index: Int, width: CGFloat)
    func didLayout(list: FeedList)
    var liveCount: Int { get }
    var tileBytes: Int { get }
    func blankReason(_ index: Int, visible: CGRect) -> String?
    var summary: String { get }
}

final class FeedRowView: FeedFlippedView {
    let label = NSTextField(labelWithString: "")
    var bubble: NSView
    var index = -1

    init(bubble: NSView) {
        self.bubble = bubble
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        addSubview(label)
        addSubview(bubble)
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class FeedList {
    static let labelHeight: CGFloat = 22
    static let gap: CGFloat = 10
    let scrollView: NSScrollView
    let document = FeedFlippedView(frame: .zero)
    let adapter: FeedAdapter
    let names: [String]
    var width: CGFloat
    private(set) var tops: [CGFloat] = []
    private var heights: [CGFloat] = []
    private var rows: [Int: FeedRowView] = [:]
    private var pool: [FeedRowView] = []
    static var anchorCenter = true
    var visibleJumps = 0
    var anchorJumps = 0
    var visibleAnchored = 0
    var generationTag: (Int) -> String = { _ in "" }
    var anchoredResizes = 0
    var resizes = 0
    var trackJumps = false
    var jumpLog: [String] = []

    init(frame: CGRect, adapter: FeedAdapter, names: [String], width: CGFloat) {
        self.adapter = adapter
        self.names = names
        self.width = width
        scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = document
        document.postsFrameChangedNotifications = true
        heights = (0..<adapter.count).map { adapter.bubbleHeight($0) }
        recomputeTops(from: 0)
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: nil) { [weak self] _ in
            self?.tile()
        }
        adapter.onResize = { [weak self] index in self?.resized(index) }
    }

    var viewport: CGRect { scrollView.contentView.bounds }
    var count: Int { heights.count }
    var maxOffset: CGFloat { max(0, document.frame.height - viewport.height) }

    private func rowHeight(_ i: Int) -> CGFloat { FeedList.labelHeight + heights[i] + FeedList.gap }

    private func recomputeTops(from start: Int) {
        if tops.count != heights.count { tops = [CGFloat](repeating: 0, count: heights.count) }
        var y: CGFloat = start == 0 ? 0 : tops[start - 1] + rowHeight(start - 1)
        for i in start..<heights.count {
            tops[i] = y
            y += rowHeight(i)
        }
        let size = NSSize(width: width, height: y)
        if document.frame.size != size { document.setFrameSize(size) }
    }

    func bubbleRect(_ i: Int) -> CGRect {
        return CGRect(x: 0, y: tops[i] + FeedList.labelHeight, width: width, height: heights[i])
    }

    func index(at y: CGFloat) -> Int {
        var lo = 0, hi = tops.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if tops[mid] <= y { lo = mid } else { hi = mid - 1 }
        }
        return max(0, lo)
    }

    var visibleRange: ClosedRange<Int> {
        let v = viewport
        return index(at: v.minY)...index(at: max(v.minY, v.maxY - 1))
    }

    func setWidth(_ width: CGFloat) {
        self.width = width
        for (_, row) in rows {
            row.removeFromSuperview()
            pool.append(row)
        }
        rows.removeAll()
        recomputeTops(from: 0)
        tile()
    }

    func tile() {
        guard !tops.isEmpty else { return }
        let range = visibleRange
        for (i, row) in rows where !range.contains(i) {
            row.removeFromSuperview()
            rows.removeValue(forKey: i)
            pool.append(row)
        }
        for i in range {
            let row: FeedRowView
            if let existing = rows[i] {
                row = existing
            } else {
                row = pool.popLast() ?? FeedRowView(bubble: adapter.makeBubble())
                rows[i] = row
                row.index = i
                row.label.stringValue = names[i]
                row.frame = CGRect(x: 0, y: tops[i], width: width, height: rowHeight(i))
                row.label.frame = CGRect(x: 8, y: 3, width: width - 16, height: 16)
                row.bubble.frame = CGRect(x: 0, y: FeedList.labelHeight, width: width, height: heights[i])
                document.addSubview(row)
                if trackJumps { (adapter as? ManagedAdapter)?.rowAppeared(i) }
                adapter.configure(row.bubble, index: i, width: width)
                continue
            }
            row.frame = CGRect(x: 0, y: tops[i], width: width, height: rowHeight(i))
        }
        adapter.didLayout(list: self)
    }

    private func resized(_ i: Int) {
        let height = adapter.bubbleHeight(i)
        guard abs(height - heights[i]) > 0.5 else { return }
        let delta = height - heights[i]
        let v = viewport
        let rect = bubbleRect(i)
        resizes += 1
        heights[i] = height
        recomputeTops(from: i)
        var origin = v.origin
        let anchor = FeedList.anchorCenter ? v.midY : v.minY
        if rect.maxY <= anchor + 0.5 {
            anchoredResizes += 1
            origin.y += delta
            if rect.maxY > v.minY + 0.5, trackJumps {
                visibleAnchored += 1
            }
        } else if rect.minY < v.maxY {
            if trackJumps {
                visibleJumps += 1
                if rect.minY < anchor {
                    anchorJumps += 1
                }
                if jumpLog.count < 400 { jumpLog.append("\(names[i])\(generationTag(i)) \(Int(height - delta))->\(Int(height))") }
            }
        }
        for (j, row) in rows where j >= i {
            row.frame = CGRect(x: 0, y: tops[j], width: width, height: rowHeight(j))
            if j == i { row.bubble.frame = CGRect(x: 0, y: FeedList.labelHeight, width: width, height: heights[i]) }
        }
        if origin != v.origin {
            scrollView.contentView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            tile()
        }
    }

    func scroll(to y: CGFloat) {
        let target = min(max(0, y), maxOffset)
        if abs(target - viewport.minY) < 0.01 { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    var visibleRows: [(Int, FeedRowView)] { rows.sorted { $0.key < $1.key } }
}

final class FeedDriver: NSObject {
    let list: FeedList
    let window: NSWindow
    let meter = MainBusyMeter()
    var phases: [FramePhase] = []
    private var current: FramePhase?
    private var lastTimestamp: CFTimeInterval = 0
    private var lastBusy: CFTimeInterval = 0
    private var lastCommit: CFTimeInterval = 0
    private var interval: CFTimeInterval = 1.0 / 120
    private var step: ((CFTimeInterval) -> Bool)?
    private var phaseStart: CFTimeInterval = 0
    private var link: AnyObject?
    private var lastSample: CFTimeInterval = 0
    var checking = true
    var blankWidgetFrames = 0
    private var frameIndex = 0
    var blankFrames = 0
    var blankWidgets = Set<String>()
    var settledStreak: [String: Int] = [:]
    var worstSettled: [String: (frames: Int, reason: String)] = [:]
    static let settledBlankReasons: Set<String> = ["undrawn", "uncovered", "no-tiles", "detached"]
    var shotLog: [String] = []

    init(list: FeedList, window: NSWindow) {
        self.list = list
        self.window = window
    }

    private var cvLink: CVDisplayLink?
    private let lock = NSLock()
    private var pending = false
    private var missed = 0
    private var vsyncs = 0

    func start() {
        CVDisplayLinkCreateWithActiveCGDisplays(&cvLink)
        guard let cvLink else { fatalError("no display link") }
        CVDisplayLinkSetOutputHandler(cvLink) { [weak self] _, now, _, _, _ in
            guard let self else { return kCVReturnSuccess }
            let ts = Double(now.pointee.hostTime) * FeedDriver.ticksToSeconds
            let period = now.pointee.videoRefreshPeriod > 0 ? Double(now.pointee.videoRefreshPeriod) / Double(now.pointee.videoTimeScale) : 1.0 / 120
            self.lock.lock()
            self.vsyncs += 1
            if self.pending {
                self.missed += 1
                self.lock.unlock()
                return kCVReturnSuccess
            }
            self.pending = true
            self.lock.unlock()
            DispatchQueue.main.async {
                self.lock.lock()
                self.pending = false
                let missed = self.missed
                self.missed = 0
                self.lock.unlock()
                self.tick(ts: ts, period: period, missed: missed)
            }
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(cvLink)
    }

    static let ticksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1e9
    }()

    func run(_ name: String, _ step: @escaping (CFTimeInterval) -> Bool) {
        current = FramePhase(name: name)
        current!.cpuStart = feedCPUSeconds()
        current!.start = CACurrentMediaTime()
        phaseStart = 0
        lastTimestamp = 0
        self.step = step
        frameIndex = 0
        while self.step != nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))
        }
    }

    private func tick(ts: CFTimeInterval, period: CFTimeInterval, missed: Int) {
        guard var phase = current, let step else { return }
        let busy = meter.busyNow
        if lastTimestamp > 0 {
            let expected = period
            interval = expected
            let gap = ts - lastTimestamp
            phase.dropped += missed
            phase.frames += 1
            phase.worstGapMs = max(phase.worstGapMs, gap * 1000)
            phase.hitchMs += Double(missed) * expected * 1000
            phase.busyMs.append((busy - lastBusy) * 1000)
            FeedSpikes.commitMs = (meter.commitTotal - lastCommit) * 1000
            FeedSpikes.frame(busyMs: (busy - lastBusy) * 1000, phase: phase.name)
        } else {
            phaseStart = ts
        }
        lastTimestamp = ts
        lastBusy = busy
        lastCommit = meter.commitTotal
        let now = CACurrentMediaTime()
        if now - lastSample > 0.25 || phase.peakFootprint == 0 {
            lastSample = now
            let s = ProcessSample.now()
            phase.peakFootprint = max(phase.peakFootprint, s.footprint)
            phase.peakResident = max(phase.peakResident, s.resident)
            phase.peakThreads = max(phase.peakThreads, s.threads)
            phase.peakTileBytes = max(phase.peakTileBytes, list.adapter.tileBytes)
        }
        phase.peakLive = max(phase.peakLive, list.adapter.liveCount)
        current = phase
        if checking { check() }
        let done = step(ts - phaseStart)
        frameIndex += 1
        if done {
            phase = current!
            phase.end = CACurrentMediaTime()
            phase.cpuEnd = feedCPUSeconds()
            let s = ProcessSample.now()
            phase.peakFootprint = max(phase.peakFootprint, s.footprint)
            phase.peakResident = max(phase.peakResident, s.resident)
            phases.append(phase)
            print(phase.line())
            fflush(stdout)
            current = nil
            self.step = nil
        }
    }

    func check() {
        let viewport = list.viewport
        var blankHere: [String] = []
        var settledNow = Set<String>()
        defer {
            for name in settledStreak.keys where !settledNow.contains(name) { settledStreak[name] = nil }
        }
        for (i, _) in list.visibleRows {
            let rect = list.bubbleRect(i)
            let inView = rect.intersection(viewport)
            guard inView.height > 8 else { continue }
            if let reason = list.adapter.blankReason(i, visible: inView.offsetBy(dx: -rect.minX, dy: -rect.minY)) {
                blankHere.append(list.names[i] + " " + reason)
                if FeedDriver.settledBlankReasons.contains(reason) {
                    let name = list.names[i]
                    settledNow.insert(name)
                    let streak = (settledStreak[name] ?? 0) + 1
                    settledStreak[name] = streak
                    if streak > (worstSettled[name]?.frames ?? 0) { worstSettled[name] = (streak, reason) }
                }
                blankWidgetFrames += 1
                blankWidgets.insert(list.names[i])
            }
        }
        if !blankHere.isEmpty {
            blankFrames += 1
            if shotLog.count < 25 { shotLog.append("\(current?.name ?? "") y=\(Int(viewport.minY)): " + blankHere.joined(separator: ", ")) }
        }
    }
}

func feedBlankReason(view: NSView, visible: CGRect) -> String? {
    guard view.window != nil, let layer = view.layer else { return "detached" }
    let tiles = feedTileLayers(layer).filter { $0.delegate != nil && !($0.delegate is NSView) }
    if tiles.isEmpty { return "no-tiles" }
    for tile in tiles where tile.frame.intersects(visible) && tile.contents == nil {
        return "undrawn"
    }
    if !tiles.contains(where: { $0.frame.intersects(visible) }) && visible.height > 30 { return "uncovered" }
    return nil
}

func loadFeedCorpus(limit: Int) -> [(String, String)] {
    let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("../../../../../packages/HTMLBubbles/Tests/HTMLBubblesTests/Fixtures").standardized
    func files(_ dir: URL, _ prefix: String) -> [(String, String)] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, URL)] = []
        for case let url as URL in e where url.pathExtension == "html" {
            out.append((prefix + String(url.path.dropFirst(dir.path.count + 1)), url))
        }
        return out.sorted { $0.0 < $1.0 }.compactMap { name, url in (try? String(contentsOf: url, encoding: .utf8)).map { (name, $0) } }
    }
    var all = files(root.appendingPathComponent("ported"), "ported/")
    for group in ["showcase", "generated", "common", "compat"] {
        all += files(root.appendingPathComponent("widget-sandbox/\(group)"), group + "/")
    }
    if limit < all.count {
        let stride = Double(all.count) / Double(limit)
        return (0..<limit).map { all[Int(Double($0) * stride)] }
    }
    return all
}

final class BaselineAdapter: FeedAdapter {
    let items: [BaselineItem]
    var onResize: ((Int) -> Void)?
    private var bubbleIndex: [ObjectIdentifier: Int] = [:]

    init(corpus: [(String, String)]) {
        items = corpus.map { BaselineItem(name: $0.0, html: $0.1) }
    }

    var count: Int { items.count }
    func bubbleHeight(_ index: Int) -> CGFloat { items[index].size(width: 0).height }
    func makeBubble() -> NSView { BaselineBubbleView(frame: .zero) }
    func configure(_ bubble: NSView, index: Int, width: CGFloat) {
        let view = bubble as! BaselineBubbleView
        view.onContentChanged = { [weak self] _ in self?.onResize?(index) }
        view.update(item: items[index], width: width)
    }
    func didLayout(list: FeedList) {}
    var liveCount: Int { BaselineItem.live }
    var tileBytes: Int { items.reduce(0) { $0 + ($1.renderer.map { feedTileBytes($0.view) } ?? 0) } }
    func blankReason(_ index: Int, visible: CGRect) -> String? {
        let item = items[index]
        guard let renderer = item.renderer else { return "no-host" }
        if !item.hasContent { return "loading" }
        return feedBlankReason(view: renderer.view, visible: visible)
    }
    var summary: String {
        let ms = BaselineItem.createMs.sorted()
        return String(format: "hosts created=%d create main ms avg=%.2f max=%.2f\n", ms.count, ms.reduce(0, +) / Double(max(1, ms.count)), ms.last ?? 0) + feedTopRenderers(items.compactMap { item in item.renderer.map { (item.name, $0) } })
    }
}

func runFeed(_ args: [String], option: (String) -> String?) {
    if ProcessInfo.processInfo.environment["LAB_CONTENTS_TRACE"] != nil { ContentsTrace.install() }
    let count = Int(option("--count") ?? "230") ?? 230
    let width = CGFloat(Double(option("--width") ?? "440") ?? 440)
    let height = CGFloat(Double(option("--height") ?? "900") ?? 900)
    let speed = CGFloat(Double(option("--speed") ?? "2000") ?? 2000)
    let mode = option("--mode") ?? "baseline"
    let pattern = option("--pattern") ?? "both"
    feedTrustOcclusion = args.contains("--trust-occlusion")
    TimedRenderer.typed = !args.contains("--json-ops")
    var slowApplies: [String] = []
    let slowLock = NSLock()
    LiteHTMLWidgetRenderer.slowApply = { ops, ms, held, stages in
        slowLock.lock()
        defer { slowLock.unlock() }
        if slowApplies.count < 30 {
            slowApplies.append(String(format: "%.1fms ops=%d held=%@ ", ms, ops, held ? "y" : "n") + stages.sorted { $0.value > $1.value }.prefix(5).map { String(format: "%@ %.1f", $0.key, $0.value) }.joined(separator: ", "))
        }
    }
    if ProcessInfo.processInfo.environment["LAB_MTC_PROBE"] != nil {
        DispatchQueue.global().async { _ = NSView(frame: .zero) }
    }
    if let delay = option("--trim-delay").flatMap(Double.init) { LiteHTMLWidgetRenderer.hiddenTrimDelay = delay }
    var corpus = option("--dir").map { dir in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".html") }.sorted().compactMap { name in (try? String(contentsOfFile: dir + "/" + name, encoding: .utf8)).map { (name, $0) } } } ?? loadFeedCorpus(limit: option("--only") == nil ? count : Int.max)
    if let times = option("--repeat").flatMap(Int.init), times > 1 {
        corpus = (0..<times).flatMap { round in corpus.map { ("\($0.0)#\(round)", $0.1) } }
    }
    if let only = option("--only") {
        let picked = corpus.filter { $0.0.contains(only) }
        corpus = (0..<max(1, count)).map { picked[$0 % picked.count] }
    }
    let adapter: FeedAdapter = mode == "baseline" ? BaselineAdapter(corpus: corpus) : makeManagedAdapter(corpus: corpus, args: args, option: option)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width + 16, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .white
    if let at = option("--at") {
        let xy = at.split(separator: ",").compactMap { Double($0) }
        if xy.count == 2 { window.setFrameOrigin(NSPoint(x: xy[0], y: xy[1])) }
    } else if let screen = NSScreen.main {
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - window.frame.width - 20, y: screen.visibleFrame.minY + 20))
    }
    window.ignoresMouseEvents = true
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    FeedList.anchorCenter = option("--anchor") != "top"
    let list = FeedList(frame: CGRect(x: 0, y: 0, width: width + 16, height: height), adapter: adapter, names: corpus.map { $0.0 }, width: width)
    if let managed = adapter as? ManagedAdapter {
        list.generationTag = { index in managed.items[index].map { $0.bubble.generation > 1 ? "@re\($0.bubble.generation)" : "" } ?? "" }
    }
    window.contentView = list.scrollView
    list.tile()
    let driver = FeedDriver(list: list, window: window)
    driver.checking = !args.contains("--no-check")
    FeedSpikes.threshold = Double(option("--spike") ?? "25") ?? 25
    driver.start()
    let settle = Double(option("--settle") ?? "3") ?? 3
    let chat = pattern == "chat"
    if chat { list.scroll(to: list.maxOffset) }
    driver.run("open") { t in
        if chat { list.scroll(to: list.maxOffset) }
        return t >= settle
    }
    print("window occlusion visible=\(window.occlusionState.contains(.visible)) isVisible=\(window.isVisible) screen=\(window.screen != nil) frame=\(window.frame)")
    list.trackJumps = true
    driver.blankFrames = 0
    driver.blankWidgetFrames = 0
    driver.blankWidgets.removeAll()
    driver.shotLog.removeAll()

    let phaseCap = Double(option("--phase-seconds") ?? "1e9") ?? 1e9
    var pressureTimer: Timer?
    if let every = option("--pressure-every").flatMap(Double.init), let managed = adapter as? ManagedAdapter {
        pressureTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
            managed.feed.memoryPressure(critical: true)
            WidgetSurfacePool.shared.purge()
            WidgetShellPool.shared.drain()
            WidgetShellPool.shared.prewarm(width: width)
        }
        RunLoop.main.add(pressureTimer!, forMode: .common)
    }
    defer { pressureTimer?.invalidate() }
    var colorTimer: Timer?
    if let every = option("--colorspace-every").flatMap(Double.init) {
        var flip = 0
        colorTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
            flip += 1
            window.colorSpace = [NSColorSpace.displayP3, .sRGB, .genericRGB, .extendedSRGB][flip % 4]
            NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
            NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        }
        RunLoop.main.add(colorTimer!, forMode: .common)
    }
    defer { colorTimer?.invalidate() }
    var themeTimer: Timer?
    if let every = option("--theme-every").flatMap(Double.init), let managed = adapter as? ManagedAdapter {
        var dark = false
        themeTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
            dark.toggle()
            managed.setTheme(dark ? "dark" : "light")
        }
        RunLoop.main.add(themeTimer!, forMode: .common)
    }
    defer { themeTimer?.invalidate() }
    var widthTimer: Timer?
    if let every = option("--width-every").flatMap(Double.init), let managed = adapter as? ManagedAdapter {
        let widths: [CGFloat] = [width, width - 90, width + 70, width - 30]
        var step = 0
        widthTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
            step += 1
            let w = widths[step % widths.count]
            managed.setWidth(w)
            window.setContentSize(NSSize(width: w + 16, height: height))
            list.scrollView.frame = CGRect(x: 0, y: 0, width: w + 16, height: height)
            list.setWidth(w)
        }
        RunLoop.main.add(widthTimer!, forMode: .common)
    }
    defer { widthTimer?.invalidate() }
    func smooth(_ name: String, down: Bool) {
        var last: CFTimeInterval = 0
        driver.run(name) { t in
            if t > phaseCap { return true }
            let dt = last == 0 ? 0 : t - last
            last = t
            let y = list.viewport.minY + (down ? 1 : -1) * speed * CGFloat(dt)
            list.scroll(to: y)
            return down ? list.viewport.minY >= list.maxOffset - 0.5 : list.viewport.minY <= 0.5
        }
    }
    func fling(_ name: String, down: Bool) {
        var last: CFTimeInterval = 0
        var velocity: CGFloat = 0
        driver.run(name) { t in
            if t > phaseCap { return true }
            let dt = last == 0 ? 0 : CGFloat(t - last)
            last = t
            if velocity < 300 { velocity = 9000 }
            velocity *= pow(0.25, dt)
            let y = list.viewport.minY + (down ? 1 : -1) * velocity * dt
            list.scroll(to: y)
            return down ? list.viewport.minY >= list.maxOffset - 0.5 : list.viewport.minY <= 0.5
        }
    }
    func idle(_ name: String, _ seconds: Double) {
        driver.run(name) { t in t >= seconds }
    }
    var backingNotes = 0, screenNotes = 0
    let backingObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: window, queue: .main) { _ in backingNotes += 1 }
    let screenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { _ in screenNotes += 1 }
    func imageCensus() -> (layers: Int, surfaces: Int, matching: Int, stale: Int) {
        let target = window.colorSpace?.cgColorSpace
        var layers = 0, surfaces = 0, matching = 0, stale = 0
        CATransaction.lock()
        let roots = (adapter as? ManagedAdapter)?.items.compactMap { $0?.renderer?.view.layer } ?? []
        var stack = roots.isEmpty ? (window.contentView?.layer.map { [$0] } ?? []) : roots
        while let layer = stack.popLast() {
            layers += 1
            if let contents = layer.contents {
                let type = CFGetTypeID(contents as CFTypeRef)
                if type == CGImage.typeID {
                    let space = (contents as! CGImage).colorSpace
                    if let space = space, let target = target, CFEqual(space, target) { matching += 1 } else { stale += 1 }
                } else if type == IOSurfaceGetTypeID() {
                    surfaces += 1
                }
            }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
        CATransaction.unlock()
        return (layers, surfaces, matching, stale)
    }
    func visibleStale() -> Int {
        let target = window.colorSpace?.cgColorSpace
        var stale = 0
        CATransaction.lock()
        for item in (adapter as? ManagedAdapter)?.items ?? [] {
            guard let view = item?.renderer?.view, view.window != nil, !view.visibleRect.isEmpty, let root = view.layer else { continue }
            var stack = [root]
            while let layer = stack.popLast() {
                if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID, let target = target, !((contents as! CGImage).colorSpace.map { CFEqual($0, target) } ?? false) { stale += 1 }
                stack.append(contentsOf: layer.sublayers ?? [])
            }
        }
        CATransaction.unlock()
        return stale
    }
    func recolorCheck(_ label: String) {
        let before = imageCensus()
        let rastersBefore = LiteHTMLWidgetRenderer.totalPromotions
        let bumpsBefore = LiteHTMLWidgetRenderer.colorSpaceChanges
        let current = window.colorSpace?.cgColorSpace
        let next: NSColorSpace = (current.map { CFEqual($0, CGColorSpace(name: CGColorSpace.displayP3)!) } ?? false) ? .sRGB : .displayP3
        let notesBefore = backingNotes
        window.colorSpace = next
        let appkitPosted = backingNotes > notesBefore
        if !appkitPosted && !args.contains("--recolor-no-notify") { NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window) }
        idle("recolor", 2)
        let after = imageCensus()
        let rasters = LiteHTMLWidgetRenderer.totalPromotions - rastersBefore
        idle("recolor-settle", 2)
        let later = LiteHTMLWidgetRenderer.totalPromotions - rastersBefore
        print("recolor \(label): \(current.flatMap { NSColorSpace(cgColorSpace: $0)?.localizedName } ?? "?") -> \(next.localizedName ?? "?") appkit-posted=\(appkitPosted) layers=\(before.layers) surfaces=\(before.surfaces) images before matching=\(before.matching) stale=\(before.stale) after matching=\(after.matching) stale=\(after.stale) visible-stale=\(visibleStale()) rasters in 2s=\(rasters) in 4s=\(later) space bumps=\(LiteHTMLWidgetRenderer.colorSpaceChanges - bumpsBefore)")
    }
    let start = CACurrentMediaTime()
    if chat {
        smooth("smooth-up", down: false)
        idle("idle-top", 3)
        smooth("smooth-down", down: true)
        fling("fling-up", down: false)
        idle("idle-top2", 2)
        fling("fling-down", down: true)
    }
    if pattern == "both" || pattern == "smooth" {
        smooth("smooth-down", down: true)
        idle("idle-bottom", 3)
        if args.contains("--recolor") { recolorCheck("bottom") }
        smooth("smooth-up", down: false)
    }
    if pattern == "both" || pattern == "fling" {
        fling("fling-down", down: true)
        idle("idle-bottom2", 2)
        fling("fling-up", down: false)
    }
    idle(chat ? "idle-bottom" : "idle-top", 3)
    if let hold = option("--hold-end").flatMap(Double.init) {
        themeTimer?.invalidate()
        widthTimer?.invalidate()
        print("hold-end \(hold)s")
        idle("hold-end", hold)
    }
    NotificationCenter.default.removeObserver(backingObserver)
    NotificationCenter.default.removeObserver(screenObserver)
    if args.contains("--recolor") {
        let end = imageCensus()
        print("recolor end: images matching=\(end.matching) stale=\(end.stale) visible-stale=\(visibleStale())")
    }
    let tileTotals = WidgetTileStats.snapshot
    print(String(format: "tile jobs=%d full=%d copy=%.0f ms draw=%.0f ms setup=%.0f ms | %@", tileTotals.jobs, tileTotals.full, tileTotals.copy, tileTotals.draw, tileTotals.setup, LiteHTMLWidgetRenderer.tileSpareReport))
    print("window notifications: backing=\(backingNotes) screen=\(screenNotes) space bumps=\(LiteHTMLWidgetRenderer.colorSpaceChanges) rasters=\(LiteHTMLWidgetRenderer.totalPromotions)")
    let total = driver.phases.filter { $0.name.hasPrefix("smooth") || $0.name.hasPrefix("fling") }
    let frames = total.reduce(0) { $0 + $1.frames }, dropped = total.reduce(0) { $0 + $1.dropped }
    let busy = total.flatMap { $0.busyMs }
    print(String(format: "SCROLL TOTAL: frames=%d dropped=%d main avg=%.2f max=%.2f ms cpu=%.0f%% peak footprint=%.0fMB rss=%.0fMB threads=%d live=%d", frames, dropped, busy.reduce(0, +) / Double(max(1, busy.count)), busy.max() ?? 0, total.reduce(0) { $0 + ($1.cpuEnd - $1.cpuStart) } / max(0.001, total.reduce(0) { $0 + ($1.end - $1.start) }) * 100, Double(driver.phases.map { $0.peakFootprint }.max() ?? 0) / 1048576, Double(driver.phases.map { $0.peakResident }.max() ?? 0) / 1048576, driver.phases.map { $0.peakThreads }.max() ?? 0, driver.phases.map { $0.peakLive }.max() ?? 0))
    print("height jumps in view=\(list.visibleJumps) under-anchor=\(list.anchorJumps) compensated-in-view=\(list.visibleAnchored) anchored=\(list.anchoredResizes) resizes=\(list.resizes) total \(String(format: "%.0f", CACurrentMediaTime() - start))s")
    if !list.jumpLog.isEmpty { print("jumps: " + list.jumpLog.prefix(400).joined(separator: "; ")) }
    print(adapter.summary)
    print("blank: frames=\(driver.blankFrames) widget-frames=\(driver.blankWidgetFrames) widgets=\(driver.blankWidgets.count)")
    print(LiteHTMLWidgetRenderer.checkTotals)
    let blankLimit = Int(option("--fail-on-blank") ?? "") ?? 0
    let settledBlanks = driver.worstSettled.filter { $0.value.frames >= max(1, blankLimit) }.sorted { $0.value.frames > $1.value.frames }
    print("settled blanks: widgets=\(settledBlanks.count) worst=" + settledBlanks.prefix(8).map { "\($0.key) \($0.value.reason)x\($0.value.frames)" }.joined(separator: ", "))
    if blankLimit > 0 && !settledBlanks.isEmpty {
        print("BLANK FAIL: \(settledBlanks.count) widgets stayed blank (undrawn/uncovered/no-tiles/detached) for >= \(blankLimit) consecutive frames")
        fflush(stdout)
        exit(3)
    }
    driver.shotLog.forEach { print("  " + $0) }
    FeedSpikes.log.forEach { print("  spike " + $0) }
    print(FeedSpikes.attachSummary)
    FeedSpikes.imageLog.forEach { print("  attach image " + $0) }
    slowLock.lock()
    slowApplies.forEach { print("  slow apply " + $0) }
    slowLock.unlock()
    print(String(format: "main busy total=%.0f ms commit total=%.0f ms slow(>8.3ms)=%d", driver.meter.busyTotal * 1000, driver.meter.commitTotal * 1000, busy.filter { $0 > 8.3 }.count))
    print("slow frames by cause: " + FeedSpikes.buckets.sorted { $0.value.count > $1.value.count }.map { "\($0.key)=\($0.value.count)" }.joined(separator: " "))
    window.orderOut(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    LiteHTMLWidgetRenderer.quiesceRaster()
}
