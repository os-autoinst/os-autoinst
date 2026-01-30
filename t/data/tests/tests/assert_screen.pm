# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use base 'basetest';
use testapi;

sub run ($) {
    # different variants of parameter selection
    assert_screen 'on_prompt', timeout => 60;
    assert_screen 'on_prompt', no_wait => 1;
}

1;

