#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import os from 'node:os';

const here = path.dirname(fileURLToPath(import.meta.url));
const pkg = path.resolve(here, '..');
const chatsDir = path.join(pkg, 'Tests/HTMLBubblesTests/Fixtures/chats');
const catalogFile = path.join(pkg, 'Sources/HTMLBubbles/HTMLDemoCatalog.swift');
const scriptFile = path.resolve(pkg, '../HTMLScript/Sources/HTMLScript/HTMLScriptPrelude.swift');

const args = process.argv.slice(2);
const flag = name => args.includes(name);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
};
const onlyFile = option('--file', null);
const onlyCommand = option('--command', null);
const verbose = flag('--verbose');
const dump = flag('--dump');
const seedArg = Number(option('--seed', '7'));
const probeBin = option('--probe', null);
const probeCSS = option('--css', null);
const probeWidth = Number(option('--width', '600'));

const CALL_LIMIT_MS = 50;
const CPU_BUDGET_MS = 200;
const WARN_CALL_MS = 16;
const WARN_BUDGET_MS = 110;
const MIN_TIMER_MS = 50;
const FRAME_MS = 1000 / 60;
const MAX_TIMERS = 16;
const MAX_HTML = 256 * 1024;
const EXPECTED_TO_FAIL = new Set(['sandbox']);
const TRANSITIONS = ['fade', 'slide-left', 'slide-right', 'slide-up', 'slide-down', 'pop', 'none'];

function readPrelude() {
  const src = fs.readFileSync(scriptFile, 'utf8');
  const open = '#"""\n';
  const start = src.indexOf(open);
  const end = src.indexOf('\n"""#', start);
  if (start < 0 || end < 0) throw new Error('prelude not found in HTMLScriptPrelude.swift');
  return src.slice(start + open.length, end);
}

function parseConversation(id, text) {
  const messages = [];
  const actions = {};
  let actionId = null, actionMessages = [];
  let header = null, body = [];
  const flush = () => {
    if (header) {
      const content = body.join('\n').trim();
      const html = header.bare ? content : '<div class="widget">\n' + content + '\n</div>';
      const template = { sender: header.sender, html, bare: header.bare, line: header.line };
      if (actionId !== null) actionMessages.push(template); else messages.push(template);
    }
    header = null; body = [];
  };
  const flushAction = () => {
    if (actionId !== null) actions[actionId] = actionMessages;
    actionId = null; actionMessages = [];
  };
  text.split(/\r?\n/).forEach((line, n) => {
    if (line.startsWith('--- ') || line === '---') {
      flush();
      const tokens = line.slice(3).trim().split(/\s+/).filter(Boolean);
      header = { sender: tokens[0] || '', bare: tokens.slice(1).includes('bare'), line: n + 1 };
      return;
    }
    if (line.startsWith('@on ')) {
      flush(); flushAction();
      actionId = line.slice(4).trim();
      return;
    }
    if (header) body.push(line);
  });
  flush(); flushAction();
  return { id, messages, actions };
}

function parseCatalog() {
  const src = fs.readFileSync(catalogFile, 'utf8');
  const re = /\("([^"]+)",\s*"((?:[^"\\]|\\.)*)",\s*"([^"]+)",\s*\[([\d,\s]*)\]\)/g;
  const out = [];
  let m;
  while ((m = re.exec(src))) {
    out.push({ command: m[1], description: m[2], file: m[3], indices: m[4].split(',').map(s => s.trim()).filter(Boolean).map(Number) });
  }
  return out;
}

const scriptBlock = /<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi;
const styleBlock = /<style\b[^>]*>[\s\S]*?<\/style\s*>/gi;

function extractScripts(html) {
  const sources = [];
  let m;
  scriptBlock.lastIndex = 0;
  while ((m = scriptBlock.exec(html))) sources.push(m[1]);
  return sources.length ? sources.join('\n') : null;
}

function stripScripts(html) {
  return html.replace(scriptBlock, '').replace(/<\/?script\b[^>]*>/gi, '');
}

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const AUTO_CLOSE = new Set(['p', 'li', 'td', 'th', 'tr', 'option', 'dt', 'dd', 'thead', 'tbody', 'tfoot']);

const dataURI = /(["'])data:[^"']*\1|data:image\/svg\+xml[^"]*/g;

function checkMarkup(html) {
  const problems = [];
  const body = html.replace(dataURI, '""').replace(styleBlock, '').replace(/<!--[\s\S]*?-->/g, '');
  const stack = [];
  const tag = /<(\/?)([a-zA-Z][a-zA-Z0-9-]*)\b[^>]*?(\/?)>/g;
  let m;
  while ((m = tag.exec(body))) {
    const close = m[1] === '/', name = m[2].toLowerCase(), selfClose = m[3] === '/';
    if (VOID.has(name) || selfClose) continue;
    if (!close) { stack.push(name); continue; }
    const at = stack.lastIndexOf(name);
    if (at < 0) { problems.push(`stray </${name}>`); continue; }
    const dropped = stack.splice(at);
    dropped.shift();
    for (const d of dropped) if (!AUTO_CLOSE.has(d)) problems.push(`<${d}> not closed before </${name}>`);
  }
  for (const d of stack) if (!AUTO_CLOSE.has(d)) problems.push(`<${d}> never closed`);
  return [...new Set(problems)].slice(0, 6);
}

const UNSUPPORTED_CSS = [
  [/(^|[;{\s"'])transition\s*:/i, 'CSS transition (not supported, animate from the script)'],
  [/(^|[;{\s"'])transform\s*:/i, 'CSS transform (not supported)'],
  [/(^|[;{\s"'])opacity\s*:/i, 'CSS opacity (not supported, use rgba colours)'],
  [/@keyframes/i, '@keyframes (not supported)'],
  [/(^|[;{\s"'])animation\s*:/i, 'CSS animation (not supported)'],
  [/box-shadow\s*:/i, 'box-shadow (not supported)'],
  [/display\s*:\s*grid/i, 'display: grid (not supported, use flex or table)'],
  [/position\s*:\s*fixed/i, 'position: fixed (not supported)'],
  [/<input\b|<select\b|<textarea\b/i, 'form controls (not interactive, use data-action)'],
  [/\bonclick\s*=/i, 'onclick attribute (use data-action)'],
  [/<svg\b/i, 'inline <svg> (not rendered, use data:image/svg+xml in <img>)'],
];

function cssWarnings(html) {
  const out = [];
  html = html.replace(dataURI, '""');
  for (const [re, text] of UNSUPPORTED_CSS) if (re.test(html)) out.push(text);
  return out;
}

const CHAT_LINK = /href\s*=\s*["']chat:(run|send|toggle|select)\b[^"']*["']/gi;

function chatLinks(html) {
  const found = new Set();
  let m;
  CHAT_LINK.lastIndex = 0;
  while ((m = CHAT_LINK.exec(html))) found.add('chat:' + m[1]);
  return [...found];
}

function decodeEntities(s) {
  return s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}

function findActions(html) {
  const out = [];
  const seen = new Set();
  const tag = /<[a-zA-Z][^>]*\bdata-action\s*=\s*(["'])(.*?)\1[^>]*>/g;
  let m;
  while ((m = tag.exec(html))) {
    const name = decodeEntities(m[2]);
    const v = /\bdata-value\s*=\s*(["'])(.*?)\1/.exec(m[0]);
    const value = v ? decodeEntities(v[2]) : undefined;
    const key = name + '\u0000' + (value ?? '');
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ name, value: value === '' ? undefined : value });
  }
  return out;
}

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}

class Runner {
  constructor(prelude, source, staticHTML) {
    this.clock = 1_700_000_000_000;
    this.timers = new Map();
    this.frameRequested = false;
    this.needsRender = false;
    this.log = [];
    this.errors = [];
    this.stopped = null;
    this.transitions = new Map();
    this.pendingTransition = null;
    this.renders = 0;
    this.maxCall = 0;
    this.maxWindow = 0;
    this.windowStart = 0;
    this.windowUsed = 0;
    this.maxLength = 0;
    this.html = null;
    this.styles = (stripScripts(staticHTML).match(styleBlock) || []).join('\n');

    const runner = this;
    const RealDate = Date;
    class FakeDate extends RealDate {
      constructor(...a) { if (a.length) super(...a); else super(runner.clock); }
      static now() { return runner.clock; }
    }
    const native = {
      schedule(id, ms, repeat) {
        if (runner.stopped) return;
        const interval = Math.max(MIN_TIMER_MS, ms);
        runner.timers.set(id, { due: runner.clock + interval, interval, repeat });
      },
      cancel(id) { runner.timers.delete(id); },
      update() { runner.needsRender = true; },
      requestFrame() { runner.frameRequested = true; },
      log(level, text) { runner.log.push(level === 'log' ? text : `[${level}] ${text}`); },
      transition(kind) { runner.pendingTransition = kind === 'none' ? null : kind; runner.pendingTransitionTime = runner.clock; },
      copy(text) { runner.copied = text; },
    };
    this.context = vm.createContext({ __native: native, Date: FakeDate }, { microtaskMode: 'afterEvaluate' });
    this.context.globalThis = this.context;
    this.call('__hooks = (' + prelude.trim() + ')(__native, ' + MAX_TIMERS + ', ' + MAX_HTML + ', ' + JSON.stringify(TRANSITIONS) + ')', 'prelude');
    this.call(source, 'message.js', true);
    this.render();
  }

  call(code, label, isSource) {
    if (this.stopped) return undefined;
    const t0 = performance.now();
    let result, error = null;
    try {
      result = vm.runInContext(code, this.context, { filename: isSource ? 'message.js' : label, timeout: 250 });
    } catch (e) {
      error = e;
    }
    const elapsed = performance.now() - t0;
    this.maxCall = Math.max(this.maxCall, elapsed);
    if (this.clock - this.windowStart >= 1000) { this.windowStart = this.clock; this.windowUsed = 0; }
    this.windowUsed += elapsed;
    this.maxWindow = Math.max(this.maxWindow, this.windowUsed);
    if (elapsed > CALL_LIMIT_MS) { this.stop(`a call (${label}) ran ${elapsed.toFixed(1)} ms`); return undefined; }
    if (this.windowUsed > CPU_BUDGET_MS) { this.stop(`used ${this.windowUsed.toFixed(0)} ms of CPU in one second`); return undefined; }
    if (error) {
      const msg = (error && error.stack ? String(error.stack).split('\n').slice(0, 3).join(' | ') : String(error)).slice(0, 400);
      this.errors.push(`${label}: ${msg}`);
      return undefined;
    }
    return result;
  }

  stop(reason) { this.stopped = reason; this.timers.clear(); this.frameRequested = false; }

  render() {
    this.needsRender = false;
    this.renders++;
    const out = this.call('__hooks.callRender()', 'render()');
    if (this.pendingTransition && this.clock - this.pendingTransitionTime > 800) this.pendingTransition = null;
    if (typeof out === 'string') {
      const html = this.styles + stripScripts(out);
      if (html !== this.html) {
        const transition = this.pendingTransition;
        this.pendingTransition = null;
        if (transition && this.html !== null) this.transitions.set(transition, (this.transitions.get(transition) || 0) + 1);
        this.html = html;
        this.maxLength = Math.max(this.maxLength, out.length);
      }
    } else if (out === null && this.html === null) {
      this.errors.push('render() is not defined');
    }
  }

  advance(ms) {
    const end = this.clock + ms;
    while (this.clock < end && !this.stopped) {
      const step = Math.min(FRAME_MS, end - this.clock);
      this.clock += step;
      const due = [...this.timers.entries()].filter(([, t]) => t.due <= this.clock).sort((a, b) => a[1].due - b[1].due);
      for (const [id, t] of due) {
        if (!this.timers.has(id)) continue;
        if (t.repeat) t.due += t.interval; else this.timers.delete(id);
        this.call(`__hooks.fire(${id})`, 'timer');
        this.needsRender = true;
      }
      if (this.frameRequested) {
        this.frameRequested = false;
        this.call('__hooks.frame()', 'requestAnimationFrame callback');
        this.needsRender = true;
      }
      if (this.needsRender) this.render();
    }
  }

  click(action) {
    const value = action.value === undefined ? 'undefined' : JSON.stringify(action.value);
    this.call(`__hooks.callAction(${JSON.stringify(action.name)}, ${value})`, `onAction(${action.name}${action.value !== undefined ? ', ' + action.value : ''})`);
    this.render();
  }

  get actions() { return this.html ? findActions(this.html) : []; }
}

function exercise(prelude, html, seed) {
  const source = extractScripts(html);
  if (!source) return null;
  const runner = new Runner(prelude, source, html);
  const random = rng(seed);
  const initialActions = runner.actions.length;
  const everSeen = new Set();
  const snapshots = [];
  const note = () => {
    for (const a of runner.actions) everSeen.add(a.name + '\u0000' + (a.value ?? ''));
    if (runner.html && snapshots[snapshots.length - 1] !== runner.html) snapshots.push(runner.html);
  };
  note();
  runner.advance(2500);
  note();
  let clicks = 0;
  for (const action of runner.actions.slice(0, 40)) {
    runner.click(action); clicks++;
    runner.advance(900);
    note();
  }
  for (let i = 0; i < 160 && !runner.stopped; i++) {
    const available = runner.actions;
    if (!available.length) { runner.advance(500); continue; }
    runner.click(available[Math.floor(random() * available.length)]); clicks++;
    runner.advance(random() < 0.25 ? 60 : 120 + random() * 1300);
    note();
  }
  runner.advance(4000);
  note();
  return { runner, initialActions, distinctActions: everSeen.size, clicks, snapshots };
}

function probeLayout(label, snapshots) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'html-bubble-'));
  const files = snapshots.map((html, i) => {
    const file = path.join(dir, `${i}.html`);
    fs.writeFileSync(file, '<body class="lc-light lc-in">' + html);
    return file;
  });
  let out = '';
  try {
    out = execFileSync(probeBin, [probeCSS, String(probeWidth), ...files], { encoding: 'utf8', timeout: 60000 });
  } catch (e) {
    return { error: `layout probe failed: ${String(e.message).split('\n')[0]}` };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
  let maxW = 0, maxH = 0, minH = Infinity;
  for (const line of out.trim().split('\n')) {
    const [, w, h] = line.split(' ');
    maxW = Math.max(maxW, Number(w)); maxH = Math.max(maxH, Number(h)); minH = Math.min(minH, Number(h));
  }
  return { maxW, maxH, minH, count: files.length };
}

function main() {
  const prelude = readPrelude();
  const catalog = parseCatalog();
  const conversations = new Map();
  for (const f of fs.readdirSync(chatsDir).filter(f => f.endsWith('.chat')).sort()) {
    const id = f.replace(/\.chat$/, '');
    conversations.set(id, parseConversation(id, fs.readFileSync(path.join(chatsDir, f), 'utf8')));
  }

  let failures = 0, warnings = 0;
  const rows = [];
  for (const entry of catalog) {
    if (onlyFile && entry.file !== onlyFile) continue;
    if (onlyCommand && entry.command !== onlyCommand) continue;
    const conversation = conversations.get(entry.file);
    if (!conversation) { console.log(`✗ /${entry.command}: no ${entry.file}.chat`); failures++; continue; }
    entry.indices.forEach((index, k) => {
      const label = `/${entry.command}${entry.indices.length > 1 ? `#${k}` : ''} (${entry.file}[${index}])`;
      const message = conversation.messages[index];
      const problems = [], notes = [];
      if (!message) { console.log(`✗ ${label}: index out of range (${conversation.messages.length} messages)`); failures++; return; }
      const isIntro = entry.indices.length > 1 && k < entry.indices.length - 1 && !/<script/i.test(message.html);
      const links = chatLinks(message.html);
      if (links.length) problems.push(`uses ${links.join(', ')} — clicks must update the card in place`);
      for (const w of cssWarnings(stripScripts(message.html).replace(scriptBlock, ''))) notes.push(w);
      const result = isIntro ? null : exercise(prelude, message.html, seedArg + index);
      if (!isIntro && !result) problems.push('no <script> — every demo card must be a scripted mini-app');
      if (result) {
        const r = result.runner;
        if (r.stopped) problems.push(`sandbox stopped it: ${r.stopped}`);
        for (const e of [...new Set(r.errors)].slice(0, 4)) problems.push(e);
        if (r.errors.length > 4) problems.push(`…and ${r.errors.length - 4} more errors`);
        const logErrors = r.log.filter(l => l.startsWith('[error]'));
        for (const e of logErrors.slice(0, 2)) problems.push('console ' + e);
        if (r.html) {
          const renderedLinks = chatLinks(r.html);
          if (renderedLinks.length) problems.push(`render() outputs ${renderedLinks.join(', ')} — clicks must update the card in place`);
          for (const p of checkMarkup(r.html)) notes.push('markup: ' + p);
          for (const w of cssWarnings(r.html)) if (!notes.includes(w)) notes.push(w);
        }
        if (result.distinctActions === 0) problems.push('no data-action anywhere — the card must react to clicks');
        if (r.maxCall > WARN_CALL_MS) notes.push(`slowest call ${r.maxCall.toFixed(1)} ms`);
        if (r.maxWindow > WARN_BUDGET_MS) notes.push(`peak CPU ${r.maxWindow.toFixed(0)} ms/s`);
        if (r.maxLength > 60_000) notes.push(`render() up to ${(r.maxLength / 1024).toFixed(0)} KB`);
        if (probeBin && probeCSS && result.snapshots.length) {
          const layout = probeLayout(label, result.snapshots);
          if (layout.error) notes.push(layout.error);
          else {
            if (layout.maxW > 450) notes.push(`layout up to ${layout.maxW}px wide (over 450)`);
            if (layout.maxH > 1300) notes.push(`layout up to ${layout.maxH}px tall`);
            if (verbose) console.log(`  layout ${label}: ${layout.count} states, width ≤ ${layout.maxW}, height ${layout.minH}–${layout.maxH}`);
          }
        }
        rows.push({ label, renders: r.renders, actions: result.distinctActions, clicks: result.clicks, transitions: [...r.transitions.keys()].join(',') || '-', maxCall: r.maxCall, peak: r.maxWindow });
        if (dump) console.log(`--- ${label} final HTML ---\n${r.html}\n`);
        if (verbose && r.log.length) console.log(`  log: ${r.log.slice(-5).join(' | ')}`);
      }
      if (problems.length && EXPECTED_TO_FAIL.has(entry.command)) {
        if (verbose) console.log(`• ${label}: stopped on purpose (${problems[0]})`);
      } else if (problems.length) {
        failures++;
        console.log(`✗ ${label}`);
        for (const p of problems) console.log(`    ${p}`);
      } else if (notes.length) {
        warnings++;
        console.log(`△ ${label}`);
      } else if (verbose) {
        console.log(`✓ ${label}`);
      }
      for (const n of notes) console.log(`    note: ${n}`);
    });
  }
  if (verbose && rows.length) {
    console.log('\ncommand'.padEnd(46) + 'renders actions clicks  maxms  peak  transitions');
    for (const r of rows) console.log(`${r.label.padEnd(45)} ${String(r.renders).padStart(7)} ${String(r.actions).padStart(7)} ${String(r.clicks).padStart(6)} ${r.maxCall.toFixed(1).padStart(6)} ${r.peak.toFixed(0).padStart(5)}  ${r.transitions}`);
  }
  console.log(`\n${failures ? '✗' : '✓'} ${failures} failing, ${warnings} with notes`);
  process.exit(failures ? 1 : 0);
}

main();
