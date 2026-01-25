#!/usr/bin/env python3
"""
Script to generate Equal app icons using PIL/Pillow only
Requires: pip install Pillow
"""

import os
from pathlib import Path
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Please install required packages: pip install Pillow")
    exit(1)

# Define icon sizes for different platforms
ICON_SIZES = {
    # Android mipmap sizes
    'android': {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192
    },
    # iOS sizes
    'ios': {
        'Icon-App-20x20@1x': 20,
        'Icon-App-20x20@2x': 40,
        'Icon-App-20x20@3x': 60,
        'Icon-App-29x29@1x': 29,
        'Icon-App-29x29@2x': 58,
        'Icon-App-29x29@3x': 87,
        'Icon-App-40x40@1x': 40,
        'Icon-App-40x40@2x': 80,
        'Icon-App-40x40@3x': 120,
        'Icon-App-60x60@2x': 120,
        'Icon-App-60x60@3x': 180,
        'Icon-App-76x76@1x': 76,
        'Icon-App-76x76@2x': 152,
        'Icon-App-83.5x83.5@2x': 167,
        'Icon-App-1024x1024@1x': 1024
    },
    # Web sizes
    'web': {
        'Icon-192': 192,
        'Icon-512': 512,
        'Icon-maskable-192': 192,
        'Icon-maskable-512': 512
    }
}

def create_equal_icon(size):
    """Create an Equal logo icon with specified size"""
    # Create image with transparent background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Calculate dimensions based on size
    margin = size * 0.05
    radius = (size - 2 * margin) / 2
    center = size / 2
    
    # Create gradient-like effect with multiple circles
    colors = [
        (255, 107, 107, 255),  # Red
        (78, 205, 196, 255),   # Teal
        (69, 183, 209, 255),   # Blue
        (150, 206, 180, 255), # Green
        (255, 234, 167, 255)  # Yellow
    ]
    
    # Draw background circles for gradient effect
    for i, color in enumerate(colors):
        offset = i * 2
        draw.ellipse(
            [margin + offset, margin + offset, size - margin - offset, size - margin - offset],
            fill=color if i == 0 else (*color[:3], 180 - i * 30)
        )
    
    # Draw inner highlight circle
    inner_margin = margin + radius * 0.2
    draw.ellipse(
        [inner_margin, inner_margin, size - inner_margin, size - inner_margin],
        fill=(255, 255, 255, 30),
        outline=(255, 255, 255, 60),
        width=max(1, size // 100)
    )
    
    # Draw the letter 'E'
    e_width = radius * 0.8
    e_height = radius * 1.2
    e_left = center - e_width / 2
    e_top = center - e_height / 2
    e_thickness = max(4, size // 12)
    
    # Main vertical line of E
    draw.rectangle(
        [e_left, e_top, e_left + e_thickness, e_top + e_height],
        fill=(255, 255, 255, 255)
    )
    
    # Top horizontal line
    draw.rectangle(
        [e_left, e_top, e_left + e_width, e_top + e_thickness],
        fill=(255, 255, 255, 255)
    )
    
    # Middle horizontal line
    middle_y = e_top + e_height / 2 - e_thickness / 2
    draw.rectangle(
        [e_left, middle_y, e_left + e_width * 0.8, middle_y + e_thickness],
        fill=(255, 255, 255, 255)
    )
    
    # Bottom horizontal line
    draw.rectangle(
        [e_left, e_top + e_height - e_thickness, e_left + e_width, e_top + e_height],
        fill=(255, 255, 255, 255)
    )
    
    # Add some decorative dots
    dot_size = max(2, size // 64)
    positions = [
        (center + radius * 0.6, center - radius * 0.4),
        (center + radius * 0.7, center - radius * 0.1),
        (center - radius * 0.6, center + radius * 0.2),
        (center - radius * 0.7, center + radius * 0.5)
    ]
    
    for x, y in positions:
        draw.ellipse(
            [x - dot_size, y - dot_size, x + dot_size, y + dot_size],
            fill=(255, 255, 255, 150)
        )
    
    return img

def generate_icon(output_path, size):
    """Generate icon with specified size"""
    try:
        icon = create_equal_icon(size)
        # Ensure directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)
        icon.save(str(output_path), 'PNG')
        print(f"Generated: {output_path} ({size}x{size})")
        return True
    except Exception as e:
        print(f"Error generating {output_path}: {e}")
        return False

def main():
    # Get the project root directory
    project_root = Path(__file__).parent
    
    print("Generating Equal app icons...")
    
    # Generate Android icons
    android_res_path = project_root / 'android' / 'app' / 'src' / 'main' / 'res'
    for folder, size in ICON_SIZES['android'].items():
        output_dir = android_res_path / folder
        output_path = output_dir / 'ic_launcher.png'
        generate_icon(output_path, size)
    
    # Generate iOS icons
    ios_path = project_root / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    for filename, size in ICON_SIZES['ios'].items():
        output_path = ios_path / f'{filename}.png'
        generate_icon(output_path, size)
    
    # Generate Web icons
    web_icons_path = project_root / 'web' / 'icons'
    for filename, size in ICON_SIZES['web'].items():
        output_path = web_icons_path / f'{filename}.png'
        generate_icon(output_path, size)
    
    # Generate favicon
    favicon_path = project_root / 'web' / 'favicon.png'
    generate_icon(favicon_path, 32)
    
    print("\nIcon generation complete!")
    print("\nNext steps:")
    print("1. Run 'flutter clean' and 'flutter pub get'")
    print("2. Rebuild your app to see the new icons")

if __name__ == '__main__':
    main()