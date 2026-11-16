import Foundation
import WidgetSandbox
import WidgetSandboxProtocol

public final class WidgetEngineXPCChannel: SandboxRemoteChannel {
    private let connection: NSXPCConnection
    private let receiver: Receiver
    private let features: Set<String>
    private var proxy: WidgetEngineServiceXPC?

    public convenience init(serviceName: String, features: Set<String>) {
        self.init(connection: NSXPCConnection(serviceName: serviceName), features: features)
    }

    public convenience init(endpoint: NSXPCListenerEndpoint, features: Set<String>) {
        self.init(connection: NSXPCConnection(listenerEndpoint: endpoint), features: features)
    }

    private init(connection: NSXPCConnection, features: Set<String>) {
        self.features = features
        self.receiver = Receiver()
        self.connection = connection
        connection.remoteObjectInterface = WidgetEngineXPCInterface.service()
        connection.exportedInterface = WidgetEngineXPCInterface.client()
        connection.exportedObject = receiver
        let receiver = self.receiver
        connection.interruptionHandler = { [weak connection] in
            receiver.disconnected()
            connection?.invalidate()
        }
        connection.invalidationHandler = {
            receiver.disconnected()
        }
        connection.resume()
        proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            receiver.disconnected()
        } as? WidgetEngineServiceXPC
    }

    deinit {
        connection.invalidate()
    }

    public func attach(_ sink: SandboxRemoteSink) {
        guard receiver.attach(sink) else { return }
        let receiver = self.receiver
        let opened = Once()
        proxy?.open(features: WidgetEngineXPCInterface.encode(features: features)) { [weak connection] error in
            guard opened.claim(), let error else { return }
            receiver.disconnected(reason: error)
            connection?.invalidate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + WidgetEngineXPCInterface.openTimeout) { [weak connection] in
            guard opened.claim() else { return }
            receiver.disconnected()
            connection?.invalidate()
        }
    }

    public func prewarm(features: Set<String>) { proxy?.prewarm() }
    public func start(html: String, config: SandboxConfig) { proxy?.start(html: html, config: SandboxRemoteCoding.encode(config: config)) }
    public func event(_ json: String) { proxy?.event(json) }
    public func activationEvent(_ json: String, gesture: Int) { proxy?.activationEvent(json, gesture: gesture) }
    public func frame(_ time: Double) { proxy?.frame(time) }
    public func viewport(innerWidth: Double, innerHeight: Double, dpr: Double) { proxy?.viewport(width: innerWidth, height: innerHeight, dpr: dpr) }
    public func resize(_ entriesJson: String) { proxy?.resize(entriesJson) }
    public func theme(_ theme: String, params: [String: String]) { proxy?.theme(theme, params: WidgetEngineXPCInterface.encode(strings: params)) }
    public func contentSafeArea(_ area: WidgetContentSafeArea) { proxy?.contentSafeArea(SandboxRemoteCoding.encode(safeArea: area)) }
    public func setData(_ data: WidgetData) { proxy?.setData(SandboxRemoteCoding.encode(data: data)) }
    public func setVisible(_ visible: Bool) { proxy?.setVisible(visible) }
    public func pressBegan() { proxy?.press(began: true) }
    public func pressEnded() { proxy?.press(began: false) }
    public func stop(reason: String) { proxy?.stop(reason) }
    public func answer(request id: Int, outcome: SandboxRemoteOutcome) { proxy?.answer(request: id, outcome: SandboxRemoteCoding.encode(outcome: outcome)) }
    public func collectGarbage() { proxy?.collectGarbage() }

    public func morph(html: String, completion: @escaping (Bool) -> Void) {
        let once = Once()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            if once.claim() { completion(false) }
        } as? WidgetEngineServiceXPC
        guard let proxy = proxy else {
            return completion(false)
        }
        proxy.morph(html) { applied in
            if once.claim() { completion(applied) }
        }
    }

    public func evaluateTrusted(_ code: String, completion: @escaping (String?) -> Void) {
        let once = Once()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            if once.claim() { completion(nil) }
        } as? WidgetEngineServiceXPC
        guard let proxy = proxy else {
            return completion(nil)
        }
        proxy.evaluate(code) { value in
            if once.claim() { completion(value) }
        }
    }

    public func close() {
        connection.invalidate()
    }

    private final class Once {
        private let lock = NSLock()
        private var done = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done {
                return false
            }
            done = true
            return true
        }
    }

    private final class Receiver: NSObject, WidgetEngineClientXPC {
        private let lock = NSLock()
        private weak var sink: SandboxRemoteSink?
        private var gone = false

        func attach(_ sink: SandboxRemoteSink) -> Bool {
            lock.lock()
            guard !gone else {
                lock.unlock()
                sink.remoteDisconnected()
                return false
            }
            self.sink = sink
            lock.unlock()
            return true
        }

        private var current: SandboxRemoteSink? {
            lock.lock()
            defer { lock.unlock() }
            return gone ? nil : sink
        }

        func disconnected(reason: String? = nil) {
            lock.lock()
            let sink = gone ? nil : self.sink
            gone = true
            lock.unlock()
            if let reason {
                sink?.remoteDied(reason)
            } else {
                sink?.remoteDisconnected()
            }
        }

        func taskStarted() { current?.remoteTaskStarted() }
        func taskCompleted() { current?.remoteTaskCompleted() }

        func ops(_ json: String, canvas: Data?) {
            guard let sink = current else { return }
            guard let decoded = decodeCanvas(canvas) else { return sink.remoteDiag(kind: "protocol-violation", detail: "malformed canvas payload from the engine") }
            sink.remoteOps(json, canvas: decoded)
        }

        func binaryOps(words: Data, strings: Data, canvas: Data?) {
            guard let sink = current else { return }
            guard let payload = SandboxRemoteCoding.decodeBinary(words: words, strings: strings), let decoded = decodeCanvas(canvas) else {
                return sink.remoteDiag(kind: "protocol-violation", detail: "malformed binary ops from the engine")
            }
            sink.remoteBinaryOps(payload, canvas: decoded)
        }

        private func decodeCanvas(_ data: Data?) -> [Int: WidgetCanvasBatch]? {
            guard let data = data, !data.isEmpty else {
                return [:]
            }
            return SandboxRemoteCoding.decodeCanvas(data)
        }

        func query(_ json: String, reply: @escaping (String, Data?) -> Void) {
            guard let sink = current else { return reply("{\"error\":\"dead\"}", nil) }
            let answer = sink.remoteQuery(json)
            reply(answer.json, answer.binary)
        }

        func listen(_ json: String) { current?.remoteListen(json) }
        func preventDefault(_ json: String) { current?.remotePreventDefault(json) }
        func anim(_ json: String) { current?.remoteAnim(json) }
        func requestsFrame() { current?.remoteRequestsFrame() }
        func log(_ level: String, text: String) { current?.remoteLog(level: level, text: text) }
        func diag(_ kind: String, detail: String) { current?.remoteDiag(kind: kind, detail: detail) }
        func bridge(_ method: String, args: String) { current?.remoteBridge(method: method, argsJson: args) }
        func copyText(_ text: String) { current?.remoteCopyText(text) }
        func request(_ id: Int, data: String, wallet: Bool) { current?.remoteRequest(id: id, data: data, wallet: wallet) }
        func wallet(_ id: Int, payload: Data) { current?.remoteWallet(id: id, payload: payload) }
        func storage(_ json: String) { current?.remoteStorage(json) }
        func resizeAnchor(_ edge: String) { current?.remoteResizeAnchor(edge) }
        func watchesPublicData(_ on: Bool) { current?.remoteWatchesPublicData(on) }
        func loaded() { current?.remoteLoaded() }

        func stats(_ values: Data) {
            guard let sink = current, let doubles = WidgetEngineXPCInterface.decode(doubles: values, max: 64), let stats = SandboxRemoteCoding.decodeStats(doubles) else { return }
            sink.remoteStats(stats)
        }

        func died(_ reason: String) { current?.remoteDied(reason) }
    }
}

public enum WidgetEngineXPC {
    public static func embeddedServiceName(in bundle: Bundle = .main) -> String? {
        let url = bundle.bundleURL.appendingPathComponent("Contents/XPCServices", isDirectory: true).appendingPathComponent(WidgetEngineXPCInterface.bundleName, isDirectory: true)
        return Bundle(url: url)?.bundleIdentifier
    }

    /// Every widget engine the app creates from now on runs in the embedded service. Main thread, before the first widget.
    @discardableResult
    public static func install(serviceName: String? = embeddedServiceName()) -> Bool {
        guard let serviceName = serviceName else {
            return false
        }
        SandboxEngine.remoteChannelFactory = { features in
            WidgetEngineXPCChannel(serviceName: serviceName, features: features)
        }
        EnginePool.shared.drain()
        return true
    }
}
