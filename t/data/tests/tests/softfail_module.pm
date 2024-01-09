# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base 'basetest', -signatures;
use testapi;

sub run ($self) {
    record_soft_failure('failing me softly with this song');
}

1;
