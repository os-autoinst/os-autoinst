# Copyright (C) 2017 SUSE LLC
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

use strict;
use warnings;

use base "basetest";

use testapi;

sub run {

    type_string("echo do not wait_still_screen\n", max_interval => 50, wait_still_screen => 0);
    type_string("echo type string and wait for 5 seconds\n",               wait_still_screen => 5);
    type_string("echo test\necho wait\necho 10se\n",                       max_interval      => 100, wait_screen_changes => 11, wait_still_screen => 10);
    type_string("echo test if wait_screen_change functions as expected\n", max_interval      => 150, wait_screen_changes => 11, wait_still_screen => 10);
    type_string("echo wait_still_screen for 20 seconds\n", max_interval => 200, wait_still_screen => 20);
    type_string("echo 'ignore \\r'\r\n");

}

sub test_flags {
    return {};
}

1;

# vim: set sw=4 et:

