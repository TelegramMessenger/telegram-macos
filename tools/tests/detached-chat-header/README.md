# Detached chat header checks

`python3 tools/tests/detached-chat-header/run.py` compiles `DetachedWindowHeaderLayout` with a small AppKit harness and checks it against a real full-size window with a unified toolbar:

- the capsule sits on the 40-point header bubble row at the 12-point side and top insets;
- the native traffic lights are centred in the capsule;
- the buttons stay in their native titlebar parent, inside its bounds, and still receive clicks;
- the geometry is the same in narrow and wide windows;
- a short titlebar clamps the buttons instead of moving them out of it.

`DetachedWindowControls` itself needs TGUIKit and is checked in the running app.
