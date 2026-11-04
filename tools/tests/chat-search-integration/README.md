# Native chat search regression

See [VALIDATION.md](VALIDATION.md) for the current scope, reproducible commands and verification boundaries. Use --prepare-app to build an interactive neutral-data SearchIntegration.app. It is a component fixture, not a Telegram client.

The current candidate keeps full-pane search results and the same empty-query behavior, preserves dynamic Stories sizing and the existing ordinary-suggestion viewport limit, and does not reposition a dismissing popup. Full-client captures are historical layout comparisons; current executable outputs establish the review follow-up.
