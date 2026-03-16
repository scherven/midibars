import Foundation

struct MIDINote {
    let pitch: UInt8
    let velocity: UInt8
    let startTime: Double
    let duration: Double
    let channel: UInt8
}

struct MIDIData {
    /// Notes sorted by startTime ascending.
    let notes: [MIDINote]
    let duration: Double
    let minPitch: UInt8
    let maxPitch: UInt8
    /// Maximum note duration in the file — used to bound binary-search windows.
    let maxNoteDuration: Double
}

extension Array where Element == MIDINote {
    /// Returns the index of the first note whose startTime >= target (lower bound).
    func lowerBound(startTime target: Double) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid].startTime < target { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
