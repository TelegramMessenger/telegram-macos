import Foundation

// Listener audio into the audio core: each audio part is decoded off the controller's thread and handed to the core on
// it, the core's control thread (`handOver` does both; the C calls live with the platform, the testbench runner's and
// the app's). A segment delivered again (a video part re-fetched at a raised ceiling) carries the same audio, which the
// core already has, so its audio is handed over once.
public final class BroadcastAudioHandover {
    // Closed when the run ends or the player stops: audio still decoding then never reaches the core, which may be
    // released right after. Read and written on the controller's thread only.
    public final class Gate {
        public fileprivate(set) var isClosed = false

        public init() {
        }
    }

    private let handOver: (Int64, Data) -> Void
    private let resetCore: () -> Void
    private let gate: Gate
    private var handedOver = Set<Int64>()

    // `handOver(segmentTimestampMs, audioPart)`: decodes and enqueues unless `gate` has closed meanwhile. `resetCore`
    // empties the core.
    public init(handOver: @escaping (Int64, Data) -> Void, resetCore: @escaping () -> Void = {}, gate: Gate = Gate()) {
        self.handOver = handOver
        self.resetCore = resetCore
        self.gate = gate
    }

    // On the controller's thread, when the run ends: nothing reaches the core afterwards. What the core has keeps
    // playing until the device stops, as the engine's own playout did.
    public func close() {
        self.gate.isClosed = true
    }

    // On the controller's thread, when the player stops (the coordinator ends broadcast): closes, and empties the core.
    // A play the controller announced ahead and never reached would otherwise be reached later, playing a stale or
    // retired segment.
    public func stop() {
        self.close()
        self.resetCore()
    }

    // On the controller's thread.
    public func deliver(_ segment: BroadcastSegment, data: [BroadcastPartRequest: Data]) {
        guard !self.gate.isClosed, case .audio = segment.primary.kind, !self.handedOver.contains(segment.timestampMs), let audio = data[segment.primary] else {
            return
        }
        self.handedOver.insert(segment.timestampMs)
        self.handOver(segment.timestampMs, audio)
    }

    // On the controller's thread: a dropped audio part may be delivered again later (after a resync) and then needs
    // handing over again.
    public func discard(_ requests: [BroadcastPartRequest]) {
        for request in requests {
            if case .audio = request.kind {
                self.handedOver.remove(request.timestampMs)
            }
        }
    }
}
