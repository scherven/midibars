"use client";
import { useState, useEffect, useRef, useMemo } from "react";
import { MidiFile, MidiEventData } from "./MidiReader";

// ─── Derived note shape used for rendering ──────────────────────────────────
interface ParsedNote {
  note: number; // MIDI note number 0–127
  startTick: number;
  durationTicks: number;
  channel: number;
}

// ─── Extract paired notes from a flat event list ────────────────────────────
function extractNotes(events: MidiEventData[]): ParsedNote[] {
  const notes: ParsedNote[] = [];

  // For each noteOn we need to find the matching noteOff.
  // Key: "channel-note" → stack of unresolved start ticks
  const pending = new Map<string, number[]>();

  for (const ev of events) {
    if (ev.type === "noteOn") {
      const key = `${ev.channel}-${ev.note}`;
      pending.get(key)?.push(ev.absoluteTick) ??
        pending.set(key, [ev.absoluteTick]);
    } else if (ev.type === "noteOff") {
      const key = `${ev.channel}-${ev.note}`;
      const stack = pending.get(key);
      if (stack && stack.length > 0) {
        const startTick = stack.shift()!; // FIFO – first on, first off
        notes.push({
          note: ev.note,
          startTick,
          durationTicks: ev.absoluteTick - startTick,
          channel: ev.channel,
        });
        if (stack.length === 0) pending.delete(key);
      }
    }
  }

  return notes;
}

// ─── Main component ─────────────────────────────────────────────────────────
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
    };
    reader.onerror = (e) => console.error("Error reading file:", e);
    reader.readAsArrayBuffer(midiFile);
  }, [midiFile]);

  // ─── Derived data (memoised so it only recalculates when midiData changes)
  const { notes, minNote, maxNote, totalTicks } = useMemo(() => {
    if (!midiData)
      return { notes: [], minNote: 0, maxNote: 127, totalTicks: 1 };

    // Flatten all tracks into one note list
    const allNotes = midiData.tracks.flatMap((track) =>
      extractNotes(track.events),
    );

    if (allNotes.length === 0)
      return { notes: [], minNote: 0, maxNote: 127, totalTicks: 1 };

    const minNote = Math.min(...allNotes.map((n) => n.note));
    const maxNote = Math.max(...allNotes.map((n) => n.note));
    const totalTicks = Math.max(
      ...allNotes.map((n) => n.startTick + n.durationTicks),
    );

    return { notes: allNotes, minNote, maxNote, totalTicks };
  }, [midiData]);

  // Number of visible pitch rows
  const pitchRange = maxNote - minNote + 1;

  // ─── Render ──────────────────────────────────────────────────────────────
  return (
    <div
      style={{
        width: "100%",
        fontFamily: "'Courier New', monospace",
        background: "#0f1117",
        minHeight: "100vh",
        padding: "24px",
        boxSizing: "border-box",
      }}
    >
      {/* Header */}
      <div style={{ marginBottom: 16 }}>
        <h2
          style={{
            color: "#e2e8f0",
            margin: 0,
            fontSize: 18,
            fontWeight: 600,
            letterSpacing: "0.05em",
          }}
        >
          MIDI VIEWER
        </h2>
        <p style={{ color: "#64748b", margin: "4px 0 0", fontSize: 13 }}>
          {fileName ? `${fileName}` : "No file loaded"}
          {midiData && (
            <span style={{ color: "#475569", marginLeft: 12 }}>
              {notes.length} notes · {midiData.tracks.length} track
              {midiData.tracks.length !== 1 ? "s" : ""} ·{" "}
              {midiData.header.ticksPerBeat} ticks/beat
            </span>
          )}
        </p>
      </div>

      {/* Piano roll */}
      {notes.length > 0 && (
        <div
          style={{
            display: "flex",
            width: "100%",
            borderRadius: 6,
            overflow: "hidden",
            border: "1px solid #1e2230",
            background: "#11131a",
          }}
        >
          {/* Left gutter: note labels */}
          <div
            style={{
              display: "flex",
              flexDirection: "column-reverse", // bottom = low note
              width: 38,
              minWidth: 38,
              borderRight: "1px solid #1e2230",
              background: "#0d0e12",
            }}
          >
            {Array.from({ length: pitchRange }, (_, i) => {
              const midiNote = minNote + i;
              const noteName = noteNumberToName(midiNote);
              const isC = noteName.startsWith("C") && !noteName.includes("#");
              return (
                <div
                  key={midiNote}
                  style={{
                    height: `${100 / pitchRange}%`,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "flex-end",
                    paddingRight: 6,
                    fontSize: 9,
                    color: isC ? "#94a3b8" : "#3b4250",
                    fontWeight: isC ? 600 : 400,
                    borderBottom: isC ? "1px solid #1e2230" : "none",
                    boxSizing: "border-box",
                  }}
                >
                  {isC ? noteName : ""}
                </div>
              );
            })}
          </div>

          {/* Grid + note bars */}
          <div
            style={{
              position: "relative",
              flex: 1,
              // Each pitch row is 12px tall; total height = pitchRange * 12px
              height: pitchRange * 12,
            }}
          >
            {/* Horizontal grid lines (one per pitch row, highlighted on C) */}
            {Array.from({ length: pitchRange }, (_, i) => {
              const midiNote = minNote + i;
              const noteName = noteNumberToName(midiNote);
              const isC = noteName.startsWith("C") && !noteName.includes("#");
              // i=0 is the lowest note; in CSS y=0 is top, so invert
              const topPercent = ((pitchRange - 1 - i) / pitchRange) * 100;
              return (
                <div
                  key={`grid-${midiNote}`}
                  style={{
                    position: "absolute",
                    top: `${topPercent}%`,
                    left: 0,
                    right: 0,
                    height: `${100 / pitchRange}%`,
                    background: isC ? "#161820" : "transparent",
                    borderBottom: isC ? "1px solid #1e2230" : "none",
                    boxSizing: "border-box",
                  }}
                />
              );
            })}

            {/* Note bars */}
            {notes.map((note, idx) => {
              // Vertical: invert so high notes are at the top
              const rowFromTop = maxNote - note.note; // 0 = top row
              const top = (rowFromTop / pitchRange) * 100;
              const height = 100 / pitchRange;

              const left = (note.startTick / totalTicks) * 100;
              const width = Math.max(
                (note.durationTicks / totalTicks) * 100,
                0.15,
              ); // min width so tiny notes are visible

              return (
                <div
                  key={idx}
                  style={{
                    position: "absolute",
                    top: `${top}%`,
                    left: `${left}%`,
                    width: `${width}%`,
                    height: `${height}%`,
                    background: "#3b82f6",
                    borderRadius: 2,
                    boxSizing: "border-box",
                    // Slight inset so bars don't bleed into each other vertically
                    paddingTop: 1,
                    paddingBottom: 1,
                  }}
                >
                  <div
                    style={{
                      width: "100%",
                      height: "100%",
                      background: "#3b82f6",
                      borderRadius: 2,
                    }}
                  />
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Empty state */}
      {midiData && notes.length === 0 && (
        <p style={{ color: "#64748b", fontSize: 14 }}>
          No note events found in this file.
        </p>
      )}
    </div>
  );
}

// ─── Utility: MIDI note number → name (e.g. 60 → "C4") ─────────────────────
const NOTE_NAMES = [
  "C",
  "C#",
  "D",
  "D#",
  "E",
  "F",
  "F#",
  "G",
  "G#",
  "A",
  "A#",
  "B",
];
function noteNumberToName(n: number): string {
  const octave = Math.floor(n / 12) - 1;
  return `${NOTE_NAMES[n % 12]}${octave}`;
}
