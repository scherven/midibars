import cv2
import subprocess
import sys
import os
import json
import numpy as np
import math
import colorsys
from tqdm import tqdm
from PIL import Image

# Try to import bubbles library
# from bubbles import ParticleEffect, ImageEffectRenderer, Emitter
from bubbles.emitter import Emitter
from bubbles.particle import Particle
from bubbles.particle_effect import ParticleEffect
from bubbles.renderers.image_effect_renderer import ImageEffectRenderer
BUBBLES_AVAILABLE = True
# except ImportError:
    # BUBBLES_AVAILABLE = False
    # Don't print warning here - will print when actually trying to use it

from midi_loader import load_midi_notes

# ============================================
# USER CONFIGURATION - Adjust these values
# ============================================

# Path to your video file
VIDEO_PATH = "/Users/simonchervenak/Documents/GitHub/midi/attempt13_copy2.mp4"

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

# Visual effects settings
ENABLE_GLOW = False  # Enable glow effect on bars
GLOW_INTENSITY = 0.6  # Glow intensity (0.0 to 1.0)
GLOW_BLUR_RADIUS = 15  # Gaussian blur radius for glow (higher = more blur)

ENABLE_PARTICLES = True  # Enable particle effects (requires: pip install bubbles pillow)

# Particle effect configuration paths
PARTICLE_CONFIG_DIR = "particle_configs"  # Directory containing JSON particle configs
DEFAULT_PARTICLE_CONFIG = "default.json"  # Default particle config for short notes
TORNADO_PARTICLE_CONFIG = "tornado.json"  # Tornado effect for long notes
POP_PARTICLE_CONFIG = "pop.json"  # Pop effect when notes end
LONG_NOTE_THRESHOLD = 1.0  # Notes longer than this (seconds) get tornado effect

# Random color settings
USE_RANDOM_COLORS = True  # Use random colors for particles
RANDOM_COLOR_SATURATION = 0.8  # Saturation for random colors (0.0 to 1.0)
RANDOM_COLOR_BRIGHTNESS = 0.9  # Brightness for random colors (0.0 to 1.0)

# Particle size (for bubbles renderer base_size)
PARTICLE_SIZE = 3  # Base particle size in pixels

# Bar appearance settings
BAR_CORNER_RADIUS = 5  # Corner radius for rounded bars in pixels
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

def load_particle_config(config_name):
    """Load a particle configuration from JSON file."""
    config_path = os.path.join(PARTICLE_CONFIG_DIR, config_name)
    if not os.path.exists(config_path):
        # Try to download tornado.json from GitHub if it doesn't exist
        # if config_name == TORNADO_PARTICLE_CONFIG:
            # return get_default_tornado_config()
        return None
    
    with open(config_path, 'r') as f:
        return json.load(f)

def generate_random_color():
    """Generate a random RGB color with good saturation and brightness."""
    # Generate random hue, use configured saturation and brightness
    hue = np.random.random()
    rgb = colorsys.hsv_to_rgb(
        hue,
        RANDOM_COLOR_SATURATION,
        RANDOM_COLOR_BRIGHTNESS
    )
    # Convert to 0-255 range
    return tuple(int(c * 255) for c in rgb)

def apply_random_colors_to_config(config):
    """Apply random colors to particle settings in a config."""
    if not USE_RANDOM_COLORS:
        return config
    
    random_color = generate_random_color()
    
    def update_colors(obj):
        """Recursively update color values in config."""
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key in ['red', 'green', 'blue']:
                    obj[key] = random_color[0] if key == 'red' else (random_color[1] if key == 'green' else random_color[2])
                elif isinstance(value, (dict, list)):
                    update_colors(value)
        elif isinstance(obj, list):
            for item in obj:
                update_colors(item)
    
    config_copy = json.loads(json.dumps(config))  # Deep copy
    update_colors(config_copy)
    return config_copy

# ============================================
# OpenCV <-> PIL Conversion Functions
# ============================================

def cv2_to_pil(cv_image):
    """Convert OpenCV BGR image to PIL RGB image."""
    # OpenCV uses BGR, PIL uses RGB
    rgb_image = cv2.cvtColor(cv_image, cv2.COLOR_BGR2RGB)
    return Image.fromarray(rgb_image)

def pil_to_cv2(pil_image):
    """Convert PIL RGB image to OpenCV BGR image."""
    # Convert PIL to numpy array
    rgb_array = np.array(pil_image)
    # Convert RGB to BGR
    return cv2.cvtColor(rgb_array, cv2.COLOR_RGB2BGR)

# ============================================
# Particle System for Visual Effects
# ============================================

class BubblesParticleSystem:
    """Particle system using the bubbles library."""
    def __init__(self, width, height, fps=30.0):
        if not BUBBLES_AVAILABLE:
            raise RuntimeError("bubbles library not available")
        
        self.width = width
        self.height = height
        self.fps = fps
        self.renderer = ImageEffectRenderer(base_size=PARTICLE_SIZE)
        
        # Create a master particle effect that will contain all emitters
        self.master_effect = ParticleEffect()
        
        # Track active emitters by their note/start_time key
        self.active_emitters = {}
        
        # Load particle configs
        self.default_config = load_particle_config(DEFAULT_PARTICLE_CONFIG)# or get_default_particle_config()
        self.tornado_config = load_particle_config(TORNADO_PARTICLE_CONFIG)# or get_default_tornado_config()
        self.pop_config = load_particle_config(POP_PARTICLE_CONFIG)# or get_default_pop_config()
    
    def create_emitter_from_config(self, config, x, y, note_key=None, custom_settings=None):
        """Create an emitter from a JSON config.
        
        Args:
            config: Particle config dictionary
            x, y: Emitter position
            note_key: Optional key to track this emitter
            custom_settings: Optional dict to override particle_settings (e.g., {'y_speed': -5})
        """
        if not BUBBLES_AVAILABLE:
            return None
        
        # Apply random colors if enabled
        config = apply_random_colors_to_config(config)
        
        # Get emitter config from JSON
        if "emitters" in config and len(config["emitters"]) > 0:
            emitter_config = config["emitters"][0].copy()
        else:
            return None
        
        # Set position
        emitter_config["x"] = x
        emitter_config["y"] = y
        
        # Apply custom settings if provided
        if custom_settings and "particle_settings" in emitter_config:
            # Handle x_speed specially if it's a list in the config
            if "x_speed" in custom_settings and isinstance(emitter_config["particle_settings"].get("x_speed"), list):
                # If custom_settings x_speed is a single value, apply it to all elements in the list
                if not isinstance(custom_settings["x_speed"], list):
                    base_x_speed = custom_settings["x_speed"]
                    emitter_config["particle_settings"]["x_speed"] = [val + base_x_speed for val in emitter_config["particle_settings"]["x_speed"]]
                else:
                    # If custom_settings x_speed is also a list, replace it
                    emitter_config["particle_settings"]["x_speed"] = custom_settings["x_speed"]
                # Remove x_speed from custom_settings so we don't override it again
                custom_settings = {k: v for k, v in custom_settings.items() if k != "x_speed"}
            emitter_config["particle_settings"].update(custom_settings)
        
        # Create emitter
        emitter = Emitter.load_from_dict(emitter_config)
        self.master_effect.add_emitter(emitter)
        
        # Track emitter if note_key provided
        if note_key:
            self.active_emitters[note_key] = emitter
        
        return emitter
    
    def start_tornado_effect(self, x, y, note_key, bar_height, direction_x, direction_y):
        """Start a continuous tornado effect for a note that stretches up the bar.
        
        Args:
            x, y: Emitter position (at the bar base)
            note_key: Key to track this emitter
            bar_height: Height of the bar in pixels
            direction_x, direction_y: Direction vector for the bar (perpendicular, pointing up)
        """
        if not BUBBLES_AVAILABLE:
            return
        
        # Create tornado emitter from config
        config = self.tornado_config.copy()
        
        # Calculate speed needed to reach bar height along the bar direction
        # Particles need to travel bar_height pixels in the direction of the bar
        # With lifetime of 120 frames, speed per frame = bar_height / 120
        target_speed = bar_height / 120.0  # pixels per frame to reach top in 120 frames
        
        # Calculate speed components in x and y directions
        speed_x = target_speed * direction_x
        speed_y = target_speed * direction_y
        
        # Customize tornado to stretch up the bar
        # The tornado config has x_speed as an array for oscillation
        # Get base oscillation from config and add bar direction movement
        base_x_speeds = config["emitters"][0]["particle_settings"]["x_speed"]
        if not isinstance(base_x_speeds, list):
            base_x_speeds = [base_x_speeds]
        
        custom_settings = {
            "x_speed": [val + speed_x for val in base_x_speeds],  # Oscillating with base movement
            "y_speed": speed_y,  # Go in bar direction
            "y_acceleration": speed_y * 0.01  # Slight acceleration in bar direction
        }
        
        emitter = self.create_emitter_from_config(config, x, y, note_key, custom_settings)
        return emitter
    
    def stop_tornado_effect(self, note_key, velocity=64, direction_x=0, direction_y=-1):
        """Stop tornado effect for a note and emit pop effect.
        
        Args:
            note_key: Key of the emitter to stop
            velocity: MIDI velocity (0-127) to scale pop distance (0-120 pixels)
            direction_x, direction_y: Direction vector for pop (default upward)
        """
        if not BUBBLES_AVAILABLE:
            return
        
        # Get the emitter position before removing it
        emitter = self.active_emitters.get(note_key)
        if emitter:
            x, y = emitter.x, emitter.y
            # Remove tornado emitter
            if emitter in self.master_effect.get_emitters():
                self.master_effect._emitters.remove(emitter)
            del self.active_emitters[note_key]
            
            # Calculate pop distance based on velocity (0-127 maps to 0-120 pixels)
            max_pop_distance = 120  # pixels
            pop_distance = (velocity / 127.0) * max_pop_distance
            
            # Calculate speed per frame to reach max_pop_distance
            # With lifetime of 60 frames, speed = distance / lifetime
            pop_speed = pop_distance / 60.0  # pixels per frame
            
            # Calculate speed components in x and y directions
            pop_speed_x = pop_speed * direction_x
            pop_speed_y = pop_speed * direction_y
            
            # Customize pop to go in bar direction based on velocity
            custom_settings = {
                "x_speed": pop_speed_x,
                "y_speed": pop_speed_y,
                "y_acceleration": -pop_speed_y * 0.1  # Gravity pulling opposite to direction
            }
            
            # Emit pop effect
            self.create_emitter_from_config(self.pop_config, x, y, custom_settings=custom_settings)
    
    def update(self, dt):
        """Update particle effects."""
        if not BUBBLES_AVAILABLE:
            return
        self.master_effect.update(deltatime=dt)
        
        # Clean up finished emitters
        # Check all emitters and remove those that are finished
        current_emitters = list(self.master_effect.get_emitters())
        emitters_to_remove = []
        
        for emitter in current_emitters:
            # Check if emitter is finished
            # For single-burst emitters (spawns == 1), check if particles are gone
            if hasattr(emitter, 'spawns') and emitter.spawns == 1:
                # Check if emitter has finished spawning and has no particles left
                if hasattr(emitter, 'particles'):
                    # Get particle count - particles list might be managed internally
                    try:
                        particle_count = len(emitter.particles) if emitter.particles else 0
                        # Also check if emitter has finished spawning
                        spawned_count = getattr(emitter, '_spawned', 0)
                        if spawned_count >= 1 and particle_count == 0:
                            emitters_to_remove.append(emitter)
                    except (AttributeError, TypeError):
                        # If we can't check particles, skip this emitter
                        pass
            # For finite spawn emitters, check if they've completed spawning and have no particles
            elif hasattr(emitter, 'spawns') and emitter.spawns > 0:
                try:
                    spawned_count = getattr(emitter, '_spawned', 0)
                    particle_count = len(emitter.particles) if hasattr(emitter, 'particles') and emitter.particles else 0
                    if spawned_count >= emitter.spawns and particle_count == 0:
                        emitters_to_remove.append(emitter)
                except (AttributeError, TypeError):
                    pass
        
        # Remove finished emitters
        for emitter in emitters_to_remove:
            try:
                if emitter in self.master_effect._emitters:
                    self.master_effect._emitters.remove(emitter)
            except (ValueError, AttributeError):
                # Emitter might have already been removed
                pass
        
        # Clean up tracked emitters that are no longer active
        current_emitters_set = set(self.master_effect.get_emitters())
        tracked_keys_to_remove = []
        for key, tracked_emitter in self.active_emitters.items():
            if tracked_emitter not in current_emitters_set:
                tracked_keys_to_remove.append(key)
        for key in tracked_keys_to_remove:
            del self.active_emitters[key]
    
    def draw(self, frame):
        """Draw particles on frame using bubbles."""
        if not BUBBLES_AVAILABLE:
            return
        
        # Convert OpenCV frame to PIL Image
        pil_image = cv2_to_pil(frame)
        
        # Render particles onto PIL image
        self.renderer.render_effect(self.master_effect, pil_image)
        
        # Convert back to OpenCV format
        frame[:] = pil_to_cv2(pil_image)
    
    def clear(self):
        """Clear all particles."""
        if BUBBLES_AVAILABLE:
            self.master_effect.emitters = []
            self.active_emitters = {}

def apply_glow_effect(frame, mask, glow_color_bgr, intensity=0.6, blur_radius=15):
    """
    Apply glow effect to regions defined by mask.
    
    Args:
        frame: Original frame
        mask: Binary mask where white pixels indicate glow regions
        glow_color_bgr: BGR color tuple for the glow (e.g., (0, 0, 255) for red)
        intensity: Glow intensity (0.0 to 1.0)
        blur_radius: Gaussian blur radius (must be odd number)
    
    Returns:
        Frame with glow effect applied
    """
    if blur_radius % 2 == 0:
        blur_radius += 1  # Ensure odd number
    
    # Create glow by blurring the mask
    glow_mask = cv2.GaussianBlur(mask.astype(np.float32), (blur_radius, blur_radius), 0)
    
    # Normalize to 0-1 range
    glow_mask = glow_mask / 255.0
    
    # Apply glow to frame
    result = frame.copy().astype(np.float32)
    
    # Create glow color image
    b, g, r = glow_color_bgr
    glow_color = np.zeros_like(frame, dtype=np.float32)
    glow_color[:, :, 0] = b
    glow_color[:, :, 1] = g
    glow_color[:, :, 2] = r
    
    # Blend glow with original frame
    for c in range(3):  # BGR channels
        result[:, :, c] = result[:, :, c] + glow_mask * glow_color[:, :, c] * intensity
    
    # Clamp values to valid range
    result = np.clip(result, 0, 255).astype(np.uint8)
    
    return result

def draw_rounded_polygon(img, pts, radius, color, mask=None):
    """
    Draw a rounded rectangle polygon.
    
    Args:
        img: Image to draw on
        pts: Array of 4 points defining the rectangle corners [bottom_left, bottom_right, top_right, top_left]
        radius: Corner radius in pixels
        color: BGR color tuple
        mask: Optional mask to draw on (for glow effects)
    """
    if len(pts) != 4:
        return
    
    pts = np.array(pts, dtype=np.int32)
    
    # Ensure radius is not too large
    # Calculate approximate width and height
    width = np.linalg.norm(pts[1] - pts[0])
    height = np.linalg.norm(pts[2] - pts[1])
    radius = min(radius, min(width, height) / 2)
    
    if radius <= 0:
        # If radius is 0 or negative, just draw a regular polygon
        if mask is not None:
            cv2.fillPoly(mask, [pts], 255)
        cv2.fillPoly(img, [pts], color)
        return
    
    # Create a mask for the rounded rectangle
    rounded_mask = np.zeros((img.shape[0], img.shape[1]), dtype=np.uint8)
    
    # Draw the main rectangle
    cv2.fillPoly(rounded_mask, [pts], 255)
    
    # Use morphological operations to round the corners
    # Create an elliptical kernel for rounding
    kernel_size = int(radius * 2) | 1  # Ensure odd number
    if kernel_size > 1:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
        # Erode slightly to create rounded corners
        rounded_mask = cv2.erode(rounded_mask, kernel, iterations=1)
        # Dilate back to restore size but with rounded corners
        rounded_mask = cv2.dilate(rounded_mask, kernel, iterations=1)
    
    # Apply the rounded mask
    if mask is not None:
        mask[rounded_mask > 0] = 255
    
    # Draw on the main image
    img[rounded_mask > 0] = color

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

def draw_midi_bars(frame, midi_bar_params, notes, current_time, lead_time=2.0, 
                   particle_system=None, previous_active_notes=None, fps=30.0):
    """
    Draw MIDI note bars on the frame with animation, glow, and particle effects.
    Uses pre-calculated parameters for efficiency.
    
    Args:
        frame: OpenCV frame
        midi_bar_params: Pre-calculated parameters dict from prepare_frame_transformations
        notes: List of MIDI note events
        current_time: Current video time in seconds
        lead_time: How many seconds before the note the bar should appear
        particle_system: BubblesParticleSystem instance for particle effects (optional)
        previous_active_notes: Set of (note, start_time) tuples from previous frame (optional)
        fps: Frames per second for particle system updates
    """
    if midi_bar_params is None:
        return frame, set()
    
    x1 = midi_bar_params['x1']
    y1 = midi_bar_params['y1']
    dir_x = midi_bar_params['dir_x']
    dir_y = midi_bar_params['dir_y']
    right_perp_x = midi_bar_params['right_perp_x']
    right_perp_y = midi_bar_params['right_perp_y']
    cumulative_widths = midi_bar_params['cumulative_widths']
    key_widths_scaled = midi_bar_params['key_widths_scaled']
    
    spawn_offset = 500  # pixels to the right of the line
    color = (0, 0, 255)  # Red in BGR
    max_height = 200000000  # Maximum height in pixels
    min_height = 20   # Minimum height in pixels
    duration_scale = 50  # pixels per second
    
    h, w = frame.shape[:2]
    
    # Create mask for glow effect if enabled
    bar_mask = None
    if ENABLE_GLOW:
        bar_mask = np.zeros((h, w), dtype=np.uint8)
    
    # Track currently active notes for particle emission
    current_active_notes = set()
    
    # Draw notes that are visible (spawning, moving, or playing)
    for note_event in notes:
        note = note_event['note']
        start_time = note_event['start_time']
        end_time = note_event['end_time']
        
        # Check if note should be visible (2 seconds before start to end)
        if current_time < start_time - lead_time or current_time > end_time:
            continue
        
        # Map note to key position (standard 88-key piano: A0 (21) to C8 (108))
        PIANO_START_NOTE = 21
        PIANO_END_NOTE = 108
        if note < PIANO_START_NOTE or note > PIANO_END_NOTE:
            continue
        key_index = note - PIANO_START_NOTE
        if key_index >= len(cumulative_widths) - 1:
            continue
        
        # Use pre-calculated cumulative width and key width
        cumulative_width = cumulative_widths[key_index]
        key_width = key_widths_scaled[key_index]
        
        # Left edge of bar (always on the line at key start position)
        bar_left_x = x1 + cumulative_width * dir_x
        bar_left_y = y1 + cumulative_width * dir_y
        
        # Calculate note duration to determine height
        note_duration = end_time - start_time
        speed = spawn_offset / lead_time
        note_height = max(min_height, note_duration * speed)
        
        # Calculate animation state
        if current_time < start_time:
            progress = max(0, min(1, (current_time - (start_time - lead_time)) / lead_time))
            perpendicular_offset = spawn_offset * (1 - progress)
            current_height = note_height
        else:
            speed = spawn_offset / lead_time
            elapsed = current_time - start_time
            raw_offset = -speed * elapsed  # how far past the line the bottom would be

            # Clamp bottom to the line, but subtract the overshoot from the height
            overshoot = max(0, -raw_offset)  # how far below the line it wanted to go
            perpendicular_offset = max(0, raw_offset)
            current_height = max(0, note_height - overshoot)
        
        # Right edge of bar
        bar_right_x = bar_left_x + key_width * dir_x
        bar_right_y = bar_left_y + key_width * dir_y
        
        # Bottom edge (on line, offset when sliding in)
        bottom_left_x = bar_left_x + perpendicular_offset
        bottom_left_y = bar_left_y
        bottom_right_x = bar_right_x + perpendicular_offset
        bottom_right_y = bar_right_y
        
        # Top edge (offset by current_height in the "right" direction)
        top_left_x = int(bottom_left_x + current_height * right_perp_x)
        top_left_y = int(bottom_left_y + current_height * right_perp_y)
        top_right_x = int(bottom_right_x + current_height * right_perp_x)
        top_right_y = int(bottom_right_y + current_height * right_perp_y)
        
        # Create polygon points
        pts = np.array([
            [int(bottom_left_x), int(bottom_left_y)],
            [int(bottom_right_x), int(bottom_right_y)],
            [top_right_x, top_right_y],
            [top_left_x, top_left_y]
        ], np.int32)
        
        # Draw rounded rectangle
        draw_rounded_polygon(frame, pts, BAR_CORNER_RADIUS, color, bar_mask if ENABLE_GLOW else None)
        
        # Track active notes for particle emission
        note_key = (note, start_time)
        is_note_active = current_time >= start_time and current_time <= end_time
        
        if is_note_active:
            current_active_notes.add(note_key)
            
            # Calculate emission position
            emit_x = (bottom_left_x + bottom_right_x) / 2
            emit_y = (bottom_left_y + bottom_right_y) / 2
            
            # Handle particle effects
            if ENABLE_PARTICLES and particle_system is not None:
                # Check if note just started
                note_just_started = (previous_active_notes is not None and 
                                    note_key not in previous_active_notes)
                
                # Determine if this is a long note
                is_long_note = note_duration > LONG_NOTE_THRESHOLD
                
                if note_just_started:
                    if is_long_note:
                        # Start tornado effect for long notes - stretch up the bar
                        particle_system.start_tornado_effect(
                            emit_x, emit_y, note_key,
                            note_height, right_perp_x, right_perp_y
                        )
                    else:
                        # Use default config for short notes
                        config = particle_system.default_config.copy()
                        particle_system.create_emitter_from_config(config, emit_x, emit_y)
        
        # Check if note just ended (was active in previous frame but not now)
        if (ENABLE_PARTICLES and particle_system is not None and 
            previous_active_notes is not None and 
            note_key in previous_active_notes and 
            not is_note_active):
            # Note just ended - stop tornado and emit pop
            emit_x = (bottom_left_x + bottom_right_x) / 2
            emit_y = (bottom_left_y + bottom_right_y) / 2
            velocity = note_event.get('velocity', 64)  # Default to 64 if not present
            particle_system.stop_tornado_effect(note_key, velocity, right_perp_x, right_perp_y)
    
    # Apply glow effect if enabled
    if ENABLE_GLOW and bar_mask is not None and np.any(bar_mask > 0):
        frame = apply_glow_effect(frame, bar_mask, color, GLOW_INTENSITY, GLOW_BLUR_RADIUS)
    
    # Update and draw particles if enabled
    if ENABLE_PARTICLES and particle_system is not None:
        dt = 1.0 / fps if fps > 0 else 1.0 / 30.0
        particle_system.update(dt)
        particle_system.draw(frame)
    
    return frame, current_active_notes

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
    
    if abs(dy) > 1e-6:  # Avoid division by zero
        # x at y=0
        top_x = x1 + dx * (0 - y1) / dy
        # x at y=h
        bot_x = x1 + dx * (h - y1) / dy
    else:
        # Horizontal line — just use the same x values
        top_x = x1
        bot_x = x2
    
    # Polygon: extended line top -> extended line bottom -> bottom-right -> top-right
    # Use int32 for better performance
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
            if not ret or frame_count > 1000:
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
