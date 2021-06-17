# Copyright (C) 2019-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

import sys

print(sys.path)
from testapi import *


def run(self):
    send_key("esc")
    if not check_screen("should_not_match", 0):
        return
    raise Exception("Should not reach here")


def test_flags(self):
    return dict([("fatal", 1)])
