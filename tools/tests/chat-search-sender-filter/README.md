# Chat search sender filter regression

Run from the repository root on macOS with Python 3 and the installed Swift/XCTest toolchain:

```sh
python3 -I tools/tests/chat-search-sender-filter/run.py
python3 -I tools/tests/chat-search-sender-filter/run.py --revision c64a3ea7 --expect-regression
```

Optional `--output <new-directory>` retains `result.json`, `build.log`, and `tests.log`. The directory must not already exist, even if empty. The runner removes inherited `GIT_*` variables before invoking Git or Swift, reads a baseline with `git -C ... show`, and builds with two jobs in an automatically cleaned temporary package with local compiler/SwiftPM caches. There are no third-party dependencies to initialize/download, application launches, visible windows, account database operations, or server requests.

## Production source coverage

The runner extracts the real `CSearchContextState`, its equality implementation, `CSearchInteraction`, and `SearchStateQuery`; the peer-selection callback, token subscription, SearchInteractions closures, query signal/application pipeline, and header removal method from `ChatSearchHeader.swift`; token enum/publication and clear/backspace/edit/init/complete/emoji actions from `ChatSearchView.swift`; and the actual search-request closure from `ChatController.swift`. It also extracts SearchView's `setString`, `cancelSearch`, and the text-change prefix through query publication. Access modifiers are removed for the test target; these bodies are not reimplemented in the fixture. `result.json` records whole-source and extracted-block SHA-256 hashes.

Disclosed doubles in `Doubles.swift.in` provide the Telegram domain values, observer notification counter, text field/modal-free view shell, SearchInteractions container, synthetic engine, and a deterministic subset of SwiftSignalKit: ValuePromise, Signal, map/mapToSignal, cancellable delay, and disposables. The two-author engine fixture records the exact production request's `fromId`, query, thread and page; only then does it filter its three synthetic messages. The controllable queue covers cancellation before debounce and while a response is pending. These doubles do not prove actual SwiftSignalKit scheduling, AppKit rendering, the full header observer/mention popup, or real backend behavior. The NSTextView command argument is never presented or made first responder.

Placeholder-bearing `.swift.in` inputs are only converted to `.swift` inside the temporary package. No production decision body is copied into them. Display layout, token drawing, analytics and mention suggestions are outside this harness.

## Cases and negative control

Fourteen XCTest cases cover pure token/peer synchronization while retaining other state, incomplete sender editing, emoji replacement, completed sender stability, peer-only equality/notifications, query-preserving token removal with two authors in peer and thread locations, staged backspace and clear-button removal, debounced/in-flight request cancellation, replacement senders with the same display name, header reset, fresh pagination after removal, initial sender setup, and ordinary text search.

Fixed source passes all fourteen tests. Original `c64a3ea7` compiles successfully and fails twelve cases with 34 assertion failures: the hidden sender remains, the second author's matching message is absent, unchanged query/token removal does not refresh, or an old request survives sender editing. The valid completed-sender and initial/plain-search cases still pass. `--expect-regression` requires successful compilation followed by XCTest assertion failures; a compiler error cannot satisfy it.

Token removal retains the entered message query. The existing clear button still deliberately clears nonempty message text before removing the sender, and closing the entire header still clears its search state. Editing an incomplete sender cancels message results while the mention picker is active; it does not issue an unfiltered search for the typed sender name.
