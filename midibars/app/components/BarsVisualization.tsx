interface BarsVisualizationProps {
  noteBars: Array<{
    note: number;
    startTime: number;
    endTime: number;
    channel: number;
    velocity: number;
    notePosition: number;
    verticalPosition: number;
    opacity: number;
    barHeight: number;
    timeUntilStart: number;
  }>;
  videoTime: number;
  currentMidiTime: number | null;
}

export default function BarsVisualization({
  noteBars,
  videoTime,
  currentMidiTime,
}: BarsVisualizationProps) {
  return (
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
  );
}

