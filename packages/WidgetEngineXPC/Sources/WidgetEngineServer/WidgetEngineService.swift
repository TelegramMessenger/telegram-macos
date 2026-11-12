import Foundation
import Security
import WidgetSandbox
import WidgetSandboxProtocol
import WidgetEngineXPC

public final class WidgetEngineService: NSObject, NSXPCListenerDelegate {
    public static func run(resources: SandboxResources? = nil) -> Never {
        let service = WidgetEngineService(resources: resources ?? embeddedResources() ?? .shared)
        let listener = NSXPCListener.service()
        listener.delegate = service
        listener.resume()
        exit(EXIT_FAILURE)
    }

    public var requiresSandbox = true
    private let resources: SandboxResources

    public init(resources: SandboxResources) {
        self.resources = resources
    }

    static func embeddedResources() -> SandboxResources? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("WidgetSandbox_WidgetSandbox.bundle"), let bundle = Bundle(url: url) else {
            return nil
        }
        return SandboxResources(bundle: bundle)
    }

    private let connectionsLock = NSLock()
    private var connections: [ObjectIdentifier: NSXPCConnection] = [:]

    func invalidateAll() {
        connectionsLock.lock()
        let all = Array(connections.values)
        connectionsLock.unlock()
        all.forEach { $0.invalidate() }
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = WidgetEngineXPCInterface.service()
        connection.remoteObjectInterface = WidgetEngineXPCInterface.client()
        let session = WidgetEngineSession(connection: connection, sandboxed: !requiresSandbox || WidgetEngineSandbox.isSandboxed, resources: resources)
        connection.exportedObject = session
        let key = ObjectIdentifier(connection)
        connectionsLock.lock()
        connections[key] = connection
        connectionsLock.unlock()
        connection.invalidationHandler = { [weak session, weak self] in
            session?.close()
            self?.connectionsLock.lock()
            self?.connections.removeValue(forKey: key)
            self?.connectionsLock.unlock()
        }
        connection.interruptionHandler = { [weak session] in session?.close() }
        connection.resume()
        return true
    }
}

final class WidgetEngineSession: NSObject, WidgetEngineServiceXPC {
    private let lock = NSLock()
    private var server: SandboxRemoteServer?
    private let sink: ProxySink
    private let sandboxed: Bool
    private let resources: SandboxResources

    init(connection: NSXPCConnection, sandboxed: Bool, resources: SandboxResources) {
        self.sink = ProxySink(connection: connection)
        self.sandboxed = sandboxed
        self.resources = resources
    }

    private var current: SandboxRemoteServer? {
        lock.lock()
        defer { lock.unlock() }
        return server
    }

    func close() {
        lock.lock()
        let server = self.server
        self.server = nil
        lock.unlock()
        server?.close()
    }

    func open(features: String, reply: @escaping (String?) -> Void) {
        guard sandboxed else {
            reply("the widget engine service is not sandboxed")
            return
        }
        lock.lock()
        if server == nil {
            server = SandboxRemoteServer(sink: sink, features: WidgetEngineXPCInterface.decode(features: features), resources: resources)
        }
        lock.unlock()
        reply(nil)
    }

    func prewarm() { current?.prewarm() }

    func start(html: String, config: Data) {
        guard let decoded = SandboxRemoteCoding.decodeConfig(config) else {
            sink.remoteDiag(kind: "engine-service", detail: "unreadable start config (\(config.count) bytes)")
            return
        }
        guard let server = current else {
            sink.remoteDiag(kind: "engine-service", detail: "start before open")
            return
        }
        server.start(html: html, config: decoded)
    }

    func event(_ json: String) { current?.event(json) }
    func activationEvent(_ json: String, gesture: Int) { current?.activationEvent(json, gesture: gesture) }
    func frame(_ time: Double) { current?.frame(time) }
    func viewport(width: Double, height: Double, dpr: Double) { current?.viewport(innerWidth: width, innerHeight: height, dpr: dpr) }
    func resize(_ json: String) { current?.resize(json) }
    func theme(_ theme: String, params: Data) { current?.theme(theme, params: WidgetEngineXPCInterface.decode(strings: params)) }

    func contentSafeArea(_ area: Data) {
        guard let area = SandboxRemoteCoding.decodeSafeArea(area) else { return }
        current?.contentSafeArea(area)
    }

    func setData(_ data: Data) {
        guard let data = SandboxRemoteCoding.decodeData(data) else { return }
        current?.setData(data)
    }

    func setVisible(_ visible: Bool) { current?.setVisible(visible) }

    func press(began: Bool) {
        if began {
            current?.pressBegan()
        } else {
            current?.pressEnded()
        }
    }

    func stop(_ reason: String) { current?.stop(reason: reason) }

    func answer(request id: Int, outcome: Data) {
        guard let outcome = SandboxRemoteCoding.decodeOutcome(outcome) else { return }
        current?.answer(request: id, outcome: outcome)
    }

    func morph(_ html: String, reply: @escaping (Bool) -> Void) {
        guard let server = current else { return reply(false) }
        server.morph(html: html, completion: reply)
    }

    func evaluate(_ code: String, reply: @escaping (String?) -> Void) {
        guard let server = current else { return reply(nil) }
        server.evaluateTrusted(code, completion: reply)
    }

    func collectGarbage() { current?.collectGarbage() }
}

final class ProxySink: SandboxRemoteSink {
    private let proxy: WidgetEngineClientXPC?
    private let synchronous: WidgetEngineClientXPC?

    init(connection: NSXPCConnection) {
        self.proxy = connection.remoteObjectProxyWithErrorHandler { _ in } as? WidgetEngineClientXPC
        self.synchronous = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in } as? WidgetEngineClientXPC
    }

    func remoteTaskStarted() { proxy?.taskStarted() }
    func remoteTaskCompleted() { proxy?.taskCompleted() }
    func remoteOps(_ json: String, canvas: [Int: WidgetCanvasBatch]) { proxy?.ops(json, canvas: canvas.isEmpty ? nil : SandboxRemoteCoding.encode(canvas: canvas)) }

    func remoteBinaryOps(_ payload: BinaryOpsPayload, canvas: [Int: WidgetCanvasBatch]) {
        let encoded = SandboxRemoteCoding.encode(binary: payload)
        proxy?.binaryOps(words: encoded.words, strings: encoded.strings, canvas: canvas.isEmpty ? nil : SandboxRemoteCoding.encode(canvas: canvas))
    }

    func remoteQuery(_ json: String) -> (json: String, binary: Data?) {
        var answer: (json: String, binary: Data?) = ("{\"error\":\"dead\"}", nil)
        guard let synchronous = synchronous else {
            return answer
        }
        synchronous.query(json) { value, binary in
            answer = (value, binary)
        }
        return answer
    }

    func remoteListen(_ json: String) { proxy?.listen(json) }
    func remotePreventDefault(_ json: String) { proxy?.preventDefault(json) }
    func remoteAnim(_ json: String) { proxy?.anim(json) }
    func remoteRequestsFrame() { proxy?.requestsFrame() }
    func remoteLog(level: String, text: String) { proxy?.log(level, text: text) }
    func remoteDiag(kind: String, detail: String) { proxy?.diag(kind, detail: detail) }
    func remoteBridge(method: String, argsJson: String) { proxy?.bridge(method, args: argsJson) }
    func remoteCopyText(_ text: String) { proxy?.copyText(text) }
    func remoteRequest(id: Int, data: String, wallet: Bool) { proxy?.request(id, data: data, wallet: wallet) }
    func remoteWallet(id: Int, payload: Data) { proxy?.wallet(id, payload: payload) }
    func remoteStorage(_ commitJson: String) { proxy?.storage(commitJson) }
    func remoteResizeAnchor(_ edge: String) { proxy?.resizeAnchor(edge) }
    func remoteWatchesPublicData(_ on: Bool) { proxy?.watchesPublicData(on) }
    func remoteLoaded() { proxy?.loaded() }
    func remoteStats(_ stats: SandboxStats) { proxy?.stats(WidgetEngineXPCInterface.encode(doubles: SandboxRemoteCoding.encode(stats: stats))) }
    func remoteDied(_ reason: String) { proxy?.died(reason) }
    func remoteDisconnected() {}
}

public enum WidgetEngineSandbox {
    public static let isSandboxed: Bool = {
        return hasSandboxEntitlement && hasContainer && !canListUserHome
    }()

    static var hasSandboxEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil), let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) else {
            return false
        }
        return (value as? Bool) == true
    }

    static var hasContainer: Bool {
        return ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var canListUserHome: Bool {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else {
            return true
        }
        guard let directory = opendir(home) else {
            return false
        }
        closedir(directory)
        return true
    }
}
