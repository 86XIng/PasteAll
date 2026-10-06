# dmgbuild settings for the PasteAll disk image. Used by scripts/package-unsigned.sh:
#   dmgbuild -s packaging/dmg/dmg-settings.py -D settings_dir=packaging/dmg \
#            -D app=<PasteAll.app> -D guide=<guide.rtf> "PasteAll <version>" <out.dmg>
# Layout: a light gray background with a dashed arrow (make-background.swift)
# between PasteAll and Applications, and the install guide above them.
import os.path

app = defines["app"]  # noqa: F821 - provided by dmgbuild
guide = defines["guide"]  # noqa: F821
guide_name = os.path.basename(guide)

format = "UDZO"
filesystem = "HFS+"
files = [app, guide]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
# dmgbuild also picks up background@2x.png for Retina displays.
background = os.path.join(defines["settings_dir"], "background.png")  # noqa: F821
# Finder hides ".app" by default. Hiding it explicitly would write Finder info
# onto the bundle, which fails strict code signature checks after copying.
hide_extensions = [guide_name]

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
# The path bar shows the volume name, including the version, at the bottom.
show_pathbar = True
show_sidebar = False
window_rect = ((200, 120), (560, 380))
icon_size = 80
text_size = 13
# The arrow in the background is centered at (280, 236).
icon_locations = {
    guide_name: (280, 90),
    "PasteAll.app": (130, 236),
    "Applications": (430, 236),
}
