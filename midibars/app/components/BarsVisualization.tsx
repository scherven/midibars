import { useEffect, useRef, useCallback } from "react";

const BAR_WIDTH = 10;
const BAR_RADIUS = 6;
const ANIMATION_FPS = 60;
const FRAME_INTERVAL = 1000 / ANIMATION_FPS;

// Piano constants
const PIANO_START_NOTE = 21; // A0 (first key on 88-key piano)
const PIANO_END_NOTE = 108; // C8 (last key on 88-key piano)
const PIANO_TOTAL_KEYS = 88;
const PIANO_WHITE_KEYS = 52;
const PIANO_BLACK_KEYS = 36;

// White keys in an octave (C, D, E, F, G, A, B) - MIDI note % 12 values
const WHITE_KEY_SEMITONES = [0, 2, 4, 5, 7, 9, 11];
const BLACK_KEY_SEMITONES = [1, 3, 6, 8, 10];

/**
 * Check if a MIDI note is a white key
 */
function isWhiteKey(note: number): boolean {
  return WHITE_KEY_SEMITONES.includes(note % 12);
}

/**
 * Calculate note position based on white keys only (0-100%)
 * Maps MIDI note to position along the 52 white keys of an 88-key piano
 */
export function calculateNotePositionWhiteKeys(note: number): number {
  // Clamp to piano range
  const clampedNote = Math.max(PIANO_START_NOTE, Math.min(PIANO_END_NOTE, note));
  
  // Count white keys from start of piano to this note
  let whiteKeyCount = 0;
  for (let n = PIANO_START_NOTE; n <= clampedNote; n++) {
    if (isWhiteKey(n)) {
      whiteKeyCount++;
    }
  }
  
  // Map to 0-100% based on 52 white keys
  return ((whiteKeyCount - 1) / (PIANO_WHITE_KEYS - 1)) * 100;
}

/**
 * Calculate note position based on all keys (white + black) (0-100%)
 * Maps MIDI note to position along all 88 keys of a piano
 */
export function calculateNotePositionAllKeys(note: number): number {
  // Clamp to piano range
  const clampedNote = Math.max(PIANO_START_NOTE, Math.min(PIANO_END_NOTE, note));
  
  // Calculate position: (note - start) / (end - start) * 100
  return ((clampedNote - PIANO_START_NOTE) / (PIANO_END_NOTE - PIANO_START_NOTE)) * 100;
}

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
  pianoEdge: {
    point1: { x: number; y: number } | null;
    point2: { x: number; y: number } | null;
  };
  videoRef: React.RefObject<any>;
}

export default function BarsVisualization({
  noteBars,
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

    // Calculate line direction and perpendicular vector
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const lineLength = Math.sqrt(dx * dx + dy * dy);

    // Normalized direction vector along the line
    const dirX = lineLength > 0 ? dx / lineLength : 0;
    const dirY = lineLength > 0 ? dy / lineLength : 0;

    // Perpendicular direction (bars extend in this direction)
    const perpX = -dirY;
    const perpY = dirX;

    noteBars.forEach((bar) => {
      // Calculate bar color based on channel and velocity
      const hue = (bar.channel * 45) % 360;
      const saturation = 90;
      const brightness = 50 + (bar.velocity / 127) * 30;
      const color = `hsl(${hue}, ${saturation}%, ${brightness}%)`;
      const opacity = Math.max(0.8, bar.opacity);

      // Calculate touch point on the line
      const noteProgress = bar.notePosition / 100;
      const xOnLine = p1.x + noteProgress * dx;
      const yOnLine = p1.y + noteProgress * dy;

      // Calculate offset from line (for verticalPosition)
      const fallDistance =
        (bar.verticalPosition / 100) * Math.max(videoWidth, videoHeight) * 0.5 -
        250;
      const barTouchX = xOnLine + fallDistance * perpX;
      const barTouchY = yOnLine + fallDistance * perpY;

      // Bar dimensions
      const barThinWidth = BAR_WIDTH;
      const barLength = (bar.barHeight / 600) * videoHeight;

      // Calculate bar center (bar extends away from touch point)
      const barMidX = barTouchX - (barLength / 2) * perpX;
      const barMidY = barTouchY - (barLength / 2) * perpY;

      // Rotation angle to align bar perpendicular to line
      const angle = Math.atan2(perpY, perpX);

      const halfWidth = barThinWidth / 2;
      const halfLength = barLength / 2;

      // Draw shadow/glow
      ctx.save();
      ctx.translate(barMidX, barMidY);
      ctx.rotate(angle);
      ctx.globalAlpha = opacity * 0.5;
      ctx.shadowColor = color;
      ctx.shadowBlur = 12;
      ctx.fillStyle = color;
      ctx.fillRect(-halfLength, -halfWidth, barLength, barThinWidth);
      ctx.restore();

      // Draw rounded rectangle bar
      ctx.save();
      ctx.translate(barMidX, barMidY);
      ctx.rotate(angle);
      ctx.globalAlpha = opacity;
      ctx.fillStyle = color;
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;

      // Draw rounded rectangle
      ctx.beginPath();
      ctx.moveTo(-halfLength + BAR_RADIUS, -halfWidth);
      ctx.lineTo(halfLength - BAR_RADIUS, -halfWidth);
      ctx.quadraticCurveTo(
        halfLength,
        -halfWidth,
        halfLength,
        -halfWidth + BAR_RADIUS,
      );
      ctx.lineTo(halfLength, halfWidth - BAR_RADIUS);
      ctx.quadraticCurveTo(
        halfLength,
        halfWidth,
        halfLength - BAR_RADIUS,
        halfWidth,
      );
      ctx.lineTo(-halfLength + BAR_RADIUS, halfWidth);
      ctx.quadraticCurveTo(
        -halfLength,
        halfWidth,
        -halfLength,
        halfWidth - BAR_RADIUS,
      );
      ctx.lineTo(-halfLength, -halfWidth + BAR_RADIUS);
      ctx.quadraticCurveTo(
        -halfLength,
        -halfWidth,
        -halfLength + BAR_RADIUS,
        -halfWidth,
      );
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

  // Handle resize and animation updates
  useEffect(() => {
    if (!pianoEdge.point1 || !pianoEdge.point2) return;

    const videoElement = videoRef.current;
    if (!videoElement) return;

    const resizeObserver = new ResizeObserver(draw);
    resizeObserver.observe(videoElement);

    const interval = setInterval(draw, FRAME_INTERVAL);

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
