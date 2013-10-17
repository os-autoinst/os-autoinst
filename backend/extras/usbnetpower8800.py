#!/usr/bin/env python

# Copyright (C) 2011  Paul Marks  http://www.pmarks.net/
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Project homepage: http://code.google.com/p/usbnetpower8800/
#
# This is a simple command-line tool for controlling the "USB Net Power 8800"
# from Linux (etc.) using Python and PyUSB.  It shows up under lsusb as:
#
#     ID 067b:2303 Prolific Technology, Inc. PL2303 Serial Port
#
# But, from what I can tell, none of the serial port features are ever used,
# and all you really need is one USB control transfer for reading the current
# state, and another for setting it.
#
# The device is basically a box with a USB port and a switchable power outlet.
# It has the unfortunate property that disconnecting it from USB immediately
# kills the power, which reduces its usefulness.
#
# To install Python and usb.core on Ubuntu:
#  $ sudo apt-get install python python-setuptools
#  $ sudo easy_install pyusb
# To install Python and usb.core on openSUSE:
#  $ sudo zypper -n in python-usb
#
# If you have a permission error using the script and udev is used on your
# system, it can be used to apply the correct permissions. Example:
#  $ cat /etc/udev/rules.d/51-usbpower.rules
#  SUBSYSTEM=="usb", ATTR{idVendor}=="067b", MODE="0666", GROUP="plugdev"


import sys
import usb.core
import time

usage = (
    "Controller for the USB Net Power 8800\n"
    "Usage: %s on|off|toggle|query\n")


class Power(object):
    def __init__(self):
        # Find the device.
        self.dev = usb.core.find(idVendor=0x067b, idProduct=0x2303)
        if self.dev is None:
            raise ValueError("Device not found")

    def IsOn(self):
        # Return True if the power is currently switched on.
        ret = self.dev.ctrl_transfer(0xc0, 0x01, 0x0081, 0x0000, 0x0001)
        return ret[0] == 0xa0

    def Set(self, on):
        # If True, turn the power on, else turn it off.
        code = 0xa0 if on else 0x20
        self.dev.ctrl_transfer(0x40, 0x01, 0x0001, code, [])


def main(argv):
    try:
        cmd = argv[1].lower()
    except IndexError:
        cmd = ""

    power = Power()

    if cmd == "on":
        power.Set(True)
    elif cmd == "off":
        power.Set(False)
    elif cmd == "toggle":
        power.Set(not power.IsOn())
    elif cmd == "query":
        on = power.IsOn()
        sys.stdout.write("Power: %s\n" % ("on" if on else "off"))
        return 0 if on else 1
    elif cmd == "cycle":
        on = power.IsOn()
        if on:
	    power.Set(False)
	    time.sleep(10)
	power.Set(True)
    else:
        sys.stdout.write(usage % argv[0])
        return -1
    return 0


if '__main__' == __name__:
    ret = main(sys.argv)
    sys.exit(ret)
