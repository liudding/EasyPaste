"""Write .DS_Store for the EasyPaste DMG installer volume.

Sets up:
- Finder window bounds (500×360)
- Icon view with 80px icons, bottom label position
- Background picture: .background:background.png
- Icon positions: EasyPaste.app at (150,110), Applications at (270,110)
  (both centered vertically at y=150 and symmetric about x=250)

Usage: python write_dmg_dsstore.py /Volumes/EasyPaste Installer
"""
import sys
import os
import plistlib
from ds_store import DSStore, DSStoreEntry

mount_dir = sys.argv[1]
ds_path = os.path.join(mount_dir, '.DS_Store')

# Build initial entries list
entries = []

# ── Window bounds (modern Finder: bwsp is a binary plist) ──
# 500×360 window. Must match WIDTH/HEIGHT in generate_dmg_background.py.
# The key set is matched exactly to what Finder itself writes (verified against
# real .DS_Store files on this Mac); a missing/extra key makes Finder ignore
# the blob and fall back to a large default window.
bwsp_dict = {
    'WindowBounds': '{{100, 100}, {250, 360}}',
    'ShowStatusBar': False,
    'ShowToolbar': False,
    'ShowTabView': False,
    'ContainerShowSidebar': False,
    'ShowSidebar': False,
    'ShowPathbar': False,
}
bwsp_entry = DSStoreEntry('', 'bwsp', 'blob',
    plistlib.dumps(bwsp_dict, fmt=plistlib.FMT_BINARY))
entries.append(bwsp_entry)

# ── Icon view properties ──
# icvp is a plist blob with icon size, arrangement, background, etc.
icvp_dict = {
    'viewIconSize': 80,
    'labelOnBottom': True,
    'arrangeBy': None,   # None (= no arrangement) so manual Iloc positions are honored
    'showIconPreview': True,
    'showItemInfo': True,
    'backgroundType': 2,  # 2 = picture
    'backgroundImageAlias': None,
    'backgroundImagePath': '.background:background.png',
}
icvp_blob = plistlib.dumps(icvp_dict, fmt=plistlib.FMT_BINARY)
icvp_entry = DSStoreEntry('', 'icvp', 'blob', icvp_blob)
entries.append(icvp_entry)

# ── Icon positions ──
# Iloc is encoded as (x, y) — big-endian 4-byte ints
def make_iloc(x, y):
    return x.to_bytes(4, 'big', signed=True) + y.to_bytes(4, 'big', signed=True)

# Icons centered as a group inside the 250-wide window:
#   app  top-left (36,114)  → center (76,154)
#   apps top-left (134,114) → center (174,154)
# Group is horizontally centered (centers 76 & 174, midpoint 125 = 250/2) and
# vertically centered in the visible content area (window 360 minus ~52px title
# bar → visible center y≈154). Must match APP_CX/APP_CY in generate_dmg_background.py.
iloc_app = DSStoreEntry('EasyPaste.app', 'Iloc', 'blob', make_iloc(36, 114))
iloc_apps = DSStoreEntry('Applications', 'Iloc', 'blob', make_iloc(134, 114))
entries.append(iloc_app)
entries.append(iloc_apps)

# Remove existing .DS_Store if present
if os.path.exists(ds_path):
    os.remove(ds_path)

# Write the new .DS_Store
with DSStore.open(ds_path, 'w+', initial_entries=entries) as d:
    pass  # entries already written during init

print(f".DS_Store written to {ds_path}")
