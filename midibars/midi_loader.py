"""
Functions for loading and processing MIDI files.
"""

import os
import mido


def load_midi_notes(midi_path, midi_start_percent=0):
    """
    Load MIDI file and extract note events.
    
    Args:
        midi_path: Path to MIDI file
        midi_start_percent: Percentage through MIDI where visualization should start
    
    Returns:
        Tuple of (list of note events, total_duration)
        Note events have: note, start_time, end_time, velocity, channel
    """
    if not os.path.exists(midi_path):
        raise FileNotFoundError(f"MIDI file not found: {midi_path}")
    
    print(f"Loading MIDI file: {midi_path}")
    mid = mido.MidiFile(midi_path)
    
    # Convert ticks to seconds with tempo handling
    notes = []
    active_notes = {}  # Track note-on events waiting for note-off
    
    ticks_per_beat = mid.ticks_per_beat
    tempo = 500000  # Default tempo (microseconds per beat)
    
    # First pass: collect all tempo events and note events
    tempo_events = []  # (tick, tempo)
    note_events = []  # (tick, type, channel, note, velocity)
    
    for track in mid.tracks:
        tick = 0
        for msg in track:
            tick += msg.time
            
            if msg.type == 'set_tempo':
                tempo_events.append((tick, msg.tempo))
            elif msg.type == 'note_on' and msg.velocity > 0:
                note_events.append((tick, 'note_on', msg.channel, msg.note, msg.velocity))
            elif msg.type == 'note_off' or (msg.type == 'note_on' and msg.velocity == 0):
                note_events.append((tick, 'note_off', msg.channel, msg.note, 0))
    
    # Sort tempo events
    tempo_events.sort(key=lambda x: x[0])
    
    # Convert ticks to seconds for note events
    def tick_to_second(tick):
        current_tick = 0
        current_time = 0.0
        current_tempo = 500000
        
        for tempo_tick, tempo_value in tempo_events:
            if tick <= tempo_tick:
                # Calculate time for remaining ticks
                ticks_in_segment = tick - current_tick
                current_time += mido.tick2second(ticks_in_segment, ticks_per_beat, current_tempo)
                return current_time
            
            # Calculate time for this tempo segment
            ticks_in_segment = tempo_tick - current_tick
            current_time += mido.tick2second(ticks_in_segment, ticks_per_beat, current_tempo)
            current_tick = tempo_tick
            current_tempo = tempo_value
        
        # Handle remaining ticks after last tempo event
        ticks_in_segment = tick - current_tick
        current_time += mido.tick2second(ticks_in_segment, ticks_per_beat, current_tempo)
        return current_time
    
    # Process note events
    for tick, event_type, channel, note, velocity in note_events:
        time = tick_to_second(tick)
        
        if event_type == 'note_on':
            key = (channel, note)
            active_notes[key] = {
                'start_time': time,
                'velocity': velocity,
                'note': note
            }
        elif event_type == 'note_off':
            key = (channel, note)
            if key in active_notes:
                note_data = active_notes[key]
                notes.append({
                    'note': note_data['note'],
                    'start_time': note_data['start_time'],
                    'end_time': time,
                    'velocity': note_data['velocity'],
                    'channel': channel
                })
                del active_notes[key]
    
    # Get total duration
    max_tick = max([tick for tick, _, _, _, _ in note_events] + [tick for tick, _ in tempo_events] + [0])
    total_duration = tick_to_second(max_tick)
    
    # Sort notes by start time
    notes.sort(key=lambda x: x['start_time'])
    
    # Apply MIDI start percentage offset
    if midi_start_percent > 0:
        start_offset = total_duration * (midi_start_percent / 100.0)
        notes = [
            {
                'note': n['note'],
                'start_time': n['start_time'] - start_offset,
                'end_time': n['end_time'] - start_offset,
                'velocity': n['velocity'],
                'channel': n['channel']
            }
            for n in notes
            if n['end_time'] > start_offset  # Only keep notes that haven't ended
        ]
    
    print(f"Loaded {len(notes)} MIDI notes")
    return notes, total_duration

