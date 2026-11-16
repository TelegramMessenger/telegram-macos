# Transcription availability across build configurations

Run `python3 tools/tests/beta-feature-gates/check.py` from the repository root.

The check compiles the production live dictation availability property in DEBUG, release, BETA, and DEBUG+BETA configurations. Live dictation remains available on macOS 10.15 and later in all four configurations. It also checks that recorded-clip startup consults the clip transcription policy.

News and AI provider screens are deferred to separate local layer-234 branches. This check does not start a recording or send a transcription request.
