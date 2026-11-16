import Cocoa
import WidgetSandbox
import TwidgetRenderer
import WidgetSandboxProtocol

private let hostileWidgets: [(String, String)] = [
    ("hostile/freeze", "<div id=a>freeze</div><script>document.getElementById('a').textContent='x';while(true){}</script>"),
    ("hostile/throw", "<div>throw</div><script>throw new Error('boom')</script>"),
    ("hostile/recursion", "<div>recursion</div><script>function f(n){return f(n+1)+1};f(0)</script>"),
    ("hostile/memory", "<div>memory</div><script>let a=[];for(;;){a.push(new Array(1e6).fill(1))}</script>"),
    ("hostile/raf", "<div id=b style='height:200px'></div><script>let n=0;function t(){document.getElementById('b').style.height=(100+(n++%300))+'px';requestAnimationFrame(t)};t()</script>"),
    ("hostile/timers", "<div id=c></div><script>for(let i=0;i<500;i++)setInterval(()=>{document.getElementById('c').textContent=String(Math.random())},1)</script>"),
    ("hostile/dom", "<div id=d></div><script>const d=document.getElementById('d');for(let i=0;i<5000;i++){const e=document.createElement('div');e.textContent=i;d.appendChild(e)}</script>"),
    ("hostile/late-freeze", "<div id=e>late</div><script>setTimeout(()=>{while(true){}},30)</script>"),
    ("gate/click-bridge", "<script>window.bot=window.TelegramWidget</script><button id=g style='width:300px;height:120px'>go</button><script>let n=0;const g=document.getElementById('g');g.addEventListener('pointerdown',()=>{bot.openLink('https://example.com/'+n)});g.addEventListener('click',()=>{n++;bot.sendMessage('click '+n);bot.sendMessage('again '+n);setTimeout(()=>bot.sendMessage('late '+n),0);Promise.resolve().then(()=>bot.openLink('https://example.com/p'+n));g.textContent='go '+n})</script>"),
    ("gate/timer-bridge", "<script>window.bot=window.TelegramWidget</script><div id=t style='height:80px'>t</div><script>let k=0;setInterval(()=>{k++;bot.sendMessage('timer '+k);document.getElementById('t').textContent=String(k)},5)</script>"),
    ("gate/keydown-bridge", "<script>window.bot=window.TelegramWidget</script><input id=i style='width:300px;height:60px'><script>document.getElementById('i').addEventListener('keydown',e=>bot.sendMessage('key '+e.key));document.addEventListener('click',()=>{bot.sendMessage('doc');document.body.appendChild(document.createElement('div')).textContent='x'})</script>"),
    ("hostile/canvas", "<canvas id=k width=400 height=300></canvas><script>const c=document.getElementById('k').getContext('2d');let t=0;function f(){for(let i=0;i<200;i++){c.fillStyle='hsl('+((t+i)%360)+',80%,50%)';c.fillRect((i*7+t)%400,(i*13)%300,20,20)}t++;requestAnimationFrame(f)};f()</script>"),
]

private final class StressState {
    let html: String
    private let lock = NSLock()
    private var prepared: (key: String, value: WidgetPrepared)?
    private var heights: [String: CGFloat] = [:]
    var bubble: WidgetBubble?
    var renderer: LiteHTMLWidgetRenderer?
    var executor: WidgetExecutor?
    private var live = false

    init(html: String) {
        self.html = html
    }

    deinit {
        let pending = prepared?.value
        let bubble = self.bubble
        if bubble != nil || pending != nil {
            DispatchQueue.main.async {
                pending?.discard()
                _ = bubble
            }
        }
    }

    func prepare(width: CGFloat, theme: String, options: WidgetHost.Options, wait: TimeInterval) {
        let key = "\(Int(width))|\(theme)"
        lock.lock()
        let known = heights[key] != nil || live
        let running = prepared?.key == key ? prepared?.value : nil
        lock.unlock()
        if known { return }
        let made: WidgetPrepared
        if let running = running {
            made = running
        } else {
            guard let p = WidgetPreparer.prepare(html: html, theme: WidgetTheme(colorScheme: theme), width: width, options: options) else {
                WidgetShellPool.shared.prewarm(width: width)
                return
            }
            made = p
            p.onReady = { [weak self] p in
                guard let self = self, p.height > 0 else { return }
                self.lock.lock()
                self.heights[key] = p.height
                self.lock.unlock()
            }
            lock.lock()
            let previous = prepared
            prepared = (key, p)
            lock.unlock()
            if let previous = previous, previous.value !== p {
                previous.value.discard()
            }
        }
        if made.wait(timeout: wait), made.height > 0 {
            lock.lock()
            heights[key] = made.height
            lock.unlock()
        }
    }

    private func take(width: CGFloat, theme: String) -> WidgetHost? {
        let key = "\(Int(width))|\(theme)"
        lock.lock()
        let p = prepared
        prepared = nil
        lock.unlock()
        guard let p = p else { return nil }
        guard p.key == key, let host = p.value.adopt() else {
            p.value.discard()
            return nil
        }
        WidgetPreparer.adopted(p.value)
        return host
    }

    func onRenderer(_ body: @escaping (LiteHTMLWidgetRenderer) -> Void) {
        guard let renderer = renderer else { return }
        guard let executor = executor ?? bubble?.host?.executor, !executor.isCurrent else {
            body(renderer)
            return
        }
        executor.async { body(renderer) }
    }

    func makeBubble(width: CGFloat, theme: String, options: WidgetHost.Options, feed: WidgetFeed) -> WidgetBubble {
        if let bubble = bubble {
            bubble.setTheme(theme)
            return bubble
        }
        var made: ((LiteHTMLWidgetRenderer) -> Void)?
        let bubble = WidgetBubble(html: html, theme: theme, width: width, options: options, feed: feed, rendererFactory: { _, theme, width in
            let r = LiteHTMLWidgetRenderer(theme: theme, width: width)
            made?(r)
            return r
        })
        made = { [weak self, weak bubble] r in
            self?.renderer = r
            self?.executor = nil
            r.preparesOffscreen = bubble?.isPrepared ?? false
        }
        bubble.preparedHost = { [weak self, weak bubble] in
            guard let self = self, let host = self.take(width: width, theme: theme) else { return nil }
            if let r = host.rendererObject as? LiteHTMLWidgetRenderer {
                self.renderer = r
                self.executor = host.executor
                let prepared = bubble?.isPrepared ?? false
                host.executor.async { r.preparesOffscreen = prepared }
            }
            return host
        }
        bubble.configure = { host in
            host.onBridge = { _, _ in
                stressBridgeCalls.lock()
                stressBridgeCount += 1
                stressBridgeCalls.unlock()
            }
        }
        bubble.onPrepareChange = { [weak self] p in self?.onRenderer { $0.preparesOffscreen = p } }
        bubble.onPauseChange = { [weak self] p in self?.onRenderer { $0.keepsTilesWhileHidden = p } }
        bubble.onVisibilityChange = { [weak self] v in self?.onRenderer { $0.setVisible(v) } }
        bubble.onHostChange = { [weak self, weak bubble] in
            guard let self = self else { return }
            if let host = bubble?.host {
                self.executor = host.executor
                self.lock.lock()
                self.live = true
                self.lock.unlock()
            } else {
                self.renderer = nil
                self.executor = nil
                self.lock.lock()
                self.live = false
                self.lock.unlock()
            }
        }
        self.bubble = bubble
        return bubble
    }
}

let stressBridgeCalls = NSLock()
var stressBridgeCount = 0

func stressClick(_ view: NSView, window: NSWindow?) {
    guard let window = window ?? view.window, view.bounds.width > 1, view.bounds.height > 1 else { return }
    let point = NSPoint(x: CGFloat.random(in: 0..<min(view.bounds.width, 300)), y: CGFloat.random(in: 0..<min(view.bounds.height, 60)))
    let inWindow = view.convert(point, to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        guard let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { return }
        if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
    }
}

private final class StressSpace: WidgetFeedSpace {
    var viewport = CGRect(x: 0, y: 0, width: 440, height: 900)
    var slots: [WidgetFeedSlot] = []
    var feedViewport: CGRect { viewport }
    var feedOnScreen: Bool { true }
    func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { slots }
}

func runCrashStress(_ args: [String], option: (String) -> String?) {
    let seconds = Double(option("--seconds") ?? "40") ?? 40
    let workers = Int(option("--workers") ?? "4") ?? 4
    var corpus = loadFeedCorpus(limit: Int.max)
    let textChaos = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../widgets/hostile/text-chaos.html").standardized
    if let html = try? String(contentsOf: textChaos, encoding: .utf8) {
        corpus += Array(repeating: ("hostile/text-chaos", html), count: 6)
    }
    for name in ["attr-chaos", "blur-chaos"] {
        let url = textChaos.deletingLastPathComponent().appendingPathComponent(name + ".html")
        if let html = try? String(contentsOf: url, encoding: .utf8) {
            corpus += Array(repeating: ("hostile/" + name, html), count: 6)
        }
    }
    let heavy = corpus.filter { $0.1.contains("<canvas") || $0.1.contains("three") || $0.1.contains("webgl") || $0.0.contains("3d") }
    let gates = hostileWidgets.filter { $0.0.hasPrefix("gate/") }
    corpus += hostileWidgets + heavy + heavy + Array(repeating: gates, count: 10).flatMap { $0 }
    print("crashstress: corpus=\(corpus.count) heavy=\(heavy.count) workers=\(workers) seconds=\(seconds)")
    WidgetShellPool.shared.factory = { width in
        let r = LiteHTMLWidgetRenderer(theme: "light", width: width)
        r.preparesOffscreen = true
        return r
    }
    WidgetShellPool.shared.targetSize = 8
    WidgetWarmup.prewarm(renderers: 0, engines: 2, validators: 2)
    WidgetPreparer.outstandingLimit = Int(option("--outstanding") ?? "6") ?? 6
    var options = labOptions()
    options.asyncValidation = true
    options.pools = true
    if !args.contains("--app-options") {
        options.cpuLimitMs = 150
        options.cpuKillAfterMs = 400
        options.memoryLimitBytes = 32 << 20
    }
    let widths: [CGFloat] = [320, 440, 441]
    widths.forEach { WidgetShellPool.shared.prewarm(width: $0) }

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .white
    window.ignoresMouseEvents = true
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    if let screen = NSScreen.main {
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 480, y: screen.visibleFrame.minY + 20))
    }
    let content = NSView(frame: window.contentLayoutRect)
    content.wantsLayer = true
    window.contentView = content
    window.orderFrontRegardless()

    let gateBefore = runGatePhase(content: content, options: options, rounds: 6)
    let feed = WidgetFeed()
    let space = StressSpace()
    feed.attach(space)
    let deadline = CACurrentMediaTime() + seconds
    let counters = NSLock()
    var stats: [String: Int] = [:]
    func count(_ key: String) {
        counters.lock()
        stats[key, default: 0] += 1
        counters.unlock()
    }
    let statesLock = NSLock()
    var states: [StressState] = (0..<24).map { StressState(html: corpus[$0 * 7 % corpus.count].1) }

    func adoptOnMain(_ p: WidgetPrepared, hold: TimeInterval) {
        DispatchQueue.main.async {
            guard let host = p.adopt() else { count("adopt-lost"); return }
            WidgetPreparer.adopted(p)
            count("adopted")
            host.moveToMain {
                count("moved")
                host.view.frame = CGRect(x: 0, y: CGFloat.random(in: 0...600), width: p.width, height: 300)
                content.addSubview(host.view)
                host.setVisible(true)
                host.onBridge = { _, _ in
                    stressBridgeCalls.lock()
                    stressBridgeCount += 1
                    stressBridgeCalls.unlock()
                }
                if Bool.random() { host.setTheme(p.theme.colorScheme == .dark ? "light" : "dark") }
                if let lite = host.rendererObject as? LiteHTMLWidgetRenderer {
                    for k in 0..<4 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * hold / 4) { stressClick(lite.view, window: content.window) }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                    host.setVisible(false)
                    host.view.removeFromSuperview()
                    host.destroy()
                }
            }
        }
    }

    for w in 0..<workers {
        let queue = DispatchQueue(label: "stress.worker.\(w)", qos: .userInitiated)
        queue.async {
            var i = w
            while CACurrentMediaTime() < deadline {
                i += 1
                let pick = corpus[Int.random(in: 0..<corpus.count)]
                let width = widths.randomElement()!
                let theme = Bool.random() ? "light" : "dark"
                switch Int.random(in: 0..<9) {
                case 0:
                    guard let p = WidgetPreparer.prepare(html: pick.1, theme: WidgetTheme(colorScheme: theme), width: width, options: options) else { count("no-shell"); usleep(2000); continue }
                    p.discard()
                    count("discard-now")
                case 1:
                    guard let p = WidgetPreparer.prepare(html: pick.1, theme: WidgetTheme(colorScheme: theme), width: width, options: options) else { count("no-shell"); usleep(2000); continue }
                    usleep(UInt32.random(in: 0...40_000))
                    p.discard()
                    count("discard-later")
                case 2:
                    guard let p = WidgetPreparer.prepare(html: pick.1, theme: WidgetTheme(colorScheme: theme), width: width, options: options) else { count("no-shell"); usleep(2000); continue }
                    p.host.setTheme(theme == "dark" ? "light" : "dark")
                    p.host.setVisible(Bool.random())
                    _ = p.wait(timeout: Double.random(in: 0...0.05))
                    adoptOnMain(p, hold: Double.random(in: 0...0.4))
                case 3:
                    guard let p = WidgetPreparer.prepare(html: pick.1, theme: WidgetTheme(colorScheme: theme), width: width, options: options) else { count("no-shell"); usleep(2000); continue }
                    count("left-for-eviction")
                    _ = p
                case 4:
                    guard let p = WidgetPreparer.prepare(html: pick.1, theme: WidgetTheme(colorScheme: theme), width: width, options: options) else { count("no-shell"); usleep(2000); continue }
                    DispatchQueue.concurrentPerform(iterations: 3) { k in
                        if k == 0 { p.discard() } else if k == 1 { adoptOnMain(p, hold: 0.05) } else { _ = p.wait(timeout: 0.01); p.onReady = { _ in count("ready") } }
                    }
                    count("race-discard-adopt")
                case 5, 6:
                    statesLock.lock()
                    let state = states.randomElement()!
                    statesLock.unlock()
                    state.prepare(width: width, theme: theme, options: options, wait: 0.025)
                    count("state-prepare")
                case 7:
                    statesLock.lock()
                    let index = Int.random(in: 0..<states.count)
                    let dropped = states[index]
                    states[index] = StressState(html: pick.1)
                    statesLock.unlock()
                    _ = dropped
                    count("state-release-offmain")
                default:
                    guard let p = WidgetPreparer.prepare(html: pick.1, theme: WidgetTheme(colorScheme: theme), width: width, options: options, tracked: false) else { count("no-shell"); usleep(2000); continue }
                    _ = p.wait(timeout: 0.2)
                    p.discard()
                    count("untracked")
                }
            }
        }
    }

    let colorSpaceEvery = Int(option("--colorspace-every") ?? "0") ?? 0
    let colorSpaces: [NSColorSpace] = [.displayP3, .sRGB, .genericRGB, .extendedSRGB]
    var tick = 0
    while CACurrentMediaTime() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.016))
        tick += 1
        statesLock.lock()
        let snapshot = states
        statesLock.unlock()
        let state = snapshot[tick % snapshot.count]
        switch tick % 12 {
        case 0, 1, 2:
            let theme = Bool.random() ? "light" : "dark"
            let bubble = state.makeBubble(width: widths.randomElement()!, theme: theme, options: options, feed: feed)
            if bubble.ensureHost() != nil, let host = bubble.host {
                if host.view.superview == nil {
                    host.view.frame = CGRect(x: 0, y: CGFloat.random(in: 0...600), width: 440, height: 300)
                    content.addSubview(host.view)
                }
                count("ensure-host")
            }
            bubble.setTheme(theme)
        case 3:
            if let bubble = state.bubble {
                bubble.host?.view.removeFromSuperview()
                bubble.slot.drop?()
                count("drop-host")
            }
        case 4:
            if let bubble = state.bubble {
                bubble.slot.visibilityChanged?(Bool.random())
                bubble.slot.prepareChanged?(Bool.random())
                bubble.slot.pauseChanged?(Bool.random())
            }
        case 5:
            if tick % 60 == 5 {
                feed.memoryPressure(critical: true)
                WidgetSurfacePool.shared.purge()
                WidgetShellPool.shared.drain()
                widths.forEach { WidgetShellPool.shared.prewarm(width: $0) }
                count("purge")
            }
        case 6:
            if let bubble = state.bubble {
                bubble.setWidth(widths.randomElement()!)
                bubble.setTheme(Bool.random() ? "light" : "dark")
            }
        case 7:
            space.viewport.origin.y = CGFloat.random(in: 0...20000)
            feed.setNeedsUpdate()
            if colorSpaceEvery > 0, tick % colorSpaceEvery == 7 {
                window.colorSpace = colorSpaces[(tick / colorSpaceEvery) % colorSpaces.count]
                NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
                NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
                count("colorspace")
            }
        case 8, 9:
            for candidate in snapshot.shuffled() {
                if candidate.bubble?.host != nil, let view = candidate.renderer?.view, view.window != nil {
                    stressClick(view, window: nil)
                    count("click")
                    break
                }
            }
        default:
            break
        }
    }
    print("crashstress: workers done, draining")
    RunLoop.main.run(until: Date().addingTimeInterval(2))
    statesLock.lock()
    states.removeAll()
    statesLock.unlock()
    RunLoop.main.run(until: Date().addingTimeInterval(2))
    counters.lock()
    print("crashstress: " + stats.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    counters.unlock()
    stressBridgeCalls.lock()
    print("crashstress: bridge calls=\(stressBridgeCount)")
    stressBridgeCalls.unlock()
    print("crashstress: preparer started=\(WidgetPreparer.started) evicted=\(WidgetPreparer.evicted) outstanding=\(WidgetPreparer.outstandingCount)")
    let gateFailures = gateBefore + runGatePhase(content: content, options: options, rounds: Int(option("--gate-rounds") ?? "12") ?? 12)
    print(gateFailures == 0 ? "crashstress: OK" : "crashstress: GATE FAILURES=\(gateFailures)")
}

private func runGatePhase(content: NSView, options: WidgetHost.Options, rounds: Int) -> Int {
    let widgets = hostileWidgets.filter { $0.0.hasPrefix("gate/") }
    var failures = 0
    var options = options
    options.visible = true
    for round in 0..<rounds {
        let widget = widgets[round % widgets.count]
        let prepared = round % 2 == 1
        var host: WidgetHost?
        if prepared {
            var p: WidgetPrepared?
            let deadline = Date().addingTimeInterval(3)
            while p == nil && Date() < deadline {
                var done = false
                let html = widget.1
                DispatchQueue.global(qos: .userInitiated).async {
                    let made = WidgetPreparer.prepare(html: html, theme: WidgetTheme(colorScheme: "light"), width: 440, options: options, tracked: false)
                    DispatchQueue.main.async {
                        p = made
                        done = true
                    }
                }
                while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
                if p == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            }
            if let p = p, let adopted = p.adopt() {
                var moved = false
                adopted.moveToMain { moved = true }
                while !moved { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
                host = adopted
            }
        } else {
            host = try? WidgetHost(html: widget.1, theme: "light", width: 440, options: options, rendererFactory: { _, theme, width in LiteHTMLWidgetRenderer(theme: theme, width: width) })
        }
        guard let host = host, let lite = host.rendererObject as? LiteHTMLWidgetRenderer else {
            print("crashstress: gate \(widget.0) no host")
            failures += 1
            continue
        }
        var bridged = 0
        host.onBridge = { _, _ in bridged += 1 }
        host.view.frame = CGRect(x: 0, y: 0, width: 440, height: 300)
        content.addSubview(host.view)
        host.setVisible(true)
        let ready = Date().addingTimeInterval(20)
        while !(host.diagnostics.rendered && host.diagnostics.loaded) && Date() < ready { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let clicks = 8
        for _ in 0..<clicks {
            let view = lite.view
            let point = NSPoint(x: 40, y: view.isFlipped ? 30 : view.bounds.height - 30)
            let inWindow = view.convert(point, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: content.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                    if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let loaded = host.diagnostics.loaded && host.diagnostics.rendered
        let ok: Bool
        if widget.0 == "gate/timer-bridge" {
            ok = bridged == 0
        } else {
            ok = bridged <= clicks && (bridged >= 1 || !loaded)
        }
        if !ok { failures += 1 }
        print("crashstress: gate \(ok ? "ok" : "FAIL") \(widget.0) \(prepared ? "prepared" : "direct") clicks=\(clicks) bridge=\(bridged) loaded=\(host.diagnostics.loaded) rendered=\(host.diagnostics.rendered) dead=\(host.diagnostics.dead ?? "-")")
        if round % 3 == 2 {
            host.destroy()
            host.view.removeFromSuperview()
        } else {
            host.view.removeFromSuperview()
            host.destroy()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return failures
}

func runClickFuzz(_ args: [String], option: (String) -> String?) {
    let seconds = Double(option("--seconds") ?? "20") ?? 20
    let width = CGFloat(Double(option("--width") ?? "440") ?? 440)
    let seed = UInt64(option("--seed") ?? "1") ?? 1
    var rng = SplitMix(seed: seed)
    let colorSpaceEvery = Int(option("--colorspace-every") ?? "0") ?? 0
    let files = args.dropFirst(2).filter { !$0.hasPrefix("--") && $0.hasSuffix(".html") }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    window.ignoresMouseEvents = true
    window.level = .floating
    window.alphaValue = 0.02
    window.orderFrontRegardless()
    var failures = 0
    var expectedKills = 0
    for file in files {
        guard let html = try? String(contentsOfFile: file) else { print("clickfuzz: missing \(file)"); continue }
        var lite: LiteHTMLWidgetRenderer?
        var errors: [String] = []
        let host = try! WidgetHost(html: html, theme: "light", width: width, options: labOptions(), rendererFactory: { _, theme, _ in
            let made = LiteHTMLWidgetRenderer(theme: theme, width: width)
            lite = made
            return made
        })
        host.onError = { errors.append($0) }
        var bridged = 0
        host.onBridge = { _, _ in bridged += 1 }
        host.view.frame = NSRect(x: 0, y: 0, width: width, height: 300)
        window.contentView?.addSubview(host.view)
        let end = CACurrentMediaTime() + seconds
        var clicks = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        while CACurrentMediaTime() < end, host.diagnostics.dead == nil {
            host.view.frame.size.height = max(24, min(900, host.diagnostics.height))
            if let view = lite?.view {
                let point = NSPoint(x: CGFloat(rng.next() % UInt64(max(1, Int(view.bounds.width)))), y: CGFloat(rng.next() % UInt64(max(1, Int(view.bounds.height)))))
                let inWindow = view.convert(point, to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                    if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
                }
                clicks += 1
                if colorSpaceEvery > 0, clicks % colorSpaceEvery == 0 {
                    window.colorSpace = [NSColorSpace.displayP3, .sRGB, .genericRGB, .extendedSRGB][(clicks / colorSpaceEvery) % 4]
                    NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
                    NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(Double(rng.next() % 120) / 1000))
        }
        let d = host.diagnostics
        let engineError = errors.contains { $0.contains("Aborted") || $0.contains("out of bounds") || $0.lowercased().contains("assert") || $0.contains("InternalError") }
        let limitKill = d.dead.map { $0.hasPrefix("CPU limit exceeded") || $0.hasPrefix("Memory limit exceeded") || $0.hasPrefix("CPU quota:") } ?? false
        let bad = engineError || (d.dead != nil && !limitKill)
        if bad { failures += 1 }
        if limitKill && !bad { expectedKills += 1 }
        let verdict = bad ? "FAIL" : limitKill ? "killed-as-expected" : "ok"
        let tail = d.logs.suffix(3).map { "\($0.level): \($0.text.prefix(160))" }.joined(separator: " | ")
        print("clickfuzz: \(verdict) \(URL(fileURLWithPath: file).lastPathComponent) clicks=\(clicks) bridge=\(bridged) dead=\(d.dead ?? "-") errors=\(errors.count) \(errors.prefix(2).map { String($0.prefix(200)) }) logs=[\(tail)]")
        host.view.removeFromSuperview()
        host.destroy()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
    print("clickfuzz: done failures=\(failures) killed-as-expected=\(expectedKills)")
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private final class ReproDelegate: SandboxEngineDelegate {
    var died: String?
    var loaded = false
    var errors: [String] = []
    func engine(_ engine: SandboxEngine, ops json: String) {}
    func engine(_ engine: SandboxEngine, ops json: String, canvas: [Int: WidgetCanvasBatch]) {}
    func engine(_ engine: SandboxEngine, query json: String) -> (json: String, binary: Data?) { ("{}", nil) }
    func engine(_ engine: SandboxEngine, listen json: String) {}
    func engine(_ engine: SandboxEngine, preventDefault json: String) {}
    func engineRequestsFrame(_ engine: SandboxEngine) {}
    func engine(_ engine: SandboxEngine, log level: String, text: String) { if level == "error" { errors.append(text) } }
    func engine(_ engine: SandboxEngine, diag kind: String, detail: String) {}
    func engine(_ engine: SandboxEngine, bridge method: String, argsJson: String) {}
    func engineLoaded(_ engine: SandboxEngine) { loaded = true }
    func engine(_ engine: SandboxEngine, stats: SandboxStats) {}
    func engine(_ engine: SandboxEngine, died reason: String) { died = reason }
    func engine(_ engine: SandboxEngine, anim json: String) {}
    var batches = 0
    func engine(_ engine: SandboxEngine, binaryOps: BinaryOpsPayload, canvas: [Int: WidgetCanvasBatch]) { batches += 1 }
}

func runEventRepro(_ args: [String], option: (String) -> String?) {
    let html = try! String(contentsOfFile: args[2])
    let rounds = Int(option("--rounds") ?? "1") ?? 1
    let ids = (option("--ids") ?? "8,10,11,13,24").split(separator: ",").compactMap { Int($0) }
    for round in 0..<rounds {
        let engine = SandboxEngine(features: LabSandbox.features)
        let delegate = ReproDelegate()
        engine.delegate = delegate
        var config = SandboxConfig(innerWidth: 440, innerHeight: 300, devicePixelRatio: 2, theme: "light")
        config.features = LabSandbox.features
        config.policy = .strict
        engine.start(html: html, config: config)
        let deadline = Date().addingTimeInterval(5)
        while !delegate.loaded && delegate.died == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        for _ in 0..<(Int(option("--repeat") ?? "1") ?? 1) {
            for id in ids {
                for type in ["pointerdown", "pointerup", "click"] {
                    engine.event(json: "{\"type\":\"\(type)\",\"targetId\":\(id)}")
                    if args.contains("--gc") { engine.collectGarbage() }
                }
            }
            if args.contains("--gc") { engine.collectGarbage() }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(Double(option("--wait") ?? "1") ?? 1))
        print("eventrepro round=\(round) batches=\(delegate.batches) loaded=\(delegate.loaded) died=\(delegate.died ?? "-") errors=\(delegate.errors.prefix(3))")
        engine.terminate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}

func runGateAttack(_ args: [String], option: (String) -> String?) {
    let files = args.dropFirst(2).filter { $0.hasSuffix(".html") }
    let clicks = Int(option("--clicks") ?? "1") ?? 1
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
    window.ignoresMouseEvents = true
    window.level = .floating
    window.orderFrontRegardless()
    var failures = 0
    for file in files {
        guard let html = try? String(contentsOfFile: file) else { continue }
        var lite: LiteHTMLWidgetRenderer?
        let host = try! WidgetHost(html: html, theme: "light", width: 420, options: labOptions(), rendererFactory: { _, theme, width in
            let r = LiteHTMLWidgetRenderer(theme: theme, width: width)
            lite = r
            return r
        })
        var calls: [String] = []
        host.onBridge = { method, argsJson in calls.append(method + argsJson) }
        host.view.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        window.contentView?.addSubview(host.view)
        host.setVisible(true)
        let ready = Date().addingTimeInterval(8)
        while !(host.diagnostics.loaded && host.diagnostics.rendered) && Date() < ready { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        guard let view = lite?.view else { continue }
        func send(_ type: NSEvent.EventType, _ point: NSPoint) {
            let inWindow = view.convert(point, to: nil)
            guard let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { return }
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseUp: view.mouseUp(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseMoved(with: event)
            }
        }
        let point = NSPoint(x: 60, y: view.isFlipped ? 40 : view.bounds.height - 40)
        let quietEnd = Date().addingTimeInterval(3)
        var k = 0
        while Date() < quietEnd {
            k += 1
            send(.mouseMoved, NSPoint(x: point.x + CGFloat(k % 30), y: point.y))
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        let quiet = calls
        calls.removeAll()
        let drag = file.contains("drag")
        for _ in 0..<clicks {
            send(.leftMouseDown, point)
            if drag {
                for step in 1...10 {
                    send(.leftMouseDragged, NSPoint(x: point.x + CGFloat(step * 25), y: point.y + CGFloat(step * (view.isFlipped ? 15 : -15))))
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                }
                send(.leftMouseUp, NSPoint(x: point.x + 250, y: point.y + (view.isFlipped ? 150 : -150)))
            } else {
                send(.leftMouseUp, point)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        let afterClick = calls
        let ok = quiet.isEmpty && afterClick.count <= clicks
        if !ok { failures += 1 }
        let d = host.diagnostics
        print("gateattack: \(ok ? "ok" : "BYPASS") \(URL(fileURLWithPath: file).lastPathComponent) quiet=\(quiet.count) \(quiet.prefix(3)) afterClicks(\(clicks))=\(afterClick.count) \(afterClick.prefix(4)) blocked=\(d.diags["activation-blocked"]?.count ?? 0) nav-blocked=\(d.diags["navigation-blocked"]?.count ?? 0) other=\(d.diags.keys.filter { $0 != "boot" && $0 != "activation-blocked" }.sorted()) dead=\(d.dead ?? "-")")
        host.view.removeFromSuperview()
        host.destroy()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
    print("gateattack: done bypasses=\(failures)")
}

private func attackLayerCount(_ layer: CALayer) -> Int {
    CATransaction.lock()
    defer { CATransaction.unlock() }
    var count = 0
    var stack = [layer]
    while let next = stack.popLast() {
        count += 1
        stack.append(contentsOf: next.sublayers ?? [])
    }
    return count
}

private func attackCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

func runResourceAttack(_ args: [String], option: (String) -> String?) {
    let files = args.dropFirst(2).filter { $0.hasSuffix(".html") }
    let seconds = Double(option("--seconds") ?? "6") ?? 6
    let storm = args.contains("--screen-storm")
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
    window.ignoresMouseEvents = true
    window.level = .floating
    window.orderFrontRegardless()
    for file in files {
        guard let html = try? String(contentsOfFile: file) else { continue }
        var lite: LiteHTMLWidgetRenderer?
        let host = try! WidgetHost(html: html, theme: "light", width: 420, options: labOptions(), rendererFactory: { _, theme, width in
            let r = LiteHTMLWidgetRenderer(theme: theme, width: width)
            lite = r
            return r
        })
        host.view.frame = NSRect(x: 0, y: 0, width: 420, height: 650)
        window.contentView?.addSubview(host.view)
        host.setVisible(true)
        let ready = Date().addingTimeInterval(8)
        while !(host.diagnostics.loaded && host.diagnostics.rendered) && Date() < ready { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        let cpu0 = attackCPUSeconds(), t0 = CACurrentMediaTime()
        var maxLayers = 0
        var storms = 0
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if storm {
                for _ in 0..<10 {
                    window.colorSpace = storms % 2 == 0 ? .displayP3 : .sRGB
                    NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
                    NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
                    storms += 1
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            maxLayers = max(maxLayers, attackLayerCount(host.view.layer ?? CALayer()))
        }
        let cpu = (attackCPUSeconds() - cpu0) / (CACurrentMediaTime() - t0) * 100
        let layersEnd = attackLayerCount(host.view.layer ?? CALayer())
        let d = host.diagnostics
        var report = ""
        if let lite = lite {
            let done = DispatchSemaphore(value: 0)
            host.executor.async { report = lite.shimmerCheckReport; done.signal() }
            while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }
        print(String(format: "resattack: %@ cpu=%.0f%% layers max=%d end=%d storms=%d dead=%@ diags=%@ | %@", URL(fileURLWithPath: file).lastPathComponent, cpu, maxLayers, layersEnd, storms, d.dead ?? "-", d.diags.map { "\($0.key)=\($0.value.count)" }.sorted().joined(separator: ","), report))
        host.view.removeFromSuperview()
        host.destroy()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
    print(String(format: "resattack: done footprint=%.0fMB", Double(ProcessSample.now().footprint) / 1048576))
}
