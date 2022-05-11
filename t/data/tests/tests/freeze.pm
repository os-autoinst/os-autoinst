# Copyright 2016-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($) {
    freeze_vm();
    diag "Simply freeze the vm and resume right before the first assert screen is done";
    resume_vm();
}

1;
