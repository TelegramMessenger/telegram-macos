import Foundation

// The listener format's playback clock: the host's monotonic clock, as `StreamingMediaContext::render` keeps it. Ready
// segments queue up; the first plays once `startBufferMs` is buffered (from the start offset), each next one starts
// where the previous ended (no drift), and an underrun waits for `resumeBufferMs`. A segment with no video ends as soon
// as its audio has played and the next segment is ready, and at the latest after its 1000 ms. The next segment's start
// is fixed once it is queued behind the playing one, so it is announced then, once, ahead of its host time: the audio
// core plays a segment only from the moment it has its play, and a play sent at the boundary arrived 3–40 ms late.
struct BroadcastListenerTimeline {
    struct Entry: Equatable {
        let timestampMs: Int64
        // The audio the segment holds; nil when unknown (counted as a whole part).
        let audioDurationMs: Int?
        let hasVideo: Bool
        // When it became ready.
        let readyTime: Double
    }

    enum Event: Equatable {
        // The playhead enters the segment. `announced`: its play already went out with an `announce`.
        case play(timestampMs: Int64, hostTime: Double, offsetMs: Int, announced: Bool)
        // The next segment will start at `hostTime` (from its beginning), unless the timeline is cleared first.
        case announce(timestampMs: Int64, hostTime: Double)
        case stall(hostTime: Double)
    }

    struct Current: Equatable {
        let entry: Entry
        let startTime: Double
        let offsetMs: Int
    }

    private static let partDurationMs = Int(BroadcastLivePosition.partDurationMs)

    let startBufferMs: Int
    let resumeBufferMs: Int
    // Where in the first segment playback starts.
    var firstOffsetMs: Int = 0

    private(set) var queue: [Entry] = []
    private(set) var current: Current?
    private(set) var hasStarted = false
    private var lastPositionMs: Int64?
    private var announcedTimestampMs: Int64?

    init(startBufferMs: Int, resumeBufferMs: Int) {
        self.startBufferMs = startBufferMs
        self.resumeBufferMs = resumeBufferMs
    }

    // The newest segment handed to the timeline, played or not.
    var newestTimestampMs: Int64? {
        return self.queue.last?.timestampMs ?? self.current?.entry.timestampMs ?? self.newestPlayedTimestampMs
    }

    private var newestPlayedTimestampMs: Int64?

    var isPlaying: Bool {
        return self.current != nil
    }

    mutating func append(_ entry: Entry) {
        self.queue.append(entry)
    }

    // What is ready ahead of the playhead.
    func bufferedAheadMs(now: Double) -> Int {
        var result = self.queue.count * BroadcastListenerTimeline.partDurationMs
        if let current = self.current {
            let played = Int(((now - current.startTime) * 1000.0).rounded(.down))
            result += max(0, BroadcastListenerTimeline.partDurationMs - current.offsetMs - played)
        } else if !self.hasStarted {
            result -= self.firstOffsetMs
        }
        return max(0, result)
    }

    private func endTime(_ current: Current) -> Double {
        let fullEnd = current.startTime + Double(BroadcastListenerTimeline.partDurationMs - current.offsetMs) / 1000.0
        if !current.entry.hasVideo, let audio = current.entry.audioDurationMs, audio < BroadcastListenerTimeline.partDurationMs, let next = self.queue.first {
            let audioEnd = current.startTime + Double(max(0, audio - current.offsetMs)) / 1000.0
            return min(fullEnd, max(audioEnd, next.readyTime))
        }
        return fullEnd
    }

    // When `advance` has to run next for the playing segment; nil while nothing plays (an append drives it then).
    var nextWakeTime: Double? {
        return self.current.map { self.endTime($0) }
    }

    mutating func advance(now: Double) -> [Event] {
        var events: [Event] = []
        while true {
            if let current = self.current {
                let end = self.endTime(current)
                if let next = self.queue.first, self.announcedTimestampMs != next.timestampMs {
                    self.announcedTimestampMs = next.timestampMs
                    events.append(.announce(timestampMs: next.timestampMs, hostTime: end))
                }
                if now + 1e-9 < end {
                    break
                }
                self.lastPositionMs = current.entry.timestampMs + Int64(current.offsetMs) + Int64(((end - current.startTime) * 1000.0).rounded())
                self.newestPlayedTimestampMs = current.entry.timestampMs
                if self.queue.isEmpty {
                    self.current = nil
                    events.append(.stall(hostTime: end))
                    break
                }
                let next = self.queue.removeFirst()
                self.current = Current(entry: next, startTime: end, offsetMs: 0)
                events.append(.play(timestampMs: next.timestampMs, hostTime: end, offsetMs: 0, announced: true))
            } else {
                if self.queue.isEmpty {
                    break
                }
                let threshold = self.hasStarted ? self.resumeBufferMs : self.startBufferMs
                if self.bufferedAheadMs(now: now) < threshold {
                    break
                }
                let next = self.queue.removeFirst()
                let offset = self.hasStarted ? 0 : self.firstOffsetMs
                self.hasStarted = true
                self.current = Current(entry: next, startTime: now, offsetMs: offset)
                events.append(.play(timestampMs: next.timestampMs, hostTime: now, offsetMs: offset, announced: false))
            }
        }
        return events
    }

    // Media time at the playhead; during a stall, where the last segment ended.
    func positionMs(now: Double) -> Int64? {
        if let current = self.current {
            let available = Int64(BroadcastListenerTimeline.partDurationMs - current.offsetMs)
            let elapsed = Int64(((now - current.startTime) * 1000.0).rounded(.down))
            return current.entry.timestampMs + Int64(current.offsetMs) + min(max(0, elapsed), available)
        }
        return self.lastPositionMs
    }

    // The segments still held (playing and queued), for a stop.
    mutating func removeAll() -> [Int64] {
        var result = self.queue.map(\.timestampMs)
        if let current = self.current {
            result.insert(current.entry.timestampMs, at: 0)
        }
        self.queue.removeAll()
        self.current = nil
        self.announcedTimestampMs = nil
        return result
    }
}
