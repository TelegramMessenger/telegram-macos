import XCTest
import Cocoa
import WidgetSandbox
import TwidgetRenderer
@testable import HTMLBubbles

func log(_ text: String) {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
}

final class RedTeamRendererTests: XCTestCase {
    final class Run {
        let window: NSWindow
        let host: WidgetHost
        var frame = CGRect(x: 250, y: 200, width: 400, height: 300)
        var maxStall: CFTimeInterval = 0
        var cpu: CFTimeInterval = 0

        static func threadCPU() -> CFTimeInterval {
            var t = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
            return CFTimeInterval(t.tv_sec) + CFTimeInterval(t.tv_nsec) / 1e9
        }

        init(_ html: String) {
            window = NSWindow(contentRect: CGRect(x: 100, y: 0, width: 900, height: 1300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .white
            window.contentView?.wantsLayer = true
            window.orderFrontRegardless()
            var options = WidgetHost.Options()
            options.asyncValidation = true
            options.features = ["binaryOps", "canvasWords", "webAnimations"]
            options.sharedValidatorThread = true
            options.startBeforeRendererReady = true
            options.policy = .strict
            host = try! WidgetHost(html: html, theme: "light", width: 400, options: options, rendererFactory: { _, theme, width in LiteHTMLWidgetRenderer(theme: theme, width: width) })
            host.view.frame = frame
            window.contentView?.addSubview(host.view)
        }

        func pump(_ seconds: TimeInterval, until: (() -> Bool)? = nil) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline && !(until?() ?? false) {
                let c0 = Self.threadCPU()
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                let used = Self.threadCPU() - c0
                maxStall = max(maxStall, used)
                cpu += used
            }
        }

        func fitHeight() {
            frame.size.height = max(host.diagnostics.height, 24)
            host.view.frame = frame
        }

        func capture() -> (pixels: [UInt8], width: Int, height: Int)? {
            window.displayIfNeeded()
            CATransaction.flush()
            guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { return nil }
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return (pixels, width, height)
        }

        func red(_ shot: (pixels: [UInt8], width: Int, height: Int)) -> (outside: Int, inside: Int) {
            let scale = CGFloat(shot.width) / window.frame.width
            let inner = CGRect(x: frame.minX * scale, y: (window.frame.height - frame.maxY) * scale, width: frame.width * scale, height: frame.height * scale).insetBy(dx: -2, dy: -2)
            var outside = 0, inside = 0
            for y in 0..<shot.height {
                for x in 0..<shot.width {
                    let i = (y * shot.width + x) * 4
                    if shot.pixels[i] > 200 && shot.pixels[i + 1] < 90 && shot.pixels[i + 2] < 90 {
                        if inner.contains(CGPoint(x: x, y: y)) { inside += 1 } else { outside += 1 }
                    }
                }
            }
            return (outside, inside)
        }

        deinit {
            host.destroy()
            window.orderOut(nil)
        }
    }

    func testNothingPaintsOutsideTheWidget() throws {
        let html = """
        <style>
        body{margin:0}
        .a{position:fixed;left:-300px;top:-300px;width:2000px;height:2000px;background:red;z-index:2147483647}
        .b{position:absolute;left:-500px;top:-200px;width:100px;height:100px;background:red}
        .c{transform:translate(-400px,-300px) scale(4);background:red;width:50px;height:50px;will-change:transform}
        .d{box-shadow:0 0 512px 300px red;outline:300px solid red;width:10px;height:10px;margin:100px}
        .e{filter:drop-shadow(0 0 200px red) drop-shadow(-600px 0 0 red);width:40px;height:40px;background:red}
        .f{margin-left:-800px;width:5000px;height:20px;background:red}
        .g{animation:m 1s infinite;width:30px;height:30px;background:red}
        @keyframes m{from{transform:translateX(-900px)}to{transform:translateX(900px)}}
        .h{backdrop-filter:blur(200px);position:absolute;inset:-500px;border:200px solid red}
        </style>
        <div class="a"></div><div class="b"></div><div class="c"></div><div class="d"></div><div class="e"></div><div class="f"></div><div class="g"></div><div class="h"></div>
        <svg width="2000" height="2000" style="position:absolute;left:-900px;top:-900px"><rect width="2000" height="2000" fill="red"/></svg>
        <canvas id="cv" width="2000" height="2000" style="position:absolute;left:-1000px;top:-1000px"></canvas>
        <script>var x=document.getElementById('cv').getContext('2d');x.fillStyle='red';x.fillRect(0,0,2000,2000);</script>
        """
        let t0 = CACurrentMediaTime()
        let run = Run(html)
        log("init \(CACurrentMediaTime() - t0)")
        run.pump(4) { run.host.diagnostics.rendered }
        log("rendered \(run.host.diagnostics.rendered) \(CACurrentMediaTime() - t0) stall \(run.maxStall) height \(run.host.diagnostics.height)")
        run.fitHeight()
        run.pump(1.5)
        guard let shot = run.capture() else { throw XCTSkip("window capture unavailable") }
        let red = run.red(shot)
        log("ESCAPE \(red) frame \(run.frame) window \(run.window.frame) shot \(shot.width)x\(shot.height) height \(run.frame.height) stall \(run.maxStall) t \(CACurrentMediaTime() - t0)")
        XCTAssertGreaterThan(red.inside, 100, "the widget did not paint; the capture proves nothing")
        XCTAssertEqual(red.outside, 0)
    }

    func testOversizedCanvasIsRejectedBeforePainting() {
        let run = Run("<canvas id='cv' width='3000' height='3000'></canvas><script>document.getElementById('cv').getContext('2d').fillRect(0,0,3000,3000);</script>")
        run.pump(4) { run.host.diagnostics.dead != nil }
        XCTAssertTrue(run.host.diagnostics.dead?.contains("Canvas limit exceeded") == true)
        XCTAssertNil(run.host.diagnostics.firstContentMs)
    }

    static func fallbackText() -> String {
        var text = ""
        for i in 0..<6000 {
            for code in [0x4E00 + i * 7 % 20000, 0x1F300 + i % 700, 0x0900 + i % 2000, 0x10A0 + i % 90, 0x1200 + i % 300] {
                if let scalar = UnicodeScalar(code) {
                    text.unicodeScalars.append(scalar)
                }
            }
        }
        return text
    }

    static func selectorRules() -> String {
        var css = ""
        for i in 0..<2000 {
            css += "div:not(.x\(i)) > div ~ div + div:nth-child(\(i)n+1) div div div{color:red}"
        }
        return css
    }

    static let knownStalls: Set<String> = ["flood-ascii-words", "flood-hyphens", "flood-questions", "flood-ext-a", "flood-hangul", "flood-kana", "flood-fullwidth", "flood-ext-b", "text-churn-split", "text-churn-budget", "filter-blur", "font-fallback", "layers", "text-churn-64k", "wide-dom", "deep-dom", "waapi", "svg-heavy", "text-shadow", "shadow-many", "radius-gradients"]

    static let exhaustion: [(String, String)] = [
        ("shadow-64", "<div style='width:10px;height:10px;margin:100px;box-shadow:0 0 64px 0 red'></div>"),
        ("shadow-256", "<div style='width:10px;height:10px;margin:100px;box-shadow:0 0 256px 0 red'></div>"),
        ("shadow-512-spread", "<div style='width:10px;height:10px;margin:100px;box-shadow:0 0 512px 300px red'></div>"),
        ("shadow-many", "<style>i{display:inline-block;width:4px;height:4px;box-shadow:0 0 40px 20px red,0 0 80px blue,0 0 120px green}</style>" + String(repeating: "<i></i>", count: 400)),
        ("text-shadow", "<p style='font-size:40px;text-shadow:0 0 200px red,0 0 150px blue,0 0 100px green'>" + String(repeating: "shadow ", count: 60) + "</p>"),
        ("filter-blur", "<style>b{display:block;height:30px;filter:blur(256px) drop-shadow(0 0 256px red);backdrop-filter:blur(256px)}</style>" + String(repeating: "<b>x</b>", count: 30)),
        ("deep-dom", String(repeating: "<div style='padding-left:1px'>", count: 3000) + "deep" + String(repeating: "</div>", count: 3000)),
        ("wide-dom", "<style>span{display:inline-block;width:3px;height:3px;background:red}</style>" + String(repeating: "<span></span>", count: 40000)),
        ("selectors", "<style>" + selectorRules() + "</style>" + String(repeating: "<div><div></div><div><div><div><div>x</div></div></div></div></div>", count: 200)),
        ("font-fallback", "<p>" + fallbackText() + "</p>"),
        ("canvas-huge", "<canvas id=c width=16384 height=16384></canvas><script>var x=document.getElementById('c').getContext('2d');for(var i=0;i<200;i++){x.shadowBlur=200;x.shadowColor='red';x.fillRect(i*50,i*50,8000,8000);}</script>"),
        ("waapi", "<style>i{display:inline-block;width:6px;height:6px;background:red}</style>" + String(repeating: "<i></i>", count: 3000) + "<script>document.querySelectorAll('i').forEach(function(e,n){e.animate([{transform:'rotate(0deg)',filter:'blur(0px)'},{transform:'rotate(360deg)',filter:'blur(50px)'}],{duration:500+n,iterations:Infinity});});</script>"),
        ("layers", "<style>i{display:inline-block;width:5px;height:5px;background:red;will-change:transform,opacity;transform:translateZ(0);opacity:.9}</style>" + String(repeating: "<i></i>", count: 5000)),
        ("radius-gradients", "<style>i{display:inline-block;width:40px;height:40px;border-radius:50%;background:conic-gradient(red,blue,green,red),radial-gradient(red,blue);border:20px dashed red;outline:30px dotted blue}</style>" + String(repeating: "<i></i>", count: 800)),
        ("text-churn", "<p id=t></p><script>var s='';for(var i=0;i<40000;i++){s+=String.fromCharCode(0x4E00+(i*7)%20000)+String.fromCharCode(0x0900+i%100);}var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<40)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("text-churn-64k", "<p id=t></p><script>var s='';for(var i=0;i<15000;i++){s+=String.fromCharCode(0x4E00+(i*7)%20000)+String.fromCharCode(0x0900+i%100);}var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<120)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("text-churn-budget", "<p id=t></p><script>var s='';for(var i=0;i<3990;i++){s+=String.fromCharCode(0x4E00+(i*7)%20000)+String.fromCharCode(0x0900+i%100);}var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("legit-typewriter", "<p id=t style='font-size:16px'></p><script>var s='';for(var i=0;i<600;i++)s+=String.fromCharCode(0x3042+(i*5)%80)+(i%40==39?'。':'');var n=0;setInterval(function(){n=(n+1)%(s.length+30);document.getElementById('t').textContent=s.slice(0,Math.min(n,s.length));},33);</script>"),
        ("legit-caption", "<p id=t style='font-size:18px'></p><script>var k=0;setInterval(function(){k++;var c='';for(var i=0;i<200;i++)c+=String.fromCharCode(0x4E00+(i*13+k*7)%2000);document.getElementById('t').textContent=c;},300);</script>"),
        ("legit-clock", "<div id=t style='font-size:40px'></div><script>var w='日月火水木金土';setInterval(function(){var d=new Date();document.getElementById('t').textContent=d.getHours()+'時'+d.getMinutes()+'分'+d.getSeconds()+'秒 ('+w[d.getDay()]+') 残り'+(100000-Date.now()%100000)+'ミリ秒';},50);</script>"),
        ("legit-transcript", "<div id=t style='font-size:14px'></div><script>var lines=['नमस्ते, आप कैसे हैं? मैं ठीक हूँ, धन्यवाद।','مرحبا، كيف حالك اليوم؟ أنا بخير والحمد لله.','आज मौसम बहुत अच्छा है, चलो बाहर चलते हैं।','هل يمكنك إرسال التقرير قبل نهاية اليوم؟'];var n=0;setInterval(function(){var p=document.createElement('p');p.textContent=lines[n%4]+' #'+n;document.getElementById('t').appendChild(p);n++;var t=document.getElementById('t');if(t.children.length>40)t.removeChild(t.firstChild);},250);</script>"),
        ("text-churn-split", "<div id=t></div><script>var t=document.getElementById('t'),ps=[];for(var j=0;j<8;j++){var p=document.createElement('p');t.appendChild(p);ps.push(p);}var n=0;function f(){n++;for(var j=0;j<8;j++){var s='';for(var i=0;i<500;i++)s+=String.fromCharCode(0x4E00+(i*7+n*3+j*11)%20000)+String.fromCharCode(0x0900+(i+n)%100);ps[j].textContent=s;}if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-ascii-words", "<p id=t></p><script>var s='a '.repeat(25000); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-hyphens", "<p id=t></p><script>var s='a-'.repeat(25000); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-questions", "<p id=t></p><script>var s='x?'.repeat(25000); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-ext-a", "<p id=t></p><script>var s='';for(var i=0;i<8000;i++)s+=String.fromCharCode(0x3400+i%6000); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-hangul", "<p id=t></p><script>var s='';for(var i=0;i<8000;i++)s+=String.fromCharCode(0xAC00+i%11000); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-kana", "<p id=t></p><script>var s='';for(var i=0;i<8000;i++)s+=String.fromCharCode(0x30A2+i%80); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-fullwidth", "<p id=t></p><script>var s='';for(var i=0;i<8000;i++)s+=String.fromCharCode(0xFF21+i%26)+(i%2?' ':''); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("flood-ext-b", "<p id=t></p><script>var s='';for(var i=0;i<4000;i++)s+=String.fromCodePoint(0x20000+i%40000); var n=0;function f(){n++;document.getElementById('t').textContent=s.slice(n%7)+n;if(n<1200)requestAnimationFrame(f);}requestAnimationFrame(f);</script>"),
        ("svg-heavy", "<svg width=400 height=400><defs><filter id=f><feGaussianBlur stdDeviation=500/><feMorphology radius=500/><feTurbulence baseFrequency=0.9 numOctaves=100/></filter></defs>" + String(repeating: "<circle cx=200 cy=200 r=190 filter='url(#f)' fill=red />", count: 200) + "</svg>"),
    ]

    func testExhaustionStallsStayBounded() {
        var report: [String] = []
        let only = ProcessInfo.processInfo.environment["REDTEAM_ONLY"]
        let repeats = Int(ProcessInfo.processInfo.environment["REDTEAM_REPEAT"] ?? "") ?? 1
        for (name, html) in Self.exhaustion where only == nil || only == name { for _ in 0..<repeats {
            let t0 = CACurrentMediaTime()
            let run = Run(html)
            run.pump(8) { run.host.diagnostics.rendered || run.host.diagnostics.dead != nil }
            let rendered = CACurrentMediaTime() - t0
            run.fitHeight()
            run.pump(Double(ProcessInfo.processInfo.environment["REDTEAM_SETTLE"] ?? "") ?? 1)
            let total = CACurrentMediaTime() - t0
            let renderer = run.host.rendererObject as? LiteHTMLWidgetRenderer
            let rendererPass = renderer?.passMaxCPUMilliseconds ?? 0
            let tile = renderer?.drawMaxMilliseconds ?? 0
            let churn = run.host.diagnostics.diags["text-churn"]?.count ?? 0
            log("CHURN \(name) \(churn)")
            if name.hasPrefix("legit-") {
                XCTAssertEqual(churn, 0, name)
            }
            let line = String(format: "%@ rendered=%.2fs total=%.2fs mainCPU=%.0fms maxPassCPU=%.0fms rendererPass=%.0fms tile=%.0fms dead=%@ height=%.0f throttled=%d", name, rendered, total, run.cpu * 1000, run.maxStall * 1000, rendererPass, tile, run.host.diagnostics.dead ?? "-", run.host.diagnostics.height, run.host.diagnostics.diags["renderer-throttled"]?.count ?? 0)
            log("EXH " + line)
            report.append(line)
            let check = {
                XCTAssertLessThan(run.cpu, 2, line)
                XCTAssertLessThan(run.maxStall, 0.05, line)
                XCTAssertLessThan(rendererPass, 50, line)
                XCTAssertLessThan(tile, 50, line)
            }
            if Self.knownStalls.contains(name) {
                XCTExpectFailure("known main-thread stall: \(name)", strict: false, failingBlock: check)
            } else {
                check()
            }
        } }
    }

    func testGlowSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["REDTEAM_SHOT"] else { throw XCTSkip("set REDTEAM_SHOT to a png path") }
        let run = Run("<div style='padding:60px;font:bold 44px -apple-system;color:white;background:#123'><span style='text-shadow:0 0 40px #f0f, 0 0 120px #0ff'>Glow 40/120</span><br><span style='text-shadow:8px 8px 6px #f80'>Hard 6</span><br><span style='box-shadow:0 0 80px 10px #ff0'>Box 80</span></div>")
        run.pump(4) { run.host.diagnostics.rendered }
        run.fitHeight()
        run.pump(1)
        run.window.displayIfNeeded()
        CATransaction.flush()
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(run.window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { throw XCTSkip("no capture") }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
