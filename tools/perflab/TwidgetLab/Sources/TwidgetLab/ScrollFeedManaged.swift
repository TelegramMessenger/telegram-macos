import Cocoa
import WidgetSandbox
import TwidgetRenderer

final class TileSnapshot {
    let layers: [(frame: CGRect, contents: Any, scale: CGFloat)]
    let size: CGSize

    init(layers: [(frame: CGRect, contents: Any, scale: CGFloat)], size: CGSize) {
        self.layers = layers
        self.size = size
    }

    static func capture(_ view: NSView) -> (snapshot: AnyObject, bytes: Int)? {
        guard view.window != nil, let layer = view.layer else { return nil }
        let tiles = feedTileLayers(layer).filter { $0.delegate != nil && !($0.delegate is NSView) }
        guard !tiles.isEmpty, tiles.allSatisfy({ $0.contents != nil }) else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        let bytes = tiles.reduce(0) { $0 + Int($1.bounds.width * scale) * Int($1.bounds.height * scale) * 4 }
        return (TileSnapshot(layers: tiles.map { ($0.frame, $0.contents!, $0.contentsScale) }, size: view.bounds.size), bytes)
    }

    func install(in host: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        for tile in layers {
            let layer = CALayer()
            layer.anchorPoint = .zero
            layer.contentsGravity = .topLeft
            layer.frame = tile.frame
            layer.contentsScale = tile.scale
            layer.contents = tile.contents
            host.addSublayer(layer)
        }
        CATransaction.commit()
    }
}

var feedPrepare = false
var feedHoldHeight = false

final class ManagedItem {
    var adoptRenderer: ((LiteHTMLWidgetRenderer, WidgetExecutor) -> Void)?
    let name: String
    let index: Int
    let bubble: WidgetBubble
    var renderer: LiteHTMLWidgetRenderer?
    var executor: WidgetExecutor?
    var visible = false
    weak var view: ManagedBubbleView?

    func onRenderer(_ body: @escaping (LiteHTMLWidgetRenderer) -> Void) {
        guard let renderer else { return }
        guard let executor = executor ?? bubble.host?.executor, !executor.isCurrent else {
            body(renderer)
            return
        }
        executor.async { body(renderer) }
    }

    init(name: String, html: String, index: Int, width: CGFloat, feed: WidgetFeed, options: WidgetHost.Options) {
        self.name = name
        self.index = index
        var made: ((LiteHTMLWidgetRenderer) -> Void)?
        bubble = WidgetBubble(html: html, theme: "light", width: width, options: options, feed: feed, rendererFactory: { _, theme, width in
            let renderer = LiteHTMLWidgetRenderer(theme: theme, width: width)
            renderer.debugName = name
            made?(renderer)
            let timed = TimedRenderer(renderer) { false }
            timed.name = name
            return timed
        })
        bubble.holdsHeightOnRebuild = feedHoldHeight
        made = { [weak self] renderer in
            self?.renderer = renderer
            self?.executor = nil
            renderer.preparesOffscreen = feedPrepare && (self?.bubble.isPrepared ?? false)
        }
        adoptRenderer = { [weak self] renderer, executor in
            renderer.debugName = name
            self?.renderer = renderer
            self?.executor = executor
            let prepared = feedPrepare && (self?.bubble.isPrepared ?? false)
            executor.async { renderer.preparesOffscreen = prepared }
        }
        bubble.onPendingHost = { [weak self] host in
            let timed = host.rendererObject as? TimedRenderer
            timed?.name = name
            guard let renderer = timed?.inner as? LiteHTMLWidgetRenderer else { return }
            self?.renderer = renderer
            self?.executor = host.executor
            host.executor.async { renderer.preparesOffscreen = true }
        }
        bubble.onPrepareChange = { [weak self] prepared in
            self?.onRenderer { $0.preparesOffscreen = feedPrepare && prepared }
        }
        bubble.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.visible = visible
            let paused = self.bubble.slot.isPausedOnScreen
            self.onRenderer { renderer in
                renderer.keepsTilesWhileHidden = paused
                renderer.setVisible(visible)
            }
        }
        bubble.onPauseChange = { [weak self] paused in
            self?.onRenderer { $0.keepsTilesWhileHidden = paused }
        }
        bubble.onHostChange = { [weak self] in
            guard let self else { return }
            if let host = self.bubble.host {
                self.executor = host.executor
            } else {
                self.renderer = nil
                self.executor = nil
            }
            self.view?.hostChanged()
        }
        bubble.onHostContent = { [weak self] in self?.view?.hostChanged() }
        bubble.onSnapshotChange = { [weak self] in self?.view?.hostChanged() }
        bubble.captureSnapshot = { [weak self] in
            guard let view = self?.renderer?.view else { return nil }
            return TileSnapshot.capture(view)
        }
    }
}

final class ManagedBubbleView: FeedFlippedView {
    private(set) var item: ManagedItem?
    private let container = FeedFlippedView(frame: .zero)
    private let placeholder = CALayer()
    private(set) var showsSnapshot = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, item?.bubble.host != nil { FeedSpikes.noteAttach(container) }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        placeholder.anchorPoint = .zero
        layer?.addSublayer(placeholder)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(item: ManagedItem) {
        if self.item !== item {
            if self.item?.view === self { self.item?.view = nil }
            self.item = item
            item.view = self
        }
        hostChanged()
    }

    func hostChanged() {
        guard let item else { return }
        let ready = item.bubble.host != nil && item.bubble.hostHasContent
        if !ready, let snapshot = item.bubble.snapshot as? TileSnapshot {
            if !showsSnapshot {
                snapshot.install(in: placeholder)
                showsSnapshot = true
            }
            item.bubble.snapshotShown()
        } else if showsSnapshot {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            placeholder.sublayers?.forEach { $0.removeFromSuperlayer() }
            CATransaction.commit()
            showsSnapshot = false
        }
        guard let host = item.bubble.host else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        if container.superview !== self { addSubview(container) }
        container.frame = bounds
        if host.view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(host.view)
            if window != nil { FeedSpikes.noteAttach(host.view) }
        }
        host.view.frame = container.bounds
        host.view.autoresizingMask = [.width, .height]
    }

    override func layout() {
        super.layout()
        container.frame = bounds
        placeholder.frame = bounds
    }
}

final class ManagedAdapter: FeedAdapter, WidgetFeedSpace {
    let feed = WidgetFeed()
    let corpus: [(String, String)]
    var width: CGFloat
    let options: WidgetHost.Options
    var theme = "light"
    var items: [ManagedItem?]
    var heights: [CGFloat]
    var onResize: ((Int) -> Void)?
    weak var list: FeedList?

    init(corpus: [(String, String)], width: CGFloat, policy: WidgetFeedPolicy, options: WidgetHost.Options) {
        self.corpus = corpus
        self.width = width
        self.options = options
        items = Array(repeating: nil, count: corpus.count)
        heights = Array(repeating: 0, count: corpus.count)
        feed.policy = policy
        feed.schedule = { block in
            let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in
                let t0 = CACurrentMediaTime()
                block()
                FeedSpikes.tickMs += (CACurrentMediaTime() - t0) * 1000
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    func item(_ index: Int) -> ManagedItem {
        if let item = items[index] { return item }
        let item = ManagedItem(name: corpus[index].0, html: corpus[index].1, index: index, width: width, feed: feed, options: options)
        item.bubble.onHeightChange = { [weak self, weak item] in
            guard let self, let item else { return }
            self.heights[index] = item.bubble.height
            self.onResize?(index)
        }
        item.bubble.slot.space = self
        item.bubble.slot.locate = { [weak self] in self?.list?.bubbleRect(index) }
        if headless {
            let previous = item.bubble.onHostChange
            item.bubble.onHostChange = { [weak self, weak item] in
                previous?()
                if let self, item?.bubble.host == nil, self.prepared[index]?.prepared.isAdopted ?? true {
                    self.prepared[index] = nil
                    self.requested.remove(index)
                }
            }
            item.bubble.preparedHost = { [weak self, weak item] in
                guard let self, let record = self.prepared[index], let host = record.prepared.adopt() else { return nil }
                WidgetPreparer.adopted(record.prepared)
                self.adoptions += 1
                if let renderer = record.renderer { item?.adoptRenderer?(renderer, host.executor) }
                return host
            }
        }
        items[index] = item
        return item
    }

    var headless = false
    var headlessScreens: CGFloat = 2
    var headlessWait: Double = 0.025
    let prepareEntries = DispatchQueue(label: "lab.prepareEntries", qos: .userInitiated)
    final class PreparedRecord {
        let prepared: WidgetPrepared
        let renderer: LiteHTMLWidgetRenderer?
        init(prepared: WidgetPrepared, renderer: LiteHTMLWidgetRenderer?) {
            self.prepared = prepared
            self.renderer = renderer
        }
    }
    var prepared: [Int: PreparedRecord] = [:]
    var requested = Set<Int>()
    var measured = Set<Int>()
    var adoptions = 0
    var shellMisses = 0
    var syncReady = 0
    var placeholderAppear = 0
    var latencies: [Double] = []

    func dropPrepared() {
        for (index, record) in prepared where !record.prepared.isAdopted {
            record.prepared.discard()
            prepared[index] = nil
            requested.remove(index)
        }
    }

    func setTheme(_ theme: String) {
        self.theme = theme
        dropPrepared()
        items.forEach { $0?.bubble.setTheme(theme) }
    }

    func setWidth(_ width: CGFloat) {
        self.width = width
        dropPrepared()
        items.forEach { $0?.bubble.setWidth(width) }
        WidgetShellPool.shared.prewarm(width: width)
    }

    func requestPrepares(list: FeedList) {
        let v = list.viewport
        let span = v.height * headlessScreens
        var i = list.index(at: max(0, v.minY - span))
        let end = list.index(at: v.maxY + span)
        var wanted: [Int] = []
        while i <= end && i < list.count {
            if !requested.contains(i) && items[i]?.bubble.host == nil {
                wanted.append(i)
            }
            i += 1
        }
        let center = v.midY
        wanted.sort { abs(list.bubbleRect($0).midY - center) < abs(list.bubbleRect($1).midY - center) }
        for index in wanted {
            requested.insert(index)
            let html = corpus[index].1, name = corpus[index].0, width = self.width, options = self.options, wait = headlessWait
            let theme = self.theme
            prepareEntries.async { [weak self] in
                guard let p = WidgetPreparer.prepare(html: html, theme: WidgetTheme(colorScheme: theme), width: width, options: options) else {
                    DispatchQueue.main.async { self?.requested.remove(index); self?.shellMisses += 1 }
                    return
                }
                let timed = p.host.rendererObject as? TimedRenderer
                timed?.name = name
                let made = timed?.inner as? LiteHTMLWidgetRenderer
                p.host.executor.async { made?.preparesOffscreen = true }
                let ready = p.wait(timeout: wait)
                let renderer = made
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.prepared[index] = PreparedRecord(prepared: p, renderer: renderer)
                    if ready { self.syncReady += 1 }
                    self.preparedReady(index, p)
                    if !ready {
                        p.onReady = { [weak self] p in self?.preparedReady(index, p) }
                    }
                }
            }
        }
    }

    private func preparedReady(_ index: Int, _ p: WidgetPrepared) {
        guard p.isReady, !measured.contains(index) else { return }
        measured.insert(index)
        if let latency = p.readyLatency { latencies.append(latency * 1000) }
        if p.height > 0, items[index]?.bubble.host == nil {
            heights[index] = p.height
            onResize?(index)
        }
        list.map { feedLayoutChanged($0) }
    }

    private func feedLayoutChanged(_ list: FeedList) {
        feed.setNeedsUpdate()
    }

    func rowAppeared(_ index: Int) {
        if headless && !measured.contains(index) && items[index]?.bubble.hasContent != true {
            placeholderAppear += 1
        }
    }

    var feedViewport: CGRect { list?.viewport ?? .zero }
    var feedOnScreen: Bool { list?.scrollView.window.map { feedWindowVisible($0) } ?? false }
    func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] {
        guard let list, list.count > 0 else { return [] }
        var result: [WidgetFeedSlot] = []
        var i = list.index(at: rect.minY)
        while i < list.count && list.bubbleRect(i).minY < rect.maxY {
            if list.bubbleRect(i).maxY > rect.minY { result.append(item(i).bubble.slot) }
            i += 1
        }
        return result
    }

    var count: Int { corpus.count }
    func bubbleHeight(_ index: Int) -> CGFloat { max(heights[index], 60) }
    func makeBubble() -> NSView { ManagedBubbleView(frame: .zero) }
    func configure(_ bubble: NSView, index: Int, width: CGFloat) {
        (bubble as! ManagedBubbleView).update(item: item(index))
    }
    func didLayout(list: FeedList) {
        if self.list == nil {
            self.list = list
            feed.attach(self)
        }
        if headless {
            requestPrepares(list: list)
        }
        feed.setNeedsUpdate()
    }
    var liveCount: Int { feed.liveCount }
    var tileBytes: Int { items.reduce(0) { $0 + ($1?.renderer.map { feedTileBytes($0.view) } ?? 0) } + feed.snapshotBytes }
    func blankReason(_ index: Int, visible: CGRect) -> String? {
        guard let item = items[index] else { return "no-item" }
        if item.view?.showsSnapshot == true { return nil }
        guard let renderer = item.renderer else { return "no-host" }
        if !item.bubble.hostHasContent { return "loading" }
        let reason = feedBlankReason(view: renderer.view, visible: visible)
        if let reason = reason, ProcessInfo.processInfo.environment["LAB_TILE_DEBUG"] != nil {
            let name = item.name
            renderer.scheduleUrgent { [weak renderer] in
                if let renderer = renderer { print("TILEDEBUG \(name) \(reason) \(renderer.tileDebug)") }
            }
        }
        return reason
    }
    var summary: String {
        let renderers = items.compactMap { $0?.renderer }
        let sorted = latencies.sorted()
        let headlessLine = headless ? String(format: "headless: shells made=%d misses=%d requested=%d ready-in-budget=%d adopted=%d placeholder-appear=%d outstanding=%d evicted=%d latency p50=%.0f p95=%.0f max=%.0f ms\n", WidgetShellPool.shared.made, shellMisses, requested.count, syncReady, adoptions, placeholderAppear, WidgetPreparer.outstandingCount, WidgetPreparer.evicted, sorted.isEmpty ? 0 : sorted[sorted.count / 2], sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 95 / 100)], sorted.last ?? 0) : ""
        let async = renderers.reduce((0, 0)) { ($0.0 + $1.asyncTileReport.jobs, $0.1 + $1.asyncTileReport.installed) }
        return String(format: "async tile jobs=%d installed=%d background boots=%d adopted=%d\n", async.0, async.1, items.reduce(0) { $0 + ($1?.bubble.backgroundBoots ?? 0) }, items.reduce(0) { $0 + ($1?.bubble.adoptedHosts ?? 0) }) + String(format: "prepared tiles=%d bg ms=%.0f %@\n", renderers.reduce(0) { $0 + $1.preparedTileCount }, renderers.reduce(0) { $0 + $1.preparedMilliseconds }, LiteHTMLWidgetRenderer.preparedReport) + headlessLine + "pauses=\(feed.pauses) feed created=\(feed.created) dropped=\(feed.dropped) ticks=\(feed.ticks) examined(last)=\(feed.lastExamined) snapshots=\(feed.snapshotBytes >> 20)MB bubbles=\(items.filter { $0 != nil }.count)\n" + feedTopRenderers(items.compactMap { item in item.flatMap { i in i.renderer.map { (i.name, $0) } } })
    }
}

func makeManagedAdapter(corpus: [(String, String)], args: [String], option: (String) -> String?) -> FeedAdapter {
    var policy = WidgetFeedPolicy()
    if let v = option("--keep").flatMap(Double.init) { policy.keepScreens = CGFloat(v) }
    if let v = option("--prefetch").flatMap(Double.init) { policy.prefetchScreens = CGFloat(v) }
    if let v = option("--budget").flatMap(Int.init) { policy.liveBudget = v }
    if let v = option("--snapshot-mb").flatMap(Int.init) { policy.snapshotBudgetBytes = v << 20 }
    policy.bootSnapshotsOnlyWhenSlow = args.contains("--slow-boot")
    feedPrepare = args.contains("--prepare")
    feedHoldHeight = args.contains("--hold-height")
    if let v = option("--pause-velocity").flatMap(Double.init) { policy.pauseVelocity = CGFloat(v) }
    var options = labOptions()
    options.asyncValidation = !args.contains("--sync-validation")
    let width = CGFloat(Double(option("--width") ?? "440") ?? 440)
    options.backgroundBoot = args.contains("--bgboot")
    options.pools = args.contains("--pools") || args.contains("--headless") || options.backgroundBoot
    if options.pools {
        WidgetWarmup.prewarm(renderers: 0, engines: Int(option("--pool-engines") ?? "4") ?? 4, validators: 4)
    }
    let adapter = ManagedAdapter(corpus: corpus, width: width, policy: policy, options: options)
    adapter.headless = args.contains("--headless")
    if adapter.headless || options.backgroundBoot {
        WidgetShellPool.shared.factory = { width in
            TimedRenderer(LiteHTMLWidgetRenderer(theme: "light", width: width)) { false }
        }
        if let v = option("--shells").flatMap(Int.init) { WidgetShellPool.shared.targetSize = v }
        WidgetShellPool.shared.prewarm(width: width)
    }
    if let v = option("--headless-screens").flatMap(Double.init) { adapter.headlessScreens = CGFloat(v) }
    if let v = option("--headless-wait").flatMap(Double.init) { adapter.headlessWait = v / 1000 }
    if let v = option("--outstanding").flatMap(Int.init) { WidgetPreparer.outstandingLimit = v }
    return adapter
}
