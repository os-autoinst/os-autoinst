# Copyright 2017-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use Feature::Compat::Try;
use testapi;

sub run ($) {
    # Test done this way, because:
    try { assert_screen ['no_tag', 'no_tag2'], timeout => 1, no_wait => 1 }
    catch ($e) { bmwqemu::diag($e) }

    try { assert_screen 'no_tag3', timeout => 1, no_wait => 1 }
    catch ($e) { bmwqemu::diag($e) }
}

1;
