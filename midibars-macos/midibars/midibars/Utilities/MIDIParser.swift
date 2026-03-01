import Foundation

enum MIDIParser {
    static func parse(from url: URL) -> MIDIData? {
        guard let data = try? Data(contentsOf: url), data.count >= 14 else { return nil }

        var pos = 0

        guard readASCII(data, at: pos, length: 4) == "MThd" else { return nil }
        pos += 4

        let headerLen = Int(readU32(data, at: pos))
        pos += 4

        pos += 2
        let numTracks = Int(readU16(data, at: pos))
        pos += 2
        let division = readU16(data, at: pos)
        pos += 2

        let ticksPerQN = Int(division & 0x7FFF)
        guard ticksPerQN > 0 else { return nil }

        pos = 8 + headerLen

        var allEvents = [(tick: Int, event: Event)]()

        for _ in 0..<numTracks {
            guard pos + 8 <= data.count,
                  readASCII(data, at: pos, length: 4) == "MTrk" else { break }
            pos += 4

            let trackLen = Int(readU32(data, at: pos))
            pos += 4
            let trackEnd = min(pos + trackLen, data.count)

            var tick = 0
            var runStatus: UInt8 = 0

            while pos < trackEnd {
                let (delta, dBytes) = readVarLen(data, at: pos, limit: trackEnd)
                pos += dBytes
                tick += delta

                guard pos < trackEnd else { break }

                var status = data[pos]
                if status >= 0x80 {
                    if status < 0xF0 { runStatus = status }
                    pos += 1
                } else {
                    status = runStatus
                }

                let type = status & 0xF0
                let ch = status & 0x0F

                switch type {
                case 0x90:
                    guard pos + 1 < trackEnd else { pos = trackEnd; break }
                    let p = data[pos], v = data[pos + 1]
                    pos += 2
                    if v > 0 {
                        allEvents.append((tick, .noteOn(ch, p, v)))
                    } else {
                        allEvents.append((tick, .noteOff(ch, p)))
                    }

                case 0x80:
                    guard pos + 1 < trackEnd else { pos = trackEnd; break }
                    let p = data[pos]
                    pos += 2
                    allEvents.append((tick, .noteOff(ch, p)))

                case 0xA0, 0xB0, 0xE0:
                    pos = min(pos + 2, trackEnd)

                case 0xC0, 0xD0:
                    pos = min(pos + 1, trackEnd)

                case 0xF0:
                    if status == 0xFF {
                        guard pos < trackEnd else { pos = trackEnd; break }
                        let metaType = data[pos]
                        pos += 1
                        let (mLen, mBytes) = readVarLen(data, at: pos, limit: trackEnd)
                        pos += mBytes
                        if metaType == 0x51, mLen == 3, pos + 2 < trackEnd {
                            let us = (Int(data[pos]) << 16) | (Int(data[pos + 1]) << 8) | Int(data[pos + 2])
                            allEvents.append((tick, .tempo(us)))
                        }
                        pos = min(pos + mLen, trackEnd)
                    } else {
                        let (sLen, sBytes) = readVarLen(data, at: pos, limit: trackEnd)
                        pos = min(pos + sBytes + sLen, trackEnd)
                    }

                default:
                    break
                }
            }

            pos = trackEnd
        }

        allEvents.sort { $0.tick < $1.tick }
        return buildNotes(from: allEvents, ticksPerQN: ticksPerQN)
    }

    // MARK: - Note Building

    private static func buildNotes(from events: [(tick: Int, event: Event)], ticksPerQN: Int) -> MIDIData? {
        var tempo = 500_000
        var curTick = 0
        var curTime: Double = 0

        struct Pending { let pitch: UInt8; let velocity: UInt8; let channel: UInt8; let time: Double }
        var pending = [Pending]()
        var notes = [MIDINote]()

        for (tick, event) in events {
            let dt = Double(tick - curTick) / Double(ticksPerQN) * Double(tempo) / 1_000_000
            curTime += dt
            curTick = tick

            switch event {
            case .noteOn(let ch, let p, let v):
                pending.append(Pending(pitch: p, velocity: v, channel: ch, time: curTime))

            case .noteOff(let ch, let p):
                if let i = pending.lastIndex(where: { $0.pitch == p && $0.channel == ch }) {
                    let n = pending.remove(at: i)
                    notes.append(MIDINote(
                        pitch: p, velocity: n.velocity,
                        startTime: n.time, duration: max(curTime - n.time, 0.01),
                        channel: ch
                    ))
                }

            case .tempo(let us):
                tempo = us
            }
        }

        for n in pending {
            notes.append(MIDINote(
                pitch: n.pitch, velocity: n.velocity,
                startTime: n.time, duration: max(curTime - n.time, 0.01),
                channel: n.channel
            ))
        }

        guard !notes.isEmpty else { return nil }

        return MIDIData(
            notes: notes,
            duration: notes.map { $0.startTime + $0.duration }.max()!,
            minPitch: notes.map(\.pitch).min()!,
            maxPitch: notes.map(\.pitch).max()!
        )
    }

    // MARK: - Internal Event Type

    private enum Event {
        case noteOn(UInt8, UInt8, UInt8)
        case noteOff(UInt8, UInt8)
        case tempo(Int)
    }

    // MARK: - Binary Helpers

    private static func readASCII(_ d: Data, at o: Int, length n: Int) -> String? {
        guard o >= 0, o + n <= d.count else { return nil }
        return String(data: d[o..<o + n], encoding: .ascii)
    }

    private static func readU32(_ d: Data, at o: Int) -> UInt32 {
        guard o + 3 < d.count else { return 0 }
        return (UInt32(d[o]) << 24) | (UInt32(d[o + 1]) << 16) | (UInt32(d[o + 2]) << 8) | UInt32(d[o + 3])
    }

    private static func readU16(_ d: Data, at o: Int) -> UInt16 {
        guard o + 1 < d.count else { return 0 }
        return (UInt16(d[o]) << 8) | UInt16(d[o + 1])
    }

    private static func readVarLen(_ d: Data, at offset: Int, limit: Int) -> (value: Int, bytesRead: Int) {
        var value = 0
        var count = 0
        var pos = offset
        repeat {
            guard pos < limit, pos < d.count else { break }
            let byte = d[pos]
            value = (value << 7) | Int(byte & 0x7F)
            count += 1
            pos += 1
            if byte & 0x80 == 0 { break }
        } while count < 4
        return (value, max(count, 1))
    }
}
