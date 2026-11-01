

import Foundation
import MediaPlayer
import SwiftSignalKit
import TelegramMediaPlayer
import RangeSet
import TGUIKit
import Postbox
import TelegramCore
import AppKit

public enum UniversalVideoContentVideoQuality: Equatable {
    case auto
    case quality(Int)
}

public protocol UniversalVideoContentView: AnyObject {
    
    var duration: Double { get }
    
    var ready: Signal<Void, NoError> { get }
    var status: Signal<MediaPlayerStatus, NoError> { get }
    var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> { get }
        
    var fileRef: FileMediaReference { get }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition)
    
    func play()
    func pause()
    func togglePlayPause()
    func setSoundEnabled(_ value: Bool)
    func setVolume(_ value: Float)
    func seek(_ timestamp: Double)
    func seek(_ timestamp: Double, play: Bool)
    func seekFrame(_ timestamp: Double)
    func playOnceWithSound(playAndRecord: Bool, actionAtEnd: MediaPlayerActionAtEnd)
    func setActionAtEnd(_ value: MediaPlayerActionAtEnd)
    func setSoundMuted(soundMuted: Bool)
    func setBaseRate(_ baseRate: Double)
    func setVideoQuality(_ videoQuality: UniversalVideoContentVideoQuality)
    func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])?
    func addPlaybackCompleted(_ f: @escaping () -> Void) -> Int
    func removePlaybackCompleted(_ index: Int)
    func fetchControl(_ control: UniversalVideoNodeFetchControl)
    
    func setVideoLayerGravity(_ gravity: AVLayerVideoGravity)
    
    
}
public func isHLSVideo(file: TelegramMediaFile) -> Bool {
    for alternativeFile in file.alternativeRepresentations {
        if alternativeFile.mimeType == "application/x-mpegurl" {
            return true
        }
    }
    return false
}

public func isAV1Video(file: TelegramMediaFile) -> Bool {
    for attribute in file.attributes {
        if case let .Video(_, _, _, _, _, videoCodec) = attribute {
            return videoCodec == "av1" || videoCodec == "av01"
        }
    }
    return false
}

public func shouldUseChunkedVideoPlayer(file: TelegramMediaFile) -> Bool {
    guard !isHLSVideo(file: file) else {
        return false
    }
    for attribute in file.attributes {
        if case let .Video(_, _, _, _, _, videoCodec) = attribute {
            return videoCodec == nil || videoCodec == "av1" || videoCodec == "av01"
        }
    }
    return false
}


public protocol UniversalVideoContent {
    var id: AnyHashable { get }
    var dimensions: CGSize { get }
    var duration: Double { get }
    
    func isEqual(to other: UniversalVideoContent) -> Bool
}

public extension UniversalVideoContent {
    func isEqual(to other: UniversalVideoContent) -> Bool {
        return false
    }
}

public extension UniversalVideoContentView {
    func seekFrame(_ timestamp: Double) {
        seek(timestamp)
    }
    func seek(_ timestamp: Double, play: Bool) {
        seek(timestamp)
        if play {
            self.play()
        }
    }
}

public protocol UniversalVideoDecoration: AnyObject {
    var backgroundView: NSView? { get }
    var contentContainerView: NSView { get }
    var foregroundView: NSView? { get }
    
    func setStatus(_ status: Signal<MediaPlayerStatus?, NoError>)
    
    func updateContentNode(_ contentNode: (UniversalVideoContentView & NSView)?)
    func updateContentNodeSnapshot(_ snapshot: NSView?)
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition)
    func tap()
}

public enum UniversalVideoPriority: Int32, Comparable {
    case minimal = 0
    case secondaryOverlay = 1
    case embedded = 2
    case gallery = 3
    case overlay = 4
    
    public static func <(lhs: UniversalVideoPriority, rhs: UniversalVideoPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public enum UniversalVideoNodeFetchControl {
    case fetch
    case cancel
}
