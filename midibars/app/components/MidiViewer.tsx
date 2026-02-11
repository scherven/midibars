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
  onMp3TimeSelect,
  midiPlayheadTime,
  mp3PlayheadTime,
  onMidiPlayheadDrag,
  onMp3TimeClick,
  onMp3ArrowKey,
  alignmentMode = false,
  waveformData,
}: {
  midiFile: File | null;
  mp3File: File | null;
  onMp3TimeSelect?: (time: number) => void;
  midiPlayheadTime?: number;
  mp3PlayheadTime?: number;
  onMidiPlayheadDrag?: (time: number) => void;
  onMp3TimeClick?: (time: number) => void;
  onMp3ArrowKey?: (direction: "left" | "right") => void;
  alignmentMode?: boolean;
  waveformData?: number[];
}) {
  const CONTROL_COLUMN_WIDTH = 40; // px reserved for controls on the left
  const COLUMN_GAP = 8; // px gap between controls and timeline/midi

  const [midiData, setMidiData] = useState<MidiFile | null>(null);
  const hasLogged = useRef(false);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [duration, setDuration] = useState(0); // visible MP3 duration after trimming silence
  const [audioLeadIn, setAudioLeadIn] = useState(0); // seconds of trimmed silence at start
  const [currentTime, setCurrentTime] = useState(0); // playback position in visible timeline seconds
  const [cropStart, setCropStart] = useState(0); // seconds
  const [cropEnd, setCropEnd] = useState(0); // seconds
  const [dragging, setDragging] = useState<null | "playhead" | "start" | "end">(
    null,
  );
  const [isPlaying, setIsPlaying] = useState(false);
  const timelineRef = useRef<HTMLDivElement | null>(null);
  const combinedViewRef = useRef<HTMLDivElement | null>(null);
  const [viewStart, setViewStart] = useState(0); // visible window start (seconds, trimmed)
  const [viewEnd, setViewEnd] = useState(0); // visible window end (seconds, trimmed)
  const [waveform, setWaveform] = useState<number[]>([]); // simple amplitude envelope for MP3 (trimmed so index 0 ≈ first sound)

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
      console.log("MidiViewer: No MP3 file provided");
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
    console.log("MidiViewer: MP3 file received:", mp3File.name, mp3File.size, mp3File.type);
    const url = URL.createObjectURL(mp3File);
    console.log("MidiViewer: Created audio URL:", url);
    setAudioUrl(url);
    return () => {
      URL.revokeObjectURL(url);
    };
  }, [mp3File]);

  // Build a simple loudness waveform for the MP3 using Web Audio API
  useEffect(() => {
    if (!mp3File) {
      setWaveform([]);
      setDuration(0);
      setAudioLeadIn(0);
      setCropStart(0);
      setCropEnd(0);
      setViewStart(0);
      setViewEnd(0);
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

            // Find first significant sound (simple threshold)
            const threshold = 0.02;
            let firstIndex = normalized.findIndex((v) => v > threshold);
            if (firstIndex < 0) firstIndex = 0;

            const trimmed = normalized.slice(firstIndex);
            const fullDuration = audioBuffer.duration || 0;
            const bucketDuration =
              fullDuration > 0 ? fullDuration / buckets : 0;
            const leadInSeconds = firstIndex * bucketDuration;
            const visibleDuration = Math.max(fullDuration - leadInSeconds, 0);

            setWaveform(trimmed);
            setAudioLeadIn(leadInSeconds);
            setDuration(visibleDuration);
            setCropStart(0);
            setCropEnd(visibleDuration);
            setViewStart(0);
            setViewEnd(visibleDuration);
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
    const rawT = audioRef.current.currentTime;
    const t = Math.max(0, rawT - audioLeadIn);
    setCurrentTime(t);
    // Stop playback at crop end if defined
    if (t > cropEnd && cropEnd > 0) {
      audioRef.current.pause();
      audioRef.current.currentTime = audioLeadIn + cropStart;
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
      audio.currentTime = Math.max(0, audioLeadIn + startTime);
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

  // For MIDI playhead in alignment mode, time is normalized 0-1 (tick ratio)
  const midiTimeToPercent = (time: number) => {
    // time is already 0-1 representing position in MIDI timeline
    return time * 100;
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
      audioRef.current.currentTime = Math.max(
        0,
        audioLeadIn + snapped,
      );
    }
  };

  const updateFromClientX = (
    clientX: number,
    target: "playhead" | "start" | "end",
  ): number | null => {
    const el = timelineRef.current;
    if (!el || !duration) return null;
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
    return snapped;
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

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    // In alignment mode, arrow keys control MP3 playhead
    if (alignmentMode && onMp3ArrowKey) {
      if (e.key === "ArrowLeft") {
        e.preventDefault();
        onMp3ArrowKey("left");
        return;
      } else if (e.key === "ArrowRight") {
        e.preventDefault();
        onMp3ArrowKey("right");
        return;
      }
    }
    
    // Normal mode: arrow keys control playhead
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
  const { notes, minNote, maxNote, totalTicks, firstNoteTick } = useMemo(() => {
    if (!midiData)
      return {
        notes: [],
        minNote: 0,
        maxNote: 127,
        totalTicks: 1,
        firstNoteTick: 0,
      };

    // Flatten all tracks into one note list
    const allNotes = midiData.tracks.flatMap((track) =>
      extractNotes(track.events),
    );

    if (allNotes.length === 0)
      return {
        notes: [],
        minNote: 0,
        maxNote: 127,
        totalTicks: 1,
        firstNoteTick: 0,
      };

    const minNote = Math.min(...allNotes.map((n) => n.note));
    const maxNote = Math.max(...allNotes.map((n) => n.note));
    const maxTick = Math.max(
      ...allNotes.map((n) => n.startTick + n.durationTicks),
    );
    const firstNoteTick = Math.min(...allNotes.map((n) => n.startTick));
    const totalTicks = maxTick;

    return { notes: allNotes, minNote, maxNote, totalTicks, firstNoteTick };
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
        zIndex: 10, // Lower z-index so video controls aren't covered
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
      {(audioUrl || notes.length > 0 || mp3File) && (
        <div
          ref={combinedViewRef}
          style={{
            position: "relative",
          }}
        >
          {/* Custom MP3 viewer aligned with MIDI viewer */}
          {(audioUrl || mp3File) && (
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
                  if (alignmentMode && onMp3TimeClick) {
                    // In alignment mode, clicking sets MP3 time (no dragging, no snapping)
                    const rect = e.currentTarget.getBoundingClientRect();
                    const ratio = clamp((e.clientX - rect.left) / rect.width, 0, 1);
                    onMp3TimeClick(ratio);
                  } else if (!alignmentMode) {
                    // Normal mode: clicking base timeline moves playhead and starts drag
                    const time = updateFromClientX(e.clientX, "playhead");
                    setDragging("playhead");
                  }
                }}
                style={{
                  position: "relative",
                  height: 32,
                  borderRadius: 4,
                  background:
                    waveform.length > 0
                      ? "linear-gradient(to right, #020617, #020617)"
                      : "#020617", // Show background even without waveform
                  border: "1px solid #1e293b",
                  cursor: alignmentMode ? "pointer" : "pointer",
                  zIndex: 2, // Ensure MP3 bar is visible above MIDI
                  minHeight: 32, // Ensure minimum height
                }}
              >
                {/* Show loading or placeholder if waveform not ready */}
                {waveform.length === 0 && mp3File && (
                  <div
                    style={{
                      position: "absolute",
                      inset: 0,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      color: "#64748b",
                      fontSize: "12px",
                    }}
                  >
                    Loading MP3...
                  </div>
                )}
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
                data-midi-area
                onMouseDown={(e) => {
                  if (alignmentMode && onMidiPlayheadDrag) {
                    // In alignment mode, drag MIDI playhead
                    const rect = e.currentTarget.getBoundingClientRect();
                    const ratio = clamp((e.clientX - rect.left) / rect.width, 0, 1);
                    onMidiPlayheadDrag(ratio);
                  }
                }}
                style={{
                  position: "relative",
                  // Compact fixed height so each pitch row (and note) is very short
                  height: 80,
                  borderRadius: 4,
                  overflow: "hidden",
                  background: "#020617",
                  cursor: alignmentMode ? "ew-resize" : "default",
                  zIndex: 1, // Ensure MIDI area is visible
                }}
              >
                {/* Note bars */}
                {notes.map((note, idx) => {
                  // Vertical: invert so high notes are at the top
                  const rowFromTop = maxNote - note.note; // 0 = top row
                  const top = (rowFromTop / pitchRange) * 100;
                  const height = 100 / pitchRange;

                  // Map note horizontally based on the same view window as the MP3,
                  // rebasing so the first note starts at timeline 0.
                  const totalTicksSpan = Math.max(
                    totalTicks - firstNoteTick,
                    1,
                  );
                  const noteStartRatio =
                    (note.startTick - firstNoteTick) / totalTicksSpan;
                  const noteEndRatio =
                    (note.startTick +
                      note.durationTicks -
                      firstNoteTick) /
                    totalTicksSpan;

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
              {/* In alignment mode, show separate playheads for MIDI and MP3 */}
              {alignmentMode ? (
                <>
                  {/* MP3 playhead - only on MP3 section (clickable, not draggable) */}
                  {mp3PlayheadTime !== undefined && (
                    <div
                      style={{
                        position: "absolute",
                        top: 0,
                        height: "32px", // MP3 bar height
                        left: `${midiTimeToPercent(mp3PlayheadTime)}%`,
                        width: 2,
                        marginLeft: -1,
                        background: "#10b981",
                        cursor: "pointer",
                        zIndex: 20,
                        pointerEvents: "none", // Clicks handled by timeline div
                      }}
                    />
                  )}
                  {/* MIDI playhead - only on MIDI section */}
                  {midiPlayheadTime !== undefined && (
                    <div
                      onMouseDown={(e) => {
                        e.stopPropagation();
                        e.preventDefault();
                        if (onMidiPlayheadDrag) {
                          // Calculate time from mouse position in MIDI area
                          const midiArea = e.currentTarget.parentElement?.querySelector('[data-midi-area]') as HTMLElement;
                          if (midiArea) {
                            const rect = midiArea.getBoundingClientRect();
                            const ratio = clamp((e.clientX - rect.left) / rect.width, 0, 1);
                            onMidiPlayheadDrag(ratio);
                          }
                        }
                      }}
                      style={{
                        position: "absolute",
                        top: "36px", // Below MP3 bar (32px + 4px margin)
                        bottom: 0,
                        left: `${midiTimeToPercent(midiPlayheadTime)}%`,
                        width: 2,
                        marginLeft: -1,
                        background: "#f59e0b",
                        cursor: "ew-resize",
                        zIndex: 20,
                        pointerEvents: "auto",
                      }}
                    />
                  )}
                </>
              ) : (
                /* Single continuous playhead spanning MP3 + MIDI (normal mode) */
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
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
