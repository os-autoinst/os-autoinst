# Copyright (C) 2016-2017 SUSE LLC
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
use testapi;

autotest::loadtest "tests/boot.pm";

unless (get_var('INTEGRATION_TESTS')) {
    autotest::loadtest "tests/assert_screen_fail_test.pm";
}

autotest::loadtest "tests/shutdown.pm";

1;

# vim: set sw=4 et:
