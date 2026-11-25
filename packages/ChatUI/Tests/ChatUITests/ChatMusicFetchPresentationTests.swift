import XCTest
import AppKit
@testable import TGUIKit
import TelegramCore
import Postbox
import TelegramTheme
import SwiftSignalKit
import AudioPlayerCore
@testable import FetchManager
@testable import ChatUI

final class ChatMusicFetchPresentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        ChatMediaUIHooks.install(.placeholder)
    }

    func testAlreadyDownloadingTrackAppearsWithoutPlaceholderTransition() throws {
        let view = ChatMusicContentView(frame: NSMakeRect(0, 0, 200, 40))
        for id: UInt32 in [1, 2, 3] {
            view.parent = message(id)
            view.initializeFetchStatus()
            XCTAssertNil(view.fetchStatus)
            XCTAssertFalse(view.hasFetchStatusForCurrentMedia)
            let manager = FetchManagerProbe()
            view.updateFetchStatus(chatMusicFetchStatus(fetchManager: manager, message: view.parent, file: musicFile()))
            manager.emit(.Fetching(isActive: true, progress: 0.6), hasEntry: true)
            XCTAssertFalse(view.statusChangeIsAnimatable)
            XCTAssertFalse(view.progressView.isHidden)
            guard case let .Fetching(progress, _) = view.progressView.state else { return XCTFail("Expected download") }
            XCTAssertEqual(progress, 0.6)
            XCTAssertEqual(view.progressView.displayedValuesForTesting.ring, 1)
            XCTAssertNil(view.progressView.displayedValuesForTesting.swap)
            view.initializeFetchStatus()
            XCTAssertEqual(view.fetchStatus, .Fetching(isActive: true, progress: 0.6))
            manager.emit(.Local)
            XCTAssertTrue(view.statusChangeIsAnimatable)
        }
        let audio = ChatAudioContentView(frame: .zero)
        audio.initializeFetchStatus()
        XCTAssertEqual(audio.fetchStatus, .Local)
    }

    func testCoverVisibilityFollowsDownloadAndCancellation() throws {
        let view = ChatMusicContentView(frame: NSMakeRect(0, 0, 200, 40))
        let cover = try XCTUnwrap(view.subviews.compactMap { $0 as? TransformImageView }.first)
        let manager = FetchManagerProbe()
        view.updateFetchStatus(chatMusicFetchStatus(fetchManager: manager, message: message(1), file: musicFile()))
        XCTAssertEqual(manager.reportExternalFetches, false)
        manager.emit(.Remote(progress: 0))
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
        manager.emit(.Fetching(isActive: true, progress: 0.25), hasEntry: true)
        XCTAssertTrue(cover.isHidden)
        XCTAssertFalse(view.progressView.isHidden)
        guard case let .Fetching(progress, _) = view.progressView.state else {
            return XCTFail("Expected download progress")
        }
        XCTAssertEqual(progress, 0.25)
        XCTAssertEqual(view.progressView.theme.backgroundColor, ChatMediaPresentation.Empty.activityBackground)
        XCTAssertEqual(view.progressView.theme.foregroundColor, ChatMediaPresentation.Empty.activityForeground)
        manager.emit(.Fetching(isActive: true, progress: 0.25), hasEntry: true, isPaused: true)
        XCTAssertEqual(view.fetchStatus, .Paused(progress: 0.25))
        XCTAssertTrue(cover.isHidden)
        XCTAssertFalse(view.progressView.isHidden)
        manager.emit(.Fetching(isActive: true, progress: 0.25))
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
    }

    func testHeaderPreloadAndStreamingKeepCoverAndPlaybackMouseRoute() throws {
        let view = PlaybackProbe(frame: NSMakeRect(10, 15, 200, 40))
        let window = host(view)
        let cover = try XCTUnwrap(view.subviews.compactMap { $0 as? TransformImageView }.first)
        let manager = FetchManagerProbe()
        view.parent = message(1)
        view.updateFetchStatus(chatMusicFetchStatus(fetchManager: manager, message: view.parent, file: musicFile()))
        manager.emit(.Fetching(isActive: true, progress: 0.05))
        XCTAssertEqual(view.fetchStatus, .Remote(progress: 0.05))
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
        XCTAssertTrue(try click(view, in: window, at: NSMakePoint(20, 20)) === cover)
        XCTAssertTrue(view.isPlaying)
        let animation = try XCTUnwrap(cover.subviews.compactMap { $0 as? PeerMediaPlayerAnimationView }.first)
        manager.emit(.Fetching(isActive: true, progress: 0.6))
        XCTAssertFalse(animation.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(animation.isPlaying)
        XCTAssertTrue(view.progressView.isHidden)
        let target = try click(view, in: window, at: NSMakePoint(20, 20))
        XCTAssertTrue(target === animation || target.isDescendant(of: animation))
        XCTAssertFalse(view.isPlaying)
        XCTAssertEqual(view.openCount, 2)
        XCTAssertEqual(view.cancelCount, 0)
    }

    func testDownloadingTitleDurationAndBodyPlayWhileRingCancels() throws {
        let view = PlaybackProbe(frame: NSMakeRect(10, 15, 200, 40))
        let window = host(view)
        let points = [NSMakePoint(70, 8), NSMakePoint(70, 30), NSMakePoint(180, 20)]
        for status: MediaResourceStatus in [.Fetching(isActive: true, progress: 0.25), .Fetching(isActive: false, progress: 0), .Paused(progress: 0.25)] {
            view.fetchStatus = status
            for point in points {
                let count = view.openCount
                let target = try click(view, in: window, at: point)
                XCTAssertFalse(target === view.progressView)
                XCTAssertEqual(view.openCount, count + 1)
            }
            view.updatePlaybackState(nil)
            let count = view.openCount
            let cancelCount = view.cancelCount
            XCTAssertTrue(try click(view, in: window, at: NSMakePoint(20, 20)) === view.progressView)
            XCTAssertEqual(view.openCount, count)
            XCTAssertEqual(view.cancelCount, cancelCount + 1)
        }
        view.userInteractionEnabled = false
        let count = view.openCount
        let cancelCount = view.cancelCount
        for point in points + [NSMakePoint(20, 20)] {
            try click(view, in: window, at: point)
        }
        XCTAssertEqual(view.openCount, count)
        XCTAssertEqual(view.cancelCount, cancelCount)
    }

    func testManagedDownloadKeepsCoverPauseAndResumeAfterPlaybackStarts() throws {
        let view = PlaybackProbe(frame: NSMakeRect(10, 15, 200, 40))
        let window = host(view)
        let cover = try XCTUnwrap(view.subviews.compactMap { $0 as? TransformImageView }.first)
        let manager = FetchManagerProbe()
        view.parent = message(1)
        view.updateFetchStatus(chatMusicFetchStatus(fetchManager: manager, message: view.parent, file: musicFile()))
        manager.emit(.Fetching(isActive: true, progress: 0.25), hasEntry: true)
        XCTAssertFalse(view.progressView.isHidden)
        try click(view, in: window, at: NSMakePoint(70, 8))
        XCTAssertTrue(view.isPlaying)
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
        let animation = try XCTUnwrap(cover.subviews.compactMap { $0 as? PeerMediaPlayerAnimationView }.first)
        XCTAssertTrue(animation.isPlaying)
        manager.emit(.Fetching(isActive: true, progress: 0.5), hasEntry: true)
        XCTAssertTrue(view.progressView.isHidden)
        XCTAssertFalse(animation.isHiddenOrHasHiddenAncestor)
        try click(view, in: window, at: NSMakePoint(20, 20))
        XCTAssertFalse(view.isPlaying)
        XCTAssertFalse(animation.isPlaying)
        XCTAssertTrue(view.progressView.isHidden)
        manager.emit(.Fetching(isActive: true, progress: 0.6), hasEntry: true)
        try click(view, in: window, at: NSMakePoint(20, 20))
        XCTAssertTrue(view.isPlaying)
        XCTAssertEqual(view.openCount, 3)
        XCTAssertEqual(view.cancelCount, 0)
        view.updatePlaybackState(.stoped)
        XCTAssertTrue(cover.isHidden)
        XCTAssertFalse(view.progressView.isHidden)
        XCTAssertTrue(try click(view, in: window, at: NSMakePoint(20, 20)) === view.progressView)
        XCTAssertEqual(view.cancelCount, 1)
    }

    func testRemoteAndLocalCoverAndBodyClicksPlayWithoutFetching() throws {
        let view = PlaybackProbe(frame: NSMakeRect(10, 15, 200, 40))
        let window = host(view)
        for status: MediaResourceStatus in [.Remote(progress: 0), .Local] {
            view.fetchStatus = status
            for point in [NSMakePoint(20, 20), NSMakePoint(70, 8), NSMakePoint(70, 30), NSMakePoint(180, 20)] {
                let count = view.openCount
                try click(view, in: window, at: point)
                XCTAssertEqual(view.openCount, count + 1)
            }
        }
        XCTAssertEqual(view.fetchCount, 0)
        XCTAssertEqual(view.cancelCount, 0)
    }

    func testUploadRingCancelsWithoutStartingPlayback() throws {
        let view = PlaybackProbe(frame: NSMakeRect(10, 15, 200, 40))
        let window = host(view)
        view.parent = message(1, flags: [.Unsent])
        view.fetchStatus = .Fetching(isActive: true, progress: 0.4)
        XCTAssertFalse(view.progressView.isHidden)
        try click(view, in: window, at: NSMakePoint(70, 8))
        XCTAssertEqual(view.openCount, 0)
        XCTAssertEqual(view.deleteCount, 0)
        XCTAssertTrue(try click(view, in: window, at: NSMakePoint(20, 20)) === view.progressView)
        XCTAssertEqual(view.openCount, 0)
        XCTAssertEqual(view.deleteCount, 1)
        XCTAssertEqual(view.cancelCount, 1)
    }

    func testCompletionCancellationAndReuseRestoreCover() throws {
        let view = ChatMusicContentView(frame: NSMakeRect(0, 0, 200, 40))
        let cover = try XCTUnwrap(view.subviews.compactMap { $0 as? TransformImageView }.first)
        let first = FetchManagerProbe()
        view.parent = message(1)
        view.updateFetchStatus(chatMusicFetchStatus(fetchManager: first, message: view.parent, file: musicFile()))
        first.emit(.Remote(progress: 0))
        XCTAssertFalse(view.statusChangeIsAnimatable)
        first.emit(.Fetching(isActive: true, progress: 0.9), hasEntry: true)
        XCTAssertTrue(view.statusChangeIsAnimatable)
        first.emit(.Local)
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
        first.emit(.Fetching(isActive: true, progress: 0.1), hasEntry: true)
        view.updatePlaybackState(.playing(current: 0, duration: 100, progress: 0))
        XCTAssertFalse(cover.isHidden)
        let second = FetchManagerProbe()
        view.parent = message(2)
        view.checkState(animated: false)
        XCTAssertTrue(cover.subviews.compactMap { $0 as? PeerMediaPlayerAnimationView }.isEmpty)
        XCTAssertFalse(view.hasFetchStatusForCurrentMedia)
        view.updateFetchStatus(chatMusicFetchStatus(fetchManager: second, message: view.parent, file: musicFile()))
        second.emit(.Fetching(isActive: true, progress: 0.05))
        XCTAssertFalse(view.statusChangeIsAnimatable)
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
        first.emit(.Fetching(isActive: true, progress: 0.8), hasEntry: true)
        XCTAssertEqual(view.fetchStatus, .Remote(progress: 0.05))
        second.emit(.Fetching(isActive: true, progress: 0.1), hasEntry: true)
        XCTAssertTrue(cover.isHidden)
        view.fetchStatus = nil
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
    }

    func testExternalFetchFilteringPreservesLegacySubscribersAndManagerTransfers() {
        let streaming = FetchManagerStatus(resourceStatus: .Fetching(isActive: true, progress: 0.3), hasEntry: false, isPaused: false)
        let downloading = FetchManagerStatus(resourceStatus: streaming.resourceStatus, hasEntry: true, isPaused: false)
        XCTAssertNotEqual(streaming, downloading)
        XCTAssertEqual(streaming.mediaResourceStatus(reportExternalFetches: true), streaming.resourceStatus)
        XCTAssertEqual(streaming.mediaResourceStatus(reportExternalFetches: false), .Remote(progress: 0.3))
        XCTAssertEqual(downloading.mediaResourceStatus(reportExternalFetches: false), streaming.resourceStatus)
        let queued = FetchManagerStatus(resourceStatus: .Remote(progress: 0), hasEntry: true, isPaused: false)
        XCTAssertEqual(queued.mediaResourceStatus(reportExternalFetches: false), .Fetching(isActive: false, progress: 0))
        let paused = FetchManagerStatus(resourceStatus: streaming.resourceStatus, hasEntry: true, isPaused: true)
        XCTAssertEqual(paused.mediaResourceStatus(reportExternalFetches: false), .Paused(progress: 0.3))
        let local = FetchManagerStatus(resourceStatus: .Local, hasEntry: true, isPaused: false)
        XCTAssertEqual(local.mediaResourceStatus(reportExternalFetches: false), .Local)
    }

    func testStandaloneAndLocalReferenceDoNotSubscribeToResourceFetches() {
        let manager = FetchManagerProbe()
        let view = ChatMusicContentView(frame: NSMakeRect(0, 0, 200, 40))
        view.fetchStatus = .Fetching(isActive: true, progress: 0.5)
        view.updateFetchStatus(chatMusicFetchStatus(fetchManager: manager, message: nil, file: musicFile()))
        XCTAssertNil(manager.reportExternalFetches)
        XCTAssertEqual(view.fetchStatus, .Local)
        XCTAssertTrue(view.progressView.isHidden)
        let local = LocalFileReferenceMediaResource(localFilePath: "/unused/music.mp3", randomId: 1)
        view.updateFetchStatus(chatMusicFetchStatus(fetchManager: manager, message: message(1), file: musicFile(resource: local)))
        XCTAssertNil(manager.reportExternalFetches)
        XCTAssertEqual(view.fetchStatus, .Local)
    }

    private func host(_ view: PlaybackProbe) -> MouseWindow {
        let window = MouseWindow(contentRect: NSMakeRect(0, 0, 240, 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSMakeRect(0, 0, 240, 80))
        window.contentView?.addSubview(view)
        view.layoutSubtreeIfNeeded()
        view.textView.frame = NSMakeRect(50, 0, 100, 16)
        view.durationView.frame = NSMakeRect(50, 24, 100, 16)
        return window
    }

    @discardableResult private func click(_ view: PlaybackProbe, in window: MouseWindow, at point: NSPoint) throws -> NSView {
        let location = view.convert(point, to: nil)
        window.pointerLocation = location
        let target = try XCTUnwrap(window.contentView?.hitTest(location))
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        target.mouseDown(with: down)
        target.mouseUp(with: up)
        return target
    }

    private func message(_ id: UInt32, flags: MessageFlags = [.Incoming]) -> Message {
        return Message(stableId: id, stableVersion: 0, id: MessageId(peerId: PeerId(1), namespace: 0, id: Int32(id)), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: flags, tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "", attributes: [], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func musicFile(resource: TelegramMediaResource? = nil) -> TelegramMediaFile {
        let resource = resource ?? CloudDocumentMediaResource(datacenterId: 1, fileId: 1, accessHash: 0, size: 10 * 1024 * 1024, fileReference: nil, fileName: "music.mp3")
        return TelegramMediaFile(fileId: MediaId(namespace: 0, id: 1), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "audio/mpeg", size: resource.size, attributes: [], alternativeRepresentations: [])
    }

    private final class MouseWindow: NSWindow {
        var pointerLocation: NSPoint = .zero
        override var mouseLocationOutsideOfEventStream: NSPoint {
            return pointerLocation
        }
    }

    private final class PlaybackProbe: ChatMusicContentView {
        var openCount = 0
        var cancelCount = 0
        var deleteCount = 0
        var fetchCount = 0
        var isPlaying = false
        override func open() {
            openCount += 1
            isPlaying.toggle()
            updatePlaybackState(isPlaying ? .playing(current: 0, duration: 100, progress: 0) : .paused(current: 0, duration: 100, progress: 0))
        }
        override func cancelFetching() {
            cancelCount += 1
        }
        override func delete() {
            deleteCount += 1
        }
        override func fetch(userInitiated: Bool) {
            fetchCount += 1
        }
    }

    private final class FetchManagerProbe: FetchManager {
        let queue = Queue.mainQueue()
        let statuses = ValuePipe<FetchManagerStatus>()
        var reportExternalFetches: Bool?

        func emit(_ resourceStatus: MediaResourceStatus, hasEntry: Bool = false, isPaused: Bool = false) {
            statuses.putNext(FetchManagerStatus(resourceStatus: resourceStatus, hasEntry: hasEntry, isPaused: isPaused))
        }

        func fetchStatus(category: FetchManagerCategory, location: FetchManagerLocation, locationKey: FetchManagerLocationKey, resource: MediaResource) -> Signal<MediaResourceStatus, NoError> {
            return fetchStatus(category: category, location: location, locationKey: locationKey, resource: resource, reportExternalFetches: true)
        }

        func fetchStatus(category: FetchManagerCategory, location: FetchManagerLocation, locationKey: FetchManagerLocationKey, resource: MediaResource, reportExternalFetches: Bool) -> Signal<MediaResourceStatus, NoError> {
            self.reportExternalFetches = reportExternalFetches
            return statuses.signal() |> map { $0.mediaResourceStatus(reportExternalFetches: reportExternalFetches) }
        }

        func interactivelyFetched(category: FetchManagerCategory, location: FetchManagerLocation, locationKey: FetchManagerLocationKey, mediaReference: AnyMediaReference?, resourceReference: MediaResourceReference, ranges: IndexSet, statsCategory: MediaResourceStatsCategory, elevatedPriority: Bool, userInitiated: Bool, priority: FetchManagerPriority, storeToDownloadsPeerType: MediaAutoDownloadPeerType?) -> Signal<Void, NoError> {
            return .complete()
        }

        func cancelInteractiveFetches(category: FetchManagerCategory, location: FetchManagerLocation, locationKey: FetchManagerLocationKey, resource: MediaResource) {
        }

        func cancelInteractiveFetches(resourceId: String) {
        }

        func toggleInteractiveFetchPaused(resourceId: String, isPaused: Bool) {
        }

        func raisePriority(resourceId: String) {
        }
    }
}
