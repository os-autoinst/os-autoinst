# Copyright 2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::null;

use Mojo::Base -strict;

use base 'backend::baseclass';

sub new { shift->SUPER::new }

sub do_start_vm { {} }

sub do_stop_vm { }

sub run_cmd { }

sub can_handle { }

sub is_shutdown { 1 }

sub stop_serial_grab { }

1;
