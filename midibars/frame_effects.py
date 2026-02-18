"""
Frame effects module for MIDI visualization.
Handles drawing bars, glow effects, and other frame modifications.
"""

import cv2
import numpy as np


# ============================================
# Configuration (can be overridden by importing module)
# ============================================

ENABLE_GLOW = False
GLOW_INTENSITY = 0.6
GLOW_BLUR_RADIUS = 15
BAR_CORNER_RADIUS = 5
ENABLE_PARTICLES = False
LONG_NOTE_THRESHOLD = 1.0


# ============================================
# Frame Effect Functions
# ============================================

def apply_glow_effect(frame, mask, glow_color_bgr, intensity=None, blur_radius=None):
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
    if intensity is None:
        intensity = GLOW_INTENSITY
    if blur_radius is None:
        blur_radius = GLOW_BLUR_RADIUS
    
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


def draw_rounded_polygon(img, pts, radius=None, color=(0, 0, 255), mask=None):
    """
    Draw a rounded rectangle polygon.
    
    Args:
        img: Image to draw on
        pts: Array of 4 points defining the rectangle corners [bottom_left, bottom_right, top_right, top_left]
        radius: Corner radius in pixels
        color: BGR color tuple
        mask: Optional mask to draw on (for glow effects)
    """
    if radius is None:
        radius = BAR_CORNER_RADIUS
    
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
                   particle_system=None, previous_active_notes=None, fps=30.0,
                   enable_glow=None, glow_intensity=None, glow_blur_radius=None,
                   bar_corner_radius=None, enable_particles=None, long_note_threshold=None):
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
        enable_glow: Override ENABLE_GLOW setting
        glow_intensity: Override GLOW_INTENSITY setting
        glow_blur_radius: Override GLOW_BLUR_RADIUS setting
        bar_corner_radius: Override BAR_CORNER_RADIUS setting
        enable_particles: Override ENABLE_PARTICLES setting
        long_note_threshold: Override LONG_NOTE_THRESHOLD setting
    """
    # Use module defaults or overrides
    if enable_glow is None:
        enable_glow = ENABLE_GLOW
    if glow_intensity is None:
        glow_intensity = GLOW_INTENSITY
    if glow_blur_radius is None:
        glow_blur_radius = GLOW_BLUR_RADIUS
    if bar_corner_radius is None:
        bar_corner_radius = BAR_CORNER_RADIUS
    if enable_particles is None:
        enable_particles = ENABLE_PARTICLES
    if long_note_threshold is None:
        long_note_threshold = LONG_NOTE_THRESHOLD
    
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
    if enable_glow:
        bar_mask = np.zeros((h, w), dtype=np.uint8)
    
    # Track currently active notes for particle emission
    current_active_notes = set()
    
    # Track pop intervals that have been emitted for long notes
    # Format: {(note, start_time): last_pop_index}
    if not hasattr(draw_midi_bars, '_pop_tracking'):
        draw_midi_bars._pop_tracking = {}
    
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
        draw_rounded_polygon(frame, pts, bar_corner_radius, color, bar_mask if enable_glow else None)
        
        # Track active notes for particle emission
        note_key = (note, start_time)
        is_note_active = current_time >= start_time and current_time <= end_time
        
        if is_note_active:
            current_active_notes.add(note_key)
            
            # Calculate emission position
            emit_x = (bottom_left_x + bottom_right_x) / 2
            emit_y = (bottom_left_y + bottom_right_y) / 2
            
            # Handle particle effects
            if enable_particles and particle_system is not None:
                # Check if note just started
                note_just_started = (previous_active_notes is not None and 
                                    note_key not in previous_active_notes)
                
                # Determine if this is a long note
                is_long_note = note_duration > long_note_threshold
                
                velocity = note_event.get('velocity', 64)  # Default to 64 if not present
                
                if note_just_started:
                    # Emit pop effect when note starts
                    particle_system.create_pop_effect(emit_x, emit_y, velocity, right_perp_x, right_perp_y)
                    
                    # Initialize pop tracking for long notes
                    if is_long_note:
                        draw_midi_bars._pop_tracking[note_key] = 0  # Track which pop interval we're on
                else:
                    # For long notes, emit additional pops at regular intervals
                    if is_long_note and note_key in draw_midi_bars._pop_tracking:
                        elapsed = current_time - start_time
                        pop_interval = 0.5  # seconds between pops
                        current_pop_index = int(elapsed / pop_interval)
                        last_pop_index = draw_midi_bars._pop_tracking[note_key]
                        
                        # Emit pop if we've moved to a new pop interval
                        if current_pop_index > last_pop_index and elapsed > 0.1:  # Small delay after start
                            particle_system.create_pop_effect(emit_x, emit_y, velocity, right_perp_x, right_perp_y)
                            draw_midi_bars._pop_tracking[note_key] = current_pop_index
        
        # Check if note just ended (was active in previous frame but not now)
        if (enable_particles and particle_system is not None and 
            previous_active_notes is not None and 
            note_key in previous_active_notes and 
            not is_note_active):
            # Note just ended - emit final pop
            emit_x = (bottom_left_x + bottom_right_x) / 2
            emit_y = (bottom_left_y + bottom_right_y) / 2
            velocity = note_event.get('velocity', 64)  # Default to 64 if not present
            particle_system.create_pop_effect(emit_x, emit_y, velocity, right_perp_x, right_perp_y)
            
            # Clean up pop tracking for this note
            if note_key in draw_midi_bars._pop_tracking:
                del draw_midi_bars._pop_tracking[note_key]
    
    # Apply glow effect if enabled
    if enable_glow and bar_mask is not None and np.any(bar_mask > 0):
        frame = apply_glow_effect(frame, bar_mask, color, glow_intensity, glow_blur_radius)
    
    # Update and draw particles if enabled
    if enable_particles and particle_system is not None:
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
        bottom_x = x1 + dx * (h - y1) / dy
        
        # Create polygon points for the blackout region
        # Points on the line (top and bottom) plus frame corners on the right side
        pts = np.array([
            [int(top_x), 0],
            [w, 0],
            [w, h],
            [int(bottom_x), h]
        ], np.int32)
        
        # Fill the region to the right of the line with black
        cv2.fillPoly(frame, [pts], (0, 0, 0))
    else:
        # Horizontal line case
        if x1 < w / 2:  # Line is on the left, blackout right side
            cv2.rectangle(frame, (int(x1), 0), (w, h), (0, 0, 0), -1)
        else:  # Line is on the right, blackout left side
            cv2.rectangle(frame, (0, 0), (int(x1), h), (0, 0, 0), -1)
    
    return frame

