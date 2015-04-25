#!/usr/bin/python3
# Copyright (C) 2015 Susanne Oberhauser-Hirschoff <froh@suse.de>
# The MIT License applies (http://opensource.org/licenses/MIT)

"""start an xterm that looks like a linux console


    # do this once, to let the xserver know about the fonts
    xset fp+ $(pwd)

    # for each font you want to try...
    gunzip -c /usr/share/kbd/consolefonts/lat9w-16.psfu.gz | perl psf2bdf.pl > lat9w-16.bdf

    sed -i -e s,-psf-,lat9w_16, lat9w-16.bdf

    # update the fonts.dir file
    mkfontdir
    # notify X about the new font
    xset fp rehash

    # have a look :)
    # start an xterm with the right colors and all, script is attached [3]
    python3 xterm_linux_vt.py

"""

# from pprint import pprint as pp
default_kernel_vt_colors = {}
RGB = ("red", "grn", "blu")
for cname in RGB:
    with open("/sys/module/vt/parameters/default_{}".format(cname)) as f:
        colors = f.read().rstrip().split(',')
        default_kernel_vt_colors[cname] = map(int, colors)

xterm_colors= list()

for r, g, b in zip(*(default_kernel_vt_colors[c] for c in RGB)):
    xterm_colors.append("rgb:{r:02x}/{g:02x}/{b:02x}".format(**locals()))

def xtc(label, color):
    return ("-xrm", "xterm*{label}: {color}".format(**locals()))

def xrm_color_options():
    yield(xtc("foreground", xterm_colors[7]))
    yield(xtc("background", xterm_colors[0]))
    for i, c in enumerate(xterm_colors):
        yield(xtc("color{}".format(i), c))

from itertools import chain

import os

xx = [
    "xterm",
    # console font
    "-fn", "lat9w_16",
    "-fullscreen",
    # no scrollbar
    "+sb",
    # no border
    "-b", "0",
    # blinking underline cursor
    "-bc", "-uc", "-bcf", "200", "-bcn", "200",
    # intense colors for bold, italics
    "+bdc", "+itc",
    # intense for bold...
    "-xrm", "xterm*boldMode: false",
]

import sys # for argv
sys.argv.pop(0) # strip command name
xx.extend(chain(*xrm_color_options()))
xx.extend(sys.argv)
os.execvp("xterm", xx)
