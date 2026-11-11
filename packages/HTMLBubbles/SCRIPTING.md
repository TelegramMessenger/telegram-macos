# Scripted HTML messages

An HTML message is static HTML, optional `<style>` blocks and an optional `<script>`. With a script the message becomes a small app: the script owns the state, `render()` turns it into HTML, and clicks call `onAction`. Every click updates the same bubble in place; nothing is sent to the chat.

```html
<style>
  .ctr { width: 300px; }
</style>
<div class="card pad ctr"><b>Counter</b></div>
<script>
let count = 0;
const pop = { scale: 1 };

function render() {
  return `<div class="card pad ctr">
    <div style="font-size: ${Math.round(40 * pop.scale)}px">${count}</div>
    <button data-action="add" data-value="1">+</button>
  </div>`;
}

function onAction(name, value) {
  count += Number(value);
  pop.scale = 1.4;
  tween(pop, { scale: 1 }, 380, ease.outBack);
}
</script>
```

## Lifecycle

- The static HTML before the script is the fallback. It shows only if the script can't run, so keep it short.
- The script runs once when the message is created. `render()` is called right away, again after every `onAction`, after every timer, every animation frame, and after `update()`.
- `render()` returns the whole body. The `<style>` blocks of the message are kept, so put CSS there, not in `render()`.
- `onAction(name, value)` runs when the user clicks an element with `data-action`, or anything inside it. `value` is its `data-value` string, or `undefined`. It can be `async`.
- Scripts pause while the bubble is off screen: timers and frames wait and catch up when it's visible again.

## Animation

litehtml has no CSS transitions, transforms or opacity. Two kinds of animation are available:

**Script animation**, for values that move: sizes, positions, colours, numbers. The script changes its state on every frame (up to 60 per second) and `render()` draws it.

| API | Use |
|---|---|
| `animate(ms, (eased, t) => {}, easing)` | Calls back every frame, resolves when done |
| `tween(object, { key: to }, ms, easing)` | Moves numeric fields of an object toward the targets, resolves when done. A newer tween of the same field wins |
| `requestAnimationFrame(fn)` | One frame, `fn(now)` |
| `ease.linear, inQuad, outQuad, inOutQuad, outCubic, inOutCubic, outQuint, outExpo, inOutSine, outBack, inOutBack, outElastic, outBounce, spring` | Easing curves, `t` in 0…1 |
| `lerp(a, b, t)`, `clamp(x, lo, hi)` | Numbers |
| `mix(colorA, colorB, t)`, `alpha(color, a)` | Colours, `#rgb`, `#rrggbb`, `rgb()`, `rgba()` or `[r, g, b, a]`, returns `rgba(...)` |
| `sleep(ms)` | Promise that resolves after `ms` |
| `performance.now()` | Milliseconds since the script started |

**Bubble transition**, for content that is swapped: another tab, the next step, a confirmation, an expanded section. Call `transition(kind)` before changing the state. The next change is drawn over the old one with a native animation, and the bubble's height animates to the new size. Only the part of the card that changed moves: the old and new drawings are compared and the animation is clipped to the area that differs.

| Kind | Looks like |
|---|---|
| `fade` | Crossfade, the default |
| `slide-left` | Forward: the new content comes in from the right |
| `slide-right` | Back: the new content comes in from the left |
| `slide-up`, `slide-down` | Vertical, for lists and steps |
| `pop` | The new content springs in from 94%, for results and confirmations |
| `move` | Magic move: elements with a `data-key` fly from their old place and size to the new one, new keys fade and scale in, removed keys fade out. Moved elements whose content changed cross-fade on the way. For reordered lists, sorted tables, moved chips and cards |
| `none` | Cancels a transition asked for earlier in the same action |

`move` matches elements by their `data-key`, which must be unique in the bubble. A keyed element inside another moving keyed element rides along inside it. If there are no keys, more than 32 keyed elements, Reduce Motion is on, or the bubble renders on the GPU engine, `move` falls back to `fade`.

Don't call `transition()` on every frame of a script animation: it is for one discrete change.

## Other globals

- `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`: at least 50 ms, at most 16 at a time
- `esc(text)` escapes text for HTML. Use it for anything that isn't a literal in the script
- `copyText(text)` puts text on the clipboard. It works only while `onAction` runs, before its first `await`
- `update()` asks for a `render()` without an action or a timer
- `console.log/info/warn/error`: shown by Script Log… in the message context menu

## Limits

- One call may run 50 ms; past that the script stops and the card shows a Restart link
- A message may use about 200 ms of CPU per second. Past that its timers and frames wait until the quota frees up (twidget's CPU quota); clicks always run
- One call may grow memory by 128 MB at most; past that the script stops
- Scripts run on their own thread, never the main thread. All messages share one frame clock at 60 fps, and hidden messages get no timers or frames
- The HTML that `render()` returns is sanitized with twidget's rules before litehtml draws it: `<script>`, `<iframe>`, `<object>`, `<link>`, `<meta>` and similar tags are dropped, unknown tags become `<span>`, `on*` attributes are removed, links may use `https:`, `http:`, `chat:`, `tg:`, `mailto:` and `#`, and images may use `data:image/…` and `icon:`. CSS loses `@import`, `@font-face`, `behavior` and `expression()`, and `url()` follows the image rule. Elements nest at most 256 deep, a message has at most 20,000 elements and a table at most 200,000 cells
- `render()` may return 256 KB of HTML
- No network, no `fetch`, no `WebAssembly`, no DOM. `document` and `window` don't exist

## What litehtml draws

Supported: block, inline, inline-block, flex (`justify-content`, `align-items`, `flex-wrap`, `flex-grow`), tables with `rowspan` and `colspan`, `position: relative` and `absolute`, `overflow: hidden`, `float`, `border-radius`, borders, `rgba()` colours, `linear-gradient`, `radial-gradient`, `conic-gradient`, `:hover`, `:active`, `:first-child`, `:nth-child`, `text-transform`, `white-space`, `line-height`.

Not supported: transitions, animations, `transform`, `opacity`, `box-shadow`, `text-shadow`, `letter-spacing`, `filter`, `display: grid`, `position: fixed`, form controls, inline `<svg>`. Fade with `rgba()` colours instead of `opacity`; move with `left`, `top`, `margin` or `width` instead of `transform`.

Images (the full rules are in twidget's `docs/WIDGET_ASSETS.md`; a message stays one self-contained HTML document):
- `icon:name?size=24&color=34c759&weight=bold`: an icon from twidget's built-in set (Phosphor Icons). `size` is the square box in px (default 20, 1–512), `color` is 3, 4, 6 or 8 hex digits (default `404045`), `weight` is `light`, `regular`, `bold` or `fill`. A `-fill` name is the filled variant: `icon:heart-fill`. Unknown names draw a placeholder. The names are listed in twidget's `Sources/TwidgetAssets/icons.json`
- `data:image/svg+xml,<svg ...>`: generated or embedded SVG, single quotes inside, `%23` for `#`. Fine for pictures, charts, rings and sparklines; a new SVG on every frame works for short animations. SVG images are drawn by the same sanitized SVG renderer as inline SVG: no scripts, no external references
- `data:image/png;base64,…` (also JPEG, GIF, WebP): embedded bitmaps
- `sf:` (SF Symbols) and `app:` (pictures the macOS app draws) still work on Apple platforms for old messages, but other clients can't show them. Use `icon:` and `data:` instead

## Theme

The body has `lc-light` or `lc-dark`, and `lc-in` or `lc-out`. Prefer the kit classes, they follow the theme:

| Class | |
|---|---|
| `card`, `pad`, `panel` | Card with the chat background and border, padding, grey panel |
| `fg`, `muted`, `small`, `tiny`, `caps` | Text colours and sizes |
| `row`, `between`, `grow`, `center`, `right`, `sep`, `nowrap` | Layout |
| `t-blue`, `t-green`, `t-red`, `t-orange`, `t-purple`, `t-teal` | Accent text |
| `badge` with `blue`, `green`, `red`, `orange`, `purple` | Pills |
| `button`, `button.primary`, `btn`, `btn primary`, `btn success`, `btn danger`, `chip` | Controls, with hover and pressed states |
| `av`, `bar`, `kbd` | Avatar circle, progress bar, key cap |

A card with its own colours should also look right on `.lc-dark`: add `.lc-dark .my-card { ... }` overrides.

## Fullsize or bubble

A message whose outermost element has the `widget` class shows inside a bubble with the name and time. Anything else shows fullsize, without a bubble. This is decided from the message source, not from `render()`.

## Checking

`node packages/HTMLBubbles/Tools/check-demos.mjs` runs every demo message the bot can send with the real prelude from `packages/HTMLScript/Sources/HTMLScript/HTMLScriptPrelude.swift`: it renders, clicks every `data-action` it finds, runs timers and frames, and reports errors, slow calls, `chat:` links, unbalanced tags and CSS litehtml can't draw. `--file 06-trip-lisbon`, `--command poll`, `--verbose` and `--dump` narrow it down.
