# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package backend::ikvm;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'backend::ipmi';

sub new ($class) { $class->SUPER::new }

sub relogin_vnc ($self) {
    my $vncopts = {
        hostname => $bmwqemu::vars{IPMI_HOSTNAME},
        port => 5900,
        username => $bmwqemu::vars{IPMI_USER},
        password => $bmwqemu::vars{IPMI_PASSWORD},
    };
    my $hwclass = $bmwqemu::vars{IPMI_HW} || 'supermicro';
    $vncopts->{ikvm} = 1 if $hwclass eq 'supermicro';
    if ($hwclass eq 'dell') {
        $vncopts->{dell} = 1;
        $vncopts->{port} = 5901;
    }
    my $vnc = $testapi::distri->add_console('sut', 'vnc-base', $vncopts);
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    return 1;
}

sub do_start_vm ($self, @) {
    $self->get_mc_status;
    $self->restart_host;
    $self->relogin_vnc;
    $self->truncate_serial_file;
    my $sol = $testapi::distri->add_console('sol', 'ipmi-sol', {serialfile => $self->{serialfile}});
    $sol->activate;
    return {};
}

sub do_stop_vm ($self, @) {
    $self->ipmitool("chassis power off");
    $self->deactivate_console({testapi_console => 'sol'});
    return {};
}

1;
