import XCTest
import WidgetSandbox
import WidgetSandboxProtocol
@testable import WidgetEngineXPC
@testable import WidgetEngineServer

final class WidgetEngineXPCTests: XCTestCase {
    private final class Probe: Renderer {
        let view = PlatformView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        var onMessage: ((String) -> Void)?
        var onDiag: ((String, String) -> Void)?
        var log = ""
        var queries = 0
        func load() { onMessage?("{\"type\":\"ready\"}") }
        func send(_ json: String) {
            log += json
            guard let message = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], message["type"] as? String == "query", let id = message["qid"] as? Int else { return }
            queries += 1
            onMessage?("{\"type\":\"result\",\"qid\":\(id),\"result\":{\"x\":0,\"y\":0,\"width\":100,\"height\":20,\"offsetHeight\":20}}")
        }
        func setTheme(_ theme: String) {}
        func evaluate(_ script: String, completion: @escaping (String?) -> Void) { completion(nil) }
        func destroy() {}
    }

    private var listener: NSXPCListener!
    private var service: WidgetEngineService!

    override func setUp() {
        service = WidgetEngineService(resources: .shared)
        service.requiresSandbox = false
        listener = NSXPCListener.anonymous()
        listener.delegate = service
        listener.resume()
        let endpoint = listener.endpoint
        SandboxEngine.remoteChannelFactory = { WidgetEngineXPCChannel(endpoint: endpoint, features: $0) }
    }

    override func tearDown() {
        SandboxEngine.remoteChannelFactory = nil
        listener.invalidate()
    }

    private func pump(_ seconds: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }

    func testWidgetRunsThroughRealXPCWithQueriesInOrder() throws {
        let probe = Probe()
        var options = WidgetHost.Options()
        options.features = ["binaryOps", "canvasWords", "webAnimations", "morphUpdates"]
        let html = "<div id='d'>a</div><canvas id='c' width='10' height='10'></canvas><script>var d=document.getElementById('d');d.style.height='50px';d.textContent='h:'+d.offsetHeight;var c=document.getElementById('c').getContext('2d');c.fillStyle='#f00';c.fillRect(0,0,5,5);console.log('logged');</script>"
        let host = try WidgetHost(html: html, options: options, rendererFactory: { _, _, _ in probe })
        defer { host.destroy() }
        pump { host.diagnostics.loaded && host.diagnostics.rendered && probe.log.contains("h:20") }
        XCTAssertTrue(host.diagnostics.loaded)
        XCTAssertNil(host.diagnostics.dead)
        XCTAssertTrue(probe.log.contains("h:20"), probe.log)
        XCTAssertTrue(probe.log.contains("fillRect"), "canvas words crossed the boundary")
        XCTAssertGreaterThan(probe.queries, 0)
        XCTAssertTrue(host.diagnostics.logs.contains { $0.1 == "logged" })
    }

    func testUnsandboxedServiceRefusesToRun() throws {
        service.requiresSandbox = true
        let probe = Probe()
        let host = try WidgetHost(html: "<p>x</p>", options: WidgetHost.Options(), rendererFactory: { _, _, _ in probe })
        defer { host.destroy() }
        pump { host.diagnostics.dead != nil }
        XCTAssertEqual(host.diagnostics.dead, "the widget engine service is not sandboxed")
    }

    func testClosedConnectionKillsTheWidget() throws {
        let probe = Probe()
        let host = try WidgetHost(html: "<p id='p'>x</p><script>setInterval(function(){document.getElementById('p').textContent=Date.now();},20);</script>", options: WidgetHost.Options(), rendererFactory: { _, _, _ in probe })
        defer { host.destroy() }
        pump { host.diagnostics.loaded }
        listener.invalidate()
        service.invalidateAll()
        pump { host.diagnostics.dead != nil }
        XCTAssertEqual(host.diagnostics.dead, "the widget engine process ended")
    }

    func testAServiceThatNeverAnswersOpenFailsInsteadOfHanging() throws {
        final class Silent: NSObject, NSXPCListenerDelegate {
            func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool { true }
        }
        let silent = Silent()
        let mute = NSXPCListener.anonymous()
        mute.delegate = silent
        mute.resume()
        defer { mute.invalidate() }
        let endpoint = mute.endpoint
        SandboxEngine.remoteChannelFactory = { WidgetEngineXPCChannel(endpoint: endpoint, features: $0) }
        let probe = Probe()
        let host = try WidgetHost(html: "<p>x</p>", options: WidgetHost.Options(), rendererFactory: { _, _, _ in probe })
        defer { host.destroy() }
        pump(WidgetEngineXPCInterface.openTimeout + 5) { host.diagnostics.dead != nil }
        XCTAssertEqual(host.diagnostics.dead, "the widget engine process ended")
    }

    private static let features: Set<String> = ["binaryOps", "canvasWords", "webAnimations", "morphUpdates"]

    private func bootedHost(_ html: String, pools: Bool = false) throws -> (WidgetHost, Probe) {
        let probe = Probe()
        var options = WidgetHost.Options()
        options.features = Self.features
        options.pools = pools
        let host = try WidgetHost(html: html, options: options, rendererFactory: { _, _, _ in probe })
        pump { host.diagnostics.loaded && host.diagnostics.rendered }
        return (host, probe)
    }

    func testPrewarmedPoolEngineBootsThroughXPC() throws {
        EnginePool.shared.features = Self.features
        EnginePool.shared.prewarm(1)
        pump(1) { false }
        let (host, probe) = try bootedHost("<p id='p'>pooled</p>", pools: true)
        defer {
            host.destroy()
            EnginePool.shared.targetSize = 0
            EnginePool.shared.drain()
        }
        XCTAssertTrue(host.diagnostics.prewarmed.contains("engine"), host.diagnostics.prewarmed)
        XCTAssertTrue(probe.log.contains("pooled"))
        XCTAssertNil(host.diagnostics.dead)
    }

    func testMorphGoesThroughXPC() throws {
        let (host, probe) = try bootedHost("<p id='p'>before</p>")
        defer { host.destroy() }
        var applied: Bool?
        host.morph(html: "<p id='p'>after-morph</p>") { applied = $0 }
        pump { applied != nil && probe.log.contains("after-morph") }
        XCTAssertEqual(applied, true)
        XCTAssertTrue(probe.log.contains("after-morph"))
    }

    func testTrustedEvaluationGoesThroughXPC() throws {
        let (host, _) = try bootedHost("<p id='p'>agent</p>")
        defer { host.destroy() }
        var answer: String??
        host.evaluateInWidget("return document.getElementById('p').textContent + ':' + (1 + 2);") { answer = .some($0) }
        pump { answer != nil }
        XCTAssertEqual(answer??.contains("agent:3"), true, "\(String(describing: answer))")
    }

    func testTapOpensALinkOnceThroughXPC() throws {
        let (host, probe) = try bootedHost("<a id='a' href='https://example.com/x'>x</a><script>document.getElementById('a').addEventListener('click',function(){TelegramWidget.openLink('https://example.com/again');});setTimeout(function(){TelegramWidget.openLink('https://example.com/timer');},50);</script>")
        defer { host.destroy() }
        var links: [String] = []
        host.onAction = { action in
            switch action {
            case .openLink(let url), .openTelegramLink(let url): links.append(url.absoluteString)
            default: break
            }
        }
        pump(0.5) { false }
        XCTAssertEqual(links, [], "no link without a tap")
        let click: [String: Any] = ["type": "event", "trusted": true, "ev": ["type": "click", "targetId": 5, "clientX": 5, "clientY": 5, "button": 0, "buttons": 0, "detail": 1]]
        probe.onMessage?(String(decoding: try JSONSerialization.data(withJSONObject: click), as: UTF8.self))
        pump { !links.isEmpty }
        pump(0.5) { false }
        XCTAssertEqual(links.count, 1, "\(links)")
        XCTAssertEqual(host.diagnostics.diags["activation-blocked"]?.count ?? 0 > 0, true)
    }

    func testPointerListenersReachTheRendererAndTheirHandlersRunThroughXPCWhileKeyListenersStayOutOfTheProfile() throws {
        let (host, probe) = try bootedHost("<p id='p'>idle</p><script>var p=document.getElementById('p');document.addEventListener('pointerdown',function(e){p.textContent='down:'+e.isTrusted;});document.addEventListener('keydown',function(e){p.textContent='key:'+e.key;});</script>")
        defer { host.destroy() }
        pump { probe.log.contains("\"listen\"") }
        let listened = probe.log.components(separatedBy: "{\"type\":\"listen\"").dropFirst().last ?? ""
        XCTAssertTrue(listened.contains("pointerdown"), probe.log)
        XCTAssertFalse(listened.prefix(while: { $0 != "}" }).contains("keydown"), "widget profile 1 has no keyboard: the renderer is never asked for key events")
        let down: [String: Any] = ["type": "event", "trusted": true, "ev": ["type": "pointerdown", "targetId": 5, "clientX": 5, "clientY": 5, "button": 0, "buttons": 1, "pointerId": 1, "pointerType": "mouse", "isPrimary": true]]
        probe.onMessage?(String(decoding: try JSONSerialization.data(withJSONObject: down), as: UTF8.self))
        pump { probe.log.contains("down:") }
        XCTAssertTrue(probe.log.contains("down:true"), probe.log)
    }

    func testWalletRequestAndSigningResultCrossXPC() throws {
        let probe = Probe()
        var options = WidgetHost.Options()
        options.context = WidgetContext(canQuery: true, wallet: true)
        let html = """
        <p id='p'>idle</p><script>
        document.addEventListener('click', function() {
            TelegramWidget.request('get-wallet', { wallet: true }).then(function() {
                return TelegramWidget.wallet.signData({ type: 'text', text: 'I agree' }, 'sign');
            }).catch(function(error) {
                console.log('wallet-result:' + error.code);
            });
        });
        </script>
        """
        let host = try WidgetHost(html: html, options: options, rendererFactory: { _, _, _ in probe })
        defer { host.destroy() }
        var request: WidgetRequest?
        var signing: WalletCall?
        host.onRequest = { value, complete in
            request = value
            complete(.success(WidgetRequestAnswer(result: "wallet")))
        }
        host.onWallet = { value, complete in
            signing = value
            complete(.failure(.rejected))
        }
        pump { host.diagnostics.loaded && host.diagnostics.rendered }
        let click: [String: Any] = ["type": "event", "trusted": true, "ev": ["type": "click", "targetId": 5, "clientX": 5, "clientY": 5, "button": 0, "buttons": 0, "detail": 1]]
        probe.onMessage?(String(decoding: try JSONSerialization.data(withJSONObject: click), as: UTF8.self))
        pump { host.diagnostics.logs.contains { $0.text == "wallet-result:REJECTED" } }
        XCTAssertEqual(request, WidgetRequest(data: "get-wallet", wallet: true))
        XCTAssertEqual(signing, .signData(SignDataPayload(type: .text, text: "I agree"), data: "sign"))
        XCTAssertTrue(host.diagnostics.logs.contains { $0.text == "wallet-result:REJECTED" })
    }

    func testWireHelpers() {
        XCTAssertEqual(WidgetEngineXPCInterface.decode(features: WidgetEngineXPCInterface.encode(features: ["b", "a"])), ["a", "b"])
        XCTAssertEqual(WidgetEngineXPCInterface.decode(doubles: WidgetEngineXPCInterface.encode(doubles: [1, 2.5]), max: 4), [1, 2.5])
        XCTAssertNil(WidgetEngineXPCInterface.decode(doubles: Data([1, 2, 3]), max: 4))
        XCTAssertNil(WidgetEngineXPCInterface.decode(doubles: Data(count: 80), max: 4))
        XCTAssertEqual(WidgetEngineXPCInterface.decode(strings: Data("not json".utf8)), [:])
    }
}
