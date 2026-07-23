"""Write .DS_Store for the EasyPaste DMG installer volume.

Sets up:
- Finder window bounds (660×400)
- Icon view with 80px icons, bottom label position
- Background picture: .background:background.png
- Icon positions: EasyPaste.app at (160,180), Applications at (500,180)

Usage: python write_dmg_dsstore.py /Volumes/EasyPaste Installer
"""
import sys
import os
from ds_store import DSStore, DSStoreEntry

mount_dir = sys.argv[1]
ds_path = os.path.join(mount_dir, '.DS_Store')

# Build initial entries list
entries = []

# ── Window bounds: {left, top, right, bottom} ──
bwsp_entry = DSStoreEntry('', 'bwsp', 'blob',
    b'\x00\x00\x00\x00\x00\x00\x00\x00'   # left, top
    b'\x00\x00\x02\x94\x00\x00\x01\x90'   # right=660, bottom=400
)
entries.append(bwsp_entry)

# ── Icon view properties ──
# icvp is a plist blob with icon size, arrangement, background, etc.
import plistlib

icvp_dict = {
    'viewIconSize': 80,
    'iconSize': 80,
    'labelOnBottom': True,
    'arrangeBy': 'none',
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

iloc_app = DSStoreEntry('EasyPaste.app', 'Iloc', 'blob', make_iloc(160, 180))
iloc_apps = DSStoreEntry('Applications', 'Iloc', 'blob', make_iloc(500, 180))
entries.append(iloc_app)
entries.append(iloc_apps)

# Remove existing .DS_Store if present
if os.path.exists(ds_path):
    os.remove(ds_path)

# Write the new .DS_Store
with DSStore.open(ds_path, 'w+', initial_entries=entries) as d:
    pass  # entries already written during init

print(f".DS_Store written to {ds_path}")
