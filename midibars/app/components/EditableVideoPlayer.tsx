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
  isDrawingPianoEdge?: boolean;
  pianoEdge?: {
    point1: { x: number; y: number } | null;
    point2: { x: number; y: number } | null;
    trapezoid?: {
      topLeft: { x: number; y: number };
      topRight: { x: number; y: number };
      bottomRight: { x: number; y: number };
      bottomLeft: { x: number; y: number };
    } | null;
  };
  onPianoEdgeClick?: (x: number, y: number) => void;
  bars?: React.ReactNode;
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
  isDrawingPianoEdge = false,
  pianoEdge = { point1: null, point2: null },
  onPianoEdgeClick,
  bars,
}: EditableVideoPlayerProps) {
  const internalVideoRef = useRef<HTMLVideoElement | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentMp3Percent, setCurrentMp3Percent] = useState<number | null>(
    null,
  );
  const [currentMidiPercent, setCurrentMidiPercent] = useState<number | null>(
    null,
  );

  // Mux video URL
  const videoUrl = `https://stream.mux.com/${playbackId}.m3u8`;

  // Sync refs
  useEffect(() => {
    if (videoRef) {
      if (typeof videoRef === "function") {
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

    player.addEventListener("loadedmetadata", handleLoadedMetadata);
    return () => {
      player.removeEventListener("loadedmetadata", handleLoadedMetadata);
    };
  }, [playbackId]);

  // Calculate MP3% only when selectedVideoTime changes (user clicks select/update)
  useEffect(() => {
    if (
      alignMode &&
      selectedVideoTime !== null &&
      selectedVideoTime !== undefined &&
      alignmentData &&
      audioRef?.current &&
      audioRef.current.duration
    ) {
      const videoStartTime = alignmentData.videoTime;
      const mp3StartTime = alignmentData.mp3Time; // normalized 0-1
      const audioDuration = audioRef.current.duration;
      const mp3StartSeconds = mp3StartTime * audioDuration;
      const videoOffset = selectedVideoTime - videoStartTime;
      const targetMp3Time = mp3StartSeconds + videoOffset;
      const mp3Percent = (targetMp3Time / audioDuration) * 100;
      setCurrentMp3Percent(Math.max(0, Math.min(100, mp3Percent)));
    } else if (
      !alignMode ||
      selectedVideoTime === null ||
      selectedVideoTime === undefined
    ) {
      setCurrentMp3Percent(null);
    }
  }, [alignMode, alignmentData, selectedVideoTime, audioRef]);

  // Calculate MIDI% only when selectedMidiNoteIndex changes (user selects MIDI note)
  useEffect(() => {
    if (
      alignMode &&
      selectedMidiNoteIndex !== null &&
      selectedMidiNoteIndex !== undefined &&
      notes.length > 0
    ) {
      const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
      const maxTick = Math.max(
        ...notes.map((n) => n.startTick + n.durationTicks),
      );
      const totalTicks = maxTick - firstNoteTick;

      if (totalTicks > 0 && selectedMidiNoteIndex < notes.length) {
        const selectedNote = notes[selectedMidiNoteIndex];
        const notePosition = selectedNote.startTick - firstNoteTick;
        const midiPercent = (notePosition / totalTicks) * 100;
        setCurrentMidiPercent(Math.max(0, Math.min(100, midiPercent)));
      } else {
        setCurrentMidiPercent(null);
      }
    } else if (
      !alignMode ||
      selectedMidiNoteIndex === null ||
      selectedMidiNoteIndex === undefined
    ) {
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
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "12px",
            flexWrap: "wrap",
          }}
        >
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
          <div
            style={{ color: "#e2e8f0", fontSize: "14px", minWidth: "100px" }}
          >
            {Math.floor(currentTime / 60)}:
            {Math.floor(currentTime % 60)
              .toString()
              .padStart(2, "0")}{" "}
            / {Math.floor(duration / 60)}:
            {Math.floor(duration % 60)
              .toString()
              .padStart(2, "0")}
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
                <div
                  style={{
                    padding: "8px 16px",
                    background: "#1e293b",
                    borderRadius: "6px",
                    border: "1px solid #334155",
                  }}
                >
                  <span
                    style={{
                      fontSize: "14px",
                      color: "#94a3b8",
                      marginRight: "8px",
                    }}
                  >
                    MP3:
                  </span>
                  <span
                    style={{
                      fontSize: "16px",
                      fontWeight: 600,
                      color: "#e2e8f0",
                    }}
                  >
                    {currentMp3Percent.toFixed(1)}%
                  </span>
                </div>
              )}

              {currentMidiPercent !== null && (
                <div
                  style={{
                    padding: "8px 16px",
                    background: "#1e293b",
                    borderRadius: "6px",
                    border: "1px solid #334155",
                  }}
                >
                  <span
                    style={{
                      fontSize: "14px",
                      color: "#94a3b8",
                      marginRight: "8px",
                    }}
                  >
                    MIDI:
                  </span>
                  <span
                    style={{
                      fontSize: "16px",
                      fontWeight: 600,
                      color: "#e2e8f0",
                    }}
                  >
                    {currentMidiPercent.toFixed(1)}%
                  </span>
                </div>
              )}

              {/* Selected time display */}
              {selectedVideoTime !== null &&
                selectedVideoTime !== undefined && (
                  <div
                    style={{
                      padding: "8px 16px",
                      background: "#1e293b",
                      borderRadius: "6px",
                      border: "1px solid #334155",
                    }}
                  >
                    <span
                      style={{
                        fontSize: "14px",
                        color: "#94a3b8",
                        marginRight: "8px",
                      }}
                    >
                      Selected:
                    </span>
                    <span
                      style={{
                        fontSize: "16px",
                        fontWeight: 600,
                        color: "#e2e8f0",
                      }}
                    >
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
                  {selectedVideoTime
                    ? `Update: ${currentVideoTime.toFixed(2)}s`
                    : `Select: ${currentVideoTime.toFixed(2)}s`}
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
        onClick={(e) => {
          if (isDrawingPianoEdge && onPianoEdgeClick) {
            const rect = e.currentTarget.getBoundingClientRect();
            const x = ((e.clientX - rect.left) / rect.width) * 100;
            const y = ((e.clientY - rect.top) / rect.height) * 100;
            onPianoEdgeClick(x, y);
          }
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
        {/* Piano trapezoid indicator */}
        {pianoEdge.trapezoid && (
          <svg
            viewBox="0 0 100 100"
            preserveAspectRatio="none"
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              height: "100%",
              pointerEvents: "none",
              zIndex: 10,
            }}
          >
            {pianoEdge.trapezoid.topLeft && pianoEdge.trapezoid.topRight && 
             pianoEdge.trapezoid.bottomRight && pianoEdge.trapezoid.bottomLeft && 
             pianoEdge.trapezoid.topRight.x !== 0 && pianoEdge.trapezoid.topRight.y !== 0 &&
             pianoEdge.trapezoid.bottomRight.x !== 0 && pianoEdge.trapezoid.bottomRight.y !== 0 &&
             pianoEdge.trapezoid.bottomLeft.x !== 0 && pianoEdge.trapezoid.bottomLeft.y !== 0 ? (
              <polygon
                points={`
                  ${pianoEdge.trapezoid.topLeft.x},${pianoEdge.trapezoid.topLeft.y}
                  ${pianoEdge.trapezoid.topRight.x},${pianoEdge.trapezoid.topRight.y}
                  ${pianoEdge.trapezoid.bottomRight.x},${pianoEdge.trapezoid.bottomRight.y}
                  ${pianoEdge.trapezoid.bottomLeft.x},${pianoEdge.trapezoid.bottomLeft.y}
                `}
                fill="rgba(16, 185, 129, 0.1)"
                stroke="#10b981"
                strokeWidth="0.2"
                filter="drop-shadow(0 0 0.4px rgba(16, 185, 129, 0.8))"
              />
            ) : (
              <>
                {pianoEdge.trapezoid.topLeft && (
                  <circle
                    cx={pianoEdge.trapezoid.topLeft.x}
                    cy={pianoEdge.trapezoid.topLeft.y}
                    r="0.5"
                    fill="#10b981"
                    filter="drop-shadow(0 0 0.2px rgba(16, 185, 129, 0.8))"
                  />
                )}
                {pianoEdge.trapezoid.topRight && pianoEdge.trapezoid.topRight.x !== 0 && pianoEdge.trapezoid.topRight.y !== 0 && (
                  <>
                    <line
                      x1={pianoEdge.trapezoid.topLeft.x}
                      y1={pianoEdge.trapezoid.topLeft.y}
                      x2={pianoEdge.trapezoid.topRight.x}
                      y2={pianoEdge.trapezoid.topRight.y}
                      stroke="#10b981"
                      strokeWidth="0.2"
                      strokeDasharray="0.4 0.4"
                      filter="drop-shadow(0 0 0.4px rgba(16, 185, 129, 0.8))"
                    />
                    <circle
                      cx={pianoEdge.trapezoid.topRight.x}
                      cy={pianoEdge.trapezoid.topRight.y}
                      r="0.5"
                      fill="#10b981"
                      filter="drop-shadow(0 0 0.2px rgba(16, 185, 129, 0.8))"
                    />
                  </>
                )}
                {pianoEdge.trapezoid.bottomRight && pianoEdge.trapezoid.bottomRight.x !== 0 && pianoEdge.trapezoid.bottomRight.y !== 0 && (
                  <>
                    <line
                      x1={pianoEdge.trapezoid.topRight.x}
                      y1={pianoEdge.trapezoid.topRight.y}
                      x2={pianoEdge.trapezoid.bottomRight.x}
                      y2={pianoEdge.trapezoid.bottomRight.y}
                      stroke="#10b981"
                      strokeWidth="0.2"
                      strokeDasharray="0.4 0.4"
                      filter="drop-shadow(0 0 0.4px rgba(16, 185, 129, 0.8))"
                    />
                    <circle
                      cx={pianoEdge.trapezoid.bottomRight.x}
                      cy={pianoEdge.trapezoid.bottomRight.y}
                      r="0.5"
                      fill="#10b981"
                      filter="drop-shadow(0 0 0.2px rgba(16, 185, 129, 0.8))"
                    />
                  </>
                )}
                {pianoEdge.trapezoid.bottomLeft && pianoEdge.trapezoid.bottomLeft.x !== 0 && pianoEdge.trapezoid.bottomLeft.y !== 0 && (
                  <>
                    <line
                      x1={pianoEdge.trapezoid.bottomRight.x}
                      y1={pianoEdge.trapezoid.bottomRight.y}
                      x2={pianoEdge.trapezoid.bottomLeft.x}
                      y2={pianoEdge.trapezoid.bottomLeft.y}
                      stroke="#10b981"
                      strokeWidth="0.2"
                      strokeDasharray="0.4 0.4"
                      filter="drop-shadow(0 0 0.4px rgba(16, 185, 129, 0.8))"
                    />
                    <line
                      x1={pianoEdge.trapezoid.bottomLeft.x}
                      y1={pianoEdge.trapezoid.bottomLeft.y}
                      x2={pianoEdge.trapezoid.topLeft.x}
                      y2={pianoEdge.trapezoid.topLeft.y}
                      stroke="#10b981"
                      strokeWidth="0.2"
                      strokeDasharray="0.4 0.4"
                      filter="drop-shadow(0 0 0.4px rgba(16, 185, 129, 0.8))"
                    />
                    <circle
                      cx={pianoEdge.trapezoid.bottomLeft.x}
                      cy={pianoEdge.trapezoid.bottomLeft.y}
                      r="0.5"
                      fill="#10b981"
                      filter="drop-shadow(0 0 0.2px rgba(16, 185, 129, 0.8))"
                    />
                  </>
                )}
              </>
            )}
          </svg>
        )}
        {/* Piano edge line indicator (backward compatibility) */}
        {!pianoEdge.trapezoid && pianoEdge.point1 && pianoEdge.point2 && (
          <svg
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              height: "100%",
              pointerEvents: "none",
              zIndex: 10,
            }}
          >
            <line
              x1={`${pianoEdge.point1.x}%`}
              y1={`${pianoEdge.point1.y}%`}
              x2={`${pianoEdge.point2.x}%`}
              y2={`${pianoEdge.point2.y}%`}
              stroke="#10b981"
              strokeWidth="2"
              filter="drop-shadow(0 0 4px rgba(16, 185, 129, 0.8))"
            />
          </svg>
        )}
        {/* First point indicator (backward compatibility) */}
        {!pianoEdge.trapezoid && pianoEdge.point1 && !pianoEdge.point2 && (
          <div
            style={{
              position: "absolute",
              left: `${pianoEdge.point1.x}%`,
              top: `${pianoEdge.point1.y}%`,
              width: "8px",
              height: "8px",
              borderRadius: "50%",
              background: "#10b981",
              transform: "translate(-50%, -50%)",
              pointerEvents: "none",
              zIndex: 11,
              boxShadow: "0 0 8px rgba(16, 185, 129, 0.8)",
            }}
          />
        )}
        {/* Drawing mode overlay */}
        {isDrawingPianoEdge && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              cursor: "crosshair",
              zIndex: 5,
            }}
          />
        )}
        {bars}
      </div>
    </div>
  );
}
