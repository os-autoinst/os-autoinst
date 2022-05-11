# Copyright 2016-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($) {
    # just assume the first screen has a timeout so we should make sure not to miss it
    assert_screen 'core', 15, no_wait => 1;
    send_key 'ret';

    # set timeout to 10 minutes so we can't miss the situation when we're waiting for the assert_screen to timeout
    # (test uses 'Skip timeout' so this won't actually delay the test execution)
    assert_screen 'on_prompt', timeout => get_var('TESTING_ASSERT_SCREEN_TIMEOUT') ? 600 : 90;
}

sub test_flags ($) { {} }

1;
