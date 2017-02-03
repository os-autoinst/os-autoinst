# Copyright (C) 2016 SUSE LLC
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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use base "basetest";
use strict;
use testapi;

sub run {
    # just assume the first screen has a timeout so we should make sure not to miss it
    assert_screen 'core', 15, no_wait => 1;
    # different variants of parameter selection
    assert_screen 'core', timeout => 60;
    assert_screen 'core', no_wait => 1, abort_on_stall => 1;
    send_key 'ret';

    assert_screen 'on_prompt';

    assert_script_run "cat /proc/cpuinfo";
}

sub test_flags {
    return {important => 1};
}

1;

# vim: set sw=4 et:

