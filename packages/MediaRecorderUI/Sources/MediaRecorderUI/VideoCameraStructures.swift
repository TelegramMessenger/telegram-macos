import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import ObjcUtils
import TGVideoCameraMovie
import AVFoundation

public enum VideoRecorderPreviewCommand {
    case update(trimRange: Range<Double>?, seekTo: Double, play: Bool)
    case togglePlayback

    public init(trimRange: Range<Double>?, seekTo: Double, play: Bool) {
        self = .update(trimRange: trimRange, seekTo: seekTo, play: play)
    }
}

public struct VideoRecorderPreviewState: Equatable {
    public let position: Double
    public let isPlaying: Bool

    public init(position: Double, isPlaying: Bool) {
        self.position = position
        self.isPlaying = isPlaying
    }
}

public enum VideoCameraRecordingStatus : Equatable {
    case idle
    case startingRecording
    case recording
    case madeThumbnail(CGImage)
    case stoppingRecording
    case paused(info: ChatRecordingPreviewData)
    case stopped(thumb: CGImage?)
    case failed
    case finishRecording(path:String, duration:Int, id: Int64?, thumb: CGImage?)
}

public func ==(lhs: VideoCameraRecordingStatus, rhs: VideoCameraRecordingStatus) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle), (.startingRecording, .startingRecording), (.recording, .recording), (.stoppingRecording, .stoppingRecording), (.failed, .failed):
        return true
    case let (.madeThumbnail(lhs), .madeThumbnail(rhs)):
        return lhs === rhs
    case let (.paused(lhs), .paused(rhs)):
        return lhs == rhs
    case let (.stopped(lhs), .stopped(rhs)):
        return lhs === rhs
    case let (.finishRecording(lhsPath, lhsDuration, lhsId, lhsThumb), .finishRecording(rhsPath, rhsDuration, rhsId, rhsThumb)):
        return lhsPath == rhsPath && lhsDuration == rhsDuration && lhsId == rhsId && lhsThumb === rhsThumb
    default:
        return false
    }
}
