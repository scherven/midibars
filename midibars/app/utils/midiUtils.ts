import { MidiEventData, TempoMetaEvent } from "@/app/components/MidiReader";

// Extract notes from MIDI events
export function extractNotes(events: MidiEventData[]): Array<{
  note: number;
  startTick: number;
  durationTicks: number;
  channel: number;
  velocity: number;
}> {
  const notes: Array<{
    note: number;
    startTick: number;
    durationTicks: number;
    channel: number;
    velocity: number;
  }> = [];
  const pending = new Map<string, Array<{ startTick: number; velocity: number }>>();

  for (const ev of events) {
    if (ev.type === "noteOn") {
      const key = `${ev.channel}-${ev.note}`;
      const stack = pending.get(key) || [];
      stack.push({ startTick: ev.absoluteTick, velocity: ev.velocity });
      pending.set(key, stack);
    } else if (ev.type === "noteOff") {
      const key = `${ev.channel}-${ev.note}`;
      const stack = pending.get(key);
      if (stack && stack.length > 0) {
        const start = stack.shift()!;
        notes.push({
          note: ev.note,
          startTick: start.startTick,
          durationTicks: ev.absoluteTick - start.startTick,
          channel: ev.channel,
          velocity: start.velocity,
        });
        if (stack.length === 0) pending.delete(key);
      }
    }
  }

  return notes;
}

// Convert MIDI ticks to seconds using tempo events
export function ticksToSeconds(
  tick: number,
  tempoEvents: TempoMetaEvent[],
  ticksPerBeat: number,
): number {
  if (tempoEvents.length === 0) {
    const defaultTempo = 500000;
    return (tick / ticksPerBeat) * (defaultTempo / 1_000_000);
  }

  let seconds = 0;
  let currentTick = 0;
  let currentTempo = tempoEvents[0].microsecondsPerBeat;

  for (let i = 0; i < tempoEvents.length; i++) {
    const tempoEvent = tempoEvents[i];
    const nextTick = i < tempoEvents.length - 1 
      ? tempoEvents[i + 1].absoluteTick 
      : tick;

    if (tick <= nextTick) {
      const ticksInSegment = tick - currentTick;
      seconds += (ticksInSegment / ticksPerBeat) * (currentTempo / 1_000_000);
      return seconds;
    }

    const ticksInSegment = nextTick - currentTick;
    seconds += (ticksInSegment / ticksPerBeat) * (currentTempo / 1_000_000);
    currentTick = nextTick;
    currentTempo = tempoEvent.microsecondsPerBeat;
  }

  const ticksInSegment = tick - currentTick;
  seconds += (ticksInSegment / ticksPerBeat) * (currentTempo / 1_000_000);
  return seconds;
}

