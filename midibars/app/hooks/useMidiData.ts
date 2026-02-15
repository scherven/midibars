import { useState, useEffect, useMemo } from "react";
import { MidiFile, TempoMetaEvent } from "@/app/components/MidiReader";
import { extractNotes } from "@/app/utils/midiUtils";

export function useMidiData(midiFile: File | null) {
  const [midiData, setMidiData] = useState<MidiFile | null>(null);

  // Parse MIDI file
  useEffect(() => {
    if (!midiFile) {
      setMidiData(null);
      return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const arrayBuffer = e.target!.result as ArrayBuffer;
        const bytes = new Uint8Array(arrayBuffer);
        const midi = new MidiFile(bytes);
        setMidiData(midi);
      } catch (error) {
        console.error("Failed to parse MIDI:", error);
      }
    };
    reader.readAsArrayBuffer(midiFile);
  }, [midiFile]);

  // Extract notes and tempo events
  const { notes, tempoEvents, ticksPerBeat } = useMemo(() => {
    if (!midiData) {
      return { notes: [], tempoEvents: [], ticksPerBeat: 480 };
    }

    const allTempoEvents: TempoMetaEvent[] = [];
    for (const track of midiData.tracks) {
      for (const event of track.events) {
        if (event.type === "tempo") {
          allTempoEvents.push(event);
        }
      }
    }
    allTempoEvents.sort((a, b) => a.absoluteTick - b.absoluteTick);

    const allNotes = midiData.tracks.flatMap((track) =>
      extractNotes(track.events),
    );

    return {
      notes: allNotes.length > 0 ? allNotes.sort((a, b) => a.startTick - b.startTick) : [],
      tempoEvents: allTempoEvents,
      ticksPerBeat: midiData.header.ticksPerBeat,
    };
  }, [midiData]);

  return {
    midiData,
    notes,
    tempoEvents,
    ticksPerBeat,
  };
}

