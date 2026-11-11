// Ported from hls.js v1.7.3 (src/controller/abr-controller.ts, src/utils/ewma-bandwidth-estimator.ts), Copyright (c) Dailymotion and hls.js contributors, Apache License 2.0.

import Foundation
import HLSPlayback

public struct BroadcastChannelLevelInput: Equatable {
    public var floor: BroadcastQuality
    public var ceiling: BroadcastQuality
    public var lastChosen: BroadcastQuality?
    // Thumbnail, medium, full.
    public var bitsPerSecond: [Double]

    public init(floor: BroadcastQuality, ceiling: BroadcastQuality, lastChosen: BroadcastQuality?, bitsPerSecond: [Double]) {
        self.floor = floor
        self.ceiling = ceiling
        self.lastChosen = lastChosen
        self.bitsPerSecond = bitsPerSecond
    }
}

// hls.js's level choice (`findBestLevel`, `getNextABRAutoLevel`) for a segment of several channels: a segment (audio and
// every channel) is one fragment. Every channel starts at its ceiling; while the segment does not fit, the first channel
// above its floor steps down one level, in the order given (smallest tiles first, the focused tile last). For one
// channel and no audio it is exactly `HLSAbr.nextAutoLevel` with a 1 s segment.
public enum BroadcastQualityChooser {
    public static func choose(_ channels: [BroadcastChannelLevelInput], fixedBitsPerSecond: Double, estimate: Double, bufferStarvationDelay: Double, ttfbSeconds: Double) -> [BroadcastQuality] {
        if channels.isEmpty {
            return []
        }
        let floors = channels.map { min($0.floor, $0.ceiling) }
        // Step 1: a choice that never rebuffers (only with something buffered); step 2: up to one segment of rebuffering.
        let starvations: [Double] = bufferStarvationDelay > 0.0 ? [0.0, 1.0] : [1.0]
        for maxStarvation in starvations {
            var levels = channels.map(\.ceiling)
            while true {
                // hls.js judges the first choice against the top level.
                let isUpSwitch = zip(levels, channels).contains(where: { level, channel in level > (channel.lastChosen ?? .full) })
                let bandwidth = (isUpSwitch ? HLSAbr.bandwidthUpFactor : HLSAbr.bandwidthFactor) * estimate
                var bits = fixedBitsPerSecond
                for (level, channel) in zip(levels, channels) {
                    bits += channel.bitsPerSecond[level.rawValue]
                }
                let fetchDuration = ttfbSeconds + bits / bandwidth
                let fetchAllows = fetchDuration <= ttfbSeconds || !fetchDuration.isFinite || fetchDuration < bufferStarvationDelay + maxStarvation
                if bandwidth >= bits && fetchAllows {
                    return levels
                }
                guard let index = levels.indices.first(where: { levels[$0] > floors[$0] }), let lower = BroadcastQuality(rawValue: levels[index].rawValue - 1) else {
                    break
                }
                levels[index] = lower
            }
        }
        // Step 3: nothing fits; the floors if they are cheaper than the current choice.
        let current = zip(channels, floors).map { channel, floor in min(max(channel.lastChosen ?? channel.ceiling, floor), channel.ceiling) }
        let floorBits = zip(floors, channels).reduce(0.0, { $0 + $1.1.bitsPerSecond[$1.0.rawValue] })
        let currentBits = zip(current, channels).reduce(0.0, { $0 + $1.1.bitsPerSecond[$1.0.rawValue] })
        return floorBits < currentBits ? floors : current
    }
}

// hls.js's time-to-first-byte average (`EwmaBandWidthEstimator.sampleTTFB` / `getEstimateTTFB`): the slow half-life (9),
// each sample weighted √2·e^(−s²/2) by its length in seconds and floored at 5 ms, 100 ms until it has weight.
public struct BroadcastTTFBEstimator: Equatable {
    private static let halfLife = 9.0
    private static let minWeight = 0.001

    private var average = HLSEWMA(halfLife: BroadcastTTFBEstimator.halfLife)

    public init() {
    }

    public mutating func sample(ttfbMs: Double) {
        let seconds = ttfbMs / 1000.0
        let weight = sqrt(2.0) * exp(-(seconds * seconds) / 2.0)
        self.average.sample(weight: weight, value: max(ttfbMs, 5.0))
    }

    public var estimateMs: Double {
        if self.average.totalWeight >= BroadcastTTFBEstimator.minWeight {
            return self.average.estimate
        }
        return HLSBandwidthEstimator.defaultTTFBMs
    }
}
