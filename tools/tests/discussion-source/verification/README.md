# Navigate from comments to the original channel

macOS 27.0.1 (26A434), Xcode 27.1, Telegram 13.1.0 (283357), Debug arm64. Baseline/candidate native workspace builds succeeded, followed by a full build without diagnostic hooks (integration c5a43c3a).

## Public native scenario

Both runs start in the public Pavel Durov channel (@durov). A temporary launcher opens the real comments for [Telegram Info English post 2208](https://t.me/tginfoen/2208), calling the existing openReplyThread path with that actual channel message ID. It does not fabricate reply-thread data or alter the navigation stack. No comments were available on the inspected Durov posts, so Telegram Info English supplies the public source/comments pair.

1. Open the same external comments thread from Pavel Durov's channel.
2. Click the production glass Discussion title.
3. Before: Discussion remains open; Back returns to Pavel Durov. [Before, after clicking the title](before-public.png).
4. After: Telegram Info English opens at the original post. Back returns to Discussion; the next Back returns to Pavel Durov. [After, after clicking the title](after-public.png).

Both images retain the same public source post, so the destination change can be checked against the post thumbnail and heading. They are exact crops of native captures, not mockups. The same crop (1400x1000, x760/y0 in a 3024x1770 native capture) excludes the entire private sidebar, account controls, comment text, the partially visible commenter avatars, and diagnostic launchers. The Discussion root post is centered while the channel history post is left-aligned; this is the actual client layout. No full-window capture is included in this branch. No messages/reactions were sent, channels joined or server settings changed.

## Current source checks

Run `python3 tools/tests/discussion-source/run.py`. **44/44** checks pass. The immutable e18830989542a063dd66c5bdc4dbe6a70cbbd175 baseline passes **28/44**, exposing 16 failures; the committed before/after logs match this fixture. Both actual legacy and modern title action bodies and the source selector are extracted. Cases cover resolved-source priority, fallback, source-post focus, unknown sources, ordinary profiles, forum topics and reusing the existing source controller without a duplicate push.

Source-controller reuse now goes through the active controller's `ableToNextController` guard before truncating the stack. Cancel or a pending recording confirmation leaves the stack and source focus unchanged. Confirmation reuses the channel; a confirmation for a page that is no longer active is ignored. Collaborators model the asynchronous guard and actual stack/focus changes. This does not claim a new physical VoiceOver/microphone run; historical public-channel screenshots above cover the cross-channel flow.

Only the modern glass header was clicked in the historical full-client comparison. Another macOS version was unavailable. Build/profile overrides and diagnostic launchers are excluded from shipping target membership.

The title action also checks navigation.isLocked both before opening/reusing a source and after any asynchronous recording confirmation. Six additional cases cover both headers during a transition, a lock acquired while confirmation is open and successful reuse after unlocking. The superseded 28-case review log pair is removed; before-checks.txt and after-checks.txt are the only current logs.
