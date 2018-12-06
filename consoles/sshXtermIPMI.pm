# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package consoles::sshXtermIPMI;
use base 'consoles::localXvnc';
use strict;
use warnings;
use testapi 'get_required_var';
require IPC::System::Simple;
use autodie ':all';
use File::Which;
use testapi 'get_var';

sub activate {
    my ($self) = @_;

    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};

    my $cstr = "";


    ############## Following snippet will be splitted into separate functions 
    ############## to simplify implementation and standardize development method
    #############  New function sub mc_reset will be needed
    my @command_reset_tmp = $self->backend->ipmi_cmdline;
    push(@command_reset_tmp, qw(mc reset cold));
    my $command_reset     = join(' ', @command_reset_tmp);

    my @command_sleep_tmp = "sleep";
    push(@command_sleep_tmp, qw(50));
    my $command_sleep     = join(' ', @command_sleep_tmp);

    my $bmcipaddr         = get_var('IPMI_HOSTNAME');
    if ($bmcipaddr eq '') {
        die "BMC IP address is not defined.";
    }
    my @command_ping_tmp_1  = "(for i in `seq 100`; do /usr/bin/ping -c1";
    push(@command_ping_tmp_1, $bmcipaddr);
    my $command_ping_tmp_2  = "; if [";
    push(@command_ping_tmp_1, $command_ping_tmp_2);
    push(@command_ping_tmp_1, qw($?));
    my $command_ping_tmp_3  = "-ne '0' ]; then break; else sleep 5; fi; done;)";
    push(@command_ping_tmp_1, $command_ping_tmp_3);

    my @command_ping_tmp_4  = "(for i in `seq 100`; do /usr/bin/ping -c1";
    push(@command_ping_tmp_4, $bmcipaddr);
    my $command_ping_tmp_5  = "; if [";
    push(@command_ping_tmp_4, $command_ping_tmp_5);
    push(@command_ping_tmp_4, qw($?));
    my $command_ping_tmp_6  = "-eq '0' ]; then break; else sleep 5; fi; done;)";
    push(@command_ping_tmp_4, $command_ping_tmp_6);
    #my $command_ping      = join(' ', @command_ping_tmp_4);
    my $command_ping_1      = join(' ', @command_ping_tmp_1);
    my $command_ping_2      = join(' ', @command_ping_tmp_4);
    my $command_ping        = join(';', $command_ping_1, $command_ping_2);

    my @command_deactivate_tmp = $self->backend->ipmi_cmdline;
    push(@command_deactivate_tmp, qw(sol deactivate));
    my $command_deactivate     = join(' ', @command_deactivate_tmp); 

    my @command_activate_tmp = $self->backend->ipmi_cmdline;
    push(@command_activate_tmp, qw(sol activate));
    my $command_activate     = join(' ', @command_activate_tmp); 
    #$cstr = join(' ; ', $command_reset, $command_sleep, $command_deactivate, $command_activate);
    $cstr = join(' ; ', $command_reset, $command_ping, $command_sleep, $command_deactivate, $command_sleep, $command_activate);

    bmwqemu::diag "ipmicmdline is $cstr";

    my $serial = $self->{args}->{serial};
    $self->callxterm($cstr, "ipmitool:$testapi_console");
}

sub reset {
    my ($self) = @_;

    # Deactivate sol connection if it is activated
    if ($self->{activated}) {
        $self->backend->ipmitool("sol deactivate");
        $self->{activated} = 0;
    }
    return;
}

sub mc_reset {
    my ($self) = @_;

    # Reset mc it necessary
    $self->backend->ipmitool("mc reset cold");
    $self->{activated} = 0;
    return;
}

1;
