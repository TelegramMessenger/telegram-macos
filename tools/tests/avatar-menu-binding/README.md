# Avatar menu binding

Run `python3 -I tools/tests/avatar-menu-binding/run.py` on macOS with Xcode and the repository's native dependencies built. Additional arguments are forwarded to `xcodebuild`, for example `-derivedDataPath /path/to/build`.

The runner invokes `packages/ChatUI/Tests/run-tests.sh`, filtered to `ChatAvatarMenuBindingTests`. It compiles the actual ChatUI module and unchanged test source against real TelegramCore, Postbox and TGUIKit dependencies. There are no replacement peer factories or model adapters; missing dependencies fail the run rather than falling back to synthetic types.

Coverage includes title/photo/boost/member-count refreshes without rebinding, same-context rebinding, story and premium-video author contexts, unrelated admin-rights and slow-mode changes, effective ban/promote/tag permissions, creator status, participation, chat kind, monoforum status, missing chat data, author/row/message/account/interaction/mode/thread/story changes, nested actions, latest-row liveness and removal. These are menu-binding tests; they do not exercise live row layout, video playback or network moderation.

The previous adapter-based runner and its `--negative-control` option have been removed because replacing test constructors hid dependency API compilation errors.
