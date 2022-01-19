# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run {
    type_string "sudo su\n";
    type_string "poweroff\n";
    assert_shutdown(get_var('INTEGRATION_TESTS') ? 90 : undef);
}

sub test_flags {
    return {fatal => 1};
}

1;
