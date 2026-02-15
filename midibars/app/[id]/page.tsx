"use client";

import { useState, useEffect } from "react";
import { useParams } from "next/navigation";
import MidiViewer from "@/app/components/MidiViewer";
import EditableVideoPlayer from "@/app/components/EditableVideoPlayer";
import Sidebar from "@/app/components/Sidebar";
import Toolbar from "@/app/components/Toolbar";
import BarsVisualization from "@/app/components/BarsVisualization";
import { useFileManagement } from "@/app/hooks/useFileManagement";
import { useMidiData } from "@/app/hooks/useMidiData";
import { useVideoPlayback } from "@/app/hooks/useVideoPlayback";
import { useAlignment } from "@/app/hooks/useAlignment";
import { useBarsVisualization } from "@/app/hooks/useBarsVisualization";

export default function MainPage() {
  const params = useParams();
  const id = params.id as string;

  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [mode, setMode] = useState<"normal" | "align" | "bars">("normal");
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [pianoEdge, setPianoEdge] = useState<{ point1: { x: number; y: number } | null; point2: { x: number; y: number } | null }>({
    point1: null,
    point2: null,
  });
  const [isDrawingPianoEdge, setIsDrawingPianoEdge] = useState(false);

  // Custom hooks
  const {
    mp3File,
    midiFile,
    playbackId,
    uploading,
    setMp3File,
    setMidiFile,
    handleFileSelect,
    uploadFile,
  } = useFileManagement(id);

  const { midiData, notes, tempoEvents, ticksPerBeat } = useMidiData(midiFile);

  const {
    videoTime,
    smoothVideoTime,
    isVideoPlaying,
    videoRef,
    audioRef,
    handleVideoTimeUpdate,
    handleVideoPlay,
    handleVideoPause,
    handleVideoSeek,
  } = useVideoPlayback();

  const {
    selectedVideoTime,
    selectedMidiNoteIndex,
    midiPlayheadTime,
    mp3PlayheadTime,
    alignmentData,
    handleMidiPlayheadDrag,
    handleMp3TimeClick,
    handleMp3ArrowKey,
    handleVideoTimeSelect,
  } = useAlignment(id, midiData, notes, audioRef);

  const { currentMidiTime, noteBars } = useBarsVisualization(
    midiData,
    notes,
    tempoEvents,
    ticksPerBeat,
    alignmentData,
    videoTime,
    smoothVideoTime,
    isVideoPlaying,
  );

  // Load piano edge position from localStorage
  useEffect(() => {
    const saved = localStorage.getItem(`piano-edge-${id}`);
    if (saved) {
      try {
        const data = JSON.parse(saved);
        setPianoEdge(data);
      } catch (e) {
        console.error("Failed to load piano edge position:", e);
      }
    }
  }, [id]);

  // Save piano edge position
  useEffect(() => {
    if (pianoEdge.point1 && pianoEdge.point2 && id) {
      localStorage.setItem(`piano-edge-${id}`, JSON.stringify(pianoEdge));
    }
  }, [pianoEdge, id]);

  // Create audio URL for MP3 playback
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

  // File handlers
  const handleMp3Drop = (file: File) => {
    setMp3File(file);
    if (id) uploadFile(file, id, "mp3");
  };

  const handleMidiDrop = (file: File) => {
    setMidiFile(file);
    if (id) uploadFile(file, id, "midi");
  };

  // Video handlers with alignment data
  const onVideoPlay = () => handleVideoPlay(alignmentData);
  const onVideoSeek = () => handleVideoSeek(alignmentData);
  const onVideoTimeSelect = () => handleVideoTimeSelect(videoTime);

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
          transition: "width 0.3s ease",
          overflow: "hidden",
          flexShrink: 0,
        }}
      >
        <Sidebar
          isOpen={sidebarOpen}
          onClose={() => setSidebarOpen(false)}
          playbackId={playbackId}
          mp3File={mp3File}
          midiFile={midiFile}
          uploading={uploading}
          onMp3FileSelect={setMp3File}
          onMidiFileSelect={setMidiFile}
          onMp3Drop={handleMp3Drop}
          onMidiDrop={handleMidiDrop}
          onFileInputChange={handleFileSelect}
        />
      </div>

      {/* Main Content */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <Toolbar
          sidebarOpen={sidebarOpen}
          mode={mode}
          onSidebarToggle={() => setSidebarOpen(true)}
          onModeChange={setMode}
          isDrawingPianoEdge={isDrawingPianoEdge}
          onTogglePianoEdgeDrawing={() => setIsDrawingPianoEdge(!isDrawingPianoEdge)}
        />

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
              <div style={{ background: "#11131a", borderRadius: "8px", padding: "20px", border: "1px solid #1e2230", position: "relative" }}>
                <EditableVideoPlayer
                  playbackId={playbackId}
                  videoRef={videoRef}
                  onTimeUpdate={handleVideoTimeUpdate}
                  onPlay={onVideoPlay}
                  onPause={handleVideoPause}
                  onSeeking={onVideoSeek}
                  onSeeked={onVideoSeek}
                  alignMode={mode === "align"}
                  alignmentData={alignmentData}
                  audioRef={audioRef}
                  selectedVideoTime={selectedVideoTime}
                  currentVideoTime={videoTime}
                  onVideoTimeSelect={onVideoTimeSelect}
                  selectedMidiNoteIndex={selectedMidiNoteIndex}
                  notes={notes}
                  isDrawingPianoEdge={isDrawingPianoEdge}
                  pianoEdge={pianoEdge}
                  onPianoEdgeClick={(x, y) => {
                    if (!pianoEdge.point1) {
                      setPianoEdge({ point1: { x, y }, point2: null });
                    } else if (!pianoEdge.point2) {
                      setPianoEdge({ ...pianoEdge, point2: { x, y } });
                      setIsDrawingPianoEdge(false);
                    }
                  }}
                />
                {/* Bars Visualization - positioned over video */}
                {mode === "bars" && midiData && notes.length > 0 && alignmentData && (
                  <BarsVisualization
                    noteBars={noteBars}
                    videoTime={videoTime}
                    currentMidiTime={currentMidiTime}
                    pianoEdge={pianoEdge}
                    videoRef={videoRef}
                  />
                )}
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
