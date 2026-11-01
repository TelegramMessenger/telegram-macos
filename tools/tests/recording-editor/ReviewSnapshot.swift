import AppKit
import XCTest
import TGUIKit
@testable import ChatUI

final class RecordingEditorReviewSnapshotTests: XCTestCase {
    func testCaptureTimeline() throws {
        UITestBootstrap.install()
        let environment = ProcessInfo.processInfo.environment
        let output = try XCTUnwrap(environment["RECORDING_REVIEW_IMAGE"])
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 680, height: 160), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = View(frame: NSRect(x: 0, y: 0, width: 680, height: 160))
        host.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        window.contentView = host
        let label = NSTextField(labelWithString: "Video preview · 10 seconds · selected range 2–8 seconds")
        label.textColor = .white
        label.font = .systemFont(ofSize: 15)
        label.frame = NSRect(x: 24, y: 112, width: 632, height: 24)
        host.addSubview(label)
        let scrubber = RecordingTrimScrubberView(frame: NSRect(x: 24, y: 48, width: 632, height: 34))
        host.addSubview(scrubber)
        let image = try XCTUnwrap(generateImage(NSSize(width: 200, height: 200), contextGenerator: { size, context in
            context.setFillColor(NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.72, alpha: 1).cgColor)
            context.fill(size.bounds)
        }))
        scrubber.update(duration: 10, waveform: nil, trimRange: 2 ..< 8, position: 4, isPlaying: false, isVideo: true)
        scrubber.setVideo(path: NSTemporaryDirectory() + "recording-review-placeholder.mp4", placeholder: image)
        scrubber.layoutSubtreeIfNeeded()
        let play = try XCTUnwrap(scrubber.subviews.compactMap { $0 as? Control }.first { $0.frame.height == 22 })
        XCTAssertEqual(play.isHidden, environment["RECORDING_REVIEW_BEFORE"] == "1")
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: output))
        XCTAssertGreaterThan(data.count, 1000)
    }
}
