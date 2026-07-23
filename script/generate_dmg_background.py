"""Generate a dark-themed DMG background image for EasyPaste installer.

Layout: 660×400 dark background with:
- Left side: App icon area with "Drag EasyPaste" label
- Right side: Applications folder icon area with "to Applications folder" label
- An arrow from left to right
"""
from PIL import Image, ImageDraw, ImageFont
import os

WIDTH = 660
HEIGHT = 400
BG_COLOR = (18, 20, 24)         # Dark background
ACCENT_COLOR = (80, 190, 180)   # Teal accent (matching app icon color)
TEXT_COLOR = (220, 220, 225)    # Light text
ARROW_COLOR = (80, 190, 180)   # Teal arrow
GLOW_COLOR = (80, 190, 180, 30) # Subtle glow

output_path = os.path.join(os.path.dirname(__file__), '..', 'dist', 'dmg_background.png')

img = Image.new('RGBA', (WIDTH, HEIGHT), BG_COLOR)
draw = ImageDraw.Draw(img)

# ── Rounded rectangle outlines for the two drop zones ──
# Left zone: where app icon sits
left_rect = [40, 100, 280, 280]
# Right zone: where Applications folder sits
right_rect = [380, 100, 620, 280]

# Draw subtle rounded rect outlines
def draw_rounded_rect(d, xy, radius, fill=None, outline=None, width=1):
    x1, y1, x2, y2 = xy
    d.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)

# Left drop zone - subtle border
draw_rounded_rect(draw, left_rect, radius=16, outline=(60, 65, 75), width=2)
# Right drop zone - subtle border with slight accent
draw_rounded_rect(draw, right_rect, radius=16, outline=(60, 65, 75), width=2)

# ── Arrow from left to right ──
arrow_y = 190
arrow_start_x = 285
arrow_end_x = 375

# Arrow line
draw.line([(arrow_start_x, arrow_y), (arrow_end_x - 15, arrow_y)],
          fill=ARROW_COLOR, width=4)
# Arrow head
draw.polygon([
    (arrow_end_x, arrow_y),
    (arrow_end_x - 18, arrow_y - 12),
    (arrow_end_x - 18, arrow_y + 12)
], fill=ARROW_COLOR)

# ── Text labels ──
# Try to use a nice system font
try:
    font_path = "/System/Library/Fonts/SFNSDisplay.ttf"
    font_title = ImageFont.truetype(font_path, 22)
    font_subtitle = ImageFont.truetype(font_path, 14)
    font_small = ImageFont.truetype(font_path, 11)
except:
    try:
        font_path = "/System/Library/Fonts/Helvetica.ttc"
        font_title = ImageFont.truetype(font_path, 22)
        font_subtitle = ImageFont.truetype(font_path, 14)
        font_small = ImageFont.truetype(font_path, 11)
    except:
        font_title = ImageFont.load_default()
        font_subtitle = ImageFont.load_default()
        font_small = ImageFont.load_default()

# Title at top center
title_text = "EasyPaste"
draw.text((WIDTH // 2 - 50, 30), title_text, fill=ACCENT_COLOR, font=font_title)

# Subtitle
subtitle_text = "Clipboard Manager for macOS"
draw.text((WIDTH // 2 - 95, 58), subtitle_text, fill=TEXT_COLOR, font=font_subtitle)

# Left label
left_label = "Drag EasyPaste.app"
draw.text((75, 88), left_label, fill=TEXT_COLOR, font=font_small)

# Right label
right_label = "to Applications folder"
draw.text((395, 88), right_label, fill=TEXT_COLOR, font=font_small)

# Bottom instruction
bottom_text = "Close this window to complete installation"
draw.text((WIDTH // 2 - 130, 320), bottom_text, fill=(100, 105, 115), font=font_small)

# ── Save ──
img.save(output_path, 'PNG')
print(f"Background saved to {output_path}")
