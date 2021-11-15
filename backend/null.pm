# Copyright 2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::null;

use Mojo::Base -strict, -signatures;

use base 'backend::baseclass';

sub new ($self) { $self->SUPER::new }

sub do_start_vm ($self, @) { {} }

sub do_stop_vm ($self, @) { }

sub do_extract_assets ($self, @) { }

sub run_cmd ($self, @) { }

sub can_handle ($self, @) { }

sub is_shutdown ($self, @) { 1 }

sub stop_serial_grab ($self, @) { }

1;
