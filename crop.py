#!/usr/bin/env python
# Copyright (c) 2013-2016 SUSE LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

from Tkinter import Tk, Canvas, NW
from PIL import Image, ImageTk
import json
import optparse
import sys
import shutil
from os.path import basename

parser = optparse.OptionParser()
parser.add_option("--new", metavar="NAME", help="create new")
parser.add_option("--tag", metavar="NAME", action='append', help="add tag")

(options, args) = parser.parse_args()

filename = args[0]
if filename.endswith('.png'):
    png = filename
    filename = filename[0:len(filename) - len(".png")] + '.json'
    needle = json.loads("""{
        "tags": [ "FIXME" ],
        "area": [ { "height": 100, "width": 100,
        "xpos": 0, "ypos": 0, "type": "match" } ]
    }""")
elif filename.endswith('.json'):
    png = filename[0:len(filename) - len(".json")] + '.png'
    needle = json.load(open(filename))

else:
    print("Error: needs to end in .png or .json")
    sys.exit(0)

if options.tag:
    needle['tags'] = options.tag

print(json.dumps(needle, sort_keys=True, indent=4, separators=(',', ': ')))

master = Tk()
master.title(basename(filename)[0:len(filename) - len(".json")])

image = Image.open(png)
photo = ImageTk.PhotoImage(image)

width = photo.width()
height = photo.height()

w = Canvas(master, width=width, height=height)
w.pack()

bg = w.create_image(0, 0, anchor=NW, image=photo)

uiareas = []


class UiArea:
    def __init__(self, w, area):
        self.color = "cyan"
        self.w = w
        self.rect = w.create_rectangle(
            area['xpos'], area['ypos'],
            area['xpos'] + area['width'],
            area['ypos'] + area['height'],
            outline=self.color)
        self.text = w.create_text(area['xpos'] + area['width'], area['ypos'] + area['height'],
                                  anchor="se", text=area['type'],
                                  fill=self.color)
        self.line = None
        self._update_exclude(area)

    def _update_exclude(self, area):
        if area['type'] == 'exclude' and self.line is None:
            self.line = w.create_line(
                area['xpos'],
                area['ypos'] + area['height'], area['xpos'] + area['width'],
                area['ypos'],
                fill=self.color)
        if area['type'] != 'exclude' and self.line is not None:
            self.w.delete(self.line)
            self.line = None

    def setcolor(self, color):
        self.color = color
        self.w.itemconfig(self.rect, outline=color)
        self.w.itemconfig(self.text, fill=color)
        if self.line is not None:
            self.w.itemconfig(self.line, fill=color)

    def updatearea(self, area):
        self.w.coords(self.rect, area['xpos'], area['ypos'],
                      area['xpos'] + area['width'],
                      area['ypos'] + area['height'])
        self.w.coords(self.text, area['xpos'] + area['width'], area['ypos'] + area['height'])
        if self.line:
            self.w.coords(self.line, area['xpos'], area['ypos'] + area['height'],
                          area['xpos'] + area['width'],
                          area['ypos'])

    def updatetype(self, area):
        self.w.itemconfig(self.text, text=area['type'])
        self._update_exclude(area)

    def destroy(self):
        self.w.delete(self.rect)
        self.w.delete(self.text)
        if self.line is not None:
            self.w.delete(self.line)


for area in needle['area']:
    # make sure we have ints
    for s in ('xpos', 'ypos', 'width', 'height'):
        area[s] = int(area[s])
    uiareas.append(UiArea(w, area))

rect = 0


def selectarea():
    global uiareas, rect, area

    print("highlighting %d" % rect)

    area = needle['area'][rect]
    for r in range(0, len(uiareas)):
        color = "green"
        if r == rect:
            color = "cyan"
        uiareas[r].setcolor(color)

selectarea()

incr = 5


def resize(arg):
    if arg.keysym == 'Right':
        if width - area['xpos'] - area['width'] >= incr:
            area['width'] = area['width'] + incr
        elif area['width'] > incr:
            area['xpos'] = area['xpos'] + incr
            area['width'] = area['width'] - incr
    elif arg.keysym == 'Left':
        if area['width'] > incr:
            area['width'] = area['width'] - incr
    elif arg.keysym == 'Down':
        if height - area['ypos'] - area['height'] >= incr:
            area['height'] = area['height'] + incr
        elif area['height'] > incr:
            area['ypos'] = area['ypos'] + incr
            area['height'] = area['height'] - incr
    elif arg.keysym == 'Up':
        if area['height'] > incr:
            area['height'] = area['height'] - incr

    uiareas[rect].updatearea(area)


def move(arg):
    if arg.keysym == 'Right':
        if width - area['xpos'] - area['width'] >= incr:
            area['xpos'] = area['xpos'] + incr
    elif arg.keysym == 'Left':
        if area['xpos'] >= incr:
            area['xpos'] = area['xpos'] - incr
    elif arg.keysym == 'Down':
        if height - area['ypos'] - area['height'] >= incr:
            area['ypos'] = area['ypos'] + incr
    elif arg.keysym == 'Up':
        if area['ypos'] >= incr:
            area['ypos'] = area['ypos'] - incr

    uiareas[rect].updatearea(area)


def switch(arg):
    global rect
    rect = (rect + 1) % len(uiareas)
    selectarea()


def addrect(arg):
    global rect, area, uiareas, needle
    rect = len(needle['area'])
    needle['area'].append({"height": 100, "width": 100,
                           "xpos": 0, "ypos": 0, "type": "match"})
    area = needle['area'][rect]
    uiareas.append(UiArea(w, area))

    selectarea()


def delrect(arg):
    global rect, area, uiareas, needle
    if len(uiareas) <= 1:
        return
    del needle['area'][rect]
    uiareas[rect].destroy()
    a = []
    for r in range(0, len(uiareas)):
        if r == rect:
            continue
        a.append(uiareas[r])
    uiareas = a
    rect = rect % len(uiareas)
    selectarea()


def changetype(arg):
    types = ('match', 'exclude', 'ocr')
    global rect, area, uiareas, needle
    area['type'] = types[(types.index(area['type']) + 1) % len(types)]
    uiareas[rect].updatetype(area)


def increment(arg):
    global incr
    if arg.keysym == 'plus':
        if incr < 100:
            incr = incr + 1
            print("increment changed to %d" % incr)
    elif arg.keysym == 'minus':
        if incr > 1:
            incr = incr - 1
            print("increment changed to %d" % incr)


def quit(arg):
    print("quit without saving")
    print(json.dumps(needle, sort_keys=True, indent=4, separators=(',', ': ')))
    master.quit()


def save_quit(arg):
    global filename
    if options.new:
        from os import environ
        if 'CASEDIR' not in environ:
            environ['CASEDIR'] = 'distri/opensuse'
        pat = environ['CASEDIR'] + "/needles/%s.%s"
        shutil.copyfile(png, pat % (options.new, 'png'))
        filename = pat % (options.new, 'json')
    json.dump(needle, open(filename, 'w'), sort_keys=True, indent=4, separators=(',', ': '))
    print("saved %s" % filename)
    master.quit()

master.bind('<Shift-Up>', resize)
master.bind('<Shift-Down>', resize)
master.bind('<Shift-Left>', resize)
master.bind('<Shift-Right>', resize)
master.bind('<Up>', move)
master.bind('<Down>', move)
master.bind('<Left>', move)
master.bind('<Right>', move)
master.bind('+', increment)
master.bind('-', increment)
master.bind('s', save_quit)
master.bind('q', quit)
master.bind('<Escape>', quit)
master.bind('<Tab>', switch)
master.bind('<Insert>', addrect)
master.bind('<Delete>', delrect)
master.bind('t', changetype)

print("""Use cursor keys to move
Use shift + cursor keys to resize
+/-: Change increment for move/resize

t = change type
ins = add area, del = remove area
<TAB>: select next area

s = save, q = quit
""")
master.mainloop()
