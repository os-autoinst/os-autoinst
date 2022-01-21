# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2015 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshXtermIPMI;

use Mojo::Base 'consoles::localXvnc', -signatures;
use autodie ':all';
require IPC::System::Simple;
use File::Which;

sub activate ($self) {
    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};

    my @command = $self->backend->ipmi_cmdline;
    push(@command, qw(sol activate));
    my $serial = $self->{args}->{serial};
    my $cstr = join(' ', @command);

    # Try to deactivate IPMI SOL before activate
    eval { $self->backend->ipmitool("sol deactivate"); };
    my $ipmi_response = $@;
    if ($ipmi_response) {
        # IPMI response like SOL payload already de-activated is expected
        die "Unexpected IPMI response: $ipmi_response" unless
          ($ipmi_response =~ /SOL payload already de-activated/);
    }

    $self->callxterm($cstr, "ipmitool:$testapi_console");
}

sub reset ($self) {
    # Deactivate sol connection if it is activated
    if ($self->{activated}) {
        $self->backend->ipmitool("sol deactivate");
        $self->{activated} = 0;
    }
    return;
}

sub disable ($self) {
    # Try to deactivate IPMI SOL during disable
    $self->reset;
    $self->SUPER::disable;
}

sub do_mc_reset ($self) {
    if ($self->{activated}) {
        $self->backend->do_mc_reset;
        $self->{activated} = 0;
    }
    return;
}

1;
