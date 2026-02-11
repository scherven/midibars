"use client";
import { useState, useEffect, useRef, useMemo, KeyboardEvent } from "react";
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
export default function MidiViewer({
  midiFile,
  mp3File,
}: {
  midiFile: File | null;
  mp3File: File | null;
}) {
  const CONTROL_COLUMN_WIDTH = 40; // px reserved for controls on the left
  const COLUMN_GAP = 8; // px gap between controls and timeline/midi

  const [midiData, setMidiData] = useState<MidiFile | null>(null);
  const hasLogged = useRef(false);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [duration, setDuration] = useState(0); // seconds
  const [currentTime, setCurrentTime] = useState(0); // seconds
  const [cropStart, setCropStart] = useState(0); // seconds
  const [cropEnd, setCropEnd] = useState(0); // seconds
  const [dragging, setDragging] = useState<null | "playhead" | "start" | "end">(
    null,
  );
  const [isPlaying, setIsPlaying] = useState(false);
  const timelineRef = useRef<HTMLDivElement | null>(null);
  const combinedViewRef = useRef<HTMLDivElement | null>(null);
  const [viewStart, setViewStart] = useState(0); // visible window start (seconds)
  const [viewEnd, setViewEnd] = useState(0); // visible window end (seconds)
  const [waveform, setWaveform] = useState<number[]>([]); // simple amplitude envelope for MP3

  useEffect(() => {
    if (!midiFile || hasLogged.current) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      const arrayBuffer = e.target!.result as ArrayBuffer;
      const bytes = new Uint8Array(arrayBuffer);
      const midi = new MidiFile(bytes);
      setMidiData(midi);
      hasLogged.current = true;
    };
    reader.onerror = (e) => console.error("Error reading file:", e);
    reader.readAsArrayBuffer(midiFile);
  }, [midiFile]);

  // Create/revoke object URL for the MP3 so the audio element can play it
  useEffect(() => {
    if (!mp3File) {
      setAudioUrl(null);
      setDuration(0);
      setCurrentTime(0);
      setCropStart(0);
      setCropEnd(0);
      setIsPlaying(false);
      setViewStart(0);
      setViewEnd(0);
      setWaveform([]);
      return;
    }
    const url = URL.createObjectURL(mp3File);
    setAudioUrl(url);
    return () => {
      URL.revokeObjectURL(url);
    };
  }, [mp3File]);

  // Build a simple loudness waveform for the MP3 using Web Audio API
  useEffect(() => {
    if (!mp3File) {
      setWaveform([]);
      return;
    }

    let cancelled = false;
    const reader = new FileReader();

    reader.onload = (e) => {
      const arrayBuffer = e.target?.result;
      if (!arrayBuffer || cancelled) return;

      try {
        const AudioContextClass =
          (window as any).AudioContext || (window as any).webkitAudioContext;
        if (!AudioContextClass) return;

        const audioCtx = new AudioContextClass();
        audioCtx.decodeAudioData(
          arrayBuffer as ArrayBuffer,
          (audioBuffer: AudioBuffer) => {
            if (cancelled) {
              audioCtx.close();
              return;
            }

            const channelData = audioBuffer.getChannelData(0);
            const sampleCount = channelData.length;
            const buckets = 400; // number of points across the viewer
            const bucketSize = Math.max(1, Math.floor(sampleCount / buckets));

            const values: number[] = [];
            let globalMax = 0;

            for (let i = 0; i < buckets; i++) {
              const start = i * bucketSize;
              let sum = 0;
              let count = 0;
              for (let j = 0; j < bucketSize && start + j < sampleCount; j++) {
                const v = channelData[start + j];
                sum += Math.abs(v);
                count++;
              }
              const avg = count > 0 ? sum / count : 0;
              values.push(avg);
              if (avg > globalMax) globalMax = avg;
            }

            // Normalize to 0–1
            const normalized =
              globalMax > 0 ? values.map((v) => v / globalMax) : values;

            setWaveform(normalized);
            audioCtx.close();
          },
          () => {
            audioCtx.close();
          },
        );
      } catch {
        // Ignore waveform errors – viewer still works without it
      }
    };

    reader.readAsArrayBuffer(mp3File);

    return () => {
      cancelled = true;
    };
  }, [mp3File]);

  // Audio element event handlers
  const handleLoadedMetadata = () => {
    if (!audioRef.current) return;
    const d = audioRef.current.duration || 0;
    setDuration(d);
    setCurrentTime(0);
    setCropStart(0);
    setCropEnd(d);
    setViewStart(0);
    setViewEnd(d);
  };

  const handleTimeUpdate = () => {
    if (!audioRef.current) return;
    const t = audioRef.current.currentTime;
    setCurrentTime(t);
    // Stop playback at crop end if defined
    if (t > cropEnd && cropEnd > 0) {
      audioRef.current.pause();
      audioRef.current.currentTime = cropStart;
      setIsPlaying(false);
    }
  };

  const handlePlayPause = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (audio.paused) {
      // Ensure we start inside the crop window
      const startTime = Math.min(
        Math.max(currentTime, cropStart),
        cropEnd || duration,
      );
      audio.currentTime = startTime;
      void audio.play();
    } else {
      audio.pause();
    }
  };

  const handleAudioPlay = () => {
    setIsPlaying(true);
  };

  const handleAudioPause = () => {
    setIsPlaying(false);
  };

  const handleAudioEnded = () => {
    setIsPlaying(false);
    if (audioRef.current) {
      audioRef.current.currentTime = cropStart;
      setCurrentTime(cropStart);
    }
  };

  const timeToPercent = (time: number) => {
    if (!duration || duration <= 0) return 0;
    const start = viewStart;
    const end = viewEnd > start ? viewEnd : duration;
    const span = end - start || duration;
    const clamped = clamp(time, start, end);
    return ((clamped - start) / span) * 100;
  };

  const clamp = (value: number, min: number, max: number) =>
    Math.min(Math.max(value, min), max);

  const nudgeTime = (deltaSeconds: number) => {
    if (!duration) return;
    const min = cropStart;
    const max = cropEnd || duration;
    const target = clamp(currentTime + deltaSeconds, min, max);
    const snapped = Math.round(target * 10) / 10;
    setCurrentTime(snapped);
    if (audioRef.current) {
      audioRef.current.currentTime = snapped;
    }
  };

  const updateFromClientX = (clientX: number, target: "playhead" | "start" | "end") => {
    const el = timelineRef.current;
    if (!el || !duration) return;
    const rect = el.getBoundingClientRect();
    const ratio = clamp((clientX - rect.left) / rect.width, 0, 1);
    // Map within current visible window
    const start = viewStart;
    const end = viewEnd > start ? viewEnd : duration;
    const span = end - start || duration;
    const rawTime = start + ratio * span;
    // Snap to 0.1s resolution
    const snapped = Math.round(rawTime * 10) / 10;

    if (target === "playhead") {
      setCurrentTime(snapped);
      if (audioRef.current) {
        audioRef.current.currentTime = snapped;
      }
    } else if (target === "start") {
      const newStart = clamp(snapped, 0, cropEnd - 0.1);
      setCropStart(newStart);
      if (currentTime < newStart) {
        setCurrentTime(newStart);
        if (audioRef.current) {
          audioRef.current.currentTime = newStart;
        }
      }
    } else if (target === "end") {
      const newEnd = clamp(snapped, cropStart + 0.1, duration);
      setCropEnd(newEnd);
      if (currentTime > newEnd) {
        setCurrentTime(newEnd);
        if (audioRef.current) {
          audioRef.current.currentTime = newEnd;
        }
      }
    }
  };

  // Global mouse listeners for dragging handles / playhead
  useEffect(() => {
    if (!dragging) return;

    const handleMove = (e: MouseEvent) => {
      updateFromClientX(e.clientX, dragging);
    };
    const handleUp = () => {
      // When finishing a crop drag, zoom the view to the selected window
      if (dragging === "start" || dragging === "end") {
        const start = Math.max(0, Math.min(cropStart, cropEnd));
        const end = Math.max(start + 0.1, Math.max(cropStart, cropEnd));
        setViewStart(start);
        setViewEnd(end);
      }
      setDragging(null);
    };

    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleUp);
    return () => {
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleUp);
    };
  }, [dragging, duration, cropStart, cropEnd, currentTime]);

  const handleKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (!duration) return;
    if (e.key === "ArrowLeft") {
      e.preventDefault();
      nudgeTime(-0.1);
    } else if (e.key === "ArrowRight") {
      e.preventDefault();
      nudgeTime(0.1);
    }
  };

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
      tabIndex={0}
      onKeyDown={handleKeyDown}
      style={{
        position: "fixed",
        left: 0,
        right: 0,
        bottom: 0,
        width: "100%",
        fontFamily: "'Courier New', monospace",
        background: "#020617",
        padding: "4px 8px 4px",
        boxSizing: "border-box",
        borderTop: "1px solid #1e2230",
        zIndex: 50,
      }}
    >
      {/* Hidden audio element driving the custom MP3 viewer */}
      {audioUrl && (
        <audio
          ref={audioRef}
          src={audioUrl}
          onLoadedMetadata={handleLoadedMetadata}
          onTimeUpdate={handleTimeUpdate}
          onPlay={handleAudioPlay}
          onPause={handleAudioPause}
          onEnded={handleAudioEnded}
          style={{ display: "none" }}
        />
      )}

      {/* Combined MP3 + MIDI view with a single continuous playhead line */}
      {(audioUrl || notes.length > 0) && (
        <div
          ref={combinedViewRef}
          style={{
            position: "relative",
          }}
        >
          {/* Custom MP3 viewer aligned with MIDI viewer */}
          {audioUrl && (
            <div
              style={{
                display: "grid",
                gridTemplateColumns: `${CONTROL_COLUMN_WIDTH}px 1fr`,
                columnGap: COLUMN_GAP,
                alignItems: "center",
                marginBottom: 4,
              }}
            >
              <button
                type="button"
                onClick={handlePlayPause}
                style={{
                  width: CONTROL_COLUMN_WIDTH,
                  height: 28,
                  borderRadius: "999px",
                  border: "1px solid #1e293b",
                  background: "#020617",
                  color: "#e2e8f0",
                  fontSize: 14,
                  cursor: "pointer",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                {isPlaying ? "❚❚" : "▶︎"}
              </button>

              <div
                ref={timelineRef}
                onMouseDown={(e) => {
                  // Clicking base timeline moves playhead and starts drag
                  updateFromClientX(e.clientX, "playhead");
                  setDragging("playhead");
                }}
                style={{
                  position: "relative",
                  height: 32,
                  borderRadius: 4,
                  background:
                    "linear-gradient(to right, #020617, #020617)",
                  border: "1px solid #1e293b",
                  cursor: "pointer",
                }}
              >
                {/* Waveform visualization (amplitude + color) */}
                {waveform.length > 0 && (
                  <svg
                    viewBox={`0 0 ${waveform.length} 100`}
                    preserveAspectRatio="none"
                    style={{
                      position: "absolute",
                      inset: 0,
                      width: "100%",
                      height: "100%",
                      pointerEvents: "none",
                    }}
                  >
                    {waveform.map((v, i) => {
                      const x = i;
                      const centerY = 50;
                      const amp = 40 * v; // amplitude in viewBox units
                      const y1 = centerY - amp;
                      const y2 = centerY + amp;

                      // Map loudness 0–1 → blue → red
                      const t = v;
                      const r = Math.round(29 + (239 - 29) * t);
                      const g = Math.round(78 + (68 - 78) * t);
                      const b = Math.round(216 + (68 - 216) * t);
                      const color = `rgb(${r}, ${g}, ${b})`;

                      return (
                        <line
                          // eslint-disable-next-line react/no-array-index-key
                          key={i}
                          x1={x}
                          y1={y1}
                          x2={x}
                          y2={y2}
                          stroke={color}
                          strokeWidth={1}
                        />
                      );
                    })}
                  </svg>
                )}

                {/* Crop region highlight */}
                {duration > 0 && cropEnd > cropStart && (
                  <div
                    style={{
                      position: "absolute",
                      top: 0,
                      bottom: 0,
                      left: `${timeToPercent(cropStart)}%`,
                      width: `${timeToPercent(cropEnd) - timeToPercent(cropStart)}%`,
                      background: "rgba(59, 130, 246, 0.25)",
                    }}
                  />
                )}

              </div>
            </div>
          )}

          {/* Piano roll – only the note bars, no labels or text */}
          {notes.length > 0 && (
            <div
              style={{
                display: "grid",
                gridTemplateColumns: `${CONTROL_COLUMN_WIDTH}px 1fr`,
                columnGap: COLUMN_GAP,
                alignItems: "stretch",
              }}
            >
              {/* Empty gutter to line up with play button column above */}
              <div
                style={{
                  width: CONTROL_COLUMN_WIDTH,
                  flexShrink: 0,
                }}
              />
              <div
                style={{
                  position: "relative",
                  // Compact fixed height so each pitch row (and note) is very short
                  height: 80,
                  borderRadius: 4,
                  overflow: "hidden",
                  background: "#020617",
                }}
              >
                {/* Note bars */}
                {notes.map((note, idx) => {
                  // Vertical: invert so high notes are at the top
                  const rowFromTop = maxNote - note.note; // 0 = top row
                  const top = (rowFromTop / pitchRange) * 100;
                  const height = 100 / pitchRange;

                  // Map note horizontally based on the same view window as the MP3
                  const totalTicksSpan = totalTicks || 1;
                  const noteStartRatio = note.startTick / totalTicksSpan;
                  const noteEndRatio =
                    (note.startTick + note.durationTicks) / totalTicksSpan;

                  const durationSpan = duration || 1;
                  const viewStartRatio =
                    duration > 0 ? viewStart / durationSpan : 0;
                  const viewEndRatio =
                    duration > 0 ? viewEnd / durationSpan : 1;
                  const viewSpan = viewEndRatio - viewStartRatio || 1;

                  // Convert note's global position to position within the visible window
                  let leftRatioInView =
                    (noteStartRatio - viewStartRatio) / viewSpan;
                  let rightRatioInView =
                    (noteEndRatio - viewStartRatio) / viewSpan;

                  // If the note is completely outside the view, skip it
                  if (rightRatioInView <= 0 || leftRatioInView >= 1) {
                    return null;
                  }

                  // Clamp partially visible notes to the viewport
                  leftRatioInView = clamp(leftRatioInView, 0, 1);
                  rightRatioInView = clamp(rightRatioInView, 0, 1);

                  const left = leftRatioInView * 100;
                  const width = Math.max(
                    (rightRatioInView - leftRatioInView) * 100,
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
                      }}
                    />
                  );
                })}
              </div>
            </div>
          )}

          {/* Unified handles container - positioned to align with timeline area */}
          {duration > 0 && (
            <div
              style={{
                position: "absolute",
                top: 0,
                bottom: 0,
                left: `${CONTROL_COLUMN_WIDTH + COLUMN_GAP}px`,
                right: 0,
                pointerEvents: "none",
              }}
            >
              {/* Single continuous playhead spanning MP3 + MIDI */}
              <div
                style={{
                  position: "absolute",
                  top: 0,
                  bottom: 0,
                  left: `${timeToPercent(currentTime)}%`,
                  width: 1,
                  marginLeft: -0.5,
                  background: "#38bdf8",
                  pointerEvents: "none",
                }}
              />

              {/* Start crop handle - unified across MP3 + MIDI */}
              <div
                onMouseDown={(e) => {
                  e.stopPropagation();
                  e.preventDefault();
                  // While adjusting crop, show the full track for context
                  setViewStart(0);
                  setViewEnd(duration);
                  setDragging("start");
                  updateFromClientX(e.clientX, "start");
                }}
                style={{
                  position: "absolute",
                  top: 0,
                  bottom: 0,
                  left: `${timeToPercent(cropStart)}%`,
                  width: 4,
                  marginLeft: -2,
                  background: "#f97316",
                  cursor: "ew-resize",
                  zIndex: 10,
                  pointerEvents: "auto",
                }}
              />

              {/* End crop handle - unified across MP3 + MIDI */}
              <div
                onMouseDown={(e) => {
                  e.stopPropagation();
                  e.preventDefault();
                  // While adjusting crop, show the full track for context
                  setViewStart(0);
                  setViewEnd(duration);
                  setDragging("end");
                  updateFromClientX(e.clientX, "end");
                }}
                style={{
                  position: "absolute",
                  top: 0,
                  bottom: 0,
                  left: `${timeToPercent(cropEnd)}%`,
                  width: 4,
                  marginLeft: -2,
                  background: "#f97316",
                  cursor: "ew-resize",
                  zIndex: 10,
                  pointerEvents: "auto",
                }}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
