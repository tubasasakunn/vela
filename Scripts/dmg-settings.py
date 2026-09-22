"""Finder layout; dmgbuild creates background aliases on the actual image."""

import os

application = os.path.abspath(defines["app"])
files = [application]
symlinks = {"Applications": "/Applications"}
background = os.path.abspath(defines["background"])
format = "UDZO"
filesystem = "HFS+"
window_rect = ((160, 120), (560, 360))
icon_locations = {os.path.basename(application): (160, 170), "Applications": (400, 170)}
icon_size = 96
text_size = 13
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
