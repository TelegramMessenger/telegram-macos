import Foundation

// What plays: the latest play whose host time has been reached, as the audio core decides it. The controller sends the
// next segment's play as soon as that segment is ready, ahead of its host time. Video outputs follow it (the testbench
// runner's and the app's), so picture and sound change segments at the same moment.
public struct BroadcastPlayhead {
    public struct Play: Equatable {
        public var timestampMs: Int64
        public var hostTime: Double
        public var offsetMs: Int

        public init(timestampMs: Int64, hostTime: Double, offsetMs: Int) {
            self.timestampMs = timestampMs
            self.hostTime = hostTime
            self.offsetMs = offsetMs
        }

        public func secondsIntoSegment(at now: Double) -> Double {
            return now - self.hostTime + Double(self.offsetMs) / 1000.0
        }
    }

    public private(set) var plays: [Play] = []

    public init() {
    }

    public mutating func add(_ play: Play) {
        self.plays.append(play)
    }

    // The play in effect at `now`; the plays it supersedes (reached earlier) are dropped.
    public mutating func active(at now: Double) -> Play? {
        var selected: Int?
        for index in self.plays.indices where self.plays[index].hostTime <= now {
            if let current = selected, self.plays[current].hostTime > self.plays[index].hostTime {
                continue
            }
            selected = index
        }
        guard let selected else {
            return nil
        }
        let play = self.plays[selected]
        self.plays = self.plays.enumerated().filter { $0.offset == selected || $0.element.hostTime > now }.map(\.element)
        return play
    }
}
