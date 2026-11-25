# HTMLBubbles tests

The tests link TelegramCore, which needs the prebuilt mozjpeg that Xcode links into the app:

```sh
swift build --build-tests -Xlinker ../../core-xprojects/Mozjpeg/build/arm64/libjpeg.a
swift test --skip-build
```

The demo chats' widgets and scripted conversations live in `Fixtures/` and ship only with the tests; the app bundles none of them. `DemoFixtures.install()` points `HTMLDemoCatalog` at them.

`MagicMovePlanTests` runs everywhere. `MagicMoveTests` opens a window and films a transition, so it needs an unlocked screen and runs only with `HTMLBUBBLES_UI_TESTS=1`. The frames go to `$TMPDIR/html-bubble-magic`.

The six `Fixtures/widget-sandbox/showcase/3d` widgets mirror widget-sandbox's
`corpus/showcase/3d` sources. The cat supports mouse X/Y rotation, with
vertical touch gestures still reserved for the chat. The existing recursive widget catalog discovers
them after `DemoFixtures.install()`. They draw projected geometry through canvas
2D and need no native 3D extension. Keep the fixture copies byte-identical to
the sandbox originals. Authoring and manual-check steps are in the upstream
folder's README; `showcase-3d.test.ts` covers payloads, storage and cancellation.

`Fixtures/native-3d/solar-system.html` mirrors twidget's standalone
`Examples/native-3d/solar-system.html`. It requires HTMLScript plus HTML3D and is
kept outside the profile-1 widget corpus. The current production widget host and
regular browser cannot load its native library. Use twidget's documented
`tools/solar-system-check` offscreen checker; production demo fixtures remain
excluded from the app bundle.
