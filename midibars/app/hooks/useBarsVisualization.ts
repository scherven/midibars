import { useMemo } from "react";
import { MidiFile, TempoMetaEvent } from "@/app/components/MidiReader";
import { ticksToSeconds } from "@/app/utils/midiUtils";
import { calculateNotePositionAllKeys } from "@/app/components/BarsVisualization";

type Note = {
  note: number;
  startTick: number;
  durationTicks: number;
  channel: number;
  velocity: number;
};

export function useBarsVisualization(
  midiData: MidiFile | null,
  notes: Note[],
  tempoEvents: TempoMetaEvent[],
  ticksPerBeat: number,
  alignmentData: any,
  videoTime: number,
  smoothVideoTime: number,
  isVideoPlaying: boolean,
) {
  const currentMidiTime = useMemo(() => {
    if (!alignmentData || !midiData || notes.length === 0) {
      return null;
    }

    const { videoTime: videoStartTime, midiNoteIndex } = alignmentData;
    
    if (midiNoteIndex >= notes.length) {
      return null;
    }
    
    const alignedNote = notes[midiNoteIndex];
    const alignedNoteStartSeconds = ticksToSeconds(
      alignedNote.startTick,
      tempoEvents,
      ticksPerBeat,
    );

    const timeToUse = isVideoPlaying ? smoothVideoTime : videoTime;
    const videoOffset = timeToUse - videoStartTime;
    const midiTimeSeconds = alignedNoteStartSeconds + videoOffset;
    
    return Math.max(0, midiTimeSeconds);
  }, [smoothVideoTime, videoTime, isVideoPlaying, alignmentData, notes, tempoEvents, ticksPerBeat, midiData]);

  const visibleNotes = useMemo(() => {
    if (!midiData || notes.length === 0 || currentMidiTime === null) {
      return [];
    }

    const lookAheadTime = 2;
    const windowEnd = currentMidiTime + lookAheadTime;

    return notes
      .map((note) => {
        const startTime = ticksToSeconds(note.startTick, tempoEvents, ticksPerBeat);
        const duration = ticksToSeconds(note.durationTicks, tempoEvents, ticksPerBeat);
        
        if (startTime > currentMidiTime && startTime <= windowEnd) {
          return {
            note: note.note,
            startTime,
            endTime: startTime + duration,
            channel: note.channel,
            velocity: note.velocity,
          };
        }
        return null;
      })
      .filter((note): note is NonNullable<typeof note> => note !== null);
  }, [notes, tempoEvents, ticksPerBeat, currentMidiTime, midiData]);

  const noteBars = useMemo(() => {
    if (visibleNotes.length === 0 || currentMidiTime === null) {
      return [];
    }

    return visibleNotes.map((noteData) => {
      const notePosition = calculateNotePositionAllKeys(noteData.note);
      const timeUntilStart = noteData.startTime - currentMidiTime;
      const clampedTime = Math.max(0.001, Math.min(2, timeUntilStart));
      const verticalPosition = 50 - (clampedTime / 2) * 50;
      const opacity = 0.7 + (clampedTime / 2) * 0.3;
      const noteDuration = noteData.endTime - noteData.startTime;
      const barHeight = Math.max(20, Math.min(150, noteDuration * 40));

      return {
        ...noteData,
        notePosition,
        verticalPosition,
        opacity,
        barHeight,
        timeUntilStart,
      };
    });
  }, [visibleNotes, currentMidiTime]);

  return {
    currentMidiTime,
    noteBars,
  };
}

