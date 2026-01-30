# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use base 'basetest';
use testapi;

sub run ($) {
    select_console 'brokenvnc';
}

1;
