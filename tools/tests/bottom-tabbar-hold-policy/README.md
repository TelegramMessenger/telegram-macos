# Bottom navigation hold policy

Run `python3 -I tools/tests/bottom-tabbar-hold-policy/run.py`.
Optional `--source-root /absolute/source` reads the app policy from another source tree.
Optional `--output /absolute/new-directory` retains logs and JSON, but never the
compiler cache or executable. Output must be new with no symlink components.

The app opts out of tab reordering. A held slide follows the same selection path
as a quick slide; it must not pick up an individual icon or persist a new order.
Existing saved tab order is deliberately preserved; this change does not reset
preferences or remove the generic toolkit's opt-in reorder implementation.

The runner reads the actual `allowsTabReordering` assignment from
`MainViewController.swift`, then compiles the original production layout,
gesture state, drag update, release, reorder release and item-frame methods from
revision `246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5`. Fixed and baseline variants
change only that extracted app policy. Boundary doubles represent controls,
delegates, cursor, animation/rendering and begin/cancel setup. Geometry uses
Foundation/CoreGraphics. This is not an AppKit view tree or live input test.

Six named cases cover 46 scenarios and 236 assertions: quick/long-held slides,
reverse slides, 2–4 visible slots, three widths, selected-tab click, edge clamping,
cancellation and the generic explicit reorder opt-in. Fixed policy passes all;
the original policy compiles and fails 138 behavioral assertions. Compilation
errors are reported separately and never count as a reproduced regression.

The gesture implementation is intentionally pinned: this test isolates the app
policy, not a separate elastic-animation change to the toolkit. The combined
client's elastic gestures have their own regression suite. Pixel appearance,
real input delivery, animation timing, live preferences and account state remain
outside this fixture. The user performs manual acceptance.

The runner strips inherited `GIT_*`, uses an owned temporary module cache and
`TMPDIR`, and compiles with two jobs. No account, GUI or application is opened.
