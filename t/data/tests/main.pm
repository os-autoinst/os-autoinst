# Copyright 2016-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use Cwd 'abs_path';

use testapi;
use testdistribution;

my $distri = testdistribution->new();
testapi::set_distribution($distri);

sub unregister_needle_tags ($tag) {
    my @a = @{needle::tags($tag)};
    for my $n (@a) { $n->unregister($tag); }
}

sub cleanup_needles () {
    unregister_needle_tags("ENV-VERSION-2") if check_var('VERSION', '1');
    unregister_needle_tags("ENV-VERSION-1") unless check_var('VERSION', '1');
}

$needle::cleanuphandler = \&cleanup_needles;

# openQA tests set INTEGRATION_TESTS to 1 when reusing the os-autoinst tests
my $integration_tests = get_var('INTEGRATION_TESTS');

autotest::loadtest "tests/freeze.pm" unless $integration_tests;

# Add import path for local test python modules from pool directory
unless ($integration_tests) {
    use Inline Python => "import os.path, sys; sys.path.insert(0, os.path.abspath(os.path.join(os.path.curdir, '../..')))";
    autotest::loadtest "tests/pre_boot.py";
}

autotest::loadtest "tests/boot.pm";
autotest::loadtest "tests/assert_screen.pm";
unless ($integration_tests) {
    autotest::loadtest "tests/save_storage.pm";
    autotest::loadtest "tests/typing.pm";
    autotest::loadtest "tests/select_console_fail_test.pm";
    autotest::loadtest "tests/select_ssh_console_fail_test.pm";
    autotest::loadtest "tests/assert_screen_fail_test.pm";
    autotest::loadtest "tests/reload_needles.pm";
    autotest::loadtest "tests/modify_and_upload_file.pm";
}
autotest::loadtest "tests/shutdown.pm";

1;
