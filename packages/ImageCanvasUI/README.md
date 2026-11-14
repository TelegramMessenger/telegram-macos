# Native video export and upload

`EditVideoController` queues a logical output URL through `PendingVideoRenders`. Re-encoded edits use `EditVideoExport.exportProgressively`; passthrough exports retain the existing complete-file path. The presence of `macos_killswitch_disable_chat_streaming_video_writer` in app configuration selects the legacy writer.

The streaming writer uses VideoToolbox, AAC conversion and the shared `FFMpegMP4StreamWriter`. It reserves space for the final MP4 metadata before writing media packets. Published media bytes remain fixed; finalization changes only that reserved header. A header overflow fails the streaming export instead of publishing a non-faststart file. Legacy fallback is allowed before growing body bytes have been published to the resource pipeline.

## Upload contract

- `LocalFileVideoMediaResource.headerSize` starts positive and reads the measured reservation from the pending-render registry. Keep this hint until cancellation or replacement: MediaBox and multipart consumers run on separate queues.
- The native resource producer waits for more than 10 MiB before publishing growing file data. Its first publication contains 10 MiB plus one byte atomically; later publications use bounded 512 KiB chunks. These are resource-fetch events, and do not imply that network upload has started.
- `VideoRenderUploadState` tracks consumed bytes. Finalization appends the remaining media, replaces the complete reserved header, and only then marks the resource complete.
- A completion with no earlier publication uses the complete-file copy/move path. This includes small videos, passthrough, legacy fallback and subscribers that arrive after rendering finishes.
- Queued growth can outlive the temporary filename after final rename. Such growth waits for the final event; it never reads an unrelated old destination file.
- `PendingVideoRenders` serializes entry replacement, cancellation, hints and event publication. Old callbacks cannot publish into a replacement render. Clearing old state precedes callbacks that may synchronously start another render.

The active configuration pins unmodified upstream iOS master. Its MediaBox V2 does not publish a nonzero growing prefix to the standard multipart uploader: `.incremental` resource-data observations remain size zero until the resource completes. Native conversion and resource fetching still produce growing events, but chat network uploads start after conversion and header replacement finish. Conversion/upload overlap is therefore not provided in this configuration. The local Postbox prefix-notification patch has been removed.

The native producer preserves the reserved-header contract so a future upstream prefix implementation can safely consume it. Multipart upload can withhold reserved header parts when it receives a growing prefix; the current completion-first path instead uploads the finalized file normally. Do not treat physical file length as proof of a contiguous available prefix.

## Verification

Permanent native lifecycle/range tests are in `ChatUI/Tests/ChatUITests/VideoRenderUploadTests.swift`. Run them from the repository root with the existing `packages/ChatUI/Tests/run-tests.sh` wrapper and repository-local DerivedData. The removed local Postbox prefix patch and its regression file are not part of the upstream submodule.

Real-media verification checks decoded H.264/AAC frames and timestamps, variable frame rates, resampling, delayed audio, faststart layout, immutable published bytes, cancellation and overflow. The current upstream integration check requires zero network parts before conversion completion for both small and large files, then byte-exact reconstruction from captured Core multipart parts. Upload parts are mocked locally; these checks send no real messages or media.
