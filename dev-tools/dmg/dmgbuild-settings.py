import os

DMG_DIR = os.environ.get("DMG_DIR", "/Users/malpern/local-code/KeyPath/dev-tools/dmg")
APP_PATH = os.environ.get("DMG_APP_PATH", "/Users/malpern/local-code/KeyPath/dist/KeyPath.app")

volume_name = "KeyPath"
format = "UDZO"
filesystem = "HFS+"

window_rect = ((200, 120), (660, 400))
icon_size = 128
text_size = 14

background = os.path.join(DMG_DIR, "dmg-background-light@2x.png")
background_dark = os.path.join(DMG_DIR, "dmg-background-dark@2x.png")

files = [APP_PATH]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["KeyPath.app"]

icon_locations = {
    os.path.basename(APP_PATH): (175, 200),
    "Applications": (485, 200),
}
