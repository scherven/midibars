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

def combine_video_audio(video_path, audio_path, output_path, audio_start_percent=0):
    """
    Combine a video file with an MP3 audio file using ffmpeg.
    
    Args:
        video_path: Path to the video file
        audio_path: Path to the MP3 audio file
        output_path: Path where the output video will be saved
        audio_start_percent: Percentage through the MP3 where the video should start (0-100)
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
    
    ffmpeg_cmd = [
        'ffmpeg',
        '-i', video_path,  # Input video
        '-ss', str(audio_start_time),  # Start audio at this time
        '-i', audio_path,  # Input audio
        '-t', str(video_duration),  # Duration to process
        '-map', '0:v:0',  # Map video stream from first input
        '-map', '1:a:0',  # Map audio stream from second input
        '-c:v', 'copy',  # Copy video codec (no re-encoding)
        '-c:a', 'aac',  # Encode audio as AAC
        '-b:a', '192k',  # Audio bitrate
        '-shortest',  # Finish when shortest stream ends
        '-y',  # Overwrite output file
        output_path
    ]
    
    print(f"Running: {' '.join(ffmpeg_cmd)}")
    result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"ffmpeg stderr: {result.stderr}")
        raise RuntimeError(f"ffmpeg failed with return code {result.returncode}")
    
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
        combine_video_audio(video_path, audio_path, output_path, start_percent)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
