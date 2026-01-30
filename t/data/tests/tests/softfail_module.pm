# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use base 'basetest';
use testapi;

sub run ($self) {
    record_soft_failure('failing me softly with this song');
}

1;
