import Foundation

public enum HTMLBubblePage {
    private static let styleRegex = try! NSRegularExpression(pattern: "<style\\b[^>]*>[\\s\\S]*?</style\\s*>", options: [.caseInsensitive])
    private static let scriptRegex = try! NSRegularExpression(pattern: "<script\\b([^>]*)>([\\s\\S]*?)</script\\s*>", options: [.caseInsensitive])

    public static func write(source: String, appearance: HTMLBubbleAppearance) -> URL? {
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        let styles = styleRegex.matches(in: source, range: range).map { ns.substring(with: $0.range) }.joined(separator: "\n")
        var scripts: [String] = []
        var usesThree = false
        for match in scriptRegex.matches(in: source, range: range) {
            if ns.substring(with: match.range(at: 1)).range(of: "app:three", options: .caseInsensitive) != nil {
                usesThree = true
            } else {
                scripts.append(ns.substring(with: match.range(at: 2)))
            }
        }
        let withoutStyles = styleRegex.stringByReplacingMatches(in: source, range: range, withTemplate: "")
        let body = scriptRegex.stringByReplacingMatches(in: withoutStyles, range: NSRange(location: 0, length: (withoutStyles as NSString).length), withTemplate: "")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HTMLBubblePages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if usesThree {
                let three = directory.appendingPathComponent("three.js")
                if !FileManager.default.fileExists(atPath: three.path) {
                    guard let library = HTMLBubbleLibraries.source(named: "three") else {
                        return nil
                    }
                    try library.write(to: three, atomically: true, encoding: .utf8)
                }
            }
            let page = """
            <!doctype html>
            <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <title>HTML</title>
            <style>\(appearance.css)</style>
            \(styles)
            <style>\(pageStyle)</style>
            </head>
            <body class="\(appearance.dark ? "lc-dark" : "lc-light") lc-in lc-page"><div id="lc-root">\(body)</div>
            \(usesThree ? "<script src=\"three.js\"></script>" : "")
            <script>\(pageRuntime)</script>
            <script>\(scripts.joined(separator: "\n"))</script>
            <script>__lcStart(typeof render === 'function' ? render : null, typeof onAction === 'function' ? onAction : null, typeof onPointer === 'function' ? onPointer : null, typeof onKey === 'function' ? onKey : null, typeof onFocus === 'function' ? onFocus : null);</script>
            </body></html>
            """
            let url = directory.appendingPathComponent("page-\(UInt(bitPattern: source.hashValue)).html")
            try page.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static let pageStyle = """
    html, body { margin: 0; height: 100%; overflow: hidden; }
    #lc-root { position: fixed; left: 0; top: 0; right: 0; bottom: 0; display: flex; }
    #lc-root > * { flex: 1 1 auto; display: flex; flex-direction: column; width: auto !important; max-width: none !important; margin: 0 !important; border: 0 !important; border-radius: 0 !important; }
    #lc-root [data-3d] { flex: 1 1 auto; height: auto !important; min-height: 160px; margin: 0 !important; border-radius: 0 !important; position: relative; overflow: hidden; }
    #lc-root [data-3d] > canvas { position: absolute; left: 0; top: 0; width: 100%; height: 100%; display: block; outline: none; }
    """

    private static let pageRuntime = #"""
    (function () {
      'use strict';
      const T = window.THREE;
      const keys = new Set(['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'w', 'a', 's', 'd', 'W', 'A', 'S', 'D', ' ', 'Enter']);
      let canvas = null, three = null, hooks = null, lastHTML = null, observed = null, queued = false, focused = false;
      const ease = Object.freeze({
        linear: t => t,
        inQuad: t => t * t,
        outQuad: t => t * (2 - t),
        inOutQuad: t => t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2,
        outCubic: t => 1 - Math.pow(1 - t, 3),
        inOutCubic: t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2,
        outQuint: t => 1 - Math.pow(1 - t, 5),
        outExpo: t => t === 1 ? 1 : 1 - Math.pow(2, -10 * t),
        inOutSine: t => -(Math.cos(Math.PI * t) - 1) / 2,
        outBack: t => 1 + 2.70158 * Math.pow(t - 1, 3) + 1.70158 * Math.pow(t - 1, 2),
        spring: t => t === 0 || t === 1 ? t : 1 - Math.exp(-7 * t) * Math.cos(9.5 * t),
      });
      const animate = (duration, onFrame, easing = ease.inOutCubic) => new Promise(resolve => {
        let start = -1;
        const step = () => {
          const time = performance.now();
          if (start < 0) start = time;
          const t = Math.min(1, (time - start) / Math.max(1, duration));
          onFrame(easing(t), t);
          if (t < 1) requestAnimationFrame(step); else resolve();
        };
        onFrame(easing(0), 0);
        requestAnimationFrame(step);
      });
      Object.assign(window, {
        ease,
        animate,
        lerp: (a, b, t) => a + (b - a) * t,
        clamp: (x, lo, hi) => Math.min(hi, Math.max(lo, x)),
        esc: v => String(v === undefined || v === null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'),
        sleep: ms => new Promise(resolve => setTimeout(resolve, ms)),
        transition: () => {},
        update: () => schedule(),
        copyText: text => { try { navigator.clipboard.writeText(String(text)); } catch (e) {} },
      });

      const fit = stage => {
        if (!three || !stage) return;
        const r = stage.getBoundingClientRect();
        three.setPixelRatio(window.devicePixelRatio || 1);
        three.setSize(Math.max(1, Math.round(r.width)), Math.max(1, Math.round(r.height)), false);
      };
      const resizer = typeof ResizeObserver === 'function' ? new ResizeObserver(entries => { for (const e of entries) fit(e.target); }) : null;
      window.addEventListener('resize', () => fit(observed));

      const place = () => {
        const stage = document.querySelector('#lc-root [data-3d]');
        if (!stage || !canvas) return;
        if (canvas.parentNode !== stage) { stage.textContent = ''; stage.appendChild(canvas); }
        if (observed !== stage) {
          if (resizer) { resizer.disconnect(); resizer.observe(stage); }
          observed = stage;
        }
        fit(stage);
      };

      const refresh = () => {
        if (!hooks || !hooks.render) return;
        let html;
        try { html = hooks.render(); } catch (e) { console.error(e); return; }
        if (typeof html !== 'string' || html === lastHTML) return;
        lastHTML = html;
        document.getElementById('lc-root').innerHTML = html;
        place();
      };

      function schedule() {
        if (queued) return;
        queued = true;
        Promise.resolve().then(() => { queued = false; refresh(); });
      }

      const nativeFrame = window.requestAnimationFrame.bind(window);
      window.requestAnimationFrame = fn => nativeFrame(t => { fn(t); schedule(); });

      if (T && T.WebGLRenderer) {
        const Base = T.WebGLRenderer;
        T.WebGLRenderer = class extends Base {
          constructor(parameters) {
            super(Object.assign({}, parameters, { antialias: true }));
            this.isSupported = true;
            this.setPixelRatio(window.devicePixelRatio || 1);
            this.setSize(1, 1, false);
            canvas = this.domElement;
            three = this;
          }
          setCornerRadius() {}
        };
        T.MetalRenderer = T.WebGLRenderer;
      }

      const focus = () => {
        if (focused || !hooks || !hooks.onFocus) return;
        focused = true;
        hooks.onFocus(true);
      };

      document.addEventListener('pointerdown', e => {
        const stage = e.target.closest ? e.target.closest('[data-3d]') : null;
        if (!stage || !hooks) return;
        const r = stage.getBoundingClientRect();
        focus();
        if (hooks.onPointer) hooks.onPointer(e.clientX - r.left, e.clientY - r.top);
        schedule();
      });
      document.addEventListener('click', e => {
        const target = e.target.closest ? e.target.closest('[data-action]') : null;
        if (!target || !hooks || !hooks.onAction) return;
        e.preventDefault();
        hooks.onAction(target.getAttribute('data-action'), target.hasAttribute('data-value') ? target.getAttribute('data-value') : undefined);
        schedule();
      });
      document.addEventListener('keydown', e => {
        if (!hooks || !hooks.onKey || e.metaKey || e.ctrlKey || e.altKey || !keys.has(e.key)) return;
        e.preventDefault();
        focus();
        hooks.onKey(e.key.length === 1 ? e.key.toLowerCase() : e.key);
        schedule();
      });

      window.__lcStart = (render, onAction, onPointer, onKey, onFocus) => {
        hooks = { render, onAction, onPointer, onKey, onFocus };
        refresh();
        const named = document.querySelector('#lc-root [data-title]');
        const heading = document.querySelector('#lc-root .title');
        document.title = named ? named.getAttribute('data-title') : heading ? heading.textContent : 'HTML';
      };
    })();
    """#
}
