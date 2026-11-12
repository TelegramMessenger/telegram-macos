import Foundation

// A video channel's or a stream's quality, as `upload.getFile`'s `videoQuality` numbers them.
public enum BroadcastQuality: Int, Comparable, CaseIterable {
    case thumbnail = 0
    case medium = 1
    case full = 2

    public static func < (lhs: BroadcastQuality, rhs: BroadcastQuality) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// How a broadcast's parts are laid out, decided by the join result: `"rtmp": true` is unified (one mp4 slice per second
// with video and AAC), otherwise listener format (Ogg Opus audio with one channel per speaker, plus one video part per
// watched participant).
public enum BroadcastFormat: Equatable {
    case listener
    case unified
}

public enum BroadcastPartKind: Hashable {
    case audio
    case video(channelId: Int32, quality: BroadcastQuality)
    case unified(quality: BroadcastQuality)
}

// One 1-second part: `timestampMs` is the part's start on the server's millisecond grid (a multiple of 1000).
public struct BroadcastPartRequest: Hashable {
    public var timestampMs: Int64
    public var kind: BroadcastPartKind

    public init(timestampMs: Int64, kind: BroadcastPartKind) {
        self.timestampMs = timestampMs
        self.kind = kind
    }
}

// What the environment read from a loaded part without decoding it.
public struct BroadcastPartInfo: Equatable {
    // An audio part's endpoint → video channel id (`ACTIVE_MASK` / `ENDPOINTS`); empty for other parts.
    public var videoChannels: [String: Int32]
    // The milliseconds of audio an audio part holds; nil for other parts.
    public var audioDurationMs: Int?

    public init(videoChannels: [String: Int32] = [:], audioDurationMs: Int? = nil) {
        self.videoChannels = videoChannels
        self.audioDurationMs = audioDurationMs
    }
}

public enum BroadcastPartOutcome: Equatable {
    // `responseTimestamp`: the server's time when it answered, in seconds.
    case data(bytes: Int64, responseTimestamp: Double, info: BroadcastPartInfo)
    // The part does not exist yet (`TIME_TOO_BIG`, `FLOOD_WAIT`, a CDN redirect): ask again.
    case notReady
    // The part is outside what the server keeps or was asked for wrongly (`TIME_INVALID`, `TIME_TOO_SMALL`, any other
    // error): re-anchor.
    case resyncNeeded(responseTimestamp: Double)
    // `GROUPCALL_JOIN_MISSING`: the call has to rejoin before parts load again.
    case rejoinNeeded
}

public enum BroadcastEdgeOutcome: Equatable {
    // Listener format: the server's time, ms. Unified: `last_timestamp_ms` of `phone.getGroupCallStreamChannels`.
    case edge(reportedMs: Int64)
    case failed
}

// One watched participant's video, as the view asks for it.
public struct BroadcastVideoChannelRequest: Equatable {
    public var endpointId: String
    public var minQuality: BroadcastQuality
    public var maxQuality: BroadcastQuality

    public init(endpointId: String, minQuality: BroadcastQuality, maxQuality: BroadcastQuality) {
        self.endpointId = endpointId
        self.minQuality = minQuality
        self.maxQuality = maxQuality
    }
}

// One second of broadcast, all of its parts loaded.
public struct BroadcastSegment: Equatable {
    public var timestampMs: Int64
    // The audio part (listener format) or the unified part.
    public var primary: BroadcastPartRequest
    // Endpoint → video part (listener format only).
    public var video: [String: BroadcastPartRequest]
    // The primary part's info.
    public var info: BroadcastPartInfo

    public init(timestampMs: Int64, primary: BroadcastPartRequest, video: [String: BroadcastPartRequest], info: BroadcastPartInfo) {
        self.timestampMs = timestampMs
        self.primary = primary
        self.video = video
        self.info = info
    }
}
