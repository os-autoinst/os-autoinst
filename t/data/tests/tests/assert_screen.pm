# Copyright 2016-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($) {
    # different variants of parameter selection
    assert_screen 'on_prompt', timeout => 60;
    assert_screen 'on_prompt', no_wait => 1;
}

1;

