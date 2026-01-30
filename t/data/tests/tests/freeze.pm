# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use base 'basetest';
use testapi;

sub run ($) {
    freeze_vm();
    diag "Simply freeze the vm and resume right before the first assert screen is done";
    resume_vm();
}

1;
