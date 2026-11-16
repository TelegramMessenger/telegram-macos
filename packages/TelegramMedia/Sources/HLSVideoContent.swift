import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import Foundation
import AppKit
import TelegramMediaResources
import RangeSet
import HLSPlayback



internal extension PixelDimensions {
    var size: CGSize {
        return CGSize(width: CGFloat(self.width), height: CGFloat(self.height))
    }
}


public enum PlatformVideoContentId: Hashable {
    case message(MessageId, UInt32, MediaId)
    case instantPage(MediaId, MediaId)
    
    public static func ==(lhs: PlatformVideoContentId, rhs: PlatformVideoContentId) -> Bool {
        switch lhs {
        case let .message(messageId, stableId, mediaId):
            if case .message(messageId, stableId, mediaId) = rhs {
                return true
            } else {
                return false
            }
        case let .instantPage(pageId, mediaId):
            if case .instantPage(pageId, mediaId) = rhs {
                return true
            } else {
                return false
            }
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .message(messageId, _, mediaId):
            hasher.combine(messageId)
            hasher.combine(mediaId)
        case let .instantPage(pageId, mediaId):
            hasher.combine(pageId)
            hasher.combine(mediaId)
        }
    }
}



public final class HLSVideoContent : UniversalVideoContent {
    public let id: AnyHashable
    public let nativeId: PlatformVideoContentId
    let userLocation: MediaResourceUserLocation
    public let fileReference: FileMediaReference
    public let dimensions: CGSize
    public let duration: Double
    let streamVideo: Bool
    let loopVideo: Bool
    let enableSound: Bool
    let baseRate: Double
    let fetchAutomatically: Bool
    
    public init(id: PlatformVideoContentId, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, streamVideo: Bool = false, loopVideo: Bool = false, enableSound: Bool = true, baseRate: Double = 1.0, fetchAutomatically: Bool = true) {
        self.id = id
        self.userLocation = userLocation
        self.nativeId = id
        self.fileReference = fileReference
        self.dimensions = self.fileReference.media.dimensions?.size ?? CGSize(width: 480, height: 320)
        self.duration = self.fileReference.media.duration ?? 0.0
        self.streamVideo = streamVideo
        self.loopVideo = loopVideo
        self.enableSound = enableSound
        self.baseRate = baseRate
        self.fetchAutomatically = fetchAutomatically
    }
    
    public func isEqual(to other: UniversalVideoContent) -> Bool {
        if let other = other as? HLSVideoContent {
            if case let .message(_, stableId, _) = self.nativeId {
                if case .message(_, stableId, _) = other.nativeId {
                    if self.fileReference.media.isInstantVideo {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    public static func qualityKey(keys: [Int], initialQuality: UniversalVideoContentVideoQuality?) -> Int? {
        switch initialQuality {
        case let .quality(quality)?:
            return keys.sorted().min(by: { abs($0 - quality) < abs($1 - quality) })
        case .auto?, nil:
            return HLSLevels.preloadQualityKey(keys: keys)
        }
    }
    
    public static func minimizedHLSQuality(file: FileMediaReference, initialQuality: UniversalVideoContentVideoQuality? = nil) -> (playlist: FileMediaReference, file: FileMediaReference)? {
        guard let qualitySet = HLSQualitySet(baseFile: file) else {
            return nil
        }
        guard let quality = HLSVideoContent.qualityKey(keys: Array(qualitySet.qualityFiles.keys), initialQuality: initialQuality), let qualityFile = qualitySet.qualityFiles[quality], let playlistFile = qualitySet.playlistFiles[quality] else {
            return nil
        }
        return (playlistFile, qualityFile)
    }
    
    public static func minimizedHLSQualityPreloadData(postbox: Postbox, file: FileMediaReference, userLocation: MediaResourceUserLocation, prefixSeconds: Int, autofetchPlaylist: Bool, initialQuality: UniversalVideoContentVideoQuality? = nil) -> Signal<(FileMediaReference, Range<Int64>)?, NoError> {
        guard let fileSet = minimizedHLSQuality(file: file, initialQuality: initialQuality) else {
            return .single(nil)
        }
        
        let playlistData: Signal<Range<Int64>?, NoError> = Signal { subscriber in
            var fetchDisposable: Disposable?
            if autofetchPlaylist {
                fetchDisposable = (fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: fileSet.playlist.media), reference: fileSet.playlist.resourceReference(fileSet.playlist.media.resource))
                |> retry(2.0, maxDelay: 30.0, onQueue: Queue.concurrentDefaultQueue())).start()
            }
            let dataDisposable = postbox.mediaBox.resourceData(fileSet.playlist.media.resource).start(next: { data in
                if !data.complete {
                    return
                }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)), let text = String(data: data, encoding: .utf8), let playlist = try? HLSMediaPlaylist.parse(text) else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                subscriber.putNext(playlist.prefixRange(seconds: Double(prefixSeconds)))
                subscriber.putCompletion()
            })
            
            return ActionDisposable {
                fetchDisposable?.dispose()
                dataDisposable.dispose()
            }
        }
        
        return playlistData
        |> map { range -> (FileMediaReference, Range<Int64>)? in
            guard let range else {
                return nil
            }
            return (fileSet.file, range)
        }
    }
}

public func fetchedResourceRangeUntilOnDisk(mediaBox: MediaBox, resource: MediaResource, range: Range<Int64>, fetch: Signal<FetchResourceSourceType, FetchResourceError>) -> Signal<Never, NoError> {
    let isOnDisk: Signal<Never, FetchResourceError> = mediaBox.resourceRangesStatus(resource)
    |> take(1)
    |> castError(FetchResourceError.self)
    |> mapToSignal { ranges -> Signal<Never, FetchResourceError> in
        return ranges.isSuperset(of: RangeSet(range)) ? .complete() : .fail(.generic)
    }
    return (fetch |> ignoreValues |> then(isOnDisk))
    |> retry(2.0, maxDelay: 30.0, onQueue: Queue.concurrentDefaultQueue())
}

public final class HLSQualitySet {
    public let qualityFiles: [Int: FileMediaReference]
    public let playlistFiles: [Int: FileMediaReference]
    public let thumbnails: [Int: (file: FileMediaReference, fileMap: FileMediaReference)]
    
    public init?(baseFile: FileMediaReference) {
        
        
        func isNativeVideoCodecSupported(videoCodec: String) -> Bool {
            return videoCodec == "h264" || videoCodec == "h265" || videoCodec == "avc" || videoCodec == "hevc"
        }
        
        var qualityFiles: [Int: FileMediaReference] = [:]
        var thumbnailFiles: [FileMediaReference] = []
        var thumbnailFileMaps: [Int: (mapFile: FileMediaReference, thumbnailFileId: Int64)] = [:]
        
        for alternativeRepresentation in baseFile.media.alternativeRepresentations {
            let alternativeFile = alternativeRepresentation
            if alternativeFile.mimeType == "application/x-tgstoryboard" {
                thumbnailFiles.append(baseFile.withMedia(alternativeFile))
            } else if alternativeFile.mimeType == "application/x-tgstoryboardmap" {
                var qualityId: Int?
                for attribute in alternativeFile.attributes {
                    switch attribute {
                    case let .ImageSize(size):
                        qualityId = Int(min(size.width, size.height))
                    default:
                        break
                    }
                }
                
                if let qualityId, let fileName = alternativeFile.fileName {
                    if fileName.hasPrefix("mtproto:") {
                        if let fileId = Int64(fileName[fileName.index(fileName.startIndex, offsetBy: "mtproto:".count)...]) {
                            thumbnailFileMaps[qualityId] = (mapFile: baseFile.withMedia(alternativeFile), thumbnailFileId: fileId)
                        }
                    }
                }
            } else {
                for attribute in alternativeFile.attributes {
                    if case let .Video(_, size, _, _, _, videoCodec) = attribute {
                        if let videoCodec, isNativeVideoCodecSupported(videoCodec: videoCodec) {
                            let key = Int(min(size.width, size.height))
                            if let currentFile = qualityFiles[key] {
                                var currentCodec: String?
                                for attribute in currentFile.media.attributes {
                                    if case let .Video(_, _, _, _, _, videoCodec) = attribute {
                                        currentCodec = videoCodec
                                    }
                                }
                                if let currentCodec, (currentCodec == "av1" || currentCodec == "av01") {
                                } else {
                                    qualityFiles[key] = baseFile.withMedia(alternativeFile)
                                }
                            } else {
                                qualityFiles[key] = baseFile.withMedia(alternativeFile)
                            }
                        }
                    }
                }
            }
        }
        
        var playlistFiles: [Int: FileMediaReference] = [:]
        for alternativeRepresentation in baseFile.media.alternativeRepresentations {
            let alternativeFile = alternativeRepresentation
            if alternativeFile.mimeType == "application/x-mpegurl" {
                if let fileName = alternativeFile.fileName {
                    if fileName.hasPrefix("mtproto:") {
                        let fileIdString = String(fileName[fileName.index(fileName.startIndex, offsetBy: "mtproto:".count)...])
                        if let fileId = Int64(fileIdString) {
                            for (quality, file) in qualityFiles {
                                if file.media.fileId.id == fileId {
                                    playlistFiles[quality] = baseFile.withMedia(alternativeFile)
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        if !playlistFiles.isEmpty && playlistFiles.keys == qualityFiles.keys {
            self.qualityFiles = qualityFiles
            self.playlistFiles = playlistFiles
            
            var thumbnails: [Int: (file: FileMediaReference, fileMap: FileMediaReference)] = [:]
            for (quality, thubmailMap) in thumbnailFileMaps {
                for file in thumbnailFiles {
                    if file.media.fileId.id == thubmailMap.thumbnailFileId {
                        thumbnails[quality] = (
                            file: file,
                            fileMap: thubmailMap.mapFile
                        )
                    }
                }
            }
            self.thumbnails = thumbnails
        } else {
            return nil
        }
    }
}
