import { FileAudio, Music, X } from "lucide-react";

interface SidebarProps {
  isOpen: boolean;
  onClose: () => void;
  playbackId: string | null;
  mp3File: File | null;
  midiFile: File | null;
  uploading: { mp3: boolean; midi: boolean };
  onMp3FileSelect: (file: File) => void;
  onMidiFileSelect: (file: File) => void;
  onMp3Drop: (file: File) => void;
  onMidiDrop: (file: File) => void;
  onFileInputChange: (e: React.ChangeEvent<HTMLInputElement>, type: "mp3" | "midi", extensions: string[]) => void;
}

export default function Sidebar({
  isOpen,
  onClose,
  playbackId,
  mp3File,
  midiFile,
  uploading,
  onMp3FileSelect,
  onMidiFileSelect,
  onMp3Drop,
  onMidiDrop,
  onFileInputChange,
}: SidebarProps) {
  if (!isOpen) return null;

  return (
    <div
      style={{
        width: "280px",
        background: "#0f172a",
        borderRight: "1px solid #1e2230",
        flexShrink: 0,
      }}
    >
      <div style={{ padding: "20px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
          <h2 style={{ margin: 0, fontSize: "18px", fontWeight: 600 }}>Files</h2>
          <button
            onClick={onClose}
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
                onMp3Drop(file);
              }
            }}
          >
            <input
              id="mp3-input"
              type="file"
              accept=".mp3,audio/mpeg"
              onChange={(e) => onFileInputChange(e, "mp3", [".mp3"])}
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
                onMidiDrop(file);
              }
            }}
          >
            <input
              id="midi-input"
              type="file"
              accept=".mid,.midi,audio/midi"
              onChange={(e) => onFileInputChange(e, "midi", [".mid", ".midi"])}
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
    </div>
  );
}

