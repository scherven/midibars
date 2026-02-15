"use client";

import { useState, useEffect, useRef, useMemo } from "react";
import { useParams } from "next/navigation";
import MuxPlayer from "@mux/mux-player-react";
import { MidiFile, MidiEventData, TempoMetaEvent } from "@/app/components/MidiReader";

// Extract notes from MIDI events
function extractNotes(events: MidiEventData[]): Array<{
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
function ticksToSeconds(
  tick: number,
  tempoEvents: TempoMetaEvent[],
  ticksPerBeat: number,
): number {
  if (tempoEvents.length === 0) {
    // Default tempo: 120 BPM = 500000 microseconds per beat
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
      // Target tick is in this tempo segment
      const ticksInSegment = tick - currentTick;
      seconds += (ticksInSegment / ticksPerBeat) * (currentTempo / 1_000_000);
      return seconds;
    }

    // Process this tempo segment
    const ticksInSegment = nextTick - currentTick;
    seconds += (ticksInSegment / ticksPerBeat) * (currentTempo / 1_000_000);
    currentTick = nextTick;
    currentTempo = tempoEvent.microsecondsPerBeat;
  }

  // If we get here, tick is after all tempo events
  const ticksInSegment = tick - currentTick;
  seconds += (ticksInSegment / ticksPerBeat) * (currentTempo / 1_000_000);
  return seconds;
}

export default function BarsPage() {
  const params = useParams();
  const id = params.id as string;

  const [midiFile, setMidiFile] = useState<File | null>(null);
  const [mp3File, setMp3File] = useState<File | null>(null);
  const [midiData, setMidiData] = useState<MidiFile | null>(null);
  const [playbackId, setPlaybackId] = useState<string | null>(null);
  const [videoTime, setVideoTime] = useState(0);
  const [smoothVideoTime, setSmoothVideoTime] = useState(0);
  const [isVideoPlaying, setIsVideoPlaying] = useState(false);
  const [alignmentData, setAlignmentData] = useState<any>(null);
  const videoRef = useRef<any>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const animationFrameRef = useRef<number | null>(null);

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

  // Load files from server API
  useEffect(() => {
    async function loadFiles() {
      try {
        const mp3Uploaded = localStorage.getItem(`mp3-${id}-uploaded`);
        const midiUploaded = localStorage.getItem(`midi-${id}-uploaded`);

        if (mp3Uploaded) {
          try {
            const response = await fetch(`/api/files/${id}/mp3`);
            if (response.ok) {
              const blob = await response.blob();
              const file = new File([blob], `audio-${id}.mp3`, {
                type: "audio/mpeg",
              });
              setMp3File(file);
            }
          } catch (err) {
            console.error("Failed to load MP3 from server:", err);
          }
        }

        if (midiUploaded) {
          try {
            const response = await fetch(`/api/files/${id}/midi`);
            if (response.ok) {
              const blob = await response.blob();
              const file = new File([blob], `audio-${id}.mid`, {
                type: "audio/midi",
              });
              setMidiFile(file);
            }
          } catch (err) {
            console.error("Failed to load MIDI from server:", err);
          }
        }
      } catch (error) {
        console.error("Failed to load files:", error);
      }
    }
    loadFiles();
  }, [id]);

  // Fetch playback ID from Mux
  useEffect(() => {
    async function fetchAsset() {
      try {
        const response = await fetch(`/api/mux-asset/${id}`);
        if (response.ok) {
          const data = await response.json();
          if (data.playback_ids?.[0]?.id) {
            setPlaybackId(data.playback_ids[0].id);
          }
        }
      } catch (error) {
        console.error("Failed to fetch asset:", error);
      }
    }
    fetchAsset();
  }, [id]);

  // Load alignment data
  useEffect(() => {
    const saved = localStorage.getItem(`alignment-${id}`);
    if (saved) {
      try {
        const data = JSON.parse(saved);
        setAlignmentData(data);
      } catch (e) {
        console.error("Failed to load alignment data:", e);
      }
    }
  }, [id]);

  const handleVideoTimeUpdate = (e: any) => {
    const currentTime = e?.detail?.currentTime ?? videoRef.current?.currentTime ?? 0;
    if (currentTime > 0) {
      setVideoTime(currentTime);
      setSmoothVideoTime(currentTime);
    }
  };

  // Smooth animation loop for continuous bar movement
  useEffect(() => {
    if (!isVideoPlaying) {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
        animationFrameRef.current = null;
      }
      return;
    }

    const animate = () => {
      if (videoRef.current?.currentTime) {
        setSmoothVideoTime(videoRef.current.currentTime);
      }
      animationFrameRef.current = requestAnimationFrame(animate);
    };

    animationFrameRef.current = requestAnimationFrame(animate);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
        animationFrameRef.current = null;
      }
    };
  }, [isVideoPlaying]);

  const handleVideoPlay = () => {
    setIsVideoPlaying(true);
    
    if (alignmentData && audioRef.current && videoRef.current) {
      const { videoTime: videoStartTime, mp3Time: mp3StartTime } = alignmentData;
      const audioDuration = audioRef.current.duration || 0;
      
      const syncAudio = () => {
        const mp3StartSeconds = mp3StartTime * audioRef.current!.duration;
        const currentVideoTime = videoRef.current?.currentTime || 0;
        const videoOffset = currentVideoTime - videoStartTime;
        const targetMp3Time = mp3StartSeconds + videoOffset;
        audioRef.current!.currentTime = Math.max(0, Math.min(targetMp3Time, audioRef.current!.duration));
        audioRef.current!.play().catch((err) => {
          console.error("Error playing MP3:", err);
        });
      };

      if (audioDuration === 0) {
        audioRef.current.addEventListener("loadedmetadata", syncAudio, { once: true });
      } else {
        syncAudio();
      }
    }
  };

  const handleVideoPause = () => {
    setIsVideoPlaying(false);
    audioRef.current?.pause();
  };

  const handleVideoSeek = () => {
    if (videoRef.current?.currentTime) {
      setSmoothVideoTime(videoRef.current.currentTime);
    }
    
    if (alignmentData && audioRef.current && videoRef.current) {
      const { videoTime: videoStartTime, mp3Time: mp3StartTime } = alignmentData;
      const audioDuration = audioRef.current.duration;
      
      if (audioDuration > 0) {
        const mp3StartSeconds = mp3StartTime * audioDuration;
        const currentVideoTime = videoRef.current.currentTime || 0;
        const videoOffset = currentVideoTime - videoStartTime;
        const targetMp3Time = mp3StartSeconds + videoOffset;
        audioRef.current.currentTime = Math.max(0, Math.min(targetMp3Time, audioDuration));
      }
    }
  };

  // Create audio URL for MP3 playback
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  
  useEffect(() => {
    if (mp3File) {
      const url = URL.createObjectURL(mp3File);
      setAudioUrl(url);
      return () => {
        URL.revokeObjectURL(url);
      };
    } else {
      setAudioUrl(null);
    }
  }, [mp3File]);

  const currentMidiTime = useMemo(() => {
    if (!alignmentData || !midiData || notes.length === 0) {
      return null;
    }

    const { videoTime: videoStartTime, midiNoteIndex } = alignmentData;
    
    if (midiNoteIndex >= notes.length) {
      return null;
    }
    
    const alignedNote = notes[midiNoteIndex];
    const alignedNoteStartSeconds = ticksToSeconds(
      alignedNote.startTick,
      tempoEvents,
      ticksPerBeat,
    );

    const timeToUse = isVideoPlaying ? smoothVideoTime : videoTime;
    const videoOffset = timeToUse - videoStartTime;
    const midiTimeSeconds = alignedNoteStartSeconds + videoOffset;
    
    return Math.max(0, midiTimeSeconds);
  }, [smoothVideoTime, videoTime, isVideoPlaying, alignmentData, notes, tempoEvents, ticksPerBeat, midiData]);

  const visibleNotes = useMemo(() => {
    if (!midiData || notes.length === 0 || currentMidiTime === null) {
      return [];
    }

    const lookAheadTime = 2;
    const windowEnd = currentMidiTime + lookAheadTime;

    return notes
      .map((note) => {
        const startTime = ticksToSeconds(note.startTick, tempoEvents, ticksPerBeat);
        const duration = ticksToSeconds(note.durationTicks, tempoEvents, ticksPerBeat);
        
        if (startTime > currentMidiTime && startTime <= windowEnd) {
          return {
            note: note.note,
            startTime,
            endTime: startTime + duration,
            channel: note.channel,
            velocity: note.velocity,
          };
        }
        return null;
      })
      .filter((note): note is NonNullable<typeof note> => note !== null);
  }, [notes, tempoEvents, ticksPerBeat, currentMidiTime, midiData]);

  const noteBars = useMemo(() => {
    if (visibleNotes.length === 0 || currentMidiTime === null) {
      return [];
    }

    return visibleNotes.map((noteData) => {
      const notePosition = (noteData.note / 127) * 100;
      const timeUntilStart = noteData.startTime - currentMidiTime;
      const clampedTime = Math.max(0.001, Math.min(2, timeUntilStart));
      const verticalPosition = 50 - (clampedTime / 2) * 50;
      const opacity = 0.7 + (clampedTime / 2) * 0.3;
      const noteDuration = noteData.endTime - noteData.startTime;
      const barHeight = Math.max(20, Math.min(150, noteDuration * 40));

      return {
        ...noteData,
        notePosition,
        verticalPosition,
        opacity,
        barHeight,
        timeUntilStart,
      };
    });
  }, [visibleNotes, currentMidiTime]);

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#020617",
        color: "#e2e8f0",
        padding: "20px",
        position: "relative",
        overflow: "hidden",
      }}
    >
      <div style={{ maxWidth: "1400px", margin: "0 auto" }}>
        <h1 style={{ margin: "0 0 20px 0", fontSize: "24px", fontWeight: 600 }}>
          MIDI Bars
        </h1>

        {playbackId && (
          <div style={{ marginBottom: "40px", maxWidth: "800px", marginLeft: "auto", marginRight: "auto" }}>
            <MuxPlayer
              playbackId={playbackId}
              streamType="on-demand"
              ref={videoRef}
              onTimeUpdate={handleVideoTimeUpdate}
              onPlay={handleVideoPlay}
              onPause={handleVideoPause}
              onSeeking={handleVideoSeek}
              onSeeked={handleVideoSeek}
              style={{ width: "100%" }}
            />
            {audioUrl && (
              <audio ref={audioRef} src={audioUrl} style={{ display: "none" }} />
            )}
          </div>
        )}

        {/* MIDI Bars Visualization */}
        {midiData && notes.length > 0 && alignmentData ? (
          <div
            style={{
              position: "relative",
              width: "100%",
              height: "600px",
              background: "#0a0f1a",
              borderRadius: "8px",
              border: "1px solid #1e2230",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                position: "absolute",
                inset: 0,
                backgroundImage: `
                  linear-gradient(to right, rgba(30, 41, 59, 0.3) 1px, transparent 1px),
                  linear-gradient(to bottom, rgba(30, 41, 59, 0.3) 1px, transparent 1px)
                `,
                backgroundSize: "5% 10%",
                pointerEvents: "none",
                zIndex: 0,
              }}
            />
            
            {noteBars.map((bar, idx) => {
              const hue = (bar.channel * 45) % 360;
              const saturation = 90;
              const brightness = 50 + (bar.velocity / 127) * 30;
              const color = `hsl(${hue}, ${saturation}%, ${brightness}%)`;

              return (
                <div
                  key={`${bar.note}-${bar.startTime}-${idx}`}
                  style={{
                    position: "absolute",
                    left: `${bar.notePosition}%`,
                    top: `${bar.verticalPosition}%`,
                    width: "20px",
                    height: `${bar.barHeight}px`,
                    background: color,
                    borderRadius: "6px",
                    opacity: Math.max(0.8, bar.opacity),
                    transform: "translateX(-50%)",
                    boxShadow: `0 0 12px ${color}, 0 0 6px ${color}80`,
                    border: `2px solid ${color}`,
                    zIndex: 10,
                    pointerEvents: "none",
                  }}
                />
              );
            })}
            
            <div
              style={{
                position: "absolute",
                left: 0,
                right: 0,
                top: "50%",
                height: "4px",
                background: "linear-gradient(to right, transparent, rgba(59, 130, 246, 1), transparent)",
                pointerEvents: "none",
                zIndex: 15,
                boxShadow: "0 0 8px rgba(59, 130, 246, 0.8)",
              }}
            />
            
            <div
              style={{
                position: "absolute",
                top: "10px",
                left: "10px",
                padding: "8px 12px",
                background: "rgba(15, 23, 42, 0.95)",
                borderRadius: "6px",
                border: "1px solid #1e2230",
                fontSize: "12px",
                color: "#e2e8f0",
                zIndex: 20,
              }}
            >
              <div>Video: {videoTime.toFixed(2)}s</div>
              {currentMidiTime !== null && <div>MIDI: {currentMidiTime.toFixed(2)}s</div>}
            </div>
          </div>
        ) : (
          <div
            style={{
              padding: "40px",
              textAlign: "center",
              background: "#11131a",
              borderRadius: "8px",
              border: "1px solid #1e2230",
            }}
          >
            {!midiData && <p>Loading MIDI file...</p>}
            {midiData && notes.length === 0 && <p>No MIDI notes found.</p>}
            {midiData && notes.length > 0 && !alignmentData && (
              <p>Please align the media first in the align page.</p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

