import cv2
import subprocess
import sys
import os
import json
import numpy as np
import math
from tqdm import tqdm

from midi_loader import load_midi_notes

# ============================================
# USER CONFIGURATION - Adjust these values
# ============================================

# Path to your video file
VIDEO_PATH = "/Users/simonchervenak/Documents/GitHub/midi/attempt13_copy.mov"

# Path to your MP3 file
MP3_PATH = "/Users/simonchervenak/Documents/GitHub/midi/attempt1213fixed.mp3"

# Path to your MIDI file
MIDI_PATH = "/Users/simonchervenak/Documents/GitHub/midi/attempt1213fixed.mid"

# MP3 start percentage (0 = start from beginning, 60 = start from 60% through the MP3)
# This determines where in the MP3 the video will start syncing
MP3_START_PERCENT = 55.6

# MIDI start percentage (0 = start from beginning, 50 = start from 50% through the MIDI)
# This determines where in the MIDI file the visualization should start
MIDI_START_PERCENT = 56.15

# Output file path
OUTPUT_PATH = "/Users/simonchervenak/Documents/GitHub/midi/output_with_audio.mp4"

# Piano key visualization settings
# Set to None to disable visualization
PIANO_START = [570, 92]  # [x, y] coordinates where piano starts, e.g., [100, 200]
PIANO_END = [560, 1829]  # [x2, y2] coordinates where piano ends, e.g., [1800, 200]
KEY_WIDTHS = [16, 27, 16, 13, 26, 12, 
         25, 18, 13, 24, 12, 25, 
              13, 24, 
              16, 16, 
              24, 14, 22, 20, 
              14, 24, 13,
              24, 14, 23, 17, 17, 22, 17, 22, 18, 
              18, 22, 14, 22, 15, 23, 16, 17, 23, 17, 
              23, 18, 18, 23, 16, 22, 16, 23, 17, 
              18, 23, 18, 22, 19, 19, 23, 16, 23, 
              16, 24, 17, 18, 23, 19, 23, 19, 20, 
              22, 18, 20, 20, 23, 19, 19, 25, 18, 
              24, 19, 19, 26, 15, 26, 15, 26, 20, 28]
  # Array of key widths, e.g., [50, 30, 50, 30, 50, 50, 30, 50, 30, 50, 30, 50]
# ============================================
# Video processing functions
# ============================================

def get_video_info(video_path):
    """Get video information using OpenCV."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = frame_count / fps if fps > 0 else 0
    
    cap.release()
    return {
        'fps': fps,
        'width': width,
        'height': height,
        'frame_count': frame_count,
        'duration': duration
    }

def map_note_to_position(note, key_widths):
    """
    Map MIDI note number (0-127) to position along the piano line.
    Piano keys typically range from A0 (21) to C8 (108) for 88 keys.
    
    Args:
        note: MIDI note number
        key_widths: Array of key widths
    
    Returns:
        Position index in key_widths array, or None if note is out of range
    """
    # Standard 88-key piano: A0 (21) to C8 (108)
    PIANO_START_NOTE = 21
    PIANO_END_NOTE = 108
    
    if note < PIANO_START_NOTE or note > PIANO_END_NOTE:
        return None
    
    # Map note to key index (0-87 for 88 keys)
    key_index = note - PIANO_START_NOTE
    
    if key_index < len(key_widths):
        return key_index
    
    return None

def draw_midi_bars(frame, start_point, end_point, key_widths, notes, current_time, bar_height=50, lead_time=2.0):
    """
    Draw MIDI note bars on the frame with animation.
    Bars spawn 2 seconds before the note, move from right to the line, then decrease in length.
    
    Args:
        frame: OpenCV frame
        start_point: [x, y] where piano starts
        end_point: [x, y] where piano ends
        key_widths: Array of key widths
        notes: List of MIDI note events
        current_time: Current video time in seconds
        bar_height: Height of the bars in pixels (perpendicular to the line)
        lead_time: How many seconds before the note the bar should appear
    """
    x1, y1 = start_point
    x2, y2 = end_point
    
    # Calculate line direction and length
    dx = x2 - x1
    dy = y2 - y1
    line_length = math.sqrt(dx * dx + dy * dy)
    
    if line_length == 0:
        return frame
    
    # Normalize direction vector
    dir_x = dx / line_length
    dir_y = dy / line_length
    
    # Perpendicular vector for bar height
    perp_x = -dir_y
    perp_y = dir_x
    
    # Calculate total width from key_widths
    total_width = sum(key_widths)
    scale_factor = line_length / total_width if total_width > 0 else 1.0
    
    # Determine "right" direction (higher x value)
    # If line goes left to right, "right" is in the direction of the line
    # If line goes right to left, "right" is opposite the line direction
    # We'll use a fixed offset distance for the starting position
    spawn_offset = 500  # pixels to the right of the line
    
    # Use red color for all bars
    color = (0, 0, 255)  # Red in BGR
    
    # Draw notes that are visible (spawning, moving, or playing)
    for note_event in notes:
        note = note_event['note']
        start_time = note_event['start_time']
        end_time = note_event['end_time']
        
        # Check if note should be visible (2 seconds before start to end)
        if current_time < start_time - lead_time or current_time > end_time:
            continue
        
        # Map note to key position
        key_index = map_note_to_position(note, key_widths)
        if key_index is None:
            continue
        
        # Calculate base position along the line for this key
        cumulative_width = sum(key_widths[:key_index]) * scale_factor
        key_width = key_widths[key_index] * scale_factor
        
        # Left edge of bar (always on the line at key start position)
        bar_left_x = x1 + cumulative_width * dir_x
        bar_left_y = y1 + cumulative_width * dir_y
        
        # Calculate note duration to determine height
        note_duration = end_time - start_time
        
        # Calculate height based on note duration
        # Scale duration to height (e.g., 1 second = some pixels, with max height)
        max_height = 200  # Maximum height in pixels
        min_height = 20   # Minimum height in pixels
        duration_scale = 50  # pixels per second
        note_height = min(max_height, max(min_height, note_duration * duration_scale))
        
        # Calculate animation state
        if current_time < start_time:
            # Phase 1: Bar is moving from right (perpendicular to line) towards the line
            # Progress from 0 (far right) to 1 (at line)
            progress = (current_time - (start_time - lead_time)) / lead_time
            progress = max(0, min(1, progress))  # Clamp to [0, 1]
            
            # Perpendicular offset: starts at spawn_offset to the right (positive x), moves to 0
            # As progress increases, offset decreases (bar moves left towards line)
            perpendicular_offset = spawn_offset * (1 - progress)
            
            # Bar has full width and height during approach
            bar_width = key_width
            current_height = note_height
            
        else:
            # Phase 2: Bar is at the line, height shrinking from bottom to top
            # Progress from 0 (full height) to 1 (zero height)
            if note_duration > 0:
                progress = (current_time - start_time) / note_duration
                progress = max(0, min(1, progress))  # Clamp to [0, 1]
            else:
                progress = 1  # Instant note
            
            # Bar maintains full width, height decreases from full to zero
            bar_width = key_width
            current_height = note_height * (1 - progress)
            
            # Bar is at the line (no perpendicular offset)
            perpendicular_offset = 0
        
        # Right edge of bar (left edge + width)
        bar_right_x = bar_left_x + bar_width * dir_x
        bar_right_y = bar_left_y + bar_width * dir_y
        
        # Calculate perpendicular offset in x,y coordinates
        # Offset in positive x direction (to the right of the line)
        offset_x = perpendicular_offset
        offset_y = 0
        
        # Draw a rectangle that spans the bar width and extends perpendicular
        # The bar shrinks from bottom to top, so bottom edge stays on the line
        # Top edge moves down as height decreases
        # All of the bar should be to the right of the line (higher x)
        
        # Determine which perpendicular direction is "to the right" (higher x)
        # perp_x = -dir_y, so we need to check which direction increases x
        # If perp_x > 0, that's to the right; if perp_x < 0, we need the opposite
        if perp_x >= 0:
            # Perpendicular already points to the right
            right_perp_x = perp_x
            right_perp_y = perp_y
        else:
            # Perpendicular points left, use opposite direction
            right_perp_x = -perp_x
            right_perp_y = -perp_y
        
        # Bottom edge is always on the line (offset by perpendicular_offset when sliding in)
        bottom_left_x = bar_left_x + offset_x
        bottom_left_y = bar_left_y + offset_y
        bottom_right_x = bar_right_x + offset_x
        bottom_right_y = bar_right_y + offset_y
        
        # Top edge is offset from bottom by current_height in the "right" direction
        # Shrinks from bottom to top means top edge moves down (towards bottom/line)
        top_left_x = int(bottom_left_x + current_height * right_perp_x)
        top_left_y = int(bottom_left_y + current_height * right_perp_y)
        top_right_x = int(bottom_right_x + current_height * right_perp_x)
        top_right_y = int(bottom_right_y + current_height * right_perp_y)
        
        # Corner 1: bottom left (on line, fixed)
        corner1_x = int(bottom_left_x)
        corner1_y = int(bottom_left_y)
        
        # Corner 2: bottom right (on line, fixed)
        corner2_x = int(bottom_right_x)
        corner2_y = int(bottom_right_y)
        
        # Corner 3: top right (moves down)
        corner3_x = top_right_x
        corner3_y = top_right_y
        
        # Corner 4: top left (moves down)
        corner4_x = top_left_x
        corner4_y = top_left_y
        
        # Draw filled rectangle
        pts = np.array([[corner1_x, corner1_y],
                       [corner2_x, corner2_y],
                       [corner3_x, corner3_y],
                       [corner4_x, corner4_y]], np.int32)
        cv2.fillPoly(frame, [pts], color)
    
    return frame

def blackout_right_of_line(frame, start_point, end_point):
    """
    Black out everything to the right of the piano line (higher x side).
    The line is extrapolated to y=0 and y=frame_height so the blackout covers the full frame.
    
    Args:
        frame: OpenCV frame (numpy array)
        start_point: [x, y] coordinates where piano line starts
        end_point: [x, y] coordinates where piano line ends
    
    Returns:
        Modified frame with the right side blacked out
    """
    if start_point is None or end_point is None:
        return frame
    
    h, w = frame.shape[:2]
    x1, y1 = start_point
    x2, y2 = end_point
    
    # Extrapolate the line to y=0 (top) and y=h (bottom)
    dy = y2 - y1
    dx = x2 - x1
    
    if dy != 0:
        # x at y=0
        top_x = x1 + dx * (0 - y1) / dy
        # x at y=h
        bot_x = x1 + dx * (h - y1) / dy
    else:
        # Horizontal line — just use the same x values
        top_x = x1
        bot_x = x2
    
    # Polygon: extended line top -> extended line bottom -> bottom-right -> top-right
    pts = np.array([
        [int(top_x), 0],
        [int(bot_x), h],
        [w, h],    # bottom-right
        [w, 0],    # top-right
    ], np.int32)
    
    # Fill the polygon with black
    cv2.fillPoly(frame, [pts], (0, 0, 0))
    
    return frame

def get_audio_info(audio_path):
    """Get audio information using ffprobe."""
    cmd = [
        'ffprobe',
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        audio_path
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed: {result.stderr}")
    
    info = json.loads(result.stdout)
    
    # Find audio stream
    audio_stream = None
    for stream in info.get('streams', []):
        if stream.get('codec_type') == 'audio':
            audio_stream = stream
            break
    
    if not audio_stream:
        raise RuntimeError("No audio stream found in file")
    
    duration = float(info.get('format', {}).get('duration', 0))
    
    return {
        'duration': duration,
        'codec': audio_stream.get('codec_name'),
        'sample_rate': audio_stream.get('sample_rate'),
        'channels': audio_stream.get('channels')
    }

def combine_video_audio(video_path, audio_path, output_path, audio_start_percent=0, 
                        piano_start=None, piano_end=None, key_widths=None,
                        midi_path=None, midi_start_percent=0):
    """
    Combine a video file with an MP3 audio file.
    Processes video frame-by-frame to add MIDI bar visualization and blackout the right side of the piano line.
    
    Args:
        video_path: Path to the video file
        audio_path: Path to the MP3 audio file
        output_path: Path where the output video will be saved
        audio_start_percent: Percentage through the MP3 where the video should start (0-100)
        piano_start: [x, y] coordinates where piano starts (None to disable visualization)
        piano_end: [x, y] coordinates where piano ends (None to disable visualization)
        key_widths: Array of key widths for visualization (None to disable)
        midi_path: Path to MIDI file (None to disable MIDI visualization)
        midi_start_percent: Percentage through MIDI where visualization should start
    """
    # Check if files exist
    if not os.path.exists(video_path):
        raise FileNotFoundError(f"Video file not found: {video_path}")
    if not os.path.exists(audio_path):
        raise FileNotFoundError(f"Audio file not found: {audio_path}")
    
    print(f"Getting video information: {video_path}")
    video_info = get_video_info(video_path)
    video_duration = video_info['duration']
    
    print(f"Getting audio information: {audio_path}")
    audio_info = get_audio_info(audio_path)
    audio_duration = audio_info['duration']
    
    print(f"Video duration: {video_duration:.2f} seconds")
    print(f"Audio duration: {audio_duration:.2f} seconds")
    print(f"Video: {video_info['width']}x{video_info['height']} @ {video_info['fps']:.2f} fps")
    
    # Load MIDI notes if MIDI file is provided
    midi_notes = None
    if midi_path is not None:
        try:
            midi_notes, _ = load_midi_notes(midi_path, midi_start_percent)
            print(f"Loaded {len(midi_notes)} MIDI notes for visualization")
        except Exception as e:
            print(f"Warning: Could not load MIDI file: {e}")
    
    # Calculate audio start time
    audio_start_time = audio_duration * (audio_start_percent / 100.0)
    print(f"Starting audio at {audio_start_percent}% through MP3 ({audio_start_time:.2f} seconds)")
    
    # Check audio duration
    remaining_audio_duration = audio_duration - audio_start_time
    if remaining_audio_duration < video_duration:
        print(f"Warning: Remaining audio ({remaining_audio_duration:.2f}s) is shorter than video ({video_duration:.2f}s)")
        print("Audio will end before video.")
    
    # Process video frame by frame
    has_visualization = (piano_start is not None and piano_end is not None and key_widths is not None)
    
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    # Write processed video to temp file using ffmpeg for better quality
    temp_video_path = output_path.replace('.mp4', '_temp_processed.mp4')
    
    # Use ffmpeg to write frames with lossless intermediate codec to preserve quality
    # Using ffv1 (lossless, more efficient than huffyuv) for intermediate file
    ffmpeg_write_cmd = [
        'ffmpeg',
        '-y',
        '-f', 'rawvideo',
        '-vcodec', 'rawvideo',
        '-s', f'{frame_width}x{frame_height}',
        '-pix_fmt', 'bgr24',
        '-r', str(fps),
        '-i', '-',
        '-an',
        '-vcodec', 'libx264rgb',  # RGB variant
        '-preset', 'ultrafast',  # Faster encoding since you don't care about size
        '-crf', '0',  # 0 = lossless
        temp_video_path
    ]
    
    ffmpeg_process = subprocess.Popen(ffmpeg_write_cmd, stdin=subprocess.PIPE)
    
    print(f"Processing {total_frames} frames...")
    frame_count = 0
    
    with tqdm(total=total_frames, desc="Processing frames", unit="frame") as pbar:
        while True:
            ret, frame = cap.read()
            if not ret or frame_count > 50 :
                break
            
            video_time = frame_count / fps
            
            if has_visualization:
                # Black out everything to the right of the piano line
                frame = blackout_right_of_line(frame, piano_start, piano_end)
                
                # Draw MIDI bars
                if midi_notes is not None:
                    frame = draw_midi_bars(frame, piano_start, piano_end, key_widths, midi_notes, video_time)
            
            # Write frame to ffmpeg
            ffmpeg_process.stdin.write(frame.tobytes())
            frame_count += 1
            pbar.update(1)
    
    cap.release()
    ffmpeg_process.stdin.close()
    ffmpeg_process.wait()
    
    if ffmpeg_process.returncode != 0:
        raise RuntimeError(f"ffmpeg video encoding failed with return code {ffmpeg_process.returncode}")
    
    print(f"Processed {frame_count} frames. Combining with audio...")
    
    # Combine processed video with audio using high-quality encoding
    # Re-encode from lossless intermediate with high quality settings
    ffmpeg_cmd = [
        'ffmpeg',
        '-i', temp_video_path,
        '-ss', str(audio_start_time),
        '-i', audio_path,
        '-t', str(video_duration),
        '-map', '0:v:0',
        '-map', '1:a:0',
        '-c:v', 'libx264',
        '-preset', 'slow',  # Slower preset for better quality
        '-crf', '15',  # Very high quality (lower = better)
        '-pix_fmt', 'yuv420p',
        '-color_primaries', 'bt709',  # Preserve color space
        '-color_trc', 'bt709',
        '-colorspace', 'bt709',
        '-c:a', 'aac',
        '-b:a', '192k',
        '-shortest',
        '-y',
        output_path
    ]
    
    print(f"Running ffmpeg to combine video and audio...")
    result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"ffmpeg stderr: {result.stderr}")
        raise RuntimeError(f"ffmpeg failed with return code {result.returncode}")
    
    # Clean up temp file
    if os.path.exists(temp_video_path):
        os.unlink(temp_video_path)
        print("Cleaned up temporary file")
    
    print(f"Done! Output saved to: {output_path}")

if __name__ == "__main__":
    # Use command line arguments if provided, otherwise use configuration variables
    if len(sys.argv) >= 3:
        video_path = sys.argv[1]
        audio_path = sys.argv[2]
        output_path = sys.argv[3] if len(sys.argv) > 3 else OUTPUT_PATH
        start_percent = float(sys.argv[4]) if len(sys.argv) > 4 else MP3_START_PERCENT
    else:
        video_path = VIDEO_PATH
        audio_path = MP3_PATH
        output_path = OUTPUT_PATH
        start_percent = MP3_START_PERCENT
    
    try:
        combine_video_audio(
            video_path, audio_path, output_path, start_percent,
            piano_start=PIANO_START,
            piano_end=PIANO_END,
            key_widths=KEY_WIDTHS,
            midi_path=MIDI_PATH,
            midi_start_percent=MIDI_START_PERCENT
        )
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
