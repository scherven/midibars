import { useEffect, useRef, useCallback } from "react";

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
  pianoEdge: {
    point1: { x: number; y: number } | null;
    point2: { x: number; y: number } | null;
  };
  videoRef: React.RefObject<any>;
}

export default function BarsVisualization({
  noteBars,
  videoTime,
  currentMidiTime,
  pianoEdge,
  videoRef,
}: BarsVisualizationProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    const videoElement = videoRef.current;
    if (!canvas || !videoElement || !pianoEdge.point1 || !pianoEdge.point2)
      return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    // Get video dimensions
    const videoRect = videoElement.getBoundingClientRect();
    const videoWidth = videoRect.width;
    const videoHeight = videoRect.height;

    // Set canvas size to match video
    const dpr = window.devicePixelRatio || 1;
    canvas.width = videoWidth * dpr;
    canvas.height = videoHeight * dpr;
    ctx.scale(dpr, dpr);
    canvas.style.width = `${videoWidth}px`;
    canvas.style.height = `${videoHeight}px`;

    // Update canvas position to match video
    const parent = videoElement.parentElement;
    if (parent) {
      const parentRect = parent.getBoundingClientRect();
      const videoOffsetLeft = videoRect.left - parentRect.left;
      const videoOffsetTop = videoRect.top - parentRect.top;
      canvas.style.left = `${videoOffsetLeft}px`;
      canvas.style.top = `${videoOffsetTop}px`;
    }

    // Clear canvas
    ctx.clearRect(0, 0, videoWidth, videoHeight);

    // Calculate piano edge line in pixels
    const p1 = {
      x: (pianoEdge.point1.x / 100) * videoWidth,
      y: (pianoEdge.point1.y / 100) * videoHeight,
    };
    const p2 = {
      x: (pianoEdge.point2.x / 100) * videoWidth,
      y: (pianoEdge.point2.y / 100) * videoHeight,
    };

    // Draw grid
    const gridColor = "rgba(30, 41, 59, 0.3)";
    const gridXStep = videoWidth * 0.05; // 5% width
    const gridYStep = videoHeight * 0.1; // 10% height

    ctx.strokeStyle = gridColor;
    ctx.lineWidth = 1;

    // Vertical grid lines
    // for (let x = 0; x <= videoWidth; x += gridXStep) {
    //   ctx.beginPath();
    //   ctx.moveTo(x, 0);
    //   ctx.lineTo(x, videoHeight);
    //   ctx.stroke();
    // }

    // // Horizontal grid lines
    // for (let y = 0; y <= videoHeight; y += gridYStep) {
    //   ctx.beginPath();
    //   ctx.moveTo(0, y);
    //   ctx.lineTo(videoWidth, y);
    //   ctx.stroke();
    // }

    // Draw piano edge line
    // ctx.save();
    // ctx.strokeStyle = "#10b981";
    // ctx.lineWidth = 2;
    // ctx.shadowColor = "rgba(16, 185, 129, 0.8)";
    // ctx.shadowBlur = 8;
    // ctx.beginPath();
    // ctx.moveTo(p1.x, p1.y);
    // ctx.lineTo(p2.x, p2.y);
    // ctx.stroke();
    // ctx.restore();

    // Calculate line equation: y = mx + b
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const m = dx !== 0 ? dy / dx : 0; // slope
    const b = p1.y - m * p1.x; // y-intercept

    // Function to get Y position on line for a given X
    const getYOnLine = (x: number) => m * x + b;

    // Draw bars
    const barWidth = 20;

    noteBars.forEach((bar) => {
      const hue = (bar.channel * 45) % 360;
      const saturation = 90;
      const brightness = 50 + (bar.velocity / 127) * 30;
      const color = `hsl(${hue}, ${saturation}%, ${brightness}%)`;
      const opacity = Math.max(0.8, bar.opacity);

      // X position based on note (0-127 maps to 0-100% of video width)
      const x = (bar.notePosition / 100) * videoWidth - barWidth / 2;

      // Y position on the piano edge line
      const yOnLine = getYOnLine(x + barWidth / 2);

      // Calculate bar position - bars fall downward from the line
      // verticalPosition 0% = at the line, 100% = further down
      const fallDistance = (bar.verticalPosition / 100) * videoHeight * 0.5; // Max fall distance
      const y = yOnLine + fallDistance;
      const height = (bar.barHeight / 600) * videoHeight;
      console.log("drawing", bar, x, y, height);

      // Draw shadow/glow
      ctx.save();
      ctx.globalAlpha = opacity * 0.5;
      ctx.shadowColor = color;
      ctx.shadowBlur = 12;
      ctx.fillStyle = color;
      ctx.fillRect(x, y, barWidth, height);
      ctx.restore();

      // Draw bar with border
      ctx.save();
      ctx.globalAlpha = opacity;
      ctx.fillStyle = color;
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;

      // Draw rounded rectangle
      const radius = 6;
      ctx.beginPath();
      ctx.moveTo(x + radius, y);
      ctx.lineTo(x + barWidth - radius, y);
      ctx.quadraticCurveTo(x + barWidth, y, x + barWidth, y + radius);
      ctx.lineTo(x + barWidth, y + height - radius);
      ctx.quadraticCurveTo(
        x + barWidth,
        y + height,
        x + barWidth - radius,
        y + height,
      );
      ctx.lineTo(x + radius, y + height);
      ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
      ctx.lineTo(x, y + radius);
      ctx.quadraticCurveTo(x, y, x + radius, y);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.restore();
    });
  }, [noteBars, pianoEdge, videoRef]);

  useEffect(() => {
    if (!pianoEdge.point1 || !pianoEdge.point2) return;
    draw();
  }, [draw, pianoEdge]);

  // Handle resize and video time updates
  useEffect(() => {
    if (!pianoEdge.point1 || !pianoEdge.point2) return;

    const videoElement = videoRef.current;
    if (!videoElement) return;

    const resizeObserver = new ResizeObserver(() => {
      draw();
    });

    resizeObserver.observe(videoElement);

    // Also redraw on video time updates for smooth animation
    const interval = setInterval(() => {
      draw();
    }, 16); // ~60fps

    return () => {
      resizeObserver.disconnect();
      clearInterval(interval);
    };
  }, [draw, pianoEdge, videoRef]);

  if (!pianoEdge.point1 || !pianoEdge.point2) {
    return (
      <div
        style={{
          padding: "20px",
          textAlign: "center",
          color: "#94a3b8",
          fontSize: "14px",
        }}
      >
        {!pianoEdge.point1
          ? 'Click "Set Piano Edge" and then click two points on the video to set the piano edge line.'
          : "Click a second point on the video to complete the piano edge line."}
      </div>
    );
  }

  const videoElement = videoRef.current;
  if (!videoElement) return null;

  const videoRect = videoElement.getBoundingClientRect();

  return (
    <canvas
      ref={canvasRef}
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: `${videoRect.width}px`,
        height: `${videoRect.height}px`,
        pointerEvents: "none",
        zIndex: 15,
      }}
    />
  );
}
