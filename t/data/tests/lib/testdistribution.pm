# Copyright (C) 2017 SUSE LLC
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

package testdistribution;
use strict;
use base 'distribution';

sub init {
    my ($self) = @_;

    $self->SUPER::init();
    $self->init_consoles();
}

sub init_consoles {
    my ($self) = @_;

    $self->add_console(
        'brokenvnc',
        'vnc-base',
        {
            hostname => 'novnc.nowhere',
            port     => 5901,
            password => $testapi::password
        });
}

1;
