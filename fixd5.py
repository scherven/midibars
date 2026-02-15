"""
fix_d5_lengths.py

Fixes D5 notes in a MIDI file that are missing note-off events (velocity 0)
by setting their duration to match the nearest note that has a proper note-off.

Usage:
    pip install mido
    python fix_d5_lengths.py input.mid output.mid
"""

import mido
import sys
import copy

D5 = 86  # MIDI note number for D5


def get_note_events(track):
    """
    Parse a track into a list of note events with absolute tick times.
    Each event is a dict: { 'type': note_on/note_off, 'note', 'velocity', 'abs_time', 'index' }
    """
    events = []
    abs_time = 0
    for i, msg in enumerate(track):
        abs_time += msg.time
        if msg.type in ('note_on', 'note_off'):
            # note_on with velocity 0 is equivalent to note_off
            event_type = 'note_off' if (msg.type == 'note_off' or msg.velocity == 0) else 'note_on'
            events.append({
                'type': event_type,
                'note': msg.note,
                'velocity': msg.velocity,
                'abs_time': abs_time,
                'index': i
            })
    return events


def pair_notes(events):
    """
    Pair note_on with note_off for each note. Returns a list of paired notes:
        { 'note', 'on_time', 'off_time', 'duration', 'has_off' }
    Notes without a matching note_off get has_off=False and duration=None.
    """
    # Track active note_ons per pitch (stack to handle overlapping)
    active = {}
    paired = []

    for ev in events:
        if ev['type'] == 'note_on':
            active.setdefault(ev['note'], []).append(ev)
        elif ev['type'] == 'note_off':
            stack = active.get(ev['note'], [])
            if stack:
                on_ev = stack.pop(0)  # FIFO: match earliest note_on
                paired.append({
                    'note': ev['note'],
                    'on_time': on_ev['abs_time'],
                    'off_time': ev['abs_time'],
                    'duration': ev['abs_time'] - on_ev['abs_time'],
                    'has_off': True
                })

    # Anything still active has no note_off
    for note, stack in active.items():
        for on_ev in stack:
            paired.append({
                'note': note,
                'on_time': on_ev['abs_time'],
                'off_time': None,
                'duration': None,
                'has_off': False
            })

    paired.sort(key=lambda n: n['on_time'])
    return paired


def find_nearest_duration(paired_notes, target_index):
    """
    Given a target note index in paired_notes, find the nearest note
    (by on_time) that has a valid duration and return that duration.
    """
    target_time = paired_notes[target_index]['on_time']
    best_duration = None
    best_distance = float('inf')

    for i, note in enumerate(paired_notes):
        if i == target_index:
            continue
        if note['has_off'] and note['duration'] is not None and note['duration'] > 0:
            distance = abs(note['on_time'] - target_time)
            if distance < best_distance:
                best_distance = distance
                best_duration = note['duration']

    return best_duration


def fix_track(track):
    """
    For each D5 note missing a note_off, insert a note_off at the duration
    of the nearest properly-paired note. Returns a new track.
    """
    events = get_note_events(track)
    paired = pair_notes(events)

    # Find D5 notes that need fixing
    insertions = []  # list of (abs_time_for_note_off, note_number)
    for i, note in enumerate(paired):
        if note['note'] == D5:# and not note['has_off']:
            duration = find_nearest_duration(paired, i)
            if duration is not None:
                off_time = note['on_time'] + duration
                insertions.append((off_time, D5))
                print(f"  D5 at tick {note['on_time']}: missing note_off -> inserting at tick {off_time} (duration {duration})")
            else:
                print(f"  D5 at tick {note['on_time']}: missing note_off, but no reference duration found. Skipping.")

    if not insertions:
        print("  No D5 notes need fixing in this track.")
        return track

    # Build a new track with insertions
    # Convert existing messages to (abs_time, msg) pairs
    msg_list = []
    abs_time = 0
    for msg in track:
        abs_time += msg.time
        msg_list.append((abs_time, msg.copy()))

    # Add note_off insertions
    for off_abs_time, note in insertions:
        msg_list.append((off_abs_time, mido.Message('note_on', note=note, velocity=0, time=0)))

    # Sort by absolute time (stable sort preserves order for same-time events)
    msg_list.sort(key=lambda x: x[0])

    # Convert back to delta times
    new_track = mido.MidiTrack()
    prev_time = 0
    for abs_t, msg in msg_list:
        msg.time = abs_t - prev_time
        prev_time = abs_t
        new_track.append(msg)

    return new_track


def main():
    if len(sys.argv) < 3:
        print("Usage: python fix_d5_lengths.py input.mid output.mid")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    mid = mido.MidiFile(input_path)
    print(f"Loaded {input_path}: {len(mid.tracks)} track(s), type={mid.type}, ticks_per_beat={mid.ticks_per_beat}")

    new_mid = mido.MidiFile(type=mid.type, ticks_per_beat=mid.ticks_per_beat)

    for i, track in enumerate(mid.tracks):
        print(f"\nTrack {i}: {track.name or '(unnamed)'}")
        new_track = fix_track(track)
        new_mid.tracks.append(new_track)

    new_mid.save(output_path)
    print(f"\nSaved fixed file to {output_path}")


if __name__ == "__main__":
    main()
