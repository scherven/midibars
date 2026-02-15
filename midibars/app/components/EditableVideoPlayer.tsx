"use client";

import { useState, useRef, useEffect } from "react";

interface EditableVideoPlayerProps {
  playbackId: string;
  videoRef?: React.Ref<any>;
  onTimeUpdate?: (e: any) => void;
  onPlay?: () => void;
  onPause?: () => void;
  onSeeking?: () => void;
  onSeeked?: () => void;
  alignMode?: boolean;
  alignmentData?: any;
  audioRef?: React.RefObject<HTMLAudioElement | null>;
  selectedVideoTime?: number | null;
  currentVideoTime?: number;
  onVideoTimeSelect?: () => void;
  selectedMidiNoteIndex?: number | null;
  notes?: Array<{ startTick: number; durationTicks: number }>;
}

export default function EditableVideoPlayer({
  playbackId,
  videoRef,
  onTimeUpdate,
  onPlay,
  onPause,
  onSeeking,
  onSeeked,
  alignMode = false,
  alignmentData,
  audioRef,
  selectedVideoTime,
  currentVideoTime = 0,
  onVideoTimeSelect,
  selectedMidiNoteIndex,
  notes = [],
}: EditableVideoPlayerProps) {
  const internalVideoRef = useRef<HTMLVideoElement | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentMp3Percent, setCurrentMp3Percent] = useState<number | null>(null);
  const [currentMidiPercent, setCurrentMidiPercent] = useState<number | null>(null);
  
  // Mux video URL
  const videoUrl = `https://stream.mux.com/${playbackId}.m3u8`;
  
  // Sync refs
  useEffect(() => {
    if (videoRef) {
      if (typeof videoRef === 'function') {
        videoRef(internalVideoRef.current);
      } else {
        videoRef.current = internalVideoRef.current;
      }
    }
  }, [videoRef]);

  // Get duration when video loads
  useEffect(() => {
    const player = internalVideoRef.current;
    if (!player) return;

    const handleLoadedMetadata = () => {
      const dur = player.duration || 0;
      setDuration(dur);
    };

    player.addEventListener('loadedmetadata', handleLoadedMetadata);
    return () => {
      player.removeEventListener('loadedmetadata', handleLoadedMetadata);
    };
  }, [playbackId]);

  // Calculate MP3% only when selectedVideoTime changes (user clicks select/update)
  useEffect(() => {
    if (alignMode && selectedVideoTime !== null && selectedVideoTime !== undefined && alignmentData && audioRef?.current && audioRef.current.duration) {
      const videoStartTime = alignmentData.videoTime;
      const mp3StartTime = alignmentData.mp3Time; // normalized 0-1
      const audioDuration = audioRef.current.duration;
      const mp3StartSeconds = mp3StartTime * audioDuration;
      const videoOffset = selectedVideoTime - videoStartTime;
      const targetMp3Time = mp3StartSeconds + videoOffset;
      const mp3Percent = (targetMp3Time / audioDuration) * 100;
      setCurrentMp3Percent(Math.max(0, Math.min(100, mp3Percent)));
    } else if (!alignMode || selectedVideoTime === null || selectedVideoTime === undefined) {
      setCurrentMp3Percent(null);
    }
  }, [alignMode, alignmentData, selectedVideoTime, audioRef]);

  // Calculate MIDI% only when selectedMidiNoteIndex changes (user selects MIDI note)
  useEffect(() => {
    if (alignMode && selectedMidiNoteIndex !== null && selectedMidiNoteIndex !== undefined && notes.length > 0) {
      const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
      const maxTick = Math.max(...notes.map((n) => n.startTick + n.durationTicks));
      const totalTicks = maxTick - firstNoteTick;
      
      if (totalTicks > 0 && selectedMidiNoteIndex < notes.length) {
        const selectedNote = notes[selectedMidiNoteIndex];
        const notePosition = selectedNote.startTick - firstNoteTick;
        const midiPercent = (notePosition / totalTicks) * 100;
        setCurrentMidiPercent(Math.max(0, Math.min(100, midiPercent)));
      } else {
        setCurrentMidiPercent(null);
      }
    } else if (!alignMode || selectedMidiNoteIndex === null || selectedMidiNoteIndex === undefined) {
      setCurrentMidiPercent(null);
    }
  }, [alignMode, selectedMidiNoteIndex, notes]);

  // Handle video time updates for control panel
  const handleTimeUpdateInternal = () => {
    const player = internalVideoRef.current;
    if (!player) return;
    
    const time = player.currentTime || 0;
    setCurrentTime(time);
    
    if (onTimeUpdate) {
      onTimeUpdate({ detail: { currentTime: time } });
    }
  };

  // Handle play/pause for control panel
  const handlePlayInternal = () => {
    if (onPlay) {
      onPlay();
    }
    setIsPlaying(true);
  };

  const handlePauseInternal = () => {
    if (onPause) {
      onPause();
    }
    setIsPlaying(false);
  };
  
  // Handle seeking
  const handleSeekingInternal = () => {
    if (onSeeking) {
      onSeeking();
    }
  };
  
  const handleSeekedInternal = () => {
    if (onSeeked) {
      onSeeked();
    }
  };

  // Control panel handlers
  const handlePlayPause = () => {
    const player = internalVideoRef.current;
    if (!player) return;
    
    if (isPlaying) {
      player.pause();
    } else {
      player.play();
    }
  };

  const handleSeek = (e: React.ChangeEvent<HTMLInputElement>) => {
    const player = internalVideoRef.current;
    if (!player) return;
    
    const newTime = parseFloat(e.target.value);
    player.currentTime = newTime;
    setCurrentTime(newTime);
  };

  return (
    <div style={{ position: "relative", width: "100%" }}>
      {/* Separate control panel - not affected by video */}
      <div
        style={{
          position: "relative",
          width: "100%",
          background: "#0f172a",
          border: "1px solid #1e2230",
          borderRadius: "8px",
          padding: "16px",
          marginBottom: "16px",
          zIndex: 100,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "12px", flexWrap: "wrap" }}>
          {/* Play/Pause button */}
          <button
            onClick={handlePlayPause}
            style={{
              width: "40px",
              height: "40px",
              borderRadius: "50%",
              background: "#3b82f6",
              border: "none",
              color: "white",
              cursor: "pointer",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: "18px",
            }}
          >
            {isPlaying ? "⏸" : "▶"}
          </button>

          {/* Time display */}
          <div style={{ color: "#e2e8f0", fontSize: "14px", minWidth: "100px" }}>
            {Math.floor(currentTime / 60)}:{(Math.floor(currentTime % 60)).toString().padStart(2, '0')} / {Math.floor(duration / 60)}:{(Math.floor(duration % 60)).toString().padStart(2, '0')}
          </div>

          {/* Seek slider */}
          <div style={{ flex: 1, minWidth: "200px", maxWidth: "600px" }}>
            <input
              type="range"
              min="0"
              max={duration || 100}
              value={currentTime}
              onChange={handleSeek}
              style={{
                width: "100%",
                height: "6px",
                borderRadius: "3px",
                background: "#1e293b",
                outline: "none",
                cursor: "pointer",
              }}
            />
          </div>

          {/* MP3% display and update button in align mode */}
          {alignMode && (
            <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
              {currentMp3Percent !== null && (
                <div style={{
                  padding: "8px 16px",
                  background: "#1e293b",
                  borderRadius: "6px",
                  border: "1px solid #334155",
                }}>
                  <span style={{ fontSize: "14px", color: "#94a3b8", marginRight: "8px" }}>MP3:</span>
                  <span style={{ fontSize: "16px", fontWeight: 600, color: "#e2e8f0" }}>
                    {currentMp3Percent.toFixed(1)}%
                  </span>
                </div>
              )}
              
              {currentMidiPercent !== null && (
                <div style={{
                  padding: "8px 16px",
                  background: "#1e293b",
                  borderRadius: "6px",
                  border: "1px solid #334155",
                }}>
                  <span style={{ fontSize: "14px", color: "#94a3b8", marginRight: "8px" }}>MIDI:</span>
                  <span style={{ fontSize: "16px", fontWeight: 600, color: "#e2e8f0" }}>
                    {currentMidiPercent.toFixed(1)}%
                  </span>
                </div>
              )}
              
              {/* Selected time display */}
              {selectedVideoTime !== null && selectedVideoTime !== undefined && (
                <div style={{
                  padding: "8px 16px",
                  background: "#1e293b",
                  borderRadius: "6px",
                  border: "1px solid #334155",
                }}>
                  <span style={{ fontSize: "14px", color: "#94a3b8", marginRight: "8px" }}>Selected:</span>
                  <span style={{ fontSize: "16px", fontWeight: 600, color: "#e2e8f0" }}>
                    {selectedVideoTime.toFixed(2)}s
                  </span>
                </div>
              )}
              
              {/* Update button */}
              {onVideoTimeSelect && (
                <button
                  onClick={onVideoTimeSelect}
                  style={{
                    padding: "8px 16px",
                    background: "#3b82f6",
                    color: "white",
                    border: "none",
                    borderRadius: "6px",
                    cursor: "pointer",
                    fontSize: "14px",
                    fontWeight: 500,
                  }}
                >
                  {selectedVideoTime ? `Update: ${currentVideoTime.toFixed(2)}s` : `Select: ${currentVideoTime.toFixed(2)}s`}
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Video element - non-interactive */}
      <div
        style={{
          position: "relative",
          width: "100%",
          maxWidth: "600px",
          margin: "0 auto",
          background: "#11131a",
          borderRadius: "8px",
          overflow: "hidden",
          border: "1px solid #1e2230",
        }}
      >
        <video
          ref={internalVideoRef}
          src={videoUrl}
          onTimeUpdate={handleTimeUpdateInternal}
          onPlay={handlePlayInternal}
          onPause={handlePauseInternal}
          onSeeking={handleSeekingInternal}
          onSeeked={handleSeekedInternal}
          style={{
            width: "100%",
            height: "auto",
            display: "block",
            pointerEvents: "none", // Disable all interactions
            userSelect: "none",
          }}
          controls={false} // No native controls
          muted={true} // Always mute video - only MP3 plays audio
          playsInline
          preload="metadata"
        />
      </div>
    </div>
  );
}
