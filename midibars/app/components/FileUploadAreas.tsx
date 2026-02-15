"use client";
import React, { useState, useEffect } from "react";
import { Upload, Music, FileAudio } from "lucide-react";
import MidiViewer from "./MidiViewer";

export default function FileUploadAreas({ id }: { id?: string }) {
  const [mp3File, setMp3File] = useState<File | null>(null);
  const [midiFile, setMidiFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState<{ mp3: boolean; midi: boolean }>({
    mp3: false,
    midi: false,
  });

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

      // Store just a flag in localStorage that files are uploaded
      localStorage.setItem(`${fileType}-${assetId}-uploaded`, "true");
      console.log(`${fileType} uploaded successfully`);
    } catch (error) {
      console.error(`Error uploading ${fileType}:`, error);
      alert(`Failed to upload ${fileType} file. Please try again.`);
    } finally {
      setUploading((prev) => ({ ...prev, [fileType]: false }));
    }
  };

  const handleDrop = (e: DragEvent) => {
    e.preventDefault();
    e.stopPropagation();

    const file = e.dataTransfer?.files[0];
    if (!file) return;
    const mp3 = file.name.toLowerCase().endsWith("mp3");
    const midi =
      file.name.toLowerCase().endsWith("mid") ||
      file.name.toLowerCase().endsWith("midi");

    if (mp3) {
      setMp3File(file);
      // Upload to server
      if (id) {
        uploadFile(file, id, "mp3");
      }
    } else if (midi) {
      setMidiFile(file);
      // Upload to server
      if (id) {
        uploadFile(file, id, "midi");
      }
    }
  };

  useEffect(() => {
    const preventDefaults = (e: DragEvent) => {
      e.preventDefault();
    };

    window.addEventListener("dragover", preventDefaults);
    window.addEventListener("drop", handleDrop);

    return () => {
      window.removeEventListener("dragover", preventDefaults);
      window.removeEventListener("drop", handleDrop);
    };
  }, []);

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
        // Upload to server
        if (id) {
          uploadFile(file, id, "mp3");
        }
      } else {
        setMidiFile(file);
        // Upload to server
        if (id) {
          uploadFile(file, id, "midi");
        }
      }
    } else {
      alert(`Please select a valid ${acceptedExtensions.join(" or ")} file`);
    }
  };

  const FileUploadBox = ({
    type,
    file,
    icon: Icon,
    acceptedFormats,
    acceptedExtensions,
    label,
  }: {
    type: "mp3" | "midi";
    file: File | null;
    icon: React.ComponentType<{ className?: string; size?: number }>;
    acceptedFormats: string;
    acceptedExtensions: string[];
    label: string;
  }) => {
    const handleBoxDrop = (e: React.DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      const file = e.dataTransfer.files[0];
      if (file) {
        const matches = acceptedExtensions.some((ext: string) =>
          file.name.toLowerCase().endsWith(ext)
        );
        if (matches) {
          if (type === "mp3") {
            setMp3File(file);
            if (id) uploadFile(file, id, "mp3");
          } else {
            setMidiFile(file);
            if (id) uploadFile(file, id, "midi");
          }
        }
      }
    };

    return (
      <div
        className={`border-2 border-dashed rounded-lg p-8 text-center transition-all cursor-pointer border-gray-300 hover:border-gray-400 bg-white"`}
        onDrop={handleBoxDrop}
        onDragOver={(e) => e.preventDefault()}
        onClick={() => document.getElementById(`${type}-input`)?.click()}
      >
      <input
        id={`${type}-input`}
        type="file"
        accept={acceptedFormats}
        onChange={(e) => handleFileSelect(e, type, acceptedExtensions)}
        className="hidden"
      />

      <Icon className="mx-auto mb-4 text-gray-400" size={48} />

      <h3 className="text-lg font-semibold mb-2">{label}</h3>

      {file ? (
        <div className="mt-4">
          <p className="text-green-600 font-medium">Selected:</p>
          <p className="text-sm text-gray-700 mt-1">{file.name}</p>
          <p className="text-xs text-gray-500 mt-1">
            {(file.size / 1024 / 1024).toFixed(2)} MB
          </p>
          {uploading[type as keyof typeof uploading] && (
            <p className="text-xs text-blue-500 mt-1">Uploading...</p>
          )}
        </div>
      ) : (
        <div>
          <p className="text-gray-600 mb-2">Drag and drop your file here</p>
          <p className="text-sm text-gray-500">or click to browse</p>
          <p className="text-xs text-gray-400 mt-2">
            Accepts {acceptedExtensions.join(", ")} files
          </p>
        </div>
      )}
      </div>
    );
  };

  return (
    <div className="w-full">
      <div className="max-w-4xl mx-auto">
        <div className="grid md:grid-cols-2 gap-6">
          <FileUploadBox
            type="mp3"
            file={mp3File}
            icon={FileAudio}
            acceptedFormats=".mp3,audio/mpeg"
            acceptedExtensions={[".mp3"]}
            label="Upload MP3 File"
          />

          <FileUploadBox
            type="midi"
            file={midiFile}
            icon={Music}
            acceptedFormats=".mid,.midi,audio/midi"
            acceptedExtensions={[".mid", ".midi"]}
            label="Upload MIDI File"
          />
        </div>
      </div>
      <MidiViewer midiFile={midiFile} mp3File={mp3File} />
    </div>
  );
}
