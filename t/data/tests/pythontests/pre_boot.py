# Copyright 2019-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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
