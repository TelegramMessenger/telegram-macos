# Read/unread actions in search

`python3 tools/tests/search-unread/run.py` compiles actual menu factories/decision methods with controlled engine and Postbox snapshots. 46 checks cover read/manual-mark round trips, group membership, archives, namespace exclusions, ordinary and forum modes, Saved Messages and top-peer removal.

Secret-chat peers have no read action. Ordinary peers use engine PeerReadCounters; forums handled as regular chats use the peer-level CombinedPeerReadState, because thread counters omit their manual unread mark. Forums not handled as regular chats only offer Mark as Read while unread. The fixture independently models thread counters and raw peer marks and executes the menu handlers through a complete mark/unmark/reopen round trip.

Before/After images show real production ContextMenuItems in an isolated AppKit popup, not the custom glass renderer. Historical native reports belong to the earlier 0884189 implementation and are not a rerun of the current forum/diagnostic changes. Old numeric check outputs and status-window images have been removed to avoid presenting them as current results. No chat list, account avatar or private message is published.

The full-client diagnostic builder works in a disposable APFS copy. Its preview and toggle subscriptions are separate; toggle runs are single-flight. The retained reusable diagnostic window has isReleasedWhenClosed=false, preventing a closed-window dangling reference. A failed check cannot report successful restoration. Diagnostic sources are committed under tools, not shipping members.

Only macOS 27.0.1 Debug arm64 full integration builds are available. The current forum round trip is a controller/Postbox fixture, not a new live server forum test. No production account is modified by the source tests.

The diagnostic fixture now weakly stores its account context and checks isCurrent before opening, previewing or starting a toggle. A primary-account subscription closes the old window as soon as accounts switch and drops menu callbacks; installing a launcher for another context also closes old evidence; closing clears the global owner. A running toggle alone retains its operation context until the restoration/check chain finishes, then clears that context and its subscription. This keeps account-switch cleanup from interrupting restoration of a mark already changed by the test. Idle fixtures and launcher closures do not keep an old account alive.

Saved Messages sub-chat search explicitly excludes the read/unread action before reading another peer's counters. The search factory forwards its target to the shared helper; the ordinary Saved Messages row remains supported in global search. Three checks verify no action, counter access or read receipt route for sub-chats.

The diagnostic toggle now holds a process-wide owner lease through restoration, independently of the window/global evidence variable. Six compiled lease checks cover closing/reopening, rejecting a concurrent run, rejecting an unrelated release and releasing the original owner after finish. A closed window can no longer admit a second overlapping toggle.
