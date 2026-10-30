# Chat header network status

```sh
python3 -I tools/tests/header-network-status/run.py --signal-kit /path/to/SSignalKit
```

The runner compiles the isolated branch's actual TGUIKit `TextView`, `TextViewLayout`, theme/font helpers and AppKit views. It extracts the production `PeerStatusStringResult`, header connection observer, title/status computation, text update and text-positioning layout. Telegram peer/presentation models, presence timing, activity data and the outer glass container are adapters; no account, network or full application is involved.

Cases cover:

- Saved Messages' empty subtitle changing to Waiting for Network in light and dark palettes.
- A connection change scheduling the two-line layout, with status below the title and outside the avatar area.
- Recovery recentering the title and subsequent connection losses.
- Waiting, connecting, proxy connecting and updating using the gray theme color, while ordinary online presence retains its accent.
- Pinned/scheduled empty subtitles, activity visibility, constrained widths, peer clearing and repeated identical connection states.

Use `--source-revision de608bb0` to run the same fixture against the pre-fix header and status implementation. On 2026-10-30, the fixed implementation passes all nine XCTest cases; the same fixture compiles against `de608bb0` and fails eight cases with 65 assertion failures, including missing/incorrect foreground colors and subtitle frames remaining at the origin. These are behavioral failures, not build/dependency errors.

The scratch package copies only the required native UI dependencies and removes its sources and build outputs when the run ends. This is a native text/control regression harness, not a full ChatUI/application build or an integrated visual test of the glass header. The scratch package targets macOS 12 for the installed Xcode toolchain; no deployment setting is changed in the branch.
