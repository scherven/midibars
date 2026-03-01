import Foundation

func isBlackKey(_ note: Int) -> Bool {
    [1, 3, 6, 8, 10].contains(note % 12)
}

func noteName(_ pitch: Int) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    guard pitch >= 0, pitch < 128 else { return "?" }
    let octave = (pitch / 12) - 1
    return "\(names[pitch % 12])\(octave)"
}

func whiteNotes(low: Int, high: Int) -> [Int] {
    guard high >= low else { return [] }
    return (low...high).filter { !isBlackKey($0) }
}

func blackNotes(low: Int, high: Int) -> [Int] {
    guard high >= low else { return [] }
    return (low...high).filter { isBlackKey($0) }
}

func defaultPianoEdges(whiteKeyCount: Int) -> [Double] {
    guard whiteKeyCount > 0 else { return [0, 1] }
    return (0...whiteKeyCount).map { Double($0) / Double(whiteKeyCount) }
}
