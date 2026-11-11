import Foundation

public protocol BroadcastCancellable: AnyObject {
    func cancel()
}

// Everything the controller needs from the outside. All calls and callbacks happen on one thread, the controller's.
public protocol BroadcastPlaybackEnvironment: AnyObject {
    // Seconds, monotonic: the host clock.
    var now: Double { get }
    func schedule(after delay: Double, _ action: @escaping () -> Void) -> BroadcastCancellable
    // Listener format: the server's time, ms. Unified: `phone.getGroupCallStreamChannels`' `last_timestamp_ms`, with
    // the server's time as the fallback.
    func requestLiveEdge(completion: @escaping (BroadcastEdgeOutcome) -> Void) -> BroadcastCancellable
    // `progress` reports the bytes received so far, only where the load can observe them (ranged loads); a load of a
    // whole response never calls it. `completion` fires once, unless the load is cancelled first.
    func loadPart(_ request: BroadcastPartRequest, progress: @escaping (Int64) -> Void, completion: @escaping (BroadcastPartOutcome) -> Void) -> BroadcastCancellable
    // All of a segment's parts are loaded: decode them (listener format) or append them to the player (unified). A
    // segment delivered again (a part re-fetched at another quality) replaces the earlier delivery, and may come after
    // the segment's play has gone out, even after its host time (the controller's transition runs on a timer, a few ms
    // late): replace its parts in place. A delivered segment's parts are the environment's to free once it has played.
    func deliver(_ segment: BroadcastSegment)
    // Listener format only: the playhead enters the segment at `hostTime`, `offsetMs` into it. The next segment's play
    // comes as soon as that segment is ready behind the playing one, up to a second or more before `hostTime`: what
    // plays at any moment is the latest play whose `hostTime` has been reached (the audio core's rule). A play still
    // ahead when the controller stops may never be reached by the controller; the environment resets on a stop.
    func play(segmentTimestampMs: Int64, at hostTime: Double, offsetMs: Int)
    // Unified only: start the player here, or jump it here.
    func setUnifiedPosition(_ positionMs: Int64)
    // Loaded parts the controller replaced (a re-fetch) or dropped (a resync, a rejoin, a stream's jump, and stop, which
    // names every delivered segment not yet played out). Parts of a segment that has played are never named here.
    func discard(_ requests: [BroadcastPartRequest])
    // A part answered `GROUPCALL_JOIN_MISSING`: the call has to rejoin, and then calls the controller's `rejoined()`.
    func requestRejoin()
}
