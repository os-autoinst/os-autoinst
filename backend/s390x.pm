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

package backend::s390x;

use strict;
use warnings;
use English;
require IPC::System::Simple;
use autodie qw(:all);

use base ('backend::baseclass');

use Carp qw(confess cluck carp croak);

use feature qw/say/;

use testapi qw(get_required_var);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    get_required_var('WORKER_HOSTNAME');
    return $self;
}

###################################################################
sub do_start_vm {
    my ($self) = @_;

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

    $self->unlink_crash_file();
    my $console = $testapi::distri->add_console('x3270', 's3270');
    $console->backend($self);
    $self->select_console({testapi_console => 'x3270'});

    return 1;
}

sub do_stop_vm {
    my ($self) = @_;

    $self->stop_serial_grab;

    #FIXME shutdown
    return 1;

    # first kill all _remote_ consoles except for the remote zVM
    # console (which would stop the vm guest)
    my @consoles = keys %{$self->{consoles}};
    for my $console (@consoles) {
        $self->deactivate_console({testapi_console => $console})
          unless $console =~ qr/bootloader|worker/;
    }

    # now cleanly disconnect from the guest and then kill the local
    # Xvnc
    $self->deactivate_console({testapi_console => 'sut'});
    $self->deactivate_console({testapi_console => 'worker'});
    return;
}

sub status {
    my ($self) = @_;
    # FIXME: do something useful here.
    carp "status not implemented";
}

sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->check_ssh_serial($fh)) {
        return 1;
    }
    return $self->SUPER::check_socket($fh, $write);
}

sub wait_serial {
    my ($self, $args) = @_;

    # make sure it's activated
    # if not activated before, this sshs into the machine
    $testapi::distri->{consoles}->{iucvconn}->select;

    return $self->SUPER::wait_serial($args);
}


1;
