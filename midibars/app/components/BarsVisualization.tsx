import { useEffect, useRef, useCallback, useMemo } from "react";
import {
  getPerspectiveTransform,
  inverseTransformPoint,
  calculateWarpedWidth,
  calculateWarpedHeight,
  type Trapezoid,
} from "@/app/utils/perspectiveTransform";

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
    trapezoid?: Trapezoid | null;
  };
  videoRef: React.RefObject<any>;
}

export default function BarsVisualization({
  noteBars,
  pianoEdge,
  videoRef,
}: BarsVisualizationProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // Calculate perspective transform if trapezoid is defined
  // This needs to be recalculated when video dimensions change, so we'll do it in draw()

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    const videoElement = videoRef.current;
    
    // Check if we have either trapezoid or 2-point edge
    const hasTrapezoid = pianoEdge.trapezoid && 
      pianoEdge.trapezoid.topRight.x !== 0 && pianoEdge.trapezoid.topRight.y !== 0 &&
      pianoEdge.trapezoid.bottomRight.x !== 0 && pianoEdge.trapezoid.bottomRight.y !== 0 &&
      pianoEdge.trapezoid.bottomLeft.x !== 0 && pianoEdge.trapezoid.bottomLeft.y !== 0;
    
    if (!canvas || !videoElement || (!hasTrapezoid && (!pianoEdge.point1 || !pianoEdge.point2)))
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

    let p1: { x: number; y: number };
    let p2: { x: number; y: number };
    let dx: number;
    let dy: number;
    let lineLength: number;
    let dirX: number;
    let dirY: number;
    let perpX: number;
    let perpY: number;
    let perspectiveTransform: {
      transform: number[];
      warpedWidth: number;
      warpedHeight: number;
    } | null = null;

    if (hasTrapezoid) {
      const trapezoid = pianoEdge.trapezoid!;
      
      // Convert percentage coordinates to pixel coordinates for transformation
      const trapezoidPixels: Trapezoid = {
        topLeft: {
          x: (trapezoid.topLeft.x / 100) * videoWidth,
          y: (trapezoid.topLeft.y / 100) * videoHeight,
        },
        topRight: {
          x: (trapezoid.topRight.x / 100) * videoWidth,
          y: (trapezoid.topRight.y / 100) * videoHeight,
        },
        bottomRight: {
          x: (trapezoid.bottomRight.x / 100) * videoWidth,
          y: (trapezoid.bottomRight.y / 100) * videoHeight,
        },
        bottomLeft: {
          x: (trapezoid.bottomLeft.x / 100) * videoWidth,
          y: (trapezoid.bottomLeft.y / 100) * videoHeight,
        },
      };

      // Calculate warped dimensions (these return percentages, convert to pixels)
      const warpedWidthPercent = calculateWarpedWidth(trapezoid);
      const warpedHeightPercent = calculateWarpedHeight(trapezoid);
      const targetWidth = (warpedWidthPercent / 100) * videoWidth;
      const targetHeight = (warpedHeightPercent / 100) * videoHeight;

      try {
        const transform = getPerspectiveTransform(trapezoidPixels, targetWidth, targetHeight);
        perspectiveTransform = {
          transform,
          warpedWidth: targetWidth,
          warpedHeight: targetHeight,
        };
      } catch (e) {
        console.error("Failed to calculate perspective transform:", e);
        perspectiveTransform = null;
      }
    }

    if (hasTrapezoid && perspectiveTransform) {
      // Use trapezoid: map note position to warped rectangle, then transform back
      // The top edge of the warped rectangle represents the piano edge
      const trapezoid = pianoEdge.trapezoid!;
      p1 = {
        x: (trapezoid.topLeft.x / 100) * videoWidth,
        y: (trapezoid.topLeft.y / 100) * videoHeight,
      };
      p2 = {
        x: (trapezoid.topRight.x / 100) * videoWidth,
        y: (trapezoid.topRight.y / 100) * videoHeight,
      };
      
      // For trapezoid, we'll calculate the direction along the top edge
      dx = p2.x - p1.x;
      dy = p2.y - p1.y;
      lineLength = Math.sqrt(dx * dx + dy * dy);
      dirX = lineLength > 0 ? dx / lineLength : 0;
      dirY = lineLength > 0 ? dy / lineLength : 0;
      perpX = -dirY;
      perpY = dirX;
    } else {
      // Fallback to 2-point system
      p1 = {
        x: (pianoEdge.point1!.x / 100) * videoWidth,
        y: (pianoEdge.point1!.y / 100) * videoHeight,
      };
      p2 = {
        x: (pianoEdge.point2!.x / 100) * videoWidth,
        y: (pianoEdge.point2!.y / 100) * videoHeight,
      };

      // Calculate line direction and perpendicular vector
      dx = p2.x - p1.x;
      dy = p2.y - p1.y;
      lineLength = Math.sqrt(dx * dx + dy * dy);

      // Normalized direction vector along the line
      dirX = lineLength > 0 ? dx / lineLength : 0;
      dirY = lineLength > 0 ? dy / lineLength : 0;

      // Perpendicular direction (bars extend in this direction)
      perpX = -dirY;
      perpY = dirX;
    }

    noteBars.forEach((bar) => {
      // Calculate bar color based on channel and velocity
      const hue = (bar.channel * 45) % 360;
      const saturation = 90;
      const brightness = 50 + (bar.velocity / 127) * 30;
      const color = `hsl(${hue}, ${saturation}%, ${brightness}%)`;
      const opacity = Math.max(0.8, bar.opacity);

      // Calculate touch point on the line
      let xOnLine: number;
      let yOnLine: number;

      if (hasTrapezoid && perspectiveTransform) {
        // Map note position (0-100%) to position along the top edge of the warped rectangle
        // In the warped rectangle, the note position maps to a point on the top edge
        const noteProgress = bar.notePosition / 100;
        const warpedX = noteProgress * perspectiveTransform.warpedWidth;
        const warpedY = 0; // Top edge of the warped rectangle

        // Transform back to original trapezoid coordinates
        const originalPoint = inverseTransformPoint(
          { x: warpedX, y: warpedY },
          perspectiveTransform.transform,
        );

        xOnLine = originalPoint.x;
        yOnLine = originalPoint.y;
      } else {
        // Use simple linear interpolation for 2-point system
        const noteProgress = bar.notePosition / 100;
        xOnLine = p1.x + noteProgress * dx;
        yOnLine = p1.y + noteProgress * dy;
      }

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
    const hasTrapezoid = pianoEdge.trapezoid && 
      pianoEdge.trapezoid.topRight.x !== 0 && pianoEdge.trapezoid.topRight.y !== 0 &&
      pianoEdge.trapezoid.bottomRight.x !== 0 && pianoEdge.trapezoid.bottomRight.y !== 0 &&
      pianoEdge.trapezoid.bottomLeft.x !== 0 && pianoEdge.trapezoid.bottomLeft.y !== 0;
    
    if (!hasTrapezoid && (!pianoEdge.point1 || !pianoEdge.point2)) return;
    draw();
  }, [draw, pianoEdge]);

  // Handle resize and animation updates
  useEffect(() => {
    const hasTrapezoid = pianoEdge.trapezoid && 
      pianoEdge.trapezoid.topRight.x !== 0 && pianoEdge.trapezoid.topRight.y !== 0 &&
      pianoEdge.trapezoid.bottomRight.x !== 0 && pianoEdge.trapezoid.bottomRight.y !== 0 &&
      pianoEdge.trapezoid.bottomLeft.x !== 0 && pianoEdge.trapezoid.bottomLeft.y !== 0;
    
    if (!hasTrapezoid && (!pianoEdge.point1 || !pianoEdge.point2)) return;

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

  const hasTrapezoid = pianoEdge.trapezoid && 
    pianoEdge.trapezoid.topRight.x !== 0 && pianoEdge.trapezoid.topRight.y !== 0 &&
    pianoEdge.trapezoid.bottomRight.x !== 0 && pianoEdge.trapezoid.bottomRight.y !== 0 &&
    pianoEdge.trapezoid.bottomLeft.x !== 0 && pianoEdge.trapezoid.bottomLeft.y !== 0;
  
  const hasTwoPoints = pianoEdge.point1 && pianoEdge.point2;

  if (!hasTrapezoid && !hasTwoPoints) {
    const trapezoidInProgress = pianoEdge.trapezoid && pianoEdge.trapezoid.topLeft;
    const pointsSet = trapezoidInProgress && pianoEdge.trapezoid
      ? (pianoEdge.trapezoid.topRight.x !== 0 && pianoEdge.trapezoid.topRight.y !== 0
          ? (pianoEdge.trapezoid.bottomRight.x !== 0 && pianoEdge.trapezoid.bottomRight.y !== 0
              ? 3
              : 2)
          : 1)
      : 0;

    return (
      <div
        style={{
          padding: "20px",
          textAlign: "center",
          color: "#94a3b8",
          fontSize: "14px",
        }}
      >
        {pointsSet === 0
          ? 'Click "Set Piano Edge" and then click 4 points on the video to draw a trapezoid around the piano.'
          : pointsSet === 1
          ? "Click the second point (top right corner)."
          : pointsSet === 2
          ? "Click the third point (bottom right corner)."
          : "Click the fourth point (bottom left corner) to complete the trapezoid."}
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
