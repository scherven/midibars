"use client";

import { useState, useEffect, useRef, useMemo, useCallback } from "react";
import { useParams, useRouter } from "next/navigation";
import MuxPlayer from "@mux/mux-player-react";
import MidiViewer from "@/app/components/MidiViewer";
import { MidiFile, MidiEventData } from "@/app/components/MidiReader";
import Image from "next/image";

// Extract notes from MIDI events (same logic as MidiViewer)
function extractNotes(events: MidiEventData[]): Array<{
  note: number;
  startTick: number;
  durationTicks: number;
  channel: number;
}> {
  const notes: Array<{
    note: number;
    startTick: number;
    durationTicks: number;
    channel: number;
  }> = [];
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
        const startTick = stack.shift()!;
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

export default function AlignPage() {
  const params = useParams();
  const router = useRouter();
  const id = params.id as string;

  const [mp3File, setMp3File] = useState<File | null>(null);
  const [midiFile, setMidiFile] = useState<File | null>(null);
  const [cropState, setCropState] = useState<any>(null);
  const [playbackId, setPlaybackId] = useState<string | null>(null);
  const [videoTime, setVideoTime] = useState(0);
  const [isVideoPlaying, setIsVideoPlaying] = useState(false);
  const [alignmentStep, setAlignmentStep] = useState<
    "video" | "midi" | "mp3" | "aligned"
  >("video");
  const [selectedVideoTime, setSelectedVideoTime] = useState<number | null>(
    null,
  );
  const [selectedMidiNoteIndex, setSelectedMidiNoteIndex] = useState<
    number | null
  >(null);
  const [selectedMp3Time, setSelectedMp3Time] = useState<number | null>(null);
  const [midiData, setMidiData] = useState<MidiFile | null>(null);
  const videoRef = useRef<any>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [alignmentData, setAlignmentData] = useState<any>(null);

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

  // Extract notes from MIDI
  const notes = useMemo(() => {
    if (!midiData) return [];
    const allNotes = midiData.tracks.flatMap((track) =>
      extractNotes(track.events),
    );
    // Sort by startTick
    return allNotes.sort((a, b) => a.startTick - b.startTick);
  }, [midiData]);

  // First 20 notes for selection UI
  const first20Notes = useMemo(() => {
    return notes.slice(0, 20);
  }, [notes]);

  // Load files from server API
  useEffect(() => {
    async function loadFiles() {
      try {
        const savedCrop = localStorage.getItem("image-editor-state");

        // Check if files are uploaded (stored as flags in localStorage)
        const mp3Uploaded = localStorage.getItem(`mp3-${id}-uploaded`);
        const midiUploaded = localStorage.getItem(`midi-${id}-uploaded`);

        console.log("Loading files from server:", {
          mp3Uploaded: !!mp3Uploaded,
          midiUploaded: !!midiUploaded,
          id,
        });

        // Load MP3 from server
        if (mp3Uploaded) {
          try {
            const response = await fetch(`/api/files/${id}/mp3`);
            if (response.ok) {
              const blob = await response.blob();
              const file = new File([blob], `audio-${id}.mp3`, {
                type: "audio/mpeg",
              });
              console.log("MP3 file loaded from server:", file.size);
              setMp3File(file);
            } else {
              console.log("MP3 file not found on server");
            }
          } catch (err) {
            console.error("Failed to load MP3 from server:", err);
          }
        }

        // Load MIDI from server
        if (midiUploaded) {
          try {
            const response = await fetch(`/api/files/${id}/midi`);
            if (response.ok) {
              const blob = await response.blob();
              const file = new File([blob], `audio-${id}.mid`, {
                type: "audio/midi",
              });
              console.log("MIDI file loaded from server:", file.size);
              setMidiFile(file);
            } else {
              console.log("MIDI file not found on server");
            }
          } catch (err) {
            console.error("Failed to load MIDI from server:", err);
          }
        }

        if (savedCrop) {
          setCropState(JSON.parse(savedCrop));
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

  const [midiPlayheadTime, setMidiPlayheadTime] = useState<number>(0);
  const [mp3PlayheadTime, setMp3PlayheadTime] = useState<number>(0);
  const [draggingPlayhead, setDraggingPlayhead] = useState<"midi" | "mp3" | null>(null);
  const [waveform, setWaveform] = useState<number[]>([]);

  // Load waveform data from MidiViewer or compute it
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
            const buckets = 400;
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
        // Ignore waveform errors
      }
    };

    reader.readAsArrayBuffer(mp3File);

    return () => {
      cancelled = true;
    };
  }, [mp3File]);

  const handleVideoTimeUpdate = (e: any) => {
    let currentVideoTime = 0;
    if (e?.detail?.currentTime !== undefined) {
      currentVideoTime = e.detail.currentTime;
      setVideoTime(currentVideoTime);
    } else if (videoRef.current?.currentTime !== undefined) {
      currentVideoTime = videoRef.current.currentTime;
      setVideoTime(currentVideoTime);
    }
    
    // Sync MP3 position when video time updates (for seeking)
    if (alignmentData && audioRef.current && videoRef.current) {
      const videoStartTime = alignmentData.videoTime;
      const mp3StartTime = alignmentData.mp3Time; // normalized 0-1
      const audioDuration = audioRef.current.duration || 0;
      
      if (audioDuration > 0) {
        const mp3StartSeconds = mp3StartTime * audioDuration;
        const videoOffset = currentVideoTime - videoStartTime;
        const targetMp3Time = mp3StartSeconds + videoOffset;
        
        // Only update if significantly different to avoid constant seeking
        const currentMp3Time = audioRef.current.currentTime || 0;
        if (Math.abs(currentMp3Time - targetMp3Time) > 0.05) {
          audioRef.current.currentTime = Math.max(0, Math.min(targetMp3Time, audioDuration));
        }
      }
    }
  };

  const handleVideoPlay = () => {
    setIsVideoPlaying(true);
    
    // Start MP3 playback in sync with video when aligned
    if (alignmentData && audioRef.current && videoRef.current) {
      const videoStartTime = alignmentData.videoTime;
      const mp3StartTime = alignmentData.mp3Time; // normalized 0-1
      const audioDuration = audioRef.current.duration || 0;
      
      if (audioDuration === 0) {
        // Wait for audio to load
        audioRef.current.addEventListener("loadedmetadata", () => {
          const mp3StartSeconds = mp3StartTime * audioRef.current!.duration;
          const currentVideoTime = videoRef.current?.currentTime || 0;
          const videoOffset = currentVideoTime - videoStartTime;
          const targetMp3Time = mp3StartSeconds + videoOffset;
          audioRef.current!.currentTime = Math.max(0, Math.min(targetMp3Time, audioRef.current!.duration));
          audioRef.current!.play().catch((err) => {
            console.error("Error playing MP3:", err);
          });
        }, { once: true });
        return;
      }

      const mp3StartSeconds = mp3StartTime * audioDuration;
      const currentVideoTime = videoRef.current.currentTime || 0;
      const videoOffset = currentVideoTime - videoStartTime;
      const targetMp3Time = mp3StartSeconds + videoOffset;

      // Set time and play - let them run naturally
      audioRef.current.currentTime = Math.max(0, Math.min(targetMp3Time, audioDuration));
      audioRef.current.play().catch((err) => {
        console.error("Error playing MP3:", err);
      });
    }
  };

  const handleVideoPause = () => {
    setIsVideoPlaying(false);
    
    // Pause MP3 when video pauses
    if (audioRef.current && !audioRef.current.paused) {
      audioRef.current.pause();
    }
  };

  // Handle video seeking - sync MP3 position
  const handleVideoSeek = () => {
    if (alignmentData && audioRef.current && videoRef.current) {
      const videoStartTime = alignmentData.videoTime;
      const mp3StartTime = alignmentData.mp3Time; // normalized 0-1
      const audioDuration = audioRef.current.duration || 0;
      
      if (audioDuration > 0) {
        const mp3StartSeconds = mp3StartTime * audioDuration;
        const currentVideoTime = videoRef.current.currentTime || 0;
        const videoOffset = currentVideoTime - videoStartTime;
        const targetMp3Time = mp3StartSeconds + videoOffset;
        
        audioRef.current.currentTime = Math.max(0, Math.min(targetMp3Time, audioDuration));
      }
    }
  };

  const handleVideoTimeSelect = () => {
    setSelectedVideoTime(videoTime);
    // Don't change step - let user drag playheads directly
  };

  // Find next MIDI note after a given time (normalized 0-1)
  const findNextMidiNote = (time: number) => {
    if (!midiData || notes.length === 0) return time;
    const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
    const maxTick = Math.max(
      ...notes.map((n) => n.startTick + n.durationTicks),
    );
    const totalTicks = maxTick - firstNoteTick;
    if (totalTicks === 0) return time;

    // Convert normalized time (0-1) to tick
    const currentTick = firstNoteTick + time * totalTicks;

    // Find next note
    const nextNote = notes.find((n) => n.startTick >= currentTick);
    if (!nextNote) {
      // If no next note, use the last note
      const lastNote = notes[notes.length - 1];
      return (lastNote.startTick - firstNoteTick) / totalTicks;
    }

    // Convert back to normalized time
    const noteTickRatio = (nextNote.startTick - firstNoteTick) / totalTicks;
    return noteTickRatio;
  };

  // Find next sound in MP3 after a given time (normalized 0-1)
  const findNextMp3Sound = (time: number) => {
    if (waveform.length === 0) return time;
    const threshold = 0.1; // Minimum amplitude to consider as "sound"
    const bucketIndex = Math.min(
      Math.floor(time * waveform.length),
      waveform.length - 1,
    );

    // Look forward for next sound (start from current position or slightly ahead)
    for (let i = bucketIndex; i < waveform.length; i++) {
      if (waveform[i] > threshold) {
        return i / waveform.length;
      }
    }
    
    // If no sound found ahead, look backward for the last sound
    for (let i = bucketIndex; i >= 0; i--) {
      if (waveform[i] > threshold) {
        return i / waveform.length;
      }
    }
    
    // If no sound found at all, return current time
    return time;
  };

  const handleMidiPlayheadDrag = (time: number) => {
    const snapped = findNextMidiNote(time);
    setMidiPlayheadTime(snapped);
    
    // Find the note index that corresponds to this time
    if (notes.length > 0) {
      const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
      const maxTick = Math.max(
        ...notes.map((n) => n.startTick + n.durationTicks),
      );
      const totalTicks = maxTick - firstNoteTick;
      if (totalTicks > 0) {
        const currentTick = firstNoteTick + snapped * totalTicks;
        const noteIndex = notes.findIndex((n) => n.startTick >= currentTick);
        if (noteIndex !== -1) {
          setSelectedMidiNoteIndex(noteIndex);
        }
      }
    }
  };

  const handleMidiNoteSelect = (noteIndex: number) => {
    setSelectedMidiNoteIndex(noteIndex);
  };

  // Handle MP3 time selection via click (no snapping)
  const handleMp3TimeClick = (time: number) => {
    setSelectedMp3Time(time);
    setMp3PlayheadTime(time);
    
    // Auto-advance to aligned if all three are selected
    if (selectedVideoTime !== null && selectedMidiNoteIndex !== null) {
      setAlignmentStep("aligned");
    }
  };

  // Handle arrow key movement for MP3 playhead
  const handleMp3ArrowKey = (direction: "left" | "right") => {
    if (selectedMp3Time === null) return;
    
    const audioDuration = audioRef.current?.duration || 0;
    if (audioDuration === 0) return;
    
    const step = 0.1 / audioDuration; // 0.1 seconds as normalized (0-1)
    const newTime = direction === "left" 
      ? Math.max(0, selectedMp3Time - step)
      : Math.min(1, selectedMp3Time + step);
    
    setSelectedMp3Time(newTime);
    setMp3PlayheadTime(newTime);
  };

  // Save alignment when all three are selected and auto-advance to aligned state
  useEffect(() => {
    if (
      selectedVideoTime !== null &&
      selectedMidiNoteIndex !== null &&
      selectedMp3Time !== null &&
      notes.length > 0
    ) {
      setAlignmentStep("aligned");
      saveAlignmentData();
    }
  }, [selectedVideoTime, selectedMidiNoteIndex, selectedMp3Time, notes.length]);

  // Save alignment data to localStorage and API
  const saveAlignmentData = () => {
    if (
      selectedVideoTime !== null &&
      selectedMidiNoteIndex !== null &&
      selectedMp3Time !== null &&
      notes.length > 0
    ) {
      const selectedNote = notes[selectedMidiNoteIndex];
      
      // Calculate MP3 time in seconds (convert from normalized 0-1)
      let mp3TimeSeconds = 0;
      if (audioRef.current && audioRef.current.duration) {
        mp3TimeSeconds = selectedMp3Time * audioRef.current.duration;
      }
      
      const alignmentData = {
        videoTime: selectedVideoTime,
        midiNoteIndex: selectedMidiNoteIndex,
        midiNoteTick: selectedNote.startTick,
        mp3Time: selectedMp3Time, // normalized 0-1
        mp3TimeSeconds: mp3TimeSeconds, // actual seconds
        timestamp: Date.now(),
      };

      // Save to localStorage
      localStorage.setItem(`alignment-${id}`, JSON.stringify(alignmentData));
      setAlignmentData(alignmentData);
      console.log("Alignment data saved (single source of truth):", alignmentData);
    }
  };

  // Load alignment data
  useEffect(() => {
    const saved = localStorage.getItem(`alignment-${id}`);
    if (saved) {
      try {
        const data = JSON.parse(saved);
        setSelectedVideoTime(data.videoTime);
        setSelectedMidiNoteIndex(data.midiNoteIndex);
        setSelectedMp3Time(data.mp3Time);
        setAlignmentData(data);
        setAlignmentStep("aligned");
        console.log("Alignment data loaded:", data);
      } catch (e) {
        console.error("Failed to load alignment data:", e);
      }
    }
  }, [id]);

  // Create audio element for MP3 playback (create early so it's available for syncing)
  useEffect(() => {
    if (mp3File) {
      const url = URL.createObjectURL(mp3File);
      const audio = new Audio(url);
      audioRef.current = audio;
      
      // When audio is loaded, update alignment data with actual duration if needed
      audio.addEventListener("loadedmetadata", () => {
        if (alignmentData && selectedMp3Time !== null && !alignmentData.mp3TimeSeconds) {
          const mp3TimeSeconds = selectedMp3Time * audio.duration;
          const updatedAlignment = {
            ...alignmentData,
            mp3TimeSeconds: mp3TimeSeconds,
          };
          setAlignmentData(updatedAlignment);
          localStorage.setItem(`alignment-${id}`, JSON.stringify(updatedAlignment));
        }
      });
      
      return () => {
        if (audioRef.current) {
          audioRef.current.pause();
          audioRef.current = null;
        }
        URL.revokeObjectURL(url);
      };
    }
  }, [mp3File, id]);

  // Synchronized playback (using the single source of truth)

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#020617",
        color: "#e2e8f0",
        padding: "20px",
        paddingBottom: "140px", // Add space at bottom so fixed MidiViewer doesn't cover content
      }}
    >
      <div style={{ maxWidth: "1400px", margin: "0 auto" }}>
        {/* Header */}
        <div style={{ marginBottom: "20px" }}>
          <h1 style={{ margin: 0, fontSize: "24px", fontWeight: 600 }}>
            Align Video, MIDI, and MP3
          </h1>
          <p style={{ margin: "8px 0 0", color: "#64748b", fontSize: "14px" }}>
            {alignmentStep === "video"
              ? "Play video and click 'Select this moment' when the first note is pressed"
              : alignmentStep === "aligned"
                ? "Alignment complete! Use video controls to play/pause all media. Drag MIDI playhead to adjust, click MP3 timeline to set position. Use left/right arrows to fine-tune MP3."
                : "Drag the MIDI playhead to select the note, then click on the MP3 timeline to set the MP3 position. Use left/right arrows to fine-tune."}
          </p>
        </div>


        {/* Video player */}
        {playbackId && cropState && (
          <div
            style={{
              marginBottom: "20px",
              background: "#11131a",
              borderRadius: "8px",
              padding: "16px",
              border: "1px solid #1e2230",
              position: "relative",
              zIndex: 100, // Ensure video section is above MidiViewer
            }}
          >
            <div
              style={{
                position: "relative",
                width: "100%",
                maxWidth: "800px",
                margin: "0 auto",
              }}
            >
              <MuxPlayer
                playbackId={playbackId}
                streamType="on-demand"
                ref={videoRef}
                onTimeUpdate={handleVideoTimeUpdate}
                onPlay={handleVideoPlay}
                onPause={handleVideoPause}
                onSeeking={handleVideoSeek}
                onSeeked={handleVideoSeek}
                style={{
                  width: "100%",
                  clipPath: cropState.crop
                    ? `inset(${cropState.crop.n}px ${cropState.crop.e}px ${cropState.crop.s}px ${cropState.crop.w}px)`
                    : "none",
                }}
              />
              {alignmentStep === "video" && (
                <div
                  style={{
                    marginTop: "12px",
                    display: "flex",
                    gap: "8px",
                    justifyContent: "center",
                    position: "relative",
                    zIndex: 101, // Ensure button is above video
                  }}
                >
                  <button
                    onClick={handleVideoTimeSelect}
                    style={{
                      padding: "8px 16px",
                      background: "#3b82f6",
                      color: "white",
                      border: "none",
                      borderRadius: "6px",
                      cursor: "pointer",
                      fontSize: "14px",
                      fontWeight: 500,
                      position: "relative",
                      zIndex: 102,
                    }}
                  >
                    Select this moment ({videoTime.toFixed(2)}s)
                  </button>
                </div>
              )}
            </div>
          </div>
        )}


        {/* Alignment info */}
        {alignmentStep === "aligned" && alignmentData && (
          <div
            style={{
              marginBottom: "20px",
              padding: "16px",
              background: "#11131a",
              borderRadius: "8px",
              border: "1px solid #1e2230",
            }}
          >
            <h3 style={{ margin: "0 0 12px", fontSize: "16px" }}>
              Alignment Complete! Use video controls to play/pause all media
            </h3>
            <p style={{ margin: 0, color: "#64748b", fontSize: "14px" }}>
              Video: {alignmentData.videoTime.toFixed(2)}s | MIDI Note: {alignmentData.midiNoteIndex} | MP3: {(alignmentData.mp3Time * 100).toFixed(1)}%
            </p>
          </div>
        )}

        {/* MP3/MIDI viewer with separate playheads */}
        {mp3File && (
          <div style={{ marginTop: "20px", padding: "8px", background: "#1e293b", borderRadius: "4px" }}>
            <p style={{ fontSize: "12px", color: "#94a3b8" }}>
              MP3 loaded: {mp3File.name} ({(mp3File.size / 1024 / 1024).toFixed(2)} MB)
            </p>
          </div>
        )}
        {midiFile && (
          <div style={{ marginTop: "8px", padding: "8px", background: "#1e293b", borderRadius: "4px" }}>
            <p style={{ fontSize: "12px", color: "#94a3b8" }}>
              MIDI loaded: {midiFile.name} ({(midiFile.size / 1024).toFixed(2)} KB)
            </p>
          </div>
        )}
        <MidiViewer
          midiFile={midiFile}
          mp3File={mp3File}
          midiPlayheadTime={midiPlayheadTime}
          mp3PlayheadTime={mp3PlayheadTime}
          onMidiPlayheadDrag={handleMidiPlayheadDrag}
          onMp3TimeClick={handleMp3TimeClick}
          onMp3ArrowKey={handleMp3ArrowKey}
          alignmentMode={true}
          waveformData={waveform}
        />
      </div>
    </div>
  );
}
