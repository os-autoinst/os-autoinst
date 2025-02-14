# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($) {
    # enter_cmd 'sudo poweroff';
    # power('acpi');
    power('off');
    # assert_shutdown(get_var('INTEGRATION_TESTS') ? 90 : undef);
    # assert_shutdown(120);
}

sub test_flags ($) { {fatal => 1} }

1;
