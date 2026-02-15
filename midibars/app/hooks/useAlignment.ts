import { useState, useEffect } from "react";
import { MidiFile } from "@/app/components/MidiReader";

type Note = {
  note: number;
  startTick: number;
  durationTicks: number;
  channel: number;
  velocity: number;
};

export function useAlignment(
  id: string,
  midiData: MidiFile | null,
  notes: Note[],
  audioRef: React.RefObject<HTMLAudioElement | null>,
) {
  const [alignmentStep, setAlignmentStep] = useState<"video" | "midi" | "mp3" | "aligned">("video");
  const [selectedVideoTime, setSelectedVideoTime] = useState<number | null>(null);
  const [selectedMidiNoteIndex, setSelectedMidiNoteIndex] = useState<number | null>(null);
  const [selectedMp3Time, setSelectedMp3Time] = useState<number | null>(null);
  const [midiPlayheadTime, setMidiPlayheadTime] = useState<number>(0);
  const [mp3PlayheadTime, setMp3PlayheadTime] = useState<number>(0);
  const [alignmentData, setAlignmentData] = useState<any>(null);

  // Load alignment data
  useEffect(() => {
    const saved = localStorage.getItem(`alignment-${id}`);
    if (saved) {
      try {
        const data = JSON.parse(saved);
        setSelectedVideoTime(data.videoTime);
        setSelectedMidiNoteIndex(data.midiNoteIndex);
        setSelectedMp3Time(data.mp3Time);
        setAlignmentData(data);
        setAlignmentStep("aligned");
      } catch (e) {
        console.error("Failed to load alignment data:", e);
      }
    }
  }, [id]);

  // Save alignment data
  useEffect(() => {
    if (
      selectedVideoTime !== null &&
      selectedMidiNoteIndex !== null &&
      selectedMp3Time !== null &&
      notes.length > 0
    ) {
      setAlignmentStep("aligned");
      const selectedNote = notes[selectedMidiNoteIndex];
      
      let mp3TimeSeconds = 0;
      if (audioRef.current && audioRef.current.duration) {
        mp3TimeSeconds = selectedMp3Time * audioRef.current.duration;
      }
      
      const alignmentData = {
        videoTime: selectedVideoTime,
        midiNoteIndex: selectedMidiNoteIndex,
        midiNoteTick: selectedNote.startTick,
        mp3Time: selectedMp3Time,
        mp3TimeSeconds: mp3TimeSeconds,
        timestamp: Date.now(),
      };

      localStorage.setItem(`alignment-${id}`, JSON.stringify(alignmentData));
      setAlignmentData(alignmentData);
    }
  }, [selectedVideoTime, selectedMidiNoteIndex, selectedMp3Time, notes.length, id, audioRef]);

  const findNextMidiNote = (time: number) => {
    if (!midiData || notes.length === 0) return time;
    const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
    const maxTick = Math.max(
      ...notes.map((n) => n.startTick + n.durationTicks),
    );
    const totalTicks = maxTick - firstNoteTick;
    if (totalTicks === 0) return time;

    const currentTick = firstNoteTick + time * totalTicks;
    const nextNote = notes.find((n) => n.startTick >= currentTick);
    if (!nextNote) {
      const lastNote = notes[notes.length - 1];
      return (lastNote.startTick - firstNoteTick) / totalTicks;
    }

    const noteTickRatio = (nextNote.startTick - firstNoteTick) / totalTicks;
    return noteTickRatio;
  };

  const handleMidiPlayheadDrag = (time: number) => {
    const snapped = findNextMidiNote(time);
    setMidiPlayheadTime(snapped);
    
    if (notes.length > 0) {
      const firstNoteTick = Math.min(...notes.map((n) => n.startTick));
      const maxTick = Math.max(
        ...notes.map((n) => n.startTick + n.durationTicks),
      );
      const totalTicks = maxTick - firstNoteTick;
      if (totalTicks > 0) {
        const currentTick = firstNoteTick + snapped * totalTicks;
        const noteIndex = notes.findIndex((n) => n.startTick >= currentTick);
        if (noteIndex !== -1) {
          setSelectedMidiNoteIndex(noteIndex);
        }
      }
    }
  };

  const handleMp3TimeClick = (time: number) => {
    setSelectedMp3Time(time);
    setMp3PlayheadTime(time);
    
    if (selectedVideoTime !== null && selectedMidiNoteIndex !== null) {
      setAlignmentStep("aligned");
    }
  };

  const handleMp3ArrowKey = (direction: "left" | "right") => {
    if (selectedMp3Time === null) return;
    
    const audioDuration = audioRef.current?.duration || 0;
    if (audioDuration === 0) return;
    
    const step = 0.1 / audioDuration;
    const newTime = direction === "left" 
      ? Math.max(0, selectedMp3Time - step)
      : Math.min(1, selectedMp3Time + step);
    
    setSelectedMp3Time(newTime);
    setMp3PlayheadTime(newTime);
  };

  const handleVideoTimeSelect = (time: number) => {
    setSelectedVideoTime(time);
  };

  return {
    alignmentStep,
    selectedVideoTime,
    selectedMidiNoteIndex,
    selectedMp3Time,
    midiPlayheadTime,
    mp3PlayheadTime,
    alignmentData,
    handleMidiPlayheadDrag,
    handleMp3TimeClick,
    handleMp3ArrowKey,
    handleVideoTimeSelect,
  };
}

