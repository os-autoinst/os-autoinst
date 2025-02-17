# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($) {
    power 'off';
    assert_shutdown(get_var('INTEGRATION_TESTS') ? 90 : undef);
    sleep 2;  # TODO this causes autotest to take a little bit longer causing: [2025-02-17T13:05:51.891245+01:00] [warn] [pid:25301] !!! OpenQA::Isotovideo::Runner::_read_response: THERE IS NOTHING TO READ 17 4 3
    # TODO we need to find a way to give clear feedback to test writers that
    # one must not execute any more commands after power off *and* handle the
    # case when autotest just takes a little bit longer
    #assert_screen 'foo';
}

sub test_flags ($) { {fatal => 1} }

1;
