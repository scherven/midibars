"""
Functions for calculating piano key widths from video frames.
"""

import numpy as np
import math


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

