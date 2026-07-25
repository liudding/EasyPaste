"""Generate a dark-themed DMG background image for EasyPaste installer.

Layout: 600 x CONTENT_H (372) dark background with:
- Left side: App icon area with "Drag EasyPaste" label
- Right side: Applications folder icon area with "to Applications folder" label
- An arrow from left to right
Both the icon group and the placeholder group are centered in their frame.

COORDINATE MODEL (critical for alignment):
In Finder, the folder background picture and the icons live inside the SAME
scroll view -- the content area *below* the title bar. They share one origin:
the top-left of the content area. There is NO title-bar offset between the
background and the icons.

Therefore:
- The window_rect in dmgbuild_settings.py is the FULL window: (600, 400).
- The title bar is 28pt (standard titled macOS window), so the CONTENT area
  is 600 x (400 - 28) = 600 x 372.
- This background image is drawn at exactly 600 x 372 (the content size) so
  Finder shows it 1:1 with no scaling/letterboxing that would shift placeholders.
- Artwork is drawn in CONTENT coordinates, identical to the icon_locations in
  dmgbuild_settings.py (top-left + 40 = icon center). No offset is applied.
"""
from PIL import Image, ImageDraw, ImageFont
import os

# Must match window_rect in dmgbuild_settings.py (600 x 400 full window).
WINDOW_W = 600
WINDOW_H = 400
# Title bar height for a standard titled macOS window (frame 428 - content 400).
TITLE_BAR = 28
# Content area = what Finder actually draws the background + icons into.
CONTENT_W = WINDOW_W
CONTENT_H = WINDOW_H - TITLE_BAR            # 372

WIDTH = CONTENT_W                           # 600
HEIGHT = CONTENT_H                          # 372

BG_COLOR = (18, 20, 24)         # Dark background
ACCENT_COLOR = (80, 190, 180)   # Teal accent (matching app icon color)
TEXT_COLOR = (220, 220, 225)    # Light text
ARROW_COLOR = (80, 190, 180)    # Teal arrow

output_path = os.path.join(os.path.dirname(__file__), '..', 'dist', 'dmg_background.png')

# ── Centered icon group ──
# 80px icons. Group bbox must be centered in the content area (CONTENT_W x
# CONTENT_H). Content center = (300, 186).
# Horizontal: icon1 left=200, icon2 left=320 -> bbox x 200..400, w=200, cx=300.
# Vertical:   both on one row, h=80 -> bbox top = 186 - 40 = 146.
# So top-left positions: (200, 146) and (320, 146); centers (240, 186)/(360, 186).
ICON_SIZE = 80
ICON_TOPLEFT_APP = (200, 146)
ICON_TOPLEFT_APPS = (320, 146)
ICON_CX_APP, ICON_CY = 240, 186
ICON_CX_APPS = 360

# Artwork is drawn in the SAME content coordinates as the icons (offset = 0).
APP_CX, APPS_CX, APP_CY, APPS_CY = ICON_CX_APP, ICON_CX_APPS, ICON_CY, ICON_CY
ZONE = 84  # drop-zone box size (slightly larger than the 80px icon)

# Text baselines (content coordinates, no offset).
TITLE_Y = 36
SUBTITLE_Y = 62
LABEL_Y = 126      # just above the zone boxes (zone top = 144)
BOTTOM_Y = 344     # near the bottom of the 372-tall image

img = Image.new('RGBA', (WIDTH, HEIGHT), BG_COLOR)
draw = ImageDraw.Draw(img)

# ── Rounded rectangle outlines for the two drop zones ──
left_rect = [APP_CX - ZONE // 2, APP_CY - ZONE // 2,
             APP_CX + ZONE // 2, APP_CY + ZONE // 2]
right_rect = [APPS_CX - ZONE // 2, APPS_CY - ZONE // 2,
              APPS_CX + ZONE // 2, APPS_CY + ZONE // 2]

# Left drop zone - subtle border
draw.rounded_rectangle(left_rect, radius=16, outline=(60, 65, 75), width=2)
# Right drop zone - subtle border
draw.rounded_rectangle(right_rect, radius=16, outline=(60, 65, 75), width=2)

# ── Arrow from left to right (between the two zones, vertically centered) ──
arrow_y = APP_CY
arrow_start_x = left_rect[2] + 4
arrow_end_x = right_rect[0] - 4

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

# Title
draw.text((WIDTH // 2, TITLE_Y), "EasyPaste", fill=ACCENT_COLOR, font=font_title, anchor='mm')

# Subtitle
draw.text((WIDTH // 2, SUBTITLE_Y), "Clipboard Manager for macOS",
          fill=TEXT_COLOR, font=font_subtitle, anchor='mm')

# Left label (just above the left zone)
draw.text((APP_CX, LABEL_Y), "Drag EasyPaste.app",
          fill=TEXT_COLOR, font=font_small, anchor='mm')

# Right label (just above the right zone)
draw.text((APPS_CX, LABEL_Y), "to Applications folder",
          fill=TEXT_COLOR, font=font_small, anchor='mm')

# Bottom instruction
draw.text((WIDTH // 2, BOTTOM_Y), "Close this window to complete installation",
          fill=(100, 105, 115), font=font_small, anchor='mm')

# ── Save ──
img.save(output_path, 'PNG')
print(f"Background saved to {output_path} ({WIDTH}x{HEIGHT}, content-origin, no offset)")
