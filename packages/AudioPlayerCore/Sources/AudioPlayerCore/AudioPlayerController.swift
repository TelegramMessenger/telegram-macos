import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import TelegramMedia
import ChatModeTypes
import MessageUtils
import AVKit
import AVFoundation
import MediaPlayer
import RangeSet
import TelegramMediaResources


public class APSingleWrapper {
    public let resource:TelegramMediaResource
    public let name:String?
    public let mimeType: String
    public let performer:String?
    public let id:AnyHashable
    public let duration: Double?
    public init(resource:TelegramMediaResource, mimeType: String = "mp3", name:String?, performer:String?, duration: Double?, id: AnyHashable) {
        self.resource = resource
        self.name = name
        self.mimeType = mimeType
        self.performer = performer
        self.id = id
        self.duration = duration
    }
}




public enum APState : Equatable {
    case waiting
    case playing(current:TimeInterval,duration:TimeInterval, progress:TimeInterval) // current, duration
    case paused(current:TimeInterval,duration:TimeInterval, progress:TimeInterval)
    case stoped
    case fetching(Float)
}



public struct APResource {
    public let complete:Bool
    public let progress:Float
    public let path:String
    public init(complete: Bool, progress: Float, path: String) {
        self.complete = complete
        self.progress = progress
        self.path = path
    }
}

public class APItem : Equatable {
    
    public private(set) var status: MediaPlayerStatus = MediaPlayerStatus(generationTimestamp: CACurrentMediaTime(), duration: 0, dimensions: CGSize(), timestamp: 0, baseRate: 1.0, volume: 1.0, seekId: 0, status: .paused)
    
    public func setStatus(_ status: MediaPlayerStatus, rate: Double) {
        
        let status = status.withUpdatedDuration(max(status.duration, self.status.duration))
        
        var progress:TimeInterval = (status.timestamp / status.duration)
        if progress.isNaN {
            progress = 0
        } 
        
        if !progress.isFinite {
            progress = 1.0
        }

        self.status = status
        switch status.status {
        case .playing:
            self.state = .playing(current: status.timestamp, duration: status.duration, progress: progress)
        case .paused:
            self.state = .paused(current: status.timestamp, duration: status.duration, progress: progress)
        default:
            self.state = .paused(current: status.timestamp, duration: status.duration, progress: progress)
        }
    }
    
    public func setProgress(_ progress: TimeInterval) {
        guard progress.isFinite, status.duration.isFinite, status.duration > 0 else {
            return
        }
        let progress = min(max(progress, 0), 1)
        self.status = status.withUpdatedTimestamp(status.duration * progress)
        switch status.status {
        case .playing:
            self.state = .playing(current: status.timestamp, duration: status.duration, progress: progress)
        case .paused:
            self.state = .paused(current: status.timestamp, duration: status.duration, progress: progress)
        default:
            break
        }
    }
    
    private var _state: APState = .waiting
    public fileprivate(set) var state:APState {
        get {
            return _state
        }
        set {
            _state = newValue
            _stateValue.set(.single(newValue))
        }
    }

    private let _stateValue:Promise<APState> = Promise()
    public var stateValue: Signal<APState, NoError> {
        return _stateValue.get()
    }
    
    public fileprivate(set) var entry:APEntry
    public let account:Account
    public init(_ entry:APEntry, _ account:Account) {
        self.entry = entry
        self.account = account
    }
    public var stableId:ChatHistoryEntryId {
        return .undefined
    }
}

public func ==(lhs:APItem, rhs:APItem) -> Bool {
    return lhs.stableId == rhs.stableId
}



public class APSongItem : APItem {
    public private(set) var songName:String
    public private(set) var performerName:String
    public private(set) var resource:TelegramMediaResource
    public private(set) var ext:String

    public override init(_ entry:APEntry, _ account:Account) {
        
        if case let .song(message) = entry {
            let file = (message.anyMedia as! TelegramMediaFile)
            resource = file.resource
            if let _ = file.mimeType.range(of: "m4a") {
                self.ext = "m4a"
            } else if let _ = file.mimeType.range(of: "mp4") {
                self.ext = "mp4"
            } else if let ext = file.fileName?.nsstring.pathExtension {
                self.ext = ext
            } else {
                self.ext = "mp3"
            }
            if file.isVoice || file.isInstantVideo {
                if let forward = message.forwardInfo {
                    songName = forward.authorTitle
                } else if let peer = message.author {
                    if peer.id == account.peerId {
                        songName = localizedString("You");
                    } else {
                        songName = peer.displayTitle
                    }
                } else {
                    songName = ""
                }
                if file.isVoice {
                    performerName = strings().audioControllerVoiceMessage
                } else {
                    performerName = strings().audioControllerVideoMessage
                }
            }  else {
                var t:String?
                var p:String?

                for attribute in file.attributes {
                    if case let .Audio(_, _, title, performer, _) = attribute {
                        t = title
                        p = performer
                        break
                    }
                }
                if let t = t {
                    songName = t
                } else {
                    songName = p != nil ? strings().audioUntitledSong : ""
                }
                if let p = p {
                    performerName = p
                } else {
                    performerName = file.fileName ?? strings().audioUnknownArtist
                }
            }


        } else if case let .single(wrapper) = entry {
            resource = wrapper.resource
            if let name = wrapper.name {
                songName = name
            } else {
                songName = ""
            }
            if let performer = wrapper.performer {
                performerName = performer
            } else {
                performerName = ""
            }
            if let _ = wrapper.mimeType.range(of: "m4a") {
                self.ext = "m4a"
            } else if let _ = wrapper.mimeType.range(of: "mp4") {
                self.ext = "mp4"
            } else {
                self.ext = "mp3"
            }
        } else if case let .savedMusic(reference, _) = entry {
            let file = reference.media
            resource = file.resource
            if let _ = file.mimeType.range(of: "m4a") {
                self.ext = "m4a"
            } else if let _ = file.mimeType.range(of: "mp4") {
                self.ext = "mp4"
            } else if let ext = file.fileName?.nsstring.pathExtension {
                self.ext = ext
            } else {
                self.ext = "mp3"
            }
            var t:String?
            var p:String?

            for attribute in file.attributes {
                if case let .Audio(_, _, title, performer, _) = attribute {
                    t = title
                    p = performer
                    break
                }
            }
            if let t = t {
                songName = t
            } else {
                songName = p != nil ? strings().audioUntitledSong : ""
            }
            if let p = p {
                performerName = p
            } else {
                performerName = file.fileName ?? strings().audioUnknownArtist
            }
        } else {
            fatalError("🤔")
        }
        super.init(entry, account)
    }

    fileprivate func updateMetadata(from item: APSongItem) {
        self.entry = item.entry
        self.songName = item.songName
        self.performerName = item.performerName
        self.resource = item.resource
        self.ext = item.ext
    }

    public override var stableId: ChatHistoryEntryId {
        return entry.stableId
    }
    
    public var isPaused: Bool {
        switch self.state {
        case .paused:
            return true
        default:
            return false
        }
    }
    public var isFetching: Bool {
        switch self.state {
        case .fetching:
            return true
        default:
            return false
        }
    }
    
    public var reference: MediaResourceReference {
        switch entry {
        case let .song(message):
            return FileMediaReference.message(message: MessageReference(message), media: message.anyMedia as! TelegramMediaFile).resourceReference(resource)
        case let .savedMusic(reference, _):
            return reference.resourceReference(reference.media.resource)
        default:
            return MediaResourceReference.standalone(resource: resource)
        }
    }
    
    public var coverFileMediaReference: FileMediaReference? {
        if let coverResource = coverResource {
            let previewRepresentations = [TelegramMediaImageRepresentation(dimensions: PixelDimensions(PeerMediaIconSize), resource: coverResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)]
            let coverFile = TelegramMediaFile(fileId: MediaId(namespace: 0, id: arc4random64()), partialReference: nil, resource: resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: ext, size: nil, attributes: [], alternativeRepresentations: [])

            switch self.entry {
            case let .song(message):
                return FileMediaReference.message(message: MessageReference(message), media: coverFile)
            default:
                return FileMediaReference.standalone(media: coverFile)
            }
        }
        return nil
    }
    
    public var coverResource: TelegramMediaResource? {
        switch entry {
        case let .song(message):
            if let file = message.anyMedia as? TelegramMediaFile {
                if file.previewRepresentations.isEmpty {
                    if ext == "mp3" {
                        return ExternalMusicAlbumArtResource(title: file.musicText.0, performer: file.musicText.1, isThumbnail: true)
                    } else {
                        return nil
                    }
                } else {
                    return file.previewRepresentations.first!.resource
                }
            } else {
                if ext == "mp3" {
                    return ExternalMusicAlbumArtResource(title: songName, performer: performerName, isThumbnail: true)
                } else {
                    return nil
                }
            }
        default:
            if ext == "mp3" {
                return ExternalMusicAlbumArtResource(title: songName, performer: performerName, isThumbnail: true)
            } else {
                return nil
            }
        }
    }

    public var duration: Double? {
        switch entry {
        case let .song(message):
            return (message.anyMedia as? TelegramMediaFile)?.duration
        case let .single(wrapper):
            return wrapper.duration
        case let .savedMusic(reference, _):
            return reference.media.duration
        }
    }
    
    public var userLocation: MediaResourceUserLocation {
        switch entry {
        case let .song(message):
            return .peer(message.id.peerId)
        default:
            return .other
        }
    }

    fileprivate func pullResource() -> Signal<APResource, NoError> {
        let mediaBox = self.account.postbox.mediaBox
        let resource = self.resource
        let reference = self.reference
        let userLocation = self.userLocation
        let ext = self.ext
        return Signal { subscriber in
            let disposables = DisposableSet()
            disposables.add(fetchedMediaResource(mediaBox: mediaBox, userLocation: userLocation, userContentType: .audio, reference: reference).start())
            let status = mediaBox.resourceStatus(resource)
            |> deliverOnMainQueue
            |> mapToSignal { status -> Signal<APResource, NoError> in
                switch status {
                case .Local:
                    return mediaBox.resourceData(resource)
                    |> filter { $0.complete }
                    |> map { data -> APResource in
                        return APResource(complete: data.complete, progress: 1, path: link(path: data.path, ext: ext)!)
                    }
                case .Remote:
                    return .complete()
                case let .Fetching(_, progress), let .Paused(progress):
                    return .single(APResource(complete: false, progress: progress, path: ""))
                }
            }
            disposables.add((status |> deliverOnMainQueue).start(next: subscriber.putNext, completed: subscriber.putCompletion))
            return disposables
        }
    }


}

public struct APTransition {
    public let inserted:[(Int,APItem)]
    public let removed:[Int]
    public let updated:[(Int,APItem)]
    public init(inserted: [(Int,APItem)], removed: [Int], updated: [(Int,APItem)]) {
        self.inserted = inserted
        self.removed = removed
        self.updated = updated
    }
}

fileprivate func prepareItems(from:[APEntry]?, to:[APEntry], account:Account) -> Signal<APTransition, NoError> {
    return Signal {(subscriber) in
        let (removed, inserted, updated) = proccessEntries(from, right: to, { (entry) -> APItem in
            return APSongItem(entry,account)
        })
        subscriber.putNext(APTransition(inserted: inserted, removed: removed, updated:updated))
        subscriber.putCompletion()
        return EmptyDisposable

    } |> runOn(prepareQueue)
}

public enum APHistoryLocation : Equatable {
    case initial
    case index(MessageIndex)
}

public enum APEntry : Comparable, Identifiable {
    case song(Message)
    case single(APSingleWrapper)
    case savedMusic(FileMediaReference, Int32)
    public var stableId: ChatHistoryEntryId {
        switch self {
        case let .song(message):
            return message.chatStableId
        case let .single(wrapper):
            if let stableId = wrapper.id.base as? ChatHistoryEntryId {
                return stableId
            }
            return .maybeId(wrapper.id)
        case let .savedMusic(reference, _):
            return .maybeId(reference.media.fileId)
        }
    }

    public func isEqual(to wrapper:APSingleWrapper) -> Bool {
        return stableId == .maybeId(wrapper.id)
    }

    public func isEqual(to message:Message) -> Bool {
        return stableId == message.chatStableId
    }
    
    public func isEqual(to file: TelegramMediaFile) -> Bool {
        switch self {
        case let .song(message):
            return message.file?.fileId.id == file.fileId.id
        case let .savedMusic(reference, _):
            return reference.media.fileId.id == file.fileId.id
        case .single(_):
            return false
        }
    }
    
    public func isEqual(to messageId: MessageId) -> Bool {
        switch self {
        case let .song(message):
            return message.id == messageId
        case let .single(wrapper):
            if let stableId = wrapper.id.base as? ChatHistoryEntryId {
                switch stableId {
                case let .message(message):
                    return message.id == messageId
                default:
                    break
                }
            }
        case let .savedMusic(reference, _):
            return mapInt64ToInt32(reference.media.fileId.id) == messageId.id
        }
        return false
    }

    public var index: MessageIndex {
        switch self {
        case let .song(message):
            return MessageIndex(message)
        case let .savedMusic(_, index):
            return MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: index), timestamp: 0)
        case .single(_):
            return MessageIndex.absoluteLowerBound()
        }
    }
}

public func ==(lhs:APEntry, rhs:APEntry) -> Bool {
    switch lhs {
    case let .song(lhsMessage):
        if case let .song(rhsMessage) = rhs, isEqualMessages(lhsMessage, rhsMessage) {
            return true
        } else {
            return false
        }
    case .single(_):
        return false
    case let .savedMusic(reference, index):
        if case .savedMusic(let rhsReference, index) = rhs {
            return reference.media == rhsReference.media
        } else {
            return false
        }
    }
}

public func <(lhs:APEntry, rhs:APEntry) -> Bool {
    return lhs.index < rhs.index
}

private struct APHistory {
    public let original:MessageHistoryView
    public let filtred:[APEntry]
}

public func ==(lhs:APHistoryLocation, rhs:APHistoryLocation) -> Bool {
    switch lhs {
    case .initial:
        if case .initial = rhs {
            return true
        } else {
            return false
        }
    case let .index(lhsIndex):
        if case let .index(rhsIndex) = rhs, lhsIndex == rhsIndex {
            return true
        } else {
            return false
        }
    }
}

public protocol APDelegate : AnyObject {
    func songDidChanged(song:APSongItem, for controller:APController, animated: Bool)
    func songDidChangedState(song:APSongItem, for controller:APController, animated: Bool)
    func songDidStartPlaying(song:APSongItem, for controller:APController, animated: Bool)
    func songDidStopPlaying(song:APSongItem, for controller:APController, animated: Bool)
    func playerDidChangedTimebase(song:APSongItem, for controller:APController, animated: Bool)
    func audioDidCompleteQueue(for controller:APController, animated: Bool)
}

public final class MediaPlaybackControlCenter {
    private static weak var activeOwner: MediaPlaybackControlCenter?
    private static var activeOwnerId: UUID?
    private static weak var persistentOwner: MediaPlaybackControlCenter?
    private let ownerId = UUID()
    private(set) var commandGeneration: UInt64 = 0
    private let artworkDisposable = MetaDisposable()
    private var artworkGeneration: UInt64 = 0
    private var artworkResourceId: MediaResourceId?
    private var artwork: MPMediaItemArtwork?
    private var nowPlayingInfo: [String: Any]?
    var restoreNowPlaying: (() -> Bool)?

    public func activate() {
        if restoreNowPlaying != nil {
            Self.persistentOwner = self
        }
        if Self.activeOwnerId != self.ownerId {
            Self.activeOwner?.removeRemoteTransportControls()
            Self.activeOwner = self
            Self.activeOwnerId = self.ownerId
        }
        self.setupRemoteTransportControls()
    }

    
    public var nextTrack:()->Bool = { return false }
    public var prevTrack:()->Bool = { return false }
    public var play:()->Bool = { return false }
    public var pause:()->Bool = { return false }
    public var togglePlayPause:()->Bool = { return false }
    public var seek:(TimeInterval)->Bool = { _ in return false }

    private var playCommand: Any?
    private var pauseCommand: Any?
    private var nextCommand: Any?
    private var prevCommand: Any?
    private var togglePlayPauseCommand: Any?
    private var playbackPositionCommand: Any?
    
    public init() {
    }

    func setupNowPlaying(_ song: APSongItem, account: Account) {
        guard Self.activeOwnerId == self.ownerId else { return }

        let resource = song.coverResource
        let resourceChanged = self.artworkResourceId != resource?.id
        if resourceChanged {
            self.resetArtwork()
            self.artworkResourceId = resource?.id
        }
        
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.songName
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.performerName
        let timestamp: Double
        let duration: Double
        let rate: Double
        switch song.state {
        case let .playing(current, length, _):
            timestamp = current
            duration = length
            rate = song.status.baseRate
        case let .paused(current, length, _):
            timestamp = current
            duration = length
            rate = 0
        default:
            timestamp = song.status.timestamp
            duration = song.status.duration
            rate = 0
        }
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        let safeTimestamp = timestamp.isFinite ? min(safeDuration, max(0, timestamp)) : 0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = safeDuration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = safeTimestamp
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate.isFinite ? max(0, rate) : 0
        if #available(macOS 10.13.2, *), let artwork = self.artwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        self.nowPlayingInfo = nowPlayingInfo
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo

        switch song.state {
        case .playing:
            nowPlayingInfoCenter.playbackState = .playing
        case .stoped:
            nowPlayingInfoCenter.playbackState = .stopped
        default:
            nowPlayingInfoCenter.playbackState = .paused
        }

        if #available(macOS 10.13.2, *), resourceChanged, let resource {
            let generation = self.artworkGeneration
            let disposable = MetaDisposable()
            self.artworkDisposable.set(disposable)
            disposable.set((account.postbox.mediaBox.resourceData(resource)
            |> filter { $0.complete }
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] data in
                guard let self, Self.activeOwnerId == self.ownerId, self.artworkGeneration == generation,
                      self.artworkResourceId == resource.id,
                      let image = NSImage(contentsOfFile: data.path),
                      var info = self.nowPlayingInfo else {
                    return
                }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.artwork = artwork
                info[MPMediaItemPropertyArtwork] = artwork
                self.nowPlayingInfo = info
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }))
        }
    }

    public func setupNowPlaying(videoTitle: String, status: MediaPlayerStatus) {
        guard Self.activeOwnerId == self.ownerId else { return }
        let duration = status.duration.isFinite ? max(0, status.duration) : 0
        let timestamp = status.timestamp.isFinite ? min(duration, max(0, status.timestamp)) : 0
        let isPlaying: Bool
        let rate: Double
        switch status.status {
        case .playing:
            isPlaying = true
            rate = status.baseRate.isFinite ? max(0, status.baseRate) : 0
        case let .buffering(_, whilePlaying):
            isPlaying = whilePlaying
            rate = 0
        case .paused:
            isPlaying = false
            rate = 0
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: videoTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: timestamp,
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ]
        self.nowPlayingInfo = info
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func resetArtwork() {
        self.artworkGeneration &+= 1
        self.artworkDisposable.set(nil)
        self.artworkResourceId = nil
        self.artwork = nil
    }
    
    private var commandTargets: [Any?] {
        return [playCommand, pauseCommand, nextCommand, prevCommand, togglePlayPauseCommand, playbackPositionCommand]
    }

    private static func removeTargets(_ targets: [Any?]) {
        let commandCenter = MPRemoteCommandCenter.shared()
        let commands = [commandCenter.playCommand, commandCenter.pauseCommand, commandCenter.nextTrackCommand, commandCenter.previousTrackCommand, commandCenter.togglePlayPauseCommand, commandCenter.changePlaybackPositionCommand]
        for (command, target) in zip(commands, targets) {
            if let target {
                command.removeTarget(target)
            }
        }
    }

    private func removeRemoteTransportControls() {
        self.commandGeneration &+= 1
        self.resetArtwork()
        self.nowPlayingInfo = nil
        Self.removeTargets(self.commandTargets)
        self.playCommand = nil
        self.pauseCommand = nil
        self.nextCommand = nil
        self.prevCommand = nil
        self.togglePlayPauseCommand = nil
        self.playbackPositionCommand = nil
    }

    private static func clearOwner(_ ownerId: UUID) {
        if Self.persistentOwner?.ownerId == ownerId {
            Self.persistentOwner = nil
        }
        guard Self.activeOwnerId == ownerId else { return }
        Self.activeOwner = nil
        Self.activeOwnerId = nil
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingInfoCenter.playbackState = .stopped
        if let owner = Self.persistentOwner {
            owner.activate()
            if owner.restoreNowPlaying?() != true {
                owner.clearNowPlaying()
            }
        }
    }

    public func clearNowPlaying() {
        self.removeRemoteTransportControls()
        Self.clearOwner(self.ownerId)
    }

    deinit {
        self.artworkDisposable.dispose()
        let targets = self.commandTargets
        let ownerId = self.ownerId
        let release = {
            Self.removeTargets(targets)
            Self.clearOwner(ownerId)
        }
        if Thread.isMainThread {
            release()
        } else {
            DispatchQueue.main.async(execute: release)
        }
    }

    public func updateControlsAvaiability(nextEnabled: Bool, prevEnabled: Bool, seekEnabled: Bool = true) {
        guard Self.activeOwnerId == self.ownerId else { return }
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = prevEnabled
        commandCenter.nextTrackCommand.isEnabled = nextEnabled
        commandCenter.changePlaybackPositionCommand.isEnabled = seekEnabled
    }
    
    func performCommand(generation: UInt64, action: (MediaPlaybackControlCenter) -> Bool) -> MPRemoteCommandHandlerStatus {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                self.performCommand(generation: generation, action: action)
            }
        }
        guard Self.activeOwnerId == self.ownerId, self.commandGeneration == generation else { return .commandFailed }
        return action(self) ? .success : .commandFailed
    }

    public func setupRemoteTransportControls() {
        guard Self.activeOwnerId == self.ownerId, self.playCommand == nil else { return }
        let commandCenter = MPRemoteCommandCenter.shared()
        let generation = self.commandGeneration

        playCommand = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performCommand(generation: generation) { $0.play() }
        }

        pauseCommand = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performCommand(generation: generation) { $0.pause() }
        }

        nextCommand = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performCommand(generation: generation) { $0.nextTrack() }
        }

        prevCommand = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performCommand(generation: generation) { $0.prevTrack() }
        }

        togglePlayPauseCommand = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performCommand(generation: generation) { $0.togglePlayPause() }
        }

        playbackPositionCommand = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent, event.positionTime.isFinite else { return .commandFailed }
            return self.performCommand(generation: generation) { $0.seek(event.positionTime) }
        }
    }
}


public class APController : NSResponder {

    public struct State : Equatable {
        public enum Status : Equatable {
            case playing
            case paused
            case waiting
            case stopped
        }
        public enum RepeatState {
            case none
            case circle
            case one
        }
        public enum OrderState {
            case normal
            case reversed
            case random
        }
        public fileprivate(set) var status: Status
        public fileprivate(set) var repeatState: RepeatState
        public fileprivate(set) var orderState: OrderState
        
        public fileprivate(set) var volume: Float
        public fileprivate(set) var baseRate: Double
        
        public static var `default`:State {
            return State(status: .waiting, repeatState: .none, orderState: .normal, volume: 1, baseRate: 1.0)
        }

    }
    
    private var mediaPlayer: MediaPlayer?
    fileprivate var playbackGeneration: UInt64 = 0
    private var playlistGeneration: UInt64 = 0
    private var completingPlaylistGeneration: UInt64?
    
    private let controlCenter: MediaPlaybackControlCenter
   
    private let statusDisposable = MetaDisposable()
    private let readyDisposable = MetaDisposable()


    private let statePromise = ValuePromise(State.default, ignoreRepeated: true)
    public var stateValue: Signal<State, NoError> {
        return statePromise.get()
    }
    public private(set) var state: State = State.default {
        didSet {
            statePromise.set(self.state)
            if oldValue != state {
                if oldValue.baseRate != state.baseRate {
                    mediaPlayer?.setBaseRate(state.baseRate)
                }
                if oldValue.volume != state.volume {
                    mediaPlayer?.setVolume(state.volume)
                }
                notifyGlobalStateChanged(animated: true)
                

            }
        }
    }

    public let ready:Promise<Bool> = Promise()
    public let context: (any AccountContextProtocol)
    
    public var account: Account {
        return context.account
    }
    
    private var _timebase: CMTimebase?

    fileprivate let history:Promise<APHistoryLocation> = Promise()
    fileprivate let entries:Atomic<APHistory?> = Atomic(value:nil)
    fileprivate let items:Atomic<[APItem]> = Atomic(value:[])
    fileprivate let disposable:MetaDisposable = MetaDisposable()

    fileprivate let itemDisposable:MetaDisposable = MetaDisposable()
    fileprivate let songStateDisposable:MetaDisposable = MetaDisposable()
    fileprivate let timebaseDisposable:MetaDisposable = MetaDisposable()
    private var listeners:[WeakReference<NSObject>] = []

   // fileprivate var player:AudioPlayer?
    fileprivate var current:Int = -1
    fileprivate var played:[Int] = []

    private let bufferingStatusValuePromise = Promise<(RangeSet<Int64>, Int64)?>()
    
    
    public private(set) var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> {
        set {
           self.bufferingStatusValuePromise.set(newValue |> deliverOnMainQueue)
        }
        get {
            return bufferingStatusValuePromise.get()
        }
    }

    
    fileprivate var timer:SwiftSignalKit.Timer?

    fileprivate var prevNextDisposable = DisposableSet()

    private var _song:APSongItem?
    fileprivate var song:APSongItem? {
        set {
            let generation = self.playlistGeneration
            let playbackGeneration = self.playbackGeneration &+ 1
            self.stop()
            guard self.playlistGeneration == generation, self.playbackGeneration == playbackGeneration else { return }
            self._song = newValue
            let subscription = MetaDisposable()
            self.songStateDisposable.set(subscription)
            if let song = newValue {
                subscription.set((song.stateValue |> distinctUntilChanged).start(next: { [weak self, weak song] _ in
                    guard let self, let song, self.playlistGeneration == generation, self.song === song else { return }
                    self.notifyStateChanged(item: song, animated: true)
                }))
            }
        }
        get {
            return _song
        }
    }

    public var timebase:CMTimebase? {
        return _timebase//self.player?.timebase
    }

    public func notifyGlobalStateChanged(animated: Bool) {
        if let song = song {
            notifyStateChanged(item: song, animated: animated)
        }
    }

    public var isPlaying: Bool {
        if let currentSong = currentSong {
            switch currentSong.state {
            case .playing:
                return true
            default:
                return false
            }
        }
        return false
    }

    public var isDownloading: Bool {
        if let currentSong = currentSong {
            switch currentSong.state {
            case .fetching:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func notifyStateChanged(item:APSongItem, animated: Bool) {
        let generation = self.playlistGeneration
        guard self.song === item else { return }
        for listener in listeners {
            guard self.playlistGeneration == generation, self.song === item else { return }
            if let value = listener.value as? APDelegate {
                value.songDidChangedState(song: item, for: self, animated: animated)
            }
        }
        guard self.playlistGeneration == generation, self.song === item else { return }
        self.controlCenter.setupNowPlaying(item, account: self.account)
        guard self.playlistGeneration == generation, self.song === item else { return }
        self.controlCenter.updateControlsAvaiability(nextEnabled: self.nextEnabled, prevEnabled: self.prevEnabled)
    }

    private func notifySongChanged(item:APSongItem, animated: Bool) {
        let generation = self.playlistGeneration
        guard self.song === item else { return }
        for listener in self.listeners {
            guard self.playlistGeneration == generation, self.song === item else { return }
            if let value = listener.value as? APDelegate {
                value.songDidChanged(song: item, for: self, animated: animated)
            }
        }
        guard self.playlistGeneration == generation, self.song === item else { return }
        self.controlCenter.setupNowPlaying(item, account: self.account)
        guard self.playlistGeneration == generation, self.song === item else { return }
        self.controlCenter.updateControlsAvaiability(nextEnabled: self.nextEnabled, prevEnabled: self.prevEnabled)
    }

    private func notifySongDidChangedTimebase(item:APSongItem, animated: Bool) {
        let generation = self.playlistGeneration
        guard self.song === item else { return }
        for listener in self.listeners {
            guard self.playlistGeneration == generation, self.song === item else { return }
            if let value = listener.value as? APDelegate {
                value.playerDidChangedTimebase(song: item, for: self, animated: animated)
            }
        }
    }



    private func notifySongDidStopPlaying(item:APSongItem, animated: Bool) {
        let generation = self.playlistGeneration
        guard self.song === item else { return }
        for listener in self.listeners {
            guard self.playlistGeneration == generation, self.song === item else { return }
            if let value = listener.value as? APDelegate {
                value.songDidStopPlaying(song: item, for: self, animated: animated)
            }
        }
    }

    public func notifyCompleteQueue(animated: Bool) {
        let generation = self.playlistGeneration
        for listener in self.listeners {
            guard self.playlistGeneration == generation else { return }
            if let value = listener.value as? APDelegate {
                value.audioDidCompleteQueue(for: self, animated: animated)
            }
        }
    }

    private let streamable: Bool
    public var baseRate: Double {
        set {
            state.baseRate = newValue
        }
        get {
            return state.baseRate
        }
    }
    
    public var volume: Float {
        set {
            state.volume = newValue
        }
        get {
            return state.volume
        }
    }
    public init(context: (any AccountContextProtocol), streamable: Bool, baseRate: Double, volume: Float) {
        self.context = context
        self.state.volume = volume
        self.streamable = streamable
        self.state.baseRate = baseRate
        self.controlCenter = MediaPlaybackControlCenter()
        super.init()
        
        controlCenter.play = { [weak self] in
            return self?.play() ?? false
        }
        controlCenter.pause = { [weak self] in
            return self?.pause() ?? false
        }
        controlCenter.togglePlayPause = { [weak self] in
            return self?.playOrPause() ?? false
        }
        controlCenter.nextTrack = { [weak self] in
            return self?.next() ?? false
        }
        controlCenter.prevTrack = { [weak self] in
            return self?.prev() ?? false
        }
        controlCenter.seek = { [weak self] timestamp in
            return self?.set(seek: timestamp) ?? false
        }
        controlCenter.restoreNowPlaying = { [weak self] in
            guard let self, let song = self.song else { return false }
            self.controlCenter.setupNowPlaying(song, account: self.account)
            self.controlCenter.updateControlsAvaiability(nextEnabled: self.nextEnabled, prevEnabled: self.prevEnabled)
            return true
        }
    }

    @objc open func windowDidBecomeKey() {
        
    }


    @objc open func windowDidResignKey() {
       
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func start() {
        
    }


    fileprivate func merge(with transition:APTransition) {

        let previous:[APItem] = self.items.modify({$0})
        let current = self.current
        var updatedCurrentMetadata = false
        let items = self.items.modify { items -> [APItem] in
            var new:[APItem] = items
            for rdx in transition.removed.reversed() {
                new.remove(at: rdx)
            }
            for (idx,item) in transition.inserted {
                new.insert(item, at: idx)
            }
            for (idx,item) in transition.updated {
                new[idx] = item
            }
            if let song = self.song,
               let index = new.firstIndex(where: { $0.stableId == song.stableId }),
               let updated = new[index] as? APSongItem,
               updated !== song, updated.resource.id == song.resource.id {
                song.updateMetadata(from: updated)
                new[index] = song
                updatedCurrentMetadata = true
            }
            return new
        }

        self.played = self.played.compactMap { index in
            guard previous.indices.contains(index) else { return nil }
            return items.firstIndex(where: { $0.stableId == previous[index].stableId })
        }

        guard current >= 0 else { return }
        guard let previousCurrent = previous.indices.contains(current) ? previous[current] : self.song else {
            self.current = -1
            return
        }
        if let index = items.firstIndex(where: { $0.stableId == previousCurrent.stableId }) {
            self.current = index
            if let song = self.song, let updated = items[index] as? APSongItem, song !== updated {
                if self.state.status == .playing {
                    self.dequeueCurrent()
                } else {
                    self.complete()
                }
                return
            }
            if current != index || previous.count != items.count || !transition.updated.isEmpty || updatedCurrentMetadata {
                if let song = self.song {
                    self.notifyStateChanged(item: song, animated: false)
                }
            }
            return
        }

        guard self.state.status == .playing, !items.isEmpty else {
            self.current = -1
            self.complete()
            return
        }

        var nextIndex: Int?
        switch self.state.orderState {
        case .normal, .reversed:
            if let previousIndex = previous.firstIndex(where: { $0.stableId == previousCurrent.stableId }) {
                let candidates: [APItem]
                if self.state.orderState == .normal {
                    candidates = Array(previous[..<previousIndex].reversed())
                } else {
                    candidates = Array(previous[(previousIndex + 1)...])
                }
                for candidate in candidates {
                    if let index = items.firstIndex(where: { $0.stableId == candidate.stableId }) {
                        nextIndex = index
                        break
                    }
                }
            }
            if nextIndex == nil, self.state.repeatState == .circle {
                nextIndex = self.state.orderState == .normal ? items.count - 1 : 0
            }
        case .random:
            nextIndex = items.indices.randomElement()
        }
        if let nextIndex {
            self.current = nextIndex
            self.dequeueCurrent()
        } else {
            self.current = -1
            self.complete()
        }
    }

    fileprivate var pullItems:[APItem] {
        return items.with { $0 }
    }
    
    public func nextOrderState() {
        switch self.state.orderState {
        case .normal:
            self.state.orderState = .reversed
        case .reversed:
            self.state.orderState = .random
        case .random:
            self.state.orderState = .normal
        }
    }
    public func nextRepeatState() {
        switch self.state.repeatState {
        case .none:
            self.state.repeatState = .circle
        case .circle:
            self.state.repeatState = .one
        case .one:
            self.state.repeatState = .none
        }
    }
    
    public var canMakeRepeat: Bool {
        return false
    }
    public var canMakeOrder: Bool {
        return false
    }

    public func playOrPause() -> Bool {
        if let _ = song {
            if case .playing = state.status {
                mediaPlayer?.pause()
                state.status = .paused
            } else if case .paused = state.status {
                self.controlCenter.activate()
                mediaPlayer?.play()
                state.status = .playing
            } else if state.status == .stopped {
                dequeueCurrent()
            }
        }
        return true
    }
    
    public func playOrPause(_ id: APSingleWrapper) -> Bool {
        return playOrPause(pullItems.firstIndex(where: { $0.entry.isEqual(to: id) }))
    }
    
    public func playOrPause(_ id: MessageId) -> Bool {
        return playOrPause(pullItems.firstIndex(where: { $0.entry.isEqual(to: id) }))
    }

    private func playOrPause(_ index: Int?) -> Bool {
        if let index = index {
            if index != self.current, current != -1 {
                self.current = index
                dequeueCurrent()
            } else {
                _ = playOrPause()
            }
            return true
        } else {
            return false
        }
    }
    
    public func pause() -> Bool {
        if let song = song {
            if case  .playing = song.state {
                mediaPlayer?.pause()
                state.status = .paused
                return true
            }
        }
        return false
    }

    public func play() -> Bool {
        if let _ = song {
            if case .paused = state.status {
                self.controlCenter.activate()
                mediaPlayer?.play()
                state.status = .playing
                return true
            }
        }
        return false
    }
    
    
    @discardableResult public func next() -> Bool {
        if !nextEnabled {
            return false
        }
        switch self.state.orderState {
        case .normal:
            if current == 0 {
                current = pullItems.count - 1
            } else {
                current -= 1
            }
        case .reversed:
            if current == pullItems.count - 1 {
                current = 0
            } else {
                current += 1
            }
        case .random:
            played.append(current)
            current = Int.random(in: 0 ..< pullItems.count)
        }
        
        dequeueCurrent()
        return true
    }

    @discardableResult public func prev() -> Bool {
        if !prevEnabled {
            return false
        }
        switch self.state.orderState {
        case .normal:
            if current == pullItems.count - 1 {
                current = 0
            } else {
                current += 1
            }
        case .reversed:
            if current == 0 {
                current = pullItems.count - 1
            } else {
                current -= 1
            }
        case .random:
            if !played.isEmpty {
                current = played.removeLast()
            } else {
                current = Int.random(in: 0 ..< pullItems.count)
            }
        }
        
        dequeueCurrent()
        return true
    }

    public var nextEnabled:Bool {
        return pullItems.count > 1
    }


    public var prevEnabled:Bool {
        return pullItems.count > 1
    }

    public var needNext:Bool {
        return true
    }

    public func complete() {
        guard self.completingPlaylistGeneration != self.playlistGeneration else { return }
        self.playlistGeneration &+= 1
        let generation = self.playlistGeneration
        self.completingPlaylistGeneration = generation
        defer {
            if self.completingPlaylistGeneration == generation {
                self.completingPlaylistGeneration = nil
            }
        }
        self.notifyCompleteQueue(animated: true)
        guard self.playlistGeneration == generation else { return }
        self.state.status = .stopped
        guard self.playlistGeneration == generation else { return }
        self.cleanup()
    }

    public var currentSong:APSongItem? {
        if !pullItems.isEmpty, pullItems.count > current, let song = pullItems[max(0, current)] as? APSongItem {
            return song
        }
        return nil
    }

    fileprivate func dequeueCurrent() {
        self.playlistGeneration &+= 1
        let generation = self.playlistGeneration
        if self.current < 0, !self.pullItems.isEmpty {
            self.current = 0
        }
        if let current = currentSong {
            let playbackGeneration = self.playbackGeneration &+ 1
            self.song = current
            guard self.playlistGeneration == generation, self.playbackGeneration == playbackGeneration, self.song === current else { return }
            play(with: current)
            guard self.playlistGeneration == generation, self.playbackGeneration == (playbackGeneration &+ 1), self.song === current else { return }
            notifySongChanged(item: current, animated: true)
        }
    }


    fileprivate func play(with item:APSongItem) {
        self.playbackGeneration &+= 1
        let generation = self.playbackGeneration

        let player = MediaPlayer(postbox: account.postbox, userLocation: item.userLocation, userContentType: .audio, reference: item.reference, streamable: streamable, video: false, preferSoftwareDecoding: false, enableSound: true, baseRate: baseRate, volume: self.volume, fetchAutomatically: false)
        
        self.mediaPlayer = player
        self.controlCenter.activate()
        player.actionAtEnd = .action({ [weak self, weak player] in
            Queue.mainQueue().async {
                guard let self, let player, self.playbackGeneration == generation, self.mediaPlayer === player else { return }
                self.audioPlayerDidFinishPlaying()
            }
        })
        state.status = .playing
        guard self.playbackGeneration == generation, self.mediaPlayer === player else { return }
        player.play()

        
        let size = item.resource.size ?? 0
        bufferingStatus = account.postbox.mediaBox.resourceRangesStatus(item.resource)
            |> map { ranges -> (RangeSet<Int64>, Int64) in
                return (ranges, size)
        }
        guard self.playbackGeneration == generation, self.mediaPlayer === player else { return }
        
        let timebaseSubscription = MetaDisposable()
        self.timebaseDisposable.set(timebaseSubscription)
        timebaseSubscription.set((player.timebase |> deliverOnMainQueue).start(next: { [weak self, weak player] timebase in
            guard let self, let player, self.playbackGeneration == generation, self.mediaPlayer === player else { return }
            self._timebase = timebase
            self.notifySongDidChangedTimebase(item: item, animated: true)
        }))
        guard self.playbackGeneration == generation, self.mediaPlayer === player else { return }

        let statusSubscription = MetaDisposable()
        self.statusDisposable.set(statusSubscription)
        statusSubscription.set((player.status |> deliverOnMainQueue).start(next: { [weak self, weak player] status in
            guard let self, let player, self.playbackGeneration == generation, self.mediaPlayer === player else { return }
            item.setStatus(status, rate: self.baseRate)
            guard self.playbackGeneration == generation, self.mediaPlayer === player else { return }
            switch status.status {
            case .paused:
                self.stopTimer()
            case .playing:
                self.startTimer()
            default:
                self.stopTimer()
            }
            self.updateUIAfterTick(status)
        }))

        guard self.playbackGeneration == generation, self.mediaPlayer === player else { return }
        if !streamable {
            let resourceSubscription = MetaDisposable()
            self.itemDisposable.set(resourceSubscription)
            resourceSubscription.set(item.pullResource().start(next: { [weak self, weak player] resource in
                if let strongSelf = self, let player, strongSelf.playbackGeneration == generation, strongSelf.mediaPlayer === player {
                    if resource.complete {
                        let items = strongSelf.items.modify({$0}).filter({$0 is APSongItem}).map{$0 as! APSongItem}
                        let mediaBox = strongSelf.account.postbox.mediaBox
                        if let index = items.firstIndex(of: item) {
                            let previous = index - 1
                            let next = index + 1
                            if previous >= 0 {
                                strongSelf.prevNextDisposable.add(fetchedMediaResource(mediaBox: mediaBox, userLocation: items[previous].userLocation, userContentType: .audio, reference: items[previous].reference, statsCategory: .audio).start())
                            }
                            if next < items.count {
                                strongSelf.prevNextDisposable.add(fetchedMediaResource(mediaBox: mediaBox, userLocation: items[next].userLocation, userContentType: .audio, reference: items[next].reference, statsCategory: .audio).start())
                            }
                        }
                        
                    } else {
                        item.state = .fetching(resource.progress)
                    }
                }
            }))
        }
        
    }


    public var currentTime: TimeInterval {
        if let current = currentSong {
            switch current.state {
            case let .paused(current, _, _), let .playing(current, _, _):
                return current
            default:
                break
            }
        }
        return 0//self.player?.currentTime ?? 0
    }

    public var duration: TimeInterval {
        if let current = currentSong {
            switch current.state {
            case let .paused(_, duration, _), let .playing(_, duration, _):
                return duration
            default:
                break
            }
        }
        return 0//self.player?.currentTime ?? 0
    }

    public var isLatest:Bool {
        return current == 0 && self.state.orderState == .normal
    }

    public func audioPlayerDidFinishPlaying() {
        let generation = self.playlistGeneration
        let playbackGeneration = self.playbackGeneration &+ 1
        self.stop()
        guard self.playlistGeneration == generation, self.playbackGeneration == playbackGeneration else { return }

        switch self.state.repeatState {
        case .one:
            self.dequeueCurrent()
        case .none:
            let isAtEnd: Bool
            switch self.state.orderState {
            case .normal:
                isAtEnd = self.current == 0
            case .reversed:
                isAtEnd = self.current == self.pullItems.count - 1
            case .random:
                isAtEnd = false
            }
            if isAtEnd {
                self.complete()
            } else if needNext && self.nextEnabled {
                self.next()
            } else {
                self.complete()
            }
        case .circle:
            if !next() {
                self.dequeueCurrent()
            }
        }
    }


    public func audioPlayerDidChangedTimebase(_ audioPLayer: MediaPlayer) {
        guard self.mediaPlayer === audioPLayer else { return }
        if let current = currentSong {
            notifySongDidChangedTimebase(item: current, animated: true)
        }
    }

    public func stop() {
        self.playbackGeneration &+= 1
        let generation = self.playbackGeneration
        let item = self.song
        let player = self.mediaPlayer
        self.mediaPlayer = nil
        player?.actionAtEnd = .stop
        player?.pause()
        self.statusDisposable.set(nil)
        self.timebaseDisposable.set(nil)
        self.itemDisposable.set(nil)
        self.prevNextDisposable.dispose()
        self.prevNextDisposable = DisposableSet()
        self._timebase = nil
        self.stopTimer()
        self.bufferingStatus = .single(nil)
        guard self.playbackGeneration == generation else { return }
        item?.state = .stoped
        guard self.playbackGeneration == generation else { return }
        if let item {
            self.notifySongDidStopPlaying(item: item, animated: false)
        }
    }

    @discardableResult public func set(trackProgress:Float) -> Bool {
        guard trackProgress.isFinite, let song = song, song.status.duration.isFinite, song.status.duration > 0 else {
            return false
        }
        return set(seek: song.status.duration * Double(min(max(trackProgress, 0), 1)))
    }
    
    @discardableResult public func set(seek: TimeInterval) -> Bool {
        guard seek.isFinite, let player = mediaPlayer, let song = song, song.status.duration.isFinite, song.status.duration > 0 else {
            return false
        }
        let timestamp = min(max(seek, 0), song.status.duration)
        stopTimer()
        player.seek(timestamp: timestamp)
        song.setProgress(timestamp / song.status.duration)
        notifyStateChanged(item: song, animated: false)
        return true
    }

    public func cleanup() {
        let generation = self.playlistGeneration
        listeners.removeAll()
        stop()
        guard self.playlistGeneration == generation else { return }
        self.controlCenter.clearNowPlaying()
    }

    private func updateUIAfterTick(_ status: MediaPlayerStatus) {
        
    }


    private func startTimer() {
        self.stopTimer()
        guard let item = self.song, let player = self.mediaPlayer else { return }
        let status = item.status
        guard status.timestamp.isFinite, status.duration.isFinite, status.duration > 0,
              status.baseRate.isFinite, status.baseRate > 0, status.generationTimestamp.isFinite else { return }
        let generation = self.playbackGeneration
        self.timer = SwiftSignalKit.Timer(timeout: 0.2, repeat: true, completion: { [weak self, weak player, weak item] in
            guard let self, let player, let item, self.playbackGeneration == generation, self.mediaPlayer === player, self.song === item else { return }
            let elapsed = status.generationTimestamp > 0 ? max(0, CACurrentMediaTime() - status.generationTimestamp) : 0
            let timestamp = status.timestamp + elapsed * status.baseRate
            guard timestamp.isFinite else { return }
            let current = min(status.duration, max(0, timestamp))
            item.state = .playing(current: current, duration: status.duration, progress: current / status.duration)
            guard self.playbackGeneration == generation else { return }
            self.updateUIAfterTick(status)
        }, queue: Queue.mainQueue())
        self.timer?.start()
    }
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        disposable.dispose()
        itemDisposable.dispose()
        songStateDisposable.dispose()
        prevNextDisposable.dispose()
        readyDisposable.dispose()
        statusDisposable.dispose()
        timebaseDisposable.dispose()
    }

    fileprivate var tags:MessageTags {
        return .music
    }

    public func add(listener:NSObject) {
        listeners.removeAll(where: { $0.value == nil })
        if !listeners.contains(where: { $0.value === listener }) {
            listeners.append(WeakReference(value: listener))
        }
    }

    public func remove(listener:NSObject) {
        listeners.removeAll(where: { $0.value == nil || $0.value === listener })
    }
}

public class APChatController : APController {

    public let chatLocationInput:ChatLocationInput
    fileprivate let mode: ChatMode
    private let index:MessageIndex?
    public let messages: [Message]
    public init(context: (any AccountContextProtocol), chatLocationInput: ChatLocationInput, mode: ChatMode, index: MessageIndex?, streamable: Bool, baseRate: Double = 1.0, volume: Float = 1.0, messages: [Message] = []) {
        self.chatLocationInput = chatLocationInput
        self.mode = mode
        self.index = index
        self.messages = messages
        super.init(context: context, streamable: streamable, baseRate: baseRate, volume: volume)
    }
    
    

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func start() {
        super.start()
        let tags = self.tags
        let tagMask:HistoryViewInputTag = .tag(tags)
        let list = self.entries
        let items = self.items
        let account = self.context.account
        let chatLocationInput = self.chatLocationInput
        let index = self.index
        let mode = self.mode
        let apply: Signal<APTransition, NoError>
        if messages.isEmpty {
            apply = history.get() |> distinctUntilChanged |> mapToSignal { location -> Signal<(MessageHistoryView, ViewUpdateType, InitialMessageHistoryData?), NoError> in
                switch mode {
                case .scheduled:
                    return account.viewTracker.scheduledMessagesViewForLocation(chatLocationInput, additionalData: [])
                default:
                    switch location {
                    case .initial:
                        return account.viewTracker.aroundMessageHistoryViewForLocation(chatLocationInput, index: MessageHistoryAnchorIndex.upperBound, anchorIndex: MessageHistoryAnchorIndex.upperBound, count: 100, fixedCombinedReadStates: nil, tag: tagMask, orderStatistics: [], additionalData: [])
                    case let .index(index):
                        return account.viewTracker.aroundMessageHistoryViewForLocation(chatLocationInput, index: MessageHistoryAnchorIndex.message(index), anchorIndex: MessageHistoryAnchorIndex.message(index), count: 100, fixedCombinedReadStates: nil, tag: tagMask, orderStatistics: [], additionalData: [])
                    }
                }
               
                
                } |> map { view -> (APHistory?,APHistory) in
                    var entries:[APEntry] = []
                    for viewEntry in view.0.entries {
                        let messages = tags.contains(.music) ? expandSharedMediaMessages([viewEntry.message], where: sharedMediaPredicate(for: tags)) : [viewEntry.message]
                        for message in messages {
                            if let media = message.anyMedia as? TelegramMediaFile, media.isMusicFile || media.isInstantVideo || media.isVoice {
                                guard message.id.peerId.isSecretChat || message.autoclearTimeout == nil else { continue }
                                entries.append(.song(message))
                            }
                        }
                    }
                    
                    let new = APHistory(original: view.0, filtred: entries)
                    return (list.swap(new),new)
                }
                |> mapToQueue { view -> Signal<APTransition, NoError> in
                    let transition = prepareItems(from: view.0?.filtred, to: view.1.filtred, account: account)
                    return transition
                } |> deliverOnMainQueue
        } else {
            var entries:[APEntry] = []
            for message in messages {
                entries.append(.song(message))
            }
            apply = prepareItems(from: [], to: entries, account: account) |> deliverOnMainQueue
        }
        

        let first:Atomic<Bool> = Atomic(value:true)
        disposable.set(apply.start(next: {[weak self] (transition) in

            let isFirst = first.swap(false)

            self?.merge(with: transition)

            if isFirst {
                if let index = index {
                    let list:[APItem] = items.with { $0 }
                    for i in 0 ..< list.count {
                        if list[i].entry.index == index {
                            self?.current = i
                            break
                        }
                    }
                }

                self?.dequeueCurrent()
                self?.ready.set(.single(true))
            }
        }))

        if let index = index {
            history.set(.single(.index(index)) |> delay(0.1, queue: Queue.mainQueue()))
        } else {
            history.set(.single(.initial) |> delay(0.1, queue: Queue.mainQueue()))
        }
    }
}

public class APChatMusicController : APChatController {

    public init(context: (any AccountContextProtocol), chatLocationInput: ChatLocationInput, mode: ChatMode, index: MessageIndex?, baseRate: Double = 1.0, volume: Float = 1.0, messages: [Message] = []) {
        super.init(context: context, chatLocationInput: chatLocationInput, mode: mode, index: index, streamable: true, baseRate: baseRate, volume: volume, messages: messages)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate override var tags: MessageTags {
        return .music
    }
    
    public override var canMakeRepeat: Bool {
        return true
    }
    public override var canMakeOrder: Bool {
        return true
    }
}

public class APChatVoiceController : APChatController {
    private let markAsConsumedDisposable = MetaDisposable()
    public init(context: (any AccountContextProtocol), chatLocationInput: ChatLocationInput, mode: ChatMode, index: MessageIndex?, baseRate: Double = 1.0, volume: Float = 1.0) {
        super.init(context: context, chatLocationInput: chatLocationInput, mode: mode, index:index, streamable: false, baseRate: baseRate, volume: volume)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var nextEnabled: Bool {
        return current > 0
    }

    public override var prevEnabled: Bool {
        return current < pullItems.count - 1
    }

    public override func play(with item: APSongItem) {
        let generation = self.playbackGeneration &+ 1
        super.play(with: item)
        guard self.playbackGeneration == generation, self.song === item else { return }
        let disposable = MetaDisposable()
        self.markAsConsumedDisposable.set(disposable)
        guard self.playbackGeneration == generation, self.song === item else { return }
        disposable.set(context.engine.messages.markMessageContentAsConsumedInteractively(messageId: item.entry.index.id).start())
    }

    deinit {
        markAsConsumedDisposable.dispose()
    }

    fileprivate override var tags: MessageTags {
        return .voiceOrInstantVideo
    }


}

public class APSingleResourceController : APController {
    public let wrapper:APSingleWrapper
    public init(context: (any AccountContextProtocol), wrapper:APSingleWrapper, streamable: Bool, baseRate: Double = 1.0, volume: Float = 1.0) {
        self.wrapper = wrapper
        super.init(context: context, streamable: streamable, baseRate: baseRate, volume: volume)
        merge(with: APTransition(inserted: [(0,APSongItem(.single(wrapper), account))], removed: [], updated: []))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func start() {
        super.start()
        ready.set(.single(true))
        dequeueCurrent()
    }

    public override var needNext: Bool {
        return false
    }
}


public class APProfileSavedController : APController {
    public let profileMusicContext: ProfileSavedMusicContext
    public let peer: EnginePeer
    
    public private(set) var currentState: ProfileSavedMusicContext.State?
    
    public init(context: (any AccountContextProtocol), peer: EnginePeer, profileMusicContext: ProfileSavedMusicContext, baseRate: Double = 1.0, volume: Float = 1.0) {
        self.peer = peer
        self.profileMusicContext = profileMusicContext
        super.init(context: context, streamable: true, baseRate: baseRate, volume: volume)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func start() {
        super.start()
        let signal = self.profileMusicContext.state
        let context = self.context
        
        let current: Atomic<[APEntry]> = Atomic(value: [])
        
        let apply: Signal<(APTransition, ProfileSavedMusicContext.State), NoError> = signal |> mapToSignal { state in
            var entries:[APEntry] = []
            for (i, file) in state.files.enumerated() {
                entries.append(APEntry.savedMusic(FileMediaReference.savedGif(media: file), Int32(i)))
            }
            return prepareItems(from: current.swap(entries), to: entries, account: context.account) |> map {
                return ($0, state)
            }
        } |> deliverOnMainQueue
        let first:Atomic<Bool> = Atomic(value:true)

        disposable.set(apply.start(next: { [weak self] (transition, state) in
            guard let self else {
                return
            }
            self.merge(with: transition)
           
            if first.swap(false) {
                if self.currentState == nil, !self.pullItems.isEmpty {
                    self.current = self.pullItems.count - 1
                }
                self.dequeueCurrent()
            }
            self.currentState = state
            
            
            self.ready.set(.single(true))
        }))
    }
    
    public override var canMakeRepeat: Bool {
        return true
    }
    
    deinit {
    }

}
