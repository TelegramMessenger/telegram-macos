import AppKit
import MediaPlayer
import XCTest
import TelegramMedia
@testable import AudioPlayerCore

final class MediaPlaybackControlCenterTests: XCTestCase {
    private var owners: [MediaPlaybackControlCenter] = []

    override func setUp() {
        super.setUp()
        XCTAssertTrue(Thread.isMainThread)
        _ = NSApplication.shared
    }

    override func tearDown() {
        for owner in owners {
            owner.clearNowPlaying()
        }
        owners.removeAll()
        super.tearDown()
    }

    private func owner() -> MediaPlaybackControlCenter {
        let owner = MediaPlaybackControlCenter()
        owners.append(owner)
        return owner
    }

    private func status(_ playback: MediaPlayerPlaybackStatus = .playing, timestamp: Double = 12, duration: Double = 60, rate: Double = 1.5, volume: Float = 1) -> MediaPlayerStatus {
        return MediaPlayerStatus(generationTimestamp: 0, duration: duration, dimensions: CGSize(width: 96, height: 64), timestamp: timestamp, baseRate: rate, volume: volume, seekId: 0, status: playback)
    }

    private func activate(_ owner: MediaPlaybackControlCenter, title: String = "Video") {
        owner.activate()
        owner.updateControlsAvaiability(nextEnabled: false, prevEnabled: false, seekEnabled: false)
        owner.setupNowPlaying(videoTitle: title, status: status())
    }

    func testUnselectedVideoCannotPublishOrHandleCommands() {
        let active = owner()
        activate(active, title: "Selected")
        let preloaded = owner()
        var invoked = false
        preloaded.togglePlayPause = { invoked = true; return true }
        preloaded.setupNowPlaying(videoTitle: "Preloaded", status: status())
        XCTAssertEqual(preloaded.performCommand(generation: preloaded.commandGeneration) { $0.togglePlayPause() }, .commandFailed)
        XCTAssertFalse(invoked)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Selected")
    }

    func testVideoPublishesNativeMetadataAndTransportAvailability() {
        let video = owner()
        activate(video)
        let center = MPNowPlayingInfoCenter.default()
        let info = center.nowPlayingInfo
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyMediaType] as? UInt, MPNowPlayingInfoMediaType.video.rawValue)
        XCTAssertEqual(info?[MPMediaItemPropertyPlaybackDuration] as? Double, 60)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 12)
        XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.5)
        XCTAssertEqual(center.playbackState, .playing)
        let commands = MPRemoteCommandCenter.shared()
        XCTAssertTrue(commands.playCommand.isEnabled)
        XCTAssertTrue(commands.pauseCommand.isEnabled)
        XCTAssertTrue(commands.togglePlayPauseCommand.isEnabled)
        XCTAssertFalse(commands.nextTrackCommand.isEnabled)
        XCTAssertFalse(commands.previousTrackCommand.isEnabled)
        XCTAssertFalse(commands.changePlaybackPositionCommand.isEnabled)
    }

    func testPauseRetainsOwnerForResume() {
        let video = owner()
        activate(video)
        var calls: [String] = []
        video.pause = { calls.append("pause"); return true }
        video.play = { calls.append("play"); return true }
        let generation = video.commandGeneration
        XCTAssertEqual(video.performCommand(generation: generation) { $0.pause() }, .success)
        video.setupNowPlaying(videoTitle: "Video", status: status(.paused))
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertEqual(video.performCommand(generation: generation) { $0.play() }, .success)
        XCTAssertEqual(calls, ["pause", "play"])
    }

    func testToggleDispatchesToCurrentOwnerOnly() {
        let audio = owner()
        let video = owner()
        var audioCalls = 0
        var videoCalls = 0
        audio.togglePlayPause = { audioCalls += 1; return true }
        video.togglePlayPause = { videoCalls += 1; return true }
        activate(audio, title: "Audio")
        let oldGeneration = audio.commandGeneration
        activate(video)
        XCTAssertEqual(audio.performCommand(generation: oldGeneration) { $0.togglePlayPause() }, .commandFailed)
        XCTAssertEqual(video.performCommand(generation: video.commandGeneration) { $0.togglePlayPause() }, .success)
        XCTAssertEqual(audioCalls, 0)
        XCTAssertEqual(videoCalls, 1)
    }

    func testOldStatusAndCleanupCannotOverwriteReplacement() {
        let previous = owner()
        activate(previous, title: "Previous")
        let current = owner()
        activate(current, title: "Current")
        previous.setupNowPlaying(videoTitle: "Late status", status: status(.paused))
        previous.updateControlsAvaiability(nextEnabled: true, prevEnabled: true)
        previous.clearNowPlaying()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Current")
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        XCTAssertFalse(MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
        current.togglePlayPause = { true }
        XCTAssertEqual(current.performCommand(generation: current.commandGeneration) { $0.togglePlayPause() }, .success)
    }

    func testResumeAudioRestoresItsAvailableCommands() {
        let audio = owner()
        activate(audio, title: "Audio")
        audio.updateControlsAvaiability(nextEnabled: true, prevEnabled: true)
        let video = owner()
        activate(video)
        video.clearNowPlaying()
        audio.activate()
        audio.updateControlsAvaiability(nextEnabled: true, prevEnabled: false)
        audio.setupNowPlaying(videoTitle: "Restored owner", status: status())
        let commands = MPRemoteCommandCenter.shared()
        XCTAssertTrue(commands.nextTrackCommand.isEnabled)
        XCTAssertFalse(commands.previousTrackCommand.isEnabled)
        XCTAssertTrue(commands.changePlaybackPositionCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Restored owner")
    }

    func testClosingVideoRestoresPausedAudioWithoutStartingIt() {
        let audio = owner()
        var playCalls = 0
        var restored = 0
        audio.play = { playCalls += 1; return true }
        audio.restoreNowPlaying = { [weak audio] in
            guard let audio else { return false }
            restored += 1
            audio.setupNowPlaying(videoTitle: "Paused audio", status: self.status(.paused))
            audio.updateControlsAvaiability(nextEnabled: true, prevEnabled: false)
            return true
        }
        activate(audio, title: "Paused audio")
        audio.setupNowPlaying(videoTitle: "Paused audio", status: status(.paused))
        let video = owner()
        activate(video)
        video.clearNowPlaying()
        XCTAssertEqual(restored, 1)
        XCTAssertEqual(playCalls, 0)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Paused audio")
        XCTAssertTrue(MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
        XCTAssertTrue(MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled)
        XCTAssertEqual(audio.performCommand(generation: audio.commandGeneration) { $0.play() }, .success)
        XCTAssertEqual(playCalls, 1)
    }

    func testClosingBackgroundAudioPreventsRestoration() {
        let audio = owner()
        var restored = false
        audio.restoreNowPlaying = { restored = true; return true }
        activate(audio)
        let video = owner()
        activate(video)
        audio.clearNowPlaying()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        video.clearNowPlaying()
        XCTAssertFalse(restored)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }

    func testUnavailablePreviousAudioIsNotRestored() {
        let audio = owner()
        audio.restoreNowPlaying = { false }
        activate(audio)
        let video = owner()
        activate(video)
        video.clearNowPlaying()
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(audio.performCommand(generation: audio.commandGeneration) { $0.play() }, .commandFailed)
    }

    func testVideoDeinitRestoresPersistentOwner() {
        let audio = owner()
        var restored = 0
        audio.restoreNowPlaying = { [weak audio] in
            guard let audio else { return false }
            restored += 1
            audio.setupNowPlaying(videoTitle: "Audio", status: self.status(.paused))
            return true
        }
        activate(audio)
        var video: MediaPlaybackControlCenter? = MediaPlaybackControlCenter()
        activate(video!)
        video = nil
        XCTAssertEqual(restored, 1)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Audio")
    }

    func testReplacingVideoDoesNotRestoreAudioUntilCurrentVideoCloses() {
        let audio = owner()
        var restored = 0
        audio.restoreNowPlaying = { restored += 1; return true }
        activate(audio)
        let first = owner()
        activate(first)
        let second = owner()
        activate(second)
        first.clearNowPlaying()
        XCTAssertEqual(restored, 0)
        second.clearNowPlaying()
        XCTAssertEqual(restored, 1)
    }

    func testReactivationRejectsCallbacksFromEarlierRegistration() {
        let first = owner()
        activate(first)
        let oldGeneration = first.commandGeneration
        let second = owner()
        activate(second)
        activate(first)
        var invoked = false
        first.togglePlayPause = { invoked = true; return true }
        XCTAssertNotEqual(first.commandGeneration, oldGeneration)
        XCTAssertEqual(first.performCommand(generation: oldGeneration) { $0.togglePlayPause() }, .commandFailed)
        XCTAssertFalse(invoked)
        XCTAssertEqual(first.performCommand(generation: first.commandGeneration) { $0.togglePlayPause() }, .success)
        XCTAssertTrue(invoked)
    }

    func testRepeatedActivationPreservesTheLiveRegistration() {
        let video = owner()
        activate(video)
        let generation = video.commandGeneration
        activate(video)
        XCTAssertEqual(video.commandGeneration, generation)
        var calls = 0
        video.togglePlayPause = { calls += 1; return true }
        XCTAssertEqual(video.performCommand(generation: generation) { $0.togglePlayPause() }, .success)
        XCTAssertEqual(calls, 1)
    }

    func testClosingClearsMetadataAndInvalidatesCommands() {
        let video = owner()
        activate(video)
        let generation = video.commandGeneration
        var calls = 0
        video.togglePlayPause = { calls += 1; return true }
        video.clearNowPlaying()
        video.setupNowPlaying(videoTitle: "Late update", status: status())
        XCTAssertEqual(video.performCommand(generation: generation) { $0.togglePlayPause() }, .commandFailed)
        XCTAssertEqual(calls, 0)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .stopped)
    }

    func testOwnerDeinitClearsNativeState() {
        var video: MediaPlaybackControlCenter? = MediaPlaybackControlCenter()
        weak var weakOwner = video
        activate(video!)
        video = nil
        XCTAssertNil(weakOwner)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .stopped)
    }

    func testPreviousOwnerDeinitDoesNotClearCurrentOwner() {
        var previous: MediaPlaybackControlCenter? = MediaPlaybackControlCenter()
        activate(previous!, title: "Previous")
        let current = owner()
        activate(current, title: "Current")
        previous = nil
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Current")
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
    }

    func testBufferingPreservesPlayIntentWithoutAdvancingElapsedTime() {
        let video = owner()
        activate(video)
        video.setupNowPlaying(videoTitle: "Video", status: status(.buffering(initial: true, whilePlaying: true)))
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        video.setupNowPlaying(videoTitle: "Video", status: status(.buffering(initial: false, whilePlaying: false)))
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
    }

    func testMutedVideoStillOwnsPlayback() {
        let video = owner()
        activate(video)
        video.setupNowPlaying(videoTitle: "Muted", status: status(volume: 0))
        video.togglePlayPause = { true }
        XCTAssertEqual(video.performCommand(generation: video.commandGeneration) { $0.togglePlayPause() }, .success)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
    }

    func testInvalidTimingValuesAreClamped() {
        let video = owner()
        activate(video)
        for (timestamp, duration, rate) in [(Double.nan, Double.infinity, Double.nan), (-5, -10, -2)] {
            video.setupNowPlaying(videoTitle: "Video", status: status(timestamp: timestamp, duration: duration, rate: rate))
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
            XCTAssertEqual(info?[MPMediaItemPropertyPlaybackDuration] as? Double, 0)
            XCTAssertEqual(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 0)
            XCTAssertEqual(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        }
        video.setupNowPlaying(videoTitle: "Video", status: status(timestamp: 100, duration: 60))
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 60)
    }

    func testBackgroundCommandIsDeliveredOnMainThread() {
        let video = owner()
        activate(video)
        video.togglePlayPause = {
            XCTAssertTrue(Thread.isMainThread)
            return true
        }
        let generation = video.commandGeneration
        let done = expectation(description: "command")
        DispatchQueue.global().async {
            XCTAssertEqual(video.performCommand(generation: generation) { $0.togglePlayPause() }, .success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testUnavailableActionReturnsFailure() {
        let video = owner()
        activate(video)
        XCTAssertEqual(video.performCommand(generation: video.commandGeneration) { $0.togglePlayPause() }, .commandFailed)
    }
}
