import { Menu, AlignCenter, BarChart3, Ruler } from "lucide-react";

interface ToolbarProps {
  sidebarOpen: boolean;
  mode: "normal" | "align" | "bars";
  onSidebarToggle: () => void;
  onModeChange: (mode: "normal" | "align" | "bars") => void;
  isDrawingPianoEdge?: boolean;
  onTogglePianoEdgeDrawing?: () => void;
}

export default function Toolbar({
  sidebarOpen,
  mode,
  onSidebarToggle,
  onModeChange,
  isDrawingPianoEdge = false,
  onTogglePianoEdgeDrawing,
}: ToolbarProps) {
  return (
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
          onClick={onSidebarToggle}
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
        onClick={() => onModeChange(mode === "align" ? "normal" : "align")}
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
        onClick={() => onModeChange(mode === "bars" ? "normal" : "bars")}
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
      
      {mode === "bars" && onTogglePianoEdgeDrawing && (
        <button
          onClick={onTogglePianoEdgeDrawing}
          style={{
            padding: "8px 16px",
            background: isDrawingPianoEdge ? "#10b981" : "#1e293b",
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
          <Ruler size={16} />
          {isDrawingPianoEdge ? "Click 4 points on video" : "Set Piano Edge"}
        </button>
      )}
    </div>
  );
}

