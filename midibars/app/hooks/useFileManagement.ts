import { useState, useEffect } from "react";

export function useFileManagement(id: string) {
  const [mp3File, setMp3File] = useState<File | null>(null);
  const [midiFile, setMidiFile] = useState<File | null>(null);
  const [playbackId, setPlaybackId] = useState<string | null>(null);
  const [uploading, setUploading] = useState<{ mp3: boolean; midi: boolean }>({
    mp3: false,
    midi: false,
  });

  // Load files from server API
  useEffect(() => {
    async function loadFiles() {
      try {
        const mp3Uploaded = localStorage.getItem(`mp3-${id}-uploaded`);
        const midiUploaded = localStorage.getItem(`midi-${id}-uploaded`);

        if (mp3Uploaded) {
          try {
            const response = await fetch(`/api/files/${id}/mp3`);
            if (response.ok) {
              const blob = await response.blob();
              const file = new File([blob], `audio-${id}.mp3`, {
                type: "audio/mpeg",
              });
              setMp3File(file);
            }
          } catch (err) {
            console.error("Failed to load MP3 from server:", err);
          }
        }

        if (midiUploaded) {
          try {
            const response = await fetch(`/api/files/${id}/midi`);
            if (response.ok) {
              const blob = await response.blob();
              const file = new File([blob], `audio-${id}.mid`, {
                type: "audio/midi",
              });
              setMidiFile(file);
            }
          } catch (err) {
            console.error("Failed to load MIDI from server:", err);
          }
        }
      } catch (error) {
        console.error("Failed to load files:", error);
      }
    }
    loadFiles();
  }, [id]);

  // Fetch playback ID from Mux
  useEffect(() => {
    async function fetchAsset() {
      try {
        const response = await fetch(`/api/mux-asset/${id}`);
        if (response.ok) {
          const data = await response.json();
          if (data.playback_ids?.[0]?.id) {
            setPlaybackId(data.playback_ids[0].id);
          }
        }
      } catch (error) {
        console.error("Failed to fetch asset:", error);
      }
    }
    fetchAsset();
  }, [id]);

  const uploadFile = async (file: File, assetId: string, fileType: "mp3" | "midi") => {
    setUploading((prev) => ({ ...prev, [fileType]: true }));
    try {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("assetId", assetId);
      formData.append("fileType", fileType);

      const response = await fetch("/api/files/upload", {
        method: "POST",
        body: formData,
      });

      if (!response.ok) {
        throw new Error("Upload failed");
      }

      localStorage.setItem(`${fileType}-${assetId}-uploaded`, "true");
      console.log(`${fileType} uploaded successfully`);
    } catch (error) {
      console.error(`Error uploading ${fileType}:`, error);
      alert(`Failed to upload ${fileType} file. Please try again.`);
    } finally {
      setUploading((prev) => ({ ...prev, [fileType]: false }));
    }
  };

  const handleFileSelect = (
    e: React.ChangeEvent<HTMLInputElement>,
    type: "mp3" | "midi",
    acceptedExtensions: string[],
  ) => {
    const file = e.target.files?.[0];
    if (
      file &&
      acceptedExtensions.some((ext: string) => file.name.toLowerCase().endsWith(ext))
    ) {
      if (type === "mp3") {
        setMp3File(file);
        if (id) {
          uploadFile(file, id, "mp3");
        }
      } else {
        setMidiFile(file);
        if (id) {
          uploadFile(file, id, "midi");
        }
      }
    } else {
      alert(`Please select a valid ${acceptedExtensions.join(" or ")} file`);
    }
  };

  return {
    mp3File,
    midiFile,
    playbackId,
    uploading,
    setMp3File,
    setMidiFile,
    handleFileSelect,
    uploadFile,
  };
}

