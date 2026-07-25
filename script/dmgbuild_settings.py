"""dmgbuild settings for the EasyPaste installer DMG.

dmgbuild exec's this file with its options dict as the exec namespace, so each
setting must be a flat top-level assignment (e.g. `files = [...]`), NOT a
`settings = {...}` dict. dmgbuild then emits a Finder-valid .DS_Store (correct
root key, real background alias, arrangeBy='none'), so the layout is actually
honored when the DMG opens.

Invoked from script/create_dmg.sh via:
    dmgbuild -s script/dmgbuild_settings.py EasyPaste dist/EasyPasteInstaller.dmg
"""
import os

# dmgbuild exec's this file without __file__, so use the known absolute path.
PROJECT_DIR = "/Users/ding/Projects/apps/easypaste"
APP = os.path.join(PROJECT_DIR, "dist", "EasyPaste.app")
BG = os.path.join(PROJECT_DIR, "dist", "dmg_background.png")

# Icon group is centered in the CONTENT area (600 x 372, i.e. full window
# 600x400 minus the 28pt title bar). Content center = (300, 186).
#   80px icons; combined bbox x 200..400 (cx 300), y 146..226 (cy 186).
#   app  top-left (200, 146) -> center (240, 186)
#   apps top-left (320, 146) -> center (360, 186)
# Mirrors the placeholder centers drawn in script/generate_dmg_background.py.
icon_locations = {
    "EasyPaste.app": (200, 146),
    "Applications": (320, 146),
}

title = "EasyPaste"
format = "UDZO"
size = None  # None -> dmgbuild auto-computes the size string from the files
files = [APP]
symlinks = {"Applications": "/Applications"}
background = BG
icon_size = 80
icon_locations = icon_locations
# ((origin_x, origin_y), (width, height))
window_rect = ((100, 100), (600, 400))
show_statusbar = False
show_tabview = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
# None -> dmgbuild writes arrangeBy='none' (manual Iloc positions honored)
arrange_by = None
