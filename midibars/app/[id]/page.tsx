"use client";

import { useState, useEffect, useRef, useMemo } from "react";
import { useParams } from "next/navigation";
import MidiViewer from "@/app/components/MidiViewer";
import EditableVideoPlayer from "@/app/components/EditableVideoPlayer";
import { MidiFile, MidiEventData, TempoMetaEvent } from "@/app/components/MidiReader";
import { Upload, Music, FileAudio, Video, Menu, X, AlignCenter, BarChart3 } from "lucide-react";

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

export default function MainPage() {
  const params = useParams();
  const id = params.id as string;

  // Sidebar state
  const [sidebarOpen, setSidebarOpen] = useState(true);
  
  // File states
  const [mp3File, setMp3File] = useState<File | null>(null);
  const [midiFile, setMidiFile] = useState<File | null>(null);
  const [midiData, setMidiData] = useState<MidiFile | null>(null);
  const [playbackId, setPlaybackId] = useState<string | null>(null);
  
  // Mode states
  const [mode, setMode] = useState<"normal" | "align" | "bars">("normal");
  
  // Video states
  const [videoTime, setVideoTime] = useState(0);
  const [smoothVideoTime, setSmoothVideoTime] = useState(0);
  const [isVideoPlaying, setIsVideoPlaying] = useState(false);
  const videoRef = useRef<any>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const animationFrameRef = useRef<number | null>(null);
  
  // Alignment states (for align mode)
  const [alignmentStep, setAlignmentStep] = useState<"video" | "midi" | "mp3" | "aligned">("video");
  const [selectedVideoTime, setSelectedVideoTime] = useState<number | null>(null);
  const [selectedMidiNoteIndex, setSelectedMidiNoteIndex] = useState<number | null>(null);
  const [selectedMp3Time, setSelectedMp3Time] = useState<number | null>(null);
  const [midiPlayheadTime, setMidiPlayheadTime] = useState<number>(0);
  const [mp3PlayheadTime, setMp3PlayheadTime] = useState<number>(0);
  const [alignmentData, setAlignmentData] = useState<any>(null);
  
  // Upload states
  const [uploading, setUploading] = useState<{ mp3: boolean; midi: boolean }>({
    mp3: false,
    midi: false,
  });

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
        setSelectedVideoTime(data.videoTime);
        setSelectedMidiNoteIndex(data.midiNoteIndex);
        setSelectedMp3Time(data.mp3Time);
        setAlignmentData(data);
        setAlignmentStep("aligned");
      } catch (e) {
        console.error("Failed to load alignment data:", e);
      }
    }
  }, [id]);

  // File upload handler
  const uploadFile = async (file: File, assetId: string, fileType: "mp3" | "midi") => {
    setUploading((prev) => ({ ...prev, [fileType]: true }));
    try {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("assetId", assetId);
      formData.append("fileType", fileType);

      const response = await fetch("/api/files/upload", {
        method: "POST",
        body: formData,
      });

      if (!response.ok) {
        throw new Error("Upload failed");
      }

      localStorage.setItem(`${fileType}-${assetId}-uploaded`, "true");
      console.log(`${fileType} uploaded successfully`);
    } catch (error) {
      console.error(`Error uploading ${fileType}:`, error);
      alert(`Failed to upload ${fileType} file. Please try again.`);
    } finally {
      setUploading((prev) => ({ ...prev, [fileType]: false }));
    }
  };

  const handleFileSelect = (
    e: React.ChangeEvent<HTMLInputElement>,
    type: "mp3" | "midi",
    acceptedExtensions: string[],
  ) => {
    const file = e.target.files?.[0];
    if (
      file &&
      acceptedExtensions.some((ext: string) => file.name.toLowerCase().endsWith(ext))
    ) {
      if (type === "mp3") {
        setMp3File(file);
        if (id) {
          uploadFile(file, id, "mp3");
        }
      } else {
        setMidiFile(file);
        if (id) {
          uploadFile(file, id, "midi");
        }
      }
    } else {
      alert(`Please select a valid ${acceptedExtensions.join(" or ")} file`);
    }
  };

  // Video handlers
  const handleVideoTimeUpdate = (e: any) => {
    const currentTime = e?.detail?.currentTime ?? videoRef.current?.currentTime ?? 0;
    if (currentTime > 0) {
      setVideoTime(currentTime);
      setSmoothVideoTime(currentTime);
    }
  };

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

  const handleVideoTimeSelect = () => {
    setSelectedVideoTime(videoTime);
  };

  // Alignment handlers
  const findNextMidiNote = (time: number) => {
    if (!midiData || notes.length === 0) return time;
    const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
    const maxTick = Math.max(
      ...notes.map((n) => n.startTick + n.durationTicks),
    );
    const totalTicks = maxTick - firstNoteTick;
    if (totalTicks === 0) return time;

    const currentTick = firstNoteTick + time * totalTicks;
    const nextNote = notes.find((n) => n.startTick >= currentTick);
    if (!nextNote) {
      const lastNote = notes[notes.length - 1];
      return (lastNote.startTick - firstNoteTick) / totalTicks;
    }

    const noteTickRatio = (nextNote.startTick - firstNoteTick) / totalTicks;
    return noteTickRatio;
  };

  const handleMidiPlayheadDrag = (time: number) => {
    const snapped = findNextMidiNote(time);
    setMidiPlayheadTime(snapped);
    
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

  const handleMp3TimeClick = (time: number) => {
    setSelectedMp3Time(time);
    setMp3PlayheadTime(time);
    
    if (selectedVideoTime !== null && selectedMidiNoteIndex !== null) {
      setAlignmentStep("aligned");
    }
  };

  const handleMp3ArrowKey = (direction: "left" | "right") => {
    if (selectedMp3Time === null) return;
    
    const audioDuration = audioRef.current?.duration || 0;
    if (audioDuration === 0) return;
    
    const step = 0.1 / audioDuration;
    const newTime = direction === "left" 
      ? Math.max(0, selectedMp3Time - step)
      : Math.min(1, selectedMp3Time + step);
    
    setSelectedMp3Time(newTime);
    setMp3PlayheadTime(newTime);
  };

  // Save alignment data
  useEffect(() => {
    if (
      selectedVideoTime !== null &&
      selectedMidiNoteIndex !== null &&
      selectedMp3Time !== null &&
      notes.length > 0
    ) {
      setAlignmentStep("aligned");
      const selectedNote = notes[selectedMidiNoteIndex];
      
      let mp3TimeSeconds = 0;
      if (audioRef.current && audioRef.current.duration) {
        mp3TimeSeconds = selectedMp3Time * audioRef.current.duration;
      }
      
      const alignmentData = {
        videoTime: selectedVideoTime,
        midiNoteIndex: selectedMidiNoteIndex,
        midiNoteTick: selectedNote.startTick,
        mp3Time: selectedMp3Time,
        mp3TimeSeconds: mp3TimeSeconds,
        timestamp: Date.now(),
      };

      localStorage.setItem(`alignment-${id}`, JSON.stringify(alignmentData));
      setAlignmentData(alignmentData);
    }
  }, [selectedVideoTime, selectedMidiNoteIndex, selectedMp3Time, notes.length, id]);

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

  // Bars visualization calculations
  const currentMidiTime = useMemo(() => {
    if (!alignmentData || !midiData || notes.length === 0 || selectedMidiNoteIndex === null) {
      return null;
    }

    if (selectedMidiNoteIndex >= notes.length) {
      return null;
    }
    
    // Calculate MIDI% from selected note (same as in EditableVideoPlayer)
    const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
    const maxTick = Math.max(...notes.map((n) => n.startTick + n.durationTicks));
    const totalTicks = maxTick - firstNoteTick;
    
    if (totalTicks === 0) {
      return null;
    }
    
    const selectedNote = notes[selectedMidiNoteIndex];
    const notePosition = selectedNote.startTick - firstNoteTick;
    const midiPercent = (notePosition / totalTicks) * 100;
    
    // Convert MIDI% back to MIDI time in seconds
    // Find the tick position from the percentage
    const targetTick = firstNoteTick + (midiPercent / 100) * totalTicks;
    const midiTimeSeconds = ticksToSeconds(targetTick, tempoEvents, ticksPerBeat);
    
    return Math.max(0, midiTimeSeconds);
  }, [alignmentData, notes, tempoEvents, ticksPerBeat, midiData, selectedMidiNoteIndex]);

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
        display: "flex",
        position: "relative",
      }}
    >
      {/* Sidebar */}
      <div
        style={{
          width: sidebarOpen ? "280px" : "0",
          background: "#0f172a",
          borderRight: "1px solid #1e2230",
          transition: "width 0.3s ease",
          overflow: "hidden",
          flexShrink: 0,
        }}
      >
        {sidebarOpen && (
          <div style={{ padding: "20px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
              <h2 style={{ margin: 0, fontSize: "18px", fontWeight: 600 }}>Files</h2>
              <button
                onClick={() => setSidebarOpen(false)}
                style={{
                  background: "transparent",
                  border: "none",
                  color: "#e2e8f0",
                  cursor: "pointer",
                  padding: "4px",
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Video Upload */}
            <div style={{ marginBottom: "20px" }}>
              <label style={{ display: "block", marginBottom: "8px", fontSize: "14px", color: "#94a3b8" }}>
                Video (Mux)
              </label>
              {playbackId ? (
                <div style={{
                  padding: "12px",
                  background: "#1e293b",
                  borderRadius: "6px",
                  border: "1px solid #334155",
                  fontSize: "12px",
                }}>
                  ✓ Video loaded
                </div>
              ) : (
                <div style={{
                  padding: "12px",
                  background: "#1e293b",
                  borderRadius: "6px",
                  border: "1px solid #334155",
                  fontSize: "12px",
                  color: "#64748b",
                }}>
                  No video
                </div>
              )}
            </div>

            {/* MP3 Upload */}
            <div style={{ marginBottom: "20px" }}>
              <label style={{ display: "block", marginBottom: "8px", fontSize: "14px", color: "#94a3b8" }}>
                MP3 File
              </label>
              <div
                style={{
                  border: "2px dashed #334155",
                  borderRadius: "8px",
                  padding: "16px",
                  textAlign: "center",
                  cursor: "pointer",
                  background: mp3File ? "#1e293b" : "transparent",
                  transition: "all 0.2s",
                }}
                onClick={() => document.getElementById("mp3-input")?.click()}
                onDragOver={(e) => {
                  e.preventDefault();
                  e.currentTarget.style.borderColor = "#3b82f6";
                }}
                onDragLeave={(e) => {
                  e.currentTarget.style.borderColor = "#334155";
                }}
                onDrop={(e) => {
                  e.preventDefault();
                  const file = e.dataTransfer.files[0];
                  if (file && file.name.toLowerCase().endsWith(".mp3")) {
                    setMp3File(file);
                    if (id) uploadFile(file, id, "mp3");
                  }
                }}
              >
                <input
                  id="mp3-input"
                  type="file"
                  accept=".mp3,audio/mpeg"
                  onChange={(e) => handleFileSelect(e, "mp3", [".mp3"])}
                  style={{ display: "none" }}
                />
                <FileAudio size={24} style={{ marginBottom: "8px", color: "#64748b" }} />
                {mp3File ? (
                  <div>
                    <p style={{ margin: 0, fontSize: "12px", color: "#10b981" }}>{mp3File.name}</p>
                    {uploading.mp3 && <p style={{ margin: "4px 0 0 0", fontSize: "11px", color: "#3b82f6" }}>Uploading...</p>}
                  </div>
                ) : (
                  <p style={{ margin: 0, fontSize: "12px", color: "#64748b" }}>Drop MP3 or click</p>
                )}
              </div>
            </div>

            {/* MIDI Upload */}
            <div style={{ marginBottom: "20px" }}>
              <label style={{ display: "block", marginBottom: "8px", fontSize: "14px", color: "#94a3b8" }}>
                MIDI File
              </label>
              <div
                style={{
                  border: "2px dashed #334155",
                  borderRadius: "8px",
                  padding: "16px",
                  textAlign: "center",
                  cursor: "pointer",
                  background: midiFile ? "#1e293b" : "transparent",
                  transition: "all 0.2s",
                }}
                onClick={() => document.getElementById("midi-input")?.click()}
                onDragOver={(e) => {
                  e.preventDefault();
                  e.currentTarget.style.borderColor = "#3b82f6";
                }}
                onDragLeave={(e) => {
                  e.currentTarget.style.borderColor = "#334155";
                }}
                onDrop={(e) => {
                  e.preventDefault();
                  const file = e.dataTransfer.files[0];
                  if (file && (file.name.toLowerCase().endsWith(".mid") || file.name.toLowerCase().endsWith(".midi"))) {
                    setMidiFile(file);
                    if (id) uploadFile(file, id, "midi");
                  }
                }}
              >
                <input
                  id="midi-input"
                  type="file"
                  accept=".mid,.midi,audio/midi"
                  onChange={(e) => handleFileSelect(e, "midi", [".mid", ".midi"])}
                  style={{ display: "none" }}
                />
                <Music size={24} style={{ marginBottom: "8px", color: "#64748b" }} />
                {midiFile ? (
                  <div>
                    <p style={{ margin: 0, fontSize: "12px", color: "#10b981" }}>{midiFile.name}</p>
                    {uploading.midi && <p style={{ margin: "4px 0 0 0", fontSize: "11px", color: "#3b82f6" }}>Uploading...</p>}
                  </div>
                ) : (
                  <p style={{ margin: 0, fontSize: "12px", color: "#64748b" }}>Drop MIDI or click</p>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Main Content */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        {/* Toolbar */}
        <div
          style={{
            padding: "12px 20px",
            background: "#0f172a",
            borderBottom: "1px solid #1e2230",
            display: "flex",
            alignItems: "center",
            gap: "12px",
          }}
        >
          {!sidebarOpen && (
            <button
              onClick={() => setSidebarOpen(true)}
              style={{
                background: "transparent",
                border: "none",
                color: "#e2e8f0",
                cursor: "pointer",
                padding: "8px",
                display: "flex",
                alignItems: "center",
              }}
            >
              <Menu size={20} />
            </button>
          )}
          
          <button
            onClick={() => setMode(mode === "align" ? "normal" : "align")}
            style={{
              padding: "8px 16px",
              background: mode === "align" ? "#3b82f6" : "#1e293b",
              color: "#e2e8f0",
              border: "1px solid #334155",
              borderRadius: "6px",
              cursor: "pointer",
              fontSize: "14px",
              fontWeight: 500,
              display: "flex",
              alignItems: "center",
              gap: "8px",
            }}
          >
            <AlignCenter size={16} />
            Align
          </button>
          
          <button
            onClick={() => setMode(mode === "bars" ? "normal" : "bars")}
            style={{
              padding: "8px 16px",
              background: mode === "bars" ? "#3b82f6" : "#1e293b",
              color: "#e2e8f0",
              border: "1px solid #334155",
              borderRadius: "6px",
              cursor: "pointer",
              fontSize: "14px",
              fontWeight: 500,
              display: "flex",
              alignItems: "center",
              gap: "8px",
            }}
          >
            <BarChart3 size={16} />
            Bars
          </button>
        </div>

        {/* Video Player Area */}
        <div style={{ padding: "20px", overflow: "auto", flex: 1 }}>
          {/* MidiViewer at the top in align mode */}
          {mode === "align" && (
            <div style={{ marginBottom: "20px" }}>
              <MidiViewer
                midiFile={midiFile}
                mp3File={mp3File}
                midiPlayheadTime={midiPlayheadTime}
                mp3PlayheadTime={mp3PlayheadTime}
                onMidiPlayheadDrag={handleMidiPlayheadDrag}
                onMp3TimeClick={handleMp3TimeClick}
                onMp3ArrowKey={handleMp3ArrowKey}
                alignmentMode={true}
              />
            </div>
          )}

          {playbackId && (
            <div style={{ marginBottom: "20px", maxWidth: "1200px", marginLeft: "auto", marginRight: "auto" }}>
              <div style={{ background: "#11131a", borderRadius: "8px", padding: "20px", border: "1px solid #1e2230" }}>
                <EditableVideoPlayer
                  playbackId={playbackId}
                  videoRef={videoRef}
                  onTimeUpdate={handleVideoTimeUpdate}
                  onPlay={handleVideoPlay}
                  onPause={handleVideoPause}
                  onSeeking={handleVideoSeek}
                  onSeeked={handleVideoSeek}
                  alignMode={mode === "align"}
                  alignmentData={alignmentData}
                  audioRef={audioRef}
                  selectedVideoTime={selectedVideoTime}
                  currentVideoTime={videoTime}
                  onVideoTimeSelect={handleVideoTimeSelect}
                  selectedMidiNoteIndex={selectedMidiNoteIndex}
                  notes={notes}
                />
              </div>
            </div>
          )}

          {/* Bars Visualization */}
          {mode === "bars" && midiData && notes.length > 0 && alignmentData && (
            <div
              style={{
                position: "relative",
                width: "100%",
                height: "600px",
                background: "#0a0f1a",
                borderRadius: "8px",
                border: "1px solid #1e2230",
                overflow: "hidden",
                marginBottom: "20px",
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
          )}

          {/* Audio element for MP3 playback */}
          {audioUrl && (
            <audio ref={audioRef} src={audioUrl} style={{ display: "none" }} />
          )}

          {/* MidiViewer at the bottom (when not in align mode) */}
          {mode !== "align" && (
            <div style={{ marginTop: "auto" }}>
              <MidiViewer
                midiFile={midiFile}
                mp3File={mp3File}
                midiPlayheadTime={undefined}
                mp3PlayheadTime={undefined}
                onMidiPlayheadDrag={undefined}
                onMp3TimeClick={undefined}
                onMp3ArrowKey={undefined}
                alignmentMode={false}
              />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

