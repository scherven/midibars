#!/usr/bin/env python3
"""
Script to combine a video file with an MP3 audio file.
The video and audio are aligned based on a sync offset percentage.
Uses OpenCV for video reading and ffmpeg for audio processing.
"""

import cv2
import subprocess
import sys
import os
import json
import numpy as np
import math

# ============================================
# USER CONFIGURATION - Adjust these values
# ============================================

# Path to your video file
VIDEO_PATH = "/Users/simonchervenak/Documents/GitHub/midi/attempt13_copy.mov"

# Path to your MP3 file
MP3_PATH = "/Users/simonchervenak/Documents/GitHub/midi/attempt1213fixed.mp3"

# MP3 start percentage (0 = start from beginning, 60 = start from 60% through the MP3)
# This determines where in the MP3 the video will start syncing
MP3_START_PERCENT = 55.6

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
print(len(KEY_WIDTHS    ))
  # Array of key widths, e.g., [50, 30, 50, 30, 50, 50, 30, 50, 30, 50, 30, 50]
LINE_THICKNESS = 5  # Thickness of the line segments

# ============================================
# Script execution
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

def calculate_key_widths_from_frame(frame, start_point, end_point):
    """
    Calculate key widths by sampling pixels along the line and following piano pattern.
    
    Args:
        frame: OpenCV frame (numpy array)
        start_point: [x, y] coordinates where piano starts
        end_point: [x, y] coordinates where piano ends
    
    Returns:
        Array of key widths
    """
    x1, y1 = start_point
    x2, y2 = end_point
    
    # Calculate line direction and length
    dx = x2 - x1
    dy = y2 - y1
    line_length = math.sqrt(dx * dx + dy * dy)
    
    if line_length == 0:
        return []
    
    # Normalize direction vector
    dir_x = dx / line_length
    dir_y = dy / line_length
    
    # Sample pixels along the line (sample every pixel)
    num_samples = int(line_length)
    pixel_values = []
    
    for i in range(num_samples):
        x = int(x1 + i * dir_x)
        y = int(y1 + i * dir_y)
        
        # Check bounds
        if 0 <= y < frame.shape[0] and 0 <= x < frame.shape[1]:
            # Get pixel value (convert to grayscale if color)
            if len(frame.shape) == 3:
                pixel = frame[y, x]
                # Convert to grayscale using standard weights
                gray = int(0.299 * pixel[2] + 0.587 * pixel[1] + 0.114 * pixel[0])
            else:
                gray = int(frame[y, x])
            pixel_values.append(gray)
        else:
            pixel_values.append(128)  # Default gray if out of bounds
    
    # Determine threshold for white/black (use median or mean)
    if len(pixel_values) == 0:
        return []
    
    threshold = np.median(pixel_values)
    
    # Classify pixels as white (1) or black (0)
    binary = [1 if p > threshold else 0 for p in pixel_values]
    
    # Group consecutive pixels of the same color
    groups = []
    current_group = [binary[0]]
    
    for i in range(1, len(binary)):
        if binary[i] == binary[i-1]:
            current_group.append(binary[i])
        else:
            groups.append((binary[i-1], len(current_group)))
            current_group = [binary[i]]
    
    if len(current_group) > 0:
        groups.append((binary[-1], len(current_group)))
    
    # Piano pattern for 88 keys
    # Pattern per octave (starting from C): W B W B W W B W B W B W
    # For 88 keys: A0, A#0, B0, then 7 full octaves (C1-B7), then C8
    # Pattern: A(W), A#(B), B(W), then 7x [C(W), C#(B), D(W), D#(B), E(W), F(W), F#(B), G(W), G#(B), A(W), A#(B), B(W)], then C8(W)
    
    # Generate expected pattern for 88 keys
    # Starting from A0: W, B, W (A0, A#0, B0)
    # Then 7 octaves: W, B, W, B, W, W, B, W, B, W, B, W (C to B)
    # Then: W (C8)
    expected_pattern = []
    
    # A0, A#0, B0
    expected_pattern.extend([1, 0, 1])  # W, B, W
    
    # 7 full octaves (C to B)
    octave_pattern = [1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1]  # C, C#, D, D#, E, F, F#, G, G#, A, A#, B
    for _ in range(7):
        expected_pattern.extend(octave_pattern)
    
    # C8
    expected_pattern.append(1)  # W
    
    # Match groups to expected pattern sequentially
    key_widths = []
    group_idx = 0
    pattern_idx = 0
    
    # Filter out very small groups (likely noise) - groups smaller than 2 pixels
    filtered_groups = [(color, width) for color, width in groups if width >= 2]
    
    while group_idx < len(filtered_groups) and pattern_idx < len(expected_pattern):
        group_color, group_width = filtered_groups[group_idx]
        expected_color = expected_pattern[pattern_idx]
        
        if group_color == expected_color:
            # Match! Add this group's width
            key_widths.append(group_width)
            group_idx += 1
            pattern_idx += 1
        else:
            # Mismatch - skip small groups or try to find next matching group
            if group_width < 5:  # Skip very small mismatched groups
                group_idx += 1
            else:
                # Look ahead for a matching group (up to 2 groups ahead)
                found_match = False
                for look_ahead in range(1, min(3, len(filtered_groups) - group_idx)):
                    if filtered_groups[group_idx + look_ahead][0] == expected_color:
                        # Found match ahead - add skipped groups and the match
                        for i in range(group_idx, group_idx + look_ahead + 1):
                            key_widths.append(filtered_groups[i][1])
                        group_idx += look_ahead + 1
                        pattern_idx += 1
                        found_match = True
                        break
                
                if not found_match:
                    # No match found, skip this pattern element and try next
                    pattern_idx += 1
    
    # If we have remaining groups but pattern is done, add them
    while group_idx < len(filtered_groups):
        key_widths.append(filtered_groups[group_idx][1])
        group_idx += 1
    
    return key_widths

def draw_piano_keys_line(frame, start_point, end_point, key_widths, line_thickness=5):
    """
    Draw a line from start_point to end_point with alternating green/red segments
    based on key_widths array.
    
    Args:
        frame: OpenCV frame (numpy array)
        start_point: [x, y] coordinates where line starts
        end_point: [x, y] coordinates where line ends
        key_widths: Array of segment widths (in pixels or relative units)
        line_thickness: Thickness of the line
    """
    if start_point is None or end_point is None or key_widths is None:
        return frame
    
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
    
    # Calculate total width from key_widths array
    total_width = sum(key_widths)
    
    # Scale key widths to match line length
    scale_factor = line_length / total_width if total_width > 0 else 1.0
    scaled_widths = [w * scale_factor for w in key_widths]
    
    # Draw segments alternating between green and red
    current_pos = 0
    is_green = True  # Start with green
    
    for width in scaled_widths:
        # Calculate segment start and end points
        seg_start_x = x1 + current_pos * dir_x
        seg_start_y = y1 + current_pos * dir_y
        seg_end_x = x1 + (current_pos + width) * dir_x
        seg_end_y = y1 + (current_pos + width) * dir_y
        
        # Choose color (BGR format in OpenCV)
        color = (0, 255, 0) if is_green else (0, 0, 255)  # Green or Red
        
        # Draw the line segment
        cv2.line(frame, 
                (int(seg_start_x), int(seg_start_y)),
                (int(seg_end_x), int(seg_end_y)),
                color, line_thickness, cv2.LINE_AA)
        
        current_pos += width
        is_green = not is_green  # Alternate color
    
    return frame

def debug_visualization_frame(video_path, output_png_path, piano_start, piano_end, key_widths, line_thickness=5, calculate_widths=False):
    """
    Debug function: Read first frame, draw piano key visualization, and save as PNG.
    
    Args:
        calculate_widths: If True, calculate key widths from the frame instead of using provided
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")
    
    # Read first frame
    ret, frame = cap.read()
    if not ret:
        cap.release()
        raise RuntimeError("Could not read first frame from video")
    
    cap.release()
    
    # Calculate key widths from frame if requested
    if calculate_widths:
        print("Calculating key widths from frame...")
        calculated_key_widths = calculate_key_widths_from_frame(frame, piano_start, piano_end)
        if calculated_key_widths:
            key_widths = calculated_key_widths
            print(key_widths)
            # print(f"Calculated {len(key_widths)} key widths: {key_widths[:10]}... (showing first 10)")
        else:
            print("Warning: Could not calculate key widths, using provided values")
    
    # Draw piano keys line on frame
    print("Drawing piano key visualization on first frame...")
    frame = draw_piano_keys_line(frame, piano_start, piano_end, key_widths, line_thickness)
    
    # Save as PNG
    cv2.imwrite(output_png_path, frame)
    print(f"Debug frame saved to: {output_png_path}")
    
    return output_png_path

def process_video_with_visualization(video_path, output_path, piano_start, piano_end, key_widths, line_thickness=5):
    """
    Process video frame by frame and add piano key visualization.
    Returns the path to the processed video (may be a temp file).
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video file: {video_path}")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    
    # Create temporary output file for processed video
    temp_output = output_path.replace('.mp4', '_temp_visualized.mp4')
    
    # Define codec and create VideoWriter
    # Try H264 first, fall back to mp4v if not available
    fourcc = cv2.VideoWriter_fourcc(*'H264')
    out = cv2.VideoWriter(temp_output, fourcc, fps, (width, height))
    if not out.isOpened():
        # Fall back to mp4v if H264 doesn't work
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(temp_output, fourcc, fps, (width, height))
        if not out.isOpened():
            raise RuntimeError("Could not create video writer")
    
    frame_count = 0
    print("Processing video frames with piano key visualization...")
    
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        
        # Draw piano keys line on frame
        frame = draw_piano_keys_line(frame, piano_start, piano_end, key_widths, line_thickness)
        
        out.write(frame)
        frame_count += 1
        
        if frame_count % 30 == 0:
            print(f"Processed {frame_count} frames...")
    
    cap.release()
    out.release()
    
    print(f"Processed {frame_count} frames. Temporary file: {temp_output}")
    return temp_output

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
                        piano_start=None, piano_end=None, key_widths=None, line_thickness=5):
    """
    Combine a video file with an MP3 audio file using ffmpeg.
    
    Args:
        video_path: Path to the video file
        audio_path: Path to the MP3 audio file
        output_path: Path where the output video will be saved
        audio_start_percent: Percentage through the MP3 where the video should start (0-100)
        piano_start: [x, y] coordinates where piano starts (None to disable)
        piano_end: [x, y] coordinates where piano ends (None to disable)
        key_widths: Array of key widths for visualization (None to disable)
        line_thickness: Thickness of the visualization line
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
    
    # Debug mode: Just output first frame with visualization as PNG
    if piano_start is not None and piano_end is not None:
        debug_output_path = "../output.png"
        # Always calculate key widths from the frame
        debug_visualization_frame(
            video_path, debug_output_path, piano_start, piano_end, key_widths, line_thickness, calculate_widths=False
        )
        print("Debug mode: Only first frame saved. Exiting.")
        return
    
    # Process video with visualization if enabled (for full video processing)
    video_to_use = video_path
    temp_video_path = None
    
    # Calculate where in the audio to start based on percentage
    audio_start_time = audio_duration * (audio_start_percent / 100.0)
    
    print(f"Starting audio at {audio_start_percent}% through MP3 ({audio_start_time:.2f} seconds)")
    
    # Calculate how much audio we need
    remaining_audio_duration = audio_duration - audio_start_time
    
    if remaining_audio_duration < video_duration:
        print(f"Warning: Remaining audio ({remaining_audio_duration:.2f}s) is shorter than video ({video_duration:.2f}s)")
        print("Audio will end before video. Consider adjusting the start percentage or using a longer audio file.")
        # Trim video to match available audio
        video_duration = remaining_audio_duration
        print(f"Trimming video to match available audio: {video_duration:.2f}s")
    
    # Build ffmpeg command to combine video and audio
    # -ss: start time for audio (skip to the percentage point)
    # -t: duration (use video duration)
    # -map: map video stream and audio stream
    # -c:v copy: copy video codec (no re-encoding for speed)
    # -c:a aac: encode audio as AAC
    # -shortest: finish encoding when the shortest input stream ends
    
    print("Combining video and audio with ffmpeg...")
    
    # Use copy codec if no visualization (faster), otherwise re-encode
    video_codec = 'libx264' if temp_video_path else 'copy'
    
    ffmpeg_cmd = [
        'ffmpeg',
        '-i', video_to_use,  # Input video (may be processed with visualization)
        '-ss', str(audio_start_time),  # Start audio at this time
        '-i', audio_path,  # Input audio
        '-t', str(video_duration),  # Duration to process
        '-map', '0:v:0',  # Map video stream from first input
        '-map', '1:a:0',  # Map audio stream from second input
        '-c:v', video_codec,  # Video codec (copy or re-encode)
        '-c:a', 'aac',  # Encode audio as AAC
        '-b:a', '192k',  # Audio bitrate
    ]
    
    # Add video encoding options if re-encoding
    if video_codec == 'libx264':
        ffmpeg_cmd.extend(['-preset', 'medium', '-crf', '23'])
    
    ffmpeg_cmd.extend([
        '-shortest',  # Finish when shortest stream ends
        '-y',  # Overwrite output file
        output_path
    ])
    
    print(f"Running: {' '.join(ffmpeg_cmd)}")
    result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"ffmpeg stderr: {result.stderr}")
        raise RuntimeError(f"ffmpeg failed with return code {result.returncode}")
    
    # Clean up temporary video file if we created one
    if temp_video_path and os.path.exists(temp_video_path):
        os.unlink(temp_video_path)
        print("Cleaned up temporary visualization file")
    
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
            line_thickness=LINE_THICKNESS
        )
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
