"use client";
import React, { useState, useEffect } from "react";
import { Upload, Music, FileAudio } from "lucide-react";
import ReactAudioPlayer from "react-audio-player";
import MidiViewer from "./MidiViewer";

export default function FileUploadAreas() {
  const [mp3File, setMp3File] = useState(null);
  const [midiFile, setMidiFile] = useState(null);

  const handleDrop = (e) => {
    console.log("hanldedorp");
    e.preventDefault();
    e.stopPropagation();

    const file = e.dataTransfer.files[0];
    const mp3 = file.name.toLowerCase().endsWith("mp3");
    const midi =
      file.name.toLowerCase().endsWith("mid") ||
      file.name.toLowerCase().endsWith("midi");

    if (mp3) setMp3File(file);
    else if (midi) setMidiFile(file);
  };

  useEffect(() => {
    const preventDefaults = (e) => {
      e.preventDefault();
    };

    window.addEventListener("dragover", preventDefaults);
    window.addEventListener("drop", handleDrop);

    return () => {
      window.removeEventListener("dragover", preventDefaults);
      window.removeEventListener("drop", handleDrop);
    };
  }, []);

  const handleFileSelect = (e, type, acceptedExtensions) => {
    const file = e.target.files[0];
    if (
      file &&
      acceptedExtensions.some((ext) => file.name.toLowerCase().endsWith(ext))
    ) {
      if (type === "mp3") setMp3File(file);
      else setMidiFile(file);
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
  }) => (
    <div
      className={`border-2 border-dashed rounded-lg p-8 text-center transition-all cursor-pointer border-gray-300 hover:border-gray-400 bg-white"`}
      onDrop={(e) => handleDrop(e, type, acceptedExtensions)}
      onClick={() => document.getElementById(`${type}-input`).click()}
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
        {(mp3File || midiFile) && (
          <div className="mt-8 p-6 bg-white rounded-lg shadow">
            <h2 className="text-xl font-semibold mb-4">Uploaded Files:</h2>
            <div className="space-y-2">
              {mp3File && (
                <div className="flex items-center justify-between p-3 bg-gray-50 rounded">
                  <span className="font-medium">MP3:</span>
                  <span className="text-sm text-gray-600">{mp3File.name}</span>
                  <ReactAudioPlayer
                    src={URL.createObjectURL(mp3File)}
                    autoPlay
                    controls
                  />
                </div>
              )}
              {midiFile && (
                <div className="flex items-center justify-between p-3 bg-gray-50 rounded">
                  <span className="font-medium">MIDI:</span>
                  <span className="text-sm text-gray-600">{midiFile.name}</span>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
      <MidiViewer midiFile={midiFile} />
    </div>
  );
}
