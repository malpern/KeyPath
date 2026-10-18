import os

DMG_DIR = os.environ.get("DMG_DIR", "/Users/malpern/local-code/KeyPath/dev-tools/dmg")
APP_PATH = os.environ.get("DMG_APP_PATH", "/Users/malpern/local-code/KeyPath/dist/KeyPath.app")

volume_name = "KeyPath"
format = "UDZO"
filesystem = "HFS+"

# Include Finder's 32-point title bar above the 660x400 background canvas.
window_rect = ((200, 120), (660, 432))
icon_size = 96
text_size = 13

background = os.environ.get("DMG_BACKGROUND", os.path.join(DMG_DIR, "installer-branded@2x.png"))
background_dark = os.path.join(DMG_DIR, "installer-branded@2x.png")

files = [APP_PATH]
symlinks = {"Applications": "/Applications"}
# Hiding extensions writes com.apple.FinderInfo onto the signed bundle,
# which fails codesign --verify --strict after packaging.
hide_extensions = []

icon_locations = {
    os.path.basename(APP_PATH): (505, 112),
    "Applications": (505, 288),
}
