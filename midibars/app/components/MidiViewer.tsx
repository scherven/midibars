"use client";

import { useState, useEffect, useRef } from "react";
import { MidiFile } from "./MidiReader";

export default function MidiViewer({ midiFile }: { midiFile: File | null }) {
  const [fileName, setFileName] = useState<string | null>(null);
  const [midiData, setMidiData] = useState<MidiFile | null>(null);
  const hasLogged = useRef(false);

  useEffect(() => {
    if (!midiFile || hasLogged.current) return;

    const reader = new FileReader();

    reader.onload = (e) => {
      const arrayBuffer = e.target!.result as ArrayBuffer;
      const bytes = new Uint8Array(arrayBuffer);

      const midi = new MidiFile(bytes);

      setFileName(midiFile.name);
      setMidiData(midi);
      hasLogged.current = true;

      // Quick sanity log
      console.log("Format:", midi.header.format);
      console.log("Ticks/beat:", midi.header.ticksPerBeat);
      midi.tracks.forEach((track, i) => {
        console.log(
          `Track ${i} "${track.name ?? "unnamed"}" — ${track.events.length} events`,
        );
        console.log(track.events);
      });
    };

    reader.onerror = (e) => {
      console.error("Error reading file:", e);
    };

    reader.readAsArrayBuffer(midiFile);
  }, [midiFile]);

  return (
    <div>
      <h2>MIDI Viewer</h2>
      <p>{fileName ? `Loaded: ${fileName}` : "No file loaded"}</p>
    </div>
  );
}
