# Settings row metrics checks

Run `tools/tests/settings-row-metrics/run.sh` from the repository root. This compiles the production SettingsRowMetrics source directly with Command Line Tools and checks content heights, long-subtitle growth, icon sizes, text offsets, sidebar alignment and device icon size.

Integration cases live in `packages/GeneralRows/Tests/GeneralRowsTests/SettingsRowLayoutTests.swift`. They exercise actual items and views, including card positions, separator geometry, accessory centering, sidebar truncation, original icon identity and unchanged non-settings rows. Run them with the GeneralRows package tests once native dependencies are configured.

Current local integration-test blocker: missing `opus/opus_multistream.h` and WebP `decode.h`. A full Telegram build additionally requires Xcode.
