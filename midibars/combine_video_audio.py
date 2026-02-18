import cv2
import subprocess
import sys
import os
import numpy as np
import math
from tqdm import tqdm

from midi_loader import load_midi_notes
from particle_system import BubblesParticleSystem, BUBBLES_AVAILABLE
from frame_effects import (
    draw_midi_bars,
    blackout_right_of_line,
    ENABLE_GLOW,
    GLOW_INTENSITY,
    GLOW_BLUR_RADIUS,
    BAR_CORNER_RADIUS,
    ENABLE_PARTICLES,
    LONG_NOTE_THRESHOLD
)

# ============================================
# USER CONFIGURATION - Adjust these values
# ============================================

# Path to your video file
VIDEO_PATH = "/Users/simonchervenak/Documents/GitHub/midi/IMG_2131.mov"

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

# Visual effects settings (imported from frame_effects and particle_system)
# Override these if needed:
# from frame_effects import ENABLE_GLOW, GLOW_INTENSITY, GLOW_BLUR_RADIUS, BAR_CORNER_RADIUS, ENABLE_PARTICLES, LONG_NOTE_THRESHOLD
# from particle_system import PARTICLE_CONFIG_DIR, DEFAULT_PARTICLE_CONFIG, TORNADO_PARTICLE_CONFIG, POP_PARTICLE_CONFIG, USE_RANDOM_COLORS, RANDOM_COLOR_SATURATION, RANDOM_COLOR_BRIGHTNESS, PARTICLE_SIZE

# Particle effect configuration paths
PARTICLE_CONFIG_DIR = "particle_configs"  # Directory containing JSON particle configs
DEFAULT_PARTICLE_CONFIG = "default.json"  # Default particle config for short notes
TORNADO_PARTICLE_CONFIG = "tornado.json"  # Tornado effect for long notes
POP_PARTICLE_CONFIG = "pop.json"  # Pop effect when notes end

# Random color settings
USE_RANDOM_COLORS = True  # Use random colors for particles
RANDOM_COLOR_SATURATION = 0.8  # Saturation for random colors (0.0 to 1.0)
RANDOM_COLOR_BRIGHTNESS = 0.9  # Brightness for random colors (0.0 to 1.0)

# Particle size (for bubbles renderer base_size)
PARTICLE_SIZE = 3  # Base particle size in pixels
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

# ============================================
# Particle Configuration Loading
# ============================================

# Particle and frame effect functions have been moved to separate modules:
# - particle_system.py: BubblesParticleSystem class and particle-related functions
# - frame_effects.py: draw_midi_bars, apply_glow_effect, draw_rounded_polygon, etc.

# ============================================
# Video processing functions
# ============================================

def get_audio_info(audio_path):
    """Get audio information using ffprobe."""
    import json
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

def prepare_frame_transformations(piano_start, piano_end, key_widths, midi_notes,
                                   original_width, original_height):
    """
    Prepare all transformation parameters needed for frame processing.
    
    Args:
        piano_start: [x, y] coordinates where piano starts (None to disable visualization)
        piano_end: [x, y] coordinates where piano ends (None to disable visualization)
        key_widths: Array of key widths for visualization (None to disable)
        midi_notes: List of MIDI note events (None to disable MIDI visualization)
        original_width: Original video frame width
        original_height: Original video frame height
    
    Returns:
        dict with transformation parameters:
            - rotation_matrix: OpenCV rotation matrix (None if no rotation)
            - output_width: Output frame width after transformations
            - output_height: Output frame height after transformations
            - piano_start: Transformed piano start coordinates
            - piano_end: Transformed piano end coordinates
            - has_visualization: Whether visualization is enabled
            - midi_notes: MIDI notes (passed through)
            - key_widths: Key widths (passed through)
    """
    has_visualization = (piano_start is not None and piano_end is not None and key_widths is not None)
    
    if not has_visualization:
        return {
            'rotation_matrix': None,
            'output_width': original_width,
            'output_height': original_height,
            'piano_start': None,
            'piano_end': None,
            'has_visualization': False,
            'midi_notes': None,
            'key_widths': None,
            'midi_bar_params': None
        }
    
    # Calculate rotation to make piano line vertical
    x1, y1 = piano_start
    x2, y2 = piano_end
    dx = x2 - x1
    dy = y2 - y1
    rotation_angle = -math.atan2(dx, dy) * 180 / math.pi
    
    # Calculate rotation matrix and transform piano coordinates
    if abs(rotation_angle) > 0.01:  # Only rotate if angle is significant
        center_x = original_width / 2
        center_y = original_height / 2
        rotation_matrix = cv2.getRotationMatrix2D((center_x, center_y), rotation_angle, 1.0)
        
        # Calculate new frame dimensions after rotation
        cos_angle = abs(rotation_matrix[0, 0])
        sin_angle = abs(rotation_matrix[0, 1])
        new_width = int(original_height * sin_angle + original_width * cos_angle)
        new_height = int(original_height * cos_angle + original_width * sin_angle)
        
        # Adjust rotation matrix to account for new dimensions
        rotation_matrix[0, 2] += (new_width / 2) - center_x
        rotation_matrix[1, 2] += (new_height / 2) - center_y
        
        # Transform piano coordinates
        piano_start_pt = np.array([[piano_start]], dtype=np.float32)
        piano_end_pt = np.array([[piano_end]], dtype=np.float32)
        rotated_piano_start_pt = cv2.transform(piano_start_pt, rotation_matrix)[0][0]
        rotated_piano_end_pt = cv2.transform(piano_end_pt, rotation_matrix)[0][0]
        transformed_piano_start = [int(rotated_piano_start_pt[0]), int(rotated_piano_start_pt[1])]
        transformed_piano_end = [int(rotated_piano_end_pt[0]), int(rotated_piano_end_pt[1])]
        
        output_width = new_width
        output_height = new_height
    else:
        rotation_matrix = None
        transformed_piano_start = piano_start
        transformed_piano_end = piano_end
        output_width = original_width
        output_height = original_height
    
    # Pre-calculate MIDI bar parameters for efficiency
    midi_bar_params = None
    if midi_notes is not None:
        # Calculate line direction and length
        tx1, ty1 = transformed_piano_start
        tx2, ty2 = transformed_piano_end
        tdx = tx2 - tx1
        tdy = ty2 - ty1
        line_length = math.sqrt(tdx * tdx + tdy * tdy)
        
        if line_length > 0:
            # Normalize direction vector
            dir_x = tdx / line_length
            dir_y = tdy / line_length
            
            # Perpendicular vector for bar height
            perp_x = -dir_y
            perp_y = dir_x
            
            # Determine "right" direction (higher x value)
            if perp_x >= 0:
                right_perp_x = perp_x
                right_perp_y = perp_y
            else:
                right_perp_x = -perp_x
                right_perp_y = -perp_y
            
            # Calculate total width and scale factor
            total_width = sum(key_widths)
            scale_factor = line_length / total_width if total_width > 0 else 1.0
            
            # Pre-calculate cumulative widths for each key (for fast lookup)
            cumulative_widths = np.cumsum([0] + list(key_widths)) * scale_factor
            key_widths_scaled = np.array(key_widths) * scale_factor
            
            midi_bar_params = {
                'x1': tx1,
                'y1': ty1,
                'dir_x': dir_x,
                'dir_y': dir_y,
                'right_perp_x': right_perp_x,
                'right_perp_y': right_perp_y,
                'cumulative_widths': cumulative_widths,
                'key_widths_scaled': key_widths_scaled,
                'line_length': line_length
            }
    
    return {
        'rotation_matrix': rotation_matrix,
        'output_width': output_width,
        'output_height': output_height,
        'piano_start': transformed_piano_start,
        'piano_end': transformed_piano_end,
        'has_visualization': True,
        'midi_notes': midi_notes,
        'key_widths': key_widths,
        'midi_bar_params': midi_bar_params
    }

def transform_frame(frame, video_time, transform_params, output_width, output_height,
                   particle_system=None, previous_active_notes=None, fps=30.0):
    """
    Apply all transformations to a single frame.
    
    Args:
        frame: OpenCV frame (numpy array)
        video_time: Current video time in seconds
        transform_params: Dictionary from prepare_frame_transformations()
        output_width: Final output width (after cropping)
        output_height: Final output height (after cropping)
        particle_system: BubblesParticleSystem instance for particle effects (optional)
        previous_active_notes: Set of active notes from previous frame (optional)
        fps: Frames per second for particle system updates
    
    Returns:
        Tuple of (transformed frame, current_active_notes)
    """
    # Rotate frame if needed
    rotation_matrix = transform_params.get('rotation_matrix')
    if rotation_matrix is not None:
        frame = cv2.warpAffine(
            frame, 
            rotation_matrix, 
            (transform_params['output_width'], transform_params['output_height']), 
            flags=cv2.INTER_LINEAR, 
            borderMode=cv2.BORDER_CONSTANT, 
            borderValue=(0, 0, 0)
        )
    
    # Apply visualization if enabled
    current_active_notes = set()
    if transform_params['has_visualization']:
        frame = blackout_right_of_line(
            frame, 
            transform_params['piano_start'], 
            transform_params['piano_end']
        )
        if transform_params['midi_notes'] is not None:
            frame, current_active_notes = draw_midi_bars(
                frame, 
                transform_params['midi_bar_params'], 
                transform_params['midi_notes'], 
                video_time,
                particle_system=particle_system,
                previous_active_notes=previous_active_notes,
                fps=fps
            )
    
    # Crop to final output dimensions (using view, not copy)
    frame = frame[:output_height, :output_width]
    
    # Rotate 90 degrees counterclockwise
    h, w = frame.shape[:2]
    center_x, center_y = w / 2, h / 2
    # 90° CCW rotation matrix
    rot_90_ccw = cv2.getRotationMatrix2D((center_x, center_y), 90, 1.0)
    # After 90° CCW: new width = old height, new height = old width
    new_w, new_h = h, w
    # Adjust translation to account for new dimensions
    rot_90_ccw[0, 2] += (new_w / 2) - center_x
    rot_90_ccw[1, 2] += (new_h / 2) - center_y
    frame = cv2.warpAffine(frame, rot_90_ccw, (new_w, new_h), 
                          flags=cv2.INTER_LINEAR, 
                          borderMode=cv2.BORDER_CONSTANT, 
                          borderValue=(0, 0, 0))
    
    return frame, current_active_notes

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
    
    # Open video file
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    original_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    original_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    # Prepare all transformation parameters
    transform_params = prepare_frame_transformations(
        piano_start, piano_end, key_widths, midi_notes,
        original_width, original_height
    )
    
    out_w = transform_params["output_width"]
    out_h = transform_params["output_height"]
    out_w = out_w - (out_w % 2)  # round down to even
    out_h = out_h - (out_h % 2)
    
    # After 90° CCW rotation, dimensions swap
    final_w = out_h
    final_h = out_w
    final_w = final_w - (final_w % 2)  # round down to even
    final_h = final_h - (final_h % 2)

    # Build ffmpeg command with output dimensions (after 90° CCW rotation)
    ffmpeg_cmd = [
        'ffmpeg',
        '-y',
        # Video input (raw frames from stdin)
        '-f', 'rawvideo',
        '-vcodec', 'rawvideo',
        '-s', f'{final_w}x{final_h}',
        '-pix_fmt', 'bgr24',
        '-r', str(fps),
        '-i', '-',  # Read video from stdin
        # Audio input
        '-ss', str(audio_start_time),
        '-i', audio_path,
        '-t', str(video_duration),
        # Map streams
        '-map', '0:v:0',  # Video from stdin
        '-map', '1:a:0',  # Audio from file
        # Video encoding
        '-c:v', 'libx264',
        '-preset', 'medium',
        '-crf', '18',
        '-pix_fmt', 'yuv420p',
        '-color_range', '2',  # Full color range (0-255)
        # Audio encoding
        '-c:a', 'aac',
        '-b:a', '192k',
        '-shortest',
        output_path
    ]

    ffmpeg_process = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE, stderr=None)

    # Initialize particle system if enabled
    particle_system = None
    if ENABLE_PARTICLES and transform_params['has_visualization']:
        if not BUBBLES_AVAILABLE:
            raise RuntimeError("bubbles library is required for particle effects. Install with: pip install bubbles pillow")
        try:
            particle_system = BubblesParticleSystem(out_w, out_h, fps)
            print("Particle effects enabled")
        except Exception as e:
            raise RuntimeError(f"Failed to initialize particle system: {e}")
    
    if ENABLE_GLOW and transform_params['has_visualization']:
        print(f"Glow effects enabled (intensity: {GLOW_INTENSITY}, blur: {GLOW_BLUR_RADIUS})")

    print(f"Processing {total_frames} frames...")
    frame_count = 0
    previous_active_notes = set()

    with tqdm(total=total_frames, desc="Processing frames", unit="frame") as pbar:
        while True:
            ret, frame = cap.read()
            if not ret:# or frame_count > 1000:
                break

            video_time = frame_count / fps
            frame, current_active_notes = transform_frame(
                frame, video_time, transform_params, out_w, out_h,
                particle_system=particle_system,
                previous_active_notes=previous_active_notes,
                fps=fps
            )
            previous_active_notes = current_active_notes
            
            # Frame is now rotated 90° CCW, so dimensions are swapped
            ffmpeg_process.stdin.write(frame.tobytes())
            frame_count += 1
            pbar.update(1)

    cap.release()
    ffmpeg_process.stdin.close()
    ffmpeg_process.wait()

    if ffmpeg_process.returncode != 0:
        raise RuntimeError(f"ffmpeg encoding failed with return code {ffmpeg_process.returncode}")

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
