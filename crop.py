#!/usr/bin/python
# Copyright (c) 2013 SUSE Linux Products GmbH
# Author: Ludwig Nussel
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

from Tkinter import *
from PIL import Image, ImageTk
import json
import optparse
import sys
import shutil
from pprint import pprint

parser = optparse.OptionParser()
parser.add_option("--new", metavar="NAME", help="create new")
parser.add_option("--tag", metavar="NAME", action='append', help="add tag")

(options, args) = parser.parse_args()

filename = args[0]
if options.new:
	if not filename.endswith('.png'):
		print "Error: needs to end in .png"
		sys.exit(0)

	png = filename
	needle = json.loads("""{
	    "good": [ "FIXME" ], 
	    "height": 100, "width": 100, 
	    "xpos": 0, "ypos": 0
	}""")
	if options.tag:
		needle['good'] = options.tag
else:
	if not filename.endswith('.json'):
		print "Error: needs to end in .json"
		sys.exit(0)

	png = filename[0:len(filename)-len(".json")]+'.png'
	needle = json.load(open(filename))

print json.dumps(needle, sort_keys=True, indent=4)

master = Tk()

image = Image.open(png)
photo = ImageTk.PhotoImage(image)

width = photo.width()
height = photo.height()

w = Canvas(master, width=width, height=height)
w.pack()

bg = w.create_image(0, 0, anchor=NW, image=photo)

crop = w.create_rectangle(needle['xpos'],
		needle['ypos'],
		needle['xpos'] + needle['width'],
		needle['ypos'] + needle['height'],
		outline="yellow")

incr = 5

def resize(arg):
	if arg.keysym == 'Right':
		if width - needle['xpos'] - needle['width'] >= incr:
			needle['width'] = needle['width'] + incr
	elif arg.keysym == 'Left':
		if needle['width'] > incr:
			needle['width'] = needle['width'] - incr
	elif arg.keysym == 'Down':
		if height - needle['ypos'] - needle['height'] >= incr:
			needle['height'] = needle['height'] + incr
	elif arg.keysym == 'Up':
		if needle['height'] > incr:
			needle['height'] = needle['height'] - incr

	w.coords(crop, needle['xpos'], needle['ypos'],
		needle['xpos'] + needle['width'],
		needle['ypos'] + needle['height'])

def move(arg):
	if arg.keysym == 'Right':
		if width - needle['xpos'] - needle['width'] >= incr:
			needle['xpos'] = needle['xpos'] + incr
	elif arg.keysym == 'Left':
		if needle['xpos'] >= incr:
			needle['xpos'] = needle['xpos'] - incr
	elif arg.keysym == 'Down':
		if height - needle['ypos'] - needle['height'] >= incr:
			needle['ypos'] = needle['ypos'] + incr
	elif arg.keysym == 'Up':
		if needle['ypos'] >= incr:
			needle['ypos'] = needle['ypos'] - incr

	w.coords(crop, needle['xpos'], needle['ypos'],
		needle['xpos'] + needle['width'],
		needle['ypos'] + needle['height'])

def increment(arg):
	global incr
	if arg.keysym == 'plus':
		if incr < 100:
			incr = incr + 1
			print "increment changed to %d"%incr
	elif arg.keysym == 'minus':
		if incr > 1:
			incr = incr - 1
			print "increment changed to %d"%incr

def quit(arg):
	print "quit without saving"
	print json.dumps(needle, sort_keys=True, indent=4)
	master.quit()

def save_quit(arg):
	global filename
	if options.new:
		pat = "distri/opensuse/needles/%s.%s"
		shutil.copyfile(filename, pat%(options.new, 'png'))
		filename = pat%(options.new, 'json')
	json.dump(needle, open(filename, 'w'), sort_keys=True, indent=4)
	print "saved %s"%filename
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

print """Use cursor keys to move
Use shift + cursor keys to resize
s = save, q = quit
"""
master.mainloop()
