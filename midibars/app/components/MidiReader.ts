// ─── Utility ─────────────────────────────────────────────────────────────────

class MidiReader {
  private bytes: Uint8Array;
  private pos = 0;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  get position() {
    return this.pos;
  }
  get remaining() {
    return this.bytes.length - this.pos;
  }

  readUint8(): number {
    return this.bytes[this.pos++];
  }

  readUint16(): number {
    const val = (this.bytes[this.pos] << 8) | this.bytes[this.pos + 1];
    this.pos += 2;
    return val;
  }

  readUint32(): number {
    const val =
      (this.bytes[this.pos] << 24) |
      (this.bytes[this.pos + 1] << 16) |
      (this.bytes[this.pos + 2] << 8) |
      this.bytes[this.pos + 3];
    this.pos += 4;
    return val >>> 0; // ensure unsigned
  }

  /** Variable-length quantity — the core MIDI encoding */
  readVarLen(): number {
    let value = 0;
    let byte: number;
    do {
      byte = this.readUint8();
      value = (value << 7) | (byte & 0x7f);
    } while (byte & 0x80);
    return value;
  }

  readBytes(n: number): Uint8Array {
    const slice = this.bytes.slice(this.pos, this.pos + n);
    this.pos += n;
    return slice;
  }

  /** Peek without advancing */
  peekUint8(): number {
    return this.bytes[this.pos];
  }
}

// ─── MIDI Event Types ────────────────────────────────────────────────────────

export type MidiEventData =
  | NoteOnEvent
  | NoteOffEvent
  | ControlChangeEvent
  | ProgramChangeEvent
  | PitchBendEvent
  | ChannelPressureEvent
  | PolyPressureEvent
  | TempoMetaEvent
  | TimeSignatureMetaEvent
  | KeySignatureMetaEvent
  | TrackNameMetaEvent
  | GenericMetaEvent
  | SysexEvent
  | UnknownEvent;

interface BaseEvent {
  /** Delta time in ticks *before* this event */
  deltaTime: number;
  /** Absolute time in ticks from the start of the track */
  absoluteTick: number;
}

// --- Channel Events ---

export interface NoteOnEvent extends BaseEvent {
  type: "noteOn";
  channel: number;
  note: number; // 0–127
  velocity: number; // 0–127  (velocity 0 = noteOff in many files)
}

export interface NoteOffEvent extends BaseEvent {
  type: "noteOff";
  channel: number;
  note: number;
  velocity: number;
}

export interface ControlChangeEvent extends BaseEvent {
  type: "controlChange";
  channel: number;
  controller: number; // 0–127
  value: number; // 0–127
}

export interface ProgramChangeEvent extends BaseEvent {
  type: "programChange";
  channel: number;
  program: number; // 0–127
}

export interface PitchBendEvent extends BaseEvent {
  type: "pitchBend";
  channel: number;
  value: number; // 0–16383 (8192 = center)
}

export interface ChannelPressureEvent extends BaseEvent {
  type: "channelPressure";
  channel: number;
  pressure: number; // 0–127
}

export interface PolyPressureEvent extends BaseEvent {
  type: "polyPressure";
  channel: number;
  note: number;
  pressure: number;
}

// --- Meta Events ---

export interface TempoMetaEvent extends BaseEvent {
  type: "tempo";
  microsecondsPerBeat: number; // default 500000 = 120 BPM
  bpm: number;
}

export interface TimeSignatureMetaEvent extends BaseEvent {
  type: "timeSignature";
  numerator: number;
  denominator: number; // already converted from power-of-2
}

export interface KeySignatureMetaEvent extends BaseEvent {
  type: "keySignature";
  key: string; // e.g. "C", "A minor"
}

export interface TrackNameMetaEvent extends BaseEvent {
  type: "trackName";
  name: string;
}

export interface GenericMetaEvent extends BaseEvent {
  type: "meta";
  metaType: number;
  data: Uint8Array;
}

// --- Sysex & Unknown ---

export interface SysexEvent extends BaseEvent {
  type: "sysex";
  data: Uint8Array;
}

export interface UnknownEvent extends BaseEvent {
  type: "unknown";
  statusByte: number;
  data: Uint8Array;
}

// ─── Track ───────────────────────────────────────────────────────────────────

export class MidiTrack {
  readonly events: MidiEventData[] = [];

  constructor(public readonly name: string | null = null) {}
}

// ─── Header ──────────────────────────────────────────────────────────────────

export class MidiHeader {
  constructor(
    public readonly format: number, // 0, 1, or 2
    public readonly numTracks: number,
    public readonly ticksPerBeat: number, // divisions (assuming ticks-per-quarter)
  ) {}
}

// ─── Main Parser ─────────────────────────────────────────────────────────────

export class MidiFile {
  readonly header!: MidiHeader;
  readonly tracks: MidiTrack[] = [];

  constructor(bytes: Uint8Array) {
    const reader = new MidiReader(bytes);
    this.header = this.parseHeader(reader);

    for (let i = 0; i < this.header.numTracks; i++) {
      this.tracks.push(this.parseTrack(reader));
    }
  }

  // ── Header ──────────────────────────────────────────────────────────────

  private parseHeader(reader: MidiReader): MidiHeader {
    const chunkId = String.fromCharCode(...reader.readBytes(4));
    if (chunkId !== "MThd") throw new Error("Not a valid MIDI file");

    const chunkLen = reader.readUint32(); // always 6 for standard MIDI
    const format = reader.readUint16();
    const numTracks = reader.readUint16();
    const division = reader.readUint16();

    // If bit 15 is set, division is SMPTE-based; we only handle ticks-per-beat here
    if (division & 0x8000) {
      throw new Error("SMPTE time division not supported");
    }

    return new MidiHeader(format, numTracks, division);
  }

  // ── Track ───────────────────────────────────────────────────────────────

  private parseTrack(reader: MidiReader): MidiTrack {
    const chunkId = String.fromCharCode(...reader.readBytes(4));
    if (chunkId !== "MTrk") throw new Error("Expected MTrk chunk");

    const chunkLen = reader.readUint32();
    const chunkEnd = reader.position + chunkLen;
    const track = new MidiTrack();

    let runningStatus = 0; // for running-status optimization
    let absoluteTick = 0;

    while (reader.position < chunkEnd) {
      const deltaTime = reader.readVarLen();
      absoluteTick += deltaTime;

      let statusByte = reader.peekUint8();

      // Running status: if high bit is 0, reuse the last status byte
      if (statusByte < 0x80) {
        statusByte = runningStatus;
      } else {
        reader.readUint8(); // consume the status byte
      }

      const base = { deltaTime, absoluteTick };

      if (statusByte === 0xff) {
        // ── Meta event ──
        track.events.push(this.parseMetaEvent(reader, base));
      } else if (statusByte === 0xf0 || statusByte === 0xf7) {
        // ── SysEx event ──
        const len = reader.readVarLen();
        const data = reader.readBytes(len);
        track.events.push({ ...base, type: "sysex", data });
        runningStatus = 0; // sysex cancels running status
      } else {
        // ── Channel event ──
        const event = this.parseChannelEvent(reader, statusByte, base);
        track.events.push(event);
        runningStatus = statusByte;
      }
    }

    // Extract track name if present
    const nameEvent = track.events.find(
      (e): e is TrackNameMetaEvent => e.type === "trackName",
    );

    return nameEvent ? Object.assign(track, { name: nameEvent.name }) : track;
  }

  // ── Channel Events ──────────────────────────────────────────────────────

  private parseChannelEvent(
    reader: MidiReader,
    status: number,
    base: { deltaTime: number; absoluteTick: number },
  ): MidiEventData {
    const type = (status & 0xf0) >> 4;
    const channel = status & 0x0f;

    switch (type) {
      case 0x8: {
        // Note Off
        const note = reader.readUint8();
        const velocity = reader.readUint8();
        return { ...base, type: "noteOff", channel, note, velocity };
      }
      case 0x9: {
        // Note On
        const note = reader.readUint8();
        const velocity = reader.readUint8();
        // Velocity 0 on a noteOn is conventionally a noteOff
        if (velocity === 0) {
          return { ...base, type: "noteOff", channel, note, velocity };
        }
        return { ...base, type: "noteOn", channel, note, velocity };
      }
      case 0xa: {
        // Poly Pressure (Aftertouch)
        const note = reader.readUint8();
        const pressure = reader.readUint8();
        return { ...base, type: "polyPressure", channel, note, pressure };
      }
      case 0xb: {
        // Control Change
        const controller = reader.readUint8();
        const value = reader.readUint8();
        return { ...base, type: "controlChange", channel, controller, value };
      }
      case 0xc: {
        // Program Change (1 data byte)
        const program = reader.readUint8();
        return { ...base, type: "programChange", channel, program };
      }
      case 0xd: {
        // Channel Pressure (1 data byte)
        const pressure = reader.readUint8();
        return { ...base, type: "channelPressure", channel, pressure };
      }
      case 0xe: {
        // Pitch Bend (2 bytes, LSB first)
        const lsb = reader.readUint8();
        const msb = reader.readUint8();
        const value = (msb << 7) | lsb;
        return { ...base, type: "pitchBend", channel, value };
      }
      default: {
        // Fallback: consume 2 bytes so we don't get stuck
        const data = reader.readBytes(2);
        return { ...base, type: "unknown", statusByte: status, data };
      }
    }
  }

  // ── Meta Events ─────────────────────────────────────────────────────────

  private parseMetaEvent(
    reader: MidiReader,
    base: { deltaTime: number; absoluteTick: number },
  ): MidiEventData {
    const metaType = reader.readUint8();
    const len = reader.readVarLen();
    const data = reader.readBytes(len);

    switch (metaType) {
      case 0x51: {
        // Tempo
        const us = (data[0] << 16) | (data[1] << 8) | data[2];
        return {
          ...base,
          type: "tempo",
          microsecondsPerBeat: us,
          bpm: 60_000_000 / us,
        };
      }
      case 0x58: {
        // Time Signature
        return {
          ...base,
          type: "timeSignature",
          numerator: data[0],
          denominator: Math.pow(2, data[1]),
        };
      }
      case 0x59: {
        // Key Signature
        const sharpsOrFlats = data[0] > 127 ? data[0] - 256 : data[0]; // signed byte
        const minor = data[1] === 1;
        const keys = [
          "Cb",
          "Gb",
          "Db",
          "Ab",
          "Eb",
          "Bb",
          "F",
          "C",
          "G",
          "D",
          "A",
          "E",
          "B",
          "F#",
          "C#",
        ];
        const keyName = keys[sharpsOrFlats + 7] ?? "?";
        return {
          ...base,
          type: "keySignature",
          key: minor ? `${keyName} minor` : keyName,
        };
      }
      case 0x03: {
        // Track / Sequence Name
        const name = new TextDecoder().decode(data);
        return { ...base, type: "trackName", name };
      }
      default:
        return { ...base, type: "meta", metaType, data };
    }
  }
}
