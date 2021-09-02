# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2020 SUSE LLC
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

package backend::ikvm;

use Mojo::Base -strict;
use autodie ':all';

use base 'backend::ipmi';

sub new {
    my $class = shift;
    return $class->SUPER::new;
}

sub relogin_vnc {
    my ($self) = @_;

    my $vncopts = {
        hostname => $bmwqemu::vars{IPMI_HOSTNAME},
        port     => 5900,
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

sub do_start_vm {
    my ($self) = @_;

    $self->get_mc_status;
    $self->restart_host;
    $self->relogin_vnc;
    $self->truncate_serial_file;
    my $sol = $testapi::distri->add_console('sol', 'ipmi-sol', {serialfile => $self->{serialfile}});
    $sol->activate;
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    $self->deactivate_console({testapi_console => 'sol'});
    return {};
}

1;
