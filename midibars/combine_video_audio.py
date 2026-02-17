#!/usr/bin/env python3
"""
Script to combine a video file with an MP3 audio file.
The video and audio are aligned based on a sync offset percentage.
"""

from moviepy.editor import VideoFileClip, AudioFileClip
import sys
import os

# ============================================
# USER CONFIGURATION - Adjust these values
# ============================================

# Path to your video file
VIDEO_PATH = "attempt13 copy.mov"

# Path to your MP3 file
MP3_PATH = "attempt1213fixed.mp3"

# MP3 start percentage (0 = start from beginning, 60 = start from 60% through the MP3)
# This determines where in the MP3 the video will start syncing
MP3_START_PERCENT = 55.9

# Output file path
OUTPUT_PATH = "output_with_audio.mp4"

# ============================================
# Script execution
# ============================================

def combine_video_audio(video_path, audio_path, output_path, audio_start_percent=0):
    """
    Combine a video file with an MP3 audio file.
    
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
    
    print(f"Loading video: {video_path}")
    video = VideoFileClip(video_path)
    
    print(f"Loading audio: {audio_path}")
    audio = AudioFileClip(audio_path)
    
    # Get durations
    video_duration = video.duration
    audio_duration = audio.duration
    
    print(f"Video duration: {video_duration:.2f} seconds")
    print(f"Audio duration: {audio_duration:.2f} seconds")
    
    # Calculate where in the audio to start based on percentage
    audio_start_time = audio_duration * (audio_start_percent / 100.0)
    
    print(f"Starting audio at {audio_start_percent}% through MP3 ({audio_start_time:.2f} seconds)")
    
    # Extract audio from the calculated start point
    if audio_start_time > 0:
        audio = audio.subclip(audio_start_time)
        remaining_audio_duration = audio.duration
        print(f"Remaining audio duration after start point: {remaining_audio_duration:.2f} seconds")
    
    # Align audio with video
    # If remaining audio is longer than video, trim it to match video duration
    # If remaining audio is shorter, it will end before video ends
    remaining_audio_duration = audio.duration
    if remaining_audio_duration > video_duration:
        print(f"Trimming audio to match video duration ({video_duration:.2f}s)")
        audio = audio.subclip(0, video_duration)
    elif remaining_audio_duration < video_duration:
        print(f"Warning: Remaining audio ({remaining_audio_duration:.2f}s) is shorter than video ({video_duration:.2f}s)")
        print("Audio will end before video. Consider adjusting the start percentage or using a longer audio file.")
    
    # Set the audio to the video
    print("Combining video and audio...")
    final_video = video.set_audio(audio)
    
    # Write the output file
    print(f"Writing output to: {output_path}")
    final_video.write_videofile(
        output_path,
        codec='libx264',
        audio_codec='aac',
        temp_audiofile='temp-audio.m4a',
        remove_temp=True
    )
    
    # Clean up
    video.close()
    audio.close()
    final_video.close()
    
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
        sys.exit(1)

