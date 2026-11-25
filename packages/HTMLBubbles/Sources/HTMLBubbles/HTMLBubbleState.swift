import Cocoa
import TGUIKit
import LiteHTML
import HTMLScript
import HTML3D
import WidgetSandbox
import Twidget3DSandbox
import TwidgetIcons
import SwiftSignalKit
import TwidgetRenderer
import Localization

public protocol HTMLBubbleVisibility: AnyObject {
    var isHTMLBubbleVisible: Bool { get }
}

struct HTMLBubbleSummary {
    let plainText: String
    let isWidget: Bool

    init(_ html: String) {
        plainText = HTMLBubbleState.plainText(from: html)
        isWidget = HTMLBubbleState.isWidget(html)
    }
}

public enum HTMLWidgetAction {
    case openLink(URL)
    case openTelegramLink(URL)
}

public final class HTMLBubbleState: NSObject, HTMLScriptHost {
    public var source: String {
        lock.lock()
        defer { lock.unlock() }
        return currentSource
    }
    private var currentSource: String
    public let outgoing: Bool
    public let isWidget: Bool
    public let plainText: String
    public let conversationId: String?
    public let engine: HTMLRenderEngine
    public let selfContained: Bool
    let renderStats = HTMLRenderStats()

    public var linkHandler: ((HTMLBubbleState, String) -> Void)?
    public var widgetRequestHandler: ((WidgetRequest, @escaping (Result<WidgetRequestAnswer, WidgetRequestFailure>) -> Void) -> Void)?
    public var widgetWalletHandler: ((WalletCall, @escaping (Result<WidgetRequestAnswer, WidgetRequestFailure>) -> Void) -> Void)?
    public var widgetCopyHandler: ((String) -> Void)?
    var widgetWatchHandler: (() -> Void)?
    var widgetVisible = false
    var widgetPreview = false
    var widgetPreviewLocale = "en-US"
    private var currentWidgetData = WidgetData()
    var widgetData: WidgetData {
        lock.lock()
        defer { lock.unlock() }
        return currentWidgetData
    }

    func updateWidgetData(_ data: WidgetData) {
        lock.lock()
        currentWidgetData = data
        let prepared = twidgetPrepared?.value.host
        lock.unlock()
        let update = { [weak self] in
            prepared?.setData(data)
            self?.twidgetHost?.setData(data)
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    public var widgetActionHandler: ((HTMLBubbleState, HTMLWidgetAction) -> Void)?
    public var heightHint: CGFloat = 0
    public internal(set) var fixedHeight: CGFloat?
    public internal(set) var isWidgetMessage = false
    private var attachedWidgetContext: HTMLWidgetContext?
    private var widgetStorageGeneration = 0
    private var liveHostDied = false
    private weak var deadHost: WidgetHost?
    static var stoppedLabel: String {
        return strings().htmlBubbleStateWidgetStopped
    }
    private var bubbleStorageGeneration = 0
    public var showsStats: Bool = true
    public weak var visibility: HTMLBubbleVisibility?

    private let lock = NSLock()
    private var keys: [String]
    private var body: String
    private var version: Int = 0
    private var transitionVersion: Int = -1
    private var transitionKind: String?
    private var document: (key: String, value: LHDocument)?
    let mayHavePins: Bool
    private var resolvedWidths: [Int: CGFloat] = [:]
    private var twidgetBubble: WidgetBubble?
    private var twidgetRenderer: LiteHTMLWidgetRenderer? {
        didSet { wireTwidgetSelection() }
    }

    public var twidgetSelectedText: String? {
        return twidgetRenderer?.selectedText
    }

    public var twidgetSelectionChanged: ((Bool) -> Void)? {
        didSet { wireTwidgetSelection() }
    }

    public var twidgetSelectionColor: NSColor? {
        didSet { wireTwidgetSelection() }
    }

    public func clearTwidgetSelection() {
        twidgetRenderer?.clearTextSelection()
    }

    private func wireTwidgetSelection() {
        guard let renderer = twidgetRenderer else {
            return
        }
        let apply = { [weak self, weak renderer] in
            guard let self = self, let renderer = renderer else {
                return
            }
            renderer.onTextSelectionChange = { [weak self] selected in
                self?.twidgetSelectionChanged?(selected)
            }
            if let color = self.twidgetSelectionColor {
                renderer.textSelectionColor = color
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
    private var twidgetRendererExecutor: WidgetExecutor?
    private struct TwidgetLayout {
        let height: CGFloat
        let resizeAnchor: WidgetResizeAnchor
    }
    private var twidgetLayout = TwidgetLayout(height: 0, resizeAnchor: .top)
    private var twidgetLayouts: [String: TwidgetLayout] = [:]
    private var twidgetPrepared: (key: String, value: WidgetPrepared)?
    private var twidgetLiveKey: String?
    private var twidgetHasHost = false
    private var twidgetMeasured: [() -> Void] = []
    var twidgetHostChanged: (() -> Void)?
    weak var twidgetHostChangedOwner: AnyObject?
    private let twidgetTimeout = MetaDisposable()

    private var script: HTMLScript?
    let gpuPool = HTMLBubbleGPUPool()
    private var started = false
    private var observers: [Int: () -> Void] = [:]
    private var nextObserver = 0

    private static let widgetWarmup: Void = {
        _ = HTMLBubbleState.sandboxLibraries
        WidgetWarmup.prewarm(renderers: 0, engines: 1, validators: 1)
        WidgetRendererWarmup.prewarm(scale: Thread.isMainThread ? (NSScreen.main?.backingScaleFactor ?? 2) : 2)
    }()

    static func prewarmLibraries() {
        _ = HTMLBubbleState.sandboxLibraries
    }

    private static let registeredSchemes: Void = {
        LHSanitizer.setLinkSchemes(["https", "chat"], imageSchemes: ["sf", "app"])
    }()

    public convenience init(html: String, outgoing: Bool, activeKeys: [String] = [], conversationId: String? = nil, engine: HTMLRenderEngine = .twidget, selfContained: Bool = false) {
        self.init(html: html, outgoing: outgoing, activeKeys: activeKeys, conversationId: conversationId, engine: engine, selfContained: selfContained, summary: nil)
    }

    init(html: String, outgoing: Bool, activeKeys: [String], conversationId: String?, engine: HTMLRenderEngine, selfContained: Bool, summary: HTMLBubbleSummary?) {
        _ = HTMLBubbleState.registeredSchemes
        _ = HTMLBubbleState.sandboxLibraries
        self.currentSource = html
        self.engine = engine
        self.selfContained = selfContained
        self.outgoing = outgoing
        let summary = summary ?? HTMLBubbleSummary(html)
        self.isWidget = summary.isWidget
        self.keys = activeKeys
        self.body = html
        self.conversationId = conversationId
        self.plainText = summary.plainText
        self.mayHavePins = HTMLBubbleState.containsASCII(html, "data-pin")
        _ = HTMLBubbleState.registerLibraries
        self.script = engine.usesWidgetSandbox ? nil : HTMLScript.make(html: html)
        super.init()
    }

    deinit {
        if let widgetWatchHandler {
            DispatchQueue.main.async(execute: widgetWatchHandler)
        }
        twidgetTimeout.dispose()
        if let context = attachedWidgetContext {
            HTMLWidgetStorage.shared.flush(context)
        }
        let bubble = twidgetBubble
        let prepared = twidgetPrepared?.value
        if bubble != nil || prepared != nil {
            let release = {
                prepared?.discard()
                _ = bubble
            }
            if Thread.isMainThread {
                release()
            } else {
                DispatchQueue.main.async(execute: release)
            }
        }
    }

    private static let registerLibraries: Void = {
        HTML3DSession.threeSource = { HTMLBubbleLibraries.source(named: "three") }
        HTML3DSession.register()
    }()

    public func attachWidget(_ context: HTMLWidgetContext) {
        lock.lock()
        if attachedWidgetContext == nil {
            attachedWidgetContext = context
        }
        lock.unlock()
    }

    var widgetContext: HTMLWidgetContext? {
        lock.lock()
        defer { lock.unlock() }
        return attachedWidgetContext
    }

    public var statsReservedHeight: CGFloat {
        return HTMLBubbleStatsOverlay.reservedHeight(self)
    }

    public var isScripted: Bool {
        return script != nil
    }

    public var scene3D: HTML3DSession? {
        return script?.scene3D
    }

    public func performInput(_ type: String, _ a: Any, _ b: Double) {
        let value: HTMLScriptValue
        switch a {
        case let flag as Bool:
            value = .bool(flag)
        case let number as Double:
            value = .number(number)
        case let number as Int:
            value = .number(Double(number))
        case let number as CGFloat:
            value = .number(Double(number))
        case let text as String:
            value = .string(text)
        default:
            value = .undefined
        }
        script?.performInput(type, value, b)
    }

    public var contentVersion: Int {
        lock.lock()
        defer { lock.unlock() }
        return version
    }

    public var activeKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return keys
    }

    public func start() {
        assert(Thread.isMainThread)
        guard let script = script, !started else {
            return
        }
        started = true
        script.host = self
        script.setVisible(visibility?.isHTMLBubbleVisible ?? false)
        update(body: script.currentHTML)
    }

    public func restartScript() {
        assert(Thread.isMainThread)
        guard script != nil else {
            return
        }
        script = HTMLScript.make(html: source)
        started = false
        start()
        notify()
    }

    public func visibilityChanged() {
        script?.setVisible(visibility?.isHTMLBubbleVisible ?? false)
    }

    public func document(for appearance: HTMLBubbleAppearance) -> LHDocument {
        return versionedDocument(for: appearance).document
    }

    public func versionedDocument(for appearance: HTMLBubbleAppearance) -> (version: Int, document: LHDocument) {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(version)|\(appearance.key)"
        if let document = document, document.key == key {
            return (version, document.value)
        }
        let html = wrap(body, appearance: appearance)
        let value: LHDocument
        if engine == .litehtml || engine == .litehtmlGPU, script != nil {
            value = LHDocument(html: html, css: appearance.css, previous: document?.value)
        } else {
            value = LHDocument(html: html, css: appearance.css)
        }
        if engine == .litehtmlBefore {
            value.clipCulling = false
        }
        value.anchorHandler = { [weak self] url in
            self?.handleAnchor(url)
        }
        value.actionHandler = { [weak self] action, value in
            self?.script?.performAction(action, value: value)
        }
        document = (key, value)
        return (version, value)
    }

    public func layout(width: CGFloat, appearance: HTMLBubbleAppearance) -> NSSize {
        if engine.usesWidgetSandbox {
            return twidgetSize(width: width)
        }
        return resolveLayout(document(for: appearance), width: width)
    }

    public func resolveLayout(_ document: LHDocument, width: CGFloat) -> NSSize {
        lock.lock()
        let hint = resolvedWidths[Int(width)] ?? 0
        lock.unlock()
        let size = document.layout(maxWidth: width, preferredWidth: hint)
        lock.lock()
        resolvedWidths[Int(width)] = min(size.width, width)
        lock.unlock()
        return size
    }

    func twidgetSize(width: CGFloat) -> NSSize {
        lock.lock()
        defer { lock.unlock() }
        let measured = cachedTwidgetLayout(width: width)?.height
        let fallback = twidgetLayout.height > 0 ? twidgetLayout.height : max(heightHint, engine == .webKit ? 320 : 0)
        if isWidgetMessage {
            return NSSize(width: width, height: fixedHeight ?? HTMLWidgetPayload.clampedHeight(measured ?? fallback))
        }
        return NSSize(width: width, height: max(measured ?? fallback, 60))
    }

    private func cachedTwidgetLayout(width: CGFloat) -> TwidgetLayout? {
        let prefix = "\(Int(width))|"
        if let key = twidgetLiveKey, key.hasPrefix(prefix), let layout = twidgetLayouts[key] {
            return layout
        }
        return twidgetLayouts.first { $0.key.hasPrefix(prefix) }?.value
    }

    func needsTwidgetPrepare(width: CGFloat) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !twidgetHasHost && twidgetPrepared == nil && !twidgetLayouts.keys.contains { $0.hasPrefix("\(Int(width))|") }
    }

    func knowsTwidgetHeight(width: CGFloat) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return twidgetLayouts.keys.contains { $0.hasPrefix("\(Int(width))|") }
    }

    private static func twidgetKey(width: CGFloat, theme: String) -> String {
        return "\(Int(width))|\(theme)"
    }

    private static let twidgetShells: Void = {
        _ = HTMLBubbleMenus.installed
        WidgetShellPool.shared.factory = { width in
            let renderer = LiteHTMLWidgetRenderer(theme: "light", width: width, selectsTextByDefault: true)
            renderer.preparesOffscreen = true
            return renderer
        }
    }()

    private func twidgetHTML(appearance: HTMLBubbleAppearance) -> String {
        if selfContained {
            return source
        }
        lock.lock()
        defer { lock.unlock() }
        return "<style>\(appearance.css)</style>" + wrap(currentSource, appearance: appearance)
    }

    private static let sandboxFeatures: Set<String> = ["binaryOps", "canvasWords", "webAnimations", "morphUpdates"]

    private static let sandboxLibraries: Void = {
        _ = Twidget3DLibrary.provideThree()
        if Thread.isMainThread {
            EnginePool.shared.features = sandboxFeatures
        } else {
            DispatchQueue.main.async {
                EnginePool.shared.features = sandboxFeatures
            }
        }
    }()

    private func twidgetOptions() -> WidgetHost.Options {
        _ = HTMLBubbleState.sandboxLibraries
        var options = WidgetHost.Options()
        if let context = widgetContext {
            options.locale = context.locale
            options.context = context.runtime
            options.storage = HTMLWidgetStorage.shared.storage(for: context)
        }
        options.context.preview = widgetPreview
        if widgetPreview {
            options.locale = widgetPreviewLocale
        }
        options.data = widgetData
        options.maximumHeight = isWidgetMessage ? fixedHeight ?? HTMLWidgetPayload.maximumHeight : 16_384
        options.asyncValidation = true
        options.sharedValidatorThread = true
        options.startBeforeRendererReady = true
        options.pools = true
        options.features = HTMLBubbleState.sandboxFeatures
        options.policy = .strict
        options.nativeScrolling = engine == .twidget
        if !isWidgetMessage {
            options.assetResolver = TwidgetIcons.resolver
            options.sideChannels = [{ Twidget3DBackend.channel() }]
        }
        return options
    }

    public static let backgroundPrepare = UserDefaults.standard.object(forKey: "HTMLBubbles.backgroundPrepare") as? Bool ?? true

    private func onTwidgetRenderer(_ body: @escaping (LiteHTMLWidgetRenderer) -> Void) {
        guard let renderer = twidgetRenderer else {
            return
        }
        guard let executor = twidgetRendererExecutor ?? twidgetBubble?.host?.executor, !executor.isCurrent else {
            body(renderer)
            return
        }
        executor.async {
            body(renderer)
        }
    }

    /// Boots the widget off the main thread (any thread but main), runs its load-time script and lays it out,
    /// waiting up to `wait` for the exact height. The bubble adopts the prepared host when it goes live.
    @discardableResult
    public func prepareTwidget(appearance: HTMLBubbleAppearance, width: CGFloat, wait: TimeInterval) -> Bool {
        guard HTMLBubbleState.backgroundPrepare, engine == .twidget, width > 0 else {
            return false
        }
        if Thread.isMainThread {
            if needsTwidgetPrepare(width: width) {
                TwidgetDeferredPrepare.enqueue(self, appearance: appearance, width: width)
            }
            return false
        }
        let theme = appearance.dark ? "dark" : "light"
        let key = HTMLBubbleState.twidgetKey(width: width, theme: theme)
        lock.lock()
        let known = twidgetLayouts[key] != nil
        let running = twidgetPrepared?.key == key ? twidgetPrepared?.value : nil
        let live = twidgetHasHost
        lock.unlock()
        if known || live {
            return true
        }
        let budget = TwidgetPrepareBudget.take(wait)
        let started = CACurrentMediaTime()
        let prepared: WidgetPrepared
        if let running = running {
            prepared = running
        } else if budget <= 0 {
            TwidgetDeferredPrepare.enqueue(self, appearance: appearance, width: width)
            return false
        } else if let made = startTwidgetPrepare(appearance: appearance, width: width) {
            prepared = made
        } else {
            TwidgetPrepareBudget.spent(CACurrentMediaTime() - started)
            TwidgetDeferredPrepare.enqueue(self, appearance: appearance, width: width)
            return false
        }
        let ready = prepared.wait(timeout: max(0, budget - (CACurrentMediaTime() - started)))
        TwidgetPrepareBudget.spent(CACurrentMediaTime() - started)
        if ready {
            recordPrepared(prepared, key: key)
        }
        return ready
    }

    @discardableResult
    func startTwidgetPrepare(appearance: HTMLBubbleAppearance, width: CGFloat) -> WidgetPrepared? {
        guard engine == .twidget, !widgetStopped else { return nil }
        let theme = appearance.dark ? "dark" : "light"
        let key = HTMLBubbleState.twidgetKey(width: width, theme: theme)
        lock.lock()
        let known = twidgetLayouts[key] != nil
        let running = twidgetPrepared?.key == key ? twidgetPrepared?.value : nil
        let live = twidgetHasHost
        lock.unlock()
        if known || live {
            return nil
        }
        if let running = running {
            return running
        }
        _ = HTMLBubbleState.twidgetShells
        guard let made = WidgetPreparer.prepare(html: twidgetHTML(appearance: appearance), theme: appearance.widgetTheme, width: width, options: twidgetOptions()) else {
            WidgetShellPool.shared.prewarm(width: width)
            return nil
        }
        observeStorageCommits(made.host)
        made.onReady = { [weak self] prepared in
            self?.twidgetPrepareReady(prepared, key: key)
        }
        lock.lock()
        let previous = twidgetPrepared
        twidgetPrepared = (key, made)
        lock.unlock()
        if let previous = previous, previous.value !== made {
            previous.value.discard()
        }
        return made
    }

    private func recordPrepared(_ prepared: WidgetPrepared, key: String) {
        let height = prepared.height
        guard height > 0 else {
            return
        }
        lock.lock()
        let layout = TwidgetLayout(height: height, resizeAnchor: prepared.host.diagnostics.resizeAnchor)
        twidgetLayouts[key] = layout
        if twidgetLayout.height == 0 {
            twidgetLayout = layout
        }
        lock.unlock()
    }

    private func twidgetPrepareReady(_ prepared: WidgetPrepared, key: String) {
        lock.lock()
        let had = twidgetLayouts[key]
        lock.unlock()
        recordPrepared(prepared, key: key)
        if had == nil, prepared.height > 0 {
            notify()
        }
    }

    private func takePreparedHost(width: CGFloat, theme: String) -> WidgetHost? {
        let key = HTMLBubbleState.twidgetKey(width: width, theme: theme)
        lock.lock()
        let prepared = twidgetPrepared
        twidgetPrepared = nil
        lock.unlock()
        guard let prepared = prepared else {
            return nil
        }
        guard prepared.key == key, let host = prepared.value.adopt() else {
            prepared.value.discard()
            return nil
        }
        WidgetPreparer.adopted(prepared.value)
        return host
    }

    var twidgetHost: WidgetHost? {
        return twidgetBubble?.host
    }

    #if DEBUG
    public func debugTwidgetFrameState(completion: @escaping (String) -> Void) {
        guard twidgetRenderer != nil else {
            completion("no renderer")
            return
        }
        onTwidgetRenderer { renderer in
            let value = "\(renderer.tileDebug) ticks=\(renderer.ticks) posted=\(renderer.framesPosted) \(renderer.canvasReport)"
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    public func debugTwidgetClick(attributes: [String: String], completion: @escaping (Bool) -> Void) {
        guard twidgetRenderer != nil else {
            completion(false)
            return
        }
        onTwidgetRenderer { renderer in
            let send = renderer.onMessage
            renderer.onMessage = { message in
                send?(HTMLBubbleState.debugPointerClickMessage(message))
            }
            let found = renderer.debugClick(attributes: attributes)
            renderer.onMessage = send
            DispatchQueue.main.async {
                completion(found)
            }
        }
    }

    static func debugPointerClickMessage(_ message: String) -> String {
        guard var object = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any], object["type"] as? String == "event", object["trusted"] as? Bool == true, var event = object["ev"] as? [String: Any], event["type"] as? String == "click" else {
            return message
        }
        event["detail"] = 1
        object["ev"] = event
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return message
        }
        return String(decoding: data, as: UTF8.self)
    }

    public var debugTwidgetSummary: String {
        guard let diagnostics = twidgetBubble?.host?.diagnostics else {
            return twidgetBubble == nil ? "nobubble" : "nohost"
        }
        let errors = diagnostics.logs.filter { $0.level == "error" }.map { $0.text }
        return "loaded=\(diagnostics.loaded) rendered=\(diagnostics.rendered) dead=\(diagnostics.dead ?? "-") lastError=\(diagnostics.lastError ?? "-") height=\(Int(diagnostics.height)) nodes=\(diagnostics.nodes) diags=\(diagnostics.diags.map { "\($0.key):\($0.value.count)" }.sorted().joined(separator: ",")) errors=\(errors.prefix(2).joined(separator: " | "))"
    }

    #endif

    func twidgetBubble(appearance: HTMLBubbleAppearance, width: CGFloat) -> WidgetBubble {
        assert(Thread.isMainThread)
        let theme = appearance.dark ? "dark" : "light"
        if let bubble = twidgetBubble {
            bubble.setTheme(appearance.widgetTheme)
            return bubble
        }
        let html: String
        if selfContained {
            html = source
        } else {
            lock.lock()
            html = "<style>\(appearance.css)</style>" + wrap(currentSource, appearance: appearance)
            lock.unlock()
        }
        _ = HTMLBubbleState.widgetWarmup
        _ = HTMLBubbleMenus.installed
        var options = twidgetOptions()
        if engine == .webKit {
            options.sharedWebKit = true
            options.recyclesRenderers = true
            RendererPool.shared.width = width
            RendererPool.shared.theme = theme
            RendererPool.shared.targetSize = 2
        }
        var made: ((LiteHTMLWidgetRenderer) -> Void)?
        let factory: RendererFactory? = engine == .webKit ? nil : { _, theme, width in
            let renderer = LiteHTMLWidgetRenderer(theme: theme, width: width, selectsTextByDefault: true)
            made?(renderer)
            return renderer
        }
        let bubble = WidgetBubble(html: html, theme: appearance.widgetTheme, width: width, options: options, feed: HTMLTwidgetTableSpace.feed(for: engine), rendererFactory: factory)
        made = { [weak self, weak bubble] renderer in
            self?.twidgetRenderer = renderer
            self?.twidgetRendererExecutor = nil
            renderer.preparesOffscreen = bubble?.isPrepared ?? false
        }
        bubble.holdsHeightOnRebuild = true
        bubble.onPrepareChange = { [weak self] prepared in
            self?.onTwidgetRenderer { $0.preparesOffscreen = prepared }
        }
        bubble.preparedHost = { [weak self, weak bubble] in
            guard let self = self, self.engine == .twidget, let host = self.takePreparedHost(width: width, theme: theme) ?? self.freshWidgetHost(bubble) else {
                return nil
            }
            if let renderer = host.rendererObject as? LiteHTMLWidgetRenderer {
                self.twidgetRenderer = renderer
                self.twidgetRendererExecutor = host.executor
                let prepared = bubble?.isPrepared ?? false
                host.executor.async {
                    renderer.preparesOffscreen = prepared
                }
            }
            return host
        }
        if widgetStopped {
            bubble.slot.create = { false }
        }
        bubble.configure = { [weak self, weak bubble] host in
            host.stoppedLabel = HTMLBubbleState.stoppedLabel
            if self?.followsWidgetResizeAnchor == true, let renderer = host.rendererObject as? LiteHTMLWidgetRenderer {
                host.executor.async { [weak host, weak renderer] in
                    guard let host = host, let renderer = renderer else {
                        return
                    }
                    renderer.resizeAnchor = host.diagnostics.resizeAnchor
                    let onChange = host.onChangeOnExecutor
                    host.onChangeOnExecutor = { [weak renderer] diagnostics in
                        renderer?.resizeAnchor = diagnostics.resizeAnchor
                        onChange?(diagnostics)
                    }
                }
            }
            let onChange = host.onChange
            host.onChange = { [weak self, weak host, weak bubble] diagnostics in
                onChange?(diagnostics)
                if diagnostics.rendered, let bubble = bubble {
                    self?.twidgetChanged(height: bubble.height, resizeAnchor: bubble.resizeAnchor)
                }
                if diagnostics.dead != nil, let host = host {
                    self?.widgetDied(host)
                }
            }
            host.onAction = { [weak self] action in
                self?.twidgetAction(action)
            }
            host.onRequest = { [weak self] request, complete in
                guard let handler = self?.widgetRequestHandler else { complete(.failure(.notAllowed)); return }
                handler(request, complete)
            }
            host.onWallet = { [weak self] call, complete in
                guard let handler = self?.widgetWalletHandler else { complete(.failure(.notAllowed)); return }
                handler(call, complete)
            }
            host.onCopyText = { [weak self] text in self?.widgetCopyHandler?(text) }
            host.onWatchPublicData = { [weak self] _ in self?.widgetWatchHandler?() }
            host.setData(self?.widgetData ?? WidgetData())
            self?.observeStorageCommits(host)
        }
        bubble.onHostChange = { [weak self, weak bubble] in
            guard let self = self else {
                return
            }
            let hasHost = bubble?.host != nil
            self.lock.lock()
            self.twidgetHasHost = hasHost
            self.lock.unlock()
            if let host = bubble?.host {
                self.twidgetRendererExecutor = host.executor
                self.liveHostDied = false
            } else {
                self.twidgetRenderer = nil
                self.twidgetRendererExecutor = nil
                self.flushWidgetStorage()
                if !self.liveHostDied, let key = self.widgetCrashKey {
                    HTMLWidgetStore.resetCrashes(key)
                }
            }
            self.widgetWatchHandler?()
            self.twidgetHostChanged?()
        }
        bubble.onPauseChange = { [weak self] paused in
            self?.onTwidgetRenderer { $0.keepsTilesWhileHidden = paused }
        }
        bubble.onVisibilityChange = { [weak self, weak bubble] visible in
            self?.widgetVisible = visible
            self?.widgetWatchHandler?()
            if !visible {
                self?.flushWidgetStorage()
            }
            let paused = bubble?.slot.isPausedOnScreen ?? false
            self?.onTwidgetRenderer { renderer in
                renderer.keepsTilesWhileHidden = paused
                renderer.setVisible(visible)
            }
        }
        bubble.onHeightChange = { [weak self, weak bubble] in
            guard let self = self, let bubble = bubble else {
                return
            }
            self.twidgetChanged(height: bubble.height, resizeAnchor: bubble.resizeAnchor)
        }
        bubble.onContent = { [weak self] in
            self?.flushTwidgetMeasured()
        }
        bubble.captureSnapshot = { [weak self] in
            guard let view = self?.twidgetRenderer?.view else {
                return nil
            }
            return HTMLTwidgetSnapshot.capture(view)
        }
        if engine == .webKit {
            bubble.captureSnapshotAsync = { [weak bubble] completion in
                guard let host = bubble?.host else { return completion(nil) }
                host.snapshot { image in
                    completion(image.flatMap { HTMLTwidgetSnapshot.capture($0) })
                }
            }
        }
        bubble.onSnapshotChange = { [weak self] in
            self?.twidgetHostChanged?()
        }
        bubble.onHostContent = { [weak self] in
            self?.twidgetHostChanged?()
        }
        lock.lock()
        twidgetLiveKey = HTMLBubbleState.twidgetKey(width: width, theme: theme)
        lock.unlock()
        bubbleStorageGeneration = widgetStorageGeneration
        twidgetBubble = bubble
        return bubble
    }

    private var widgetCrashKey: String? {
        guard isWidgetMessage, let context = widgetContext else {
            return nil
        }
        return "\(context.basePath)|\(context.messageId)|\(source.hashValue)"
    }

    var widgetStopped: Bool {
        guard let key = widgetCrashKey else {
            return false
        }
        return HTMLWidgetStore.crashCount(key) >= HTMLWidgetStore.crashLimit
    }

    private func widgetDied(_ host: WidgetHost) {
        assert(Thread.isMainThread)
        guard deadHost !== host, twidgetBubble?.host === host else {
            return
        }
        deadHost = host
        liveHostDied = true
        guard let key = widgetCrashKey, HTMLWidgetStore.recordCrash(key) >= HTMLWidgetStore.crashLimit else {
            return
        }
        twidgetBubble?.slot.create = { false }
    }

    private func observeStorageCommits(_ host: WidgetHost) {
        let observe: () -> Void = { [weak self, weak host] in
            guard let host = host else {
                return
            }
            host.onStorageCommit = { [weak self] area, values in
                self?.widgetStorageCommitted(area, values: values)
            }
        }
        if Thread.isMainThread {
            observe()
        } else {
            DispatchQueue.main.async(execute: observe)
        }
    }

    private func widgetStorageCommitted(_ area: WidgetStorageArea, values: [String: String]) {
        assert(Thread.isMainThread)
        guard let context = widgetContext else {
            return
        }
        HTMLWidgetStorage.shared.commit(area, values: values, context: context)
        widgetStorageGeneration += 1
    }

    private func flushWidgetStorage() {
        if let context = widgetContext {
            HTMLWidgetStorage.shared.flush(context)
        }
    }

    private func freshWidgetHost(_ bubble: WidgetBubble?) -> WidgetHost? {
        guard isWidgetMessage, let bubble = bubble, bubbleStorageGeneration != widgetStorageGeneration else {
            return nil
        }
        _ = HTMLBubbleState.twidgetShells
        guard let prepared = WidgetPreparer.prepare(html: bubble.html, theme: bubble.theme, width: bubble.width, options: twidgetOptions(), tracked: false) else {
            return nil
        }
        observeStorageCommits(prepared.host)
        guard let host = prepared.adopt() else {
            return nil
        }
        bubbleStorageGeneration = widgetStorageGeneration
        return host
    }

    public func twidgetSlot(appearance: HTMLBubbleAppearance, width: CGFloat, locate: @escaping () -> CGRect?) -> WidgetFeedSlot? {
        guard engine.usesWidgetSandbox, width > 0 else {
            return nil
        }
        let slot = twidgetBubble(appearance: appearance, width: width).slot
        slot.locate = locate
        return slot
    }

    func twidgetAttachedRect(in document: NSView) -> CGRect? {
        guard let view = twidgetHostChangedOwner as? HTMLBubbleView, view.state === self, view.window != nil, view.window === document.window else {
            return nil
        }
        return view.convert(view.bounds, to: document)
    }

    var twidgetSnapshot: HTMLTwidgetSnapshot? {
        return twidgetBubble?.snapshot as? HTMLTwidgetSnapshot
    }

    func captureTwidgetSnapshot() -> HTMLTwidgetSnapshot? {
        guard let view = twidgetRenderer?.view else {
            return nil
        }
        return HTMLTwidgetSnapshot.capture(view)?.snapshot as? HTMLTwidgetSnapshot
    }

    public var canMorph: Bool {
        assert(Thread.isMainThread)
        return engine.usesWidgetSandbox && selfContained && twidgetBubble?.host != nil
    }

    public func morph(html: String, completion: @escaping (Bool) -> Void) {
        assert(Thread.isMainThread)
        guard canMorph, let bubble = twidgetBubble else {
            completion(false)
            return
        }
        bubble.morph(html: html) { [weak self] applied in
            guard let self = self, applied else {
                completion(false)
                return
            }
            self.lock.lock()
            self.currentSource = html
            self.body = html
            let prepared = self.twidgetPrepared
            self.twidgetPrepared = nil
            self.lock.unlock()
            prepared?.value.discard()
            completion(true)
        }
    }

    var twidgetReady: Bool {
        return twidgetBubble?.host != nil && twidgetBubble?.hostHasContent == true
    }

    func twidgetSnapshotShown() {
        twidgetBubble?.snapshotShown()
    }

    public func twidgetNeedsUpdate() {
        twidgetBubble?.slot.setNeedsUpdate()
    }

    func measureTwidget(appearance: HTMLBubbleAppearance, width: CGFloat, timeout: Double, completion: @escaping () -> Void) {
        assert(Thread.isMainThread)
        guard !widgetStopped, twidgetBubble(appearance: appearance, width: width).ensureHost() != nil else {
            completion()
            return
        }
        if twidgetBubble?.hasContent == true {
            completion()
            return
        }
        twidgetMeasured.append(completion)
        twidgetTimeout.set((Signal<Void, NoError>.single(Void()) |> delay(timeout, queue: Queue.mainQueue())).start(next: { [weak self] _ in
            self?.flushTwidgetMeasured()
        }))
    }

    private func twidgetAction(_ action: WidgetAction) {
        assert(Thread.isMainThread)
        guard let slot = twidgetBubble?.slot, slot.isLive, slot.isVisible, visibility?.isHTMLBubbleVisible ?? true else {
            return
        }
        let request: HTMLWidgetAction
        switch action {
        case let .openLink(url):
            request = .openLink(url)
        case let .openTelegramLink(url):
            request = .openTelegramLink(url)
        case .ready, .haptic:
            return
        }
        guard HTMLBubbleUserAction.allow(now: CACurrentMediaTime(), sinceInput: HTMLBubbleUserAction.inputAge()) else {
            return
        }
        widgetActionHandler?(self, request)
    }

    private func flushTwidgetMeasured() {
        let callbacks = twidgetMeasured
        twidgetMeasured.removeAll()
        twidgetTimeout.set(nil)
        callbacks.forEach { $0() }
    }

    var scriptMilliseconds: Double {
        return script?.totalMilliseconds ?? 0
    }

    var scriptFrames: Int {
        return script?.frameCount ?? 0
    }

    var twidgetSandboxStats: SandboxStats? {
        return twidgetBubble?.host?.diagnostics.stats
    }

    public func twidgetResize(oldHeight: CGFloat, newHeight: CGFloat) -> HTMLTwidgetResize? {
        assert(Thread.isMainThread)
        guard let diff = twidgetRenderer?.lastResizeDiff, abs(diff.oldHeight - oldHeight) <= 1, abs(diff.newHeight - newHeight) <= 1 else {
            return nil
        }
        return HTMLTwidgetResize(unchangedTop: diff.unchangedTop, unchangedBottom: diff.unchangedBottom, pointerFrom: diff.pointerFrom, pointerTo: diff.pointerTo, keepsBottom: diff.keepsBottom)
    }

    public func twidgetPrefersBottom(_ value: Bool) {
        assert(Thread.isMainThread)
        guard !followsWidgetResizeAnchor else {
            return
        }
        twidgetRenderer?.prefersBottomResize = value
    }

    private var followsWidgetResizeAnchor: Bool {
        return isWidgetMessage && !HTMLWidgetTestMode.usesPreviousBehavior
    }

    public func twidgetMessageResizeAnchor(width: CGFloat, oldHeight: CGFloat, newHeight: CGFloat) -> TableRowResizeAnchor? {
        guard followsWidgetResizeAnchor else {
            return nil
        }
        lock.lock()
        let layout = cachedTwidgetLayout(width: width) ?? twidgetLayout
        lock.unlock()
        return layout.resizeAnchor == .bottom ? .bottom(oldHeight: oldHeight, newHeight: newHeight) : .top
    }

    public var resizePacing = TableRowResizePacing()

    var twidgetRendererStats: (frames: Int, update: Double, draw: Double, composited: Int)? {
        guard let renderer = twidgetRenderer else {
            return nil
        }
        return (renderer.layoutCount, renderer.layoutMilliseconds, renderer.drawMilliseconds, renderer.compositedCount)
    }

    private func twidgetChanged(height: CGFloat, resizeAnchor: WidgetResizeAnchor) {
        lock.lock()
        let changed = height > 0 && abs(height - twidgetLayout.height) > 0.5
        if height > 0 {
            let layout = TwidgetLayout(height: height, resizeAnchor: resizeAnchor)
            twidgetLayout = layout
            if let key = twidgetLiveKey {
                twidgetLayouts[key] = layout
            }
        }
        lock.unlock()
        if changed {
            notify()
        }
    }

    public func renderKey(width: CGFloat, appearance: HTMLBubbleAppearance, scale: CGFloat) -> String {
        return renderKey(version: contentVersion, width: width, appearance: appearance, scale: scale)
    }

    public func renderKey(version: Int, width: CGFloat, appearance: HTMLBubbleAppearance, scale: CGFloat) -> String {
        return "\(version)|\(appearance.key)|\(Int(width))|\(scale)"
    }

    public func transition(after applied: Int, upTo rendered: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let kind = transitionKind, transitionVersion > applied, transitionVersion <= rendered else {
            return nil
        }
        return kind
    }

    public func addObserver(_ observer: @escaping () -> Void) -> Int {
        assert(Thread.isMainThread)
        nextObserver += 1
        observers[nextObserver] = observer
        return nextObserver
    }

    public func removeObserver(_ token: Int) {
        assert(Thread.isMainThread)
        observers.removeValue(forKey: token)
    }

    public func scriptDidChange(_ script: HTMLScript) {
        guard script === self.script else {
            return
        }
        update(body: script.currentHTML, transition: script.transition)
        notify()
    }

    private func update(body: String, transition: String? = nil) {
        lock.lock()
        if self.body != body {
            self.body = body
            version += 1
            if let transition = transition {
                transitionVersion = version
                transitionKind = transition
            }
        }
        lock.unlock()
    }

    private func notify() {
        for observer in observers.values {
            observer()
        }
    }

    private func handleAnchor(_ url: String) {
        if url == "chat:restart-script" {
            restartScript()
            return
        }
        if let (command, params) = HTMLBubbleState.parseChatLink(url), command == "toggle" || command == "select" {
            if applyState(command: command, params: params) {
                notify()
            }
            return
        }
        guard let url = HTMLBubbleState.contentLink(url), HTMLBubbleUserAction.allow(now: CACurrentMediaTime(), sinceInput: HTMLBubbleUserAction.inputAge()) else {
            return
        }
        linkHandler?(self, url)
    }

    static let contentLinkSchemes: Set<String> = ["https"]

    static func contentLink(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard let colon = trimmed.firstIndex(of: ":"), contentLinkSchemes.contains(trimmed[..<colon].lowercased()), !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private func applyState(command: String, params: [String: String]) -> Bool {
        guard let key = params["key"], !key.isEmpty else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        if command == "toggle" {
            if let index = keys.firstIndex(of: key) {
                keys.remove(at: index)
            } else {
                keys.append(key)
            }
        } else {
            var group = params["group"] ?? ""
            if group.isEmpty {
                if let dash = key.range(of: "-", options: .backwards) {
                    group = String(key[key.startIndex ..< dash.lowerBound])
                } else {
                    group = key
                }
            }
            let prefix = group + "-"
            keys.removeAll(where: { $0.hasPrefix(prefix) })
            keys.append(key)
        }
        version += 1
        transitionVersion = version
        transitionKind = "fade"
        return true
    }

    static func containsASCII(_ text: String, _ needle: String) -> Bool {
        let pattern = Array(needle.utf8)
        let scan: (UnsafeBufferPointer<UInt8>) -> Bool = { bytes in
            let count = bytes.count, length = pattern.count
            if length == 0 || count < length {
                return length == 0
            }
            var i = 0
            while i <= count - length {
                if bytes[i] == pattern[0] {
                    var j = 1
                    while j < length && bytes[i + j] == pattern[j] {
                        j += 1
                    }
                    if j == length {
                        return true
                    }
                }
                i += 1
            }
            return false
        }
        if let result = text.utf8.withContiguousStorageIfAvailable(scan) {
            return result
        }
        return Array(text.utf8).withUnsafeBufferPointer(scan)
    }

    static func containsBodyTag(_ text: String) -> Bool {
        let scan: (UnsafeBufferPointer<UInt8>) -> Bool = { bytes in
            let count = bytes.count
            if count < 5 {
                return false
            }
            var i = 0
            while i <= count - 5 {
                if bytes[i] == 0x3C, bytes[i + 1] | 0x20 == 0x62, bytes[i + 2] | 0x20 == 0x6F, bytes[i + 3] | 0x20 == 0x64, bytes[i + 4] | 0x20 == 0x79 {
                    return true
                }
                i += 1
            }
            return false
        }
        if let result = text.utf8.withContiguousStorageIfAvailable(scan) {
            return result
        }
        return Array(text.utf8).withUnsafeBufferPointer(scan)
    }

    private func wrap(_ body: String, appearance: HTMLBubbleAppearance) -> String {
        if HTMLBubbleState.containsBodyTag(body) {
            return body.drop(while: { $0.isWhitespace }).range(of: "<!doctype", options: [.caseInsensitive, .anchored]) == nil ? "<!doctype html>" + body : body
        }
        var classes = [appearance.dark ? "lc-dark" : "lc-light", outgoing ? "lc-out" : "lc-in"]
        classes.append(contentsOf: keys.map { "on-\($0)" })
        return "<!doctype html><body class=\"\(classes.joined(separator: " "))\">" + body
    }

    public static func parseChatLink(_ url: String) -> (String, [String: String])? {
        guard url.hasPrefix("chat:") else {
            return nil
        }
        let rest = "chat://x/" + url.dropFirst(5)
        let components = URLComponents(string: rest) ?? rest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap { URLComponents(string: $0) }
        guard let components = components else {
            return nil
        }
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name] = item.value ?? ""
        }
        let command = (components.path as NSString).lastPathComponent
        return (command, params)
    }

    public static func escape(_ text: String) -> String {
        return text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static let styleRegex = try? NSRegularExpression(pattern: "<(style|script)[^>]*>[\\s\\S]*?</\\1>", options: [.caseInsensitive])
    private static let tagRegex = try? NSRegularExpression(pattern: "<[^>]*>", options: [])
    private static let spaceRegex = try? NSRegularExpression(pattern: "\\s+", options: [])

    public static func plainText(from html: String) -> String {
        var text = html
        for regex in [styleRegex, tagRegex] {
            if let regex = regex {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            }
        }
        let entities: [(String, String)] = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        if let regex = spaceRegex {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let widgetRegex = try? NSRegularExpression(pattern: "^\\s*(?:<!--[\\s\\S]*?-->\\s*|<(style|script)\\b[^>]*>[\\s\\S]*?</\\1\\s*>\\s*)*<[a-zA-Z][^>]*\\bclass\\s*=\\s*[\"'](?:[^\"']*\\s)?widget(?:\\s[^\"']*)?[\"']", options: [.caseInsensitive])

    public static func isWidget(_ html: String) -> Bool {
        guard let regex = widgetRegex else {
            return false
        }
        return regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)) != nil
    }

    public static func looksLikeHTML(_ text: String) -> Bool {
        return text.range(of: "<[a-zA-Z!/][^>]*>", options: .regularExpression) != nil
    }
}

enum HTMLBubbleUserAction {
    static let inputWindow: CFTimeInterval = 2
    static let minimumInterval: CFTimeInterval = 0.7
    private static var lastAllowed: CFTimeInterval = -.infinity
    static var inputAge: () -> CFTimeInterval = { secondsSinceUserInput }

    static var secondsSinceUserInput: CFTimeInterval {
        let types: [CGEventType] = [.leftMouseUp, .keyDown, .rightMouseUp, .otherMouseUp]
        return types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? .infinity
    }

    static func allow(now: CFTimeInterval, sinceInput: CFTimeInterval = secondsSinceUserInput) -> Bool {
        assert(Thread.isMainThread)
        guard sinceInput >= 0, sinceInput <= inputWindow, now - lastAllowed >= minimumInterval else {
            return false
        }
        lastAllowed = now
        return true
    }

    static func reset() {
        lastAllowed = -.infinity
    }
}

public struct HTMLTwidgetResize: Equatable {
    public let unchangedTop: CGFloat
    public let unchangedBottom: CGFloat
    public let pointerFrom: CGFloat?
    public let pointerTo: CGFloat?
    public let keepsBottom: Bool
}
