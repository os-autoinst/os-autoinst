# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Backend;
use Mojo::Base -base, -signatures;

use Mojo::File qw(path);
use backend::driver;
use bmwqemu;
use log qw(diag);

sub new ($class, @args) {
    $bmwqemu::vars{BACKEND} ||= "qemu";
    $bmwqemu::backend = backend::driver->new($bmwqemu::vars{BACKEND});

    path('os-autoinst.pid')->spew("$$");
    # might throw an exception
    $bmwqemu::backend->start_vm;
    $class->SUPER::new(@args);
}

sub process ($self) {
    $bmwqemu::backend->{backend_process};
}

sub stop ($self) {
    return undef unless my $process = $self->process;
    diag('stopping backend process ' . $process->pid);
    $process->stop if $process->is_running;
    diag('done with backend process');
}

1;
