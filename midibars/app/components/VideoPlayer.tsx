"use client";

import { useState, useRef, useEffect } from "react";
import Image from "next/image";

interface MuxPlayerComponentProps {
  playbackId: string;
}

export default function VideoThumbnailEditor({
  playbackId,
}: MuxPlayerComponentProps) {
  const [scale, setScale] = useState(1);
  const [rotation, setRotation] = useState(0);
  const [size, setSize] = useState({ x: 0, y: 0, width: 400, height: 400 });
  const [crop, setCrop] = useState({ n: 0, e: 0, s: 0, w: 0 });
  const [isDragging, setIsDragging] = useState("");
  const [currentCorner, setCurrentCorner] = useState("");
  const [currentSide, setCurrentSide] = useState("");
  const [rotateStart, setRotateStart] = useState({ angle: 0, x: 0, y: 0 });
  const [hasLoadedState, setHasLoadedState] = useState(false);
  const containerRef = useRef<HTMLDivElement | null>(null);

  const imageUrl = `https://image.mux.com/${playbackId}/thumbnail.jpg?time=${0}`;

  const handleImageLoad = (e: React.SyntheticEvent<HTMLImageElement>) => {
    const img = e.currentTarget;
    setSize((prev) => ({
      x: prev.x,
      y: prev.y,
      width: img.naturalWidth,
      height: img.naturalHeight,
    }));
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (isDragging === "rotate") {
      if (!containerRef.current) return;
      const rect = containerRef.current.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      const currentAngle =
        Math.atan2(e.clientY - centerY, e.clientX - centerX) * (180 / Math.PI);
      const newRotation = currentAngle - rotateStart.angle;
      setRotation(newRotation);
    } else if (isDragging === "move") {
      setSize((prev) => ({
        ...prev,
        x: prev.x + e.movementX,
        y: prev.y + e.movementY,
      }));
    } else if (isDragging === "corner" && currentCorner) {
      setSize((prev) => {
        const newSize = { ...prev };
        const rad = (rotation * Math.PI) / 180;
        const cos = Math.cos(rad);
        const sin = Math.sin(rad);
        
        // Rotate movement to match image rotation
        const rotatedX = e.movementX * cos + e.movementY * sin;
        const rotatedY = -e.movementX * sin + e.movementY * cos;
        
        if (currentCorner.includes("e")) {
          newSize.width = Math.max(50, prev.width + rotatedX);
        }
        if (currentCorner.includes("w")) {
          const delta = -rotatedX;
          newSize.width = Math.max(50, prev.width + delta);
          newSize.x = prev.x - delta;
        }
        if (currentCorner.includes("s")) {
          newSize.height = Math.max(50, prev.height + rotatedY);
        }
        if (currentCorner.includes("n")) {
          const delta = -rotatedY;
          newSize.height = Math.max(50, prev.height + delta);
          newSize.y = prev.y - delta;
        }
        return newSize;
      });
    } else if (isDragging === "side" && currentSide) {
      const rad = (rotation * Math.PI) / 180;
      const cos = Math.cos(rad);
      const sin = Math.sin(rad);

      const rotatedX = e.movementX * cos + e.movementY * sin;
      const rotatedY = -e.movementX * sin + e.movementY * cos;

      setCrop((prev) => {
        const newCrop = { ...prev };

        if (currentSide === "n") {
          newCrop.n = Math.max(
            0,
            Math.min(size.height - prev.s, prev.n + rotatedY),
          );
        } else if (currentSide === "s") {
          newCrop.s = Math.max(
            0,
            Math.min(size.height - prev.n, prev.s - rotatedY),
          );
        } else if (currentSide === "w") {
          newCrop.w = Math.max(
            0,
            Math.min(size.width - prev.e, prev.w + rotatedX),
          );
        } else if (currentSide === "e") {
          newCrop.e = Math.max(
            0,
            Math.min(size.width - prev.w, prev.e - rotatedX),
          );
        }

        return newCrop;
      });
    }
  };

  const handleMouseUp = (e: React.MouseEvent) => {
    setIsDragging("");
    setCurrentCorner("");
    setCurrentSide("");
  };

  const handlePan = (action: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setIsDragging("move");
  };

  const handleResize = (corner: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setCurrentCorner(corner);
    setIsDragging("corner");
  };

  const handleCrop = (side: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setCurrentSide(side);
    setIsDragging("side");
  };

  const handleRotate = (action: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const startAngle =
      Math.atan2(e.clientY - centerY, e.clientX - centerX) * (180 / Math.PI);
    setRotateStart({ angle: startAngle - rotation, x: centerX, y: centerY });
    setIsDragging("rotate");
  };

  useEffect(() => {
    const loadState = async () => {
      try {
        const result = window.localStorage.getItem("image-editor-state");
        if (result) {
          const savedState = JSON.parse(result);
          setScale(savedState.scale ?? 1);
          setRotation(savedState.rotation ?? 0);
          setSize(savedState.size ?? { x: 0, y: 0, width: 400, height: 400 });
          setCrop(savedState.crop ?? { n: 0, e: 0, s: 0, w: 0 });
          setHasLoadedState(true);
        }
      } catch (error) {
        console.log("No saved state found");
        setHasLoadedState(true);
      }
    };
    loadState();
  }, []);

  useEffect(() => {
    const saveState = async () => {
      try {
        window.localStorage.setItem(
          "image-editor-state",
          JSON.stringify({
            scale,
            rotation,
            size,
            crop,
          }),
        );
      } catch (error) {
        console.error("Failed to save state:", error);
      }
    };
    saveState();
  }, [scale, rotation, size, crop]);
  return (
    <div 
      onMouseMove={(e) => {
        handleMouseMove(e);
      }} 
      onMouseUp={handleMouseUp}
    >
      <div
        ref={containerRef}
        style={{
          transform: `scale(${scale})`,
        }}
      >
        <div
          style={{
            position: "relative",
            width: `${size.width}px`,
            height: `${size.height}px`,
            transform: `translate(${size.x}px, ${size.y}px) rotate(${rotation}deg)`,
            transformOrigin: "center",
          }}
        >
          <Image
            src={imageUrl}
            alt="Editor Background"
            width={size.width}
            height={size.height}
            draggable={false}
            style={{
              userSelect: "none",
              opacity: isDragging == "side" ? 0.4 : 0.0,
              position: "absolute",
              top: 0,
              left: 0,
            }}
          />

          <Image
            src={imageUrl}
            alt="Editor"
            width={size.width}
            height={size.height}
            draggable={false}
            onLoad={handleImageLoad}
            style={{
              userSelect: "none",
              clipPath: `inset(${crop.n}px ${crop.e}px ${crop.s}px ${crop.w}px)`,
            }}
          />

          <div
            className="absolute border-2 border-blue-500 cursor-move"
            style={{
              left: `${crop.w}px`,
              top: `${crop.n}px`,
              width: `${size.width - crop.w - crop.e}px`,
              height: `${size.height - crop.n - crop.s}px`,
              pointerEvents: isDragging ? "none" : "auto",
            }}
            onMouseDown={(e) => handlePan("move", e)}
          >
            <div
              className="absolute left-1/2 -translate-x-1/2 cursor-grab active:cursor-grabbing"
              style={{ top: "-40px" }}
              onMouseDown={(e) => handleRotate("rotate", e)}
            >
              <div className="flex flex-col items-center">
                <div className="w-8 h-8 bg-green-600 border-2 border-white rounded-full flex items-center justify-center hover:scale-110 transition shadow-lg">
                  <svg
                    className="w-5 h-5 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                    />
                  </svg>
                </div>
                <div className="w-0.5 h-6 bg-green-600"></div>
              </div>
            </div>

            {["nw", "ne", "sw", "se"].map((corner) => (
              <div
                key={corner}
                className="absolute w-4 h-4 bg-blue-600 border-2 border-white rounded-full cursor-pointer hover:scale-125 transition"
                style={{
                  top: corner.includes("n") ? "-8px" : "auto",
                  bottom: corner.includes("s") ? "-8px" : "auto",
                  left: corner.includes("w") ? "-8px" : "auto",
                  right: corner.includes("e") ? "-8px" : "auto",
                  cursor:
                    corner === "nw"
                      ? "nwse-resize"
                      : corner === "ne"
                        ? "nesw-resize"
                        : corner === "sw"
                          ? "nesw-resize"
                          : "nwse-resize",
                }}
                onMouseDown={(e) => handleResize(corner, e)}
              />
            ))}

            {["n", "e", "s", "w"].map((side) => (
              <div
                key={side}
                className="absolute bg-blue-600 border-2 border-white cursor-pointer hover:bg-blue-700 transition"
                style={{
                  top: side === "n" ? "-4px" : side === "s" ? "auto" : "50%",
                  bottom: side === "s" ? "-4px" : "auto",
                  left: side === "w" ? "-4px" : side === "e" ? "auto" : "50%",
                  right: side === "e" ? "-4px" : "auto",
                  width: side === "n" || side === "s" ? "40px" : "8px",
                  height: side === "e" || side === "w" ? "40px" : "8px",
                  transform:
                    side === "n" || side === "s"
                      ? "translateX(-50%)"
                      : "translateY(-50%)",
                  cursor:
                    side === "n" || side === "s" ? "ns-resize" : "ew-resize",
                }}
                onMouseDown={(e) => handleCrop(side, e)}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
