import Foundation

struct MIDINote {
    let pitch: UInt8
    let velocity: UInt8
    let startTime: Double
    let duration: Double
    let channel: UInt8
}

struct MIDIData {
    let notes: [MIDINote]
    let duration: Double
    let minPitch: UInt8
    let maxPitch: UInt8
}
