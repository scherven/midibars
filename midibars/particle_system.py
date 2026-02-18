"""
Particle system module for MIDI visualization.
Handles particle effects using the bubbles library.
"""

import os
import json
import numpy as np
import colorsys
import cv2
from PIL import Image

# Try to import bubbles library
# try:
from bubbles.emitter import Emitter
from bubbles.particle import Particle
from bubbles.particle_effect import ParticleEffect
from bubbles.renderers.image_effect_renderer import ImageEffectRenderer
BUBBLES_AVAILABLE=True

# ============================================
# Configuration (can be overridden by importing module)
# ============================================

PARTICLE_CONFIG_DIR = "particle_configs"
DEFAULT_PARTICLE_CONFIG = "default.json"
TORNADO_PARTICLE_CONFIG = "tornado.json"
POP_PARTICLE_CONFIG = "pop.json"
USE_RANDOM_COLORS = True
RANDOM_COLOR_SATURATION = 0.8
RANDOM_COLOR_BRIGHTNESS = 0.9
PARTICLE_SIZE = 3


# ============================================
# Helper Functions
# ============================================

def load_particle_config(config_name, config_dir=None):
    """Load a particle configuration from JSON file."""
    if config_dir is None:
        config_dir = PARTICLE_CONFIG_DIR
    config_path = os.path.join(config_dir, config_name)
    if not os.path.exists(config_path):
        return None
    
    with open(config_path, 'r') as f:
        return json.load(f)


def generate_random_color(saturation=None, brightness=None):
    """Generate a random RGB color with good saturation and brightness."""
    if saturation is None:
        saturation = RANDOM_COLOR_SATURATION
    if brightness is None:
        brightness = RANDOM_COLOR_BRIGHTNESS
    
    # Generate random hue, use configured saturation and brightness
    hue = np.random.random()
    rgb = colorsys.hsv_to_rgb(hue, saturation, brightness)
    # Convert to 0-255 range
    return tuple(int(c * 255) for c in rgb)


def apply_random_colors_to_config(config, use_random=None):
    """Apply random colors to particle settings in a config."""
    if use_random is None:
        use_random = USE_RANDOM_COLORS
    
    if not use_random:
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
# Particle System Class
# ============================================

class BubblesParticleSystem:
    """Particle system using the bubbles library."""
    def __init__(self, width, height, fps=30.0, 
                 particle_size=None,
                 config_dir=None,
                 default_config=None,
                 tornado_config=None,
                 pop_config=None,
                 use_random_colors=None):
        if not BUBBLES_AVAILABLE:
            raise RuntimeError("bubbles library not available")
        
        self.width = width
        self.height = height
        self.fps = fps
        
        if particle_size is None:
            particle_size = PARTICLE_SIZE
        self.renderer = ImageEffectRenderer(base_size=particle_size)
        
        # Track active effects by their note/start_time key
        # Each effect contains one emitter for finer control
        self.active_effects = {}  # {note_key: ParticleEffect}
        
        # Counter for generating unique IDs for untracked effects (like pop effects)
        self._effect_counter = 0
        
        # Load particle configs
        if config_dir is None:
            config_dir = PARTICLE_CONFIG_DIR
        if default_config is None:
            default_config = DEFAULT_PARTICLE_CONFIG
        if tornado_config is None:
            tornado_config = TORNADO_PARTICLE_CONFIG
        if pop_config is None:
            pop_config = POP_PARTICLE_CONFIG
        
        self.config_dir = config_dir
        self.default_config = load_particle_config(default_config, config_dir)
        self.tornado_config = load_particle_config(tornado_config, config_dir)
        self.pop_config = load_particle_config(pop_config, config_dir)
        
        self.use_random_colors = use_random_colors if use_random_colors is not None else USE_RANDOM_COLORS
    
    def create_emitter_from_config(self, config, x, y, note_key=None, custom_settings=None):
        """Create an emitter from a JSON config.
        
        Args:
            config: Particle config dictionary
            x, y: Emitter position
            note_key: Optional key to track this effect
            custom_settings: Optional dict to override particle_settings (e.g., {'y_speed': -5})
        
        Returns:
            ParticleEffect instance containing the emitter
        """
        if not BUBBLES_AVAILABLE:
            return None
        
        # Apply random colors if enabled
        config = apply_random_colors_to_config(config, self.use_random_colors)
        
        # Get emitter config from JSON
        if "emitters" in config and len(config["emitters"]) > 0:
            emitter_config = config["emitters"][0].copy()
        else:
            return None
        
        # Set position
        emitter_config["x"] = x
        emitter_config["y"] = y
        
        # Apply custom settings if provided
        if custom_settings:
            # Handle width/height at emitter level
            if "width" in custom_settings:
                emitter_config["width"] = custom_settings["width"]
            if "height" in custom_settings:
                emitter_config["height"] = custom_settings["height"]
            
            # Handle particle_settings
            if "particle_settings" in emitter_config:
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
                
                # Update particle_settings with remaining custom_settings
                particle_custom = {k: v for k, v in custom_settings.items() 
                                  if k not in ["width", "height"]}
                emitter_config["particle_settings"].update(particle_custom)
        
        # Create emitter
        emitter = Emitter.load_from_dict(emitter_config)
        
        # Create a ParticleEffect for this emitter
        effect = ParticleEffect()
        effect.add_emitter(emitter)
        
        # Track effect if note_key provided
        if note_key:
            self.active_effects[note_key] = effect
        
        return effect
    
    def start_tornado_effect(self, x, y, note_key, bar_height, direction_x, direction_y):
        """Start a continuous tornado effect for a note that stretches up the bar.
        
        Args:
            x, y: Emitter position (at the bar base)
            note_key: Key to track this effect
            bar_height: Height of the bar in pixels
            direction_x, direction_y: Direction vector for the bar (perpendicular, pointing up)
        """
        # Remove existing effect for this note if any
        if note_key in self.active_effects:
            del self.active_effects[note_key]
        
        # Create tornado emitter from config
        config = self.tornado_config.copy() if self.tornado_config else None
        if config is None:
            return
        
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
        base_x_speeds = config["emitters"][0]["particle_settings"].get("x_speed", [0])
        if not isinstance(base_x_speeds, list):
            base_x_speeds = [base_x_speeds]
        
        custom_settings = {
            "width": bar_height,
            "x_speed": [val + speed_x for val in base_x_speeds],  # Oscillating with base movement
            "y_speed": speed_y,  # Go in bar direction
            "y_acceleration": speed_y * 0.01  # Slight acceleration in bar direction
        }
        
        effect = self.create_emitter_from_config(config, x, y, note_key, custom_settings)
        return effect
    
    def create_pop_effect(self, x, y, velocity=64, direction_x=0, direction_y=-1):
        """Create a pop effect at the specified position.
        
        Args:
            x, y: Position for the pop effect
            velocity: MIDI velocity (0-127) to scale pop distance (0-120 pixels)
            direction_x, direction_y: Direction vector for pop (default upward)
        
        Returns:
            The created ParticleEffect instance
        """
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
        
        # Generate a unique key for this pop effect
        pop_key = f"pop_{self._effect_counter}"
        self._effect_counter += 1
        
        # Create and track the pop effect
        effect = self.create_emitter_from_config(self.pop_config, x, y, note_key=pop_key, custom_settings=custom_settings)
        return effect
    
    def update(self, dt):
        """Update particle effects."""
        # Update each effect separately
        effects_to_remove = []
        for note_key, effect in self.active_effects.items():
            # Update the effect
            effect.update(deltatime=dt)
            
            # Check if effect is finished (no active emitters or all emitters finished)
            emitters = effect.get_emitters()
            if not emitters or len(emitters) == 0:
                effects_to_remove.append(note_key)
                continue
            
            # Check if all emitters in this effect are finished
            all_finished = True
            for emitter in emitters:
                # Check if emitter is finished
                # For single-burst emitters (spawns == 1), check if particles are gone
                if hasattr(emitter, 'spawns') and emitter.spawns == 1:
                    try:
                        particle_count = len(emitter.particles) if hasattr(emitter, 'particles') and emitter.particles else 0
                        spawned_count = getattr(emitter, '_spawned', 0)
                        if not (spawned_count >= 1 and particle_count == 0):
                            all_finished = False
                    except (AttributeError, TypeError):
                        all_finished = False
                # For finite spawn emitters
                elif hasattr(emitter, 'spawns') and emitter.spawns > 0:
                    try:
                        spawned_count = getattr(emitter, '_spawned', 0)
                        particle_count = len(emitter.particles) if hasattr(emitter, 'particles') and emitter.particles else 0
                        if not (spawned_count >= emitter.spawns and particle_count == 0):
                            all_finished = False
                    except (AttributeError, TypeError):
                        all_finished = False
                # For infinite spawn emitters (spawns == -1), they're never finished unless manually removed
                elif hasattr(emitter, 'spawns') and emitter.spawns == -1:
                    all_finished = False
            
            if all_finished:
                effects_to_remove.append(note_key)
        
        # Remove finished effects
        for note_key in effects_to_remove:
            del self.active_effects[note_key]
    
    def draw(self, frame):
        """Draw particles on frame using bubbles."""
        # Convert OpenCV frame to PIL Image
        pil_image = cv2_to_pil(frame)
        
        # Render each effect separately
        for effect in self.active_effects.values():
            self.renderer.render_effect(effect, pil_image)
        
        # Convert back to OpenCV format
        frame[:] = pil_to_cv2(pil_image)
    
    def clear(self):
        """Clear all particles."""
        self.active_effects = {}

