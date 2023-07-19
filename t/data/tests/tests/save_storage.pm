# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;


sub run ($) {
    save_storage;
}

sub test_flags ($) { {fatal => 1} }

1;
