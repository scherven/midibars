"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

export default function EditPageClient({
  id,
  playbackId,
  children,
}: {
  id: string;
  playbackId: string | null;
  children: React.ReactNode;
}) {
  const router = useRouter();

  useEffect(() => {
    // Check if ready to redirect to align page
    const checkReady = () => {
      try {
        // Check for uploaded flags instead of actual file data
        const mp3Uploaded = localStorage.getItem(`mp3-${id}-uploaded`);
        const midiUploaded = localStorage.getItem(`midi-${id}-uploaded`);
        const cropState = localStorage.getItem("image-editor-state");

        // Check if both files are uploaded and image is cropped
        if (mp3Uploaded && midiUploaded && cropState) {
          const crop = JSON.parse(cropState);
          // Consider cropped if any crop value is non-zero or if crop object exists
          const isCropped = crop && (crop.crop?.n > 0 || crop.crop?.e > 0 || crop.crop?.s > 0 || crop.crop?.w > 0 || Object.keys(crop).length > 0);
          
          if (isCropped) {
            // Redirect to align page
            router.push(`/align/${id}`);
            return;
          }
        }
      } catch (error) {
        console.error("Error checking readiness:", error);
      }
    };

    // Check immediately
    checkReady();

    // Also check periodically (every 2 seconds) in case files are being uploaded
    const interval = setInterval(checkReady, 2000);

    return () => clearInterval(interval);
  }, [id, router]);

  return <>{children}</>;
}

