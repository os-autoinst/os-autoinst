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

use 5.018;
use base 'basetest';
use testapi;

sub run {
    wait_idle 1;
    type_string "sudo su\n";
    type_string "poweroff\n";
    if (get_var('INTEGRATION_TESTS')) {
        assert_shutdown(90);
    }
    else {
        assert_shutdown;
    }
}

sub test_flags {
    return {fatal => 1};
}

1;
