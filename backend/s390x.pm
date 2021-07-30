# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::s390x;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'backend::baseclass';

use English;
require IPC::System::Simple;
use Carp qw(confess cluck carp croak);
use testapi 'get_required_var';

sub new ($class) {
    my $self = $class->SUPER::new;
    get_required_var('WORKER_HOSTNAME');
    return $self;
}

###################################################################
sub do_start_vm ($self) {
    $self->truncate_serial_file;
    my $console = $testapi::distri->add_console('x3270', 's3270');
    $console->backend($self);
    $self->select_console({testapi_console => 'x3270'});

    return 1;
}

sub do_stop_vm ($self) {
    # first kill all _remote_ consoles except for the remote zVM
    # console (which would stop the vm guest)
    my @consoles = keys %{$self->{consoles}};
    for my $console (@consoles) {
        $self->deactivate_console({testapi_console => $console})
          unless $console =~ qr/bootloader|worker/;
    }

    return;
}

sub check_socket ($self, $fh, $write = undef) {
    return $self->check_ssh_serial($fh) || $self->SUPER::check_socket($fh, $write);
}

1;
