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
}

export default function EditableVideoPlayer({
  playbackId,
  videoRef,
  onTimeUpdate,
  onPlay,
  onPause,
  onSeeking,
  onSeeked,
}: EditableVideoPlayerProps) {
  const internalVideoRef = useRef<HTMLVideoElement | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  
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

          {/* Volume control (optional) */}
          <div style={{ display: "flex", alignItems: "center", gap: "8px", color: "#94a3b8", fontSize: "14px" }}>
            <span>🔊</span>
          </div>
        </div>
      </div>

      {/* Video element - non-interactive */}
      <div
        style={{
          position: "relative",
          width: "100%",
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
          playsInline
          preload="metadata"
        />
      </div>
    </div>
  );
}
