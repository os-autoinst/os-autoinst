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
use warnings;

use testapi;
use testdistribution;

testapi::set_distribution(testdistribution->new());

sub unregister_needle_tags {
    my ($tag) = @_;
    my @a = @{needle::tags($tag)};
    for my $n (@a) { $n->unregister($tag); }
}

sub cleanup_needles {
    unregister_needle_tags("ENV-VERSION-2") if check_var('VERSION', '1');
    unregister_needle_tags("ENV-VERSION-1") unless check_var('VERSION', '1');
}

$needle::cleanuphandler = \&cleanup_needles;

autotest::loadtest "tests/boot.pm";

# openQA tests set this to 0 when reusing the os-autoinst tests
unless (get_var('INTEGRATION_TESTS')) {
    autotest::loadtest "tests/select_console_fail_test.pm";
    autotest::loadtest "tests/assert_screen_fail_test.pm";
    autotest::loadtest "tests/typing.pm";
    autotest::loadtest "tests/reload_needles.pm";
    autotest::loadtest "tests/modify_and_upload_file.pm";
}
autotest::loadtest "tests/shutdown.pm";

1;

# vim: set sw=4 et:
